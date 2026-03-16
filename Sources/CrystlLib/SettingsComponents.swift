// SettingsComponents.swift — Shared UI components for the settings panel
//
// Contains:
//   - GlassToggle: iOS-style toggle switch with glass aesthetics
//   - VerticallyCenteredTextFieldCell: text field cell with vertical centering

import Cocoa

// ── Glass Toggle ──

/// iOS-style toggle switch rendered with glass aesthetics.
/// Fires target/action when toggled. Uses `identifier` for identification.
class GlassToggle: NSView {
    var isOn: Bool { didSet { updateAppearance(animated: true) } }
    weak var target: AnyObject?
    var action: Selector?

    /// Label text displayed to the right of the toggle.
    var title: String {
        didSet { label.stringValue = title }
    }

    private let track = CALayer()
    private let knob = CALayer()
    private let label: NSTextField

    private let trackW: CGFloat = 36
    private let trackH: CGFloat = 20
    private let knobSize: CGFloat = 16
    private let knobPad: CGFloat = 2

    init(title: String, isOn: Bool, frame: NSRect) {
        self.isOn = isOn
        self.title = title
        self.label = NSTextField(labelWithString: title)
        super.init(frame: frame)
        wantsLayer = true

        // Track
        track.frame = NSRect(x: 0, y: (frame.height - trackH) / 2, width: trackW, height: trackH)
        track.cornerRadius = trackH / 2
        track.borderWidth = 1
        track.borderColor = NSColor(white: 1.0, alpha: 0.2).cgColor
        layer?.addSublayer(track)

        // Knob
        let knobY = track.frame.origin.y + knobPad
        knob.frame = NSRect(x: knobPad, y: knobY, width: knobSize, height: knobSize)
        knob.cornerRadius = knobSize / 2
        knob.backgroundColor = NSColor.white.cgColor
        knob.shadowColor = NSColor.black.cgColor
        knob.shadowOffset = CGSize(width: 0, height: -1)
        knob.shadowRadius = 2
        knob.shadowOpacity = 0.3
        layer?.addSublayer(knob)

        // Label
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: trackW + 10, y: (frame.height - 16) / 2, width: frame.width - trackW - 10, height: 16)
        addSubview(label)

        updateAppearance(animated: false)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func updateAppearance(animated: Bool) {
        let onX = trackW - knobSize - knobPad
        let offX = knobPad
        let targetX = isOn ? onX : offX
        let trackColor = isOn
            ? NSColor(red: 0.55, green: 0.72, blue: 0.85, alpha: 0.6).cgColor
            : NSColor(white: 1.0, alpha: 0.12).cgColor

        if animated {
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.2)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }

        knob.frame.origin.x = targetX
        track.backgroundColor = trackColor

        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        if let t = target, let a = action {
            NSApp.sendAction(a, to: t, from: self)
        }
    }

    /// Compatibility with NSButton state for the existing handler.
    var state: NSControl.StateValue {
        isOn ? .on : .off
    }
}

// ── Vertically Centered Text Field Cell ──

class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    private let hPad: CGFloat = 8

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        let inset = rect.insetBy(dx: hPad, dy: 0)
        var r = super.titleRect(forBounds: inset)
        let stringHeight = attributedStringValue.boundingRect(
            with: NSSize(width: r.width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin
        ).height
        let offset = (r.height - stringHeight) / 2
        r.origin.y += offset
        r.size.height = stringHeight
        return r
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: titleRect(forBounds: cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: rect.insetBy(dx: hPad, dy: 0), in: controlView,
                   editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int) {
        super.select(withFrame: rect.insetBy(dx: hPad, dy: 0), in: controlView,
                     editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
    }
}
