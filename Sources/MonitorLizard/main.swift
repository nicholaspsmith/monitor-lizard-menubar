import AppKit
import MonitorLizardCore
import StatusItemKit

/// Monitor Lizard — external-display control for the menu bar: DDC brightness
/// and contrast, HiDPI resolution, built-in brightness, and Night Shift with an
/// automatic fix for displays macOS wrongly calls televisions.
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
    private var fixInProgress = false

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
                self?.model.readBuiltInOnly()
                self?.refreshIcon()
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

    private func modelChanged() {
        refreshIcon()
        // Correct any open slider to the value the monitor confirmed.
        for entry in model.entries {
            if let v = entry.brightness { sliderRows[entry.info.id]?[.brightness]?.update(value: Double(v.current)) }
            if let v = entry.contrast { sliderRows[entry.info.id]?[.contrast]?.update(value: Double(v.current)) }
        }
    }

    // MARK: - Menu

    private func buildMenu(_ menu: NSMenu) {
        // StatusItemController.menuNeedsUpdate already clears the menu before
        // calling onBuildMenu.
        sliderRows = [:]
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
        let login = actionItem("Start at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(appearanceMenu.menuItem())
        menu.addItem(.separator())
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

    @objc private func toggleLogin() { LoginItem.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = App()
app.delegate = delegate
app.run()
