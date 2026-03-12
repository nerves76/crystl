// TerminalWindow.swift — Glass-style terminal window with tabs and controls
//
// Contains the main terminal UI:
//   - InsetFrostView: Decorative inner glow along window edges
//   - TerminalTab: Wraps a SwiftTerm LocalProcessTerminalView with metadata
//   - TabBarView: Custom-drawn tab bar with rename, close, add, settings gear
//   - TerminalWindowController: Manages the window, glass effect, tabs, and status bar
//
// Design: Apple Glass aesthetic using NSVisualEffectView (.hudWindow material),
// transparent terminal backgrounds, rounded corners, and subtle white borders.
// SwiftTerm's background is forced transparent via KVO on layer.backgroundColor.

import Cocoa
import SwiftTerm

// ── Inset Frost View ──

/// Draws a subtle white inner shadow around the window edges using even-odd
/// clipping. The view is non-interactive (hitTest returns nil) and floats
/// above all content as a decorative overlay.
class InsetFrostView: NSView {
    var cornerRadius: CGFloat = 12

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: inset, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.addRect(bounds.insetBy(dx: -20, dy: -20))
        ctx.clip(using: .evenOdd)

        ctx.setShadow(offset: .zero, blur: 16, color: NSColor(white: 1.0, alpha: 0.6).cgColor)
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.7).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }
}

// ── Terminal Tab ──

/// Wraps a SwiftTerm terminal view with tab metadata (title, cwd, color).
/// Title auto-updates from the working directory unless manually renamed.
class TerminalTab {
    let id = UUID()
    let terminalView: LocalProcessTerminalView
    var title: String = "shell"
    var hasCustomTitle: Bool = false
    var cwd: String
    let color: NSColor
    var historyLogger: CommandHistoryLogger?

    init(color: NSColor, shell: String = "/bin/zsh", cwd: String = NSHomeDirectory(), frame: NSRect = NSRect(x: 0, y: 0, width: 900, height: 536)) {
        self.color = color
        self.cwd = cwd
        self.title = (cwd as NSString).lastPathComponent
        self.terminalView = LocalProcessTerminalView(frame: frame)
        self.terminalView.autoresizingMask = [.width, .height]
    }

    func start() {
        let shell = "/bin/zsh"
        let shellIdiom = "-" + (shell as NSString).lastPathComponent
        let env = ShellIntegration.shared.environment()
        terminalView.startProcess(executable: shell, environment: env, execName: shellIdiom, currentDirectory: cwd)

        // Register OSC handler for command history after terminal starts
        let logger = CommandHistoryLogger(terminalView: terminalView)
        logger.registerHandler()
        historyLogger = logger
    }
}

// ── Glow Button ──

/// NSButton subclass that glows on hover via layer shadow animation.
class GlowButton: NSButton {
    private var trackingArea: NSTrackingArea?
    private let restAlpha: CGFloat = 0.75
    private let hoverAlpha: CGFloat = 1.0

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
            animator().alphaValue = hoverAlpha
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
            animator().alphaValue = restAlpha
        }
        let anim = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue = 0.6
        anim.toValue = 0
        anim.duration = 0.25
        layer?.shadowOpacity = 0
        layer?.add(anim, forKey: "glowOut")
    }
}

// ── Tab Bar View ──

/// Custom-drawn tab bar with: tab selection, close buttons, "+" to add,
/// double-click to rename (inline NSTextField), and a settings gear icon.
/// Tabs auto-size to fill available width (max 160px each).
class TabBarView: NSView, NSTextFieldDelegate {
    var tabs: [TerminalTab] = []
    var selectedIndex: Int = 0
    var onSelectTab: ((Int) -> Void)?
    var onAddTab: (() -> Void)?
    var onCloseTab: ((Int) -> Void)?
    var onRenameTab: ((Int, String) -> Void)?
    private let leftInset: CGFloat = 20
    private let tabSpacing: CGFloat = 2
    private var editField: NSTextField?
    private var editingIndex: Int = -1

    private func computeTabWidth() -> CGFloat {
        let available = bounds.width - leftInset - 20
        return min(160, available / max(CGFloat(tabs.count), 1))
    }

    private func tabOriginX(_ index: Int) -> CGFloat {
        return leftInset + CGFloat(index) * (computeTabWidth() + tabSpacing)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Separator line at bottom
        NSColor(white: 0.0, alpha: 0.08).setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: bounds.width, height: 0.5))

        let tabW = computeTabWidth()
        let h: CGFloat = 26
        let y: CGFloat = (bounds.height - h) / 2

        for (i, tab) in tabs.enumerated() {
            let x = tabOriginX(i)
            let rect = NSRect(x: x, y: y, width: tabW, height: h)
            let isSelected = (i == selectedIndex)

            if isSelected {
                // Subtle glass highlight for selected tab
                NSColor(white: 1.0, alpha: 0.12).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
            }

            // Title (skip if editing this tab)
            if i != editingIndex {
                let title = tab.title as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: isSelected ? .medium : .regular),
                    .foregroundColor: NSColor.white
                ]
                let sz = title.size(withAttributes: attrs)
                let textX = x + 12
                let textW = tabW - (tabs.count > 1 ? 32 : 24)
                let textRect = NSRect(x: textX, y: rect.midY - sz.height / 2, width: textW, height: sz.height)
                title.draw(with: textRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attrs)
            }

            // Close button (only when multiple tabs)
            if tabs.count > 1 {
                let sym = "\u{2715}" as NSString  // ✕
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
        let plusX = tabOriginX(tabs.count) + 8
        let plusAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .ultraLight),
            .foregroundColor: NSColor.white
        ]
        let plusStr = "+" as NSString
        let plusSize = plusStr.size(withAttributes: plusAttrs)
        plusStr.draw(at: NSPoint(x: plusX, y: (bounds.height - plusSize.height) / 2), withAttributes: plusAttrs)

    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let tabW = computeTabWidth()


        // Double-click to rename
        if event.clickCount == 2 {
            for i in 0..<tabs.count {
                let x = tabOriginX(i)
                if loc.x >= x && loc.x < x + tabW {
                    beginEditing(index: i)
                    return
                }
            }
        }

        // "+" button
        let plusX = tabOriginX(tabs.count) + 8
        if loc.x >= plusX - 4 && loc.x <= plusX + 28 {
            onAddTab?()
            return
        }

        for i in 0..<tabs.count {
            let x = tabOriginX(i)
            if loc.x >= x && loc.x < x + tabW {
                if tabs.count > 1 && loc.x >= x + tabW - 20 {
                    onCloseTab?(i)
                    return
                }
                onSelectTab?(i)
                return
            }
        }
    }

    func beginEditing(index: Int) {
        endEditing()
        editingIndex = index
        let tabW = computeTabWidth()
        let x = tabOriginX(index)
        let h: CGFloat = 26
        let y: CGFloat = (bounds.height - h) / 2

        let field = NSTextField(frame: NSRect(x: x + 8, y: y + 2, width: tabW - 20, height: h - 4))
        field.stringValue = tabs[index].title
        field.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)
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
        guard let field = editField, editingIndex >= 0, editingIndex < tabs.count else {
            editField?.removeFromSuperview()
            editField = nil
            editingIndex = -1
            return
        }
        let newTitle = field.stringValue.trimmingCharacters(in: .whitespaces)
        if !newTitle.isEmpty {
            onRenameTab?(editingIndex, newTitle)
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

// ── Terminal Window Controller ──

/// Manages the main Crystl window: glass background, tab bar, terminal views,
/// and the status bar with approval mode buttons and Claude mode dropdown.
///
/// Layout (top to bottom):
///   - macOS titlebar (48px, transparent, with invisible toolbar for traffic light spacing)
///   - Tab bar (40px, custom drawn)
///   - Terminal content area (fills remaining space, padded 20px sides / 24px top+bottom)
///   - Status bar (64px) with APPROVAL buttons, Pause, and CLAUDE MODE dropdown
///
/// The terminal background is forced transparent so the glass effect shows through.
/// SwiftTerm resets layer.backgroundColor during setup, so we use KVO to override it.
class TerminalWindowController: NSObject, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    var window: NSWindow!
    var tabBar: TabBarView!
    var onProcessFinished: ((String, String) -> Void)?  // (tabTitle, cwd)
    var onModeChanged: ((String) -> Void)?  // approval mode
    var onClaudeModeChanged: ((String) -> Void)?  // claude mode
    var onPauseToggled: ((Bool) -> Void)?
    var onTabAdded: ((TerminalTab) -> Void)?
    var onTabRemoved: ((UUID) -> Void)?
    var onTabSelected: ((UUID) -> Void)?
    var onTabUpdated: ((UUID, String, String) -> Void)?  // (tabId, title, cwd)
    var contentArea: NSView!
    var projectLabel: NSTextField!
    var claudeModePopup: NSPopUpButton!
    var tabs: [TerminalTab] = []
    var selectedIndex: Int = 0
    private var colorIndex = 0
    private var scrollerObservers: [UUID: [NSKeyValueObservation]] = [:]
    private var backgroundObservers: [UUID: NSKeyValueObservation] = [:]
    private var currentMode: String = "manual"
    private var currentClaudeMode: String = "default"
    private var isPaused: Bool = false
    private var directoryPicker: DirectoryPicker?
    private var settingsButton: NSButton?

    func setup() {
        let windowWidth: CGFloat = 900
        let windowHeight: CGFloat = 600
        let tabBarHeight: CGFloat = 40
        let titleBarHeight: CGFloat = 48
        let statusBarHeight: CGFloat = 64
        let termPadX: CGFloat = 20
        let termPadBottom: CGFloat = 24
        let termPadTop: CGFloat = 24

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Crystl"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 480, height: 320)
        window.center()

        // Invisible toolbar gives the titlebar more height, pushing traffic lights down
        let toolbar = NSToolbar(identifier: "crystl")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        // Container with rounded corners and soft border
        let container = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.7).cgColor
        window.contentView = container

        // Glass background — fullScreenUI gives the warm Apple frosted look
        let glass = NSVisualEffectView(frame: container.bounds)
        glass.material = .hudWindow
        glass.alphaValue = 0.85
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        glass.appearance = NSAppearance(named: .darkAqua)
        container.addSubview(glass)

        // Tab bar
        let tabBarY = windowHeight - tabBarHeight - titleBarHeight
        tabBar = TabBarView(frame: NSRect(x: 0, y: tabBarY, width: windowWidth, height: tabBarHeight))
        tabBar.autoresizingMask = [.width, .minYMargin]
        tabBar.onSelectTab = { [weak self] idx in self?.selectTab(idx) }
        tabBar.onAddTab = { [weak self] in self?.addTab(showPicker: true) }
        tabBar.onCloseTab = { [weak self] idx in self?.closeTab(idx) }
        tabBar.onRenameTab = { [weak self] idx, name in self?.renameTab(idx, name: name) }
        container.addSubview(tabBar)

        // Crystal icon settings button — titlebar area, top right
        let iconSize: CGFloat = 28
        let iconPadRight: CGFloat = 14
        let iconPadTop: CGFloat = 10
        let settingsBtn = GlowButton(frame: NSRect(
            x: windowWidth - iconSize - iconPadRight,
            y: windowHeight - iconSize - iconPadTop,
            width: iconSize,
            height: iconSize
        ))
        settingsBtn.autoresizingMask = [.minXMargin, .minYMargin]
        settingsBtn.isBordered = false
        settingsBtn.bezelStyle = .inline
        settingsBtn.target = self
        settingsBtn.action = #selector(settingsButtonClicked)
        if let path = Bundle.main.path(forResource: "crystl-white", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: iconSize, height: iconSize)
            settingsBtn.image = img
            settingsBtn.imageScaling = .scaleProportionallyDown
        }
        settingsBtn.alphaValue = 0.85
        settingsBtn.toolTip = "Settings"
        self.settingsButton = settingsBtn
        container.addSubview(settingsBtn)

        // Status bar at bottom
        let statusBar = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: statusBarHeight))
        statusBar.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(statusBar)

        // Separator above status bar
        let sep = NSView(frame: NSRect(x: 0, y: statusBarHeight - 0.5, width: windowWidth, height: 0.5))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
        sep.autoresizingMask = [.width]
        statusBar.addSubview(sep)

        let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let labelColor = NSColor(white: 1.0, alpha: 0.6)

        // ── Project name (left) ──
        projectLabel = NSTextField(labelWithString: "")
        projectLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        projectLabel.textColor = NSColor(white: 1.0, alpha: 0.7)
        projectLabel.alignment = .left
        projectLabel.lineBreakMode = .byTruncatingMiddle
        projectLabel.frame = NSRect(x: 24, y: 24, width: windowWidth * 0.6, height: 16)
        projectLabel.autoresizingMask = [.width]
        statusBar.addSubview(projectLabel)

        // ── Claude Mode section (right) ──
        let claudeLabel = NSTextField(labelWithString: "CLAUDE MODE")
        claudeLabel.font = labelFont
        claudeLabel.textColor = labelColor
        claudeLabel.frame = NSRect(x: windowWidth - 154, y: 48, width: 80, height: 12)
        claudeLabel.autoresizingMask = [.minXMargin]
        statusBar.addSubview(claudeLabel)

        let popupBg = NSView(frame: NSRect(x: windowWidth - 148, y: 20, width: 124, height: 18))
        popupBg.wantsLayer = true
        popupBg.layer?.cornerRadius = 6
        popupBg.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        popupBg.layer?.borderWidth = 0.5
        popupBg.layer?.borderColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        popupBg.autoresizingMask = [.minXMargin]
        statusBar.addSubview(popupBg)

        claudeModePopup = NSPopUpButton(frame: NSRect(x: windowWidth - 147, y: 18, width: 122, height: 22))
        claudeModePopup.addItems(withTitles: ["plan", "default", "acceptEdits", "bypassPermissions", "auto"])
        claudeModePopup.selectItem(withTitle: "default")
        claudeModePopup.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        claudeModePopup.controlSize = .small
        claudeModePopup.isBordered = false
        claudeModePopup.isTransparent = false
        claudeModePopup.wantsLayer = true
        claudeModePopup.layer?.backgroundColor = NSColor.clear.cgColor
        claudeModePopup.appearance = NSAppearance(named: .darkAqua)
        (claudeModePopup.cell as? NSButtonCell)?.backgroundColor = .clear
        claudeModePopup.target = self
        claudeModePopup.action = #selector(claudeModeChanged(_:))
        (claudeModePopup.cell as? NSPopUpButtonCell)?.arrowPosition = .arrowAtBottom
        claudeModePopup.autoresizingMask = [.minXMargin]
        statusBar.addSubview(claudeModePopup)

        // Content area — inset from edges for padding
        let contentHeight = windowHeight - tabBarHeight - titleBarHeight - statusBarHeight
        contentArea = NSView(frame: NSRect(x: termPadX, y: statusBarHeight + termPadBottom, width: windowWidth - termPadX * 2, height: contentHeight - termPadBottom - termPadTop))
        contentArea.autoresizingMask = [.width, .height]
        container.addSubview(contentArea)


        addTab(showPicker: true)
        animateWindowOpen(container: container)
    }

    /// Liquid crystal open animation: the window materializes from a bright
    /// central point, expanding smoothly like liquid filling glass. A prismatic
    /// shimmer flashes across the surface as it forms, then settles into the
    /// frosted glass resting state.
    private func animateWindowOpen(container: NSView) {
        guard let layer = container.layer else {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let duration: CFTimeInterval = 0.9
        // Smooth deceleration — fast start, gentle settle (no bounce)
        let fluidTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        // Start invisible
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        // Anchor to center for scale
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)

        // ── Scale: liquid expansion from center ──
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.0
        scale.toValue = 1.0
        scale.duration = duration
        scale.timingFunction = fluidTiming

        // ── Corner radius: circle → rounded rect ──
        let corners = CABasicAnimation(keyPath: "cornerRadius")
        corners.fromValue = container.bounds.width / 2
        corners.toValue = 16
        corners.duration = duration * 0.7
        corners.timingFunction = fluidTiming

        // ── Opacity: materialise ──
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = duration * 0.4
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // ── Border glow: bright flash that fades ──
        let borderColor = CABasicAnimation(keyPath: "borderColor")
        borderColor.fromValue = NSColor(white: 1.0, alpha: 1.0).cgColor
        borderColor.toValue = NSColor(white: 1.0, alpha: 0.7).cgColor
        borderColor.duration = duration * 1.2
        borderColor.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let borderWidth = CABasicAnimation(keyPath: "borderWidth")
        borderWidth.fromValue = 2.0
        borderWidth.toValue = 0.5
        borderWidth.duration = duration * 1.2
        borderWidth.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // ── Gaussian blur: start soft, sharpen as crystal forms ──
        if let blur = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 0.0]) {
            layer.filters = [blur]
            layer.setValue(0, forKeyPath: "filters.gaussianBlur.inputRadius")

            let blurAnim = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            blurAnim.fromValue = 12.0
            blurAnim.toValue = 0.0
            blurAnim.duration = duration * 0.8
            blurAnim.timingFunction = fluidTiming
            layer.add(blurAnim, forKey: "openBlur")
        }

        // Set final values
        layer.transform = CATransform3DIdentity
        layer.cornerRadius = 16
        layer.opacity = 1.0
        layer.borderWidth = 0.5
        layer.borderColor = NSColor(white: 1.0, alpha: 0.7).cgColor

        // Run main animations
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.window.alphaValue = 1.0
            layer.filters = nil
        }
        layer.add(scale, forKey: "openScale")
        layer.add(corners, forKey: "openCorners")
        layer.add(opacity, forKey: "openOpacity")
        layer.add(borderColor, forKey: "openBorderColor")
        layer.add(borderWidth, forKey: "openBorderWidth")
        CATransaction.commit()

        window.alphaValue = 1.0

        // ── Shimmer pass: sweeps across after window has mostly formed ──
        addShimmerSweep(
            to: layer, bounds: container.bounds, cornerRadius: 16,
            delay: duration * 0.25,
            fadeInDuration: 0.15, sweepDuration: 0.5, fadeOutDuration: 0.3
        )
    }

    func nextColor() -> NSColor {
        let color = sessionColors[colorIndex % sessionColors.count]
        colorIndex += 1
        return color
    }

    func addTab(cwd: String = NSHomeDirectory(), showPicker: Bool = false) {
        let tab = TerminalTab(color: nextColor(), cwd: cwd, frame: contentArea.bounds)
        tab.terminalView.processDelegate = self
        tabs.append(tab)

        configureTerminalAppearance(tab.terminalView, tabId: tab.id)

        // Terminal fills the content area (which is already inset)
        tab.terminalView.frame = contentArea.bounds
        tab.terminalView.isHidden = true
        contentArea.addSubview(tab.terminalView)

        selectTab(tabs.count - 1)
        updateTabBar()
        onTabAdded?(tab)

        DispatchQueue.main.async {
            tab.start()
            self.hideScroller(in: tab.terminalView, tabId: tab.id)

            // Push prompt to bottom after shell has started and terminal knows its size
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                let rows = tab.terminalView.getTerminal().rows
                if rows > 2 {
                    tab.terminalView.feed(text: String(repeating: "\n", count: rows - 2))
                }
            }

            // Show directory picker for new tabs
            if showPicker {
                self.showDirectoryPicker(for: tab)
            }
        }
    }

    func showDirectoryPicker(for tab: TerminalTab) {
        let projDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
        let dir = projDir.isEmpty ? (NSHomeDirectory() + "/Projects") : projDir

        let picker = DirectoryPicker()
        picker.onSelect = { [weak self] path in
            // cd to the selected directory
            tab.terminalView.send(txt: "cd \(self?.shellEscape(path) ?? path) && clear\n")
            tab.cwd = path
            tab.title = (path as NSString).lastPathComponent
            self?.updateTabBar()
            self?.updateWindowTitle()
            self?.onTabUpdated?(tab.id, tab.title, tab.cwd)
            self?.directoryPicker = nil
            self?.window.makeFirstResponder(tab.terminalView)
        }
        picker.onDismiss = { [weak self] in
            self?.directoryPicker = nil
            self?.window.makeFirstResponder(tab.terminalView)
        }
        picker.show(in: contentArea, projectsDir: dir)
        directoryPicker = picker
    }

    /// Escapes a path for safe use in shell commands.
    private func shellEscape(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func configureTerminalAppearance(_ tv: LocalProcessTerminalView, tabId: UUID) {
        tv.nativeForegroundColor = NSColor.white
        tv.nativeBackgroundColor = NSColor(white: 1.0, alpha: 0.001)

        let fontSize: CGFloat = 13
        if let mono = NSFont(name: "SF Mono", size: fontSize) ?? NSFont(name: "Menlo", size: fontSize) {
            tv.font = mono
        }

        tv.caretColor = NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
        tv.alphaValue = 0.9
        makeTerminalTransparent(tv, tabId: tabId)
    }

    var onSettingsChanged: (([String: Any]) -> Void)?
    private var settingsView: NSView?
    private var isShowingSettings = false

    @objc func settingsButtonClicked() {
        showSettingsPopover()
    }

    func showSettingsPopover() {
        if isShowingSettings {
            flipToTerminal()
        } else {
            flipToSettings()
        }
    }

    private func buildSettingsView() -> NSView {
        guard let container = window.contentView else { return NSView() }
        let bounds = container.bounds

        let view = NSView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true

        // Glass background
        let glass = NSVisualEffectView(frame: bounds)
        glass.material = .hudWindow
        glass.alphaValue = 0.85
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        glass.appearance = NSAppearance(named: .darkAqua)
        view.addSubview(glass)

        let centerX = bounds.width / 2
        let cardWidth: CGFloat = 320
        let cardLeft = centerX - cardWidth / 2
        let labelColor = NSColor(white: 1.0, alpha: 0.6)
        let fieldBg = NSColor(white: 1.0, alpha: 0.12)

        // Title
        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.alignment = .center
        title.frame = NSRect(x: cardLeft, y: bounds.height - 90, width: cardWidth, height: 28)
        title.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(title)

        var y = bounds.height - 130

        // ── Projects Directory ──
        let projLabel = NSTextField(labelWithString: "PROJECTS DIRECTORY")
        projLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        projLabel.textColor = labelColor
        projLabel.frame = NSRect(x: cardLeft, y: y, width: cardWidth, height: 14)
        projLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(projLabel)
        y -= 26

        let projDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
        let projDisplay = projDir.isEmpty ? "~/Projects" : (projDir as NSString).abbreviatingWithTildeInPath
        let projField = NSTextField(string: projDisplay)
        projField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        projField.textColor = .white
        projField.backgroundColor = fieldBg
        projField.isBordered = false
        projField.isBezeled = false
        projField.drawsBackground = true
        projField.isEditable = false
        projField.wantsLayer = true
        projField.layer?.cornerRadius = 6
        projField.frame = NSRect(x: cardLeft, y: y, width: cardWidth - 70, height: 24)
        projField.identifier = NSUserInterfaceItemIdentifier("projectsDirField")
        projField.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(projField)

        let browseBtn = NSButton(frame: NSRect(x: cardLeft + cardWidth - 64, y: y, width: 64, height: 24))
        browseBtn.title = "Browse"
        browseBtn.bezelStyle = .rounded
        browseBtn.isBordered = false
        browseBtn.wantsLayer = true
        browseBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        browseBtn.layer?.cornerRadius = 6
        browseBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        browseBtn.contentTintColor = .white
        browseBtn.target = self
        browseBtn.action = #selector(browseProjectsDir(_:))
        browseBtn.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(browseBtn)
        y -= 36

        // ── Effort Level ──
        let effortLabel = NSTextField(labelWithString: "EFFORT LEVEL")
        effortLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        effortLabel.textColor = labelColor
        effortLabel.frame = NSRect(x: cardLeft, y: y, width: cardWidth, height: 14)
        effortLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(effortLabel)
        y -= 26

        let effortPop = NSPopUpButton(frame: NSRect(x: cardLeft, y: y, width: cardWidth, height: 24))
        effortPop.addItems(withTitles: ["low", "medium", "high"])
        effortPop.selectItem(withTitle: "high")
        effortPop.font = NSFont.systemFont(ofSize: 12)
        effortPop.appearance = NSAppearance(named: .darkAqua)
        effortPop.target = self
        effortPop.action = #selector(effortChanged(_:))
        effortPop.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(effortPop)
        y -= 36

        // ── Default Mode ──
        let modeLabel = NSTextField(labelWithString: "DEFAULT MODE")
        modeLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        modeLabel.textColor = labelColor
        modeLabel.frame = NSRect(x: cardLeft, y: y, width: cardWidth, height: 14)
        modeLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(modeLabel)
        y -= 26

        let modePop = NSPopUpButton(frame: NSRect(x: cardLeft, y: y, width: cardWidth, height: 24))
        modePop.addItems(withTitles: ["plan", "default", "acceptEdits", "bypassPermissions"])
        modePop.font = NSFont.systemFont(ofSize: 12)
        modePop.appearance = NSAppearance(named: .darkAqua)
        modePop.target = self
        modePop.action = #selector(defaultModeChanged(_:))
        modePop.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(modePop)
        y -= 36

        // ── Bridge Port ──
        let portLabel = NSTextField(labelWithString: "BRIDGE PORT")
        portLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        portLabel.textColor = labelColor
        portLabel.frame = NSRect(x: cardLeft, y: y, width: cardWidth, height: 14)
        portLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(portLabel)
        y -= 26

        let portField = NSTextField(string: "19280")
        portField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        portField.textColor = NSColor(white: 1.0, alpha: 0.5)
        portField.backgroundColor = fieldBg
        portField.isBordered = false
        portField.isBezeled = false
        portField.drawsBackground = true
        portField.isEditable = false
        portField.wantsLayer = true
        portField.layer?.cornerRadius = 6
        portField.frame = NSRect(x: cardLeft, y: y, width: cardWidth, height: 24)
        portField.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(portField)
        y -= 36

        // ── Open settings.json ──
        let openBtn = NSButton(frame: NSRect(x: cardLeft, y: y, width: cardWidth, height: 30))
        openBtn.title = "Open Claude settings.json"
        openBtn.bezelStyle = .rounded
        openBtn.isBordered = false
        openBtn.wantsLayer = true
        openBtn.layer?.backgroundColor = fieldBg.cgColor
        openBtn.layer?.cornerRadius = 8
        openBtn.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        openBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        openBtn.target = self
        openBtn.action = #selector(openSettingsFile)
        openBtn.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.addSubview(openBtn)

        // Crystal icon — top right, flips back to terminal
        let iconSize: CGFloat = 28
        let crystalBtn = GlowButton(frame: NSRect(
            x: bounds.width - iconSize - 14,
            y: bounds.height - iconSize - 18,
            width: iconSize,
            height: iconSize
        ))
        crystalBtn.autoresizingMask = [.minXMargin, .minYMargin]
        crystalBtn.isBordered = false
        crystalBtn.bezelStyle = .inline
        crystalBtn.target = self
        crystalBtn.action = #selector(flipBackClicked)
        crystalBtn.keyEquivalent = "\u{1b}" // Escape
        if let path = Bundle.main.path(forResource: "crystl-white", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: iconSize, height: iconSize)
            crystalBtn.image = img
            crystalBtn.imageScaling = .scaleProportionallyDown
        }
        crystalBtn.alphaValue = 0.75
        crystalBtn.toolTip = "Back to terminal"
        view.addSubview(crystalBtn)

        return view
    }

    private func flipToSettings() {
        guard let container = window.contentView else { return }
        isShowingSettings = true

        let settings = buildSettingsView()
        settings.frame = container.bounds
        settingsView = settings

        let terminalViews = container.subviews.map { $0 }

        // Hide the static border/corner during flip
        container.layer?.borderWidth = 0
        container.layer?.cornerRadius = 0

        let transition = CATransition()
        transition.duration = 0.6
        transition.type = CATransitionType(rawValue: "flip")
        transition.subtype = .fromRight
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.wantsLayer = true
        container.layer?.add(transition, forKey: "settingsFlip")

        for sub in terminalViews { sub.isHidden = true }
        container.addSubview(settings)

        // Restore border after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            container.layer?.borderWidth = 0.5
            container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.7).cgColor
            container.layer?.cornerRadius = 16
        }
    }

    private func flipToTerminal() {
        guard let container = window.contentView, let settings = settingsView else { return }
        isShowingSettings = false

        // Hide the static border/corner during flip
        container.layer?.borderWidth = 0
        container.layer?.cornerRadius = 0

        let transition = CATransition()
        transition.duration = 0.6
        transition.type = CATransitionType(rawValue: "flip")
        transition.subtype = .fromLeft
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.wantsLayer = true
        container.layer?.add(transition, forKey: "settingsFlip")

        settings.removeFromSuperview()
        self.settingsView = nil
        for sub in container.subviews { sub.isHidden = false }

        if selectedIndex < tabs.count {
            window.makeFirstResponder(tabs[selectedIndex].terminalView)
        }

        // Restore border after animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            container.layer?.borderWidth = 0.5
            container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.7).cgColor
            container.layer?.cornerRadius = 16
        }
    }

    @objc func flipBackClicked() {
        flipToTerminal()
    }

    @objc func effortChanged(_ sender: NSPopUpButton) {
        guard let level = sender.selectedItem?.title else { return }
        onSettingsChanged?(["effortLevel": level])
    }

    @objc func defaultModeChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.title else { return }
        onSettingsChanged?(["defaultMode": mode])
    }

    @objc func openSettingsFile() {
        let path = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func browseProjectsDir(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select your projects directory"

        let currentDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? (NSHomeDirectory() + "/Projects")
        panel.directoryURL = URL(fileURLWithPath: currentDir)

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let path = url.path
            UserDefaults.standard.set(path, forKey: "projectsDirectory")

            // Update the field in the settings view
            if let settingsView = self?.settingsView {
                func findField(in view: NSView) -> NSTextField? {
                    if let tf = view as? NSTextField, tf.identifier?.rawValue == "projectsDirField" { return tf }
                    for sub in view.subviews {
                        if let found = findField(in: sub) { return found }
                    }
                    return nil
                }
                findField(in: settingsView)?.stringValue = (path as NSString).abbreviatingWithTildeInPath
            }
        }
    }

    // Accessors for rail menu
    var currentModeValue: String { currentMode }
    var currentClaudeModeValue: String { currentClaudeMode }
    var isPausedValue: Bool { isPaused }

    func setMode(_ mode: String) {
        currentMode = mode
        onModeChanged?(mode)
    }

    func togglePause() {
        isPaused = !isPaused
        onPauseToggled?(isPaused)
    }

    @objc func claudeModeChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.title else { return }
        currentClaudeMode = mode
        onClaudeModeChanged?(mode)
    }

    func setClaudeMode(_ mode: String) {
        currentClaudeMode = mode
        claudeModePopup.selectItem(withTitle: mode)
        onClaudeModeChanged?(mode)
    }

    func syncSettings(mode: String, paused: Bool, claudeMode: String? = nil) {
        currentMode = mode
        isPaused = paused
        if let cm = claudeMode {
            currentClaudeMode = cm
            claudeModePopup.selectItem(withTitle: cm)
        }
    }

    func renameTab(_ index: Int, name: String) {
        guard index >= 0 && index < tabs.count else { return }
        tabs[index].title = name
        tabs[index].hasCustomTitle = true
        updateTabBar()
        updateWindowTitle()
    }

    /// Hides the terminal scrollbar and watches for SwiftTerm re-showing it.
    /// SwiftTerm's scroller is private, so we find it by type and use KVO.
    func hideScroller(in tv: LocalProcessTerminalView, tabId: UUID) {
        for sub in tv.subviews {
            if sub is NSScroller {
                sub.isHidden = true
                // Observe in case SwiftTerm re-shows it
                let obs = sub.observe(\.isHidden, options: [.new]) { scroller, change in
                    if change.newValue == false {
                        scroller.isHidden = true
                    }
                }
                scrollerObservers[tabId, default: []].append(obs)
            }
        }
    }

    /// Forces the terminal layer transparent and adds a KVO observer to
    /// prevent SwiftTerm from resetting it during setupOptions().
    func makeTerminalTransparent(_ tv: LocalProcessTerminalView, tabId: UUID) {
        tv.wantsLayer = true
        tv.layer?.isOpaque = false
        tv.layer?.backgroundColor = CGColor(gray: 0, alpha: 0)

        // Also clear any scroll view backgrounds inside SwiftTerm
        for sub in tv.subviews {
            if let scrollView = sub as? NSScrollView {
                scrollView.drawsBackground = false
                scrollView.backgroundColor = .clear
                scrollView.contentView.drawsBackground = false
                scrollView.wantsLayer = true
                scrollView.layer?.backgroundColor = CGColor.clear
                scrollView.contentView.wantsLayer = true
                scrollView.contentView.layer?.backgroundColor = CGColor.clear
            }
            sub.wantsLayer = true
            sub.layer?.backgroundColor = CGColor.clear
        }

        if let layer = tv.layer {
            let obs = layer.observe(\.backgroundColor, options: [.new]) { layer, _ in
                let alpha = layer.backgroundColor?.alpha ?? 1.0
                if alpha > 0.01 {
                    layer.backgroundColor = CGColor(gray: 0, alpha: 0)
                }
            }
            backgroundObservers[tabId] = obs
        }
    }

    func selectTab(_ index: Int) {
        guard index >= 0 && index < tabs.count else { return }

        if selectedIndex < tabs.count {
            tabs[selectedIndex].terminalView.isHidden = true
        }

        selectedIndex = index

        let tab = tabs[index]
        tab.terminalView.isHidden = false
        tab.terminalView.frame = contentArea.bounds
        window.makeFirstResponder(tab.terminalView)

        updateTabBar()
        updateWindowTitle()
        onTabSelected?(tab.id)
    }

    func closeTab(_ index: Int) {
        guard tabs.count > 1 && index < tabs.count else { return }

        let tab = tabs[index]
        let tabId = tab.id

        // Remove KVO observers for this tab
        backgroundObservers.removeValue(forKey: tabId)
        scrollerObservers.removeValue(forKey: tabId)

        tab.terminalView.removeFromSuperview()
        tabs.remove(at: index)
        onTabRemoved?(tabId)

        if selectedIndex >= tabs.count {
            selectedIndex = tabs.count - 1
        } else if selectedIndex > index {
            selectedIndex -= 1
        }

        selectTab(selectedIndex)
        updateTabBar()
    }

    func updateTabBar() {
        tabBar.tabs = tabs
        tabBar.selectedIndex = selectedIndex
        tabBar.needsDisplay = true
    }

    func updateWindowTitle() {
        if selectedIndex < tabs.count {
            let tab = tabs[selectedIndex]
            window.title = "Crystl \u{2014} \(tab.title)"
            let cwdDisplay = (tab.cwd as NSString).abbreviatingWithTildeInPath
            projectLabel.stringValue = "\(tab.title)  \u{2022}  \(cwdDisplay)"
        }
    }

    // ── LocalProcessTerminalViewDelegate ──

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let tab = self.tabs.first(where: { $0.terminalView === source }) {
                tab.title = title
                self.updateTabBar()
                self.updateWindowTitle()
            }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let dir = directory,
               let lpv = source as? LocalProcessTerminalView,
               let tab = self.tabs.first(where: { $0.terminalView === lpv }) {
                tab.cwd = dir
                if !tab.hasCustomTitle {
                    tab.title = (dir as NSString).lastPathComponent
                    self.updateTabBar()
                    self.updateWindowTitle()
                }
                self.onTabUpdated?(tab.id, tab.title, tab.cwd)
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let lpv = source as? LocalProcessTerminalView,
               let idx = self.tabs.firstIndex(where: { $0.terminalView === lpv }) {
                let tab = self.tabs[idx]
                self.onProcessFinished?(tab.title, tab.cwd)

                if self.tabs.count > 1 {
                    self.closeTab(idx)
                } else {
                    tab.start()
                }
            }
        }
    }
}
