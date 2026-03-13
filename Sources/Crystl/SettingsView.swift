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

        // Save instruction file templates if edited
        if let textView = findView(in: settings, id: "claudeMdTemplate") as? NSTextView {
            DefaultClaudeMd.save(textView.string)
        }
        if let textView = findView(in: settings, id: "agentsMdTemplate") as? NSTextView {
            DefaultAgentsMd.save(textView.string)
        }

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

        let docHeight: CGFloat = 1100
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: bounds.width, height: docHeight))

        let leftX = (bounds.width - totalWidth) / 2
        let rightX = leftX + colWidth + gap

        let claudeEnabled = UserDefaults.standard.object(forKey: "agentEnabled:claude") as? Bool ?? true
        let codexEnabled = UserDefaults.standard.object(forKey: "agentEnabled:codex") as? Bool ?? false
        let textEditorH: CGFloat = 100

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

        // Default CLAUDE.md
        let claudeMdLabel = NSTextField(labelWithString: "DEFAULT CLAUDE.md")
        claudeMdLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        claudeMdLabel.textColor = labelColor
        claudeMdLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(claudeMdLabel); claudeControls.append(claudeMdLabel)
        yL -= (labelH + labelToControl)

        let claudeMdScroll = NSScrollView(frame: NSRect(x: leftX, y: yL - textEditorH + controlH, width: colWidth, height: textEditorH))
        claudeMdScroll.hasVerticalScroller = true
        claudeMdScroll.hasHorizontalScroller = false
        claudeMdScroll.autohidesScrollers = true
        claudeMdScroll.borderType = .noBorder
        claudeMdScroll.drawsBackground = true
        claudeMdScroll.backgroundColor = fieldBg
        claudeMdScroll.wantsLayer = true
        claudeMdScroll.layer?.cornerRadius = 8
        claudeMdScroll.layer?.masksToBounds = true

        let claudeTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: colWidth - 16, height: textEditorH))
        claudeTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        claudeTextView.textColor = .white
        claudeTextView.backgroundColor = .clear
        claudeTextView.isEditable = true
        claudeTextView.isSelectable = true
        claudeTextView.isRichText = false
        claudeTextView.allowsUndo = true
        claudeTextView.textContainerInset = NSSize(width: 6, height: 6)
        claudeTextView.isAutomaticQuoteSubstitutionEnabled = false
        claudeTextView.isAutomaticDashSubstitutionEnabled = false
        claudeTextView.isAutomaticTextReplacementEnabled = false
        claudeTextView.insertionPointColor = .white
        claudeTextView.isVerticallyResizable = true
        claudeTextView.isHorizontallyResizable = false
        claudeTextView.textContainer?.widthTracksTextView = true
        claudeTextView.identifier = NSUserInterfaceItemIdentifier("claudeMdTemplate")
        claudeTextView.string = DefaultClaudeMd.load()
        claudeMdScroll.documentView = claudeTextView
        docView.addSubview(claudeMdScroll); claudeControls.append(claudeMdScroll)
        yL -= (textEditorH + sectionBreak)

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

        // Default AGENTS.md
        let agentsMdLabel = NSTextField(labelWithString: "DEFAULT AGENTS.md")
        agentsMdLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        agentsMdLabel.textColor = labelColor
        agentsMdLabel.frame = NSRect(x: leftX, y: yL, width: colWidth, height: labelH)
        docView.addSubview(agentsMdLabel); codexControls.append(agentsMdLabel)
        yL -= (labelH + labelToControl)

        let agentsMdScroll = NSScrollView(frame: NSRect(x: leftX, y: yL - textEditorH + controlH, width: colWidth, height: textEditorH))
        agentsMdScroll.hasVerticalScroller = true
        agentsMdScroll.hasHorizontalScroller = false
        agentsMdScroll.autohidesScrollers = true
        agentsMdScroll.borderType = .noBorder
        agentsMdScroll.drawsBackground = true
        agentsMdScroll.backgroundColor = fieldBg
        agentsMdScroll.wantsLayer = true
        agentsMdScroll.layer?.cornerRadius = 8
        agentsMdScroll.layer?.masksToBounds = true

        let agentsTextView = NSTextView(frame: NSRect(x: 0, y: 0, width: colWidth - 16, height: textEditorH))
        agentsTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        agentsTextView.textColor = .white
        agentsTextView.backgroundColor = .clear
        agentsTextView.isEditable = true
        agentsTextView.isSelectable = true
        agentsTextView.isRichText = false
        agentsTextView.allowsUndo = true
        agentsTextView.textContainerInset = NSSize(width: 6, height: 6)
        agentsTextView.isAutomaticQuoteSubstitutionEnabled = false
        agentsTextView.isAutomaticDashSubstitutionEnabled = false
        agentsTextView.isAutomaticTextReplacementEnabled = false
        agentsTextView.insertionPointColor = .white
        agentsTextView.isVerticallyResizable = true
        agentsTextView.isHorizontallyResizable = false
        agentsTextView.textContainer?.widthTracksTextView = true
        agentsTextView.identifier = NSUserInterfaceItemIdentifier("agentsMdTemplate")
        agentsTextView.string = DefaultAgentsMd.load()
        agentsMdScroll.documentView = agentsTextView
        docView.addSubview(agentsMdScroll); codexControls.append(agentsMdScroll)
        yL -= (textEditorH + sectionBreak)

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
        let projLabel = NSTextField(labelWithString: "DEFAULT PROJECTS DIRECTORY")
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
        alert.informativeText = "This removes the MCP server from all projects."
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
        panel.message = "Select your projects directory"

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
}

// ── Default CLAUDE.md Template ──

/// Manages the default CLAUDE.md content written to new projects.
/// Stored at ~/.config/crystl/default-claude.md.
class DefaultClaudeMd {
    private static let configDir = NSHomeDirectory() + "/.config/crystl"
    private static let path = NSHomeDirectory() + "/.config/crystl/default-claude.md"

    static func load() -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func save(_ content: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Writes the template to {project}/CLAUDE.md if it doesn't already exist.
    /// Does nothing if the template is empty or the file already exists.
    static func syncToProject(_ project: String) {
        let claudeMdPath = project + "/CLAUDE.md"
        let fm = FileManager.default
        guard !fm.fileExists(atPath: claudeMdPath) else { return }

        let content = load()
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? content.write(toFile: claudeMdPath, atomically: true, encoding: .utf8)
    }
}

// ── Default AGENTS.md Template ──

/// Manages the default AGENTS.md content written to new projects (for Codex CLI).
/// Stored at ~/.config/crystl/default-agents.md.
class DefaultAgentsMd {
    private static let configDir = NSHomeDirectory() + "/.config/crystl"
    private static let path = NSHomeDirectory() + "/.config/crystl/default-agents.md"

    static func load() -> String {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }
        return text
    }

    static func save(_ content: String) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        try? content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Writes the template to {project}/AGENTS.md if it doesn't already exist.
    /// Does nothing if the template is empty or the file already exists.
    static func syncToProject(_ project: String) {
        let agentsMdPath = project + "/AGENTS.md"
        let fm = FileManager.default
        guard !fm.fileExists(atPath: agentsMdPath) else { return }

        let content = load()
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try? content.write(toFile: agentsMdPath, atomically: true, encoding: .utf8)
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
