// SplitViewController.swift — Split pane management for terminal sessions
//
// Contains:
//   - SplitPaneView: NSView subclass with focus border
//   - GlassSplitView: NSSplitView subclass with glass-style divider
//   - SplitViewController: Manages NSSplitView, pane focus, shard picker

import Cocoa
import SwiftTerm

// ── Split Pane View ──

/// Container for one side of a split. Draws a focus border when active.
class SplitPaneView: NSView {
    var focusBorderColor: NSColor = .white
    var isFocused: Bool = false { didSet { needsDisplay = true } }
    var onClicked: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isFocused {
            focusBorderColor.withAlphaComponent(0.4).setStroke()
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        onClicked?()
        super.mouseDown(with: event)
    }
}

// ── Glass Split View ──

/// NSSplitView with a thin glass-style divider.
class GlassSplitView: NSSplitView {
    override var dividerColor: NSColor {
        NSColor(white: 1.0, alpha: 0.15)
    }

    override var dividerThickness: CGFloat { 1.5 }
}

// ── Split View Controller ──

class SplitViewController: NSObject, NSSplitViewDelegate {
    weak var contentArea: NSView?

    private var splitView: GlassSplitView?
    private var leftPane: SplitPaneView?
    private var rightPane: SplitPaneView?
    private var shardPicker: ShardPickerView?

    // Callbacks
    var onFocusChanged: (() -> Void)?
    var onSessionSelected: ((Int) -> Void)?
    var onNewSession: (() -> Void)?
    var onNewIsolatedSession: (() -> Void)?

    // MARK: - Split

    /// Enter split mode: current session stays in left pane, picker appears in right.
    func split(project: ProjectTab) {
        guard let contentArea = contentArea,
              project.splitLayout == .single else { return }

        let currentIdx = project.selectedSessionIndex
        let currentView = project.sessions[currentIdx].terminalView

        // Create split view
        let sv = GlassSplitView(frame: contentArea.bounds)
        sv.isVertical = true
        sv.autoresizingMask = [.width, .height]
        sv.delegate = self

        // Left pane — existing terminal
        let left = SplitPaneView(frame: NSRect(x: 0, y: 0,
                                                width: contentArea.bounds.width / 2,
                                                height: contentArea.bounds.height))
        left.autoresizingMask = [.width, .height]
        let color = project.sessions[currentIdx].crystalColor
        left.focusBorderColor = color
        left.isFocused = false

        currentView.removeFromSuperview()
        currentView.frame = left.bounds
        currentView.autoresizingMask = [.width, .height]
        currentView.isHidden = false
        left.addSubview(currentView)

        left.onClicked = { [weak self] in self?.focusPane(0, project: project) }

        // Right pane — shard picker
        let right = SplitPaneView(frame: NSRect(x: 0, y: 0,
                                                 width: contentArea.bounds.width / 2,
                                                 height: contentArea.bounds.height))
        right.autoresizingMask = [.width, .height]
        right.isFocused = true
        right.focusBorderColor = .white

        let picker = ShardPickerView(frame: right.bounds)
        picker.autoresizingMask = [.width, .height]
        picker.sessions = project.sessions
        picker.visibleSessionIndices = Set([currentIdx])
        picker.projectColor = project.color

        picker.onSelectSession = { [weak self] idx in
            self?.assignSession(idx, toPane: 1, project: project)
        }
        picker.onNewSession = { [weak self] in self?.onNewSession?() }
        picker.onNewIsolatedSession = { [weak self] in self?.onNewIsolatedSession?() }
        picker.onCancel = { [weak self] in self?.unsplit(project: project) }
        picker.setup()

        right.addSubview(picker)
        right.onClicked = { [weak self] in self?.focusPane(1, project: project) }

        sv.addSubview(left)
        sv.addSubview(right)
        sv.adjustSubviews()

        // Hide all other terminal views
        for (i, session) in project.sessions.enumerated() {
            if i != currentIdx {
                session.terminalView.isHidden = true
            }
        }

        contentArea.addSubview(sv)
        splitView = sv
        leftPane = left
        rightPane = right
        shardPicker = picker

        // Update project state
        project.splitLayout = .horizontal
        project.panes = [
            PaneState(sessionIndex: currentIdx, isFocused: false),
            PaneState(sessionIndex: nil, isFocused: true),
        ]

        onFocusChanged?()
    }

    // MARK: - Unsplit

    /// Exit split mode. The focused pane's session becomes the single visible session.
    func unsplit(project: ProjectTab) {
        guard let contentArea = contentArea,
              project.splitLayout != .single else { return }

        // Determine which session to keep visible
        let focusedIdx = project.focusedPaneIndex
        let keepSessionIdx = project.panes[focusedIdx].sessionIndex
            ?? project.panes.compactMap({ $0.sessionIndex }).first
            ?? 0

        // Move all terminal views back to contentArea
        for session in project.sessions {
            session.terminalView.removeFromSuperview()
            session.terminalView.frame = contentArea.bounds
            session.terminalView.autoresizingMask = [.width, .height]
            session.terminalView.isHidden = true
            contentArea.addSubview(session.terminalView)
        }

        // Show the kept session
        if keepSessionIdx < project.sessions.count {
            project.sessions[keepSessionIdx].terminalView.isHidden = false
        }

        // Remove split view
        splitView?.removeFromSuperview()
        splitView = nil
        leftPane = nil
        rightPane = nil
        shardPicker = nil

        // Update project state
        project.splitLayout = .single
        project.panes = [PaneState(sessionIndex: keepSessionIdx, isFocused: true)]

        onFocusChanged?()
    }

    // MARK: - Pane Management

    /// Focus a specific pane.
    func focusPane(_ paneIndex: Int, project: ProjectTab) {
        for i in 0..<project.panes.count {
            project.panes[i].isFocused = (i == paneIndex)
        }
        leftPane?.isFocused = (paneIndex == 0)
        rightPane?.isFocused = (paneIndex == 1)

        // Update focus border color
        if let idx = project.panes[paneIndex].sessionIndex, idx < project.sessions.count {
            let pane = paneIndex == 0 ? leftPane : rightPane
            pane?.focusBorderColor = project.sessions[idx].crystalColor
        }

        // Make the terminal first responder
        if let idx = project.panes[paneIndex].sessionIndex, idx < project.sessions.count {
            let tv = project.sessions[idx].terminalView
            tv.window?.makeFirstResponder(tv)
        }

        onFocusChanged?()
    }

    /// Assign a session to a pane (replaces picker or swaps content).
    func assignSession(_ sessionIndex: Int, toPane paneIndex: Int, project: ProjectTab) {
        guard sessionIndex < project.sessions.count else { return }
        // Don't assign a session that's already visible in the other pane
        let otherPane = paneIndex == 0 ? 1 : 0
        if otherPane < project.panes.count, project.panes[otherPane].sessionIndex == sessionIndex {
            return
        }
        let pane = paneIndex == 0 ? leftPane : rightPane
        guard let pane = pane else { return }

        // Remove old content
        for sub in pane.subviews { sub.removeFromSuperview() }

        // Place the terminal view
        let session = project.sessions[sessionIndex]
        session.terminalView.removeFromSuperview()
        session.terminalView.frame = pane.bounds
        session.terminalView.autoresizingMask = [.width, .height]
        session.terminalView.isHidden = false
        pane.addSubview(session.terminalView)

        // Update border color
        pane.focusBorderColor = session.crystalColor

        // Update state
        project.panes[paneIndex].sessionIndex = sessionIndex
        shardPicker = nil

        // Focus this pane
        focusPane(paneIndex, project: project)
    }

    /// Swap a session into the focused pane.
    func swapSessionIntoFocusedPane(_ sessionIndex: Int, project: ProjectTab) {
        // If already visible in a pane, just focus that pane
        if let existingPane = project.panes.firstIndex(where: { $0.sessionIndex == sessionIndex }) {
            focusPane(existingPane, project: project)
            return
        }
        assignSession(sessionIndex, toPane: project.focusedPaneIndex, project: project)
    }

    /// Close the focused pane (collapse split).
    func closeFocusedPane(project: ProjectTab) {
        unsplit(project: project)
    }

    /// Whether a split is currently active.
    var isSplit: Bool { splitView != nil }

    /// Tear down the split view without changing project state (used when switching projects).
    func tearDown() {
        splitView?.removeFromSuperview()
        splitView = nil
        leftPane = nil
        rightPane = nil
        shardPicker = nil
    }

    /// Restore split view for a project (used when switching back to a split project).
    func restore(project: ProjectTab) {
        guard let contentArea = contentArea,
              project.splitLayout == .horizontal,
              project.panes.count == 2 else { return }

        let sv = GlassSplitView(frame: contentArea.bounds)
        sv.isVertical = true
        sv.autoresizingMask = [.width, .height]
        sv.delegate = self

        let left = SplitPaneView(frame: NSRect(x: 0, y: 0,
                                                width: contentArea.bounds.width / 2,
                                                height: contentArea.bounds.height))
        left.autoresizingMask = [.width, .height]
        left.isFocused = project.panes[0].isFocused
        left.onClicked = { [weak self] in self?.focusPane(0, project: project) }

        let right = SplitPaneView(frame: NSRect(x: 0, y: 0,
                                                 width: contentArea.bounds.width / 2,
                                                 height: contentArea.bounds.height))
        right.autoresizingMask = [.width, .height]
        right.isFocused = project.panes[1].isFocused
        right.onClicked = { [weak self] in self?.focusPane(1, project: project) }

        for (i, pane) in [(0, left), (1, right)] as [(Int, SplitPaneView)] {
            if let sessionIdx = project.panes[i].sessionIndex, sessionIdx < project.sessions.count {
                let session = project.sessions[sessionIdx]
                session.terminalView.removeFromSuperview()
                session.terminalView.frame = pane.bounds
                session.terminalView.autoresizingMask = [.width, .height]
                session.terminalView.isHidden = false
                pane.addSubview(session.terminalView)
                pane.focusBorderColor = session.crystalColor
            }
        }

        sv.addSubview(left)
        sv.addSubview(right)
        sv.adjustSubviews()
        contentArea.addSubview(sv)

        splitView = sv
        leftPane = left
        rightPane = right
    }

    // MARK: - NSSplitViewDelegate

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return max(proposedMinimumPosition, 200)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        return min(proposedMaximumPosition, splitView.bounds.width - 200)
    }
}
