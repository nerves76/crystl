// SettingsView.swift — Settings panel with flip animation
//
// Extracted from TerminalWindowController. Builds the settings view and
// manages the flip transition between terminal and settings.

import Cocoa

extension TerminalWindowController {

    func flipToSettings() {
        guard let container = window.contentView else { return }
        isShowingSettings = true

        let settings = buildSettingsView()
        settings.frame = container.bounds
        settingsView = settings

        let terminalViews = container.subviews.map { $0 }

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
        for sub in container.subviews {
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

        let labelColor = NSColor(white: 1.0, alpha: 0.7)
        let fieldBg = NSColor(white: 1.0, alpha: 0.12)
        let colWidth: CGFloat = 300
        let gap: CGFloat = 60
        let totalWidth = colWidth * 2 + gap
        let leftX = (bounds.width - totalWidth) / 2
        let rightX = leftX + colWidth + gap
        let mask: NSView.AutoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]

        // Spacing constants — consistent vertical rhythm
        // Note: gap must be >= controlH - labelH to prevent overlap
        // (controls extend upward from their y origin in non-flipped NSView)
        let sectionToHeader: CGFloat = 16  // section header to first field label
        let labelToControl: CGFloat = 16   // label to its control (14+16=30 step, 30-28=2px gap)
        let controlToLabel: CGFloat = 10   // control to next field label
        let sectionBreak: CGFloat = 20     // control to next section header
        let labelH: CGFloat = 14           // label text height
        let controlH: CGFloat = 28         // standard control height

        // ── Title ──
        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.alignment = .center
        title.frame = NSRect(x: 0, y: bounds.height - 80, width: bounds.width, height: 28)
        title.autoresizingMask = [.width, .minYMargin]
        view.addSubview(title)

        // ════════════════════════════════════════
        // LEFT COLUMN — General
        // ════════════════════════════════════════
        var yL = bounds.height - 120

        let genLabel = NSTextField(labelWithString: "GENERAL")
        genLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        genLabel.textColor = labelColor
        genLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: 14)
        genLabel.autoresizingMask = mask
        view.addSubview(genLabel)
        yL -= (14 + sectionToHeader)

        // ── Projects Directory ──
        let projLabel = NSTextField(labelWithString: "DEFAULT PROJECTS DIRECTORY")
        projLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        projLabel.textColor = labelColor
        projLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        projLabel.autoresizingMask = mask
        view.addSubview(projLabel)
        yL -= (labelH + labelToControl)

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
        projField.layer?.cornerRadius = 8
        projField.layer?.masksToBounds = true
        projField.frame = NSRect(x: leftX, y: yL, width: colWidth - 70, height: 28)
        projField.identifier = NSUserInterfaceItemIdentifier("projectsDirField")
        projField.autoresizingMask = mask
        view.addSubview(projField)

        let browseBtn = NSButton(frame: NSRect(x: leftX + colWidth - 64, y: yL, width: 64, height: 28))
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
        browseBtn.autoresizingMask = mask
        view.addSubview(browseBtn)
        yL -= (controlH + sectionBreak)

        // ── Claude ──
        let claudeLabel = NSTextField(labelWithString: "CLAUDE")
        claudeLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        claudeLabel.textColor = labelColor
        claudeLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: 14)
        claudeLabel.autoresizingMask = mask
        view.addSubview(claudeLabel)
        yL -= (14 + sectionToHeader)

        let effortLabel = NSTextField(labelWithString: "EFFORT LEVEL")
        effortLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        effortLabel.textColor = labelColor
        effortLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        effortLabel.autoresizingMask = mask
        view.addSubview(effortLabel)
        yL -= (labelH + labelToControl)

        let effortPop = NSPopUpButton(frame: NSRect(x: leftX, y: yL, width: colWidth, height: 28))
        effortPop.addItems(withTitles: ["low", "medium", "high"])
        effortPop.selectItem(withTitle: "high")
        effortPop.font = NSFont.systemFont(ofSize: 12)
        effortPop.appearance = NSAppearance(named: .darkAqua)
        effortPop.target = self
        effortPop.action = #selector(effortChanged(_:))
        effortPop.autoresizingMask = mask
        view.addSubview(effortPop)
        yL -= (controlH + controlToLabel)

        let modeLabel = NSTextField(labelWithString: "DEFAULT MODE")
        modeLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        modeLabel.textColor = labelColor
        modeLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        modeLabel.autoresizingMask = mask
        view.addSubview(modeLabel)
        yL -= (labelH + labelToControl)

        let modePop = NSPopUpButton(frame: NSRect(x: leftX, y: yL, width: colWidth, height: 28))
        modePop.addItems(withTitles: ["plan", "default", "acceptEdits", "bypassPermissions"])
        modePop.font = NSFont.systemFont(ofSize: 12)
        modePop.appearance = NSAppearance(named: .darkAqua)
        modePop.target = self
        modePop.action = #selector(defaultModeChanged(_:))
        modePop.autoresizingMask = mask
        view.addSubview(modePop)
        yL -= (controlH + sectionBreak)

        let portLabel = NSTextField(labelWithString: "BRIDGE PORT")
        portLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        portLabel.textColor = labelColor
        portLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        portLabel.autoresizingMask = mask
        view.addSubview(portLabel)
        yL -= (labelH + labelToControl)

        let portField = NSTextField(string: "19280")
        portField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        portField.textColor = NSColor(white: 1.0, alpha: 0.5)
        portField.backgroundColor = fieldBg
        portField.isBordered = false
        portField.isBezeled = false
        portField.drawsBackground = true
        portField.isEditable = false
        portField.wantsLayer = true
        portField.layer?.cornerRadius = 8
        portField.layer?.masksToBounds = true
        portField.frame = NSRect(x: leftX, y: yL, width: colWidth, height: 28)
        portField.autoresizingMask = mask
        view.addSubview(portField)
        yL -= (controlH + controlToLabel)

        let openBtn = NSButton(frame: NSRect(x: leftX, y: yL, width: colWidth, height: 28))
        openBtn.title = "Open settings.json"
        openBtn.bezelStyle = .rounded
        openBtn.isBordered = false
        openBtn.wantsLayer = true
        openBtn.layer?.backgroundColor = fieldBg.cgColor
        openBtn.layer?.cornerRadius = 8
        openBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        openBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        openBtn.target = self
        openBtn.action = #selector(openSettingsFile)
        openBtn.autoresizingMask = mask
        view.addSubview(openBtn)
        // hasClaude check removed — always show Claude section since it's labeled

        // ════════════════════════════════════════
        // RIGHT COLUMN — MCP Servers
        // ════════════════════════════════════════
        var yR = bounds.height - 120

        let mcpTitle = NSTextField(labelWithString: "MCP SERVERS")
        mcpTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        mcpTitle.textColor = labelColor
        mcpTitle.frame = NSRect(x: rightX, y: yR, width: colWidth, height: 14)
        mcpTitle.autoresizingMask = mask
        view.addSubview(mcpTitle)
        yR -= (14 + sectionToHeader)

        let mcpManager = MCPConfigManager.shared
        let projectDir = selectedProject?.directory
        let projectName = projectDir.map { ($0 as NSString).lastPathComponent } ?? "none"
        let sortedServers = mcpManager.catalog.servers.sorted(by: { $0.key < $1.key })

        // Column sub-headers
        let globalHdr = NSTextField(labelWithString: "Global")
        globalHdr.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        globalHdr.textColor = NSColor(white: 1.0, alpha: 0.4)
        globalHdr.frame = NSRect(x: rightX, y: yR, width: 42, height: 12)
        globalHdr.autoresizingMask = mask
        view.addSubview(globalHdr)

        let serverHdr = NSTextField(labelWithString: "Server")
        serverHdr.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        serverHdr.textColor = NSColor(white: 1.0, alpha: 0.4)
        serverHdr.frame = NSRect(x: rightX + 46, y: yR, width: 100, height: 12)
        serverHdr.autoresizingMask = mask
        view.addSubview(serverHdr)

        let projHdr = NSTextField(labelWithString: projectName)
        projHdr.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        projHdr.textColor = NSColor(white: 1.0, alpha: 0.4)
        projHdr.frame = NSRect(x: rightX + colWidth - 80, y: yR, width: 60, height: 12)
        projHdr.autoresizingMask = mask
        view.addSubview(projHdr)
        yR -= 20

        if sortedServers.isEmpty {
            yR -= 16
            let emptyLabel = NSTextField(labelWithString: "No MCP servers configured")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor(white: 1.0, alpha: 0.35)
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: rightX + 4, y: yR, width: colWidth - 8, height: 16)
            emptyLabel.autoresizingMask = mask
            view.addSubview(emptyLabel)
            yR -= (16 + sectionBreak)
        } else {
            for (name, server) in sortedServers {
                // Global default toggle
                let globalToggle = NSButton(checkboxWithTitle: "", target: self,
                                            action: #selector(mcpGlobalToggled(_:)))
                globalToggle.state = server.enabledByDefault ? .on : .off
                globalToggle.identifier = NSUserInterfaceItemIdentifier("mcpGlobal:" + name)
                globalToggle.frame = NSRect(x: rightX + 4, y: yR, width: 20, height: 18)
                globalToggle.autoresizingMask = mask
                view.addSubview(globalToggle)

                // Server name
                let nameLabel = NSTextField(labelWithString: name)
                nameLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                nameLabel.textColor = .white
                nameLabel.frame = NSRect(x: rightX + 46, y: yR, width: colWidth - 130, height: 16)
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.autoresizingMask = mask
                view.addSubview(nameLabel)

                // Per-project toggle
                if projectDir != nil {
                    let isActive = mcpManager.isActive(project: projectDir!, server: name)
                    let projToggle = NSButton(checkboxWithTitle: "", target: self,
                                              action: #selector(mcpToggled(_:)))
                    projToggle.state = isActive ? .on : .off
                    projToggle.identifier = NSUserInterfaceItemIdentifier("mcp:" + name)
                    projToggle.frame = NSRect(x: rightX + colWidth - 72, y: yR, width: 20, height: 18)
                    projToggle.autoresizingMask = mask
                    view.addSubview(projToggle)
                }

                // Remove button
                let removeBtn = NSButton(frame: NSRect(
                    x: rightX + colWidth - 18, y: yR + 1, width: 16, height: 16))
                removeBtn.title = "×"
                removeBtn.bezelStyle = .inline
                removeBtn.isBordered = false
                removeBtn.font = NSFont.systemFont(ofSize: 14, weight: .light)
                removeBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.3)
                removeBtn.identifier = NSUserInterfaceItemIdentifier("mcpRemove:" + name)
                removeBtn.target = self
                removeBtn.action = #selector(removeMCPServer(_:))
                removeBtn.autoresizingMask = mask
                view.addSubview(removeBtn)

                yR -= 26
            }
            yR -= sectionBreak
        }

        // Add / Edit buttons
        yR -= controlH
        let mcpBtnW: CGFloat = (colWidth - 8) / 2
        let addBtn = NSButton(frame: NSRect(x: rightX, y: yR, width: mcpBtnW, height: 28))
        addBtn.title = "+ Add MCP"
        addBtn.bezelStyle = .rounded
        addBtn.isBordered = false
        addBtn.wantsLayer = true
        addBtn.layer?.backgroundColor = fieldBg.cgColor
        addBtn.layer?.cornerRadius = 8
        addBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        addBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        addBtn.target = self
        addBtn.action = #selector(addMCPServer)
        addBtn.autoresizingMask = mask
        view.addSubview(addBtn)

        let editCfgBtn = NSButton(frame: NSRect(x: rightX + mcpBtnW + 8, y: yR,
                                                 width: mcpBtnW, height: 28))
        editCfgBtn.title = "Edit mcp.json"
        editCfgBtn.bezelStyle = .rounded
        editCfgBtn.isBordered = false
        editCfgBtn.wantsLayer = true
        editCfgBtn.layer?.backgroundColor = fieldBg.cgColor
        editCfgBtn.layer?.cornerRadius = 8
        editCfgBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        editCfgBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        editCfgBtn.target = self
        editCfgBtn.action = #selector(editMCPConfig)
        editCfgBtn.autoresizingMask = mask
        view.addSubview(editCfgBtn)

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

    @objc func mcpGlobalToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("mcpGlobal:") else { return }
        let name = String(raw.dropFirst(10))
        let mgr = MCPConfigManager.shared
        guard var server = mgr.catalog.servers[name] else { return }
        server.enabledByDefault = sender.state == .on
        mgr.updateServer(name: name, server: server)

        // Re-sync current project and rebuild to update project column
        if let dir = selectedProject?.directory {
            mgr.syncToProject(dir)
        }
        flipToTerminal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.flipToSettings()
        }
    }

    @objc func mcpToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("mcp:"),
              let dir = selectedProject?.directory else { return }
        let name = String(raw.dropFirst(4))
        let mgr = MCPConfigManager.shared
        let isDefault = mgr.catalog.servers[name]?.enabledByDefault ?? false
        let newState = sender.state == .on

        if newState == isDefault {
            mgr.clearProjectOverride(project: dir, server: name)
        } else {
            mgr.setProjectOverride(project: dir, server: name, enabled: newState)
        }
        mgr.syncToProject(dir)
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

        // Rebuild settings to show new entry
        flipToTerminal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.flipToSettings()
        }
    }

    @objc func removeMCPServer(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("mcpRemove:") else { return }
        let name = String(raw.dropFirst(10))

        let alert = NSAlert()
        alert.messageText = "Remove \(name)?"
        alert.informativeText = "This removes the MCP server from all projects."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        MCPConfigManager.shared.removeServer(name: name)

        // Re-sync any active project
        if let dir = selectedProject?.directory {
            MCPConfigManager.shared.syncToProject(dir)
        }

        // Rebuild settings
        flipToTerminal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.flipToSettings()
        }
    }

    @objc func editMCPConfig() {
        guard let dir = selectedProject?.directory else { return }
        let path = dir + "/.mcp.json"
        // Ensure file exists by syncing first
        MCPConfigManager.shared.syncToProject(dir)
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
