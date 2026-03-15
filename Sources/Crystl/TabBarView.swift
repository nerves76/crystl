// TabBarView.swift — Tab bar and session bar UI
//
// Contains:
//   - TabBarView: Primary tab bar showing project tabs with rename, close, add
//   - SessionBarView: Secondary bar showing numbered sessions within a project

import Cocoa

// ── Hover Label ──

/// A small white text label that appears near the mouse on hover.
/// Attached to a parent view; call `show(text:near:in:)` and `hide()`.
class HoverLabel {
    private let label: NSTextField = {
        let l = NSTextField(labelWithString: "")
        l.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        l.textColor = .white
        l.isHidden = true
        return l
    }()
    private weak var parent: NSView?

    func attach(to view: NSView) {
        parent = view
        view.addSubview(label)
    }

    func show(text: String, near point: NSPoint, in view: NSView) {
        label.stringValue = text
        label.sizeToFit()
        let w = label.fittingSize.width
        let x = min(point.x - w / 2, view.bounds.width - w - 4)
        label.frame = NSRect(x: max(4, x), y: 2, width: w, height: 12)
        label.isHidden = false
    }

    func hide() {
        label.isHidden = true
    }
}

// ── Tab Bar View ──

/// Custom-drawn tab bar showing project directories. Tabs auto-size to fill
/// available width (max 160px each). "+" to add, click to select.
class TabBarView: NSView {
    var projects: [ProjectTab] = []
    var selectedIndex: Int = 0
    var onSelectTab: ((Int) -> Void)?
    var onAddTab: (() -> Void)?
    var onCloseTab: ((Int) -> Void)?
    private let leftInset: CGFloat = 14
    private let hoverLabel = HoverLabel()
    private var hoverTrackingArea: NSTrackingArea?
    private let tabSpacing: CGFloat = 2

    private func computeTabWidth() -> CGFloat {
        let available = bounds.width - leftInset - 20
        return min(160, available / max(CGFloat(projects.count), 1))
    }

    private func tabOriginX(_ index: Int) -> CGFloat {
        return leftInset + CGFloat(index) * (computeTabWidth() + tabSpacing)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Separator line at bottom
        NSColor(white: 1.0, alpha: 0.25).setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: bounds.width, height: 0.5))

        let tabW = computeTabWidth()
        let h: CGFloat = 26
        let y: CGFloat = (bounds.height - h) / 2 + 4

        for (i, project) in projects.enumerated() {
            let x = tabOriginX(i)
            let rect = NSRect(x: x, y: y, width: tabW, height: h)
            let isSelected = (i == selectedIndex)

            if isSelected {
                NSColor(white: 1.0, alpha: 0.12).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }

            // Icon + Title
            var textX = x + 12
            let iconSize: CGFloat = 14

            // Draw project icon if available
            if let iconName = project.iconName,
               let icon = LucideIcons.render(name: iconName, size: iconSize, color: project.color.withAlphaComponent(isSelected ? 0.9 : 0.5)) {
                let iconY = rect.midY - iconSize / 2
                icon.draw(in: NSRect(x: textX, y: iconY, width: iconSize, height: iconSize))
                textX += iconSize + 5
            }

            let title = project.title as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: isSelected ? .medium : .regular),
                .foregroundColor: NSColor.white
            ]
            let sz = title.size(withAttributes: attrs)
            let textW = (x + tabW) - textX - (projects.count > 1 ? 20 : 12)
            let textRect = NSRect(x: textX, y: rect.midY - sz.height / 2, width: textW, height: sz.height)
            title.draw(with: textRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attrs)

            // Close button (only when multiple projects)
            if projects.count > 1 {
                let sym = "\u{2715}" as NSString
                let symAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.white.withAlphaComponent(isSelected ? 0.7 : 0.4)
                ]
                let symSize = sym.size(withAttributes: symAttrs)
                let symX = x + tabW - 12 - symSize.width
                let symY = rect.midY - symSize.height / 2
                sym.draw(at: NSPoint(x: symX, y: symY), withAttributes: symAttrs)
            }
        }

        // "+" button
        let plusX = tabOriginX(projects.count) + 8
        let plusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .ultraLight),
            .foregroundColor: NSColor.white
        ]
        let plusStr = "+" as NSString
        let plusSize = plusStr.size(withAttributes: plusAttrs)
        plusStr.draw(at: NSPoint(x: plusX, y: (bounds.height - plusSize.height) / 2 + 4), withAttributes: plusAttrs)
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let tabW = computeTabWidth()

        // "+" button
        let plusX = tabOriginX(projects.count) + 8
        if loc.x >= plusX - 4 && loc.x <= plusX + 28 {
            onAddTab?()
            return
        }

        for i in 0..<projects.count {
            let x = tabOriginX(i)
            if loc.x >= x && loc.x < x + tabW {
                if projects.count > 1 && loc.x >= x + tabW - 20 {
                    onCloseTab?(i)
                    return
                }
                onSelectTab?(i)
                return
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = hoverTrackingArea { removeTrackingArea(ta) }
        hoverTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil
        )
        addTrackingArea(hoverTrackingArea!)
        hoverLabel.attach(to: self)
    }

    override func mouseMoved(with event: NSEvent) {
        hoverLabel.hide()
    }

    override func mouseExited(with event: NSEvent) {
        hoverLabel.hide()
    }

}

// ── Session Bar View ──

/// Shows numbered sessions within the selected project. Only visible when
/// a project has 2+ sessions. Supports rename on double-click and "+" to add.
class SessionBarView: NSView, NSTextFieldDelegate {
    var sessions: [TerminalSession] = []
    var selectedIndex: Int = 0
    var projectColor: NSColor = .white
    var onSelectSession: ((Int) -> Void)?
    private let hoverLabel = HoverLabel()
    private var hoverTrackingArea: NSTrackingArea?
    var onAddSession: (() -> Void)?
    var onAddIsolatedSession: (() -> Void)?
    var onRenameSession: ((Int, String) -> Void)?
    var onCloseSession: ((Int) -> Void)?
    private let headerInset: CGFloat = 14
    private let leftInset: CGFloat = 85  // after "SHARDS" label
    private let pillSpacing: CGFloat = 4
    private let pillWidth: CGFloat = 64
    private var editField: NSTextField?
    private var editingIndex: Int = -1

    override func draw(_ dirtyRect: NSRect) {
        // "SHARDS" header label — left of the session pills
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.4)
        ]
        let header = "SHARDS" as NSString
        let headerSize = header.size(withAttributes: headerAttrs)
        header.draw(at: NSPoint(x: headerInset,
                                y: (bounds.height - headerSize.height) / 2),
                    withAttributes: headerAttrs)

        let h: CGFloat = 22
        let y: CGFloat = (bounds.height - h) / 2

        for (i, session) in sessions.enumerated() {
            let x = leftInset + CGFloat(i) * (pillWidth + pillSpacing)
            let rect = NSRect(x: x, y: y, width: pillWidth, height: h)
            let isSelected = (i == selectedIndex)

            let gemColor = session.crystalColor

            if isSelected {
                // Crystal color accent underline
                gemColor.withAlphaComponent(0.6).setFill()
                NSBezierPath.fill(NSRect(x: x + 8, y: y, width: pillWidth - 16, height: 2))
            }

            // Session name (skip if editing)
            if i != editingIndex {
                let displayName = (session.isIsolated ? "\u{2387} " : "") + session.name
                let name = displayName as NSString
                let textColor = isSelected ? gemColor : gemColor.withAlphaComponent(0.5)
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: isSelected ? .medium : .regular),
                    .foregroundColor: textColor
                ]
                let sz = name.size(withAttributes: attrs)
                let textRect = NSRect(x: x + 8, y: rect.midY - sz.height / 2, width: pillWidth - 16, height: sz.height)
                name.draw(with: textRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attrs)
            }
        }

        // "+" button
        let plusX = leftInset + CGFloat(sessions.count) * (pillWidth + pillSpacing) + 4
        let plusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .ultraLight),
            .foregroundColor: NSColor.white.withAlphaComponent(0.6)
        ]
        let plusStr = "+" as NSString
        let plusSize = plusStr.size(withAttributes: plusAttrs)
        plusStr.draw(at: NSPoint(x: plusX, y: (bounds.height - plusSize.height) / 2), withAttributes: plusAttrs)

        // Hint — right-aligned, hidden when shards would overlap
        let hint = "\u{2325}+ isolated shard" as NSString
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.2)
        ]
        let hintSize = hint.size(withAttributes: hintAttrs)
        let hintX = bounds.width - hintSize.width - 14
        let contentRight = plusX + plusSize.width + 12
        if hintX > contentRight {
            hint.draw(at: NSPoint(x: hintX, y: (bounds.height - hintSize.height) / 2),
                      withAttributes: hintAttrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)

        // Double-click to rename
        if event.clickCount == 2 {
            for i in 0..<sessions.count {
                let x = leftInset + CGFloat(i) * (pillWidth + pillSpacing)
                if loc.x >= x && loc.x < x + pillWidth {
                    beginEditing(index: i)
                    return
                }
            }
        }

        // "+" button — Option+click for isolated (worktree) session
        let plusX = leftInset + CGFloat(sessions.count) * (pillWidth + pillSpacing) + 4
        if loc.x >= plusX - 4 && loc.x <= plusX + 24 {
            if event.modifierFlags.contains(.option) {
                onAddIsolatedSession?()
            } else {
                onAddSession?()
            }
            return
        }

        // Session selection
        for i in 0..<sessions.count {
            let x = leftInset + CGFloat(i) * (pillWidth + pillSpacing)
            if loc.x >= x && loc.x < x + pillWidth {
                onSelectSession?(i)
                return
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = hoverTrackingArea { removeTrackingArea(ta) }
        hoverTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow],
            owner: self, userInfo: nil
        )
        addTrackingArea(hoverTrackingArea!)
        hoverLabel.attach(to: self)
    }

    override func mouseMoved(with event: NSEvent) {
        hoverLabel.hide()
    }

    override func mouseExited(with event: NSEvent) {
        hoverLabel.hide()
    }

    func beginEditing(index: Int) {
        endEditing()
        editingIndex = index
        let x = leftInset + CGFloat(index) * (pillWidth + pillSpacing)
        let h: CGFloat = 22
        let y: CGFloat = (bounds.height - h) / 2

        let field = NSTextField(frame: NSRect(x: x + 4, y: y + 1, width: pillWidth - 8, height: h - 2))
        field.stringValue = sessions[index].name
        field.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium)
        field.textColor = .white
        field.backgroundColor = .clear
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.delegate = self
        field.target = self
        field.action = #selector(editFieldCommit)
        addSubview(field)
        field.selectText(nil)
        window?.makeFirstResponder(field)
        editField = field
    }

    @objc func editFieldCommit() {
        endEditing()
    }

    func endEditing() {
        guard let field = editField, editingIndex >= 0, editingIndex < sessions.count else {
            editField?.removeFromSuperview()
            editField = nil
            editingIndex = -1
            return
        }
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !newName.isEmpty {
            onRenameSession?(editingIndex, newName)
        }
        field.removeFromSuperview()
        editField = nil
        editingIndex = -1
        needsDisplay = true
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing()
    }
}
