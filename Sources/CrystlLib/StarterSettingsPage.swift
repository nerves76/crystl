// StarterSettingsPage.swift — Starter Files settings page builder, handlers, and editor panel
//
// Contains:
//   - buildStartersPage(): starter file list with toggles, edit/remove buttons
//   - editStarter(): opens the StarterEditorPanel for a starter file
//   - addStarter(): creates a new starter and opens the editor
//   - deleteStarter(): removes a starter file
//   - starterEnabledToggled(): per-starter enable/disable checkbox handler
//   - StarterEditorPanel: floating glass panel for editing starter filename and content

import Cocoa

extension TerminalWindowController {

    // MARK: - Starter Files Page

    func buildStartersPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let starterMgr = StarterManager.shared
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("DEFAULT STARTER FILES", to: docView, x: x, y: &y, width: w)
        addDescription("Templates written to new gems", to: docView, x: x, y: &y, width: w)

        if starterMgr.starters.isEmpty {
            y -= 4
            let emptyLabel = NSTextField(labelWithString: "No starter files configured")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = NSColor(white: 1.0, alpha: 0.35)
            emptyLabel.alignment = .center
            emptyLabel.frame = NSRect(x: x + 4, y: y - 16, width: w - 8, height: 16)
            docView.addSubview(emptyLabel)
            y -= 24
        } else {
            for starter in starterMgr.starters {
                y -= 26
                let rowY = y

                let toggle = NSButton(checkboxWithTitle: "", target: self,
                                      action: #selector(starterEnabledToggled(_:)))
                toggle.state = starter.enabledByDefault ? .on : .off
                toggle.identifier = NSUserInterfaceItemIdentifier("starterEnabled:\(starter.id.uuidString)")
                toggle.frame = NSRect(x: x + 4, y: rowY, width: 20, height: 18)
                docView.addSubview(toggle)

                let nameLabel = NSTextField(labelWithString: starter.filename)
                nameLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                nameLabel.textColor = .white
                nameLabel.lineBreakMode = .byTruncatingTail
                nameLabel.frame = NSRect(x: x + 30, y: rowY, width: w - 82, height: 16)
                docView.addSubview(nameLabel)

                let editBtn = NSButton(frame: NSRect(x: x + w - 44, y: rowY, width: 22, height: 16))
                editBtn.title = "✎"
                editBtn.bezelStyle = .inline
                editBtn.isBordered = false
                editBtn.font = NSFont.systemFont(ofSize: 12, weight: .regular)
                editBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
                editBtn.identifier = NSUserInterfaceItemIdentifier("starterEdit:\(starter.id.uuidString)")
                editBtn.target = self
                editBtn.action = #selector(editStarter(_:))
                docView.addSubview(editBtn)

                let removeBtn = NSButton(frame: NSRect(x: x + w - 18, y: rowY + 1, width: 16, height: 16))
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
        y -= 42

        _ = addButton("+ Add Starter File", to: docView, x: x, y: &y, width: w,
                      action: #selector(addStarter))

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - Starter File Action Handlers

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
            backing: .buffered, defer: false
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
        var y0 = panelH - 48

        let title = NSTextField(labelWithString: "Edit Starter File")
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 18)
        glass.addSubview(title)
        y0 -= 34

        let fnLabel = NSTextField(labelWithString: "FILENAME")
        fnLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        fnLabel.textColor = labelColor
        fnLabel.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 14)
        glass.addSubview(fnLabel)
        y0 -= 28

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
        y0 -= 42

        let contentLabel = NSTextField(labelWithString: "CONTENT")
        contentLabel.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        contentLabel.textColor = labelColor
        contentLabel.frame = NSRect(x: pad, y: y0, width: panelW - pad * 2, height: 14)
        glass.addSubview(contentLabel)
        y0 -= 20

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
