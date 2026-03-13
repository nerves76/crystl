// DirectoryPicker.swift — Warp-style directory dropdown for new tabs
//
// A glass overlay that lists subdirectories from the projects directory.
// Appears when a new tab is opened, letting the user pick a project folder.
// Features: search filtering, keyboard navigation, escape to dismiss.

import Cocoa

class DirectoryPicker: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private var overlay: NSView?
    private var searchField: NSTextField?
    private var tableView: NSTableView?
    private var scrollView: NSScrollView?
    private var pathLabel: NSTextField?

    private var allEntries: [DirEntry] = []
    private var filtered: [DirEntry] = []
    private var currentPath: String = ""
    private var basePath: String = ""

    var onSelect: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    struct DirEntry {
        let name: String
        let path: String
        let isDirectory: Bool
        let isParent: Bool
    }

    /// Show the picker as an overlay anchored to the top-left of the parent view.
    /// Layout (top to bottom): search field, directory list, path label.
    func show(in parent: NSView, projectsDir: String) {
        dismiss()

        basePath = projectsDir
        currentPath = projectsDir

        let fm = FileManager.default
        if !fm.fileExists(atPath: projectsDir) {
            try? fm.createDirectory(atPath: projectsDir, withIntermediateDirectories: true)
        }

        loadEntries()

        let w: CGFloat = min(parent.bounds.width - 24, 460)
        let h: CGFloat = min(parent.bounds.height - 20, 360)
        let x: CGFloat = 0
        let y: CGFloat = -20

        let container = NSView(frame: NSRect(x: x, y: y, width: w, height: h))
        container.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true

        // Glass background
        let glass = NSVisualEffectView(frame: container.bounds)
        glass.material = .hudWindow
        glass.alphaValue = 0.92
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        glass.appearance = NSAppearance(named: .darkAqua)
        container.addSubview(glass)

        // Border
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor(white: 1.0, alpha: 0.3).cgColor

        // ── Search field at the top ──
        let searchY = h - 40
        let field = NSTextField(frame: NSRect(x: 12, y: searchY, width: w - 24, height: 32))
        field.placeholderAttributedString = NSAttributedString(
            string: "Search directories...",
            attributes: [
                .foregroundColor: NSColor(white: 1.0, alpha: 0.45),
                .font: NSFont.systemFont(ofSize: 14, weight: .regular)
            ]
        )
        field.font = NSFont.systemFont(ofSize: 14, weight: .regular)
        field.textColor = .white
        field.backgroundColor = NSColor(white: 1.0, alpha: 0.08)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = true
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 12
        field.layer?.masksToBounds = true
        field.delegate = self
        field.target = self
        field.action = #selector(searchSubmitted(_:))
        container.addSubview(field)
        searchField = field

        // ── Path label at the bottom ──
        let pathLbl = NSTextField(labelWithString: "")
        pathLbl.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        pathLbl.textColor = NSColor(white: 1.0, alpha: 0.5)
        pathLbl.wantsLayer = true
        pathLbl.layer?.cornerRadius = 6
        pathLbl.layer?.borderWidth = 0.5
        pathLbl.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        pathLbl.frame = NSRect(x: 12, y: 10, width: w - 24, height: 22)
        pathLbl.lineBreakMode = .byTruncatingMiddle
        container.addSubview(pathLbl)
        pathLabel = pathLbl
        updatePathLabel()

        // ── Table view — between search and path label ──
        let tableBottom: CGFloat = 40
        let tableTop = searchY - 6
        let tableH = tableTop - tableBottom
        let sv = NSScrollView(frame: NSRect(x: 0, y: tableBottom, width: w, height: tableH))
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.borderType = .noBorder
        sv.drawsBackground = false

        let tv = NSTableView()
        tv.headerView = nil
        tv.backgroundColor = .clear
        tv.gridStyleMask = []
        tv.selectionHighlightStyle = .regular
        tv.rowHeight = 36
        tv.intercellSpacing = NSSize(width: 0, height: 2)
        tv.dataSource = self
        tv.delegate = self
        tv.appearance = NSAppearance(named: .darkAqua)
        tv.doubleAction = #selector(rowDoubleClicked)
        tv.target = self

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        col.width = w
        tv.addTableColumn(col)

        sv.documentView = tv
        container.addSubview(sv)
        scrollView = sv
        tableView = tv

        parent.addSubview(container, positioned: .above, relativeTo: nil)
        overlay = container

        // Animate in — slide up from bottom
        container.alphaValue = 0
        let startFrame = NSRect(x: x, y: y - 20, width: w, height: h)
        let endFrame = NSRect(x: x, y: y, width: w, height: h)
        container.frame = startFrame
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
            container.animator().alphaValue = 1.0
            container.animator().frame = endFrame
        }

        // Focus the search field
        parent.window?.makeFirstResponder(field)

        tv.reloadData()
        if !filtered.isEmpty {
            tv.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func dismiss() {
        guard let ov = overlay else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ov.animator().alphaValue = 0
        }, completionHandler: {
            ov.removeFromSuperview()
        })
        overlay = nil
        searchField = nil
        tableView = nil
        scrollView = nil
        pathLabel = nil
    }

    var isVisible: Bool { overlay != nil }

    // MARK: - Data

    private func loadEntries() {
        let fm = FileManager.default
        var entries: [DirEntry] = []

        // Parent directory — only if we've navigated deeper than base
        if currentPath != basePath {
            let parent = (currentPath as NSString).deletingLastPathComponent
            entries.append(DirEntry(name: ".. (Parent Directory)", path: parent, isDirectory: true, isParent: true))
        }

        if let items = try? fm.contentsOfDirectory(atPath: currentPath) {
            let sorted = items.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            for item in sorted {
                guard !item.hasPrefix(".") else { continue }
                let fullPath = currentPath + "/" + item
                var isDir: ObjCBool = false
                fm.fileExists(atPath: fullPath, isDirectory: &isDir)
                entries.append(DirEntry(name: item, path: fullPath, isDirectory: isDir.boolValue, isParent: false))
            }
        }

        allEntries = entries
        applyFilter()
    }

    private func applyFilter() {
        let query = searchField?.stringValue.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        if query.isEmpty {
            filtered = allEntries
        } else {
            filtered = allEntries.filter { $0.isParent || $0.name.lowercased().contains(query) }
        }
        tableView?.reloadData()
        if !filtered.isEmpty {
            tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    private func updatePathLabel() {
        let display = (currentPath as NSString).abbreviatingWithTildeInPath
        pathLabel?.stringValue = display
    }

    private func navigateTo(_ path: String) {
        currentPath = path
        searchField?.stringValue = ""
        loadEntries()
        updatePathLabel()
    }

    private func selectCurrentRow() {
        guard let tv = tableView else { return }
        let row = tv.selectedRow
        guard row >= 0 && row < filtered.count else { return }
        let entry = filtered[row]

        if entry.isDirectory {
            // Navigate into this directory
            navigateTo(entry.path)
        } else {
            // Select the parent directory (the current path) since user clicked a file
            // This is a no-op for files — they're informational
        }
    }

    private func confirmSelection() {
        guard let tv = tableView else { return }
        let row = tv.selectedRow
        guard row >= 0 && row < filtered.count else {
            // If nothing selected, use currentPath
            onSelect?(currentPath)
            dismiss()
            return
        }

        let entry = filtered[row]
        if entry.isDirectory && !entry.isParent {
            onSelect?(entry.path)
            dismiss()
        } else if entry.isDirectory && entry.isParent {
            navigateTo(entry.path)
        }
    }

    // MARK: - Actions

    @objc func searchSubmitted(_ sender: NSTextField) {
        confirmSelection()
    }

    @objc func rowDoubleClicked() {
        guard let tv = tableView else { return }
        let row = tv.clickedRow
        guard row >= 0 && row < filtered.count else { return }
        let entry = filtered[row]

        if entry.isDirectory {
            if entry.isParent {
                navigateTo(entry.path)
            } else {
                onSelect?(entry.path)
                dismiss()
            }
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            // Arrow down — move selection in table
            guard let tv = tableView else { return false }
            let next = min(tv.selectedRow + 1, filtered.count - 1)
            tv.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
            tv.scrollRowToVisible(next)
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            guard let tv = tableView else { return false }
            let prev = max(tv.selectedRow - 1, 0)
            tv.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
            tv.scrollRowToVisible(prev)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Escape
            dismiss()
            onDismiss?()
            return true
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            // Tab — navigate into selected directory
            selectCurrentRow()
            return true
        }
        return false
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return filtered.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < filtered.count else { return nil }
        let entry = filtered[row]

        let rowH: CGFloat = 36
        let cell = NSView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: rowH))

        // Icon — Lucide icons for folders, arrow for parent, file icon for files
        let iconSize: CGFloat = 18
        let iconY = (rowH - iconSize) / 2
        if entry.isParent {
            let iconLabel = NSTextField(labelWithString: "\u{2191}")
            iconLabel.font = NSFont.systemFont(ofSize: 15)
            iconLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            iconLabel.frame = NSRect(x: 16, y: iconY, width: 24, height: iconSize)
            cell.addSubview(iconLabel)
        } else if let img = LucideIcons.render(
            name: entry.isDirectory ? "folder" : "file",
            size: iconSize,
            color: entry.isDirectory ? NSColor(white: 1.0, alpha: 0.7) : NSColor(white: 1.0, alpha: 0.4)
        ) {
            let iconView = NSImageView(frame: NSRect(x: 16, y: iconY, width: iconSize, height: iconSize))
            iconView.image = img
            cell.addSubview(iconView)
        }

        // Name
        let nameLabel = NSTextField(labelWithString: entry.name)
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: entry.isDirectory ? .medium : .regular)
        nameLabel.textColor = entry.isDirectory ? .white : NSColor(white: 1.0, alpha: 0.5)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 48, y: (rowH - 20) / 2, width: tableView.bounds.width - 64, height: 20)
        cell.addSubview(nameLabel)

        return cell
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        // Could show preview or update path label
    }
}
