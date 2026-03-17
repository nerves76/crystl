// GeneralSettingsPage.swift — General settings page builder and handlers
//
// Contains:
//   - buildGeneralPage(): projects directory, git URL, toggles, demo button
//   - generalToggleChanged(): crystal rail and notifications toggle handler
//   - browseProjectsDir(): directory picker for gems directory
//   - gitBaseUrlChanged(): git remote base URL field handler
//   - runDemo(): launches the demo sequence

import Cocoa

extension TerminalWindowController {

    // MARK: - General Page

    func buildGeneralPage(width: CGFloat, minH: CGFloat = 0) -> NSView {
        let (docView, x, startY) = makeDocView(width: width)
        var y = startY
        let w = settingsColWidth

        addSectionHeader("GENERAL", to: docView, x: x, y: &y, width: w)

        // Projects Directory
        addFieldLabel("DEFAULT GEMS DIRECTORY", to: docView, x: x, y: &y, width: w)

        let projDir = UserDefaults.standard.string(forKey: "projectsDirectory") ?? ""
        let projDisplay = projDir.isEmpty ? "~/Projects" : (projDir as NSString).abbreviatingWithTildeInPath
        let projField = NSTextField(string: projDisplay)
        projField.cell = VerticallyCenteredTextFieldCell(textCell: projDisplay)
        projField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        projField.textColor = .white
        projField.isBordered = false
        projField.isBezeled = false
        projField.drawsBackground = false
        projField.isEditable = false
        projField.wantsLayer = true
        projField.layer?.backgroundColor = settingsFieldBg.cgColor
        projField.layer?.cornerRadius = 8
        projField.layer?.masksToBounds = true
        projField.frame = NSRect(x: x, y: y, width: w - 74, height: 28)
        projField.identifier = NSUserInterfaceItemIdentifier("projectsDirField")
        docView.addSubview(projField)

        let browseBtn = NSButton(frame: NSRect(x: x + w - 68, y: y, width: 68, height: 28))
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
        y -= 38

        // Git Remote Base URL
        addFieldLabel("GIT REMOTE BASE URL", to: docView, x: x, y: &y, width: w)
        let gitBaseUrl = UserDefaults.standard.string(forKey: "gitRemoteBaseUrl") ?? ""
        _ = addTextField(gitBaseUrl, placeholder: "git@github.com:user/", to: docView,
                         x: x, y: &y, width: w, id: "gitRemoteBaseUrl", action: #selector(gitBaseUrlChanged(_:)))

        y -= 12

        // ── Toggles ──
        let railOn = UserDefaults.standard.object(forKey: "crystalRailEnabled") as? Bool ?? true
        let railToggle = GlassToggle(title: "Crystal Rail", isOn: railOn,
                                      frame: NSRect(x: x, y: y, width: w, height: 22))
        railToggle.identifier = NSUserInterfaceItemIdentifier("toggle:crystalRail")
        railToggle.target = self
        railToggle.action = #selector(generalToggleChanged(_:))
        docView.addSubview(railToggle)
        y -= 32

        // Rail side picker
        addFieldLabel("RAIL POSITION", to: docView, x: x, y: &y, width: w)
        let currentSide = UserDefaults.standard.string(forKey: "crystalRailSide") ?? "left"
        let sidePopup = addPopup(["Left", "Right"], selected: currentSide == "right" ? "Right" : "Left",
                                  to: docView, x: x, y: &y, width: w,
                                  action: #selector(railSideChanged(_:)))
        sidePopup.identifier = NSUserInterfaceItemIdentifier("railSidePicker")

        let notifsOn = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        let notifToggle = GlassToggle(title: "Notifications", isOn: notifsOn,
                                       frame: NSRect(x: x, y: y, width: w, height: 22))
        notifToggle.identifier = NSUserInterfaceItemIdentifier("toggle:notifications")
        notifToggle.target = self
        notifToggle.action = #selector(generalToggleChanged(_:))
        docView.addSubview(notifToggle)
        y -= 38

        // Demo button
        _ = addButton("▶  Run Demo", to: docView, x: x, y: &y, width: w, action: #selector(runDemo))

        finalizeDocView(docView, startY: startY, currentY: y, width: width, minHeight: minH)
        return docView
    }

    // MARK: - General Action Handlers

    @objc func generalToggleChanged(_ sender: AnyObject) {
        guard let toggle = sender as? GlassToggle,
              let raw = toggle.identifier?.rawValue,
              raw.hasPrefix("toggle:") else { return }
        let key = String(raw.dropFirst(7))
        let isOn = toggle.isOn

        switch key {
        case "crystalRail":
            UserDefaults.standard.set(isOn, forKey: "crystalRailEnabled")
            if let appDelegate = NSApp.delegate as? AppDelegate {
                if isOn {
                    appDelegate.rail?.panel.orderFront(nil)
                } else {
                    appDelegate.rail?.panel.orderOut(nil)
                }
            }
        case "notifications":
            UserDefaults.standard.set(isOn, forKey: "notificationsEnabled")
            if !isOn {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.dismissAllNotificationsClicked()
                }
            }
        default:
            break
        }
    }

    @objc func railSideChanged(_ sender: NSPopUpButton) {
        let side = sender.titleOfSelectedItem == "Right" ? "right" : "left"
        UserDefaults.standard.set(side, forKey: "crystalRailSide")
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.rail?.repositionRail()
            appDelegate.layoutAllPanels()
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

    @objc func runDemo() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        flipToTerminal()
        DemoRunner.run(terminalController: self, appDelegate: appDelegate)
    }
}
