// SettingsView.swift — Settings panel with sidebar navigation
//
// Contains:
//   - SettingsPage: enum of navigation pages
//   - GlassToggle: iOS-style toggle switch
//   - VerticallyCenteredTextFieldCell: text field cell with vertical centering
//   - buildSettingsView(): sidebar + content layout
//   - Per-page builders: General, Claude, Codex, MCP, Starters, API Keys, License
//   - Settings action handlers
//   - StarterEditorPanel: floating editor for starter files
//   - CodexConfig: reads/writes ~/.codex/config.toml
//   - DemoRunner: orchestrates the Crystl demo sequence

import Cocoa

// ── Settings Page ──

/// Pages available in the settings sidebar.
enum SettingsPage: String, CaseIterable {
    case general = "General"
    case claude = "Claude"
    case codex = "Codex"
    case mcpServers = "MCP Servers"
    case starters = "Starter Files"
    case apiKeys = "API Keys"
    case license = "License"
}

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

// ── Settings Builder ──

extension TerminalWindowController {

    func flipToSettings() {
        guard let container = window.contentView else { return }
        isShowingSettings = true

        let settings = buildSettingsView()
        settings.frame = container.bounds
        settingsView = settings

        let terminalViews = container.subviews.filter {
            !($0 is NSVisualEffectView) && !($0 is CharcoalBackingView)
        }

        container.layer?.cornerRadius = 0

        let transition = CATransition()
        transition.duration = 0.6
        transition.type = CATransitionType(rawValue: "flip")
        transition.subtype = .fromRight
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.wantsLayer = true
        container.layer?.add(transition, forKey: "settingsFlip")

        for sub in terminalViews {
            sub.isHidden = true
            sub.layer?.opacity = 0
        }
        container.addSubview(settings)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            container.layer?.cornerRadius = 16
        }
    }

    func flipToTerminal() {
        guard let container = window.contentView, let settings = settingsView else { return }
        isShowingSettings = false

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
        for sub in container.subviews where !(sub is NSVisualEffectView) && !(sub is CharcoalBackingView) {
            sub.isHidden = false
            sub.layer?.opacity = 1
        }

        if let session = selectedSession {
            window.makeFirstResponder(session.terminalView)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            container.layer?.cornerRadius = 16
        }
    }

    @objc func flipBackClicked() { flipToTerminal() }

    // MARK: - Main Settings View

    func buildSettingsView() -> NSView {
        guard let container = window.contentView else { return NSView() }
        let bounds = container.bounds

        let view = NSView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true

        let glass = NSVisualEffectView(frame: bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        glass.appearance = NSAppearance(named: .darkAqua)
        view.addSubview(glass)

        // ── Layout constants ──
        let sidebarW: CGFloat = 200
        let sidebarTopPad: CGFloat = 52   // sidebar clears traffic lights
        let contentTopPad: CGFloat = 100  // content area below title

        // ── Title ──
        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: sidebarW + 32, y: bounds.height - contentTopPad + 10, width: bounds.width - sidebarW - 32, height: 28)
        title.autoresizingMask = [.width, .minYMargin]
        view.addSubview(title)

        // ── Sidebar ──
        let sidebarFrame = NSRect(x: 0, y: 0, width: sidebarW, height: bounds.height - sidebarTopPad)
        let sidebar = NSView(frame: sidebarFrame)
        sidebar.autoresizingMask = [.height]

        var navY = sidebarFrame.height - 12
        let itemH: CGFloat = 30

        for page in SettingsPage.allCases {
            navY -= itemH
            let isSelected = page == settingsSelectedPage

            if isSelected {
                let bg = NSView(frame: NSRect(x: 12, y: navY, width: sidebarW - 24, height: itemH))
                bg.wantsLayer = true
                bg.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
                bg.layer?.cornerRadius = 6
                sidebar.addSubview(bg)
            }

            let item = NSButton(frame: NSRect(x: 20, y: navY, width: sidebarW - 32, height: itemH))
            item.title = page.rawValue
            item.bezelStyle = .inline
            item.isBordered = false
            item.font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
            item.contentTintColor = isSelected ? .white : NSColor(white: 1.0, alpha: 0.6)
            item.alignment = .left

            item.identifier = NSUserInterfaceItemIdentifier("settingsNav:\(page.rawValue)")
            item.target = self
            item.action = #selector(settingsNavClicked(_:))
            sidebar.addSubview(item)
        }

        view.addSubview(sidebar)

        // ── Separator line ──
        let sep = NSView(frame: NSRect(x: sidebarW, y: 0, width: 1, height: bounds.height - sidebarTopPad))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        sep.autoresizingMask = [.height]
        view.addSubview(sep)

        // ── Content area (scrollable) ──
        let contentFrame = NSRect(x: sidebarW + 1, y: 0, width: bounds.width - sidebarW - 1, height: bounds.height - contentTopPad)
        let contentScroll = NSScrollView(frame: contentFrame)
        contentScroll.hasVerticalScroller = true
        contentScroll.hasHorizontalScroller = false
        contentScroll.autohidesScrollers = true
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentScroll.autoresizingMask = [.width, .height]
        contentScroll.scrollerStyle = .overlay

        let pageContent = buildPage(settingsSelectedPage, width: contentFrame.width, minHeight: contentFrame.height)
        contentScroll.documentView = pageContent
        view.addSubview(contentScroll)

        // Scroll to top (non-flipped: top = max y)
        if let docView = contentScroll.documentView {
            let topY = max(0, docView.frame.height - contentScroll.contentView.bounds.height)
            contentScroll.contentView.scroll(to: NSPoint(x: 0, y: topY))
        }

        // ── Crystal icon — top right, flips back ──
        let iconSize: CGFloat = 28
        let crystalBtn = GlowButton(frame: NSRect(
            x: bounds.width - iconSize - 14,
            y: bounds.height - iconSize - 18,
            width: iconSize, height: iconSize
        ))
        crystalBtn.autoresizingMask = [.minXMargin, .minYMargin]
        crystalBtn.isBordered = false
        crystalBtn.bezelStyle = .inline
        crystalBtn.target = self
        crystalBtn.action = #selector(flipBackClicked)
        crystalBtn.keyEquivalent = "\u{1b}"
        if let path = Bundle.main.path(forResource: "crystl-white-28@2x", ofType: "png")
            ?? Bundle.main.path(forResource: "crystl-white", ofType: "png"),
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

    // MARK: - Page Router

    private func buildPage(_ page: SettingsPage, width: CGFloat, minHeight: CGFloat = 0) -> NSView {
        switch page {
        case .general:    return buildGeneralPage(width: width, minH: minHeight)
        case .claude:     return buildClaudePage(width: width, minH: minHeight)
        case .codex:      return buildCodexPage(width: width, minH: minHeight)
        case .mcpServers: return buildMCPPage(width: width, minH: minHeight)
        case .starters:   return buildStartersPage(width: width, minH: minHeight)
        case .apiKeys:    return buildAPIKeysPage(width: width, minH: minHeight)
        case .license:    return buildLicensePage(width: width, minH: minHeight)
        }
    }

    // MARK: - Shared Layout Helpers

    private var settingsColWidth: CGFloat { 360 }
    private var settingsLabelColor: NSColor { NSColor(white: 1.0, alpha: 0.7) }
    private var settingsFieldBg: NSColor { NSColor(white: 1.0, alpha: 0.12) }

    /// Creates a doc view with a generous initial height. Call `finalizeDocView` when done.
    private func makeDocView(width: CGFloat) -> (NSView, CGFloat, CGFloat) {
        let docH: CGFloat = 2000  // generous; trimmed by finalizeDocView
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: docH))
        let leftX: CGFloat = 32
        let startY = docH - 24
        return (docView, leftX, startY)
    }

    /// Trims the doc view to fit content, pinning it to the top (high y in non-flipped coords).
    /// Ensures doc is at least `minHeight` tall so scroll-to-top works.
    private func finalizeDocView(_ docView: NSView, startY: CGFloat, currentY: CGFloat, width: CGFloat, minHeight: CGFloat = 0) {
        let contentUsed = startY - currentY
        let actualH = max(contentUsed + 48, minHeight)
        docView.frame = NSRect(x: 0, y: 0, width: width, height: actualH)
        // Content was laid out from startY downward. Shift so top content sits at top of docView.
        let targetTopY = actualH - 24  // 24px top padding
        let shift = startY - targetTopY
        for sub in docView.subviews { sub.frame.origin.y -= shift }
    }

    private func addSectionHeader(_ text: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let header = NSTextField(labelWithString: text)
        header.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        header.textColor = settingsLabelColor
        header.frame = NSRect(x: x, y: y, width: width, height: 14)
        view.addSubview(header)
        y -= 24
    }

    /// Places a field label. The next control (28px) must not overlap.
    /// Non-flipped: label frame.origin.y is its bottom edge.
    /// After this, y points where a 28px control can be placed with its
    /// top edge 4px below the label bottom.
    private func addFieldLabel(_ text: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.textColor = settingsLabelColor
        label.frame = NSRect(x: x, y: y, width: width, height: 14)
        view.addSubview(label)
        // label bottom edge = y. Next 28px control top = new_y+28.
        // Want new_y+28 = y-4 (4px gap), so new_y = y-32.
        y -= 32
    }

    private func addTextField(_ value: String, placeholder: String? = nil, editable: Bool = true,
                               to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat,
                               id: String? = nil, action: Selector? = nil) -> NSTextField {
        let field = NSTextField(string: value)
        field.cell = VerticallyCenteredTextFieldCell(textCell: value)
        if let ph = placeholder {
            field.placeholderAttributedString = NSAttributedString(string: ph, attributes: [
                .foregroundColor: NSColor(white: 1.0, alpha: 0.35),
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ])
        }
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = editable ? .white : NSColor(white: 1.0, alpha: 0.5)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = editable
        field.wantsLayer = true
        field.layer?.backgroundColor = settingsFieldBg.cgColor
        field.layer?.cornerRadius = 8
        field.layer?.masksToBounds = true
        field.frame = NSRect(x: x, y: y, width: width, height: 28)
        if let id = id { field.identifier = NSUserInterfaceItemIdentifier(id) }
        if let action = action { field.target = self; field.action = action }
        view.addSubview(field)
        y -= 38  // 28 + 10
        return field
    }

    private func addPopup(_ items: [String], selected: String? = nil,
                           to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat,
                           action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: x, y: y, width: width, height: 28))
        popup.addItems(withTitles: items)
        if let sel = selected { popup.selectItem(withTitle: sel) }
        popup.font = NSFont.systemFont(ofSize: 12)
        popup.appearance = NSAppearance(named: .darkAqua)
        popup.target = self
        popup.action = action
        view.addSubview(popup)
        y -= 38
        return popup
    }

    private func addButton(_ title: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat,
                            tintColor: NSColor = NSColor(white: 1.0, alpha: 0.6),
                            bgColor: NSColor? = nil,
                            action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: width, height: 28))
        btn.title = title
        btn.bezelStyle = .rounded
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = (bgColor ?? settingsFieldBg).cgColor
        btn.layer?.cornerRadius = 8
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.contentTintColor = tintColor
        btn.target = self
        btn.action = action
        view.addSubview(btn)
        y -= 38
        return btn
    }

    private func addDescription(_ text: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let desc = NSTextField(labelWithString: text)
        desc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        desc.textColor = NSColor(white: 1.0, alpha: 0.5)
        desc.frame = NSRect(x: x, y: y, width: width, height: 14)
        view.addSubview(desc)
        y -= 24
    }

    // MARK: - General Page

    private func buildGeneralPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("GENERAL", to: docView, x: x, y: &y, width: w)

        // Projects Directory
        addFieldLabel("DEFAULT GEMS DIRECTORY", to: docView, x: x, y: &y, width: w)

        let projDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
        let projDisplay = projDir.isEmpty ? "~/Projects" : (projDir as NSString).abbreviatingWithTildeInPath
        let projField = NSTextField(string: projDisplay)
        projField.cell = VerticallyCenteredTextFieldCell(textCell: projDisplay)
        projField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        projField.textColor = .white
        projField.isBordered = false
        projField.isBezeled = false
        projField.drawsBackground = false
        projField.isEditable = false
        projField.wantsLayer = true
        projField.layer?.backgroundColor = settingsFieldBg.cgColor
        projField.layer?.cornerRadius = 8
        projField.layer?.masksToBounds = true
        projField.frame = NSRect(x: x, y: y, width: w - 74, height: 28)
        projField.identifier = NSUserInterfaceItemIdentifier("projectsDirField")
        docView.addSubview(projField)

        let browseBtn = NSButton(frame: NSRect(x: x + w - 68, y: y, width: 68, height: 28))
        browseBtn.title = "Browse"
        browseBtn.bezelStyle = .rounded
        browseBtn.isBordered = false
        browseBtn.wantsLayer = true
        browseBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        browseBtn.layer?.cornerRadius = 8
        browseBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        browseBtn.contentTintColor = .white
        browseBtn.target = self
        browseBtn.action = #selector(browseProjectsDir(_:))
        docView.addSubview(browseBtn)
        y -= 38

        // Git Remote Base URL
        addFieldLabel("GIT REMOTE BASE URL", to: docView, x: x, y: &y, width: w)
        let gitBaseUrl = UserDefaults.standard.string(forKey: "gitRemoteBaseUrl") ?? ""
        _ = addTextField(gitBaseUrl, placeholder: "git@github.com:user/", to: docView,
                         x: x, y: &y, width: w, id: "gitRemoteBaseUrl", action: #selector(gitBaseUrlChanged(_:)))

        y -= 12

        // ── Toggles ──
        let railOn = UserDefaults.standard.object(forKey: "crystalRailEnabled") as? Bool ?? true
        let railToggle = GlassToggle(title: "Crystal Rail", isOn: railOn,
                                      frame: NSRect(x: x, y: y, width: w, height: 22))
        railToggle.identifier = NSUserInterfaceItemIdentifier("toggle:crystalRail")
        railToggle.target = self
        railToggle.action = #selector(generalToggleChanged(_:))
        docView.addSubview(railToggle)
        y -= 32

        let notifsOn = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        let notifToggle = GlassToggle(title: "Notifications", isOn: notifsOn,
                                       frame: NSRect(x: x, y: y, width: w, height: 22))
        notifToggle.identifier = NSUserInterfaceItemIdentifier("toggle:notifications")
        notifToggle.target = self
        notifToggle.action = #selector(generalToggleChanged(_:))
        docView.addSubview(notifToggle)
        y -= 38

        // Demo button
        _ = addButton("▶  Run Demo", to: docView, x: x, y: &y, width: w, action: #selector(runDemo))

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - Claude Page

    private func buildClaudePage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth
        let claudeEnabled = UserDefaults.standard.object(forKey: "agentEnabled:claude") as? Bool ?? true

        // Toggle
        let toggle = GlassToggle(title: "Claude", isOn: claudeEnabled,
                                  frame: NSRect(x: x, y: y, width: w, height: 22))
        toggle.identifier = NSUserInterfaceItemIdentifier("agentEnable:claude")
        toggle.target = self
        toggle.action = #selector(agentEnableToggled(_:))
        docView.addSubview(toggle)
        y -= 38

        guard claudeEnabled else {
            let hint = NSTextField(labelWithString: "Enable to configure Claude settings")
            hint.font = NSFont.systemFont(ofSize: 11)
            hint.textColor = NSColor(white: 1.0, alpha: 0.35)
            hint.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(hint)
            y -= 24
            finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
            return docView
        }

        // Effort Level
        addFieldLabel("EFFORT LEVEL", to: docView, x: x, y: &y, width: w)
        _ = addPopup(["low", "medium", "high"], selected: "high", to: docView, x: x, y: &y, width: w,
                     action: #selector(effortChanged(_:)))

        // Default Mode
        addFieldLabel("DEFAULT MODE", to: docView, x: x, y: &y, width: w)
        _ = addPopup(["plan", "default", "acceptEdits", "bypassPermissions"], to: docView, x: x, y: &y, width: w,
                     action: #selector(defaultModeChanged(_:)))

        // Bridge Port
        addFieldLabel("BRIDGE PORT", to: docView, x: x, y: &y, width: w)
        _ = addTextField("19280", to: docView, x: x, y: &y, width: w, id: nil, action: nil)
        // Make it read-only (last added)
        if let lastField = docView.subviews.last as? NSTextField {
            lastField.isEditable = false
            lastField.textColor = NSColor(white: 1.0, alpha: 0.5)
        }

        // Open settings.json
        _ = addButton("Open settings.json", to: docView, x: x, y: &y, width: w, action: #selector(openSettingsFile))

        y -= 12

        // Notifications
        addSectionHeader("NOTIFICATIONS", to: docView, x: x, y: &y, width: w)

        let appDelegate = NSApp.delegate as? AppDelegate
        let enabled = appDelegate?.currentEnabledNotifications

        let notifTypes: [(key: String, label: String, defaultOn: Bool)] = [
            ("Stop",          "Task completed (Stop)",    true),
            ("PostToolUse",   "Tool finished",            false),
            ("SubagentStop",  "Agent finished",           false),
            ("TaskCompleted", "Task completed (team)",    false),
            ("Notification",  "Notifications",            true),
            ("TeammateIdle",  "Teammate idle",            false),
            ("SessionEnd",    "Session ended",            false),
        ]

        for item in notifTypes {
            let currentState: Bool
            switch item.key {
            case "Stop":          currentState = enabled?.Stop ?? item.defaultOn
            case "PostToolUse":   currentState = enabled?.PostToolUse ?? item.defaultOn
            case "SubagentStop":  currentState = enabled?.SubagentStop ?? item.defaultOn
            case "TaskCompleted": currentState = enabled?.TaskCompleted ?? item.defaultOn
            case "Notification":  currentState = enabled?.Notification ?? item.defaultOn
            case "TeammateIdle":  currentState = enabled?.TeammateIdle ?? item.defaultOn
            case "SessionEnd":    currentState = enabled?.SessionEnd ?? item.defaultOn
            default:              currentState = item.defaultOn
            }

            let cb = NSButton(checkboxWithTitle: item.label, target: self,
                               action: #selector(notifToggled(_:)))
            cb.state = currentState ? .on : .off
            cb.identifier = NSUserInterfaceItemIdentifier("notif:" + item.key)
            cb.attributedTitle = NSAttributedString(string: item.label, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11)
            ])
            cb.frame = NSRect(x: x, y: y, width: w, height: 18)
            docView.addSubview(cb)
            y -= 22
        }

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - Codex Page

    private func buildCodexPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth
        let codexEnabled = UserDefaults.standard.object(forKey: "agentEnabled:codex") as? Bool ?? false

        let toggle = GlassToggle(title: "Codex", isOn: codexEnabled,
                                  frame: NSRect(x: x, y: y, width: w, height: 22))
        toggle.identifier = NSUserInterfaceItemIdentifier("agentEnable:codex")
        toggle.target = self
        toggle.action = #selector(agentEnableToggled(_:))
        docView.addSubview(toggle)
        y -= 38

        guard codexEnabled else {
            let hint = NSTextField(labelWithString: "Enable to configure Codex settings")
            hint.font = NSFont.systemFont(ofSize: 11)
            hint.textColor = NSColor(white: 1.0, alpha: 0.35)
            hint.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(hint)
            y -= 24
            finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
            return docView
        }

        // Approval Policy
        addFieldLabel("APPROVAL POLICY", to: docView, x: x, y: &y, width: w)
        let currentApproval = CodexConfig.readApprovalPolicy()
        _ = addPopup(["untrusted", "on-request", "never"], selected: currentApproval,
                     to: docView, x: x, y: &y, width: w, action: #selector(codexApprovalChanged(_:)))

        // Sandbox Mode
        addFieldLabel("SANDBOX MODE", to: docView, x: x, y: &y, width: w)
        let currentSandbox = CodexConfig.readSandboxMode()
        _ = addPopup(["workspace-read", "workspace-write", "danger-full-access"], selected: currentSandbox,
                     to: docView, x: x, y: &y, width: w, action: #selector(codexSandboxChanged(_:)))

        addDescription("Applied on next Codex launch", to: docView, x: x, y: &y, width: w)

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - MCP Servers Page

    private func buildMCPPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let mcpManager = MCPConfigManager.shared
        let sortedServers = mcpManager.catalog.servers.sorted(by: { $0.key < $1.key })
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("DEFAULT MCP SERVERS", to: docView, x: x, y: &y, width: w)
        addDescription("Synced to Claude (.mcp.json) and Codex (config.toml)", to: docView, x: x, y: &y, width: w)

        if sortedServers.isEmpty {
            y -= 4
            let emptyLabel = NSTextField(labelWithString: "No MCP servers configured")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor(white: 1.0, alpha: 0.35)
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: x + 4, y: y - 16, width: w - 8, height: 16)
            docView.addSubview(emptyLabel)
            y -= 24
        } else {
            for (name, server) in sortedServers {
                y -= 26
                let rowY = y

                let toggle = NSButton(checkboxWithTitle: "", target: self,
                                      action: #selector(mcpGlobalToggled(_:)))
                toggle.state = server.enabledByDefault ? .on : .off
                toggle.identifier = NSUserInterfaceItemIdentifier("mcpGlobal:" + name)
                toggle.frame = NSRect(x: x + 4, y: rowY, width: 20, height: 18)
                docView.addSubview(toggle)

                let nameLabel = NSTextField(labelWithString: name)
                nameLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                nameLabel.textColor = .white
                nameLabel.frame = NSRect(x: x + 30, y: rowY, width: w - 56, height: 16)
                nameLabel.lineBreakMode = .byTruncatingTail
                docView.addSubview(nameLabel)

                let removeBtn = NSButton(frame: NSRect(x: x + w - 18, y: rowY + 1, width: 16, height: 16))
                removeBtn.title = "×"
                removeBtn.bezelStyle = .inline
                removeBtn.isBordered = false
                removeBtn.font = NSFont.systemFont(ofSize: 14, weight: .light)
                removeBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.3)
                removeBtn.identifier = NSUserInterfaceItemIdentifier("mcpRemove:" + name)
                removeBtn.target = self
                removeBtn.action = #selector(removeMCPServer(_:))
                docView.addSubview(removeBtn)
            }
        }
        y -= 42

        _ = addButton("+ Add MCP Server", to: docView, x: x, y: &y, width: w,
                      action: #selector(addMCPServer))

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - Starter Files Page

    private func buildStartersPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let starterMgr = StarterManager.shared
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("DEFAULT STARTER FILES", to: docView, x: x, y: &y, width: w)
        addDescription("Templates written to new gems", to: docView, x: x, y: &y, width: w)

        if starterMgr.starters.isEmpty {
            y -= 4
            let emptyLabel = NSTextField(labelWithString: "No starter files configured")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor(white: 1.0, alpha: 0.35)
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: x + 4, y: y - 16, width: w - 8, height: 16)
            docView.addSubview(emptyLabel)
            y -= 24
        } else {
            for starter in starterMgr.starters {
                y -= 26
                let rowY = y

                let toggle = NSButton(checkboxWithTitle: "", target: self,
                                      action: #selector(starterEnabledToggled(_:)))
                toggle.state = starter.enabledByDefault ? .on : .off
                toggle.identifier = NSUserInterfaceItemIdentifier("starterEnabled:\(starter.id.uuidString)")
                toggle.frame = NSRect(x: x + 4, y: rowY, width: 20, height: 18)
                docView.addSubview(toggle)

                let nameLabel = NSTextField(labelWithString: starter.filename)
                nameLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                nameLabel.textColor = .white
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.frame = NSRect(x: x + 30, y: rowY, width: w - 82, height: 16)
                docView.addSubview(nameLabel)

                let editBtn = NSButton(frame: NSRect(x: x + w - 44, y: rowY, width: 22, height: 16))
                editBtn.title = "✎"
                editBtn.bezelStyle = .inline
                editBtn.isBordered = false
                editBtn.font = NSFont.systemFont(ofSize: 12, weight: .regular)
                editBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
                editBtn.identifier = NSUserInterfaceItemIdentifier("starterEdit:\(starter.id.uuidString)")
                editBtn.target = self
                editBtn.action = #selector(editStarter(_:))
                docView.addSubview(editBtn)

                let removeBtn = NSButton(frame: NSRect(x: x + w - 18, y: rowY + 1, width: 16, height: 16))
                removeBtn.title = "×"
                removeBtn.bezelStyle = .inline
                removeBtn.isBordered = false
                removeBtn.font = NSFont.systemFont(ofSize: 14, weight: .light)
                removeBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.3)
                removeBtn.identifier = NSUserInterfaceItemIdentifier("starterDelete:\(starter.id.uuidString)")
                removeBtn.target = self
                removeBtn.action = #selector(deleteStarter(_:))
                docView.addSubview(removeBtn)
            }
        }
        y -= 42

        _ = addButton("+ Add Starter File", to: docView, x: x, y: &y, width: w,
                      action: #selector(addStarter))

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - API Keys Page

    private func buildAPIKeysPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let isPro = LicenseManager.shared.tier == .pro
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("API KEYS", to: docView, x: x, y: &y, width: w)

        if !isPro {
            // Guild membership callout
            let features = [
                "Secure API key storage in Keychain",
                "Auto-inject keys into every shell session",
                "Private Slack community access",
                "Priority support & early features",
            ]
            let lineH: CGFloat = 16
            let headerH: CGFloat = 22
            let listTopPad: CGFloat = 8
            let boxPadV: CGFloat = 14
            let boxH: CGFloat = boxPadV + headerH + listTopPad + (lineH * CGFloat(features.count)) + boxPadV
            let box = NSView(frame: NSRect(x: x, y: y - boxH, width: w, height: boxH))
            box.wantsLayer = true
            box.layer?.borderWidth = 1
            box.layer?.borderColor = NSColor(white: 1.0, alpha: 0.2).cgColor
            box.layer?.cornerRadius = 8

            let heading = NSTextField(labelWithString: "Join the Guild! Get access to:")
            heading.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            heading.textColor = NSColor(red: 0.55, green: 0.72, blue: 0.85, alpha: 1.0)
            heading.frame = NSRect(x: 14, y: boxH - boxPadV - headerH, width: w - 28, height: headerH)
            box.addSubview(heading)

            var listY = boxH - boxPadV - headerH - listTopPad
            for feature in features {
                let item = NSTextField(labelWithString: "  ◇  \(feature)")
                item.font = NSFont.systemFont(ofSize: 11, weight: .regular)
                item.textColor = NSColor(white: 1.0, alpha: 0.6)
                item.frame = NSRect(x: 14, y: listY - lineH, width: w - 28, height: lineH)
                box.addSubview(item)
                listY -= lineH
            }

            docView.addSubview(box)
            y -= (boxH + 16)

            let hint = NSTextField(labelWithString: "Activate a license on the License page to join.")
            hint.font = NSFont.systemFont(ofSize: 10, weight: .regular)
            hint.textColor = NSColor(white: 1.0, alpha: 0.35)
            hint.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(hint)
            y -= 20
        }

        if isPro {
            addDescription("Injected into shell sessions as env vars", to: docView, x: x, y: &y, width: w)
            let store = APIKeyStore.shared
            for slot in apiKeySlots {
                addFieldLabel(slot.name.uppercased(), to: docView, x: x, y: &y, width: w)

                let existing = store.get(slot.envVar) ?? ""
                let masked = existing.isEmpty ? "" : maskKey(existing)
                let keyField = NSSecureTextField(string: "")
                keyField.cell = VerticallyCenteredTextFieldCell(textCell: "")
                (keyField.cell as? NSSecureTextFieldCell)?.echosBullets = true
                keyField.placeholderString = existing.isEmpty ? slot.placeholder : masked
                keyField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                keyField.textColor = .white
                keyField.isBordered = false
                keyField.isBezeled = false
                keyField.drawsBackground = false
                keyField.wantsLayer = true
                keyField.layer?.backgroundColor = settingsFieldBg.cgColor
                keyField.layer?.cornerRadius = 8
                keyField.layer?.masksToBounds = true
                keyField.frame = NSRect(x: x, y: y, width: w, height: 28)
                keyField.identifier = NSUserInterfaceItemIdentifier("apiKey:\(slot.envVar)")
                keyField.target = self
                keyField.action = #selector(apiKeyChanged(_:))
                docView.addSubview(keyField)
                y -= 38
            }
        }

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - License Page

    private func buildLicensePage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("LICENSE", to: docView, x: x, y: &y, width: w)

        let lm = LicenseManager.shared
        switch lm.currentState {
        case .valid(let payload):
            let statusLabel = NSTextField(labelWithString: "GUILD MEMBER")
            statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            statusLabel.textColor = NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
            statusLabel.frame = NSRect(x: x, y: y, width: w, height: 16)
            docView.addSubview(statusLabel)
            y -= 22

            let emailLabel = NSTextField(labelWithString: payload.email)
            emailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emailLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            emailLabel.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(emailLabel)
            y -= 18

            let expiryText = payload.isLifetime ? "Lifetime license" : "Expires: \(payload.expires)"
            let expiryLabel = NSTextField(labelWithString: expiryText)
            expiryLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            expiryLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            expiryLabel.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(expiryLabel)
            y -= 30

            _ = addButton("Deactivate License", to: docView, x: x, y: &y, width: w,
                          tintColor: NSColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 0.8),
                          bgColor: NSColor(red: 0.5, green: 0.15, blue: 0.15, alpha: 0.4),
                          action: #selector(deactivateLicense))

        case .expired(let payload):
            let statusLabel = NSTextField(labelWithString: "EXPIRED")
            statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            statusLabel.textColor = NSColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1.0)
            statusLabel.frame = NSRect(x: x, y: y, width: w, height: 16)
            docView.addSubview(statusLabel)
            y -= 22

            let infoLabel = NSTextField(labelWithString: "\(payload.email) — expired \(payload.expires)")
            infoLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            infoLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            infoLabel.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(infoLabel)
            y -= 30

            addLicenseKeyInput(to: docView, x: x, y: &y, w: w)

        case .unlicensed:
            addLicenseKeyInput(to: docView, x: x, y: &y, w: w)
        }

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    private func addLicenseKeyInput(to docView: NSView, x: CGFloat, y: inout CGFloat, w: CGFloat) {
        let keyField = NSTextField(string: "")
        keyField.cell = VerticallyCenteredTextFieldCell(textCell: "")
        keyField.placeholderString = "Paste license key"
        keyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.textColor = .white
        keyField.isBordered = false
        keyField.isBezeled = false
        keyField.drawsBackground = false
        keyField.wantsLayer = true
        keyField.layer?.backgroundColor = settingsFieldBg.cgColor
        keyField.layer?.cornerRadius = 8
        keyField.layer?.masksToBounds = true
        keyField.frame = NSRect(x: x, y: y, width: w, height: 28)
        keyField.identifier = NSUserInterfaceItemIdentifier("licenseKey")
        docView.addSubview(keyField)
        y -= 36

        _ = addButton("Activate", to: docView, x: x, y: &y, width: w,
                      tintColor: NSColor(red: 0.5, green: 1.0, blue: 0.7, alpha: 0.9),
                      bgColor: NSColor(red: 0.2, green: 0.5, blue: 0.35, alpha: 0.5),
                      action: #selector(activateLicense))
    }

    // MARK: - Navigation Action

    @objc func settingsNavClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("settingsNav:") else { return }
        let pageName = String(raw.dropFirst(12))
        guard let page = SettingsPage(rawValue: pageName) else { return }
        settingsSelectedPage = page
        rebuildSettings()
    }

    // MARK: - Settings Action Handlers

    @objc func generalToggleChanged(_ sender: AnyObject) {
        guard let toggle = sender as? GlassToggle,
              let raw = toggle.identifier?.rawValue,
              raw.hasPrefix("toggle:") else { return }
        let key = String(raw.dropFirst(7))
        let isOn = toggle.isOn

        switch key {
        case "crystalRail":
            UserDefaults.standard.set(isOn, forKey: "crystalRailEnabled")
            if let appDelegate = NSApp.delegate as? AppDelegate {
                if isOn {
                    appDelegate.rail?.panel.orderFront(nil)
                } else {
                    appDelegate.rail?.panel.orderOut(nil)
                }
            }
        case "notifications":
            UserDefaults.standard.set(isOn, forKey: "notificationsEnabled")
            if !isOn {
                // Dismiss all existing notifications
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.dismissAllNotificationsClicked()
                }
            }
        default:
            break
        }
    }

    @objc func effortChanged(_ sender: NSPopUpButton) {
        guard let level = sender.selectedItem?.title else { return }
        onSettingsChanged?(["effortLevel": level])
    }

    @objc func defaultModeChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.title else { return }
        onSettingsChanged?(["defaultMode": mode])
    }

    @objc func notifToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("notif:") else { return }
        let key = String(raw.dropFirst(6))
        let isOn = sender.state == .on
        let update: [String: Any] = ["enabledNotifications": [key: isOn]]
        onSettingsChanged?(update)
    }

    @objc func openSettingsFile() {
        let path = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func agentEnableToggled(_ sender: AnyObject) {
        let raw: String?
        let isOn: Bool
        if let toggle = sender as? GlassToggle {
            raw = toggle.identifier?.rawValue
            isOn = toggle.state == .on
        } else if let btn = sender as? NSButton {
            raw = btn.identifier?.rawValue
            isOn = btn.state == .on
        } else { return }
        guard let rawVal = raw, rawVal.hasPrefix("agentEnable:") else { return }
        let agent = String(rawVal.dropFirst(12))
        UserDefaults.standard.set(isOn, forKey: "agentEnabled:\(agent)")
        rebuildSettings()
    }

    @objc func codexApprovalChanged(_ sender: NSPopUpButton) {
        guard let policy = sender.selectedItem?.title else { return }
        CodexConfig.writeApprovalPolicy(policy)
    }

    @objc func codexSandboxChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.title else { return }
        CodexConfig.writeSandboxMode(mode)
    }

    @objc func mcpGlobalToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("mcpGlobal:") else { return }
        let name = String(raw.dropFirst(10))
        let mgr = MCPConfigManager.shared
        guard var server = mgr.catalog.servers[name] else { return }
        server.enabledByDefault = sender.state == .on
        mgr.updateServer(name: name, server: server)
    }

    @objc func addMCPServer() {
        let alert = NSAlert()
        alert.messageText = "Add MCP Server"
        alert.informativeText = "Enter the server details."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 90))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 62, width: 320, height: 24))
        nameField.placeholderString = "Name (e.g. browser-mcp)"
        nameField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        container.addSubview(nameField)

        let cmdField = NSTextField(frame: NSRect(x: 0, y: 32, width: 320, height: 24))
        cmdField.placeholderString = "Command (e.g. npx)"
        cmdField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        container.addSubview(cmdField)

        let argsField = NSTextField(frame: NSRect(x: 0, y: 2, width: 320, height: 24))
        argsField.placeholderString = "Args (space-separated)"
        argsField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        container.addSubview(argsField)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        let cmd = cmdField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !cmd.isEmpty else { return }

        let args = argsField.stringValue
            .trimmingCharacters(in: .whitespaces)
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }

        let server = MCPServer(
            command: cmd,
            args: args.isEmpty ? nil : args,
            enabledByDefault: true
        )
        MCPConfigManager.shared.addServer(name: name, server: server)
        rebuildSettings()
    }

    @objc func removeMCPServer(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("mcpRemove:") else { return }
        let name = String(raw.dropFirst(10))

        let alert = NSAlert()
        alert.messageText = "Remove \(name)?"
        alert.informativeText = "This removes the MCP server from all gems."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        MCPConfigManager.shared.removeServer(name: name)
        rebuildSettings()
    }

    @objc func browseProjectsDir(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select your gems directory"

        let currentDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? (NSHomeDirectory() + "/Projects")
        panel.directoryURL = URL(fileURLWithPath: currentDir)

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let path = url.path
            UserDefaults.standard.set(path, forKey: "projectsDirectory")

            if let settingsView = self?.settingsView {
                if let tf = self?.findView(in: settingsView, id: "projectsDirField") as? NSTextField {
                    tf.stringValue = (path as NSString).abbreviatingWithTildeInPath
                }
            }
        }
    }

    @objc func gitBaseUrlChanged(_ sender: NSTextField) {
        let value = sender.stringValue.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(value, forKey: "gitRemoteBaseUrl")
    }

    @objc func apiKeyChanged(_ sender: NSTextField) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("apiKey:") else { return }
        let envVar = String(raw.dropFirst(7))
        let value = sender.stringValue.trimmingCharacters(in: .whitespaces)
        APIKeyStore.shared.set(envVar, value: value)
        if !value.isEmpty {
            sender.placeholderString = maskKey(value)
        }
        sender.stringValue = ""
    }

    // MARK: - License Actions

    @objc func activateLicense(_ sender: NSButton) {
        guard let scrollView = settingsView?.subviews.compactMap({ $0 as? NSScrollView }).first,
              let docView = scrollView.documentView else { return }
        guard let keyField = docView.subviews.compactMap({ $0 as? NSTextField })
                .first(where: { $0.identifier?.rawValue == "licenseKey" }) else { return }
        let keyString = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyString.isEmpty else { return }

        let result = LicenseManager.shared.activate(keyString)
        switch result {
        case .success:
            rebuildSettings()
        case .failure(let error):
            keyField.stringValue = ""
            keyField.placeholderString = error.localizedDescription
        }
    }

    @objc func deactivateLicense(_ sender: NSButton) {
        LicenseManager.shared.deactivate()
        rebuildSettings()
    }

    /// Masks an API key for display: shows first 6 and last 4 chars.
    private func maskKey(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "\u{2022}", count: key.count) }
        let prefix = String(key.prefix(6))
        let suffix = String(key.suffix(4))
        return prefix + String(repeating: "\u{2022}", count: 6) + suffix
    }

    // MARK: - Starter File Actions

    @objc func editStarter(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("starterEdit:"),
              let uuid = UUID(uuidString: String(raw.dropFirst(12))) else { return }
        guard let starter = StarterManager.shared.starters.first(where: { $0.id == uuid }) else { return }
        StarterEditorPanel.shared.show(starter: starter, relativeTo: window) { [weak self] in
            self?.rebuildSettings()
        }
    }

    @objc func addStarter() {
        let starter = StarterManager.shared.add(name: "new-file.md", filename: "new-file.md")
        StarterEditorPanel.shared.show(starter: starter, relativeTo: window) { [weak self] in
            self?.rebuildSettings()
        }
    }

    @objc func deleteStarter(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("starterDelete:"),
              let uuid = UUID(uuidString: String(raw.dropFirst(14))) else { return }
        StarterManager.shared.remove(id: uuid)
        rebuildSettings()
    }

    @objc func starterEnabledToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("starterEnabled:"),
              let uuid = UUID(uuidString: String(raw.dropFirst(15))) else { return }
        guard var starter = StarterManager.shared.starters.first(where: { $0.id == uuid }) else { return }
        starter.enabledByDefault = sender.state == .on
        StarterManager.shared.update(starter)
    }

    /// Rebuilds the settings view in place (no flip animation).
    func rebuildSettings() {
        guard let container = window.contentView, let old = settingsView else { return }
        old.removeFromSuperview()
        let newSettings = buildSettingsView()
        newSettings.frame = container.bounds
        settingsView = newSettings
        container.addSubview(newSettings)
    }

    func findView(in view: NSView, id: String) -> NSView? {
        if view.identifier?.rawValue == id { return view }
        for sub in view.subviews {
            if let found = findView(in: sub, id: id) { return found }
        }
        if let sv = view as? NSScrollView, let doc = sv.documentView {
            if let found = findView(in: doc, id: id) { return found }
        }
        return nil
    }

    @objc func runDemo() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        flipToTerminal()
        DemoRunner.run(terminalController: self, appDelegate: appDelegate)
    }
}

// ── Demo Runner ──

/// Orchestrates the full Crystl demo: fades out, sets up projects, animates back in,
/// shows code in terminal, then sends approval/notification events to the bridge.
class DemoRunner {
    static let demoDir = "/tmp/crystl-demo"
    static let bridge = "http://127.0.0.1:19280"

    struct DemoProject {
        let name: String
        let icon: String
        let color: String
    }

    static let projects = [
        DemoProject(name: "webapp", icon: "rocket", color: "#7AA2F7"),
        DemoProject(name: "api-server", icon: "zap", color: "#F7768E"),
        DemoProject(name: "design-system", icon: "gem", color: "#BB9AF7"),
        DemoProject(name: "docs", icon: "book", color: "#9ECE6A"),
        DemoProject(name: "infra", icon: "shield", color: "#FF9E64"),
    ]

    static func run(terminalController tc: TerminalWindowController, appDelegate: AppDelegate) {
        guard let win = tc.window else { return }

        // 1. Fade out window + rail
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            win.animator().alphaValue = 0
            appDelegate.rail?.panel.animator().alphaValue = 0
        }, completionHandler: {
            // 2. Close all tabs except one
            while tc.projects.count > 1 {
                tc.closeProject(tc.projects.count - 1)
            }
            // Remove tiles from rail
            appDelegate.rail?.removeAllTiles()

            // 3. Create demo project files on disk
            createDemoFiles()

            // 4. Set bridge to manual mode
            saveBridgeSettings()
            setBridgeManualMode()

            // 5. Open demo projects — first one replaces current tab
            tc.projects[0].sessions.forEach { $0.terminalView.removeFromSuperview() }
            tc.projects.removeAll()

            for proj in projects {
                let path = demoDir + "/" + proj.name
                let color = NSColor(hex: proj.color) ?? .white
                let project = ProjectTab(directory: path, color: color)
                project.iconName = proj.icon
                guard let session = project.addSession(frame: tc.contentArea.bounds).session else { continue }
                session.terminalView.processDelegate = tc
                tc.projects.append(project)

                tc.configureTerminalAppearance(session.terminalView, sessionId: session.id)
                session.terminalView.frame = tc.contentArea.bounds
                session.terminalView.isHidden = true
                tc.contentArea.addSubview(session.terminalView)

                tc.onTabAdded?(project)
            }

            tc.selectedProjectIndex = 0
            tc.selectProject(0)
            tc.updateTabBar()

            // Make window visible and animate in
            win.alphaValue = 1
            win.makeKeyAndOrderFront(nil)
            appDelegate.rail?.panel.alphaValue = 1
            appDelegate.rail?.animateOpen()

            if let container = win.contentView {
                tc.animateWindowOpen(container: container)
            }

            // 7a. Reset opacity and show approval flyout after rail finishes sliding in (0.6s)
            tc.setOpacity(0.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                tc.syncSettings(mode: "manual", paused: false)
                if let iconView = appDelegate.rail?.iconView {
                    appDelegate.showRailSettingsMenu(from: iconView)
                }
            }

            // After 1.8s, animate selection down to "smart"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                appDelegate.animateFlyoutSelection(to: "smart")
                tc.syncSettings(mode: "smart", paused: false)
            }

            // After 3.0s, close the flyout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                appDelegate.closeFlyout()
            }

            // 7b. Start shells AFTER flyout closes so typing happens after menu
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                for project in tc.projects {
                    for session in project.sessions {
                        session.start()
                        tc.hideScroller(in: session.terminalView, sessionId: session.id)
                    }
                }

                // 8. After autorun finishes (~10s), send bridge events
                DispatchQueue.global().asyncAfter(deadline: .now() + 10) {

                    // Phase 1: webapp approvals
                    sendApprovalEvents()

                    // Phase 2: auto-click Allow All after 3s
                    Thread.sleep(forTimeInterval: 3)
                    DispatchQueue.main.async {
                        appDelegate.allowAllClicked()
                    }

                    // Phase 3: api-server approvals (different tile activates)
                    Thread.sleep(forTimeInterval: 1.5)
                    sendApiServerApprovalEvents()

                    // Phase 4: notifications
                    Thread.sleep(forTimeInterval: 2)
                    sendNotificationEvents()

                    // Phase 5: auto-click Allow All + Dismiss All to end cleanly
                    Thread.sleep(forTimeInterval: 3)
                    DispatchQueue.main.async {
                        appDelegate.allowAllClicked()
                        appDelegate.dismissAllNotificationsClicked()
                    }

                    // Phase 6: show New Project panel
                    Thread.sleep(forTimeInterval: 1.5)
                    DispatchQueue.main.async {
                        appDelegate.rail?.showNewProjectPanel()
                    }
                    // Type project name
                    Thread.sleep(forTimeInterval: 0.8)
                    let demoName = "my-saas-app"
                    for (i, ch) in demoName.enumerated() {
                        DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                            let partial = String(demoName.prefix(i + 1))
                            appDelegate.rail?.newProjectPanel.setName(partial)
                        }
                    }
                    // Select color + icon after typing finishes
                    let typeTime = Double(demoName.count) * 0.06 + 0.4
                    Thread.sleep(forTimeInterval: typeTime)
                    DispatchQueue.main.async {
                        appDelegate.rail?.newProjectPanel.selectColor(4)
                    }
                    Thread.sleep(forTimeInterval: 0.6)
                    DispatchQueue.main.async {
                        appDelegate.rail?.newProjectPanel.selectIcon("rocket")
                    }
                    // Close after a pause
                    Thread.sleep(forTimeInterval: 2.0)
                    DispatchQueue.main.async {
                        appDelegate.rail?.newProjectPanel.dismiss()
                    }

                    // Restore settings
                    Thread.sleep(forTimeInterval: 1)
                    restoreBridgeSettings()
                }
            }
        })
    }

    // MARK: - File Creation

    static func createDemoFiles() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: demoDir)

        // webapp
        let webapp = demoDir + "/webapp"
        try? fm.createDirectory(atPath: webapp + "/src/components", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: webapp + "/src/api", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: webapp + "/.crystl", withIntermediateDirectories: true)
        try? "{ \"color\": \"#7AA2F7\", \"icon\": \"rocket\" }".write(toFile: webapp + "/.crystl/project.json", atomically: true, encoding: .utf8)

        let dashboardCode = """
        import React, { useState, useEffect } from 'react';
        import { Card, Grid, Metric, Text, AreaChart } from '@tremor/react';
        import { fetchAnalytics, AnalyticsData } from '../api/analytics';

        interface DashboardProps {
          projectId: string;
          dateRange: [Date, Date];
        }

        export default function Dashboard({ projectId, dateRange }: DashboardProps) {
          const [data, setData] = useState<AnalyticsData | null>(null);
          const [loading, setLoading] = useState(true);

          useEffect(() => {
            setLoading(true);
            fetchAnalytics(projectId, dateRange)
              .then(setData)
              .finally(() => setLoading(false));
          }, [projectId, dateRange]);

          if (loading) return <Skeleton rows={4} />;

          return (
            <Grid numItems={3} className="gap-6">
              <Card decoration="top" decorationColor="blue">
                <Text>Active Users</Text>
                <Metric>{data?.activeUsers.toLocaleString()}</Metric>
              </Card>
              <Card decoration="top" decorationColor="emerald">
                <Text>Revenue</Text>
                <Metric>${data?.revenue.toLocaleString()}</Metric>
              </Card>
              <Card decoration="top" decorationColor="amber">
                <Text>Conversion Rate</Text>
                <Metric>{data?.conversionRate}%</Metric>
              </Card>
              <AreaChart
                className="h-72 mt-4"
                data={data?.timeline ?? []}
                index="date"
                categories={["pageViews", "uniqueVisitors"]}
                colors={["blue", "cyan"]}
                showAnimation={true}
              />
            </Grid>
          );
        }
        """
        try? dashboardCode.write(toFile: webapp + "/src/components/Dashboard.tsx", atomically: true, encoding: .utf8)

        // Autorun script for webapp
        let autorun = """
        clear
        sleep 0.5
        echo -e "\\033[0;36m❯\\033[0m \\c"
        for c in c l a u d e; do echo -n "$c"; sleep 0.08; done
        echo ""
        sleep 1
        echo ""
        O="\\033[38;5;208m"; W="\\033[1;37m"; D="\\033[38;5;245m"; R="\\033[0m"; G="\\033[0;37m"
        echo -e "${O}╭─── Claude Code v2.1.75 ────────────────────────────────────────────────────────────────╮${R}"
        echo -e "${O}│${R}                                             ${O}│${R} ${W}Tips for getting started${R}                 ${O}│${R}"
        echo -e "${O}│${R}             ${W}Welcome back Chris!${R}             ${O}│${R} Run ${W}/init${R} to create a CLAUDE.md file     ${O}│${R}"
        echo -e "${O}│${R}                                             ${O}│${R} ${D}───────────────────────────────────────${R}  ${O}│${R}"
        echo -e "${O}│${R}                   ${O}▐▛███▜▌${R}                   ${O}│${R} ${W}Recent activity${R}                          ${O}│${R}"
        echo -e "${O}│${R}                  ${O}▝▜█████▛▘${R}                  ${O}│${R} ${D}No recent activity${R}                       ${O}│${R}"
        echo -e "${O}│${R}                    ${O}▘▘ ▝▝${R}                    ${O}│${R}                                          ${O}│${R}"
        echo -e "${O}│${R}                                             ${O}│${R}                                          ${O}│${R}"
        echo -e "${O}│${R}   ${D}Opus 4.6 (1M context) · Claude Max ·${R}      ${O}│${R}                                          ${O}│${R}"
        echo -e "${O}│${R}        ${G}/tmp/crystl-demo/webapp${R}              ${O}│${R}                                          ${O}│${R}"
        echo -e "${O}╰────────────────────────────────────────────────────────────────────────────────────────╯${R}"
        echo ""
        echo -e "  ${D}↑ Opus now defaults to 1M context · 5x more room, same pricing${R}"
        echo ""
        sleep 1
        echo -ne "\\033[1;35m❯\\033[0m "
        prompt="Add error handling with a retry button to the Dashboard component"
        for (( i=0; i<${#prompt}; i++ )); do
            echo -n "${prompt:$i:1}"
            sleep 0.025
        done
        echo ""
        sleep 1.5
        echo ""
        echo -e "\\033[38;5;245m● Reading src/components/Dashboard.tsx...\\033[0m"
        sleep 0.8
        echo -e "\\033[38;5;245m● Analyzing component structure...\\033[0m"
        sleep 0.6
        echo -e "\\033[38;5;245m● Planning changes...\\033[0m"
        sleep 1
        echo ""
        echo -e "I'll add error handling with a retry mechanism. This requires:"
        echo ""
        echo -e "  1. Adding error state and refetch logic to the hook"
        echo -e "  2. Creating an \\033[1mErrorCard\\033[0m component with a retry button"
        echo -e "  3. Running the test suite to verify"
        echo ""
        sleep 0.5
        echo -e "\\033[0;33m⏳ Waiting for approval...\\033[0m"
        """
        try? autorun.write(toFile: webapp + "/.crystl/autorun.sh", atomically: true, encoding: .utf8)

        // Other projects — just config + icon
        for proj in projects where proj.name != "webapp" {
            let dir = demoDir + "/" + proj.name
            try? fm.createDirectory(atPath: dir + "/.crystl", withIntermediateDirectories: true)
            let config = "{ \"color\": \"\(proj.color)\", \"icon\": \"\(proj.icon)\" }"
            try? config.write(toFile: dir + "/.crystl/project.json", atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Bridge Communication

    private static var savedSettings: String?

    static func saveBridgeSettings() {
        guard let url = URL(string: bridge + "/settings") else { return }
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data { savedSettings = String(data: data, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 2)
    }

    static func setBridgeManualMode() {
        guard let url = URL(string: bridge + "/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = """
        {"autoApproveMode":"manual","enabledNotifications":{"Stop":true,"PostToolUse":true,"SubagentStop":true,"TaskCompleted":true,"Notification":true,"TeammateIdle":true,"SessionEnd":true}}
        """
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
    }

    static func restoreBridgeSettings() {
        guard let saved = savedSettings, let url = URL(string: bridge + "/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = saved.data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
        savedSettings = nil
    }

    static func postBridge(path: String, json: String) {
        guard let url = URL(string: bridge + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = json.data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
    }

    static func sendApprovalEvents() {
        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Edit","tool_input":{"file_path":"src/components/Dashboard.tsx","old_string":"if (loading) return <Skeleton rows={4} />;","new_string":"if (loading) return <Skeleton rows={4} />;\\n  if (error) return <ErrorCard message={error} onRetry={refetch} />;"},"cwd":"/tmp/crystl-demo/webapp","session_id":"demo-webapp-001","permission_mode":"default"}
        """)
        Thread.sleep(forTimeInterval: 1)

        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Write","tool_input":{"file_path":"src/components/ErrorCard.tsx","content":"export function ErrorCard({ message, onRetry }) { ... }"},"cwd":"/tmp/crystl-demo/webapp","session_id":"demo-webapp-001","permission_mode":"default"}
        """)
        Thread.sleep(forTimeInterval: 1)

        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Bash","tool_input":{"command":"npm test -- --run src/components/Dashboard.test.tsx"},"cwd":"/tmp/crystl-demo/webapp","session_id":"demo-webapp-001","permission_mode":"default"}
        """)
    }

    static func sendApiServerApprovalEvents() {
        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Edit","tool_input":{"file_path":"src/routes/auth.rs","old_string":"let access_token = encode(","new_string":"let access_token = encode_with_rotation("},"cwd":"/tmp/crystl-demo/api-server","session_id":"demo-api-002","permission_mode":"default"}
        """)
        Thread.sleep(forTimeInterval: 1)

        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Bash","tool_input":{"command":"cargo test auth::tests -- --nocapture"},"cwd":"/tmp/crystl-demo/api-server","session_id":"demo-api-002","permission_mode":"default"}
        """)
    }

    static func sendNotificationEvents() {
        postBridge(path: "/hook?type=Stop", json: """
        {"session_id":"demo-api-002","cwd":"/tmp/crystl-demo/api-server","last_assistant_message":"Auth module refactored. JWT refresh token rotation enabled on all endpoints.","stop_hook_active":true}
        """)
        Thread.sleep(forTimeInterval: 0.8)

        postBridge(path: "/hook?type=Stop", json: """
        {"session_id":"demo-infra-003","cwd":"/tmp/crystl-demo/infra","last_assistant_message":"Terraform plan ready. 3 resources to add, 1 to modify, 0 to destroy.","stop_hook_active":true}
        """)
    }
}

// ── Starter Editor Panel ──

/// Floating glass panel for editing a starter file's filename and content.
class StarterEditorPanel: NSObject, NSTextFieldDelegate {
    static let shared = StarterEditorPanel()

    private var panel: NSPanel?
    private var starterId: UUID?
    private var filenameField: NSTextField?
    private var contentView: NSTextView?
    private var onDismiss: (() -> Void)?

    func show(starter: StarterFile, relativeTo window: NSWindow, onDismiss: @escaping () -> Void) {
        dismiss()
        self.starterId = starter.id
        self.onDismiss = onDismiss

        let panelW: CGFloat = 700
        let panelH: CGFloat = 800

        let winFrame = window.frame
        let x = winFrame.midX - panelW / 2
        let y = winFrame.midY - panelH / 2

        let p = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelW, height: panelH),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true

        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelW, height: panelH))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.appearance = NSAppearance(named: .darkAqua)
        glass.maskImage = roundedMaskImage(size: NSSize(width: panelW, height: panelH), radius: 12)
        glass.wantsLayer = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor(white: 1.0, alpha: 0.3).cgColor

        let labelColor = NSColor(white: 1.0, alpha: 0.7)
        let fieldBg = NSColor(white: 1.0, alpha: 0.12)
        let pad: CGFloat = 16
        var y0 = panelH - 48

        // Title
        let title = NSTextField(labelWithString: "Edit Starter File")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 18)
        glass.addSubview(title)
        y0 -= 34

        // Filename
        let fnLabel = NSTextField(labelWithString: "FILENAME")
        fnLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        fnLabel.textColor = labelColor
        fnLabel.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 14)
        glass.addSubview(fnLabel)
        y0 -= 28

        let fnField = NSTextField(string: starter.filename)
        fnField.cell = VerticallyCenteredTextFieldCell(textCell: starter.filename)
        fnField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        fnField.textColor = .white
        fnField.isBordered = false
        fnField.isBezeled = false
        fnField.drawsBackground = false
        fnField.isEditable = true
        fnField.wantsLayer = true
        fnField.layer?.backgroundColor = fieldBg.cgColor
        fnField.layer?.cornerRadius = 8
        fnField.layer?.masksToBounds = true
        fnField.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 28)
        glass.addSubview(fnField)
        self.filenameField = fnField
        y0 -= 42

        // Content
        let contentLabel = NSTextField(labelWithString: "CONTENT")
        contentLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        contentLabel.textColor = labelColor
        contentLabel.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 14)
        glass.addSubview(contentLabel)
        y0 -= 20

        let editorH = y0 - 48
        let editorScroll = NSScrollView(frame: NSRect(x: pad, y: 48, width: panelW - pad * 2, height: editorH))
        editorScroll.hasVerticalScroller = true
        editorScroll.hasHorizontalScroller = false
        editorScroll.autohidesScrollers = true
        editorScroll.borderType = .noBorder
        editorScroll.drawsBackground = false
        editorScroll.wantsLayer = true
        editorScroll.layer?.cornerRadius = 8
        editorScroll.layer?.masksToBounds = true
        editorScroll.layer?.backgroundColor = fieldBg.cgColor

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: panelW - pad * 2, height: editorH))
        tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        tv.textColor = .white
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 6, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.string = starter.content
        editorScroll.documentView = tv
        glass.addSubview(editorScroll)
        self.contentView = tv

        // Save button
        let saveBtn = NSButton(frame: NSRect(x: pad, y: 12, width: panelW - pad * 2, height: 28))
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

    @objc private func saveClicked() {
        guard let sid = starterId,
              var starter = StarterManager.shared.starters.first(where: { $0.id == sid }) else {
            dismiss()
            return
        }
        if let fn = filenameField?.stringValue.trimmingCharacters(in: .whitespaces), !fn.isEmpty {
            starter.filename = fn
            starter.name = fn
        }
        if let content = contentView?.string {
            starter.content = content
        }
        StarterManager.shared.update(starter)
        dismiss()
    }

    func dismiss() {
        panel?.close()
        panel = nil
        filenameField = nil
        contentView = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}

// ── Codex Config ──

/// Reads and writes top-level keys in ~/.codex/config.toml.
/// Uses simple line-based parsing — no TOML library needed for scalar values.
class CodexConfig {
    private static let configPath = NSHomeDirectory() + "/.codex/config.toml"

    static func readApprovalPolicy() -> String {
        return readKey("approval_policy") ?? "on-request"
    }

    static func readSandboxMode() -> String {
        return readKey("sandbox_mode") ?? "workspace-write"
    }

    static func writeApprovalPolicy(_ value: String) {
        writeKey("approval_policy", value: value)
    }

    static func writeSandboxMode(_ value: String) {
        writeKey("sandbox_mode", value: value)
    }

    /// Read a top-level string value from config.toml.
    private static func readKey(_ key: String) -> String? {
        guard let content = try? String(contentsOfFile: configPath, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") { break }
            if trimmed.hasPrefix(key) {
                let parts = trimmed.components(separatedBy: "=")
                guard parts.count >= 2 else { continue }
                let val = parts.dropFirst().joined(separator: "=")
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                return val
            }
        }
        return nil
    }

    /// Write a top-level string value to config.toml.
    /// If the key exists, updates it in place. Otherwise inserts it at the top.
    private static func writeKey(_ key: String, value: String) {
        let fm = FileManager.default
        let dir = NSHomeDirectory() + "/.codex"
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        var content = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        var lines = content.components(separatedBy: "\n")
        let newLine = "\(key) = \"\(value)\""

        var found = false
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") { break }
            if trimmed.hasPrefix(key) && trimmed.contains("=") {
                lines[i] = newLine
                found = true
                break
            }
        }

        if !found {
            var insertIdx = 0
            for (i, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("[") && !trimmed.hasPrefix("[[") { break }
                if !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                    insertIdx = i + 1
                }
            }
            lines.insert(newLine, at: insertIdx)
        }

        content = lines.joined(separator: "\n")
        try? content.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
}

// ── Window Open Animation ──

extension TerminalWindowController {
    func animateWindowOpen(container: NSView) {
        guard let layer = container.layer else {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let duration: CFTimeInterval = 0.9
        let fluidTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.0
        scale.toValue = 1.0
        scale.duration = duration
        scale.timingFunction = fluidTiming

        let corners = CABasicAnimation(keyPath: "cornerRadius")
        corners.fromValue = container.bounds.width / 2
        corners.toValue = 16
        corners.duration = duration * 0.7
        corners.timingFunction = fluidTiming

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = duration * 0.4
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)

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

        layer.transform = CATransform3DIdentity
        layer.cornerRadius = 16
        layer.opacity = 1.0

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.window.alphaValue = 1.0
            layer.filters = nil
        }
        layer.add(scale, forKey: "openScale")
        layer.add(corners, forKey: "openCorners")
        layer.add(opacity, forKey: "openOpacity")
        CATransaction.commit()

        window.alphaValue = 1.0

        addShimmerSweep(
            to: layer, bounds: container.bounds, cornerRadius: 16,
            delay: duration * 0.25,
            fadeInDuration: 0.15, sweepDuration: 0.5, fadeOutDuration: 0.3
        )
    }
}
