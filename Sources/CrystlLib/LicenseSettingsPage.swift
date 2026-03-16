// LicenseSettingsPage.swift — License settings page builder and handlers
//
// Contains:
//   - buildLicensePage(): license status display, activation/deactivation
//   - addLicenseKeyInput(): shared license key input field and activate button
//   - activateLicense(): activates a license key from the input field
//   - deactivateLicense(): deactivates the current license

import Cocoa

extension TerminalWindowController {

    // MARK: - License Page

    func buildLicensePage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("LICENSE", to: docView, x: x, y: &y, width: w)

        let lm = LicenseManager.shared
        switch lm.currentState {
        case .valid(let payload):
            let statusLabel = NSTextField(labelWithString: "GUILD MEMBER")
            statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            statusLabel.textColor = NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0)
            statusLabel.frame = NSRect(x: x, y: y, width: w, height: 16)
            docView.addSubview(statusLabel)
            y -= 22

            let emailLabel = NSTextField(labelWithString: payload.email)
            emailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emailLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            emailLabel.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(emailLabel)
            y -= 18

            let expiryText = payload.isLifetime ? "Lifetime license" : "Expires: \(payload.expires)"
            let expiryLabel = NSTextField(labelWithString: expiryText)
            expiryLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            expiryLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            expiryLabel.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(expiryLabel)
            y -= 30

            _ = addButton("Deactivate License", to: docView, x: x, y: &y, width: w,
                          tintColor: NSColor(red: 1.0, green: 0.5, blue: 0.5, alpha: 0.8),
                          bgColor: NSColor(red: 0.5, green: 0.15, blue: 0.15, alpha: 0.4),
                          action: #selector(deactivateLicense))

        case .expired(let payload):
            let statusLabel = NSTextField(labelWithString: "EXPIRED")
            statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            statusLabel.textColor = NSColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1.0)
            statusLabel.frame = NSRect(x: x, y: y, width: w, height: 16)
            docView.addSubview(statusLabel)
            y -= 22

            let infoLabel = NSTextField(labelWithString: "\(payload.email) — expired \(payload.expires)")
            infoLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            infoLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            infoLabel.frame = NSRect(x: x, y: y, width: w, height: 14)
            docView.addSubview(infoLabel)
            y -= 30

            addLicenseKeyInput(to: docView, x: x, y: &y, w: w)

        case .unlicensed:
            addLicenseKeyInput(to: docView, x: x, y: &y, w: w)
        }

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    func addLicenseKeyInput(to docView: NSView, x: CGFloat, y: inout CGFloat, w: CGFloat) {
        let keyField = NSTextField(string: "")
        keyField.cell = VerticallyCenteredTextFieldCell(textCell: "")
        keyField.placeholderString = "Paste license key"
        keyField.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        keyField.textColor = .white
        keyField.isEditable = true
        keyField.isSelectable = true
        keyField.isBordered = false
        keyField.isBezeled = false
        keyField.drawsBackground = false
        keyField.wantsLayer = true
        keyField.layer?.backgroundColor = settingsFieldBg.cgColor
        keyField.layer?.cornerRadius = 8
        keyField.layer?.masksToBounds = true
        keyField.frame = NSRect(x: x, y: y, width: w, height: 28)
        keyField.identifier = NSUserInterfaceItemIdentifier("licenseKey")
        docView.addSubview(keyField)
        y -= 36

        _ = addButton("Activate", to: docView, x: x, y: &y, width: w,
                      tintColor: NSColor(red: 0.5, green: 1.0, blue: 0.7, alpha: 0.9),
                      bgColor: NSColor(red: 0.2, green: 0.5, blue: 0.35, alpha: 0.5),
                      action: #selector(activateLicense))
    }

    // MARK: - License Action Handlers

    @objc func activateLicense(_ sender: NSButton) {
        guard let scrollView = settingsView?.subviews.compactMap({ $0 as? NSScrollView }).first,
              let docView = scrollView.documentView else { return }
        guard let keyField = docView.subviews.compactMap({ $0 as? NSTextField })
                .first(where: { $0.identifier?.rawValue == "licenseKey" }) else { return }
        let keyString = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyString.isEmpty else { return }

        let result = LicenseManager.shared.activate(keyString)
        switch result {
        case .success:
            rebuildSettings()
        case .failure(let error):
            keyField.stringValue = ""
            keyField.placeholderString = error.localizedDescription
        }
    }

    @objc func deactivateLicense(_ sender: NSButton) {
        LicenseManager.shared.deactivate()
        rebuildSettings()
    }
}
