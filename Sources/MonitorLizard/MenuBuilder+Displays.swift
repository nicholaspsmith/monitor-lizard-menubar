// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

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

        switch entry.brightnessSource {
        case .system where entry.info.isBuiltIn:
            addBuiltInBrightnessRow(entry, to: menu)
        case .system:
            // The built-in panel, or an external display macOS dims itself
            // (the keyboard keys work on it even when DDC doesn't).
            let row = NSMenuItem()
            let view = SliderRow(title: "Brightness", symbol: "sun.max", value: entry.systemBrightness.map { Double($0) * 100 }, maximum: 100,
                                 format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setSystemBrightness(entry.info.id, Float(v / 100))
                self?.refreshIcon()
            }
            row.view = view
            systemBrightnessRows[entry.info.id] = view
            menu.addItem(row)
        case .ddc:
            let b = NSMenuItem()
            let brightnessView = SliderRow(title: "Brightness", symbol: "sun.max",
                               value: entry.brightness.map { Double($0.current) }, maximum: Double(entry.brightness?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setBrightness(entry.info.id, UInt16(v.rounded()))
            }
            b.view = brightnessView
            sliderRows[entry.info.id, default: [:]][.brightness] = brightnessView
            menu.addItem(b)
        case .none:
            break
        }
        if entry.info.isBuiltIn {
            addXDRRows(entry, to: menu)
            return
        }

        if entry.isExternalControllable {
            let c = NSMenuItem()
            let contrastView = SliderRow(title: "Contrast", symbol: "circle.lefthalf.filled",
                               value: entry.contrast.map { Double($0.current) }, maximum: Double(entry.contrast?.maximum ?? 100),
                               format: { "\(Int($0.rounded()))" }) { [weak self] v in
                self?.model.setContrast(entry.info.id, UInt16(v.rounded()))
            }
            c.view = contrastView
            sliderRows[entry.info.id, default: [:]][.contrast] = contrastView
            menu.addItem(c)
        } else if entry.brightnessSource == .none {
            let none = NSMenuItem(title: "No DDC control", action: nil, keyEquivalent: "")
            none.isEnabled = false
            none.indentationLevel = 1
            menu.addItem(none)
        }

        let res = NSMenuItem()
        res.view = ResolutionRow(plan: entry.plan) { [weak self] spec in
            guard let self else { return .failure }
            let rc = self.model.apply(spec, to: entry.info.id)
            if rc != .success { Log.modes.error("apply failed rc=\(rc.rawValue)") }
            return rc
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

    /// The built-in panel's one Brightness slider: Dim along the bottom
    /// fifth, macOS's range in the middle, and the XDR boost along the top
    /// fifth while XDR Brightness is on (`BuiltInSlider`).
    private func addBuiltInBrightnessRow(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        let xdrOn = xdr.isEnabled
        let row = NSMenuItem()
        let position = builtInLevel().map { BuiltInSlider.position($0, xdr: xdrOn) * 100 }
        let view = SliderRow(title: "Brightness", symbol: "sun.max", value: entry.systemBrightness == nil ? nil : position, maximum: 100,
                             format: { BuiltInSlider.label(BuiltInSlider.level(at: $0 / 100, xdr: xdrOn)) }) { [weak self] v in
            self?.setBuiltIn(position: v / 100)
        }
        view.toolTip = xdrOn
            ? "The bottom of the slider dims past the lowest brightness; the top brightens past full using the panel's HDR headroom."
            : "The bottom of the slider dims past the lowest brightness. Turn on XDR Brightness to brighten past full."
        row.view = view
        builtInRow = view
        menu.addItem(row)
    }

    /// XDR brightness: only on a built-in panel with EDR headroom.
    private func addXDRRows(_ entry: DisplayModel.Entry, to menu: NSMenu) {
        guard xdr.isSupported(entry.info.id) else { return }
        let toggle: NSMenuItem
        if xdr.isBlockedByBattery {
            toggle = NSMenuItem(title: "XDR Brightness · off on battery", action: nil, keyEquivalent: "")
            toggle.isEnabled = false
        } else {
            toggle = NSMenuItem(title: "XDR Brightness", action: #selector(toggleXDR), keyEquivalent: "")
            toggle.target = self
            toggle.state = xdr.isEnabled ? .on : .off
        }
        toggle.toolTip = "Extends the Brightness slider (and the brightness-up key) past full, into the panel's HDR headroom. Off again at every launch."
        menu.addItem(toggle)

        let battery = NSMenuItem(title: "Off on Battery", action: #selector(toggleXDROffOnBattery), keyEquivalent: "")
        battery.target = self
        battery.state = xdr.offOnBattery ? .on : .off
        battery.indentationLevel = 1
        menu.addItem(battery)

        let note = NSMenuItem(title: "HDR video may clip · more battery and heat", action: nil, keyEquivalent: "")
        note.isEnabled = false
        note.indentationLevel = 1
        menu.addItem(note)
    }

    @objc func toggleXDR() { xdr.setEnabled(!xdr.isEnabled) }
    @objc func toggleXDROffOnBattery() { xdr.offOnBattery.toggle() }

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
