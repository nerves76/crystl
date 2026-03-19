// IconPickerView.swift — Icon and color picker UI components
//
// Shared views used by the NewProjectPanel (create flow) and
// IconPickerPanel (change icon flow). Includes:
//   - ColorGridView: Row of preset color dots with selection
//   - IconGridView: Scrollable grid of Lucide icons with search filtering
//   - IconPickerPanel: Standalone floating glass panel for changing icon/color

import Cocoa

// MARK: - Preset Colors

/// Extended color palette for project identification.
/// Includes the 8 session colors plus 8 additional vibrant colors.
let presetColors: [NSColor] = [
    // Session colors (muted)
    NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0),  // soft blue
    NSColor(red: 0.72, green: 0.58, blue: 0.90, alpha: 1.0),  // lavender
    NSColor(red: 0.90, green: 0.62, blue: 0.55, alpha: 1.0),  // warm coral
    NSColor(red: 0.55, green: 0.82, blue: 0.72, alpha: 1.0),  // sage
    NSColor(red: 0.88, green: 0.75, blue: 0.55, alpha: 1.0),  // amber
    NSColor(red: 0.75, green: 0.55, blue: 0.72, alpha: 1.0),  // mauve
    NSColor(red: 0.55, green: 0.78, blue: 0.82, alpha: 1.0),  // frost
    NSColor(red: 0.85, green: 0.65, blue: 0.78, alpha: 1.0),  // rose
    // Additional vibrant
    NSColor(red: 0.95, green: 0.30, blue: 0.35, alpha: 1.0),  // red
    NSColor(red: 0.95, green: 0.55, blue: 0.25, alpha: 1.0),  // orange
    NSColor(red: 0.95, green: 0.85, blue: 0.35, alpha: 1.0),  // yellow
    NSColor(red: 0.35, green: 0.85, blue: 0.45, alpha: 1.0),  // green
    NSColor(red: 0.30, green: 0.80, blue: 0.85, alpha: 1.0),  // teal
    NSColor(red: 0.40, green: 0.50, blue: 0.95, alpha: 1.0),  // indigo
    NSColor(red: 0.90, green: 0.40, blue: 0.70, alpha: 1.0),  // pink
    NSColor(red: 0.85, green: 0.85, blue: 0.90, alpha: 1.0),  // silver
]

// MARK: - Color Grid View

/// A row of clickable color dots for selecting a project color.
/// Edges fade to transparent so dots don't clip hard against the panel border.
class ColorGridView: NSView {
    var selectedColor: NSColor = presetColors[0]
    var onColorChanged: ((NSColor) -> Void)?
    private let dotSize: CGFloat = 16
    private let dotSpacing: CGFloat = 2
    private let fadeWidth: CGFloat = 0

    override func layout() {
        super.layout()
        wantsLayer = true
        layer?.mask = nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let cols = presetColors.count
        let totalW = CGFloat(cols) * dotSize + CGFloat(cols - 1) * dotSpacing
        let startX = (bounds.width - totalW) / 2

        for (i, color) in presetColors.enumerated() {
            let x = startX + CGFloat(i) * (dotSize + dotSpacing)
            let y = (bounds.height - dotSize) / 2
            let rect = NSRect(x: x, y: y, width: dotSize, height: dotSize)

            // Fill
            color.setFill()
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            path.fill()

            // Selection ring
            if colorsMatch(color, selectedColor) {
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let ring = NSBezierPath(ovalIn: rect)
                ring.lineWidth = 2.0
                ring.stroke()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let cols = presetColors.count
        let totalW = CGFloat(cols) * dotSize + CGFloat(cols - 1) * dotSpacing
        let startX = (bounds.width - totalW) / 2

        for (i, color) in presetColors.enumerated() {
            let x = startX + CGFloat(i) * (dotSize + dotSpacing)
            let rect = NSRect(x: x, y: (bounds.height - dotSize) / 2, width: dotSize, height: dotSize)
            if rect.contains(loc) {
                selectedColor = color
                onColorChanged?(color)
                needsDisplay = true
                return
            }
        }
    }

    /// Programmatically select a color by index (for demo).
    func selectIndex(_ index: Int) {
        guard index >= 0 && index < presetColors.count else { return }
        selectedColor = presetColors[index]
        onColorChanged?(selectedColor)
        needsDisplay = true
    }

    private func colorsMatch(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let a2 = a.usingColorSpace(.sRGB), let b2 = b.usingColorSpace(.sRGB) else { return false }
        return abs(a2.redComponent - b2.redComponent) < 0.02
            && abs(a2.greenComponent - b2.greenComponent) < 0.02
            && abs(a2.blueComponent - b2.blueComponent) < 0.02
    }
}

// MARK: - Icon Grid View

/// Scrollable grid of Lucide icons. Supports search filtering and selection.
class IconGridView: NSView {
    var selectedIcon: String?
    var selectedColor: NSColor = presetColors[0]
    var onIconSelected: ((String) -> Void)?
    private let iconSize: CGFloat = 28
    private let cellSize: CGFloat = 36
    private let cellSpacing: CGFloat = 4
    private var containerWidth: CGFloat = 288
    private var filteredIcons: [String] = []

    var filterText: String = "" {
        didSet { refilter() }
    }

    init(frame: NSRect, containerWidth: CGFloat) {
        self.containerWidth = containerWidth
        super.init(frame: frame)
        refilter()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refilter() {
        let allIcons = LucideIcons.allNames
        if filterText.isEmpty {
            filteredIcons = allIcons
        } else {
            let query = filterText.lowercased()
            filteredIcons = allIcons.filter { $0.contains(query) }
        }
        resizeToFit()
        needsDisplay = true
    }

    private var cols: Int {
        max(1, Int((containerWidth + cellSpacing) / (cellSize + cellSpacing)))
    }

    private func resizeToFit() {
        let rows = (filteredIcons.count + cols - 1) / cols
        let height = CGFloat(rows) * (cellSize + cellSpacing)
        frame = NSRect(x: frame.origin.x, y: frame.origin.y, width: containerWidth, height: max(height, 40))
    }

    override func draw(_ dirtyRect: NSRect) {
        let c = cols
        for (i, iconName) in filteredIcons.enumerated() {
            let col = i % c
            let row = i / c
            let x = CGFloat(col) * (cellSize + cellSpacing)
            let y = frame.height - CGFloat(row + 1) * (cellSize + cellSpacing)
            let cellRect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

            guard cellRect.intersects(dirtyRect) else { continue }

            let isSelected = iconName == selectedIcon

            // Cell background
            if isSelected {
                NSColor(white: 1.0, alpha: 0.2).setFill()
                NSBezierPath(roundedRect: cellRect, xRadius: 6, yRadius: 6).fill()
            }

            // Icon
            let color = isSelected ? selectedColor : NSColor(white: 1.0, alpha: 0.6)
            if let img = LucideIcons.render(name: iconName, size: iconSize, color: color) {
                let iconRect = NSRect(
                    x: cellRect.midX - iconSize / 2,
                    y: cellRect.midY - iconSize / 2,
                    width: iconSize, height: iconSize
                )
                img.draw(in: iconRect)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let c = cols
        for (i, iconName) in filteredIcons.enumerated() {
            let col = i % c
            let row = i / c
            let x = CGFloat(col) * (cellSize + cellSpacing)
            let y = frame.height - CGFloat(row + 1) * (cellSize + cellSpacing)
            let cellRect = NSRect(x: x, y: y, width: cellSize, height: cellSize)

            if cellRect.contains(loc) {
                // Toggle: clicking the already-selected icon deselects it
                if selectedIcon == iconName {
                    selectedIcon = nil
                } else {
                    selectedIcon = iconName
                }
                onIconSelected?(selectedIcon ?? "")
                needsDisplay = true
                return
            }
        }
    }

    /// Programmatically select an icon by name (for demo).
    func selectIcon(_ name: String) {
        selectedIcon = name
        onIconSelected?(name)
        needsDisplay = true

        // Scroll to make the selected icon visible
        if let idx = filteredIcons.firstIndex(of: name) {
            let col = idx % cols
            let row = idx / cols
            let x = CGFloat(col) * (cellSize + cellSpacing)
            let y = frame.height - CGFloat(row + 1) * (cellSize + cellSpacing)
            let cellRect = NSRect(x: x, y: y, width: cellSize, height: cellSize)
            scrollToVisible(cellRect)
        }
    }
}

// MARK: - Icon Picker Panel

/// Standalone floating glass panel for changing a project's icon and color.
/// Used from the right-click "Change Icon" menu on rail tiles.
class IconPickerPanel: NSObject {
    private var panel: NSPanel?
    private var iconGrid: IconGridView?
    private var colorGrid: ColorGridView?
    var selectedIcon: String?
    var selectedColor: NSColor = presetColors[0]
    var onSave: ((String?, NSColor) -> Void)?

    func show(relativeTo railPanel: NSPanel) {
        dismiss()

        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 400

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

        let label = NSTextField(labelWithString: "Change Icon")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        label.frame = NSRect(x: 16, y: y0, width: panelWidth - 32, height: 18)
        glass.addSubview(label)
        y0 -= 24

        // Color section
        let colorLabel = NSTextField(labelWithString: "COLOR")
        colorLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        colorLabel.textColor = NSColor(white: 1.0, alpha: 0.4)
        colorLabel.frame = NSRect(x: 16, y: y0, width: panelWidth - 32, height: 12)
        glass.addSubview(colorLabel)
        y0 -= 32

        let cGrid = ColorGridView(frame: NSRect(x: 16, y: y0, width: panelWidth - 32, height: 28))
        cGrid.selectedColor = selectedColor
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

        // Search field
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
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        glass.addSubview(searchField)
        y0 -= 26

        // Icon grid (scrollable)
        let gridHeight = y0 - 48
        let scrollView = NSScrollView(frame: NSRect(x: 16, y: 48, width: panelWidth - 32, height: gridHeight))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let iGrid = IconGridView(frame: NSRect(x: 0, y: 0, width: panelWidth - 32, height: gridHeight), containerWidth: panelWidth - 32)
        iGrid.selectedIcon = selectedIcon
        iGrid.selectedColor = selectedColor
        scrollView.documentView = iGrid
        glass.addSubview(scrollView)
        iconGrid = iGrid

        cGrid.onColorChanged = { [weak iGrid] color in
            iGrid?.selectedColor = color
            iGrid?.needsDisplay = true
        }

        // Save button
        let saveBtn = NSButton(frame: NSRect(x: 16, y: 12, width: panelWidth - 32, height: 28))
        saveBtn.title = "Save"
        saveBtn.bezelStyle = .rounded
        saveBtn.isBordered = false
        saveBtn.wantsLayer = true
        saveBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
        saveBtn.layer?.cornerRadius = 6
        saveBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        saveBtn.contentTintColor = NSColor.systemGreen
        saveBtn.target = self
        saveBtn.action = #selector(saveClicked)
        glass.addSubview(saveBtn)

        p.contentView = glass
        p.orderFrontRegardless()
        p.makeKey()

        panel = p
    }

    @objc private func searchChanged(_ sender: NSTextField) {
        iconGrid?.filterText = sender.stringValue
    }

    @objc private func saveClicked() {
        let iconName = iconGrid?.selectedIcon
        let color = colorGrid?.selectedColor ?? selectedColor
        onSave?(iconName, color)
        dismiss()
    }

    func dismiss() {
        if let contentView = panel?.contentView {
            for subview in contentView.subviews {
                if let field = subview as? NSTextField, field.target === self {
                    field.target = nil
                    field.action = nil
                }
                if let btn = subview as? NSButton, btn.target === self {
                    btn.target = nil
                    btn.action = nil
                }
            }
        }
        panel?.close()
        panel = nil
    }
}
