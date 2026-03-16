// ShardPickerView.swift — Shard selection overlay for split pane
//
// Glass panel that appears in an empty split pane. Lists existing shards
// (with crystal colors and isolation badges) plus options to create new ones.

import Cocoa

// ── Shard Picker View ──

class ShardPickerView: NSView {
    var sessions: [TerminalSession] = []
    var visibleSessionIndices: Set<Int> = []
    var projectColor: NSColor = .white

    var onSelectSession: ((Int) -> Void)?
    var onNewSession: (() -> Void)?
    var onNewIsolatedSession: (() -> Void)?
    var onCancel: (() -> Void)?

    private var glass: NSVisualEffectView?
    private var rows: [ShardRow] = []

    func setup() {
        // Glass background
        let g = NSVisualEffectView(frame: bounds)
        g.material = .hudWindow
        g.blendingMode = .behindWindow
        g.state = .active
        g.appearance = NSAppearance(named: .darkAqua)
        g.autoresizingMask = [.width, .height]
        addSubview(g)
        glass = g

        layoutContent()
    }

    private func layoutContent() {
        // Remove old rows
        for row in rows { row.removeFromSuperview() }
        rows.removeAll()

        let panelWidth: CGFloat = 220
        let rowHeight: CGFloat = 32
        let padding: CGFloat = 16
        let headerH: CGFloat = 14

        // Available (non-visible) sessions
        var availableSessions: [(index: Int, session: TerminalSession)] = []
        for (i, s) in sessions.enumerated() {
            if !visibleSessionIndices.contains(i) {
                availableSessions.append((i, s))
            }
        }

        let sessionRows = availableSessions.count
        let actionRows = 2  // new shard + new isolated
        let totalRows = sessionRows + actionRows
        let panelHeight = padding + headerH + 8 + CGFloat(totalRows) * rowHeight + padding

        let panelX = (bounds.width - panelWidth) / 2
        let panelY = (bounds.height - panelHeight) / 2

        // Header
        let header = NSTextField(labelWithString: "PICK A SHARD")
        header.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        header.textColor = NSColor(white: 1.0, alpha: 0.7)
        header.frame = NSRect(x: panelX + padding, y: panelY + panelHeight - padding - headerH,
                              width: panelWidth - padding * 2, height: headerH)
        addSubview(header)
        rows.append(ShardRow()) // placeholder for cleanup

        var y = panelY + panelHeight - padding - headerH - 8

        // Session rows
        for item in availableSessions {
            y -= rowHeight
            let row = ShardRow(frame: NSRect(x: panelX, y: y, width: panelWidth, height: rowHeight))
            row.crystalColor = item.session.crystalColor
            row.title = item.session.isIsolated ? "\u{2387} \(item.session.name)" : item.session.name
            row.sessionIndex = item.index
            row.onClick = { [weak self] idx in self?.onSelectSession?(idx) }
            addSubview(row)
            rows.append(row)
        }

        // Divider
        if !availableSessions.isEmpty {
            y -= 8
            let divider = NSView(frame: NSRect(x: panelX + padding, y: y, width: panelWidth - padding * 2, height: 1))
            divider.wantsLayer = true
            divider.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
            addSubview(divider)
            y -= 8
        }

        // New shard
        y -= rowHeight
        let newRow = ShardRow(frame: NSRect(x: panelX, y: y, width: panelWidth, height: rowHeight))
        newRow.title = "+ New shard"
        newRow.crystalColor = NSColor(white: 1.0, alpha: 0.5)
        newRow.isAction = true
        newRow.onClick = { [weak self] _ in self?.onNewSession?() }
        addSubview(newRow)
        rows.append(newRow)

        // New isolated shard
        y -= rowHeight
        let isoRow = ShardRow(frame: NSRect(x: panelX, y: y, width: panelWidth, height: rowHeight))
        isoRow.title = "+ New isolated shard"
        isoRow.crystalColor = NSColor(white: 1.0, alpha: 0.5)
        isoRow.isAction = true
        isoRow.onClick = { [weak self] _ in self?.onNewIsolatedSession?() }
        addSubview(isoRow)
        rows.append(isoRow)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override var acceptsFirstResponder: Bool { true }
}

// ── Shard Row ──

/// A single row in the shard picker — shows crystal dot + name, highlights on hover.
class ShardRow: NSView {
    var title: String = "" { didSet { needsDisplay = true } }
    var crystalColor: NSColor = .white
    var sessionIndex: Int = -1
    var isAction: Bool = false
    var onClick: ((Int) -> Void)?

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor(white: 1.0, alpha: 0.08).setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 2), xRadius: 6, yRadius: 6).fill()
        }

        let textX: CGFloat = isAction ? 24 : 36
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: isHovered ? NSColor.white : NSColor(white: 1.0, alpha: 0.8),
            .font: NSFont.systemFont(ofSize: 12, weight: isAction ? .medium : .regular),
        ]
        (title as NSString).draw(at: NSPoint(x: textX, y: (bounds.height - 14) / 2), withAttributes: attrs)

        // Crystal dot
        if !isAction {
            let dotSize: CGFloat = 8
            let dotY = (bounds.height - dotSize) / 2
            crystalColor.setFill()
            NSBezierPath(ovalIn: NSRect(x: 20, y: dotY, width: dotSize, height: dotSize)).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(sessionIndex)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                      owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }
}
