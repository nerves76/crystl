// MCPSettingsPage.swift — MCP Servers settings page builder and handlers
//
// Contains:
//   - buildMCPPage(): server list with toggles and remove buttons, add button
//   - mcpGlobalToggled(): per-server enable/disable checkbox handler
//   - addMCPServer(): alert-based dialog for adding a new MCP server
//   - removeMCPServer(): confirmation and removal of an MCP server

import Cocoa

extension TerminalWindowController {

    // MARK: - MCP Servers Page

    func buildMCPPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
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

    // MARK: - MCP Action Handlers

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
}
