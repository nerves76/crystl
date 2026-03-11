import Cocoa

// ── Data Models ──

struct PendingRequest: Codable, Equatable {
    let id: String
    let tool_name: String
    let tool_input: [String: AnyCodable]?
    let cwd: String?
    let session_id: String?
    let created: Double

    static func == (lhs: PendingRequest, rhs: PendingRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct PollResponse: Codable {
    let pending: [PendingRequest]
}

struct DecisionBody: Codable {
    let id: String
    let decision: String
}

// Wrapper to handle mixed JSON values
struct AnyCodable: Codable, Equatable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s }
        else if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self) { value = d }
        else if let b = try? c.decode(Bool.self) { value = b }
        else if let dict = try? c.decode([String: AnyCodable].self) { value = dict }
        else if let arr = try? c.decode([AnyCodable].self) { value = arr }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let s = value as? String { try c.encode(s) }
        else if let i = value as? Int { try c.encode(i) }
        else if let d = value as? Double { try c.encode(d) }
        else if let b = value as? Bool { try c.encode(b) }
        else { try c.encode(String(describing: value)) }
    }

    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        String(describing: lhs.value) == String(describing: rhs.value)
    }
}

// ── App Delegate ──

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var pollTimer: Timer?
    var panels: [String: NSPanel] = [:]
    var knownIds: Set<String> = []
    let bridgePort = 19280
    var isConnected = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: 30)
        if let button = statusItem.button {
            // Draw a simple icon as an image
            let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                NSColor.controlTextColor.setStroke()
                let path = NSBezierPath()
                path.lineWidth = 2.0
                path.lineCapStyle = .round
                // Checkmark
                path.move(to: NSPoint(x: 3, y: 9))
                path.line(to: NSPoint(x: 7, y: 4))
                path.line(to: NSPoint(x: 15, y: 14))
                path.stroke()
                return true
            }
            img.isTemplate = true
            button.image = img
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Apprvr — Claude Code Approvals", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let statusMenuItem = NSMenuItem(title: "Checking bridge...", action: nil, keyEquivalent: "")
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // Start polling
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    func updateStatusMenu(connected: Bool, pendingCount: Int) {
        guard let menu = statusItem.menu,
              let item = menu.item(withTag: 100) else { return }
        if connected {
            item.title = pendingCount > 0
                ? "\(pendingCount) pending approval\(pendingCount == 1 ? "" : "s")"
                : "Connected — no pending requests"
        } else {
            item.title = "Bridge not running (port \(bridgePort))"
        }

        // Update icon badge
        if let button = statusItem.button {
            if pendingCount > 0 {
                let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                    NSColor.systemGreen.setStroke()
                    let path = NSBezierPath()
                    path.lineWidth = 2.0
                    path.lineCapStyle = .round
                    path.move(to: NSPoint(x: 3, y: 9))
                    path.line(to: NSPoint(x: 7, y: 4))
                    path.line(to: NSPoint(x: 15, y: 14))
                    path.stroke()
                    return true
                }
                button.image = img
            } else {
                let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                    NSColor.controlTextColor.setStroke()
                    let path = NSBezierPath()
                    path.lineWidth = 2.0
                    path.lineCapStyle = .round
                    path.move(to: NSPoint(x: 3, y: 9))
                    path.line(to: NSPoint(x: 7, y: 4))
                    path.line(to: NSPoint(x: 15, y: 14))
                    path.stroke()
                    return true
                }
                img.isTemplate = true
                button.image = img
            }
        }
    }

    // ── Polling ──

    func poll() {
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/pending") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 3

        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let data = data,
                   let resp = try? JSONDecoder().decode(PollResponse.self, from: data) {
                    self.isConnected = true
                    self.updateStatusMenu(connected: true, pendingCount: resp.pending.count)
                    self.handlePending(resp.pending)
                } else {
                    self.isConnected = false
                    self.updateStatusMenu(connected: false, pendingCount: 0)
                    // Dismiss any panels if bridge goes down
                    self.dismissAllPanels()
                }
            }
        }.resume()
    }

    func handlePending(_ pending: [PendingRequest]) {
        let currentIds = Set(pending.map { $0.id })

        // Dismiss panels for resolved requests
        for id in knownIds.subtracting(currentIds) {
            dismissPanel(id: id)
        }

        // Show panels for new requests
        for req in pending where !knownIds.contains(req.id) {
            showApprovalPanel(req)
        }

        knownIds = currentIds
    }

    // ── Approval Panel ──

    func showApprovalPanel(_ request: PendingRequest) {
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 158

        // Position: vertically centered on left edge
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let existingCount = CGFloat(panels.count)
        let x: CGFloat = 16
        let centerY = screenFrame.midY + (screenFrame.height * 0.1)
        let y = centerY - (panelHeight / 2) - (existingCount * (panelHeight + 12))

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        // Glass background using NSVisualEffectView
        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 14
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        // Green accent line at top
        let accent = NSView(frame: NSRect(x: 0, y: panelHeight - 2.5, width: panelWidth, height: 2.5))
        accent.wantsLayer = true
        accent.layer?.backgroundColor = NSColor.systemGreen.cgColor
        glass.addSubview(accent)

        // Project directory (from cwd)
        let projectName = extractProjectName(request.cwd)
        if !projectName.isEmpty {
            let dirLabel = NSTextField(labelWithString: projectName)
            dirLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            dirLabel.textColor = NSColor.systemGreen.withAlphaComponent(0.8)
            dirLabel.frame = NSRect(x: 16, y: panelHeight - 22, width: panelWidth - 80, height: 14)
            glass.addSubview(dirLabel)
        }

        // Tool name
        let toolLabel = NSTextField(labelWithString: request.tool_name)
        toolLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        toolLabel.textColor = .white
        let toolY = projectName.isEmpty ? panelHeight - 32 : panelHeight - 40
        toolLabel.frame = NSRect(x: 16, y: toolY, width: panelWidth - 80, height: 20)
        glass.addSubview(toolLabel)

        // "apprvr" tag
        let tagLabel = NSTextField(labelWithString: "apprvr")
        tagLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        tagLabel.textColor = NSColor(white: 1.0, alpha: 0.25)
        tagLabel.alignment = .right
        tagLabel.frame = NSRect(x: panelWidth - 60, y: panelHeight - 22, width: 44, height: 12)
        glass.addSubview(tagLabel)

        // Detail text (command, file path, etc.)
        let detail = formatToolInput(request.tool_input)
        if !detail.isEmpty {
            let detailLabel = NSTextField(wrappingLabelWithString: detail)
            detailLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            detailLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
            detailLabel.maximumNumberOfLines = 2
            detailLabel.lineBreakMode = .byTruncatingTail
            detailLabel.frame = NSRect(x: 16, y: 48, width: panelWidth - 32, height: 36)
            glass.addSubview(detailLabel)
        }

        // Buttons
        let btnWidth = (panelWidth - 44) / 2
        let btnHeight: CGFloat = 30

        let denyBtn = NSButton(frame: NSRect(x: 14, y: 10, width: btnWidth, height: btnHeight))
        denyBtn.title = "Deny"
        denyBtn.bezelStyle = .rounded
        denyBtn.isBordered = false
        denyBtn.wantsLayer = true
        denyBtn.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.07).cgColor
        denyBtn.layer?.cornerRadius = 8
        denyBtn.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        denyBtn.contentTintColor = NSColor(white: 1.0, alpha: 0.5)
        denyBtn.target = self
        denyBtn.action = #selector(denyClicked(_:))
        denyBtn.identifier = NSUserInterfaceItemIdentifier(request.id)
        glass.addSubview(denyBtn)

        let allowBtn = NSButton(frame: NSRect(x: panelWidth / 2 + 2, y: 10, width: btnWidth, height: btnHeight))
        allowBtn.title = "Allow"
        allowBtn.bezelStyle = .rounded
        allowBtn.isBordered = false
        allowBtn.wantsLayer = true
        allowBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.85).cgColor
        allowBtn.layer?.cornerRadius = 8
        allowBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        allowBtn.contentTintColor = .white
        allowBtn.target = self
        allowBtn.action = #selector(allowClicked(_:))
        allowBtn.identifier = NSUserInterfaceItemIdentifier(request.id)
        allowBtn.keyEquivalent = "\r"
        glass.addSubview(allowBtn)

        panel.contentView = glass
        panel.orderFrontRegardless()

        panels[request.id] = panel

        // Slide in from left
        let startFrame = NSRect(x: x - 40, y: y, width: panelWidth, height: panelHeight)
        let endFrame = NSRect(x: x, y: y, width: panelWidth, height: panelHeight)
        panel.setFrame(startFrame, display: false)
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(endFrame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func extractProjectName(_ cwd: String?) -> String {
        guard let cwd = cwd, !cwd.isEmpty else { return "" }
        // Show last 2 path components for context, e.g. "Nextcloud/gyaslack"
        let parts = cwd.split(separator: "/")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "/")
        }
        return String(parts.last ?? "")
    }

    @objc func allowClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        sendDecision(id: id, decision: "allow")
        dismissPanel(id: id)
    }

    @objc func denyClicked(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        sendDecision(id: id, decision: "deny")
        dismissPanel(id: id)
    }

    func dismissPanel(id: String) {
        guard let panel = panels[id] else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
            self.panels.removeValue(forKey: id)
            self.knownIds.remove(id)
            self.repositionPanels()
        })
    }

    func dismissAllPanels() {
        for id in Array(panels.keys) {
            dismissPanel(id: id)
        }
    }

    func repositionPanels() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 320
        let panelHeight: CGFloat = 140
        let x: CGFloat = 16
        let centerY = screenFrame.midY + (screenFrame.height * 0.1)

        for (i, (_, panel)) in panels.enumerated() {
            let y = centerY - (panelHeight / 2) - (CGFloat(i) * (panelHeight + 12))
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                panel.animator().setFrame(
                    NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
                    display: true
                )
            }
        }
    }

    // ── Bridge Communication ──

    func sendDecision(id: String, decision: String) {
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/decide") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONEncoder().encode(DecisionBody(id: id, decision: decision))
        URLSession.shared.dataTask(with: req).resume()
    }

    func formatToolInput(_ input: [String: AnyCodable]?) -> String {
        guard let input = input else { return "" }
        if let cmd = input["command"]?.value as? String { return cmd }
        if let path = input["file_path"]?.value as? String { return path }
        if let pattern = input["pattern"]?.value as? String { return pattern }
        if let query = input["query"]?.value as? String { return query }
        if let prompt = input["prompt"]?.value as? String { return prompt }
        if let data = try? JSONSerialization.data(withJSONObject: input.mapValues { $0.value }, options: []),
           let str = String(data: data, encoding: .utf8) {
            return str.count > 120 ? String(str.prefix(120)) + "..." : str
        }
        return ""
    }
}

// ── Main ──

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // Menu bar only, no dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
