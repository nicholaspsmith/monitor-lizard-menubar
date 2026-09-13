import AppKit
import MonitorLizardCore

/// The per-display blocks of the menu. Kept out of `App` so main.swift stays
/// the wiring and this stays the layout.
extension App {
    func addDisplayBlock(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        let header = NSMenuItem(title: entry.info.name, action: nil, keyEquivalent: "")
        header.isEnabled = false
        if entry.info.isHDMI {
            header.attributedTitle = headerTitle(entry.info.name, tag: "HDMI")
        }
        menu.addItem(header)

        if entry.info.isBuiltIn {
            let row = NSMenuItem()
            row.view = SliderRow(title: "Brightness", symbol: "sun.max", value: entry.builtInBrightness.map { Double($0) * 100 }, maximum: 100,
                                 format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setBuiltInBrightness(entry.info.id, Float(v / 100))
                self?.refreshIcon()
            }
            menu.addItem(row)
            return
        }

        if entry.isExternalControllable {
            let b = NSMenuItem()
            b.view = SliderRow(title: "Brightness", symbol: "sun.max",
                               value: entry.brightness.map { Double($0.current) }, maximum: Double(entry.brightness?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setBrightness(entry.info.id, UInt16(v.rounded()))
            }
            sliderRows[entry.info.id, default: [:]][.brightness] = b.view as? SliderRow
            menu.addItem(b)
            let c = NSMenuItem()
            c.view = SliderRow(title: "Contrast", symbol: "circle.lefthalf.filled",
                               value: entry.contrast.map { Double($0.current) }, maximum: Double(entry.contrast?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setContrast(entry.info.id, UInt16(v.rounded()))
            }
            sliderRows[entry.info.id, default: [:]][.contrast] = c.view as? SliderRow
            menu.addItem(c)
        } else {
            let none = NSMenuItem(title: "No DDC control", action: nil, keyEquivalent: "")
            none.isEnabled = false
            none.indentationLevel = 1
            menu.addItem(none)
        }

        let res = NSMenuItem()
        res.view = ResolutionRow(plan: entry.plan) { [weak self] spec in
            let rc = self?.model.apply(spec, to: entry.info.id)
            if rc != .success { Log.modes.error("apply failed rc=\(rc?.rawValue ?? -1)") }
        }
        res.submenu = ResolutionMenu.make(plan: entry.plan, displayID: entry.info.id, target: self, action: #selector(pickMode(_:)))
        menu.addItem(res)

        let ns: NSMenuItem
        switch entry.tvState {
        case .ok:
            ns = NSMenuItem(title: "✓ Night Shift works on this display", action: nil, keyEquivalent: "")
            ns.isEnabled = false
        case .fixedPendingReconnect:
            ns = NSMenuItem(title: "⏳ Marked as a monitor — reconnect to enable Night Shift", action: nil, keyEquivalent: "")
            ns.isEnabled = false
        case .blocked, .skipped:
            ns = NSMenuItem(title: "✗ TV mode · Night Shift blocked · Retry", action: #selector(retryTVFix(_:)), keyEquivalent: "")
            ns.target = self
            ns.representedObject = NSNumber(value: entry.info.id)
        }
        ns.indentationLevel = 1
        menu.addItem(ns)
    }

    private func headerTitle(_ name: String, tag: String) -> NSAttributedString {
        let s = NSMutableAttributedString(string: name, attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor])
        s.append(NSAttributedString(string: "   \(tag)", attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.tertiaryLabelColor]))
        return s
    }

    @objc func pickMode(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ModeBox else { return }
        _ = model.apply(box.mode, to: CGDirectDisplayID(sender.tag))
    }

    @objc func retryTVFix(_ sender: NSMenuItem) {
        guard let id = (sender.representedObject as? NSNumber)?.uint32Value, let entry = model.entry(id) else { return }
        model.tvRoles.clearSkipped(entry.info)
        fixTVRole(entry.info)
    }
}
