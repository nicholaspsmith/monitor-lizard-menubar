import AppKit
import MonitorLizardCore

/// A stepped slider over the HiDPI "looks like" sizes. Snaps to a stop while
/// dragging and applies only on release — a mode switch blanks the display for
/// a second, so it must not fire per tick.
final class ResolutionRow: NSView {
    private let slider: NSSlider
    private let label = NSTextField(labelWithString: "")
    private let plan: ModePlan
    private let onApply: (ModeSpec) -> CGError
    private var lastApplied: Int?

    init(plan: ModePlan, onApply: @escaping (ModeSpec) -> CGError) {
        self.plan = plan
        self.onApply = onApply
        let stops = max(plan.hiDPI.count - 1, 0)
        slider = NSSlider(value: 0, minValue: 0, maxValue: Double(stops), target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: SliderRow.rowWidth, height: 28))

        let title = NSTextField(labelWithString: "Resolution")
        title.font = .menuFont(ofSize: 0)
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        let icon = NSImageView(image: NSImage(systemSymbolName: "rectangle.expand.diagonal", accessibilityDescription: nil)
                               ?? NSImage(systemSymbolName: "rectangle", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        slider.numberOfTickMarks = plan.hiDPI.count
        slider.allowsTickMarkValuesOnly = true
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(slid(_:))
        slider.isEnabled = plan.hiDPI.count > 1
        if let current = plan.current, let i = plan.stopIndex(of: current) {
            slider.doubleValue = Double(i); lastApplied = i; label.stringValue = plan.hiDPI[i].label
        } else if let current = plan.current {
            // Not a HiDPI stop (native or a stale/off-plan mode): show the
            // real label, park the knob at the nearest stop by width, and
            // leave `lastApplied` nil so picking that stop still applies it.
            label.stringValue = current.label
            if let nearest = Self.nearestStopIndex(to: current, in: plan.hiDPI) {
                slider.doubleValue = Double(nearest)
            }
        }

        for v in [title, icon, slider, label] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.widthAnchor.constraint(equalToConstant: 72),
            icon.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            slider.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.widthAnchor.constraint(equalToConstant: 68),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func slid(_ sender: NSSlider) {
        let i = Int(sender.doubleValue.rounded())
        guard plan.hiDPI.indices.contains(i) else { return }
        // Live preview while dragging: track the label to the knob even
        // though the mode switch itself only fires on release (below).
        label.stringValue = plan.hiDPI[i].label
        // NSSlider with isContinuous fires on every tick of a mouse drag, so
        // gate on "not an in-progress drag" rather than only `.leftMouseUp` —
        // that also lets a mouse release, a keyboard nudge (arrow keys) and an
        // accessibility value set apply, none of which are `.leftMouseUp`.
        let type = NSApp.currentEvent?.type
        let dragging = type == .leftMouseDragged || type == .leftMouseDown
        guard !dragging, i != lastApplied else { return }
        let result = onApply(plan.hiDPI[i])
        if result == .success {
            // The label already shows plan.hiDPI[i].label from the preview
            // update above; just record the confirmed stop.
            lastApplied = i
        } else {
            // Restore the knob and label to the previous stop: the last
            // confirmed apply, or the plan's current stop if none.
            if let previous = lastApplied {
                slider.doubleValue = Double(previous)
                label.stringValue = plan.hiDPI[previous].label
            } else if let current = plan.current {
                label.stringValue = current.label
                if let nearest = Self.nearestStopIndex(to: current, in: plan.hiDPI) {
                    slider.doubleValue = Double(nearest)
                }
            }
        }
    }

    /// Position of the HiDPI stop closest to `mode` by width — used to park
    /// the knob when `mode` isn't itself a stop (native or off-plan).
    private static func nearestStopIndex(to mode: ModeSpec, in hiDPI: [ModeSpec]) -> Int? {
        hiDPI.indices.min { abs(hiDPI[$0].width - mode.width) < abs(hiDPI[$1].width - mode.width) }
    }
}

/// Wraps `ModeSpec` (a struct) so it can be an `NSMenuItem.representedObject`.
final class ModeBox: NSObject {
    let mode: ModeSpec
    init(_ mode: ModeSpec) { self.mode = mode }
}

/// The picker submenu: every same-aspect mode, HiDPI first, the current one checked.
enum ResolutionMenu {
    static func make(plan: ModePlan, displayID: CGDirectDisplayID, target: AnyObject, action: Selector) -> NSMenu {
        let menu = NSMenu()
        func section(_ title: String, _ modes: [ModeSpec]) {
            guard !modes.isEmpty else { return }
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: ""); header.isEnabled = false
            menu.addItem(header)
            for mode in modes {
                var text = mode.label
                if let native = plan.native, mode.width == native.width, mode.height == native.height, !mode.isHiDPI {
                    text += " (native)"
                }
                let item = NSMenuItem(title: text, action: action, keyEquivalent: "")
                item.target = target
                item.tag = Int(displayID)
                item.representedObject = ModeBox(mode)
                if let current = plan.current, current.width == mode.width, current.height == mode.height, current.isHiDPI == mode.isHiDPI {
                    item.state = .on
                }
                menu.addItem(item)
            }
        }
        section("HiDPI", plan.hiDPI)
        if !plan.hiDPI.isEmpty && !plan.lowRes.isEmpty { menu.addItem(.separator()) }
        section("Low resolution", plan.lowRes)
        return menu
    }
}
