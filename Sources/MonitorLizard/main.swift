// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import MonitorLizardCore
import StatusItemKit

/// Monitor Lizard — external-display control for the menu bar: DDC brightness
/// and contrast (DisplayServices brightness where macOS drives the display
/// itself), HiDPI resolution, built-in brightness, and Night Shift with an
/// automatic fix for displays macOS wrongly calls televisions, and XDR
/// brightness and dimming below macOS's minimum for the built-in panel.
final class App: NSObject, NSApplicationDelegate {
    private var status: StatusItemController!
    private var yieldClient: YieldClient!
    private let notifier = Notifier()
    let model: DisplayModel
    private let appearance = MeterAppearance(defaultStyle: .character)
    private var appearanceMenu: AppearanceMenu!
    private var tongueUntil = Date.distantPast
    /// Open-menu slider rows, so a confirmed read can correct them in place.
    var sliderRows: [CGDirectDisplayID: [VCPCode: SliderRow]] = [:]
    /// Same, for DisplayServices brightness rows: the keyboard keys and
    /// Control Center move these while the menu is open.
    var systemBrightnessRows: [CGDirectDisplayID: SliderRow] = [:]
    private var fixInProgress = false
    private var brightnessKeys: BrightnessKeyController!
    /// The built-in panel's transfer table: XDR brightness or dim. Both off at
    /// every launch.
    let panelGamma = PanelGammaController()
    /// The open menu's Dim row, so the keys move it.
    weak var dimRow: SliderRow?
    /// The built-in panel's last macOS brightness, to notice it being raised.
    private var lastBuiltInBrightness: Float?

    override init() {
        model = DisplayModel(brightness: DisplayServicesBrightness(), nightShift: CoreBrightnessNightShift(), tvRoles: TVRoleTracker())
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notifier.requestAuthorization()
        appearanceMenu = AppearanceMenu(appearance: appearance, styles: [.character] + MeterStyle.proportional, characterTitle: "Lizard") { [weak self] in
            self?.refreshIcon()
        }
        status = StatusItemController(
            pollInterval: 60,
            onPoll: { [weak self] in
                // Brightness and Night Shift both push change notifications; this
                // tick is only a safety net if one is missed. DDC is never polled.
                self?.model.readSystemBrightness()
                self?.refreshIcon()
                // Optional-safe: the first poll fires from status.start().
                self?.brightnessKeys?.reassert()
            },
            onBuildMenu: { [weak self] menu in self?.buildMenu(menu) }
        )
        status.onMenuDidClose = { [weak self] in self?.refreshIcon() }
        model.onChange = { [weak self] in self?.modelChanged() }
        model.onWrite = { [weak self] in self?.flickTongue() }
        // Dispatched async so the admin dialog in `fixTVRole` never runs from
        // inside `DisplayModel.refresh()`'s own enumeration loop.
        model.onNeedsTVFix = { [weak self] info in DispatchQueue.main.async { self?.fixTVRole(info) } }
        model.start()
        status.start()
        yieldClient = YieldClient(item: status)
        yieldClient.start()

        brightnessKeys = BrightnessKeyController(
            route: { [weak self] direction in
                guard let self else { return .passThrough }
                let builtIn = self.model.entries.first { $0.info.isBuiltIn }
                return BrightnessKeys.route(
                    among: self.model.entries.map {
                        BrightnessKeys.Display(id: $0.info.id, isMain: $0.info.isMain,
                                               isBuiltIn: $0.info.isBuiltIn, source: $0.brightnessSource)
                    },
                    direction: direction,
                    builtInBrightness: builtIn.flatMap { self.model.liveSystemBrightness($0.info.id) },
                    dimLevel: self.panelGamma.dimLevel,
                    dimAvailable: self.panelGamma.isDimAvailable
                )
            },
            stepExternal: { [weak self] id, direction in self?.model.stepBrightness(id, direction) },
            stepDim: { [weak self] direction in self?.stepDim(direction) }
        )
        brightnessKeys.start()
        panelGamma.start()
        lastBuiltInBrightness = model.entries.first { $0.info.isBuiltIn }?.systemBrightness
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Neither the boost's nor the dim's transfer table may outlive the app.
        panelGamma.stop()
    }

    // MARK: - Icon

    func refreshIcon() {
        let fraction = model.mainBrightnessFraction
        let icon: NSImage
        if appearance.style == .character {
            let ns = model.nightShift?.status().enabled ?? false
            icon = CharacterIcon.monitorLizard(brightness: fraction, nightShift: ns, tongue: Date() < tongueUntil)
        } else {
            icon = appearance.image(fraction: fraction)
        }
        status.setIcon(icon)
    }

    private func flickTongue() {
        tongueUntil = Date().addingTimeInterval(0.6)
        refreshIcon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in self?.refreshIcon() }
    }

    /// A brightness key press past macOS's minimum, or back.
    private func stepDim(_ direction: BrightnessKeys.Direction) {
        panelGamma.dimLevel = PanelDim.step(panelGamma.dimLevel, direction)
        dimRow?.update(value: Double(panelGamma.dimLevel) * 100)
    }

    private func modelChanged() {
        // Raising macOS brightness while dimmed (Control Center, auto-brightness
        // in a brighter room) means someone wants light: drop the dim.
        let builtIn = model.entries.first { $0.info.isBuiltIn }?.systemBrightness
        if panelGamma.dimLevel > 0, PanelDim.cancels(previous: lastBuiltInBrightness, current: builtIn) {
            Log.xdr.info("dim cancelled: brightness raised to \(builtIn ?? -1)")
            panelGamma.dimLevel = 0
            dimRow?.update(value: 0)
        }
        lastBuiltInBrightness = builtIn
        refreshIcon()
        // Correct any open slider to the value the monitor confirmed, or that
        // DisplayServices reports after a change made elsewhere.
        for entry in model.entries {
            if let v = entry.brightness { sliderRows[entry.info.id]?[.brightness]?.update(value: Double(v.current)) }
            if let v = entry.contrast { sliderRows[entry.info.id]?[.contrast]?.update(value: Double(v.current)) }
            if let b = entry.systemBrightness { systemBrightnessRows[entry.info.id]?.update(value: Double(b) * 100) }
        }
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        // StatusItemController.menuNeedsUpdate already clears the menu before
        // calling onBuildMenu.
        sliderRows = [:]
        systemBrightnessRows = [:]
        model.readValues()

        if model.entries.isEmpty {
            menu.addItem(disabledItem("No displays"))
        }
        for (i, entry) in model.entries.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            addDisplayBlock(entry, to: menu)
        }

        menu.addItem(.separator())
        if let ns = model.nightShift, ns.isAvailable {
            let s = ns.status()
            let toggle = actionItem("Night Shift", #selector(toggleNightShift))
            toggle.state = s.enabled ? .on : .off
            menu.addItem(toggle)
            let warmth = NSMenuItem()
            warmth.view = SliderRow(title: "Warmth", symbol: "thermometer.sun", value: Double(s.strength) * 100, maximum: 100,
                                    format: { "\(Int($0.rounded()))" }) { v in
                _ = ns.setStrength(Float(v / 100))
            }
            menu.addItem(warmth)
        } else {
            menu.addItem(disabledItem("Night Shift unavailable on this macOS"))
        }

        menu.addItem(.separator())
        // The keyboard's brightness keys step the main monitor over DDC.
        let keys = actionItem("Brightness Keys", #selector(toggleBrightnessKeys))
        keys.state = brightnessKeys.isEnabled ? .on : .off
        keys.toolTip = "The keyboard's brightness keys change the main monitor's brightness"
        menu.addItem(keys)
        if brightnessKeys.isWaitingForTrust {
            menu.addItem(actionItem("⚠ Grant Accessibility…", #selector(grantTrust)))
        }

        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(appearanceMenu.menuItem())
        menu.addItem(.separator())
        menu.addItem(AppVersion.menuItem())
        menu.addItem(actionItem("Quit Monitor Lizard", #selector(quit), key: "q"))
    }

    func disabledItem(_ title: String) -> NSMenuItem {
        NSMenuItem(title: title, action: nil, keyEquivalent: "")
    }

    func actionItem(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: - TV-role fix

    func fixTVRole(_ info: DisplayInfo) {
        guard !fixInProgress, model.tvRoles.needsFix(info) else { return }
        // Held through the trailing async refresh (reset there, not via
        // `defer`), so a second blocked display's queued fix waits until this
        // one has fully settled rather than firing while the admin dialog for
        // this one is still up — it gets picked up by that refresh instead.
        fixInProgress = true
        switch OverrideWriter.write(for: info) {
        case .written:
            notifier.post(title: "Marked \(info.name) as a monitor",
                          body: "Reconnect it (or reboot) to enable Night Shift.")
        case .cancelled:
            model.tvRoles.markSkipped(info)
        case .failed(let message):
            notifier.post(title: "Couldn't mark \(info.name) as a monitor", body: message)
            model.tvRoles.markSkipped(info)
        }
        DispatchQueue.main.async { [weak self] in
            self?.model.refresh()
            self?.fixInProgress = false
        }
    }

    // MARK: - Selectors

    @objc private func toggleNightShift() {
        guard let ns = model.nightShift else { return }
        _ = ns.setEnabled(!ns.status().enabled)
        refreshIcon()
    }

    @objc private func toggleBrightnessKeys() { brightnessKeys.isEnabled.toggle() }
    @objc private func grantTrust() { brightnessKeys.requestTrust() }
    @objc private func toggleLogin() { LoginItem.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
