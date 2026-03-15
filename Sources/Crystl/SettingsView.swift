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

        // Spacing constants
        let sectionToHeader: CGFloat = 16
        let labelToControl: CGFloat = 16
        let controlToLabel: CGFloat = 10
        let sectionBreak: CGFloat = 20
        let labelH: CGFloat = 14
        let controlH: CGFloat = 28

        // ── Title ──
        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.alignment = .center
        title.frame = NSRect(x: 0, y: bounds.height - 80, width: bounds.width, height: 28)
        title.autoresizingMask = [.width, .minYMargin]
        view.addSubview(title)

        // ── Scrollable content area ──
        let scrollFrame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - 100)
        let settingsScroll = NSScrollView(frame: scrollFrame)
        settingsScroll.hasVerticalScroller = true
        settingsScroll.hasHorizontalScroller = false
        settingsScroll.autohidesScrollers = true
        settingsScroll.borderType = .noBorder
        settingsScroll.drawsBackground = false
        settingsScroll.autoresizingMask = [.width, .height]
        settingsScroll.scrollerStyle = .overlay

        let docHeight: CGFloat = 1500
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: docHeight))

        let leftX = (bounds.width - totalWidth) / 2
        let rightX = leftX + colWidth + gap

        let claudeEnabled = UserDefaults.standard.object(forKey: "agentEnabled:claude") as? Bool ?? true
        let codexEnabled = UserDefaults.standard.object(forKey: "agentEnabled:codex") as? Bool ?? false
        // ════════════════════════════════════════
        // LEFT COLUMN — Agent Settings
        // ════════════════════════════════════════
        var yL = docHeight - 20

        let leftHeader = NSTextField(labelWithString: "AGENT SETTINGS")
        leftHeader.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        leftHeader.textColor = .white
        leftHeader.frame = NSRect(x: leftX, y: yL, width: colWidth, height: 20)
        docView.addSubview(leftHeader)
        yL -= (20 + sectionToHeader)

        // ── Claude ──
        let claudeToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(agentEnableToggled(_:)))
        claudeToggle.state = claudeEnabled ? .on : .off
        claudeToggle.identifier = NSUserInterfaceItemIdentifier("agentEnable:claude")
        claudeToggle.frame = NSRect(x: leftX, y: yL, width: 20, height: 18)
        docView.addSubview(claudeToggle)

        let claudeSectionLabel = NSTextField(labelWithString: "Claude")
        claudeSectionLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        claudeSectionLabel.textColor = .white
        claudeSectionLabel.frame = NSRect(x: leftX + 24, y: yL, width: colWidth - 24, height: 16)
        docView.addSubview(claudeSectionLabel)
        yL -= (18 + sectionToHeader)

        // Claude settings — container for easy show/hide
        let claudeSettingsY = yL
        var claudeControls: [NSView] = []

        let effortLabel = NSTextField(labelWithString: "EFFORT LEVEL")
        effortLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        effortLabel.textColor = labelColor
        effortLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(effortLabel); claudeControls.append(effortLabel)
        yL -= (labelH + labelToControl)

        let effortPop = NSPopUpButton(frame: NSRect(x: leftX, y: yL, width: colWidth, height: 28))
        effortPop.addItems(withTitles: ["low", "medium", "high"])
        effortPop.selectItem(withTitle: "high")
        effortPop.font = NSFont.systemFont(ofSize: 12)
        effortPop.appearance = NSAppearance(named: .darkAqua)
        effortPop.target = self
        effortPop.action = #selector(effortChanged(_:))
        docView.addSubview(effortPop); claudeControls.append(effortPop)
        yL -= (controlH + controlToLabel)

        let modeLabel = NSTextField(labelWithString: "DEFAULT MODE")
        modeLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        modeLabel.textColor = labelColor
        modeLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(modeLabel); claudeControls.append(modeLabel)
        yL -= (labelH + labelToControl)

        let modePop = NSPopUpButton(frame: NSRect(x: leftX, y: yL, width: colWidth, height: 28))
        modePop.addItems(withTitles: ["plan", "default", "acceptEdits", "bypassPermissions"])
        modePop.font = NSFont.systemFont(ofSize: 12)
        modePop.appearance = NSAppearance(named: .darkAqua)
        modePop.target = self
        modePop.action = #selector(defaultModeChanged(_:))
        docView.addSubview(modePop); claudeControls.append(modePop)
        yL -= (controlH + controlToLabel)

        let portLabel = NSTextField(labelWithString: "BRIDGE PORT")
        portLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        portLabel.textColor = labelColor
        portLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(portLabel); claudeControls.append(portLabel)
        yL -= (labelH + labelToControl)

        let portField = NSTextField(string: "19280")
        portField.cell = VerticallyCenteredTextFieldCell(textCell: "19280")
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
        docView.addSubview(portField); claudeControls.append(portField)
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
        docView.addSubview(openBtn); claudeControls.append(openBtn)
        yL -= (controlH + sectionBreak)

        // Notifications (Claude bridge-specific)
        let notifLabel = NSTextField(labelWithString: "NOTIFICATIONS")
        notifLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        notifLabel.textColor = labelColor
        notifLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(notifLabel); claudeControls.append(notifLabel)
        yL -= (labelH + labelToControl)

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

            let toggle = NSButton(checkboxWithTitle: item.label, target: self,
                                   action: #selector(notifToggled(_:)))
            toggle.state = currentState ? .on : .off
            toggle.identifier = NSUserInterfaceItemIdentifier("notif:" + item.key)
            toggle.attributedTitle = NSAttributedString(string: item.label, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 11)
            ])
            toggle.frame = NSRect(x: leftX, y: yL, width: colWidth, height: 18)
            docView.addSubview(toggle); claudeControls.append(toggle)
            yL -= 22
        }
        yL -= controlToLabel

        if !claudeEnabled {
            for c in claudeControls { c.isHidden = true }
            yL = claudeSettingsY - 4  // collapse space
        }

        // ── Codex ──
        let codexToggle = NSButton(checkboxWithTitle: "", target: self, action: #selector(agentEnableToggled(_:)))
        codexToggle.state = codexEnabled ? .on : .off
        codexToggle.identifier = NSUserInterfaceItemIdentifier("agentEnable:codex")
        codexToggle.frame = NSRect(x: leftX, y: yL, width: 20, height: 18)
        docView.addSubview(codexToggle)

        let codexSectionLabel = NSTextField(labelWithString: "Codex")
        codexSectionLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        codexSectionLabel.textColor = .white
        codexSectionLabel.frame = NSRect(x: leftX + 24, y: yL, width: colWidth - 24, height: 16)
        docView.addSubview(codexSectionLabel)
        yL -= (18 + sectionToHeader)

        let codexSettingsY = yL
        var codexControls: [NSView] = []

        let approvalLabel = NSTextField(labelWithString: "APPROVAL POLICY")
        approvalLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        approvalLabel.textColor = labelColor
        approvalLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(approvalLabel); codexControls.append(approvalLabel)
        yL -= (labelH + labelToControl)

        let currentApproval = CodexConfig.readApprovalPolicy()
        let approvalPop = NSPopUpButton(frame: NSRect(x: leftX, y: yL, width: colWidth, height: 28))
        approvalPop.addItems(withTitles: ["untrusted", "on-request", "never"])
        approvalPop.selectItem(withTitle: currentApproval)
        approvalPop.font = NSFont.systemFont(ofSize: 12)
        approvalPop.appearance = NSAppearance(named: .darkAqua)
        approvalPop.target = self
        approvalPop.action = #selector(codexApprovalChanged(_:))
        docView.addSubview(approvalPop); codexControls.append(approvalPop)
        yL -= (controlH + controlToLabel)

        let sandboxLabel = NSTextField(labelWithString: "SANDBOX MODE")
        sandboxLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        sandboxLabel.textColor = labelColor
        sandboxLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(sandboxLabel); codexControls.append(sandboxLabel)
        yL -= (labelH + labelToControl)

        let currentSandbox = CodexConfig.readSandboxMode()
        let sandboxPop = NSPopUpButton(frame: NSRect(x: leftX, y: yL, width: colWidth, height: 28))
        sandboxPop.addItems(withTitles: ["workspace-read", "workspace-write", "danger-full-access"])
        sandboxPop.selectItem(withTitle: currentSandbox)
        sandboxPop.font = NSFont.systemFont(ofSize: 12)
        sandboxPop.appearance = NSAppearance(named: .darkAqua)
        sandboxPop.target = self
        sandboxPop.action = #selector(codexSandboxChanged(_:))
        docView.addSubview(sandboxPop); codexControls.append(sandboxPop)
        yL -= (controlH + controlToLabel)

        let codexDesc = NSTextField(labelWithString: "Applied on next Codex launch")
        codexDesc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        codexDesc.textColor = NSColor(white: 1.0, alpha: 0.5)
        codexDesc.frame = NSRect(x: leftX, y: yL, width: colWidth, height: 14)
        docView.addSubview(codexDesc); codexControls.append(codexDesc)
        yL -= (14 + controlToLabel)

        if !codexEnabled {
            for c in codexControls { c.isHidden = true }
            yL = codexSettingsY - 4
        }

        // ════════════════════════════════════════
        // RIGHT COLUMN — General
        // ════════════════════════════════════════
        var yR = docHeight - 20

        let rightHeader = NSTextField(labelWithString: "GENERAL")
        rightHeader.font = NSFont.systemFont(ofSize: 16, weight: .bold)
        rightHeader.textColor = .white
        rightHeader.frame = NSRect(x: rightX, y: yR, width: colWidth, height: 20)
        docView.addSubview(rightHeader)
        yR -= (20 + sectionToHeader)

        // ── Projects Directory ──
        let projLabel = NSTextField(labelWithString: "DEFAULT GEMS DIRECTORY")
        projLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        projLabel.textColor = labelColor
        projLabel.frame = NSRect(x: rightX, y: yR, width: colWidth, height: labelH)
        docView.addSubview(projLabel)
        yR -= (labelH + labelToControl)

        let projDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
        let projDisplay = projDir.isEmpty ? "~/Projects" : (projDir as NSString).abbreviatingWithTildeInPath
        let projField = NSTextField(string: projDisplay)
        projField.cell = VerticallyCenteredTextFieldCell(textCell: projDisplay)
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
        projField.frame = NSRect(x: rightX, y: yR, width: colWidth - 70, height: 28)
        projField.identifier = NSUserInterfaceItemIdentifier("projectsDirField")
        docView.addSubview(projField)

        let browseBtn = NSButton(frame: NSRect(x: rightX + colWidth - 64, y: yR, width: 64, height: 28))
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
        yR -= (controlH + controlToLabel)

        // ── Git Remote Base URL ──
        let gitLabel = NSTextField(labelWithString: "GIT REMOTE BASE URL")
        gitLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        gitLabel.textColor = labelColor
        gitLabel.frame = NSRect(x: rightX, y: yR, width: colWidth, height: labelH)
        docView.addSubview(gitLabel)
        yR -= (labelH + labelToControl)

        let gitBaseUrl = UserDefaults.standard.string(forKey: "gitRemoteBaseUrl") ?? ""
        let gitField = NSTextField(string: gitBaseUrl)
        gitField.cell = VerticallyCenteredTextFieldCell(textCell: gitBaseUrl)
        gitField.placeholderString = "git@github.com:user/"
        gitField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        gitField.textColor = .white
        gitField.backgroundColor = fieldBg
        gitField.isBordered = false
        gitField.isBezeled = false
        gitField.drawsBackground = true
        gitField.wantsLayer = true
        gitField.layer?.cornerRadius = 8
        gitField.layer?.masksToBounds = true
        gitField.frame = NSRect(x: rightX, y: yR, width: colWidth, height: 28)
        gitField.identifier = NSUserInterfaceItemIdentifier("gitRemoteBaseUrl")
        gitField.target = self
        gitField.action = #selector(gitBaseUrlChanged(_:))
        docView.addSubview(gitField)
        yR -= (controlH + sectionBreak)

        // ── MCP Servers ──
        let mcpTitle = NSTextField(labelWithString: "DEFAULT MCP SERVERS")
        mcpTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        mcpTitle.textColor = labelColor
        mcpTitle.frame = NSRect(x: rightX, y: yR, width: colWidth, height: 14)
        docView.addSubview(mcpTitle)
        yR -= (14 + 6)

        let mcpDesc = NSTextField(labelWithString: "Synced to Claude (.mcp.json) and Codex (config.toml)")
        mcpDesc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        mcpDesc.textColor = NSColor(white: 1.0, alpha: 0.5)
        mcpDesc.frame = NSRect(x: rightX, y: yR, width: colWidth, height: 14)
        docView.addSubview(mcpDesc)
        yR -= (14 + controlToLabel)

        let mcpManager = MCPConfigManager.shared
        let sortedServers = mcpManager.catalog.servers.sorted(by: { $0.key < $1.key })

        // Server list — each row is 26px, laid out top-to-bottom
        if sortedServers.isEmpty {
            yR -= 4
            let emptyLabel = NSTextField(labelWithString: "No MCP servers configured")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor(white: 1.0, alpha: 0.35)
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: rightX + 4, y: yR - 16, width: colWidth - 8, height: 16)
            docView.addSubview(emptyLabel)
            yR -= 24
        } else {
            for (i, (name, server)) in sortedServers.enumerated() {
                yR -= 26
                let rowY = yR

                let toggle = NSButton(checkboxWithTitle: "", target: self,
                                      action: #selector(mcpGlobalToggled(_:)))
                toggle.state = server.enabledByDefault ? .on : .off
                toggle.identifier = NSUserInterfaceItemIdentifier("mcpGlobal:" + name)
                toggle.frame = NSRect(x: rightX + 4, y: rowY, width: 20, height: 18)
                docView.addSubview(toggle)

                let nameLabel = NSTextField(labelWithString: name)
                nameLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                nameLabel.textColor = .white
                nameLabel.frame = NSRect(x: rightX + 30, y: rowY, width: colWidth - 56, height: 16)
                nameLabel.lineBreakMode = .byTruncatingTail
                docView.addSubview(nameLabel)

                let removeBtn = NSButton(frame: NSRect(
                    x: rightX + colWidth - 18, y: rowY + 1, width: 16, height: 16))
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
        yR -= (controlH + 14)

        let addBtn = NSButton(frame: NSRect(x: rightX, y: yR, width: colWidth, height: controlH))
        addBtn.title = "+ Add MCP Server"
        addBtn.bezelStyle = .rounded
        addBtn.isBordered = false
        addBtn.wantsLayer = true
        addBtn.layer?.backgroundColor = fieldBg.cgColor
        addBtn.layer?.cornerRadius = 8
        addBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        addBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        addBtn.target = self
        addBtn.action = #selector(addMCPServer)
        docView.addSubview(addBtn)
        yR -= (controlH + sectionBreak)

        // ── Starter Files ──
        let starterTitle = NSTextField(labelWithString: "DEFAULT STARTER FILES")
        starterTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        starterTitle.textColor = labelColor
        starterTitle.frame = NSRect(x: rightX, y: yR, width: colWidth, height: 14)
        docView.addSubview(starterTitle)
        yR -= (14 + 6)

        let starterDesc = NSTextField(labelWithString: "Templates written to new gems")
        starterDesc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        starterDesc.textColor = NSColor(white: 1.0, alpha: 0.5)
        starterDesc.frame = NSRect(x: rightX, y: yR, width: colWidth, height: 14)
        docView.addSubview(starterDesc)
        yR -= (14 + controlToLabel)

        let starterMgr = StarterManager.shared

        if starterMgr.starters.isEmpty {
            yR -= 4
            let emptyLabel = NSTextField(labelWithString: "No starter files configured")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor(white: 1.0, alpha: 0.35)
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: rightX + 4, y: yR - 16, width: colWidth - 8, height: 16)
            docView.addSubview(emptyLabel)
            yR -= 24
        } else {
            for starter in starterMgr.starters {
                yR -= 26
                let rowY = yR

                let toggle = NSButton(checkboxWithTitle: "", target: self,
                                      action: #selector(starterEnabledToggled(_:)))
                toggle.state = starter.enabledByDefault ? .on : .off
                toggle.identifier = NSUserInterfaceItemIdentifier("starterEnabled:\(starter.id.uuidString)")
                toggle.frame = NSRect(x: rightX + 4, y: rowY, width: 20, height: 18)
                docView.addSubview(toggle)

                let nameLabel = NSTextField(labelWithString: starter.filename)
                nameLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                nameLabel.textColor = .white
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.frame = NSRect(x: rightX + 30, y: rowY, width: colWidth - 82, height: 16)
                docView.addSubview(nameLabel)

                let editBtn = NSButton(frame: NSRect(
                    x: rightX + colWidth - 44, y: rowY, width: 22, height: 16))
                editBtn.title = "✎"
                editBtn.bezelStyle = .inline
                editBtn.isBordered = false
                editBtn.font = NSFont.systemFont(ofSize: 12, weight: .regular)
                editBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
                editBtn.identifier = NSUserInterfaceItemIdentifier("starterEdit:\(starter.id.uuidString)")
                editBtn.target = self
                editBtn.action = #selector(editStarter(_:))
                docView.addSubview(editBtn)

                let removeBtn = NSButton(frame: NSRect(
                    x: rightX + colWidth - 18, y: rowY + 1, width: 16, height: 16))
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
        yR -= (controlH + 14)

        let addStarterBtn = NSButton(frame: NSRect(x: rightX, y: yR, width: colWidth, height: controlH))
        addStarterBtn.title = "+ Add Starter File"
        addStarterBtn.bezelStyle = .rounded
        addStarterBtn.isBordered = false
        addStarterBtn.wantsLayer = true
        addStarterBtn.layer?.backgroundColor = fieldBg.cgColor
        addStarterBtn.layer?.cornerRadius = 8
        addStarterBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        addStarterBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        addStarterBtn.target = self
        addStarterBtn.action = #selector(addStarter)
        docView.addSubview(addStarterBtn)
        yR -= (controlH + sectionBreak)

        // ── Demo ──
        let demoBtn = NSButton(frame: NSRect(x: rightX, y: yR, width: colWidth, height: controlH))
        demoBtn.title = "▶  Run Demo"
        demoBtn.bezelStyle = .rounded
        demoBtn.isBordered = false
        demoBtn.wantsLayer = true
        demoBtn.layer?.backgroundColor = fieldBg.cgColor
        demoBtn.layer?.cornerRadius = 8
        demoBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        demoBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
        demoBtn.target = self
        demoBtn.action = #selector(runDemo)
        docView.addSubview(demoBtn)
        yR -= (controlH + sectionBreak)

        // ── Finalize scroll view ──
        let lowestY = min(yL, yR)
        let actualDocH = docHeight - lowestY + 20
        docView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: actualDocH)

        let shift = lowestY - 20
        for sub in docView.subviews {
            sub.frame.origin.y -= shift
        }

        settingsScroll.documentView = docView
        view.addSubview(settingsScroll)

        // Scroll to top
        settingsScroll.contentView.scroll(to: NSPoint(x: 0, y: actualDocH - settingsScroll.frame.height))

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

    @objc func notifToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("notif:") else { return }
        let key = String(raw.dropFirst(6))
        let isOn = sender.state == .on

        // Build partial update — only send the changed key
        let update: [String: Any] = ["enabledNotifications": [key: isOn]]
        onSettingsChanged?(update)
    }

    @objc func openSettingsFile() {
        let path = ("~/.claude/settings.json" as NSString).expandingTildeInPath
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @objc func agentEnableToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("agentEnable:") else { return }
        let agent = String(raw.dropFirst(12))
        let isOn = sender.state == .on
        UserDefaults.standard.set(isOn, forKey: "agentEnabled:\(agent)")

        // Rebuild settings to show/hide agent controls
        flipToTerminal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.flipToSettings()
        }
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

        // Rebuild settings to reflect change
        flipToTerminal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.flipToSettings()
        }
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
        alert.informativeText = "This removes the MCP server from all gems."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        MCPConfigManager.shared.removeServer(name: name)

        // Rebuild settings
        flipToTerminal()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.flipToSettings()
        }
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
    private func rebuildSettings() {
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
        // Check inside scroll views
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
            let firstDir = demoDir + "/webapp"
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
                        appDelegate.rail?.newProjectPanel.selectColor(4)  // pick a color
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
        var y0 = panelH - 48  // clear traffic light buttons

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
        y0 -= 28  // 14 label + 14 gap

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
        y0 -= 42  // 28 field + 14 gap

        // Content
        let contentLabel = NSTextField(labelWithString: "CONTENT")
        contentLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        contentLabel.textColor = labelColor
        contentLabel.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 14)
        glass.addSubview(contentLabel)
        y0 -= 20  // 14 label + 6 gap

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
            // Stop at first section header — only read top-level keys
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

        // Find and replace existing key (only in top-level, before first [section])
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
            // Insert after last top-level key (before first section or at end)
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

// ── Vertically Centered Text Field Cell ──

class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var r = super.titleRect(forBounds: rect)
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

    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int) {
        super.select(withFrame: titleRect(forBounds: rect), in: controlView,
                     editor: textObj, delegate: delegate,
                     start: selStart, length: selLength)
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
