// CodexSettingsPage.swift — Codex agent settings page builder and handlers
//
// Contains:
//   - buildCodexPage(): agent toggle, approval policy, sandbox mode
//   - codexApprovalChanged(): approval policy popup handler
//   - codexSandboxChanged(): sandbox mode popup handler
//   - CodexConfig: reads/writes top-level keys in ~/.codex/config.toml

import Cocoa

extension TerminalWindowController {

    // MARK: - Codex Page

    func buildCodexPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
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

        addFieldLabel("APPROVAL POLICY", to: docView, x: x, y: &y, width: w)
        let currentApproval = CodexConfig.readApprovalPolicy()
        _ = addPopup(["untrusted", "on-request", "never"], selected: currentApproval,
                     to: docView, x: x, y: &y, width: w, action: #selector(codexApprovalChanged(_:)))

        addFieldLabel("SANDBOX MODE", to: docView, x: x, y: &y, width: w)
        let currentSandbox = CodexConfig.readSandboxMode()
        _ = addPopup(["workspace-read", "workspace-write", "danger-full-access"], selected: currentSandbox,
                     to: docView, x: x, y: &y, width: w, action: #selector(codexSandboxChanged(_:)))

        addDescription("Applied on next Codex launch", to: docView, x: x, y: &y, width: w)

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - Codex Action Handlers

    @objc func codexApprovalChanged(_ sender: NSPopUpButton) {
        guard let policy = sender.selectedItem?.title else { return }
        CodexConfig.writeApprovalPolicy(policy)
    }

    @objc func codexSandboxChanged(_ sender: NSPopUpButton) {
        guard let mode = sender.selectedItem?.title else { return }
        CodexConfig.writeSandboxMode(mode)
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
