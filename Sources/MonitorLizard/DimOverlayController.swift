// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import MonitorLizardCore

/// Dims the built-in panel below macOS's lowest lit brightness with a
/// click-through black window over it (`PanelDim` has the levels and why not
/// a gamma table).
///
/// The window sits above everything, menus and the menu bar included, takes
/// no clicks, joins every Space and full-screen app, and is left out of
/// screenshots and recordings. The pointer is drawn above it by the system,
/// so it stays at full brightness. Unlike a gamma table an overlay can't be
/// left behind: it goes with the process. Off at every launch.
final class DimOverlayController {
    /// 0 (off) … 1 (deepest). In memory only.
    var level: Float = 0 {
        didSet {
            level = max(0, min(1, level))
            guard level != oldValue else { return }
            Log.xdr.info("dim \(self.level) (lets through \(PanelDim.factor(level: self.level)))")
            update()
        }
    }

    var isAvailable: Bool { !Self.builtInScreens().isEmpty }

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var observer: NSObjectProtocol?

    func start() {
        // Displays come and go, and the panel's frame changes with its
        // resolution; refit on every change.
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.update() }
    }

    func stop() {
        level = 0
        update()
    }

    private func update() {
        guard level > 0 else {
            for w in windows.values { w.orderOut(nil) }
            windows = [:]
            return
        }
        let screens = Self.builtInScreens()
        for (id, w) in windows where screens[id] == nil {
            w.orderOut(nil)
            windows[id] = nil
        }
        let alpha = CGFloat(1 - PanelDim.factor(level: level))
        for (id, screen) in screens {
            let w = windows[id] ?? Self.makeWindow()
            windows[id] = w
            w.setFrame(screen.frame, display: false)
            w.alphaValue = alpha
            w.orderFrontRegardless()
        }
    }

    private static func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        w.isReleasedWhenClosed = false
        w.isOpaque = false
        w.hasShadow = false
        w.backgroundColor = .black
        w.ignoresMouseEvents = true
        w.canHide = false
        w.hidesOnDeactivate = false
        w.animationBehavior = .none
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        w.sharingType = .none
        return w
    }

    private static func builtInScreens() -> [CGDirectDisplayID: NSScreen] {
        var out: [CGDirectDisplayID: NSScreen] = [:]
        for screen in NSScreen.screens {
            guard let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = n.uint32Value
            if CGDisplayIsBuiltin(id) != 0 { out[id] = screen }
        }
        return out
    }
}
