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

    var knownIds: Set<String> = []            // Currently displayed request IDs
    var pendingIds: [String] = []             // Ordered list for Allow All
    let bridgePort = 19280
    var isConnected = false
    var currentMode: String = "manual"
    var currentSessions: [SessionInfo] = []
    var currentHistory: [HistoryEntry] = []
    var isPaused: Bool = false

    var pendingFolders: [String] = []

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
        terminalController.setup()

        // Set up Crystal Rail
        let r = CrystalRailController()
        r.onTileClicked = { [weak self] tabId in
            guard let self = self else { return }
            if let idx = self.terminalController.tabs.firstIndex(where: { $0.id == tabId }) {
                self.terminalController.selectTab(idx)
                self.terminalController.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        r.onFolderDropped = { [weak self] path in
            _ = self?.openFolder(path)
        }
        r.onAddClicked = { [weak self] in
            self?.terminalController.addTab(showPicker: true)
            self?.terminalController.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        r.onNewProject = { [weak self] name in
            self?.createAndOpenProject(name: name)
        }
        r.onSettingsIconClicked = { [weak self] view in
            self?.showRailSettingsMenu(from: view)
        }
        r.setup()

        // Add tiles for any existing tabs
        for tab in terminalController.tabs {
            r.addTile(tab: tab)
        }
        if let firstTab = terminalController.tabs.first {
            r.selectTile(tabId: firstTab.id)
        }
        rail = r

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
    func createAndOpenProject(name: String) {
        let projectPath = projectsDirectory + "/" + name
        let fm = FileManager.default

        // Ensure projects directory exists
        try? fm.createDirectory(atPath: projectsDirectory, withIntermediateDirectories: true)

        // Create the project folder
        do {
            try fm.createDirectory(atPath: projectPath, withIntermediateDirectories: true)
        } catch {
            NSLog("Crystl: Failed to create project directory: \(error)")
            return
        }

        _ = openFolder(projectPath)
    }

    private var approvalFlyout: NSPanel?

    func showRailSettingsMenu(from view: NSView) {
        // Dismiss if already showing
        if let existing = approvalFlyout {
            existing.close()
            approvalFlyout = nil
            return
        }

        let tc = terminalController!
        let panelWidth: CGFloat = 140
        let btnHeight: CGFloat = 28
        let modes: [(String, String)] = [("Manual", "manual"), ("Smart", "smart"), ("Auto", "all")]
        let panelHeight: CGFloat = CGFloat(modes.count + 1) * btnHeight + 16  // +1 for Pause, padding

        // Position to the right of the rail icon
        let iconScreenFrame = view.window!.convertToScreen(view.convert(view.bounds, to: nil))
        let x = iconScreenFrame.maxX + 6
        let y = iconScreenFrame.midY - panelHeight / 2

        let (panel, glass) = makeGlassPanel(
            width: panelWidth, height: panelHeight, x: x, y: y,
            cornerRadius: 12, glassAlpha: 0.85, borderAlpha: 0.3
        )
        panel.contentView = glass

        var btnY = panelHeight - btnHeight - 8
        for (label, mode) in modes {
            let isActive = mode == tc.currentModeValue
            let btn = NSButton(frame: NSRect(x: 8, y: btnY, width: panelWidth - 16, height: btnHeight))
            btn.title = label
            btn.bezelStyle = .rounded
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 6
            btn.layer?.backgroundColor = isActive
                ? NSColor(white: 1.0, alpha: 0.15).cgColor
                : NSColor.clear.cgColor
            btn.font = NSFont.systemFont(ofSize: 12, weight: isActive ? .semibold : .regular)
            btn.contentTintColor = isActive ? .white : NSColor(white: 1.0, alpha: 0.6)
            btn.target = self
            btn.action = #selector(railMenuModeSelected(_:))
            btn.identifier = NSUserInterfaceItemIdentifier(mode)
            glass.addSubview(btn)
            btnY -= btnHeight
        }

        // Separator
        let sep = NSView(frame: NSRect(x: 12, y: btnY + btnHeight - 2, width: panelWidth - 24, height: 0.5))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
        glass.addSubview(sep)

        // Pause button
        let pauseBtn = NSButton(frame: NSRect(x: 8, y: btnY, width: panelWidth - 16, height: btnHeight))
        pauseBtn.title = tc.isPausedValue ? "Resume" : "Pause"
        pauseBtn.bezelStyle = .rounded
        pauseBtn.isBordered = false
        pauseBtn.wantsLayer = true
        pauseBtn.layer?.cornerRadius = 6
        pauseBtn.layer?.backgroundColor = tc.isPausedValue
            ? NSColor.systemOrange.withAlphaComponent(0.2).cgColor
            : NSColor.clear.cgColor
        pauseBtn.font = NSFont.systemFont(ofSize: 12, weight: tc.isPausedValue ? .semibold : .regular)
        pauseBtn.contentTintColor = tc.isPausedValue
            ? NSColor.systemOrange
            : NSColor(white: 1.0, alpha: 0.6)
        pauseBtn.target = self
        pauseBtn.action = #selector(railMenuPauseToggled)
        glass.addSubview(pauseBtn)

        panel.orderFrontRegardless()
        approvalFlyout = panel
    }

    @objc func railMenuModeSelected(_ sender: NSButton) {
        guard let mode = sender.identifier?.rawValue else { return }
        terminalController.setMode(mode)
        approvalFlyout?.close()
        approvalFlyout = nil
    }

    @objc func railMenuPauseToggled() {
        terminalController.togglePause()
        approvalFlyout?.close()
        approvalFlyout = nil
    }

    private func openFolder(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return false
        }
        terminalController.addTab(cwd: path)
        terminalController.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // ── Menu Actions ──

    @objc func newShard() {
        terminalController.addTab()
    }

    @objc func closeShard() {
        let tc = terminalController!
        if tc.tabs.count > 1 {
            tc.closeTab(tc.selectedIndex)
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
                    if let s = resp.sessions { self.currentSessions = s }
                    if let h = resp.history { self.currentHistory = h }
                    if let s = resp.settings {
                        self.currentMode = s.autoApproveMode
                        self.isPaused = s.paused ?? false
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
    }

    // ── Approval Panel ──
    // Floating glass panels that appear on the left side of the screen.
    // Each shows: tab name (headline), tool name (subtitle in session color),
    // tool input detail, Show/Allow/Deny buttons. Styled to match the terminal
    // window with .hudWindow material and translucent green Allow button.

    func showApprovalPanel(_ request: PendingRequest) {
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 158

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let existingCount = CGFloat(panels.count)
        let x: CGFloat = panelLeftEdge
        let centerY = screenFrame.midY + (screenFrame.height * 0.1)
        let y = centerY - (panelHeight / 2) - (existingCount * (panelHeight + 12))

        let (panel, glass) = makeGlassPanel(
            width: panelWidth, height: panelHeight, x: x, y: y,
            cornerRadius: 16, movable: true
        )

        // Session-colored glow at top
        let sessColor = colorForSession(request.session_id)
        let glow = GlowView(frame: NSRect(x: 0, y: panelHeight - 50, width: panelWidth, height: 50))
        glow.color = sessColor
        glass.addSubview(glow)

        // Tab name — match by cwd to a terminal tab, fall back to folder name
        let cwd = request.cwd ?? ""
        let tabName: String = {
            if let tab = terminalController.tabs.first(where: { $0.cwd == cwd }) {
                return tab.title
            }
            if let tab = terminalController.tabs.first(where: { cwd.hasPrefix($0.cwd) || $0.cwd.hasPrefix(cwd) }) {
                return tab.title
            }
            return extractProjectName(cwd)
        }()
        // Tab name — large headline
        if !tabName.isEmpty {
            let nameLabel = NSTextField(labelWithString: tabName)
            nameLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
            nameLabel.textColor = .white
            nameLabel.frame = NSRect(x: 16, y: panelHeight - 34, width: panelWidth - 80, height: 20)
            glass.addSubview(nameLabel)
        }

        // Tool name — smaller subtitle
        let toolLabel = NSTextField(labelWithString: request.tool_name)
        toolLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        toolLabel.textColor = sessColor.withAlphaComponent(0.8)
        let toolY = tabName.isEmpty ? panelHeight - 34 : panelHeight - 50
        toolLabel.frame = NSRect(x: 16, y: toolY, width: panelWidth - 80, height: 16)
        glass.addSubview(toolLabel)

        // "Show" button — navigates to matching tab
        let showBtn = NSButton(frame: NSRect(x: panelWidth - 62, y: panelHeight - 34, width: 50, height: 18))
        showBtn.title = "Show ›"
        showBtn.bezelStyle = .rounded
        showBtn.isBordered = false
        showBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        showBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.4)
        showBtn.target = self
        showBtn.action = #selector(showTabClicked(_:))
        showBtn.identifier = NSUserInterfaceItemIdentifier("show_" + request.id)
        glass.addSubview(showBtn)

        // Detail text
        let detail = formatToolInput(request.tool_input)
        if !detail.isEmpty {
            let detailLabel = NSTextField(wrappingLabelWithString: detail)
            detailLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            detailLabel.maximumNumberOfLines = 2
            detailLabel.lineBreakMode = .byTruncatingTail
            detailLabel.frame = NSRect(x: 16, y: 48, width: panelWidth - 32, height: 36)
            glass.addSubview(detailLabel)
        }

        // Buttons
        let btnWidth = (panelWidth - 44) / 2
        let btnHeight: CGFloat = 30

        let denyBtn = NSButton(frame: NSRect(x: 14, y: 10, width: btnWidth, height: btnHeight))
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

        let allowBtn = NSButton(frame: NSRect(x: panelWidth / 2 + 2, y: 10, width: btnWidth, height: btnHeight))
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

        animateLiquidCrystal(panel: panel, cornerRadius: 16)
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
        // Find a tab whose cwd matches (or is a parent/child)
        if let idx = terminalController.tabs.firstIndex(where: { $0.cwd == cwd }) {
            terminalController.selectTab(idx)
        } else if let idx = terminalController.tabs.firstIndex(where: { cwd.hasPrefix($0.cwd) || $0.cwd.hasPrefix(cwd) }) {
            terminalController.selectTab(idx)
        }
        terminalController.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismissPanel(id: String) {
        guard let panel = panels[id] else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            panel.close()
            self.panels.removeValue(forKey: id)
            self.panelCwds.removeValue(forKey: id)
            self.knownIds.remove(id)
            self.repositionPanels()
        })
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
        let barWidth: CGFloat = 340
        let barHeight: CGFloat = 38

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelHeight: CGFloat = 158
        let x: CGFloat = panelLeftEdge
        let centerY = screenFrame.midY + (screenFrame.height * 0.1)
        let topOfFirstCard = centerY - (panelHeight / 2) + panelHeight
        let y = topOfFirstCard + 12  // 12px gap above top card

        if let existing = allowAllPanel {
            if let btn = existing.contentView?.subviews.compactMap({ $0 as? NSButton }).first {
                btn.title = "Allow All (\(panels.count))"
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                existing.animator().setFrame(NSRect(x: x, y: y, width: barWidth, height: barHeight), display: true)
            }
            return
        }

        let (panel, glass) = makeGlassPanel(
            width: barWidth, height: barHeight, x: x, y: y,
            cornerRadius: 10
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

        animateLiquidCrystal(panel: panel, cornerRadius: 10)
    }

    func dismissAllowAllBar() {
        guard let panel = allowAllPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.close()
            self?.allowAllPanel = nil
        })
    }

    @objc func allowAllClicked() {
        let ids = pendingIds
        for id in ids {
            sendDecision(id: id, decision: "allow")
        }
        dismissAllPanels()
    }

    func repositionPanels() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 158
        let x: CGFloat = panelLeftEdge
        let centerY = screenFrame.midY + (screenFrame.height * 0.1)

        for (i, (_, panel)) in panels.enumerated() {
            let y = centerY - (panelHeight / 2) - (CGFloat(i) * (panelHeight + 12))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().setFrame(
                    NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
                    display: true
                )
            }
        }

        if panels.count >= 2 {
            showAllowAllBar()
        } else {
            dismissAllowAllBar()
        }
    }

    // ── Process Finished Notification ──
    // Small card shown at the top-left when a terminal process exits.
    // Persists until manually dismissed via the X button.

    func showProcessFinishedCard(tabTitle: String, cwd: String) {
        let cardWidth: CGFloat = 280
        let cardHeight: CGFloat = 60

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = panelLeftEdge
        let y = screenFrame.maxY - cardHeight - 16

        let (panel, glass) = makeGlassPanel(
            width: cardWidth, height: cardHeight, x: x, y: y,
            cornerRadius: 12, borderAlpha: 0.12
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
    }

    @objc func dismissFinishedCard(_ sender: NSButton) {
        guard let panel = sender.window as? NSPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.close()
            self?.finishedPanels.removeAll { $0 === panel }
        })
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
        CATransaction.setCompletionBlock {
            layer.filters = nil
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
}
