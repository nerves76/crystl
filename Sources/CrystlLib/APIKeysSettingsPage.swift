// APIKeysSettingsPage.swift — API Keys settings page builder and handlers
//
// Contains:
//   - buildAPIKeysPage(): Guild membership callout, per-key secure fields
//   - apiKeyChanged(): saves API key to keychain and masks display
//   - maskKey(): masks an API key for display (first 6 + last 4 chars)

import Cocoa

extension TerminalWindowController {

    // MARK: - API Keys Page

    func buildAPIKeysPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let isPro = LicenseManager.shared.tier == .pro
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("API KEYS", to: docView, x: x, y: &y, width: w)

        if !isPro {
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

    // MARK: - API Keys Action Handlers

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

    /// Masks an API key for display: shows first 6 and last 4 chars.
    func maskKey(_ key: String) -> String {
        guard key.count > 12 else { return String(repeating: "\u{2022}", count: key.count) }
        let prefix = String(key.prefix(6))
        let suffix = String(key.suffix(4))
        return prefix + String(repeating: "\u{2022}", count: 6) + suffix
    }
}
