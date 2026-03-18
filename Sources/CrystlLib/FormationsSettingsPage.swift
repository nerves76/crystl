// FormationsSettingsPage.swift — Settings page for managing formations
//
// Contains:
//   - buildFormationsPage(): list of saved formations with default/rename/delete actions
//   - formationSetDefault(): toggle default formation for startup auto-load
//   - formationRename(): rename a formation via alert prompt
//   - formationDelete(): delete a formation with confirmation
//   - formationSaveCurrent(): save current open gems as a new formation

import Cocoa

extension TerminalWindowController {

    // MARK: - Formations Page

    func buildFormationsPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth
        let controlH: CGFloat = 28
        let btnSize: CGFloat = 24

        addSectionHeader("FORMATIONS", to: docView, x: x, y: &y, width: w)

        let formations = FormationManager.shared.formations

        if formations.isEmpty {
            let empty = NSTextField(labelWithString: "No saved formations")
            empty.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            empty.textColor = NSColor(white: 1.0, alpha: 0.35)
            empty.frame = NSRect(x: x, y: y, width: w, height: controlH)
            docView.addSubview(empty)
            y -= controlH + 10
        } else {
            for (i, formation) in formations.enumerated() {
                let isDefault = formation.isDefault
                let rowH: CGFloat = 40  // room for name + subtitle

                // Formation name
                let nameLabel = NSTextField(labelWithString: formation.name)
                nameLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: isDefault ? .semibold : .regular)
                nameLabel.textColor = .white
                nameLabel.frame = NSRect(x: x, y: y + 16, width: w - 150, height: 14)
                docView.addSubview(nameLabel)

                // Project count subtitle
                let countLabel = NSTextField(labelWithString: "\(formation.projects.count) gem\(formation.projects.count == 1 ? "" : "s")")
                countLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
                countLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
                countLabel.frame = NSRect(x: x, y: y, width: w - 150, height: 14)
                docView.addSubview(countLabel)

                // Buttons — right-aligned, vertically centered
                let btnY = y + (rowH - btnSize) / 2

                let starBtn = NSButton(frame: NSRect(x: x + w - 144, y: btnY, width: btnSize, height: btnSize))
                starBtn.isBordered = false
                starBtn.title = isDefault ? "★" : "☆"
                starBtn.font = NSFont.systemFont(ofSize: 14)
                starBtn.contentTintColor = isDefault
                    ? NSColor(calibratedRed: 0.55, green: 0.72, blue: 0.85, alpha: 1.0)
                    : NSColor(white: 1.0, alpha: 0.4)
                starBtn.tag = i
                starBtn.target = self
                starBtn.action = #selector(formationSetDefault(_:))
                docView.addSubview(starBtn)

                let loadBtn = NSButton(frame: NSRect(x: x + w - 114, y: btnY, width: 48, height: btnSize))
                loadBtn.title = "Load"
                loadBtn.bezelStyle = .rounded
                loadBtn.isBordered = false
                loadBtn.wantsLayer = true
                loadBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
                loadBtn.layer?.cornerRadius = 6
                loadBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
                loadBtn.contentTintColor = .white
                loadBtn.tag = i
                loadBtn.target = self
                loadBtn.action = #selector(formationLoad(_:))
                docView.addSubview(loadBtn)

                let renameBtn = NSButton(frame: NSRect(x: x + w - 60, y: btnY, width: btnSize, height: btnSize))
                renameBtn.isBordered = false
                renameBtn.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename")
                renameBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.6)
                renameBtn.tag = i
                renameBtn.target = self
                renameBtn.action = #selector(formationRename(_:))
                docView.addSubview(renameBtn)

                let deleteBtn = NSButton(frame: NSRect(x: x + w - 32, y: btnY, width: btnSize, height: btnSize))
                deleteBtn.isBordered = false
                deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
                deleteBtn.contentTintColor = NSColor.systemRed.withAlphaComponent(0.7)
                deleteBtn.tag = i
                deleteBtn.target = self
                deleteBtn.action = #selector(formationDelete(_:))
                docView.addSubview(deleteBtn)

                y -= rowH + 10  // controlToLabel spacing
            }
        }

        y -= 10  // sectionBreak before button
        _ = addButton("Save Current Gems as Formation", to: docView, x: x, y: &y, width: w,
                       action: #selector(formationSaveCurrent))

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - Formation Action Handlers

    @objc func formationSetDefault(_ sender: NSButton) {
        let formations = FormationManager.shared.formations
        guard sender.tag < formations.count else { return }
        let formation = formations[sender.tag]
        if formation.isDefault {
            FormationManager.shared.clearDefault()
        } else {
            FormationManager.shared.setDefault(id: formation.id)
        }
        rebuildSettings()
    }

    @objc func formationLoad(_ sender: NSButton) {
        let formations = FormationManager.shared.formations
        guard sender.tag < formations.count else { return }
        let formation = formations[sender.tag]
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        flipToTerminal()
        appDelegate.loadFormation(formation)
    }

    @objc func formationRename(_ sender: NSButton) {
        let formations = FormationManager.shared.formations
        guard sender.tag < formations.count else { return }
        let formation = formations[sender.tag]

        let alert = NSAlert()
        alert.messageText = "Rename Formation"
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = formation.name
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !newName.isEmpty else { return }
            FormationManager.shared.rename(id: formation.id, newName: newName)
            rebuildSettings()
        }
    }

    @objc func formationDelete(_ sender: NSButton) {
        let formations = FormationManager.shared.formations
        guard sender.tag < formations.count else { return }
        let formation = formations[sender.tag]

        let alert = NSAlert()
        alert.messageText = "Delete \"\(formation.name)\"?"
        alert.informativeText = "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            FormationManager.shared.remove(id: formation.id)
            rebuildSettings()
        }
    }

    @objc func formationSaveCurrent() {
        let alert = NSAlert()
        alert.messageText = "Save Formation"
        alert.informativeText = "Name this formation:"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "My Formation"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            let formationProjects = projects.map { project in
                FormationProject(
                    path: project.directory,
                    name: project.hasCustomTitle ? project.title : nil
                )
            }
            FormationManager.shared.add(name: name, projects: formationProjects)
            rebuildSettings()
        }
    }
}
