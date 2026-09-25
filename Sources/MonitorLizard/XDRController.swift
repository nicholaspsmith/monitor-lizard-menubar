// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import IOKit.ps
import MetalKit
import MonitorLizardCore

/// XDR brightness for the built-in panel, the way BrightIntosh, Lunar and
/// BetterDisplay do it: a full-screen EDR overlay puts the panel into HDR
/// mode, then a transfer table maps SDR white up into the headroom.
///
/// A gamma table is exactly what BetterDisplay's wake colour-scramble bug
/// left behind, so the lifecycle is the feature:
/// - off at every launch; the on state is never persisted
/// - the table is cleared before sleep, before display sleep, on quit, and at
///   the start of every display reconfiguration (lid close, the panel leaving
///   the display list); it comes back only once reconfiguration has been
///   quiet for `settleDelay`
/// - unplugging switches it off (optional, on by default)
/// - built-in displays only; external displays are never touched
/// - after every clear the table is read back and checked for leftover boost
///
/// CoreGraphics also restores every transfer table when the process exits,
/// so a crash cannot strand the boost either.
final class XDRController {
    static let offOnBatteryKey = "xdrOffOnBattery"
    private static let settleDelay: TimeInterval = 2

    private(set) var isEnabled = false
    /// 0…1 across the panel's usable headroom. In memory only, like `isEnabled`.
    var boost: Float = 1 {
        didSet { update() }
    }
    var offOnBattery: Bool {
        didSet {
            UserDefaults.standard.set(offOnBattery, forKey: Self.offOnBatteryKey)
            switchOffIfOnBattery()
            update()
        }
    }
    /// The toggle can't be turned on while unplugged with "Off on Battery" set.
    var isBlockedByBattery: Bool { onBattery && offOnBattery }

    private var onBattery = false
    private var systemAsleep = false
    private var screensAsleep = false
    private var settling = false
    private var settleWork: DispatchWorkItem?
    private var overlays: [CGDirectDisplayID: NSWindow] = [:]
    private var boosted: Set<CGDirectDisplayID> = []
    private var powerSource: CFRunLoopSource?

    init() {
        // Safe by default: an absent key reads as "switch off on battery".
        offOnBattery = UserDefaults.standard.object(forKey: Self.offOnBatteryKey) as? Bool ?? true
    }

    func start() {
        onBattery = Self.isOnBattery()
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            guard let userInfo else { return }
            let controller = Unmanaged<XDRController>.fromOpaque(userInfo).takeUnretainedValue()
            controller.reconfigured(beginning: flags.contains(.beginConfigurationFlag))
        }, Unmanaged.passUnretained(self).toOpaque())

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemAsleep = true
            self?.update()
        }
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.update()
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.systemAsleep = false
            self?.settle()
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.settle()
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<XDRController>.fromOpaque(context).takeUnretainedValue().powerChanged()
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    /// On quit: the table goes before the app does.
    func stop() {
        isEnabled = false
        update()
    }

    func setEnabled(_ on: Bool) {
        isEnabled = on && !isBlockedByBattery
        Log.xdr.info("XDR brightness \(self.isEnabled ? "on" : "off")")
        update()
    }

    /// Whether the display is a built-in panel with EDR headroom to boost into.
    func isSupported(_ id: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(id) != 0, let screen = Self.screen(for: id) else { return false }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
    }

    // MARK: - Lifecycle

    private func reconfigured(beginning: Bool) {
        if beginning {
            // Clear before the display list changes under the table.
            settleWork?.cancel()
            settling = true
            update()
        } else {
            settle()
        }
    }

    /// Hold the boost off until wake/reconfiguration has been quiet for a while.
    private func settle() {
        settleWork?.cancel()
        settling = true
        update()
        let work = DispatchWorkItem { [weak self] in
            self?.settling = false
            self?.update()
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    private func powerChanged() {
        let now = Self.isOnBattery()
        guard now != onBattery else { return }
        onBattery = now
        switchOffIfOnBattery()
        update()
    }

    private func switchOffIfOnBattery() {
        guard XDRPolicy.shouldSwitchOff(enabled: isEnabled, onBattery: onBattery, offOnBattery: offOnBattery) else { return }
        isEnabled = false
        Log.xdr.info("XDR brightness switched off: on battery")
    }

    private func update() {
        if XDRPolicy.shouldBoost(enabled: isEnabled, asleep: systemAsleep || screensAsleep, settling: settling,
                                 onBattery: onBattery, offOnBattery: offOnBattery) {
            apply()
        } else {
            clear()
        }
    }

    // MARK: - Overlay and table

    private func apply() {
        let panels = Self.builtInDisplays()
        // A panel that has left the list takes its overlay with it.
        for (id, window) in overlays where !panels.contains(id) {
            window.orderOut(nil)
            overlays[id] = nil
            boosted.remove(id)
        }
        for id in panels {
            guard let screen = Self.screen(for: id) else { continue }
            let headroom = Float(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
            guard headroom > 1 else { continue }
            guard let window = overlays[id] ?? Self.makeOverlay(on: screen) else {
                // Without the overlay there is no HDR mode to boost into; a
                // table alone would only clip highlights.
                Log.xdr.error("display \(id): couldn't create the EDR overlay")
                continue
            }
            overlays[id] = window
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            window.contentView?.needsDisplay = true

            let table = XDRGamma.table(factor: XDRGamma.factor(boost: boost, headroom: headroom))
            let rc = CGSetDisplayTransferByTable(id, UInt32(table.count), table, table, table)
            if rc == .success {
                boosted.insert(id)
            } else {
                Log.xdr.error("display \(id): transfer table write failed rc=\(rc.rawValue)")
            }
        }
    }

    private func clear() {
        let ids = boosted
        boosted = []
        if !ids.isEmpty {
            // Table first, overlay second: the other way round would briefly
            // show a >1 table with no HDR mode behind it.
            CGDisplayRestoreColorSyncSettings()
            verifyCleared(ids)
        }
        for window in overlays.values { window.orderOut(nil) }
        overlays = [:]
    }

    /// The colour guard's ramp check: whatever is on the panel now must carry
    /// no boost. A display that has already left the list can't be read, and
    /// needs no check.
    private func verifyCleared(_ ids: Set<CGDirectDisplayID>) {
        for id in ids {
            var red = [CGGammaValue](repeating: 0, count: XDRGamma.tableSize)
            var green = red, blue = red
            var count: UInt32 = 0
            guard CGGetDisplayTransferByTable(id, UInt32(XDRGamma.tableSize), &red, &green, &blue, &count) == .success,
                  count > 0 else { continue }
            let n = Int(count)
            let channels = [red, green, blue].map { Array($0.prefix(n)) }
            if channels.contains(where: { XDRGamma.carriesBoost($0) }) {
                Log.xdr.fault("display \(id): boost still present after clear; restoring again")
                CGDisplayRestoreColorSyncSettings()
            } else if !channels.allSatisfy({ XDRGamma.isPlainRamp($0) }) {
                Log.xdr.error("display \(id): transfer table is not a plain ramp after clear")
            }
        }
    }

    private static func makeOverlay(on screen: NSScreen) -> NSWindow? {
        guard let view = EDROverlayView(size: screen.frame.size) else { return nil }
        let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = view
        return window
    }

    // MARK: - System queries

    private static func builtInDisplays() -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &count)
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}

/// A transparent full-screen Metal layer that asks for EDR content, which is
/// what switches the panel into HDR mode. It multiplies what is beneath it by
/// 1.0, so it changes nothing on screen by itself; the transfer table does
/// the brightening. Drawn once per frame change, never on a display link.
final class EDROverlayView: MTKView, MTKViewDelegate {
    private let queue: MTLCommandQueue

    init?(size: NSSize) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        super.init(frame: NSRect(origin: .zero, size: size), device: device)
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        clearColor = MTLClearColorMake(1, 1, 1, 1)
        isPaused = true
        enableSetNeedsDisplay = true
        delegate = self
        wantsLayer = true
        layer?.isOpaque = false
        layer?.compositingFilter = "multiply"
        (layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
