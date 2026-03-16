// ClaudeSettingsPage.swift — Claude agent settings page builder and handlers
//
// Contains:
//   - buildClaudePage(): agent toggle, effort level, default mode, bridge port, notifications
//   - effortChanged(): effort level popup handler
//   - defaultModeChanged(): default mode popup handler
//   - notifToggled(): per-notification-type checkbox handler
//   - openSettingsFile(): opens ~/.claude/settings.json
//   - agentEnableToggled(): shared agent enable/disable toggle handler (Claude + Codex)

import Cocoa

extension TerminalWindowController {

    // MARK: - Claude Page

    func buildClaudePage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth
        let claudeEnabled = UserDefaults.standard.object(forKey: "agentEnabled:claude") as? Bool ?? true

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

        addFieldLabel("EFFORT LEVEL", to: docView, x: x, y: &y, width: w)
        _ = addPopup(["low", "medium", "high"], selected: "high", to: docView, x: x, y: &y, width: w,
                     action: #selector(effortChanged(_:)))

        addFieldLabel("DEFAULT MODE", to: docView, x: x, y: &y, width: w)
        _ = addPopup(["plan", "default", "acceptEdits", "bypassPermissions"], to: docView, x: x, y: &y, width: w,
                     action: #selector(defaultModeChanged(_:)))

        addFieldLabel("BRIDGE PORT", to: docView, x: x, y: &y, width: w)
        _ = addTextField("19280", to: docView, x: x, y: &y, width: w, id: nil, action: nil)
        if let lastField = docView.subviews.last as? NSTextField {
            lastField.isEditable = false
            lastField.textColor = NSColor(white: 1.0, alpha: 0.5)
        }

        _ = addButton("Open settings.json", to: docView, x: x, y: &y, width: w, action: #selector(openSettingsFile))

        y -= 12

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

    // MARK: - Claude Action Handlers

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
}
