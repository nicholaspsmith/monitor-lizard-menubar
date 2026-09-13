import AppKit

/// A labelled slider in an `NSMenuItem.view`: title left, value right, an
/// SF Symbol at each end of the track. Fires `onChange` on every tick; the
/// DDC layer collapses bursts, so no debounce here.
final class SliderRow: NSView {
    static let rowWidth: CGFloat = 260
    private let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "–")
    private let format: (Double) -> String
    private let onChange: (Double) -> Void

    init(title: String, symbol: String, value: Double?, maximum: Double,
         format: @escaping (Double) -> String, onChange: @escaping (Double) -> Void) {
        self.format = format
        self.onChange = onChange
        slider = NSSlider(value: value ?? 0, minValue: 0, maxValue: maximum, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.rowWidth, height: 28))

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .menuFont(ofSize: 0)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor

        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(slid(_:))
        slider.isEnabled = value != nil

        for v in [titleLabel, icon, slider, valueLabel] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalToConstant: 72),
            icon.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 14),
            slider.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 30),
        ])
        if let value { show(value) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(value: Double) {
        guard !slider.isHighlighted else { return }
        slider.doubleValue = value
        slider.isEnabled = true
        show(value)
    }

    private func show(_ value: Double) { valueLabel.stringValue = format(value) }

    @objc private func slid(_ sender: NSSlider) {
        show(sender.doubleValue)
        onChange(sender.doubleValue)
    }
}
