// AppDelegate.swift — Bridge polling and floating notification panels
//
// Manages the lifecycle of Crystl:
// 1. Creates the terminal window (TerminalWindowController)
// 2. Polls the claude-bridge.js server every 0.5s for pending permission requests
// 3. Shows floating glass-style approval panels for each pending request
// 4. Shows "Allow All" bar when multiple requests are queued
// 5. Shows process-finished notifications that persist until dismissed
// 6. Syncs approval mode and pause state between the UI and bridge
//
// Communication flow:
//   Claude Code -> HTTP hook -> claude-bridge.js (holds connection)
//   Crystl polls GET /pending -> shows panel -> user clicks Allow/Deny
//   Crystl sends POST /decide -> bridge resolves the held connection

import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var terminalController: TerminalWindowController!
    var rail: CrystalRailController?
    var pollTimer: Timer?

    // Approval panels — one per pending request, keyed by request ID
    var panels: [String: NSPanel] = [:]
    var panelCwds: [String: String] = [:]     // request ID -> cwd for tab navigation
    var allowAllPanel: NSPanel?               // Detached bar above cards when 2+ pending
    var finishedPanels: [NSPanel] = []        // Process-complete cards (persist until dismissed)

    // Hook notification panels — keyed by notification ID
    var notificationPanels: [String: NSPanel] = [:]
    var knownNotificationIds: Set<String> = []
    var notificationDismissTimers: [String: Timer] = [:]
    var dismissAllNotificationsPanel: NSPanel?

    var knownIds: Set<String> = []            // Currently displayed request IDs
    var pendingIds: [String] = []             // Ordered list for Allow All
    let bridgePort = 19280
    var isConnected = false
    var currentMode: String = "manual"
    var currentSessions: [SessionInfo] = []
    var currentHistory: [HistoryEntry] = []
    var isPaused: Bool = false
    var currentEnabledNotifications: EnabledNotifications?

    var pendingFolders: [String] = []
    var currentOpacity: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "windowOpacity")
        return saved > 0.01 ? CGFloat(saved) : 0.5
    }()

    /// Shared secret token for authenticating with the bridge server.
    /// Read from ~/.crystl-bridge-token at startup.
    var bridgeToken: String? = {
        let tokenPath = NSHomeDirectory() + "/.crystl-bridge-token"
        return try? String(contentsOfFile: tokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register Apple Event handler early so we catch open events during launch
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:withReply:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )

        // Register as service provider early (must be before app finishes launching)
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch terminal window
        terminalController = TerminalWindowController()
        terminalController.onProcessFinished = { [weak self] title, cwd in
            self?.showProcessFinishedCard(tabTitle: title, cwd: cwd)
        }
        terminalController.onModeChanged = { [weak self] mode in
            self?.updateBridgeSettings(["autoApproveMode": mode])
        }
        terminalController.onPauseToggled = { [weak self] paused in
            self?.updateBridgeSettings(["paused": paused])
        }
        terminalController.onSettingsChanged = { [weak self] update in
            self?.updateBridgeSettings(update)
        }
        terminalController.onTabAdded = { [weak self] tab in
            self?.rail?.addTile(tab: tab)
        }
        terminalController.onTabRemoved = { [weak self] tabId in
            self?.rail?.removeTile(tabId: tabId)
        }
        terminalController.onTabSelected = { [weak self] tabId in
            self?.rail?.selectTile(tabId: tabId)
        }
        terminalController.onTabUpdated = { [weak self] tabId, title, cwd in
            self?.rail?.updateTile(tabId: tabId, title: title, cwd: cwd)
        }
        terminalController.onOpacityChanged = { [weak self] sliderVal in
            guard let self = self else { return }
            self.currentOpacity = sliderVal
            self.rail?.setOpacity(sliderVal)
            self.applyPanelOpacity(sliderVal)
        }
        terminalController.setup()

        // Set up Crystal Rail
        let r = CrystalRailController()
        r.onTileClicked = { [weak self] tabId in
            guard let self = self else { return }
            if let idx = self.terminalController.projects.firstIndex(where: { $0.id == tabId }) {
                self.terminalController.selectProject(idx)
                self.terminalController.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        r.onFolderDropped = { [weak self] path in
            _ = self?.openFolder(path)
        }
        r.onAddClicked = { [weak self] in
            self?.terminalController.addProject()
            self?.terminalController.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        r.onNewProject = { [weak self] name, path, iconName, colorHex, mcpServers, starterIds, gitInit, remote in
            self?.createAndOpenProject(name: name, path: path, iconName: iconName, colorHex: colorHex,
                                       mcpServers: mcpServers, starterIds: starterIds, gitInit: gitInit, remote: remote)
        }
        r.onChangeIcon = { [weak self] tabId in
            self?.showIconPicker(for: tabId)
        }
        r.onSettingsIconClicked = { [weak self] view in
            self?.showRailSettingsMenu(from: view)
        }
        r.setup()

        // Add tiles for any existing tabs
        for project in terminalController.projects {
            r.addTile(tab: project)
        }
        if let firstProject = terminalController.projects.first {
            r.selectTile(tabId: firstProject.id)
        }
        rail = r

        // Sync rail opacity with saved slider value
        let savedOpacity = UserDefaults.standard.double(forKey: "windowOpacity")
        let initialOpacity = savedOpacity > 0.01 ? savedOpacity : 0.5
        r.setOpacity(CGFloat(initialOpacity))

        // Open any folders queued during launch
        for path in pendingFolders {
            _ = openFolder(path)
        }
        pendingFolders.removeAll()

        // Start bridge polling
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        ShellIntegration.shared.cleanup()
    }

    /// Handle kAEOpenDocuments Apple Event directly — this is what `open -a Crystl /path`
    /// and the Finder Quick Action trigger.
    @objc func handleOpenDocuments(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let listDesc = event.paramDescriptor(forKeyword: keyDirectObject) else { return }
        for i in 1...listDesc.numberOfItems {
            guard let itemDesc = listDesc.atIndex(i) else { continue }
            guard let path = pathFromDescriptor(itemDesc) else { continue }
            if terminalController != nil {
                _ = openFolder(path)
            } else {
                pendingFolders.append(path)
            }
        }
    }

    /// Extract a filesystem path from an Apple Event descriptor.
    /// Handles bookmark data, file URLs, and alias records.
    private func pathFromDescriptor(_ desc: NSAppleEventDescriptor) -> String? {
        // Try coercing to file URL first
        if let urlDesc = desc.coerce(toDescriptorType: typeFileURL),
           let data = urlDesc.data as Data?,
           let urlString = String(data: data, encoding: .utf8),
           let url = URL(string: urlString) {
            return url.path
        }
        // Try bookmark data (what Finder typically sends)
        if let data = desc.data as Data? {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url.path
            }
        }
        // Try plain string path
        if let str = desc.stringValue, str.hasPrefix("/") {
            return str
        }
        return nil
    }

    /// Finder Services handler — called when user right-clicks a folder
    /// and selects "Open in Crystl" from the Services menu.
    @objc func openInCrystl(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return }
        for url in urls {
            _ = openFolder(url.path)
        }
    }

    /// The base directory for new projects. Defaults to ~/Projects.
    var projectsDirectory: String {
        get {
            let saved = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
            return saved.isEmpty ? (NSHomeDirectory() + "/Projects") : saved
        }
        set { UserDefaults.standard.set(newValue, forKey: "projectsDirectory") }
    }

    /// Creates a new project folder and opens it in a new tab.
    func createAndOpenProject(name: String, path: String? = nil, iconName: String? = nil, colorHex: String? = nil,
                              mcpServers: Set<String> = [], starterIds: Set<UUID> = [], gitInit: Bool = false, remote: String? = nil) {
        let projectPath = path ?? (projectsDirectory + "/" + name)
        let fm = FileManager.default

        // Ensure parent directory exists
        let parentDir = (projectPath as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

        // Create the project folder
        do {
            try fm.createDirectory(atPath: projectPath, withIntermediateDirectories: true)
        } catch {
            NSLog("Crystl: Failed to create project directory: \(error)")
            return
        }

        // Initialize git repository if requested
        if gitInit && !GitWorktree.isGitRepo(projectPath) {
            runGit(["init", projectPath])
            if let remote = remote, !remote.isEmpty {
                runGit(["-C", projectPath, "remote", "add", "origin", remote])
            }
        }

        // Save project config
        var config = ProjectConfig.load(from: projectPath) ?? ProjectConfig()
        config.name = name
        config.icon = iconName
        config.color = colorHex
        config.save(to: projectPath)

        // Write defaults based on user's choices in new project panel
        if !mcpServers.isEmpty {
            MCPConfigManager.shared.syncSelectedToProject(projectPath, serverNames: mcpServers)
        }
        if !starterIds.isEmpty {
            StarterManager.shared.syncToProject(projectPath, starterIds: starterIds)
        }

        _ = openFolder(projectPath, skipDefaults: true)
    }

    // MARK: - Icon Picker

    private var iconPickerPanel: IconPickerPanel?

    /// Shows the icon picker for an existing project tile (right-click "Change Icon").
    func showIconPicker(for tabId: UUID) {
        guard let project = terminalController.projects.first(where: { $0.id == tabId }),
              let railPanel = rail?.panel else { return }

        iconPickerPanel?.dismiss()
        let picker = IconPickerPanel()
        picker.selectedIcon = project.iconName
        picker.selectedColor = project.color
        picker.onSave = { [weak self] iconName, color in
            guard let self = self else { return }
            project.iconName = iconName
            project.color = color
            // Save to disk
            var config = ProjectConfig.load(from: project.directory) ?? ProjectConfig()
            config.icon = iconName
            config.color = color.hexString
            config.save(to: project.directory)
            // Update UI — clear icon cache since color changed
            LucideIcons.clearCache()
            self.rail?.updateTile(tabId: tabId, title: project.title, cwd: project.directory, iconName: iconName, color: color)
            self.terminalController.updateTabBar()
            self.terminalController.updateSessionBar()
        }
        picker.show(relativeTo: railPanel)
        iconPickerPanel = picker
    }

    var approvalFlyout: NSPanel?
    var flyoutModeItems: [String: FlyoutMenuItem] = [:]

    func showRailSettingsMenu(from view: NSView) {
        // Dismiss if already showing
        if approvalFlyout != nil {
            closeFlyout()
            return
        }

        // Only show if Claude integration is enabled in settings
        let claudeEnabled = UserDefaults.standard.object(forKey: "agentEnabled:claude") as? Bool ?? true
        guard claudeEnabled else { return }

        let tc = terminalController!
        let panelWidth: CGFloat = 140
        let itemHeight: CGFloat = 24
        let itemGap: CGFloat = 2
        let modes: [(String, String)] = [("Manual", "manual"), ("Smart", "smart"), ("Auto Approve", "all")]
        let topPad: CGFloat = 14
        let headerLabelH: CGFloat = 14
        let headerGap: CGFloat = 10
        let bottomPad: CGFloat = 14
        let itemCount = CGFloat(modes.count + 1)  // +1 for Pause All
        let panelHeight: CGFloat = topPad + headerLabelH + headerGap + itemCount * itemHeight + (itemCount - 1) * itemGap + bottomPad

        // Position to the right of the rail icon
        let iconScreenFrame = view.window!.convertToScreen(view.convert(view.bounds, to: nil))
        let x = iconScreenFrame.maxX + 16
        let y = iconScreenFrame.midY - panelHeight / 2

        let (panel, glass) = makeGlassPanel(
            width: panelWidth, height: panelHeight, x: x, y: y,
            cornerRadius: 12, glassAlpha: currentOpacity, borderAlpha: 0.3
        )
        panel.contentView = glass

        // Header
        let header = NSTextField(labelWithString: "CLAUDE APPROVAL")
        header.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        header.textColor = NSColor(white: 1.0, alpha: 0.5)
        header.alignment = .center
        header.frame = NSRect(x: 0, y: panelHeight - topPad - headerLabelH, width: panelWidth, height: headerLabelH)
        glass.addSubview(header)

        flyoutModeItems.removeAll()
        var itemY = panelHeight - topPad - headerLabelH - headerGap - itemHeight
        for (label, mode) in modes {
            let isActive = mode == tc.currentModeValue
            let item = FlyoutMenuItem(
                frame: NSRect(x: 8, y: itemY, width: panelWidth - 16, height: itemHeight),
                title: label, isActive: isActive
            )
            item.onClick = { [weak self] in
                self?.terminalController.setMode(mode)
                self?.closeFlyout()
            }
            glass.addSubview(item)
            flyoutModeItems[mode] = item
            itemY -= (itemHeight + itemGap)
        }

        // Pause button
        let isPaused = tc.isPausedValue
        let pauseItem = FlyoutMenuItem(
            frame: NSRect(x: 8, y: itemY, width: panelWidth - 16, height: itemHeight),
            title: isPaused ? "Resume All" : "Pause All",
            isActive: isPaused,
            activeColor: .systemOrange
        )
        pauseItem.onClick = { [weak self] in
            self?.terminalController.togglePause()
            self?.approvalFlyout?.close()
            self?.approvalFlyout = nil
            self?.flyoutModeItems.removeAll()
        }
        glass.addSubview(pauseItem)

        panel.orderFrontRegardless()
        approvalFlyout = panel
        (rail?.iconView as? RailSettingsButton)?.setLocked(true)
        animateLiquidCrystal(panel: panel, cornerRadius: 12, borderAlpha: 0.3)
    }

    func closeFlyout() {
        guard let panel = approvalFlyout else { return }
        approvalFlyout = nil
        flyoutModeItems.removeAll()
        (rail?.iconView as? RailSettingsButton)?.setLocked(false)
        animatePanelOut(panel) {}
    }

    /// Animate selection from current mode to a new mode in the flyout (for demo).
    func animateFlyoutSelection(to mode: String) {
        // Deactivate all, then activate target
        for (key, item) in flyoutModeItems {
            item.setActive(key == mode, animated: true)
        }
        terminalController.setMode(mode)
        updateBridgeSettings(["autoApproveMode": mode])
    }

    private func openFolder(_ path: String, skipDefaults: Bool = false) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        if !skipDefaults {
            // Write defaults only if project doesn't already have them
            MCPConfigManager.shared.syncToProject(path)
            StarterManager.shared.syncAllDefaultsToProject(path)
        }
        terminalController.addProject(cwd: path)
        terminalController.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // ── Menu Actions ──

    @objc func newShard() {
        terminalController.addProject()
    }

    @objc func closeShard() {
        let tc = terminalController!
        if tc.projects.count > 1 {
            tc.closeProject(tc.selectedProjectIndex)
        }
    }

    // ── Bridge Polling ──
    // Polls GET /pending every 0.5s. The response contains pending requests,
    // active sessions, recent history, and current settings. On each poll we
    // sync the UI state and show/dismiss approval panels as needed.

    func poll() {
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/pending") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        if let token = bridgeToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let data = data,
                   let resp = try? JSONDecoder().decode(PollResponse.self, from: data) {
                    self.isConnected = true
                    self.handlePending(resp.pending)
                    if let n = resp.notifications { self.handleNotifications(n) }
                    if let s = resp.sessions { self.currentSessions = s }
                    if let h = resp.history { self.currentHistory = h }
                    if let s = resp.settings {
                        self.currentMode = s.autoApproveMode
                        self.isPaused = s.paused ?? false
                        self.currentEnabledNotifications = s.enabledNotifications
                        self.terminalController.syncSettings(mode: s.autoApproveMode, paused: s.paused ?? false)
                    }
                } else {
                    self.isConnected = false
                    self.dismissAllPanels()
                }
            }
        }.resume()
    }

    /// Left edge for all floating panels — shifted right to clear the Crystal Rail.
    var panelLeftEdge: CGFloat { rail != nil ? 72 : 16 }

    // ── Unified Panel Layout ──
    // All floating panels share a single vertical stack from the top of the screen.
    // Order (top to bottom): notifications, Allow All bar, approval panels, finished cards.

    let panelGap: CGFloat = 8

    func layoutAllPanels() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = panelLeftEdge
        var cursorY = screenFrame.maxY - 16  // start 16px below top

        // "Dismiss All" bar (only if 2+ notification panels)
        let dismissAllBarH: CGFloat = 38
        let dismissAllBarW: CGFloat = 300
        if notificationPanels.count >= 2, let bar = dismissAllNotificationsPanel {
            cursorY -= dismissAllBarH
            animatePanel(bar, to: NSRect(x: x, y: cursorY, width: dismissAllBarW, height: dismissAllBarH))
            cursorY -= panelGap
        }

        let notifHeight: CGFloat = 112
        let notifWidth: CGFloat = 300
        for (_, panel) in notificationPanels {
            cursorY -= notifHeight
            animatePanel(panel, to: NSRect(x: x, y: cursorY, width: notifWidth, height: notifHeight))
            cursorY -= panelGap
        }

        // Allow All bar (only if 2+ approval panels)
        let barHeight: CGFloat = 38
        let barWidth: CGFloat = 300
        if panels.count >= 2, let bar = allowAllPanel {
            cursorY -= barHeight
            animatePanel(bar, to: NSRect(x: x, y: cursorY, width: barWidth, height: barHeight))
            cursorY -= panelGap
        }

        // Approval panels
        let approvalWidth: CGFloat = 300
        let approvalHeight: CGFloat = 118
        for (_, panel) in panels {
            cursorY -= approvalHeight
            animatePanel(panel, to: NSRect(x: x, y: cursorY, width: approvalWidth, height: approvalHeight))
            cursorY -= panelGap
        }

        // Process-finished cards
        let finishedWidth: CGFloat = 300
        let finishedHeight: CGFloat = 60
        for panel in finishedPanels {
            cursorY -= finishedHeight
            animatePanel(panel, to: NSRect(x: x, y: cursorY, width: finishedWidth, height: finishedHeight))
            cursorY -= panelGap
        }
    }

    private func animatePanel(_ panel: NSPanel, to frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            panel.animator().setFrame(frame, display: true)
        }
    }

    func handlePending(_ pending: [PendingRequest]) {
        let currentIds = Set(pending.map { $0.id })

        for id in knownIds.subtracting(currentIds) {
            dismissPanel(id: id)
        }

        for req in pending where !knownIds.contains(req.id) {
            showApprovalPanel(req)
        }

        knownIds = currentIds
        pendingIds = pending.map { $0.id }

        // Update rail pending indicators
        rail?.updatePending(pending)

        if panels.count >= 2 {
            showAllowAllBar()
        } else {
            dismissAllowAllBar()
        }

        layoutAllPanels()
    }

    // ── Approval Panel ──
    // Floating glass panels that appear on the left side of the screen.
    // Each shows: tab name (headline), tool name (subtitle in session color),
    // tool input detail, Show/Allow/Deny buttons. Styled to match the terminal
    // window with .hudWindow material and translucent green Allow button.

    func showApprovalPanel(_ request: PendingRequest) {
        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 118

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = panelLeftEdge
        // Place off-screen initially; layoutAllPanels() will position it
        let y = screenFrame.maxY + panelHeight

        let (panel, glass) = makeGlassPanel(
            width: panelWidth, height: panelHeight, x: x, y: y,
            cornerRadius: 12, glassAlpha: currentOpacity, borderAlpha: 0.12, movable: true
        )

        let sessColor = colorForSession(request.session_id)

        // Tab name — match by cwd to a terminal tab, fall back to folder name
        let cwd = request.cwd ?? ""
        let tabName: String = {
            if let project = terminalController.projects.first(where: { $0.directory == cwd }) {
                return project.title
            }
            if let project = terminalController.projects.first(where: { cwd.hasPrefix($0.directory) || $0.directory.hasPrefix(cwd) }) {
                return project.title
            }
            return extractProjectName(cwd)
        }()
        // Tab name — large headline, with project icon if available
        if !tabName.isEmpty {
            var nameLabelX: CGFloat = 16
            let iconSize: CGFloat = 18
            let matchedProject = terminalController.projects.first(where: { $0.directory == cwd })
                ?? terminalController.projects.first(where: { cwd.hasPrefix($0.directory) || $0.directory.hasPrefix(cwd) })
            let iconColor = matchedProject?.color ?? sessColor
            if let project = matchedProject,
               let iconName = project.iconName,
               let icon = LucideIcons.render(name: iconName, size: iconSize, color: iconColor) {
                let iconRect = NSRect(x: 16, y: panelHeight - 30, width: iconSize, height: iconSize)
                let iconView = NSImageView(frame: iconRect)
                iconView.image = icon
                glass.addSubview(iconView)
                nameLabelX = 16 + iconSize + 6
            }
            let nameLabel = NSTextField(labelWithString: tabName)
            nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            nameLabel.textColor = .white
            nameLabel.frame = NSRect(x: nameLabelX, y: panelHeight - 30, width: panelWidth - nameLabelX - 60, height: 20)
            glass.addSubview(nameLabel)
        }

        // Tool name — smaller subtitle
        let toolLabel = NSTextField(labelWithString: request.tool_name)
        toolLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        toolLabel.textColor = sessColor.withAlphaComponent(0.8)
        let toolY = tabName.isEmpty ? panelHeight - 30 : panelHeight - 50
        toolLabel.frame = NSRect(x: 16, y: toolY, width: panelWidth - 80, height: 16)
        glass.addSubview(toolLabel)

        // "Show" button — navigates to matching tab
        let showBtn = NSButton(frame: NSRect(x: panelWidth - 62, y: panelHeight - 30, width: 50, height: 18))
        showBtn.title = "Show ›"
        showBtn.bezelStyle = .rounded
        showBtn.isBordered = false
        showBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        showBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        showBtn.target = self
        showBtn.action = #selector(showTabClicked(_:))
        showBtn.identifier = NSUserInterfaceItemIdentifier("show_" + request.id)
        glass.addSubview(showBtn)

        // Detail text
        let detail = formatToolInput(request.tool_input)
        if !detail.isEmpty {
            let detailLabel = NSTextField(labelWithString: detail)
            detailLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = NSColor(white: 1.0, alpha: 0.6)
            detailLabel.maximumNumberOfLines = 1
            detailLabel.lineBreakMode = .byTruncatingTail
            detailLabel.cell?.isScrollable = false
            detailLabel.isSelectable = false
            detailLabel.frame = NSRect(x: 16, y: toolY - 18, width: panelWidth - 32, height: 16)
            glass.addSubview(detailLabel)
        }

        // Buttons
        let btnWidth = (panelWidth - 44) / 2
        let btnHeight: CGFloat = 28

        let denyBtn = NSButton(frame: NSRect(x: 14, y: 8, width: btnWidth, height: btnHeight))
        denyBtn.title = "Deny"
        denyBtn.bezelStyle = .rounded
        denyBtn.isBordered = false
        denyBtn.wantsLayer = true
        denyBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        denyBtn.layer?.cornerRadius = 8
        denyBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        denyBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
        denyBtn.target = self
        denyBtn.action = #selector(denyClicked(_:))
        denyBtn.identifier = NSUserInterfaceItemIdentifier(request.id)
        glass.addSubview(denyBtn)

        let allowBtn = NSButton(frame: NSRect(x: panelWidth / 2 + 2, y: 8, width: btnWidth, height: btnHeight))
        allowBtn.title = "Allow"
        allowBtn.bezelStyle = .rounded
        allowBtn.isBordered = false
        allowBtn.wantsLayer = true
        allowBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor
        allowBtn.layer?.cornerRadius = 8
        allowBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        allowBtn.contentTintColor = NSColor.systemGreen
        allowBtn.target = self
        allowBtn.action = #selector(allowClicked(_:))
        allowBtn.identifier = NSUserInterfaceItemIdentifier(request.id)
        allowBtn.keyEquivalent = "\r"
        glass.addSubview(allowBtn)

        panel.contentView = glass
        panel.orderFrontRegardless()
        panels[request.id] = panel
        panelCwds[request.id] = request.cwd ?? ""

        animateLiquidCrystal(panel: panel, cornerRadius: 12, borderAlpha: 0.12)
    }

    @objc func allowClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        sendDecision(id: id, decision: "allow")
        dismissPanel(id: id)
    }

    @objc func denyClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        sendDecision(id: id, decision: "deny")
        dismissPanel(id: id)
    }

    @objc func showTabClicked(_ sender: NSButton) {
        guard let rawId = sender.identifier?.rawValue,
              rawId.hasPrefix("show_") else { return }
        let id = String(rawId.dropFirst(5))
        focusTabByCwd(panelCwds[id] ?? "")
    }

    func focusTabByCwd(_ cwd: String) {
        guard !cwd.isEmpty else { return }
        // Find a project whose directory matches (or is a parent/child)
        if let idx = terminalController.projects.firstIndex(where: { $0.directory == cwd }) {
            terminalController.selectProject(idx)
        } else if let idx = terminalController.projects.firstIndex(where: { cwd.hasPrefix($0.directory) || $0.directory.hasPrefix(cwd) }) {
            terminalController.selectProject(idx)
        }
        terminalController.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissPanel(id: String) {
        guard let panel = panels[id] else { return }
        panels.removeValue(forKey: id)
        panelCwds.removeValue(forKey: id)
        knownIds.remove(id)
        animatePanelOut(panel) { [weak self] in
            self?.repositionPanels()
        }
    }

    func dismissAllPanels() {
        for id in Array(panels.keys) {
            dismissPanel(id: id)
        }
        dismissAllowAllBar()
        rail?.clearAllPending()
    }

    // ── Allow All Bar ──
    // A detached bar that floats 12px above the top approval card.
    // Only shown when 2+ requests are pending. Approves all at once.

    func showAllowAllBar() {
        let barWidth: CGFloat = 300
        let barHeight: CGFloat = 38

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = panelLeftEdge

        if let existing = allowAllPanel {
            if let btn = existing.contentView?.subviews.compactMap({ $0 as? NSButton }).first {
                btn.title = "Allow All (\(panels.count))"
            }
            return  // layoutAllPanels() handles positioning
        }

        // Place off-screen initially; layoutAllPanels() will position it
        let y = screenFrame.maxY + barHeight

        let (panel, glass) = makeGlassPanel(
            width: barWidth, height: barHeight, x: x, y: y,
            cornerRadius: 10, glassAlpha: currentOpacity, borderAlpha: 0.12
        )

        let allowAllBtn = NSButton(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        allowAllBtn.title = "Allow All (\(panels.count))"
        allowAllBtn.bezelStyle = .rounded
        allowAllBtn.isBordered = false
        allowAllBtn.wantsLayer = true
        allowAllBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.2).cgColor
        allowAllBtn.layer?.cornerRadius = 10
        allowAllBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        allowAllBtn.contentTintColor = NSColor.systemGreen
        allowAllBtn.target = self
        allowAllBtn.action = #selector(allowAllClicked)
        glass.addSubview(allowAllBtn)

        panel.contentView = glass
        panel.orderFrontRegardless()
        allowAllPanel = panel

        animateLiquidCrystal(panel: panel, cornerRadius: 10, borderAlpha: 0.12)
    }

    func dismissAllowAllBar() {
        guard let panel = allowAllPanel else { return }
        allowAllPanel = nil
        animatePanelOut(panel) {}
    }

    @objc func allowAllClicked() {
        let ids = pendingIds
        for id in ids {
            sendDecision(id: id, decision: "allow")
        }
        dismissAllPanels()
    }

    func applyPanelOpacity(_ sliderVal: CGFloat) {
        let opacity = opacityFromSlider(sliderVal)

        let allPanels: [NSPanel] = Array(panels.values) + Array(notificationPanels.values)
            + finishedPanels + [allowAllPanel, dismissAllNotificationsPanel].compactMap { $0 }

        for panel in allPanels {
            if let glass = panel.contentView as? NSVisualEffectView {
                glass.alphaValue = opacity.glassAlpha
                if let backing = findCharcoalBacking(in: glass) {
                    backing.alphaValue = opacity.darkAlpha
                }
            }
        }
    }

    func repositionPanels() {
        if panels.count >= 2 {
            showAllowAllBar()
        } else {
            dismissAllowAllBar()
        }
        layoutAllPanels()
    }

    // ── Hook Notifications ──
    // Unified notification cards for non-permission hook events (Stop, PostToolUse, etc.)
    // Stack from top-left (same side as approval panels), auto-dismiss after 8 seconds.

    func handleNotifications(_ incoming: [HookNotification]) {
        let incomingIds = Set(incoming.map { $0.id })

        // Remove panels for notifications no longer present
        for id in knownNotificationIds.subtracting(incomingIds) {
            dismissNotificationPanel(id: id)
        }

        // Show panels for new notifications
        for notif in incoming where !knownNotificationIds.contains(notif.id) {
            // Cap at 4 — dismiss oldest to make room
            if notificationPanels.count >= 4, let oldestId = notificationPanels.keys.first {
                dismissNotificationOnBridge(id: oldestId)
            }
            showNotificationPanel(notif)
        }

        knownNotificationIds = incomingIds
        updateDismissAllNotificationsBar()
        layoutAllPanels()
    }

    func showNotificationPanel(_ notif: HookNotification) {
        let cardWidth: CGFloat = 300
        let cardHeight: CGFloat = 112
        let btnHeight: CGFloat = 28

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = panelLeftEdge
        // Place off-screen initially; layoutAllPanels() will position it
        let y = screenFrame.maxY + cardHeight

        let (panel, glass) = makeGlassPanel(
            width: cardWidth, height: cardHeight, x: x, y: y,
            cornerRadius: 12, glassAlpha: currentOpacity, borderAlpha: 0.12
        )

        let sessColor = colorForSession(notif.session_id ?? "")

        // Project name — match by cwd to a terminal tab, fall back to folder name
        let cwd = notif.cwd ?? ""
        let tabName: String = {
            if let project = terminalController.projects.first(where: { $0.directory == cwd }) {
                return project.title
            }
            if let project = terminalController.projects.first(where: { cwd.hasPrefix($0.directory) || $0.directory.hasPrefix(cwd) }) {
                return project.title
            }
            return extractProjectName(cwd)
        }()
        if !tabName.isEmpty {
            var nameLabelX: CGFloat = 16
            let iconSize: CGFloat = 18
            let matchedProject = terminalController.projects.first(where: { $0.directory == cwd })
                ?? terminalController.projects.first(where: { cwd.hasPrefix($0.directory) || $0.directory.hasPrefix(cwd) })
            let iconColor = matchedProject?.color ?? sessColor
            if let project = matchedProject,
               let iconName = project.iconName,
               let icon = LucideIcons.render(name: iconName, size: iconSize, color: iconColor) {
                let iconRect = NSRect(x: 16, y: cardHeight - 30, width: iconSize, height: iconSize)
                let iconView = NSImageView(frame: iconRect)
                iconView.image = icon
                glass.addSubview(iconView)
                nameLabelX = 16 + iconSize + 6
            }
            let nameLabel = NSTextField(labelWithString: tabName)
            nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            nameLabel.textColor = .white
            nameLabel.frame = NSRect(x: nameLabelX, y: cardHeight - 30, width: cardWidth - nameLabelX - 60, height: 20)
            glass.addSubview(nameLabel)
        }

        // Headline — colored subtitle (like tool name on approval panels)
        let headlineLabel = NSTextField(labelWithString: notif.headline)
        headlineLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        headlineLabel.textColor = sessColor.withAlphaComponent(0.8)
        let headlineY = tabName.isEmpty ? cardHeight - 30 : cardHeight - 50
        headlineLabel.frame = NSRect(x: 16, y: headlineY, width: cardWidth - 80, height: 16)
        headlineLabel.lineBreakMode = .byTruncatingTail
        glass.addSubview(headlineLabel)

        // "Show" button — top right
        if notif.cwd != nil {
            let showBtn = NSButton(frame: NSRect(x: cardWidth - 62, y: cardHeight - 30, width: 50, height: 18))
            showBtn.title = "Show ›"
            showBtn.bezelStyle = .rounded
            showBtn.isBordered = false
            showBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            showBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
            showBtn.target = self
            showBtn.action = #selector(notificationShowClicked(_:))
            showBtn.identifier = NSUserInterfaceItemIdentifier("notif_" + (notif.cwd ?? ""))
            glass.addSubview(showBtn)
        }

        // Detail text
        let sub = notif.subtitle
        if !sub.isEmpty {
            let subLabel = NSTextField(labelWithString: sub)
            subLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            subLabel.textColor = NSColor(white: 1.0, alpha: 0.6)
            subLabel.frame = NSRect(x: 16, y: headlineY - 18, width: cardWidth - 32, height: 16)
            subLabel.lineBreakMode = .byTruncatingTail
            glass.addSubview(subLabel)
        }

        // Dismiss button — full width, same position/style as Allow button on approval panels
        let dismissBtn = NSButton(frame: NSRect(x: 12, y: 8, width: cardWidth - 24, height: btnHeight))
        dismissBtn.title = "Dismiss"
        dismissBtn.bezelStyle = .rounded
        dismissBtn.isBordered = false
        dismissBtn.wantsLayer = true
        dismissBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        dismissBtn.layer?.cornerRadius = 8
        dismissBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        dismissBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
        dismissBtn.target = self
        dismissBtn.action = #selector(notificationDismissClicked(_:))
        dismissBtn.identifier = NSUserInterfaceItemIdentifier("ndismiss_" + notif.id)
        glass.addSubview(dismissBtn)

        panel.contentView = glass
        panel.orderFrontRegardless()

        animateLiquidCrystal(panel: panel, cornerRadius: 12, borderAlpha: 0.12)

        notificationPanels[notif.id] = panel

    }

    func dismissNotificationPanel(id: String) {
        notificationDismissTimers[id]?.invalidate()
        notificationDismissTimers.removeValue(forKey: id)
        guard let panel = notificationPanels.removeValue(forKey: id) else { return }
        knownNotificationIds.remove(id)
        updateDismissAllNotificationsBar()
        repositionNotificationPanels()
        animatePanelOut(panel) {}
    }

    func repositionNotificationPanels() {
        layoutAllPanels()
    }

    func dismissNotificationOnBridge(id: String) {
        dismissNotificationPanel(id: id)
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/dismiss-notification") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bridgeToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id])
        URLSession.shared.dataTask(with: req).resume()
    }

    @objc func notificationDismissClicked(_ sender: NSButton) {
        guard let rawId = sender.identifier?.rawValue,
              rawId.hasPrefix("ndismiss_") else { return }
        let id = String(rawId.dropFirst("ndismiss_".count))
        dismissNotificationOnBridge(id: id)
    }

    @objc func notificationShowClicked(_ sender: NSButton) {
        guard let rawId = sender.identifier?.rawValue,
              rawId.hasPrefix("notif_") else { return }
        let cwd = String(rawId.dropFirst("notif_".count))
        focusTabByCwd(cwd)
    }

    // ── Dismiss All Notifications Bar ──

    func showDismissAllNotificationsBar() {
        let barWidth: CGFloat = 300
        let barHeight: CGFloat = 38

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = panelLeftEdge

        if let existing = dismissAllNotificationsPanel {
            if let btn = existing.contentView?.subviews.compactMap({ $0 as? NSButton }).first {
                btn.title = "Dismiss All (\(notificationPanels.count))"
            }
            return
        }

        let y = screenFrame.maxY + barHeight

        let (panel, glass) = makeGlassPanel(
            width: barWidth, height: barHeight, x: x, y: y,
            cornerRadius: 10, glassAlpha: currentOpacity, borderAlpha: 0.12
        )

        let btn = NSButton(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        btn.title = "Dismiss All (\(notificationPanels.count))"
        btn.bezelStyle = .rounded
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        btn.layer?.cornerRadius = 10
        btn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        btn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        btn.target = self
        btn.action = #selector(dismissAllNotificationsClicked)
        glass.addSubview(btn)

        panel.contentView = glass
        panel.orderFrontRegardless()
        dismissAllNotificationsPanel = panel

        animateLiquidCrystal(panel: panel, cornerRadius: 10, borderAlpha: 0.12)
    }

    func hideDismissAllNotificationsBar() {
        guard let panel = dismissAllNotificationsPanel else { return }
        dismissAllNotificationsPanel = nil
        animatePanelOut(panel) {}
    }

    @objc func dismissAllNotificationsClicked() {
        let ids = Array(notificationPanels.keys)
        for id in ids {
            dismissNotificationOnBridge(id: id)
        }
        hideDismissAllNotificationsBar()
    }

    func updateDismissAllNotificationsBar() {
        if notificationPanels.count >= 2 {
            showDismissAllNotificationsBar()
        } else {
            hideDismissAllNotificationsBar()
        }
    }

    // ── Process Finished Notification ──
    // Small card shown at the top-left when a terminal process exits.
    // Persists until manually dismissed via the X button.

    func showProcessFinishedCard(tabTitle: String, cwd: String) {
        let cardWidth: CGFloat = 300
        let cardHeight: CGFloat = 60

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = panelLeftEdge
        // Place off-screen initially; layoutAllPanels() will position it
        let y = screenFrame.maxY + cardHeight

        let (panel, glass) = makeGlassPanel(
            width: cardWidth, height: cardHeight, x: x, y: y,
            cornerRadius: 12, glassAlpha: currentOpacity, borderAlpha: 0.12
        )

        let titleLabel = NSTextField(labelWithString: "\u{2713} \(tabTitle)")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 14, y: cardHeight - 26, width: cardWidth - 28, height: 18)
        glass.addSubview(titleLabel)

        let subLabel = NSTextField(labelWithString: "Process finished")
        subLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subLabel.textColor = NSColor(white: 1.0, alpha: 0.45)
        subLabel.frame = NSRect(x: 14, y: 10, width: cardWidth - 70, height: 16)
        glass.addSubview(subLabel)

        // "Show" button
        let showBtn = NSButton(frame: NSRect(x: cardWidth - 58, y: 8, width: 48, height: 20))
        showBtn.title = "Show ›"
        showBtn.bezelStyle = .rounded
        showBtn.isBordered = false
        showBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        showBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
        showBtn.target = self
        showBtn.action = #selector(finishedShowClicked(_:))
        showBtn.identifier = NSUserInterfaceItemIdentifier("fin_" + cwd)
        glass.addSubview(showBtn)

        // Dismiss button
        let dismissBtn = NSButton(frame: NSRect(x: cardWidth - 24, y: cardHeight - 22, width: 16, height: 16))
        dismissBtn.title = "\u{2715}"
        dismissBtn.bezelStyle = .rounded
        dismissBtn.isBordered = false
        dismissBtn.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        dismissBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.35)
        dismissBtn.target = self
        dismissBtn.action = #selector(dismissFinishedCard(_:))
        glass.addSubview(dismissBtn)

        panel.contentView = glass
        panel.orderFrontRegardless()

        animateLiquidCrystal(panel: panel, cornerRadius: 12, borderAlpha: 0.12)

        finishedPanels.append(panel)
        layoutAllPanels()
    }

    @objc func dismissFinishedCard(_ sender: NSButton) {
        guard let panel = sender.window as? NSPanel else { return }
        finishedPanels.removeAll { $0 === panel }
        animatePanelOut(panel) { [weak self] in
            self?.layoutAllPanels()
        }
    }

    @objc func finishedShowClicked(_ sender: NSButton) {
        guard let rawId = sender.identifier?.rawValue,
              rawId.hasPrefix("fin_") else { return }
        let cwd = String(rawId.dropFirst(4))
        focusTabByCwd(cwd)
    }

    // ── Bridge Communication ──
    // HTTP helpers for sending decisions and settings to claude-bridge.js.

    func updateBridgeSettings(_ update: [String: Any]) {
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bridgeToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: update)
        URLSession.shared.dataTask(with: req).resume()
    }

    func sendDecision(id: String, decision: String) {
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/decide") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = bridgeToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = try? JSONEncoder().encode(DecisionBody(id: id, decision: decision))
        URLSession.shared.dataTask(with: req).resume()
    }

    // ── Liquid Crystal Animation ──
    // Reusable panel open animation: scale from center, blur-to-sharp,
    // prismatic shimmer sweep, and border glow. Adapted from the main
    // window animation with shorter duration for smaller elements.

    private func animateLiquidCrystal(panel: NSPanel, cornerRadius: CGFloat, borderAlpha: CGFloat = 0.7) {
        guard let contentView = panel.contentView else { return }
        contentView.wantsLayer = true
        guard let layer = contentView.layer else { return }

        // Hide shadow during scale-up so it doesn't sit at full size
        panel.hasShadow = false

        let duration: CFTimeInterval = 0.5
        let fluidTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        // Anchor to center for scale
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)

        // Scale: liquid expansion from center
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.0
        scale.toValue = 1.0
        scale.duration = duration
        scale.timingFunction = fluidTiming

        // Corner radius: circle -> rounded rect
        let corners = CABasicAnimation(keyPath: "cornerRadius")
        corners.fromValue = min(contentView.bounds.width, contentView.bounds.height) / 2
        corners.toValue = cornerRadius
        corners.duration = duration * 0.7
        corners.timingFunction = fluidTiming

        // Opacity: materialise
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = duration * 0.4
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)

        // Border glow: bright flash that fades
        let borderColor = CABasicAnimation(keyPath: "borderColor")
        borderColor.fromValue = NSColor(white: 1.0, alpha: 1.0).cgColor
        borderColor.toValue = NSColor(white: 1.0, alpha: borderAlpha).cgColor
        borderColor.duration = duration * 1.2
        borderColor.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let borderWidth = CABasicAnimation(keyPath: "borderWidth")
        borderWidth.fromValue = 2.0
        borderWidth.toValue = 0.5
        borderWidth.duration = duration * 1.2
        borderWidth.timingFunction = CAMediaTimingFunction(name: .easeOut)

        // Gaussian blur: start soft, sharpen as crystal forms
        if let blur = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 0.0]) {
            layer.filters = [blur]
            layer.setValue(0, forKeyPath: "filters.gaussianBlur.inputRadius")

            let blurAnim = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            blurAnim.fromValue = 8.0
            blurAnim.toValue = 0.0
            blurAnim.duration = duration * 0.8
            blurAnim.timingFunction = fluidTiming
            layer.add(blurAnim, forKey: "crystalBlur")
        }

        // Set final values
        layer.transform = CATransform3DIdentity
        layer.cornerRadius = cornerRadius
        layer.opacity = 1.0
        layer.borderWidth = 0.5
        layer.borderColor = NSColor(white: 1.0, alpha: borderAlpha).cgColor

        // Run main animations
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak panel] in
            layer.filters = nil
            panel?.hasShadow = true
        }
        layer.add(scale, forKey: "crystalScale")
        layer.add(corners, forKey: "crystalCorners")
        layer.add(opacity, forKey: "crystalOpacity")
        layer.add(borderColor, forKey: "crystalBorderColor")
        layer.add(borderWidth, forKey: "crystalBorderWidth")
        CATransaction.commit()

        // Shimmer pass: sweeps across after panel has mostly formed
        addShimmerSweep(
            to: layer, bounds: contentView.bounds, cornerRadius: cornerRadius,
            delay: duration * 0.25
        )
    }

    // MARK: - Project Settings Panel

    private var setupPanel: NewProjectPanel?

    func showSetupPanel(for tc: TerminalWindowController) {
        setupPanel?.dismiss()

        let project = tc.selectedProject
        let panel = NewProjectPanel()

        panel.onSubmit = { [weak self, weak tc] name, projectPath, iconName, colorHex, mcpServers, starterIds, gitInit, remote in
            guard let self = self, let tc = tc else { return }

            let fm = FileManager.default

            // Create project directory
            let parentDir = (projectPath as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            try? fm.createDirectory(atPath: projectPath, withIntermediateDirectories: true)

            // Initialize git repository if requested
            if gitInit && !GitWorktree.isGitRepo(projectPath) {
                self.runGit(["init", projectPath])
                if let remote = remote, !remote.isEmpty {
                    self.runGit(["-C", projectPath, "remote", "add", "origin", remote])
                }
            }

            // Save project config (merge with existing)
            var config = ProjectConfig.load(from: projectPath) ?? ProjectConfig()
            config.name = name
            config.icon = iconName
            config.color = colorHex
            config.save(to: projectPath)

            // Sync MCP and starters
            if !mcpServers.isEmpty {
                MCPConfigManager.shared.syncSelectedToProject(projectPath, serverNames: mcpServers)
            }
            if !starterIds.isEmpty {
                StarterManager.shared.syncToProject(projectPath, starterIds: starterIds)
            }

            // Configure the current tab
            let color = colorHex.flatMap { NSColor(hex: $0) }
            tc.configureCurrentProject(name: name, path: projectPath, iconName: iconName, color: color)

            self.setupPanel = nil
        }

        // Position relative to the terminal window
        let winFrame = tc.window.frame
        let panelW: CGFloat = 320
        let panelH = panel.panelHeight
        let x = winFrame.midX - panelW / 2
        let y = winFrame.origin.y + 60
        panel.show(at: NSPoint(x: x, y: y))

        // Pre-populate with existing project data
        if let project = project, !project.isUnconfigured {
            panel.populate(
                name: project.title,
                path: project.directory,
                iconName: project.iconName,
                color: project.color
            )
        }

        setupPanel = panel
    }

    // MARK: - Git Helpers

    private func runGit(_ args: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Menu Actions

    @objc func showSettings() {
        if !terminalController.isShowingSettings {
            terminalController.flipToSettings()
        }
        terminalController.window.makeKeyAndOrderFront(nil)
    }

    @objc func newTab() {
        terminalController.addProject()
        terminalController.window.makeKeyAndOrderFront(nil)
    }

    @objc func closeTab() {
        let tc = terminalController!
        if tc.projects.count > 1 {
            tc.closeProject(tc.selectedProjectIndex)
        } else {
            tc.window.performClose(nil)
        }
    }

    @objc func selectNextTab() {
        let tc = terminalController!
        let next = (tc.selectedProjectIndex + 1) % tc.projects.count
        tc.selectProject(next)
    }

    @objc func selectPreviousTab() {
        let tc = terminalController!
        let prev = (tc.selectedProjectIndex - 1 + tc.projects.count) % tc.projects.count
        tc.selectProject(prev)
    }

    @objc func openHelp() {
        NSWorkspace.shared.open(URL(string: "https://github.com/nerves76/crystl")!)
    }
}
