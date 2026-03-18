// TerminalSession.swift — Terminal session model and supporting views
//
// Contains:
//   - InsetFrostView: Decorative inner glow along window edges
//   - CursorBracketOverlay: Two horizontal lines bracketing the cursor row
//   - GlowButton: NSButton that glows on hover
//   - TerminalSession: A single terminal shell instance with metadata

import Cocoa
import SwiftTerm

// ── Inset Frost View ──

/// Draws a subtle white inner shadow around the window edges using even-odd
/// clipping. The view is non-interactive (hitTest returns nil) and floats
/// above all content as a decorative overlay.
class InsetFrostView: NSView {
    var cornerRadius: CGFloat = 12
    private var glowLayer: CAShapeLayer?
    private var isGlowing = false

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let inset = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = CGPath(roundedRect: inset, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.addRect(bounds.insetBy(dx: -20, dy: -20))
        ctx.clip(using: .evenOdd)

        ctx.setShadow(offset: .zero, blur: 16, color: NSColor(white: 1.0, alpha: 0.6).cgColor)
        ctx.setFillColor(NSColor(white: 1.0, alpha: 0.7).cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    /// Starts or stops a breathing white glow around the window border.
    func setGlowing(_ on: Bool) {
        guard on != isGlowing else { return }
        isGlowing = on

        if on {
            startGlow()
        } else {
            stopGlow()
        }
    }

    override func layout() {
        super.layout()
        // Keep glow layer in sync with view bounds
        if let gl = glowLayer {
            gl.frame = bounds
            let inset = bounds.insetBy(dx: 1, dy: 1)
            gl.path = CGPath(roundedRect: inset, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        }
    }

    private func startGlow() {
        wantsLayer = true
        let gl = CAShapeLayer()
        gl.frame = bounds
        let inset = bounds.insetBy(dx: 1, dy: 1)
        gl.path = CGPath(roundedRect: inset, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        gl.fillColor = nil
        gl.strokeColor = NSColor(white: 1.0, alpha: 0.5).cgColor
        gl.lineWidth = 1.5
        gl.shadowColor = NSColor.white.cgColor
        gl.shadowOffset = .zero
        gl.shadowRadius = 12
        gl.shadowOpacity = 0.6
        layer?.addSublayer(gl)
        glowLayer = gl

        // Breathing animation — shadow opacity pulses
        let breathe = CABasicAnimation(keyPath: "shadowOpacity")
        breathe.fromValue = 0.3
        breathe.toValue = 0.8
        breathe.duration = 2.0
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gl.add(breathe, forKey: "breathe")

        // Stroke opacity pulses too
        let strokeBreathe = CABasicAnimation(keyPath: "strokeColor")
        strokeBreathe.fromValue = NSColor(white: 1.0, alpha: 0.2).cgColor
        strokeBreathe.toValue = NSColor(white: 1.0, alpha: 0.6).cgColor
        strokeBreathe.duration = 2.0
        strokeBreathe.autoreverses = true
        strokeBreathe.repeatCount = .infinity
        strokeBreathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gl.add(strokeBreathe, forKey: "strokeBreathe")

        // Fade in
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = 0.4
        gl.opacity = 1.0
        gl.add(fadeIn, forKey: "glowFadeIn")
    }

    private func stopGlow() {
        guard let gl = glowLayer else { return }

        // Fade out then remove
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak gl] in
            gl?.removeFromSuperlayer()
        }
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = gl.presentation()?.opacity ?? gl.opacity
        fadeOut.toValue = 0.0
        fadeOut.duration = 0.5
        gl.opacity = 0.0
        gl.removeAnimation(forKey: "breathe")
        gl.removeAnimation(forKey: "strokeBreathe")
        gl.add(fadeOut, forKey: "glowFadeOut")
        CATransaction.commit()

        glowLayer = nil
    }
}

// ── Glow Button ──

/// NSButton subclass that glows on hover via layer shadow animation.
class GlowButton: NSButton {
    private var trackingArea: NSTrackingArea?
    var restAlpha: CGFloat = 0.75
    var hoverAlpha: CGFloat = 1.0
    var glowColor: NSColor = .white
    var glowRadius: CGFloat = 8
    var glowOpacity: Float = 0.6

    /// White text label shown below the button on hover.
    var hoverText: String?
    private var hoverLabel: NSTextField?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = hoverAlpha
        }
        wantsLayer = true
        layer?.shadowColor = glowColor.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = glowRadius
        let anim = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue = 0
        anim.toValue = glowOpacity
        anim.duration = 0.15
        layer?.shadowOpacity = glowOpacity
        layer?.add(anim, forKey: "glowIn")

        if let text = hoverText, let parent = superview {
            let label = NSTextField(labelWithString: text)
            label.font = NSFont.systemFont(ofSize: 10, weight: .medium)
            label.textColor = NSColor(white: 1.0, alpha: 0.4)
            label.sizeToFit()
            let w = label.fittingSize.width
            let btnCenter = frame.midX
            label.frame = NSRect(x: btnCenter - w / 2, y: frame.minY - 20, width: w, height: 12)
            parent.addSubview(label)
            hoverLabel = label
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().alphaValue = restAlpha
        }
        let anim = CABasicAnimation(keyPath: "shadowOpacity")
        anim.fromValue = glowOpacity
        anim.toValue = 0
        anim.duration = 0.25
        layer?.shadowOpacity = 0
        layer?.add(anim, forKey: "glowOut")

        hoverLabel?.removeFromSuperview()
        hoverLabel = nil
    }
}

// ── Terminal Drop View ──

/// Transparent overlay that accepts file/folder drops and pastes the
/// shell-escaped path(s) into the terminal. Supports multiple files
/// (space-separated). Non-interactive for everything except drops.
class TerminalDropView: NSView {
    weak var terminalView: LocalProcessTerminalView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return hasFileURL(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let tv = terminalView,
              let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
              ) as? [URL] else { return false }

        let paths = urls.map { shellEscape($0.path) }
        guard !paths.isEmpty else { return false }
        tv.send(txt: paths.joined(separator: " "))
        return true
    }

    private func hasFileURL(_ info: NSDraggingInfo) -> Bool {
        return info.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private func shellEscape(_ path: String) -> String {
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// ── Terminal Session ──

/// Session crystal names and their gem colors.
let sessionCrystals: [(name: String, color: (r: CGFloat, g: CGFloat, b: CGFloat))] = [
    ("diamond",    (0.73, 0.84, 0.93)),  // icy blue-white
    ("opal",       (0.80, 0.72, 0.85)),  // iridescent lavender
    ("jade",       (0.40, 0.70, 0.45)),  // muted green
    ("lapis",      (0.25, 0.35, 0.72)),  // deep blue
    ("topaz",      (0.95, 0.65, 0.25)),  // amber
    ("onyx",       (0.60, 0.60, 0.65)),  // dark grey
    ("pearl",      (0.90, 0.88, 0.85)),  // warm white
    ("amber",      (0.90, 0.78, 0.30)),  // golden
    ("quartz",     (0.88, 0.75, 0.80)),  // rose pink
    ("ruby",       (0.82, 0.22, 0.32)),  // red
    ("garnet",     (0.70, 0.15, 0.22)),  // deep red
    ("emerald",    (0.31, 0.78, 0.47)),  // green
    ("cobalt",     (0.36, 0.48, 0.85)),  // deep blue
    ("peridot",    (0.68, 0.82, 0.31)),  // yellow-green
    ("zircon",     (0.55, 0.75, 0.88)),  // sky blue
    ("amethyst",   (0.68, 0.44, 0.72)),  // purple
    ("tanzanite",  (0.55, 0.42, 0.78)),  // violet-blue
    ("carnelian",  (0.85, 0.45, 0.28)),  // red-orange
    ("turquoise",  (0.30, 0.78, 0.76)),  // teal
    ("morganite",  (0.90, 0.68, 0.68)),  // peach pink
]

/// A single terminal shell instance with metadata.
/// Sessions live inside a ProjectTab and share the project's color.
class TerminalSession {
    let id = UUID()
    let terminalView: LocalProcessTerminalView
    var name: String = "diamond"
    var hasCustomName: Bool = false
    var crystalColor: NSColor = .white
    var cwd: String
    var historyLogger: CommandHistoryLogger?
    var detectedAgent: AgentKind = .none
    var isAgentWorking: Bool = false

    /// If non-nil, this session runs in an isolated git worktree at this path.
    var worktreePath: String?
    /// The original project directory (used to clean up the worktree on close).
    var worktreeProjectDir: String?

    /// True if this session is running in a git worktree.
    var isIsolated: Bool { worktreePath != nil }

    init(name: String = "diamond", cwd: String = NSHomeDirectory(), frame: NSRect = NSRect(x: 0, y: 0, width: 900, height: 536)) {
        self.name = name
        self.cwd = cwd
        self.terminalView = LocalProcessTerminalView(frame: frame)
        self.terminalView.autoresizingMask = [.width, .height]
    }

    func start() {
        let shell = "/bin/zsh"
        let shellIdiom = "-" + (shell as NSString).lastPathComponent
        let env = ShellIntegration.shared.environment()
        terminalView.startProcess(executable: shell, environment: env, execName: shellIdiom, currentDirectory: cwd)

        // Register OSC handler for command history after terminal starts
        let logger = CommandHistoryLogger(terminalView: terminalView)
        logger.registerHandler()
        historyLogger = logger
    }

    /// Cleans up the git worktree when this session closes.
    func cleanupWorktree() {
        guard let projectDir = worktreeProjectDir, let _ = worktreePath else { return }
        GitWorktree.remove(projectDir: projectDir, crystalName: name)
        worktreePath = nil
        worktreeProjectDir = nil
    }
}

// ── Split Layout ──

/// Layout mode for a gem's content area.
enum SplitLayout {
    case single
    case horizontal  // side-by-side
}

/// State of a single pane in a split layout.
struct PaneState {
    var sessionIndex: Int?  // nil = showing shard picker
    var isFocused: Bool
}

// ── Project Tab ──

/// Groups one or more terminal sessions under a project directory.
/// Shown as a primary tab in the tab bar. Sessions appear in the session bar.
class ProjectTab {
    let id = UUID()
    var directory: String
    var title: String
    var hasCustomTitle: Bool = false
    var sessions: [TerminalSession] = []
    var color: NSColor
    var iconName: String? = "diamond"
    var isUnconfigured: Bool = false

    // Split state
    var splitLayout: SplitLayout = .single
    var panes: [PaneState] = [PaneState(sessionIndex: 0, isFocused: true)]

    /// Index of the focused pane.
    var focusedPaneIndex: Int { panes.firstIndex(where: { $0.isFocused }) ?? 0 }

    /// The selected session index (focused pane's session).
    var selectedSessionIndex: Int {
        get { panes[focusedPaneIndex].sessionIndex ?? 0 }
        set {
            let idx = focusedPaneIndex
            if idx < panes.count { panes[idx].sessionIndex = newValue }
        }
    }

    /// All session indices currently visible in split panes.
    var visibleSessionIndices: Set<Int> {
        Set(panes.compactMap { $0.sessionIndex })
    }

    var selectedSession: TerminalSession? {
        let idx = selectedSessionIndex
        guard idx >= 0 && idx < sessions.count else { return nil }
        return sessions[idx]
    }

    init(directory: String, color: NSColor) {
        self.directory = directory
        self.color = color
        self.title = (directory as NSString).lastPathComponent

        // Load project config if available
        if let config = ProjectConfig.load(from: directory) {
            if let name = config.name { self.title = name; self.hasCustomTitle = true }
            self.iconName = config.icon
            if let hex = config.color, let c = NSColor(hex: hex) {
                self.color = c
            }
        }
    }

    enum AddSessionResult {
        case created(TerminalSession)
        case notGitRepo
        case worktreeFailed(TerminalSession)  // fell back to shared shard

        /// The session, if one was created.
        var session: TerminalSession? {
            switch self {
            case .created(let s), .worktreeFailed(let s): return s
            case .notGitRepo: return nil
            }
        }
    }

    /// Adds a new session with the next crystal name and color.
    /// If `isolated` is true and the project is a git repo, creates a worktree.
    func addSession(frame: NSRect = NSRect(x: 0, y: 0, width: 900, height: 536), isolated: Bool = false) -> AddSessionResult {
        let idx = sessions.count
        let crystal = idx < sessionCrystals.count ? sessionCrystals[idx] : nil
        let name = crystal?.name ?? "\(idx + 1)"

        var sessionCwd = directory
        var worktreePath: String?
        var worktreeFailed = false

        if isolated {
            if !GitWorktree.isGitRepo(directory) {
                return .notGitRepo
            }
            if let wtPath = GitWorktree.create(projectDir: directory, crystalName: name) {
                sessionCwd = wtPath
                worktreePath = wtPath
            } else {
                worktreeFailed = true
            }
        }

        let session = TerminalSession(name: name, cwd: sessionCwd, frame: frame)
        if let c = crystal {
            session.crystalColor = NSColor(red: c.color.r, green: c.color.g, blue: c.color.b, alpha: 1.0)
        }
        if let wt = worktreePath {
            session.worktreePath = wt
            session.worktreeProjectDir = directory
        }
        sessions.append(session)
        return worktreeFailed ? .worktreeFailed(session) : .created(session)
    }
}
