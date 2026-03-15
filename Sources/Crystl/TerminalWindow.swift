// TerminalWindow.swift — Main terminal window controller
//
// Manages the Crystl window: glass background, tab bar, session bar,
// terminal views, status bar, and settings flip.
//
// Primary tabs = project directories. Sessions = terminals within a project.
// The session bar appears when a project has 2+ sessions.

import Cocoa
import SwiftTerm

// ── Terminal Window Controller ──

class TerminalWindowController: NSObject, NSWindowDelegate, LocalProcessTerminalViewDelegate {
    var window: NSWindow!
    var tabBar: TabBarView!
    var sessionBar: SessionBarView!
    private var sessionBarHeight: CGFloat = 28
    var onProcessFinished: ((String, String) -> Void)?
    var onModeChanged: ((String) -> Void)?
    var onClaudeModeChanged: ((String) -> Void)?
    var onPauseToggled: ((Bool) -> Void)?
    var onTabAdded: ((ProjectTab) -> Void)?
    var onTabRemoved: ((UUID) -> Void)?
    var onTabSelected: ((UUID) -> Void)?
    var onTabUpdated: ((UUID, String, String) -> Void)?
    var contentArea: NSView!
    var projectLabel: NSTextField!
    var claudeModePopup: NSPopUpButton!
    var projects: [ProjectTab] = []
    var selectedProjectIndex: Int = 0
    private var colorIndex = 0
    private var scrollerObservers: [UUID: [NSKeyValueObservation]] = [:]
    private var backgroundObservers: [UUID: NSKeyValueObservation] = [:]
    private var currentMode: String = "manual"
    private var currentClaudeMode: String = "default"
    private var isPaused: Bool = false
    private var directoryPicker: DirectoryPicker?
    private var settingsButton: NSButton?
    private var opacitySlider: NSSlider?
    private var opacityLabel: NSTextField?
    private var opacityLabelTimer: Timer?
    private weak var glassView: NSVisualEffectView?
    private weak var backingView: NSView?
    private var setupButton: NSButton?
    private weak var statusBar: NSView?

    // Starter files — tracks which starter is being edited in settings
    var editingStarterId: UUID?

    // Agent detection — mode UI shown when an agent is running
    private var agentMonitor: AgentMonitor?
    private var claudeModeLabel: NSTextField?
    private var claudeModeBg: NSView?
    private var codexModeLabel: NSTextField?
    private var codexModeBg: NSView?
    private var frostView: InsetFrostView?

    // Convenience accessors
    var selectedProject: ProjectTab? {
        guard selectedProjectIndex >= 0 && selectedProjectIndex < projects.count else { return nil }
        return projects[selectedProjectIndex]
    }
    var selectedSession: TerminalSession? { selectedProject?.selectedSession }

    // Legacy compatibility — flat list of all sessions
    var tabs: [TerminalSession] { projects.flatMap { $0.sessions } }

    // MARK: - Setup

    func setup() {
        let windowWidth: CGFloat = 1080
        let windowHeight: CGFloat = 720
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

        let toolbar = NSToolbar(identifier: "crystl")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        let container = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        container.autoresizingMask = [.width, .height]
        window.contentView = container

        let savedOpacity = UserDefaults.standard.double(forKey: "windowOpacity")
        let opacityVal = savedOpacity > 0.01 ? savedOpacity : 0.5

        let glass = NSVisualEffectView(frame: container.bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        glass.appearance = NSAppearance(named: .darkAqua)
        container.addSubview(glass)
        self.glassView = glass

        // Charcoal overlay above glass, below content — only kicks in past halfway
        let backing = CharcoalBackingView(frame: container.bounds)
        backing.wantsLayer = true
        backing.layer?.backgroundColor = darkCharcoalColor.cgColor
        backing.autoresizingMask = [.width, .height]
        container.addSubview(backing)
        self.backingView = backing

        // Apply initial values
        applyOpacity(opacityVal)

        // Tab bar
        let tabBarY = windowHeight - tabBarHeight - titleBarHeight
        tabBar = TabBarView(frame: NSRect(x: 0, y: tabBarY, width: windowWidth, height: tabBarHeight))
        tabBar.autoresizingMask = [.width, .minYMargin]
        tabBar.onSelectTab = { [weak self] idx in self?.selectProject(idx) }
        tabBar.onAddTab = { [weak self] in self?.addProject() }
        tabBar.onCloseTab = { [weak self] idx in self?.closeProject(idx) }
        container.addSubview(tabBar)

        // Session bar — below tab bar with a small gap
        let sessionGap: CGFloat = 10
        let sessionBarY = tabBarY - sessionBarHeight - sessionGap
        sessionBar = SessionBarView(frame: NSRect(x: 0, y: sessionBarY, width: windowWidth, height: sessionBarHeight))
        sessionBar.autoresizingMask = [.width, .minYMargin]
        // Session bar always visible — shows current session(s) and "+" to add more
        sessionBar.onSelectSession = { [weak self] idx in self?.selectSession(idx) }
        sessionBar.onAddSession = { [weak self] in self?.addSessionToCurrentProject() }
        sessionBar.onAddIsolatedSession = { [weak self] in self?.addSessionToCurrentProject(isolated: true) }
        sessionBar.onRenameSession = { [weak self] idx, name in self?.renameSession(idx, name: name) }
        container.addSubview(sessionBar)

        // Crystal icon settings button
        let iconSize: CGFloat = 28
        let settingsBtn = GlowButton(frame: NSRect(
            x: windowWidth - iconSize - 14,
            y: windowHeight - iconSize - 16,
            width: iconSize, height: iconSize
        ))
        settingsBtn.autoresizingMask = [.minXMargin, .minYMargin]
        settingsBtn.isBordered = false
        settingsBtn.bezelStyle = .inline
        settingsBtn.target = self
        settingsBtn.action = #selector(settingsButtonClicked)
        if let path = Bundle.main.path(forResource: "crystl-white-28@2x", ofType: "png")
            ?? Bundle.main.path(forResource: "crystl-white", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: iconSize, height: iconSize)
            settingsBtn.image = img
            settingsBtn.imageScaling = .scaleProportionallyDown
        }
        settingsBtn.alphaValue = 0.85
        settingsBtn.hoverText = "Settings"
        self.settingsButton = settingsBtn
        container.addSubview(settingsBtn)

        // ── Opacity slider in title bar ──
        let sliderWidth: CGFloat = 80
        let slider = NSSlider(frame: NSRect(
            x: (windowWidth - sliderWidth) / 2,
            y: windowHeight - 34,
            width: sliderWidth, height: 16
        ))
        slider.cell = GraySliderCell()
        slider.minValue = 0.0
        slider.maxValue = 1.0
        slider.doubleValue = savedOpacity > 0.01 ? savedOpacity : 0.5
        slider.controlSize = .mini
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(opacitySliderChanged(_:))
        slider.appearance = NSAppearance(named: .darkAqua)
        slider.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        container.addSubview(slider)
        opacitySlider = slider

        // Percentage label (hidden until slider dragged)
        let pctLabel = NSTextField(labelWithString: "")
        pctLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .medium)
        pctLabel.textColor = NSColor(white: 1.0, alpha: 0.7)
        pctLabel.alignment = .center
        pctLabel.frame = NSRect(x: (windowWidth - 40) / 2, y: windowHeight - 50, width: 40, height: 14)
        pctLabel.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        pctLabel.alphaValue = 0
        container.addSubview(pctLabel)
        opacityLabel = pctLabel

        // Status bar
        let statusBar = NSView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: statusBarHeight))
        statusBar.autoresizingMask = [.width, .maxYMargin]
        container.addSubview(statusBar)
        self.statusBar = statusBar

        let labelFont = NSFont.systemFont(ofSize: 9, weight: .medium)
        let labelColor = NSColor(white: 1.0, alpha: 0.6)

        // ── Project path label + clickable button (left) ──
        projectLabel = NSTextField(labelWithString: "")
        projectLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        projectLabel.textColor = NSColor(white: 1.0, alpha: 0.7)
        projectLabel.alignment = .left
        projectLabel.lineBreakMode = .byTruncatingMiddle
        projectLabel.frame = NSRect(x: 24, y: 20, width: 188, height: 16)
        statusBar.addSubview(projectLabel)

        // Invisible button on top of label to catch clicks
        let pathBtn = NSButton(frame: NSRect(x: 16, y: 16, width: 200, height: 28))
        pathBtn.title = ""
        pathBtn.isBordered = false
        pathBtn.isTransparent = true
        pathBtn.target = self
        pathBtn.action = #selector(pathButtonClicked)
        statusBar.addSubview(pathBtn)

        // ── Claude Mode section (right) — hidden until Claude is detected ──
        let claudeLabel = NSTextField(labelWithString: "CLAUDE MODE")
        claudeLabel.font = labelFont
        claudeLabel.textColor = labelColor
        claudeLabel.frame = NSRect(x: windowWidth - 154, y: 48, width: 80, height: 12)
        claudeLabel.autoresizingMask = [.minXMargin]
        claudeLabel.isHidden = true
        statusBar.addSubview(claudeLabel)
        self.claudeModeLabel = claudeLabel

        let popupBg = NSView(frame: NSRect(x: windowWidth - 148, y: 20, width: 124, height: 18))
        popupBg.wantsLayer = true
        popupBg.layer?.cornerRadius = 6
        popupBg.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        popupBg.layer?.borderWidth = 0.5
        popupBg.layer?.borderColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        popupBg.autoresizingMask = [.minXMargin]
        popupBg.isHidden = true
        statusBar.addSubview(popupBg)
        self.claudeModeBg = popupBg

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
        claudeModePopup.isHidden = true
        statusBar.addSubview(claudeModePopup)

        // ── Codex Mode section (right) — hidden until Codex is detected ──
        let codexLabel = NSTextField(labelWithString: "CODEX")
        codexLabel.font = labelFont
        codexLabel.textColor = labelColor
        codexLabel.frame = NSRect(x: windowWidth - 154, y: 48, width: 80, height: 12)
        codexLabel.autoresizingMask = [.minXMargin]
        codexLabel.isHidden = true
        statusBar.addSubview(codexLabel)
        self.codexModeLabel = codexLabel

        let codexBg = NSView(frame: NSRect(x: windowWidth - 148, y: 20, width: 124, height: 18))
        codexBg.wantsLayer = true
        codexBg.layer?.cornerRadius = 6
        codexBg.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        codexBg.layer?.borderWidth = 0.5
        codexBg.layer?.borderColor = NSColor(white: 1.0, alpha: 0.25).cgColor
        codexBg.autoresizingMask = [.minXMargin]
        codexBg.isHidden = true
        statusBar.addSubview(codexBg)
        self.codexModeBg = codexBg

        let codexModeText = NSTextField(labelWithString: "running")
        codexModeText.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        codexModeText.textColor = NSColor(white: 1.0, alpha: 0.7)
        codexModeText.alignment = .center
        codexModeText.frame = NSRect(x: 0, y: 1, width: 124, height: 16)
        codexBg.addSubview(codexModeText)

        // Content area — between session bar and status bar
        let contentTop = sessionBarY
        let contentBottom = statusBarHeight + termPadBottom
        contentArea = NSView(frame: NSRect(x: termPadX, y: contentBottom, width: windowWidth - termPadX * 2, height: contentTop - contentBottom - termPadTop))
        contentArea.autoresizingMask = [.width, .height]
        container.addSubview(contentArea)

        // Inset frost border — topmost subview, covers entire container
        let frost = InsetFrostView(frame: container.bounds)
        frost.cornerRadius = 16
        frost.autoresizingMask = [.width, .height]
        container.addSubview(frost, positioned: .above, relativeTo: nil)
        self.frostView = frost

        addProject()
        animateWindowOpen(container: container)

        // Start agent detection
        let monitor = AgentMonitor()
        monitor.sessions = tabs
        monitor.onAgentChanged = { [weak self] sessionId, agent in
            guard let self = self else { return }
            // If the changed session is the active one, update UI
            if self.selectedSession?.id == sessionId {
                self.updateAgentUI()
            }
        }
        monitor.start()
        self.agentMonitor = monitor
    }

    // MARK: - Project Management

    func nextColor() -> NSColor {
        let color = sessionColors[colorIndex % sessionColors.count]
        colorIndex += 1
        return color
    }

    func addProject(cwd: String = NSHomeDirectory()) {
        let project = ProjectTab(directory: cwd, color: nextColor())
        if cwd == NSHomeDirectory() { project.isUnconfigured = true }
        guard let session = project.addSession(frame: contentArea.bounds).session else { return }
        session.terminalView.processDelegate = self
        projects.append(project)

        configureTerminalAppearance(session.terminalView, sessionId: session.id)

        session.terminalView.frame = contentArea.bounds
        session.terminalView.isHidden = true
        contentArea.addSubview(session.terminalView)

        selectProject(projects.count - 1)
        updateTabBar()
        refreshMonitorSessions()
        onTabAdded?(project)

        DispatchQueue.main.async { [weak self] in
            session.start()
            self?.hideScroller(in: session.terminalView, sessionId: session.id)
        }
    }

    // MARK: - Project Settings Button

    func updateSetupButton() {
        guard let bar = statusBar else { return }

        if setupButton == nil {
            let btn = NSButton(frame: .zero)
            btn.bezelStyle = .rounded
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.08).cgColor
            btn.layer?.cornerRadius = 6
            btn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            btn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
            btn.target = self
            btn.action = #selector(setupProjectClicked)
            bar.addSubview(btn)
            setupButton = btn
        }

        setupButton?.title = "Crystal Settings"
        let btnW: CGFloat = 110
        let btnH: CGFloat = 20
        setupButton?.frame = NSRect(
            x: bar.bounds.width - btnW - 16,
            y: 18,  // aligned with projectLabel y:20
            width: btnW, height: btnH
        )
        setupButton?.autoresizingMask = [.minXMargin]
    }

    @objc func setupProjectClicked() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        appDelegate.showSetupPanel(for: self)
    }

    /// Configures the current tab with project settings (called from NewProjectPanel).
    func configureCurrentProject(name: String, path: String, iconName: String?, color: NSColor?) {
        guard let project = selectedProject else { return }

        let wasUnconfigured = project.isUnconfigured
        let oldPath = project.directory

        project.directory = path
        project.title = name
        project.isUnconfigured = false
        if let icon = iconName { project.iconName = icon }
        if let c = color { project.color = c }

        // cd into the new directory if it changed
        if wasUnconfigured || path != oldPath {
            if let session = project.selectedSession {
                let escaped = shellEscape(path)
                session.terminalView.send(txt: "cd \(escaped) && clear\n")
                session.cwd = path
            }
        }

        updateTabBar()
        updateWindowTitle()
        updateSetupButton()

        // Notify rail of the update
        let hex = color?.hexString ?? project.color.hexString
        onTabUpdated?(project.id, name, hex)
    }

    // MARK: - Session Management

    func addSessionToCurrentProject(isolated: Bool = false) {
        guard let project = selectedProject else { return }
        let result = project.addSession(frame: contentArea.bounds, isolated: isolated)

        let session: TerminalSession
        switch result {
        case .notGitRepo:
            showShardError("Not a git repository — isolated shards require git.")
            return
        case .worktreeFailed(let s):
            session = s
            // Show warning after terminal starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak s] in
                s?.terminalView.feed(text: "\r\n\u{001B}[33m⚠ Worktree creation failed — opened as shared shard instead.\u{001B}[0m\r\n")
            }
        case .created(let s):
            session = s
            if isolated {
                let branch = GitWorktree.branchName(for: session.cwd) ?? "crystl/\(session.name)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak s] in
                    s?.terminalView.feed(text: "\r\n\u{001B}[36m⎇ Isolated shard on branch: \(branch)\u{001B}[0m\r\n")
                }
            }
        }

        session.terminalView.processDelegate = self
        configureTerminalAppearance(session.terminalView, sessionId: session.id)

        session.terminalView.frame = contentArea.bounds
        session.terminalView.isHidden = true
        contentArea.addSubview(session.terminalView)

        selectSession(project.sessions.count - 1)
        updateSessionBar()
        refreshMonitorSessions()

        DispatchQueue.main.async { [weak self] in
            session.start()
            self?.hideScroller(in: session.terminalView, sessionId: session.id)
        }
    }

    private func showShardError(_ message: String) {
        guard let session = selectedProject?.selectedSession else { return }
        session.terminalView.feed(text: "\r\n\u{001B}[31m✗ \(message)\u{001B}[0m\r\n")
    }

    func selectSession(_ sessionIndex: Int) {
        guard let project = selectedProject,
              sessionIndex >= 0 && sessionIndex < project.sessions.count else { return }

        if let current = project.selectedSession {
            current.terminalView.isHidden = true
        }

        project.selectedSessionIndex = sessionIndex
        let session = project.sessions[sessionIndex]
        session.terminalView.isHidden = false
        session.terminalView.frame = contentArea.bounds
        window.makeFirstResponder(session.terminalView)

        updateSessionBar()
        updateWindowTitle()
        updateAgentUI()
    }

    func renameSession(_ index: Int, name: String) {
        guard let project = selectedProject,
              index >= 0 && index < project.sessions.count else { return }
        project.sessions[index].name = name
        project.sessions[index].hasCustomName = true
        updateSessionBar()
    }

    func closeSession(_ sessionIndex: Int) {
        guard let project = selectedProject,
              project.sessions.count > 1 && sessionIndex < project.sessions.count else { return }

        let session = project.sessions[sessionIndex]
        session.cleanupWorktree()
        backgroundObservers.removeValue(forKey: session.id)
        scrollerObservers.removeValue(forKey: session.id)
        session.terminalView.removeFromSuperview()
        project.sessions.remove(at: sessionIndex)

        if project.selectedSessionIndex >= project.sessions.count {
            project.selectedSessionIndex = project.sessions.count - 1
        } else if project.selectedSessionIndex > sessionIndex {
            project.selectedSessionIndex -= 1
        }

        selectSession(project.selectedSessionIndex)
        updateSessionBar()
        refreshMonitorSessions()
    }

    // MARK: - Project Selection

    func selectProject(_ index: Int) {
        guard index >= 0 && index < projects.count else { return }

        if let currentSession = selectedProject?.selectedSession {
            currentSession.terminalView.isHidden = true
        }

        selectedProjectIndex = index
        let project = projects[index]

        if let session = project.selectedSession {
            session.terminalView.isHidden = false
            session.terminalView.frame = contentArea.bounds
            window.makeFirstResponder(session.terminalView)
        }

        updateTabBar()
        updateSessionBar()
        updateWindowTitle()
        updateAgentUI()
        updateSetupButton()
        onTabSelected?(project.id)
    }

    func closeProject(_ index: Int) {
        guard projects.count > 1 && index < projects.count else { return }

        let project = projects[index]
        let projectId = project.id

        // Clean up all sessions
        for session in project.sessions {
            session.cleanupWorktree()
            backgroundObservers.removeValue(forKey: session.id)
            scrollerObservers.removeValue(forKey: session.id)
            session.terminalView.removeFromSuperview()
        }
        projects.remove(at: index)
        onTabRemoved?(projectId)

        if selectedProjectIndex >= projects.count {
            selectedProjectIndex = projects.count - 1
        } else if selectedProjectIndex > index {
            selectedProjectIndex -= 1
        }

        selectProject(selectedProjectIndex)
        updateTabBar()
        refreshMonitorSessions()
    }

    // MARK: - UI Updates

    func updateTabBar() {
        tabBar.projects = projects
        tabBar.selectedIndex = selectedProjectIndex
        tabBar.needsDisplay = true
    }

    func updateSessionBar() {
        guard let project = selectedProject else { return }

        sessionBar.sessions = project.sessions
        sessionBar.selectedIndex = project.selectedSessionIndex
        sessionBar.projectColor = project.color
        sessionBar.isHidden = false
        sessionBar.needsDisplay = true
    }

    func updateWindowTitle() {
        guard let project = selectedProject, let session = project.selectedSession else { return }
        let sessionSuffix = project.sessions.count > 1 ? " / \(session.name)" : ""
        window.title = "Crystl \u{2014} \(project.title)\(sessionSuffix)"
        let cwdDisplay = (session.cwd as NSString).abbreviatingWithTildeInPath
        projectLabel.stringValue = "\(project.title)  \(cwdDisplay)"
    }

    /// Show or hide agent-specific UI based on the active session's detected agent.
    func updateAgentUI() {
        let agent = selectedSession?.detectedAgent ?? .none
        let isClaude = agent == .claude
        let isCodex = agent == .codex

        claudeModeLabel?.isHidden = !isClaude
        claudeModeBg?.isHidden = !isClaude
        claudeModePopup.isHidden = !isClaude

        codexModeLabel?.isHidden = !isCodex
        codexModeBg?.isHidden = !isCodex

        frostView?.setGlowing(agent.isAgent)
    }

    private func refreshMonitorSessions() {
        agentMonitor?.sessions = tabs
    }

    // MARK: - Directory Picker

    func showDirectoryPicker(for session: TerminalSession) {
        let projDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
        let dir = projDir.isEmpty ? (NSHomeDirectory() + "/Projects") : projDir

        let picker = DirectoryPicker()
        picker.onSelect = { [weak self] path in
            session.terminalView.send(txt: "cd \(self?.shellEscape(path) ?? path) && clear\n")
            session.cwd = path
            if let project = self?.selectedProject {
                project.directory = path
                if !project.hasCustomTitle {
                    project.title = (path as NSString).lastPathComponent
                }
            }
            self?.updateTabBar()
            self?.updateWindowTitle()
            if let project = self?.selectedProject {
                self?.onTabUpdated?(project.id, project.title, project.directory)
            }
            self?.directoryPicker = nil
            self?.window.makeFirstResponder(session.terminalView)
        }
        picker.onDismiss = { [weak self] in
            self?.directoryPicker = nil
            self?.window.makeFirstResponder(session.terminalView)
        }
        picker.show(in: contentArea, projectsDir: dir)
        directoryPicker = picker
    }

    @objc func pathButtonClicked() {
        guard let session = selectedSession else { return }

        if directoryPicker?.isVisible == true {
            directoryPicker?.dismiss()
            directoryPicker = nil
            window.makeFirstResponder(session.terminalView)
            return
        }

        showDirectoryPicker(for: session)
    }

    private func shellEscape(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Terminal Appearance

    func configureTerminalAppearance(_ tv: LocalProcessTerminalView, sessionId: UUID) {
        // File drop overlay — pastes shell-escaped paths into the terminal
        let dropView = TerminalDropView(frame: tv.bounds)
        dropView.autoresizingMask = [.width, .height]
        dropView.terminalView = tv
        tv.addSubview(dropView)

        tv.nativeForegroundColor = NSColor.white
        tv.nativeBackgroundColor = NSColor(white: 1.0, alpha: 0.001)

        let fontSize: CGFloat = 13
        if let mono = NSFont(name: "SF Mono", size: fontSize) ?? NSFont(name: "Menlo", size: fontSize) {
            tv.font = mono
        }

        tv.caretColor = NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
        tv.alphaValue = 0.9
        makeTerminalTransparent(tv, sessionId: sessionId)
    }

    func hideScroller(in tv: LocalProcessTerminalView, sessionId: UUID) {
        for sub in tv.subviews {
            if sub is NSScroller {
                sub.isHidden = true
                let obs = sub.observe(\.isHidden, options: [.new]) { scroller, change in
                    if change.newValue == false { scroller.isHidden = true }
                }
                scrollerObservers[sessionId, default: []].append(obs)
            }
        }
    }

    func makeTerminalTransparent(_ tv: LocalProcessTerminalView, sessionId: UUID) {
        tv.wantsLayer = true
        tv.layer?.isOpaque = false
        tv.layer?.backgroundColor = CGColor(gray: 0, alpha: 0)

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
                if alpha > 0.01 { layer.backgroundColor = CGColor(gray: 0, alpha: 0) }
            }
            backgroundObservers[sessionId] = obs
        }
    }

    // MARK: - Settings

    var onSettingsChanged: (([String: Any]) -> Void)?
    var onOpacityChanged: ((CGFloat) -> Void)?
    var settingsView: NSView?
    var isShowingSettings = false

    @objc func settingsButtonClicked() {
        if isShowingSettings { flipToTerminal() } else { flipToSettings() }
    }

    private func applyOpacity(_ val: Double) {
        let opacity = opacityFromSlider(CGFloat(val))
        glassView?.alphaValue = opacity.glassAlpha
        backingView?.alphaValue = opacity.darkAlpha
    }

    @objc private func opacitySliderChanged(_ sender: NSSlider) {
        let val = sender.doubleValue
        applyOpacity(val)
        UserDefaults.standard.set(val, forKey: "windowOpacity")
        onOpacityChanged?(CGFloat(val))

        // Show percentage label
        let pct = Int(round(val * 100))
        opacityLabel?.stringValue = "\(pct)%"
        opacityLabelTimer?.invalidate()
        if opacityLabel?.alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                opacityLabel?.animator().alphaValue = 1
            }
        }
        // Fade out after dragging stops
        opacityLabelTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self?.opacityLabel?.animator().alphaValue = 0
            }
        }
    }

    /// Programmatically set opacity slider value and apply to all elements.
    func setOpacity(_ val: Double) {
        opacitySlider?.doubleValue = val
        applyOpacity(val)
        UserDefaults.standard.set(val, forKey: "windowOpacity")
        onOpacityChanged?(CGFloat(val))
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

    // MARK: - Window Close Animation

    private var isAnimatingClose = false

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isAnimatingClose { return true }
        guard let contentView = sender.contentView else { return true }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return true }

        isAnimatingClose = true
        sender.hasShadow = false

        let duration: CFTimeInterval = 0.25
        let timing = CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = 0.85
        scale.duration = duration
        scale.timingFunction = timing
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = duration
        fade.timingFunction = timing
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak sender] in
            sender?.close()
        }
        layer.add(scale, forKey: "closeScale")
        layer.add(fade, forKey: "closeFade")
        CATransaction.commit()

        return false
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            for project in self.projects {
                if let session = project.sessions.first(where: { $0.terminalView === source }) {
                    if !session.hasCustomName {
                        // Strip leading emoji/symbols (e.g. Claude Code's ✳ prefix)
                        let cleaned = title.drop(while: { !$0.isLetter && !$0.isNumber })
                        session.name = cleaned.isEmpty ? title : String(cleaned)
                    }
                    self.updateSessionBar()
                    self.updateWindowTitle()
                    // Title change may indicate agent launch/exit — rescan immediately
                    self.agentMonitor?.scanNow()
                    self.updateAgentUI()
                    return
                }
            }
        }
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let dir = directory,
                  let lpv = source as? LocalProcessTerminalView else { return }
            for project in self.projects {
                if let session = project.sessions.first(where: { $0.terminalView === lpv }) {
                    session.cwd = dir
                    if !project.hasCustomTitle {
                        project.title = (dir as NSString).lastPathComponent
                        self.updateTabBar()
                    }
                    self.updateWindowTitle()
                    self.onTabUpdated?(project.id, project.title, project.directory)
                    return
                }
            }
        }
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self,
                  let lpv = source as? LocalProcessTerminalView else { return }
            for (pi, project) in self.projects.enumerated() {
                if let si = project.sessions.firstIndex(where: { $0.terminalView === lpv }) {
                    let session = project.sessions[si]
                    self.onProcessFinished?(project.title, session.cwd)

                    if project.sessions.count > 1 {
                        self.closeSession(si)
                    } else if self.projects.count > 1 {
                        self.closeProject(pi)
                    } else {
                        session.start()
                    }
                    return
                }
            }
        }
    }
}
