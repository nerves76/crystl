// CrystalRail.swift — Screen-edge glass panel for project navigation and approval indicators
//
// A narrow frosted glass rail pinned to the left edge of the screen. Shows a tile
// for each open terminal tab with its project initial and session color. When a
// pending approval arrives, the matching tile pulses with a prismatic shimmer.
// Clicking a tile brings that tab to front. Folders can be dragged onto the rail
// to open them as new projects.

import Cocoa

// MARK: - Rail Tile Data

/// Holds the state for one tile in the rail, mapped 1:1 to a ProjectTab.
class RailTile {
    let tabId: UUID
    var title: String
    var color: NSColor
    var cwd: String
    var iconName: String?
    var pendingCount: Int = 0
    var isSelected: Bool = false

    init(tabId: UUID, title: String, color: NSColor, cwd: String, iconName: String? = nil) {
        self.tabId = tabId
        self.title = title
        self.color = color
        self.cwd = cwd
        self.iconName = iconName
    }
}

// MARK: - Rail Tile View

/// Renders a single tile: rounded glass square with a project initial, session-colored
/// border, and pulsing shimmer animation when approvals are pending.
class RailTileView: NSView {
    var tile: RailTile
    var onClick: ((UUID) -> Void)?
    var onChangeIcon: ((UUID) -> Void)?
    private var shimmerLayer: CAGradientLayer?
    private var isPulsing = false
    private var badgeLabel: NSTextField?
    init(tile: RailTile, frame: NSRect) {
        self.tile = tile
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        setupBadge()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let changeItem = NSMenuItem(title: "Change Icon...", action: #selector(changeIconClicked), keyEquivalent: "")
        changeItem.target = self
        menu.addItem(changeItem)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func changeIconClicked() {
        onChangeIcon?(tile.tabId)
    }

    private func setupBadge() {
        let badge = NSTextField(labelWithString: "")
        badge.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 7
        badge.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.9).cgColor
        badge.frame = NSRect(x: bounds.width - 16, y: bounds.height - 16, width: 14, height: 14)
        badge.isHidden = true
        addSubview(badge)
        badgeLabel = badge
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Background — brighter when selected
        let bgAlpha: CGFloat = tile.isSelected ? 0.25 : 0.1
        ctx.setFillColor(tile.color.withAlphaComponent(bgAlpha).cgColor)
        let bgPath = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(bgPath)
        ctx.fillPath()

        // Border
        let borderAlpha: CGFloat = tile.isSelected ? 0.6 : 0.2
        ctx.setStrokeColor(tile.color.withAlphaComponent(borderAlpha).cgColor)
        ctx.setLineWidth(tile.isSelected ? 1.5 : 0.5)
        ctx.addPath(bgPath)
        ctx.strokePath()

        // Icon or initial letter
        let iconAlpha: CGFloat = tile.isSelected ? 1.0 : 0.7
        if let name = tile.iconName,
           let icon = LucideIcons.render(name: name, size: 20, color: tile.color.withAlphaComponent(iconAlpha)) {
            let iconRect = NSRect(
                x: (bounds.width - 20) / 2,
                y: (bounds.height - 20) / 2,
                width: 20, height: 20
            )
            icon.draw(in: iconRect)
        } else {
            let initial = projectInitial(tile.title)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(iconAlpha)
            ]
            let str = initial as NSString
            let sz = str.size(withAttributes: attrs)
            let textRect = NSRect(
                x: (bounds.width - sz.width) / 2,
                y: (bounds.height - sz.height) / 2,
                width: sz.width,
                height: sz.height
            )
            str.draw(in: textRect, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(tile.tabId)
        onChangeIcon?(tile.tabId)
    }

    func update() {
        // Update badge
        if tile.pendingCount > 0 {
            badgeLabel?.stringValue = "\(tile.pendingCount)"
            badgeLabel?.isHidden = false
        } else {
            badgeLabel?.isHidden = true
        }

        // Toggle pulse animation
        if tile.pendingCount > 0 && !isPulsing {
            startPulse()
        } else if tile.pendingCount == 0 && isPulsing {
            stopPulse()
        }

        needsDisplay = true
    }

    // MARK: - Pulse Animation

    private func startPulse() {
        isPulsing = true
        guard let layer = self.layer else { return }

        // Pulsing border glow
        let borderPulse = CABasicAnimation(keyPath: "borderColor")
        borderPulse.fromValue = tile.color.withAlphaComponent(0.3).cgColor
        borderPulse.toValue = tile.color.withAlphaComponent(0.9).cgColor
        borderPulse.duration = 1.0
        borderPulse.autoreverses = true
        borderPulse.repeatCount = .infinity
        borderPulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.borderWidth = 1.5
        layer.borderColor = tile.color.withAlphaComponent(0.6).cgColor
        layer.add(borderPulse, forKey: "pendingBorderPulse")

        // Subtle scale pulse
        let scalePulse = CABasicAnimation(keyPath: "transform.scale")
        scalePulse.fromValue = 1.0
        scalePulse.toValue = 1.06
        scalePulse.duration = 1.0
        scalePulse.autoreverses = true
        scalePulse.repeatCount = .infinity
        scalePulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(scalePulse, forKey: "pendingScalePulse")

        // Shimmer sweep (looping)
        let shimmer = CAGradientLayer()
        shimmer.frame = bounds
        shimmer.type = .axial
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.colors = [
            NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.0).cgColor,
            NSColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 0.25).cgColor,
            NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.4).cgColor,
            NSColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 0.25).cgColor,
            NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.0).cgColor,
        ]
        shimmer.locations = [0, 0.25, 0.5, 0.75, 1.0]
        shimmer.cornerRadius = 10

        let sweep = CABasicAnimation(keyPath: "startPoint.x")
        sweep.fromValue = -1.0
        sweep.toValue = 2.0
        sweep.duration = 2.0
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)

        let sweepEnd = CABasicAnimation(keyPath: "endPoint.x")
        sweepEnd.fromValue = 0.0
        sweepEnd.toValue = 3.0
        sweepEnd.duration = 2.0
        sweepEnd.repeatCount = .infinity
        sweepEnd.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)

        shimmer.add(sweep, forKey: "shimmerSweep")
        shimmer.add(sweepEnd, forKey: "shimmerSweepEnd")
        layer.addSublayer(shimmer)
        shimmerLayer = shimmer
    }

    private func stopPulse() {
        isPulsing = false
        layer?.removeAnimation(forKey: "pendingBorderPulse")
        layer?.removeAnimation(forKey: "pendingScalePulse")
        layer?.borderWidth = tile.isSelected ? 1.5 : 0.5
        layer?.borderColor = tile.color.withAlphaComponent(tile.isSelected ? 0.6 : 0.2).cgColor
        shimmerLayer?.removeFromSuperlayer()
        shimmerLayer = nil
    }

    private func projectInitial(_ title: String) -> String {
        let clean = title.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return "?" }
        return String(clean.prefix(1)).uppercased()
    }
}

// MARK: - Rail Settings Button

/// Clickable icon button with hover glow for the rail settings icon.
class RailSettingsButton: NSButton {
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1.0
        }
        wantsLayer = true
        layer?.shadowColor = NSColor.white.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = 8
        let anim = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue = 0
        anim.toValue = 0.6
        anim.duration = 0.15
        layer?.shadowOpacity = 0.6
        layer?.add(anim, forKey: "glowIn")
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = 0.7
        }
        let anim = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue = 0.6
        anim.toValue = 0
        anim.duration = 0.25
        layer?.shadowOpacity = 0
        layer?.add(anim, forKey: "glowOut")
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - Rail Add Button

/// A "+" button rendered as a rounded glass tile, matching the tile aesthetic.
class RailAddButton: NSView {
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Subtle background
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
        let bgPath = CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(bgPath)
        ctx.fillPath()

        // Border
        ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(bgPath)
        ctx.strokePath()

        // "+" text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .ultraLight),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.5)
        ]
        let str = "+" as NSString
        let sz = str.size(withAttributes: attrs)
        let textRect = NSRect(
            x: (bounds.width - sz.width) / 2,
            y: (bounds.height - sz.height) / 2,
            width: sz.width,
            height: sz.height
        )
        str.draw(in: textRect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

// MARK: - New Project Panel

/// A floating glass input panel for creating a new project folder.
/// Includes name field, icon picker grid, and color picker.
class NewProjectPanel: NSObject {
    private var panel: NSPanel?
    private var nameField: NSTextField?
    private var iconGrid: IconGridView?
    private var colorGrid: ColorGridView?
    private var includeMcp: NSButton?
    private var includeClaudeMd: NSButton?
    private var includeAgentsMd: NSButton?
    var onSubmit: ((String, String?, String?, Bool, Bool, Bool) -> Void)?  // (name, iconName, colorHex, includeMcp, includeClaudeMd, includeAgentsMd)
    var onDismiss: (() -> Void)?

    func show(relativeTo railPanel: NSPanel) {
        dismiss()

        let hasMcpDefaults = !MCPConfigManager.shared.catalog.servers.isEmpty
        let hasClaudeMdTemplate = !DefaultClaudeMd.load().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAgentsMdTemplate = !DefaultAgentsMd.load().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let checkboxCount = (hasMcpDefaults ? 1 : 0) + (hasClaudeMdTemplate ? 1 : 0) + (hasAgentsMdTemplate ? 1 : 0)
        let checkboxHeight: CGFloat = checkboxCount > 0 ? CGFloat(checkboxCount) * 22 + 4 : 0

        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 420 + checkboxHeight

        // Position to the right of the rail
        let railFrame = railPanel.frame
        let x = railFrame.maxX + 8
        let y = railFrame.midY - (panelHeight / 2)

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = false

        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        glass.material = .hudWindow
        glass.alphaValue = 0.85
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.maskImage = roundedMaskImage(size: NSSize(width: panelWidth, height: panelHeight), radius: 12)
        glass.wantsLayer = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor(white: 1.0, alpha: 0.3).cgColor

        var y0 = panelHeight - 28

        // Label + close button
        let label = NSTextField(labelWithString: "New Project")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: 16, y: y0, width: panelWidth - 56, height: 18)
        glass.addSubview(label)

        let closeBtn = NSButton(frame: NSRect(x: panelWidth - 32, y: y0, width: 18, height: 18))
        closeBtn.title = "×"
        closeBtn.bezelStyle = .inline
        closeBtn.isBordered = false
        closeBtn.font = NSFont.systemFont(ofSize: 16, weight: .light)
        closeBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
        closeBtn.target = self
        closeBtn.action = #selector(cancelClicked)
        closeBtn.keyEquivalent = "\u{1b}"  // Escape key
        glass.addSubview(closeBtn)
        y0 -= 30

        // Name field
        let field = NSTextField(frame: NSRect(x: 16, y: y0, width: panelWidth - 32, height: 24))
        field.placeholderString = "project-name"
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = .white
        field.backgroundColor = NSColor(white: 1.0, alpha: 0.08)
        field.isBordered = false
        field.isBezeled = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.target = self
        field.action = #selector(fieldSubmitted(_:))
        glass.addSubview(field)
        nameField = field
        y0 -= 28

        // Color section
        let colorLabel = NSTextField(labelWithString: "COLOR")
        colorLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        colorLabel.textColor = NSColor(white: 1.0, alpha: 0.4)
        colorLabel.frame = NSRect(x: 16, y: y0, width: panelWidth - 32, height: 12)
        glass.addSubview(colorLabel)
        y0 -= 32

        let cGrid = ColorGridView(frame: NSRect(x: 16, y: y0, width: panelWidth - 32, height: 28))
        glass.addSubview(cGrid)
        colorGrid = cGrid
        y0 -= 22

        // Icon section
        let iconLabel = NSTextField(labelWithString: "ICON")
        iconLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        iconLabel.textColor = NSColor(white: 1.0, alpha: 0.4)
        iconLabel.frame = NSRect(x: 16, y: y0, width: panelWidth - 32, height: 12)
        glass.addSubview(iconLabel)
        y0 -= 6

        // Search field for icons
        let searchField = NSTextField(frame: NSRect(x: 16, y: y0 - 20, width: panelWidth - 32, height: 20))
        searchField.placeholderString = "Search icons..."
        searchField.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        searchField.textColor = .white
        searchField.backgroundColor = NSColor(white: 1.0, alpha: 0.06)
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.focusRingType = .none
        searchField.drawsBackground = true
        searchField.wantsLayer = true
        searchField.layer?.cornerRadius = 4
        glass.addSubview(searchField)
        y0 -= 26

        // Bottom area height: checkboxes + create button + padding
        let bottomH: CGFloat = 48 + checkboxHeight

        // Icon grid (scrollable)
        let gridHeight = y0 - bottomH
        let scrollView = NSScrollView(frame: NSRect(x: 16, y: bottomH, width: panelWidth - 32, height: gridHeight))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let iGrid = IconGridView(frame: NSRect(x: 0, y: 0, width: panelWidth - 32, height: gridHeight), containerWidth: panelWidth - 32)
        iGrid.selectedColor = cGrid.selectedColor
        scrollView.documentView = iGrid
        glass.addSubview(scrollView)
        iconGrid = iGrid

        // Wire color changes to icon grid
        cGrid.onColorChanged = { [weak iGrid] color in
            iGrid?.selectedColor = color
            iGrid?.needsDisplay = true
        }

        // Wire search to icon grid
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))

        // ── Default include checkboxes (above create button) ──
        var cbY: CGFloat = 44

        if hasAgentsMdTemplate {
            let cb = NSButton(checkboxWithTitle: "Include default AGENTS.md", target: nil, action: nil)
            cb.state = .on
            cb.attributedTitle = NSAttributedString(string: "Include default AGENTS.md", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10)
            ])
            cb.frame = NSRect(x: 16, y: cbY, width: panelWidth - 32, height: 18)
            glass.addSubview(cb)
            includeAgentsMd = cb
            cbY += 22
        }

        if hasClaudeMdTemplate {
            let cb = NSButton(checkboxWithTitle: "Include default CLAUDE.md", target: nil, action: nil)
            cb.state = .on
            cb.attributedTitle = NSAttributedString(string: "Include default CLAUDE.md", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10)
            ])
            cb.frame = NSRect(x: 16, y: cbY, width: panelWidth - 32, height: 18)
            glass.addSubview(cb)
            includeClaudeMd = cb
            cbY += 22
        }

        if hasMcpDefaults {
            let cb = NSButton(checkboxWithTitle: "Include default MCP servers", target: nil, action: nil)
            cb.state = .on
            cb.attributedTitle = NSAttributedString(string: "Include default MCP servers", attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 10)
            ])
            cb.frame = NSRect(x: 16, y: cbY, width: panelWidth - 32, height: 18)
            glass.addSubview(cb)
            includeMcp = cb
            cbY += 22
        }

        // Create button
        let createBtn = NSButton(frame: NSRect(x: 16, y: 12, width: panelWidth - 32, height: 28))
        createBtn.title = "Create Project"
        createBtn.bezelStyle = .rounded
        createBtn.isBordered = false
        createBtn.wantsLayer = true
        createBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
        createBtn.layer?.cornerRadius = 6
        createBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        createBtn.contentTintColor = NSColor.systemGreen
        createBtn.target = self
        createBtn.action = #selector(createClicked)
        glass.addSubview(createBtn)

        p.contentView = glass
        p.orderFrontRegardless()
        p.makeKey()
        p.makeFirstResponder(field)

        panel = p
    }

    @objc private func fieldSubmitted(_ sender: NSTextField) {
        submitProject()
    }

    @objc private func createClicked() {
        submitProject()
    }

    @objc private func cancelClicked() {
        dismiss()
        onDismiss?()
    }

    @objc private func searchChanged(_ sender: NSTextField) {
        iconGrid?.filterText = sender.stringValue
    }

    private func submitProject() {
        let name = nameField?.stringValue.trimmingCharacters(in: .whitespaces) ?? ""
        guard !name.isEmpty else { return }
        let iconName = iconGrid?.selectedIcon
        let colorHex = colorGrid?.selectedColor.hexString
        let wantMcp = includeMcp?.state == .on
        let wantClaudeMd = includeClaudeMd?.state == .on
        let wantAgentsMd = includeAgentsMd?.state == .on
        onSubmit?(name, iconName, colorHex, wantMcp, wantClaudeMd, wantAgentsMd)
        dismiss()
    }

    func dismiss() {
        // Break retain cycles from field targets
        if let contentView = panel?.contentView {
            for subview in contentView.subviews {
                if let field = subview as? NSTextField, field.target === self {
                    field.target = nil
                    field.action = nil
                }
            }
            for subview in contentView.subviews {
                if let btn = subview as? NSButton, btn.target === self {
                    btn.target = nil
                    btn.action = nil
                }
            }
        }
        includeMcp = nil
        includeClaudeMd = nil
        includeAgentsMd = nil
        panel?.close()
        panel = nil
    }
}

// MARK: - Rail Drop Target View

/// Invisible drop zone layered over the rail. Accepts folder drops.
class RailDropView: NSView {
    var onFolderDropped: ((String) -> Void)?
    var isHighlighted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasFolderURL(sender) else { return [] }
        isHighlighted = true
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHighlighted = false
        layer?.borderWidth = 0
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isHighlighted = false
        layer?.borderWidth = 0

        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }

        for url in items {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                onFolderDropped?(url.path)
            }
        }
        return true
    }

    private func hasFolderURL(_ info: NSDraggingInfo) -> Bool {
        return info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ])
    }
}

// MARK: - Crystal Rail Controller

/// Manages the screen-edge glass rail panel. Creates an always-on-top NSPanel
/// pinned to the left edge of the screen, populated with tiles for each terminal tab.
class CrystalRailController {
    var panel: NSPanel!
    var tileViews: [UUID: RailTileView] = [:]
    var tiles: [RailTile] = []
    var onTileClicked: ((UUID) -> Void)?
    var onFolderDropped: ((String) -> Void)?
    var onAddClicked: (() -> Void)?
    var onNewProject: ((String, String?, String?, Bool, Bool, Bool) -> Void)?  // (name, iconName, colorHex, includeMcp, includeClaudeMd, includeAgentsMd)
    var onChangeIcon: ((UUID) -> Void)?
    var onSettingsIconClicked: ((NSView) -> Void)?
    private var newProjectPanel = NewProjectPanel()
    private weak var glassView: NSVisualEffectView?

    private let railWidth: CGFloat = 52
    private let tileSize: CGFloat = 38
    private let tileSpacing: CGFloat = 8
    private let topPadding: CGFloat = 8
    private let iconSize: CGFloat = 28     // Crystl logo at top
    private let addButtonSize: CGFloat = 28 // "+" button at bottom
    private let sectionSpacing: CGFloat = 10 // space between icon/tiles/button
    private let railMargin: CGFloat = 6
    private var contentView: NSView!
    private var iconView: NSView?
    private var addButton: NSView?

    func setup() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Start with a minimal height — layoutTiles will resize to fit content
        let initialHeight: CGFloat = tileSize + (topPadding * 2)
        let y = screenFrame.midY - (initialHeight / 2)
        panel = NSPanel(
            contentRect: NSRect(
                x: screenFrame.minX + railMargin,
                y: y,
                width: railWidth,
                height: initialHeight
            ),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.hasShadow = true

        // Glass background — match window opacity
        let savedOpacity = UserDefaults.standard.double(forKey: "windowOpacity")
        let resolvedOpacity: CGFloat = savedOpacity > 0.01 ? CGFloat(savedOpacity) : 0.85
        panel.backgroundColor = NSColor(white: 0.1, alpha: resolvedOpacity)
        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: railWidth, height: initialHeight))
        glass.material = .hudWindow
        glass.alphaValue = resolvedOpacity
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.maskImage = railMaskImage(size: NSSize(width: railWidth, height: initialHeight))
        glass.wantsLayer = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor(white: 1.0, alpha: 0.3).cgColor

        // Drop target
        let dropView = RailDropView(frame: glass.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.onFolderDropped = { [weak self] path in
            self?.onFolderDropped?(path)
        }
        glass.addSubview(dropView)

        // Settings icon at top — clickable, shows flyout menu
        let iconBtn = RailSettingsButton(frame: NSRect(x: (railWidth - iconSize) / 2, y: 0, width: iconSize, height: iconSize))
        if let path = Bundle.main.path(forResource: "white-diamond-top", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: iconSize, height: iconSize)
            iconBtn.image = img
            iconBtn.imageScaling = .scaleProportionallyDown
        }
        iconBtn.isBordered = false
        iconBtn.bezelStyle = .inline
        iconBtn.alphaValue = 0.7
        iconBtn.onClick = { [weak self] in
            self?.onSettingsIconClicked?(iconBtn)
        }
        glass.addSubview(iconBtn)
        iconView = iconBtn

        // "+" button at bottom
        let addBtn = RailAddButton(frame: NSRect(x: (railWidth - addButtonSize) / 2, y: 0, width: addButtonSize, height: addButtonSize))
        addBtn.onClick = { [weak self] in
            self?.showNewProjectPanel()
        }
        newProjectPanel.onSubmit = { [weak self] name, iconName, colorHex, includeMcp, includeClaudeMd, includeAgentsMd in
            self?.onNewProject?(name, iconName, colorHex, includeMcp, includeClaudeMd, includeAgentsMd)
        }
        glass.addSubview(addBtn)
        addButton = addBtn

        contentView = glass
        glassView = glass
        panel.contentView = glass
        panel.orderFrontRegardless()

        animateRailOpen()
    }

    // MARK: - Opacity

    func setOpacity(_ alpha: CGFloat) {
        glassView?.alphaValue = alpha
        panel?.backgroundColor = NSColor(white: 0.1, alpha: alpha)
    }

    // MARK: - New Project

    func showNewProjectPanel() {
        guard let p = panel else { return }
        newProjectPanel.show(relativeTo: p)
    }

    // MARK: - Tile Management

    func addTile(tab: ProjectTab) {
        // Prevent duplicate tiles
        guard !tiles.contains(where: { $0.tabId == tab.id }) else { return }
        let tile = RailTile(tabId: tab.id, title: tab.title, color: tab.color, cwd: tab.directory, iconName: tab.iconName)
        tiles.append(tile)
        NSLog("CrystalRail: addTile '\(tab.title)' — total tiles: \(tiles.count)")

        let tileFrame = NSRect(x: (railWidth - tileSize) / 2, y: 0, width: tileSize, height: tileSize)
        let tileView = RailTileView(tile: tile, frame: tileFrame)
        tileView.onClick = { [weak self] tabId in
            self?.onTileClicked?(tabId)
        }
        tileView.onChangeIcon = { [weak self] tabId in
            self?.onChangeIcon?(tabId)
        }
        tileViews[tab.id] = tileView
        contentView.addSubview(tileView)

        layoutTiles()
        animateTileIn(tileView)
    }

    func removeTile(tabId: UUID) {
        guard let view = tileViews[tabId] else { return }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            view.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            view.removeFromSuperview()
            self.tileViews.removeValue(forKey: tabId)
            self.tiles.removeAll { $0.tabId == tabId }
            self.layoutTiles()
        })
    }

    func selectTile(tabId: UUID) {
        for tile in tiles {
            tile.isSelected = (tile.tabId == tabId)
        }
        for (_, view) in tileViews {
            view.update()
        }
    }

    func updateTile(tabId: UUID, title: String, cwd: String, iconName: String? = nil, color: NSColor? = nil) {
        guard let tile = tiles.first(where: { $0.tabId == tabId }) else { return }
        tile.title = title
        tile.cwd = cwd
        if let name = iconName { tile.iconName = name }
        if let c = color { tile.color = c }
        tileViews[tabId]?.update()
    }

    // MARK: - Pending Approvals

    /// Updates pending counts based on current pending requests.
    /// Matches requests to tiles using cwd prefix matching.
    func updatePending(_ pending: [PendingRequest]) {
        // Reset all counts
        for tile in tiles {
            tile.pendingCount = 0
        }

        // Count pending per tile
        for req in pending {
            guard let cwd = req.cwd, !cwd.isEmpty else { continue }
            if let tile = tiles.first(where: { $0.cwd == cwd }) {
                tile.pendingCount += 1
            } else if let tile = tiles.first(where: { cwd.hasPrefix($0.cwd) || $0.cwd.hasPrefix(cwd) }) {
                tile.pendingCount += 1
            }
        }

        // Update views
        for (_, view) in tileViews {
            view.update()
        }
    }

    func clearAllPending() {
        for tile in tiles {
            tile.pendingCount = 0
        }
        for (_, view) in tileViews {
            view.update()
        }
    }

    // MARK: - Layout

    private func layoutTiles() {
        guard panel != nil, let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // Layout: [padding] [icon] [spacing] [tiles...] [spacing] [+button] [padding]
        let tileCount = max(tiles.count, 0)
        let tilesHeight = CGFloat(tileCount) * tileSize + CGFloat(max(tileCount - 1, 0)) * tileSpacing
        let panelHeight = topPadding + iconSize + sectionSpacing + tilesHeight + sectionSpacing + addButtonSize + topPadding

        // Center vertically on screen
        let y = screenFrame.midY - (panelHeight / 2)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().setFrame(NSRect(x: screenFrame.minX + railMargin, y: y, width: railWidth, height: panelHeight), display: true)
        }

        // Update glass view and mask to match new size
        if let glass = contentView as? NSVisualEffectView {
            glass.frame = NSRect(x: 0, y: 0, width: railWidth, height: panelHeight)
            glass.maskImage = railMaskImage(size: NSSize(width: railWidth, height: panelHeight))
        }

        // Position icon at top
        let iconY = panelHeight - topPadding - iconSize
        iconView?.frame = NSRect(x: (railWidth - iconSize) / 2, y: iconY, width: iconSize, height: iconSize)

        // Position tiles below icon
        let tilesStartY = iconY - sectionSpacing - tileSize

        for (i, tile) in tiles.enumerated() {
            guard let view = tileViews[tile.tabId] else { continue }
            let tileY = tilesStartY - CGFloat(i) * (tileSize + tileSpacing)
            let targetFrame = NSRect(x: (railWidth - tileSize) / 2, y: tileY, width: tileSize, height: tileSize)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
                view.animator().frame = targetFrame
            }
        }

        // Position "+" button at bottom
        addButton?.frame = NSRect(x: (railWidth - addButtonSize) / 2, y: topPadding, width: addButtonSize, height: addButtonSize)
    }

    // MARK: - Animations

    private func animateRailOpen() {
        guard let layer = contentView.layer else { return }
        let fluidTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        // Slide in from left
        let slide = CABasicAnimation(keyPath: "transform.translation.x")
        slide.fromValue = -railWidth
        slide.toValue = 0
        slide.duration = 0.5
        slide.timingFunction = fluidTiming

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.3
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)

        layer.add(slide, forKey: "railSlide")
        layer.add(fade, forKey: "railFade")
    }

    private func animateTileIn(_ view: RailTileView) {
        guard let layer = view.layer else { return }
        let fluidTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: view.bounds.midX + view.frame.origin.x,
                                  y: view.bounds.midY + view.frame.origin.y)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.0
        scale.toValue = 1.0
        scale.duration = 0.35
        scale.timingFunction = fluidTiming

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = 0.2

        layer.add(scale, forKey: "tileScale")
        layer.add(opacity, forKey: "tileOpacity")
    }

    // MARK: - Mask

    /// Creates a mask image for the rail with rounded corners.
    private func railMaskImage(size: NSSize) -> NSImage {
        roundedMaskImage(size: size, radius: 12)
    }
}
