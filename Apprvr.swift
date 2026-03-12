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

struct BridgeSettings: Codable {
    var autoApproveMode: String
    var paused: Bool?
    var sessionOverrides: [String: String]?
}

struct SessionInfo: Codable {
    let session_id: String
    let cwd: String?
    let permission_mode: String?
    let lastSeen: Double
    let requestCount: Int
    let override: String?
}

struct HistoryEntry: Codable {
    let id: String
    let tool_name: String
    let cwd: String?
    let session_id: String?
    let decision: String
    let timestamp: Double
}

struct PollResponse: Codable {
    let pending: [PendingRequest]
    let sessions: [SessionInfo]?
    let history: [HistoryEntry]?
    let settings: BridgeSettings?
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

// ── Helpers ──

let sessionColors: [NSColor] = [
    NSColor.systemGreen,
    NSColor.systemBlue,
    NSColor.systemPurple,
    NSColor.systemOrange,
    NSColor.systemPink,
    NSColor.systemTeal,
    NSColor.systemYellow,
    NSColor.systemIndigo
]

// Stable mapping from session_id to color index (persists across polls)
var sessionColorMap: [String: Int] = [:]
var nextColorIndex = 0

func colorForSession(_ sessionId: String?) -> NSColor {
    guard let sid = sessionId, !sid.isEmpty else { return NSColor.systemGreen }
    if let idx = sessionColorMap[sid] {
        return sessionColors[idx % sessionColors.count]
    }
    let idx = nextColorIndex
    sessionColorMap[sid] = idx
    nextColorIndex += 1
    return sessionColors[idx % sessionColors.count]
}

class GlowView: NSView {
    var color: NSColor = .systemGreen

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let colors = [
            color.withAlphaComponent(0.5).cgColor,
            color.withAlphaComponent(0.15).cgColor,
            color.withAlphaComponent(0.0).cgColor
        ] as CFArray
        let locations: [CGFloat] = [0.0, 0.35, 1.0]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locations) else { return }
        ctx.drawLinearGradient(gradient, start: CGPoint(x: bounds.midX, y: bounds.maxY), end: CGPoint(x: bounds.midX, y: bounds.minY), options: [])
    }
}

func roundedMaskImage(size: NSSize, radius: CGFloat) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.black.setFill()
        path.fill()
        return true
    }
}

// ── App Delegate ──

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var pollTimer: Timer?
    var panels: [String: NSPanel] = [:]
    var allowAllPanel: NSPanel?
    var knownIds: Set<String> = []
    var pendingIds: [String] = [] // ordered list for Allow All
    let bridgePort = 19280
    var isConnected = false
    var currentMode: String = "manual"
    var modeMenuItems: [String: NSMenuItem] = [:]
    var settingsPill: NSPanel?
    var settingsModeLabel: NSTextField?
    var settingsDot: NSView?
    var pauseIcon: NSTextField?
    var sessionCountLabel: NSTextField?
    var dashboardPanel: NSPanel?
    var currentSessions: [SessionInfo] = []
    var currentHistory: [HistoryEntry] = []
    var isPaused: Bool = false

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

        // Mode header
        let modeHeader = NSMenuItem(title: "Approval Mode", action: nil, keyEquivalent: "")
        modeHeader.isEnabled = false
        menu.addItem(modeHeader)

        let manualItem = NSMenuItem(title: "  Manual — Ask for each request", action: #selector(setManualMode), keyEquivalent: "")
        manualItem.state = .on
        modeMenuItems["manual"] = manualItem
        menu.addItem(manualItem)

        let smartItem = NSMenuItem(title: "  Smart — Auto-approve safe tools", action: #selector(setSmartMode), keyEquivalent: "")
        modeMenuItems["smart"] = smartItem
        menu.addItem(smartItem)

        let allItem = NSMenuItem(title: "  Auto-approve All ⚠️", action: #selector(setAllMode), keyEquivalent: "")
        modeMenuItems["all"] = allItem
        menu.addItem(allItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        // Start polling
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()

        // Show floating settings pill
        showSettingsPill()
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    // ── Mode Switching ──

    @objc func setManualMode() { updateMode("manual") }
    @objc func setSmartMode() { updateMode("smart") }

    @objc func setAllMode() {
        let alert = NSAlert()
        alert.messageText = "Enable Auto-approve All?"
        alert.informativeText = "This will automatically approve ALL tool requests without prompting, including file writes, bash commands, and other potentially dangerous operations.\n\nOnly use this if you fully trust the current Claude Code sessions."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            updateMode("all")
        }
    }

    func updateMode(_ mode: String) {
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{\"autoApproveMode\":\"\(mode)\"}".data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            DispatchQueue.main.async {
                if error == nil {
                    self?.applyModeUI(mode)
                }
            }
        }.resume()
    }

    func applyModeUI(_ mode: String) {
        currentMode = mode
        for (key, item) in modeMenuItems {
            item.state = key == mode ? .on : .off
        }
        updateSettingsPill(mode)
    }

    // ── Settings Pill ──

    func modeDisplayName(_ mode: String) -> String {
        switch mode {
        case "smart": return "Smart"
        case "all": return "Auto-All"
        default: return "Manual"
        }
    }

    func modeColor(_ mode: String) -> NSColor {
        switch mode {
        case "smart": return NSColor.systemBlue
        case "all": return NSColor.systemOrange
        default: return NSColor.systemGreen
        }
    }

    func showSettingsPill() {
        let pillWidth: CGFloat = 180
        let pillHeight: CGFloat = 28

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = 16
        let y: CGFloat = screenFrame.origin.y + 16

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: pillWidth, height: pillHeight),
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

        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: pillWidth, height: pillHeight))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = roundedMaskImage(size: NSSize(width: pillWidth, height: pillHeight), radius: pillHeight / 2)
        glass.wantsLayer = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        // Colored dot indicator
        let dot = NSView(frame: NSRect(x: 10, y: (pillHeight - 8) / 2, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = modeColor(currentMode).cgColor
        glass.addSubview(dot)
        settingsDot = dot

        // Mode label (clickable to cycle)
        let label = NSTextField(labelWithString: modeDisplayName(currentMode))
        label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(white: 1.0, alpha: 0.7)
        label.frame = NSRect(x: 24, y: (pillHeight - 14) / 2, width: 60, height: 14)
        glass.addSubview(label)
        settingsModeLabel = label

        let modeBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 88, height: pillHeight))
        modeBtn.title = ""
        modeBtn.bezelStyle = .rounded
        modeBtn.isBordered = false
        modeBtn.isTransparent = true
        modeBtn.target = self
        modeBtn.action = #selector(settingsPillClicked)
        glass.addSubview(modeBtn)

        // Divider
        let divider = NSView(frame: NSRect(x: 88, y: 6, width: 1, height: pillHeight - 12))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        glass.addSubview(divider)

        // Session count
        let sessLabel = NSTextField(labelWithString: "0")
        sessLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        sessLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
        sessLabel.frame = NSRect(x: 96, y: (pillHeight - 14) / 2, width: 36, height: 14)
        glass.addSubview(sessLabel)
        sessionCountLabel = sessLabel

        let dashBtn = NSButton(frame: NSRect(x: 88, y: 0, width: 48, height: pillHeight))
        dashBtn.title = ""
        dashBtn.bezelStyle = .rounded
        dashBtn.isBordered = false
        dashBtn.isTransparent = true
        dashBtn.target = self
        dashBtn.action = #selector(dashboardClicked)
        glass.addSubview(dashBtn)

        // Divider 2
        let divider2 = NSView(frame: NSRect(x: 140, y: 6, width: 1, height: pillHeight - 12))
        divider2.wantsLayer = true
        divider2.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        glass.addSubview(divider2)

        // Pause button
        let pauseLabel = NSTextField(labelWithString: "||")
        pauseLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        pauseLabel.textColor = NSColor(white: 1.0, alpha: 0.5)
        pauseLabel.alignment = .center
        pauseLabel.frame = NSRect(x: 148, y: (pillHeight - 14) / 2, width: 24, height: 14)
        glass.addSubview(pauseLabel)
        pauseIcon = pauseLabel

        let pauseBtn = NSButton(frame: NSRect(x: 140, y: 0, width: 40, height: pillHeight))
        pauseBtn.title = ""
        pauseBtn.bezelStyle = .rounded
        pauseBtn.isBordered = false
        pauseBtn.isTransparent = true
        pauseBtn.target = self
        pauseBtn.action = #selector(pauseClicked)
        glass.addSubview(pauseBtn)

        panel.contentView = glass
        panel.orderFrontRegardless()
        settingsPill = panel

        // Fade in
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            panel.animator().alphaValue = 1
        }
    }

    func updateSettingsPill(_ mode: String) {
        settingsModeLabel?.stringValue = modeDisplayName(mode)
        settingsDot?.layer?.backgroundColor = modeColor(mode).cgColor
    }

    func updateSessionCount() {
        let count = currentSessions.count
        sessionCountLabel?.stringValue = count == 1 ? "1 ses" : "\(count) ses"
    }

    func updatePauseState() {
        if isPaused {
            pauseIcon?.stringValue = ">"
            pauseIcon?.textColor = NSColor.systemOrange
            settingsPill?.contentView?.layer?.borderColor = NSColor.systemOrange.withAlphaComponent(0.4).cgColor
        } else {
            pauseIcon?.stringValue = "||"
            pauseIcon?.textColor = NSColor(white: 1.0, alpha: 0.5)
            settingsPill?.contentView?.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        }
    }

    @objc func settingsPillClicked() {
        switch currentMode {
        case "manual":
            updateMode("smart")
        case "smart":
            setAllMode()
        case "all":
            updateMode("manual")
        default:
            updateMode("manual")
        }
    }

    @objc func pauseClicked() {
        let newPaused = !isPaused
        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = "{\"paused\":\(newPaused)}".data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                self?.isPaused = newPaused
                self?.updatePauseState()
            }
        }.resume()
    }

    @objc func dashboardClicked() {
        if dashboardPanel != nil {
            dismissDashboard()
        } else {
            showDashboard()
        }
    }

    // ── Dashboard Panel ──

    func showDashboard() {
        let dashWidth: CGFloat = 340
        let dashHeight: CGFloat = 380

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = 16
        let y: CGFloat = screenFrame.origin.y + 52

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: dashWidth, height: dashHeight),
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

        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: dashWidth, height: dashHeight))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = roundedMaskImage(size: NSSize(width: dashWidth, height: dashHeight), radius: 14)
        glass.wantsLayer = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        var yOffset = dashHeight - 14

        // ── Sessions Section ──
        let sessHeader = NSTextField(labelWithString: "SESSIONS")
        sessHeader.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        sessHeader.textColor = NSColor(white: 1.0, alpha: 0.35)
        yOffset -= 14
        sessHeader.frame = NSRect(x: 16, y: yOffset, width: dashWidth - 32, height: 14)
        glass.addSubview(sessHeader)

        if currentSessions.isEmpty {
            yOffset -= 20
            let noSess = NSTextField(labelWithString: "No active sessions")
            noSess.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            noSess.textColor = NSColor(white: 1.0, alpha: 0.3)
            noSess.frame = NSRect(x: 16, y: yOffset, width: dashWidth - 32, height: 16)
            glass.addSubview(noSess)
        } else {
            for session in currentSessions {
                yOffset -= 36
                let projectName = extractProjectName(session.cwd)
                let sidShort = String(session.session_id.prefix(6))
                let sessColor = colorForSession(session.session_id)

                // Color dot
                let dot = NSView(frame: NSRect(x: 16, y: yOffset + 18, width: 8, height: 8))
                dot.wantsLayer = true
                dot.layer?.cornerRadius = 4
                dot.layer?.backgroundColor = sessColor.cgColor
                glass.addSubview(dot)

                // Project name
                let projLabel = NSTextField(labelWithString: projectName.isEmpty ? sidShort : projectName)
                projLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
                projLabel.textColor = .white
                projLabel.frame = NSRect(x: 30, y: yOffset + 14, width: 146, height: 16)
                glass.addSubview(projLabel)

                // Permission mode + request count
                let modeStr = session.override ?? session.permission_mode ?? "?"
                let infoLabel = NSTextField(labelWithString: "\(modeStr) · \(session.requestCount) req")
                infoLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
                infoLabel.textColor = NSColor(white: 1.0, alpha: 0.4)
                infoLabel.frame = NSRect(x: 30, y: yOffset, width: 146, height: 14)
                glass.addSubview(infoLabel)

                // Per-session mode cycle button
                let overrideMode = session.override ?? "default"
                let btnLabel: String
                let btnColor: NSColor
                switch overrideMode {
                case "manual": btnLabel = "Manual"; btnColor = NSColor.systemGreen
                case "smart": btnLabel = "Smart"; btnColor = NSColor.systemBlue
                case "all": btnLabel = "Auto"; btnColor = NSColor.systemOrange
                default: btnLabel = "Global"; btnColor = NSColor(white: 1.0, alpha: 0.3)
                }

                let overrideBtn = NSButton(frame: NSRect(x: dashWidth - 80, y: yOffset + 4, width: 60, height: 22))
                overrideBtn.title = btnLabel
                overrideBtn.bezelStyle = .rounded
                overrideBtn.isBordered = false
                overrideBtn.wantsLayer = true
                overrideBtn.layer?.backgroundColor = btnColor.withAlphaComponent(0.2).cgColor
                overrideBtn.layer?.cornerRadius = 6
                overrideBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
                overrideBtn.contentTintColor = btnColor
                overrideBtn.target = self
                overrideBtn.action = #selector(sessionOverrideClicked(_:))
                overrideBtn.identifier = NSUserInterfaceItemIdentifier(session.session_id)
                glass.addSubview(overrideBtn)

                // Separator
                yOffset -= 2
                let sep = NSView(frame: NSRect(x: 16, y: yOffset, width: dashWidth - 32, height: 1))
                sep.wantsLayer = true
                sep.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.06).cgColor
                glass.addSubview(sep)
            }
        }

        // ── Activity Feed Section ──
        yOffset -= 22
        let actHeader = NSTextField(labelWithString: "RECENT ACTIVITY")
        actHeader.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        actHeader.textColor = NSColor(white: 1.0, alpha: 0.35)
        actHeader.frame = NSRect(x: 16, y: yOffset, width: dashWidth - 32, height: 14)
        glass.addSubview(actHeader)

        let maxHistory = min(currentHistory.count, 8)
        for i in 0..<maxHistory {
            let entry = currentHistory[i]
            yOffset -= 20

            // Decision indicator
            let indicator: String
            let indicatorColor: NSColor
            switch entry.decision {
            case "allow": indicator = "✓"; indicatorColor = NSColor.systemGreen
            case "deny": indicator = "✗"; indicatorColor = NSColor.systemRed
            case "auto-approved": indicator = "⚡"; indicatorColor = NSColor.systemBlue
            case "expired": indicator = "○"; indicatorColor = NSColor(white: 1.0, alpha: 0.3)
            default: indicator = "?"; indicatorColor = NSColor(white: 1.0, alpha: 0.3)
            }

            let indLabel = NSTextField(labelWithString: indicator)
            indLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            indLabel.textColor = indicatorColor
            indLabel.frame = NSRect(x: 16, y: yOffset, width: 16, height: 16)
            glass.addSubview(indLabel)

            // Session color bar
            let entryColor = colorForSession(entry.session_id)
            let colorBar = NSView(frame: NSRect(x: 34, y: yOffset + 1, width: 2, height: 12))
            colorBar.wantsLayer = true
            colorBar.layer?.cornerRadius = 1
            colorBar.layer?.backgroundColor = entryColor.withAlphaComponent(0.6).cgColor
            glass.addSubview(colorBar)

            let toolLabel = NSTextField(labelWithString: entry.tool_name)
            toolLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            toolLabel.textColor = NSColor(white: 1.0, alpha: 0.6)
            toolLabel.frame = NSRect(x: 42, y: yOffset, width: 130, height: 16)
            glass.addSubview(toolLabel)

            let timeAgo = formatTimeAgo(entry.timestamp)
            let timeLabel = NSTextField(labelWithString: timeAgo)
            timeLabel.font = NSFont.systemFont(ofSize: 9, weight: .regular)
            timeLabel.textColor = NSColor(white: 1.0, alpha: 0.2)
            timeLabel.alignment = .right
            timeLabel.frame = NSRect(x: 180, y: yOffset, width: 50, height: 16)
            glass.addSubview(timeLabel)
        }

        if currentHistory.isEmpty {
            yOffset -= 18
            let noHist = NSTextField(labelWithString: "No activity yet")
            noHist.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            noHist.textColor = NSColor(white: 1.0, alpha: 0.3)
            noHist.frame = NSRect(x: 16, y: yOffset, width: dashWidth - 32, height: 16)
            glass.addSubview(noHist)
        }

        panel.contentView = glass
        panel.orderFrontRegardless()
        dashboardPanel = panel

        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func dismissDashboard() {
        guard let panel = dashboardPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
            self.dashboardPanel = nil
        })
    }

    @objc func sessionOverrideClicked(_ sender: NSButton) {
        guard let sid = sender.identifier?.rawValue else { return }
        let session = currentSessions.first { $0.session_id == sid }
        let currentOverride = session?.override

        // Cycle: global -> manual -> smart -> all -> global
        let nextMode: String?
        switch currentOverride {
        case nil: nextMode = "manual"
        case "manual": nextMode = "smart"
        case "smart": nextMode = "all"
        case "all": nextMode = nil
        default: nextMode = nil
        }

        guard let url = URL(string: "http://127.0.0.1:\(bridgePort)/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let modeVal = nextMode.map { "\"\($0)\"" } ?? "null"
        req.httpBody = "{\"sessionOverride\":{\"session_id\":\"\(sid)\",\"mode\":\(modeVal)}}".data(using: .utf8)
        URLSession.shared.dataTask(with: req) { [weak self] _, _, _ in
            DispatchQueue.main.async {
                // Refresh dashboard
                self?.dismissDashboard()
                self?.showDashboard()
            }
        }.resume()
    }

    func formatTimeAgo(_ timestamp: Double) -> String {
        let seconds = Int((Date().timeIntervalSince1970 * 1000 - timestamp) / 1000)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
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
                    if let s = resp.sessions { self.currentSessions = s }
                    if let h = resp.history { self.currentHistory = h }
                    if let s = resp.settings {
                        self.applyModeUI(s.autoApproveMode)
                        self.isPaused = s.paused ?? false
                        self.updatePauseState()
                    }
                    self.updateSessionCount()
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
        pendingIds = pending.map { $0.id }

        // Show or hide Allow All bar
        if panels.count >= 2 {
            showAllowAllBar()
        } else {
            dismissAllowAllBar()
        }
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
        glass.maskImage = roundedMaskImage(size: NSSize(width: panelWidth, height: panelHeight), radius: 14)
        glass.wantsLayer = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor

        // Session-colored glow at top
        let sessColor = colorForSession(request.session_id)
        let glow = GlowView(frame: NSRect(x: 0, y: panelHeight - 50, width: panelWidth, height: 50))
        glow.color = sessColor
        glass.addSubview(glow)

        // Project directory (from cwd)
        let projectName = extractProjectName(request.cwd)
        if !projectName.isEmpty {
            let dirLabel = NSTextField(labelWithString: projectName)
            dirLabel.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            dirLabel.textColor = sessColor.withAlphaComponent(0.8)
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
        dismissAllowAllBar()
    }

    // ── Allow All Bar ──

    func showAllowAllBar() {
        let barWidth: CGFloat = 340
        let barHeight: CGFloat = 38

        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x: CGFloat = 16
        let centerY = screenFrame.midY + (screenFrame.height * 0.1)
        let y = centerY - (-barHeight / 2) + 24 // above the top panel

        if let existing = allowAllPanel {
            // Update count text
            if let btn = existing.contentView?.subviews.compactMap({ $0 as? NSButton }).first {
                btn.title = "Allow All (\(panels.count))"
            }
            // Reposition
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                existing.animator().setFrame(NSRect(x: x, y: y, width: barWidth, height: barHeight), display: true)
            }
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: barWidth, height: barHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.maskImage = roundedMaskImage(size: NSSize(width: barWidth, height: barHeight), radius: 10)
        glass.wantsLayer = true
        glass.layer?.borderWidth = 0.5
        glass.layer?.borderColor = NSColor.systemGreen.withAlphaComponent(0.3).cgColor

        let allowAllBtn = NSButton(frame: NSRect(x: 0, y: 0, width: barWidth, height: barHeight))
        allowAllBtn.title = "Allow All (\(panels.count))"
        allowAllBtn.bezelStyle = .rounded
        allowAllBtn.isBordered = false
        allowAllBtn.wantsLayer = true
        allowAllBtn.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.2).cgColor
        allowAllBtn.layer?.cornerRadius = 10
        allowAllBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        allowAllBtn.contentTintColor = NSColor.systemGreen
        allowAllBtn.target = self
        allowAllBtn.action = #selector(allowAllClicked)
        glass.addSubview(allowAllBtn)

        panel.contentView = glass
        panel.orderFrontRegardless()
        allowAllPanel = panel

        // Fade in
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func dismissAllowAllBar() {
        guard let panel = allowAllPanel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.close()
            self.allowAllPanel = nil
        })
    }

    @objc func allowAllClicked() {
        let ids = pendingIds
        for id in ids {
            sendDecision(id: id, decision: "allow")
        }
        dismissAllPanels()
    }

    func repositionPanels() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 340
        let panelHeight: CGFloat = 158
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

        // Reposition Allow All bar if visible
        if panels.count >= 2 {
            showAllowAllBar()
        } else {
            dismissAllowAllBar()
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
