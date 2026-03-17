// SettingsView.swift — Settings panel with sidebar navigation and shared layout helpers
//
// Contains:
//   - SettingsPage: enum of navigation pages
//   - flipToSettings() / flipToTerminal(): card-flip transitions
//   - buildSettingsView(): sidebar + content layout
//   - buildPage(): page router
//   - Shared layout helpers: makeDocView, finalizeDocView, addSectionHeader, etc.
//   - settingsNavClicked(): sidebar navigation handler
//   - rebuildSettings() / findView(): settings view management
//   - DemoRunner: orchestrates the Crystl demo sequence
//   - animateWindowOpen(): window open animation with scale/blur/shimmer

import Cocoa

// ── Settings Page ──

/// Pages available in the settings sidebar.
enum SettingsPage: String, CaseIterable {
    case general = "General"
    case claude = "Claude"
    case codex = "Codex"
    case mcpServers = "MCP Servers"
    case starters = "Starter Files"
    case apiKeys = "API Keys"
    case license = "License"
}

// ── Settings Builder ──

extension TerminalWindowController {

    func flipToSettings() {
        guard let container = window.contentView else { return }
        isShowingSettings = true

        let settings = buildSettingsView()
        settings.frame = container.bounds
        settingsView = settings

        let terminalViews = container.subviews.filter {
            !($0 is NSVisualEffectView) && !($0 is CharcoalBackingView)
        }

        container.layer?.cornerRadius = 0

        let transition = CATransition()
        transition.duration = 0.6
        transition.type = CATransitionType(rawValue: "flip")
        transition.subtype = .fromRight
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.wantsLayer = true
        container.layer?.add(transition, forKey: "settingsFlip")

        for sub in terminalViews {
            sub.isHidden = true
            sub.layer?.opacity = 0
        }
        container.addSubview(settings)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            container.layer?.cornerRadius = 16
        }
    }

    func flipToTerminal() {
        guard let container = window.contentView, let settings = settingsView else { return }
        isShowingSettings = false

        container.layer?.cornerRadius = 0

        let transition = CATransition()
        transition.duration = 0.6
        transition.type = CATransitionType(rawValue: "flip")
        transition.subtype = .fromLeft
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.wantsLayer = true
        container.layer?.add(transition, forKey: "settingsFlip")

        settings.removeFromSuperview()
        self.settingsView = nil
        for sub in container.subviews where !(sub is NSVisualEffectView) && !(sub is CharcoalBackingView) {
            sub.isHidden = false
            sub.layer?.opacity = 1
        }

        if let session = selectedSession {
            window.makeFirstResponder(session.terminalView)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            container.layer?.cornerRadius = 16
        }
    }

    @objc func flipBackClicked() { flipToTerminal() }

    // MARK: - Main Settings View

    func buildSettingsView() -> NSView {
        guard let container = window.contentView else { return NSView() }
        let bounds = container.bounds

        let view = NSView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.masksToBounds = true

        let glass = NSVisualEffectView(frame: bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.autoresizingMask = [.width, .height]
        glass.appearance = NSAppearance(named: .darkAqua)
        view.addSubview(glass)

        // ── Layout constants ──
        let sidebarW: CGFloat = 200
        let sidebarTopPad: CGFloat = 52   // sidebar clears traffic lights
        let contentTopPad: CGFloat = 100  // content area below title

        // ── Title ──
        let title = NSTextField(labelWithString: "Settings")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .white
        title.frame = NSRect(x: sidebarW + 32, y: bounds.height - contentTopPad + 10, width: bounds.width - sidebarW - 32, height: 28)
        title.autoresizingMask = [.width, .minYMargin]
        view.addSubview(title)

        // ── Sidebar ──
        let sidebarFrame = NSRect(x: 0, y: 0, width: sidebarW, height: bounds.height - sidebarTopPad)
        let sidebar = NSView(frame: sidebarFrame)
        sidebar.autoresizingMask = [.height]

        var navY = sidebarFrame.height - 12
        let itemH: CGFloat = 30

        for page in SettingsPage.allCases {
            navY -= itemH
            let isSelected = page == settingsSelectedPage

            if isSelected {
                let bg = NSView(frame: NSRect(x: 12, y: navY, width: sidebarW - 24, height: itemH))
                bg.wantsLayer = true
                bg.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.1).cgColor
                bg.layer?.cornerRadius = 6
                sidebar.addSubview(bg)
            }

            let item = NSButton(frame: NSRect(x: 20, y: navY, width: sidebarW - 32, height: itemH))
            item.title = page.rawValue
            item.bezelStyle = .inline
            item.isBordered = false
            item.font = NSFont.systemFont(ofSize: 12, weight: isSelected ? .semibold : .regular)
            item.contentTintColor = isSelected ? .white : NSColor(white: 1.0, alpha: 0.6)
            item.alignment = .left

            item.identifier = NSUserInterfaceItemIdentifier("settingsNav:\(page.rawValue)")
            item.target = self
            item.action = #selector(settingsNavClicked(_:))
            sidebar.addSubview(item)
        }

        view.addSubview(sidebar)

        // ── Separator line ──
        let sep = NSView(frame: NSRect(x: sidebarW, y: 0, width: 1, height: bounds.height - sidebarTopPad))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        sep.autoresizingMask = [.height]
        view.addSubview(sep)

        // ── Content area (scrollable) ──
        let contentFrame = NSRect(x: sidebarW + 1, y: 0, width: bounds.width - sidebarW - 1, height: bounds.height - contentTopPad)
        let contentScroll = NSScrollView(frame: contentFrame)
        contentScroll.hasVerticalScroller = true
        contentScroll.hasHorizontalScroller = false
        contentScroll.autohidesScrollers = true
        contentScroll.borderType = .noBorder
        contentScroll.drawsBackground = false
        contentScroll.autoresizingMask = [.width, .height]
        contentScroll.scrollerStyle = .overlay

        let pageContent = buildPage(settingsSelectedPage, width: contentFrame.width, minHeight: contentFrame.height)
        contentScroll.documentView = pageContent
        view.addSubview(contentScroll)

        // Scroll to top (non-flipped: top = max y)
        if let docView = contentScroll.documentView {
            let topY = max(0, docView.frame.height - contentScroll.contentView.bounds.height)
            contentScroll.contentView.scroll(to: NSPoint(x: 0, y: topY))
        }

        // ── Crystal icon — top right, flips back ──
        let iconSize: CGFloat = 28
        let crystalBtn = GlowButton(frame: NSRect(
            x: bounds.width - iconSize - 14,
            y: bounds.height - iconSize - 18,
            width: iconSize, height: iconSize
        ))
        crystalBtn.autoresizingMask = [.minXMargin, .minYMargin]
        crystalBtn.isBordered = false
        crystalBtn.bezelStyle = .inline
        crystalBtn.target = self
        crystalBtn.action = #selector(flipBackClicked)
        crystalBtn.keyEquivalent = "\u{1b}"
        if let path = Bundle.main.path(forResource: "crystl-white-28@2x", ofType: "png")
            ?? Bundle.main.path(forResource: "crystl-white", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: iconSize, height: iconSize)
            crystalBtn.image = img
            crystalBtn.imageScaling = .scaleProportionallyDown
        }
        crystalBtn.alphaValue = 0.75
        crystalBtn.toolTip = "Back to terminal"
        view.addSubview(crystalBtn)

        return view
    }

    // MARK: - Page Router

    private func buildPage(_ page: SettingsPage, width: CGFloat, minHeight: CGFloat = 0) -> NSView {
        switch page {
        case .general:    return buildGeneralPage(width: width, minH: minHeight)
        case .claude:     return buildClaudePage(width: width, minH: minHeight)
        case .codex:      return buildCodexPage(width: width, minH: minHeight)
        case .mcpServers: return buildMCPPage(width: width, minH: minHeight)
        case .starters:   return buildStartersPage(width: width, minH: minHeight)
        case .apiKeys:    return buildAPIKeysPage(width: width, minH: minHeight)
        case .license:    return buildLicensePage(width: width, minH: minHeight)
        }
    }

    // MARK: - Shared Layout Helpers

    var settingsColWidth: CGFloat { 360 }
    var settingsLabelColor: NSColor { NSColor(white: 1.0, alpha: 0.7) }
    var settingsFieldBg: NSColor { NSColor(white: 1.0, alpha: 0.12) }

    /// Creates a doc view with a generous initial height. Call `finalizeDocView` when done.
    func makeDocView(width: CGFloat) -> (NSView, CGFloat, CGFloat) {
        let docH: CGFloat = 2000  // generous; trimmed by finalizeDocView
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: docH))
        let leftX: CGFloat = 32
        let startY = docH - 24
        return (docView, leftX, startY)
    }

    /// Trims the doc view to fit content, pinning it to the top (high y in non-flipped coords).
    /// Ensures doc is at least `minHeight` tall so scroll-to-top works.
    func finalizeDocView(_ docView: NSView, startY: CGFloat, currentY: CGFloat, width: CGFloat, minHeight: CGFloat = 0) {
        let contentUsed = startY - currentY
        let actualH = max(contentUsed + 48, minHeight)
        docView.frame = NSRect(x: 0, y: 0, width: width, height: actualH)
        let targetTopY = actualH - 24
        let shift = startY - targetTopY
        for sub in docView.subviews { sub.frame.origin.y -= shift }
    }

    func addSectionHeader(_ text: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let header = NSTextField(labelWithString: text)
        header.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        header.textColor = settingsLabelColor
        header.frame = NSRect(x: x, y: y, width: width, height: 14)
        view.addSubview(header)
        y -= 24
    }

    func addFieldLabel(_ text: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        label.textColor = settingsLabelColor
        label.frame = NSRect(x: x, y: y, width: width, height: 14)
        view.addSubview(label)
        y -= 32
    }

    func addTextField(_ value: String, placeholder: String? = nil, editable: Bool = true,
                      to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat,
                      id: String? = nil, action: Selector? = nil) -> NSTextField {
        let field = NSTextField(string: value)
        field.cell = VerticallyCenteredTextFieldCell(textCell: value)
        if let ph = placeholder {
            field.placeholderAttributedString = NSAttributedString(string: ph, attributes: [
                .foregroundColor: NSColor(white: 1.0, alpha: 0.35),
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ])
        }
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = editable ? .white : NSColor(white: 1.0, alpha: 0.5)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.isEditable = editable
        field.isSelectable = true
        field.wantsLayer = true
        field.layer?.backgroundColor = settingsFieldBg.cgColor
        field.layer?.cornerRadius = 8
        field.layer?.masksToBounds = true
        field.frame = NSRect(x: x, y: y, width: width, height: 28)
        if let id = id { field.identifier = NSUserInterfaceItemIdentifier(id) }
        if let action = action { field.target = self; field.action = action }
        view.addSubview(field)
        y -= 38
        return field
    }

    func addPopup(_ items: [String], selected: String? = nil,
                  to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat,
                  action: Selector) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: x, y: y, width: width, height: 28))
        popup.addItems(withTitles: items)
        if let sel = selected { popup.selectItem(withTitle: sel) }
        popup.font = NSFont.systemFont(ofSize: 12)
        popup.appearance = NSAppearance(named: .darkAqua)
        popup.target = self
        popup.action = action
        view.addSubview(popup)
        y -= 38
        return popup
    }

    func addButton(_ title: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat,
                   tintColor: NSColor = NSColor(white: 1.0, alpha: 0.6),
                   bgColor: NSColor? = nil,
                   action: Selector) -> NSButton {
        let btn = NSButton(frame: NSRect(x: x, y: y, width: width, height: 28))
        btn.title = title
        btn.bezelStyle = .rounded
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.backgroundColor = (bgColor ?? settingsFieldBg).cgColor
        btn.layer?.cornerRadius = 8
        btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        btn.contentTintColor = tintColor
        btn.target = self
        btn.action = action
        view.addSubview(btn)
        y -= 38
        return btn
    }

    func addDescription(_ text: String, to view: NSView, x: CGFloat, y: inout CGFloat, width: CGFloat) {
        let desc = NSTextField(labelWithString: text)
        desc.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        desc.textColor = NSColor(white: 1.0, alpha: 0.5)
        desc.frame = NSRect(x: x, y: y, width: width, height: 14)
        view.addSubview(desc)
        y -= 24
    }

    // MARK: - Navigation Action

    @objc func settingsNavClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue,
              raw.hasPrefix("settingsNav:") else { return }
        let pageName = String(raw.dropFirst(12))
        guard let page = SettingsPage(rawValue: pageName) else { return }
        settingsSelectedPage = page
        rebuildSettings()
    }

    /// Rebuilds the settings view in place (no flip animation).
    func rebuildSettings() {
        guard let container = window.contentView, let old = settingsView else { return }
        old.removeFromSuperview()
        let newSettings = buildSettingsView()
        newSettings.frame = container.bounds
        settingsView = newSettings
        container.addSubview(newSettings)
    }

    func findView(in view: NSView, id: String) -> NSView? {
        if view.identifier?.rawValue == id { return view }
        for sub in view.subviews {
            if let found = findView(in: sub, id: id) { return found }
        }
        if let sv = view as? NSScrollView, let doc = sv.documentView {
            if let found = findView(in: doc, id: id) { return found }
        }
        return nil
    }
}

// ── Demo Runner ──

/// Orchestrates the full Crystl demo: fades out, sets up projects, animates back in,
/// shows code in terminal, then sends approval/notification events to the bridge.
class DemoRunner {
    static let demoDir = "/tmp/crystl-demo"
    static let bridge = "http://127.0.0.1:19280"

    struct DemoProject {
        let name: String
        let icon: String
        let color: String
    }

    static let projects = [
        DemoProject(name: "webapp", icon: "rocket", color: "#7AA2F7"),
        DemoProject(name: "wordpress-site", icon: "zap", color: "#F7768E"),
        DemoProject(name: "design-system", icon: "gem", color: "#BB9AF7"),
        DemoProject(name: "infra", icon: "shield", color: "#FF9E64"),
    ]

    static func run(terminalController tc: TerminalWindowController, appDelegate: AppDelegate) {
        guard let win = tc.window else { return }

        // 1. Fade out window + rail
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            win.animator().alphaValue = 0
            appDelegate.rail?.panel.animator().alphaValue = 0
        }, completionHandler: {
            // 2. Close all tabs except one
            while tc.projects.count > 1 {
                tc.closeProject(tc.projects.count - 1)
            }
            // Remove tiles from rail
            appDelegate.rail?.removeAllTiles()

            // 3. Create demo project files on disk
            createDemoFiles()

            // 4. Set bridge to manual mode
            saveBridgeSettings()
            setBridgeManualMode()

            // 5. Open demo projects — first one replaces current tab
            tc.projects[0].sessions.forEach { $0.terminalView.removeFromSuperview() }
            tc.projects.removeAll()

            for proj in projects {
                let path = demoDir + "/" + proj.name
                let color = NSColor(hex: proj.color) ?? .white
                let project = ProjectTab(directory: path, color: color)
                project.iconName = proj.icon
                guard let session = project.addSession(frame: tc.contentArea.bounds).session else { continue }
                session.terminalView.processDelegate = tc
                tc.projects.append(project)

                tc.configureTerminalAppearance(session.terminalView, sessionId: session.id)
                session.terminalView.frame = tc.contentArea.bounds
                session.terminalView.isHidden = true
                tc.contentArea.addSubview(session.terminalView)

                // Add a second shard to api-server for split view demo
                if proj.name == "wordpress-site" {
                    if let shard2 = project.addSession(frame: tc.contentArea.bounds).session {
                        shard2.terminalView.processDelegate = tc
                        tc.configureTerminalAppearance(shard2.terminalView, sessionId: shard2.id)
                        shard2.terminalView.frame = tc.contentArea.bounds
                        shard2.terminalView.isHidden = true
                        tc.contentArea.addSubview(shard2.terminalView)
                    }
                }

                tc.onTabAdded?(project)
            }

            tc.selectedProjectIndex = 0
            tc.selectProject(0)
            tc.updateTabBar()

            // Make window visible and animate in
            win.alphaValue = 1
            win.makeKeyAndOrderFront(nil)
            appDelegate.rail?.panel.alphaValue = 1
            appDelegate.rail?.animateOpen()

            if let container = win.contentView {
                tc.animateWindowOpen(container: container)
            }

            // 6. Start shells immediately — autorun begins typing "claude"
            tc.setOpacity(0.5)
            for project in tc.projects {
                for session in project.sessions {
                    session.start()
                    tc.hideScroller(in: session.terminalView, sessionId: session.id)
                }
            }

            // 7. Show approval flyout after Claude banner appears (~2.5s from shell start)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                tc.syncSettings(mode: "manual", paused: false)
                if let iconView = appDelegate.rail?.iconView {
                    appDelegate.showRailSettingsMenu(from: iconView)
                }
            }

            // After 4s, animate selection down to "smart"
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                appDelegate.animateFlyoutSelection(to: "smart")
                tc.syncSettings(mode: "smart", paused: false)
            }

            // After 5.5s, close the flyout (prompt typing starts around now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.5) {
                appDelegate.closeFlyout()
            }

            // 8. Webapp events while viewing webapp (~14s from shell start)
            DispatchQueue.global().asyncAfter(deadline: .now() + 14) {

                // Phase 1: webapp approvals (matches the tab we're viewing)
                sendApprovalEvents()

                // Phase 2: Allow All after 3s
                Thread.sleep(forTimeInterval: 3)
                DispatchQueue.main.async {
                    appDelegate.allowAllClicked()
                }

                // Phase 3: webapp notification
                Thread.sleep(forTimeInterval: 1)
                sendWebappNotification()

                // Phase 4: dismiss notification after 6s
                Thread.sleep(forTimeInterval: 6)
                DispatchQueue.main.async {
                    appDelegate.highlightNotificationDismissButtons()
                }
                Thread.sleep(forTimeInterval: 0.4)
                DispatchQueue.main.async {
                    appDelegate.dismissAllNotificationsClicked()
                }

                // Phase 5: switch to api-server + split view
                Thread.sleep(forTimeInterval: 1)
                DispatchQueue.main.async {
                    let apiIdx = tc.projects.firstIndex(where: { $0.directory.hasSuffix("wordpress-site") }) ?? 1
                    tc.selectProject(apiIdx)
                    tc.updateTabBar()

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        guard apiIdx < tc.projects.count else { return }
                        let project = tc.projects[apiIdx]
                        if let sc = tc.splitController {
                            sc.split(project: project)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                if project.sessions.count > 1 {
                                    sc.assignSession(1, toPane: 1, project: project)
                                    tc.updateSessionBar()
                                }
                            }
                        }
                    }
                }

                // Phase 6: api-server approvals (viewing api-server now)
                Thread.sleep(forTimeInterval: 2)
                sendApiServerApprovalEvents()

                // Phase 7: Allow All after 3s
                Thread.sleep(forTimeInterval: 3)
                DispatchQueue.main.async {
                    appDelegate.allowAllClicked()
                }

                // Phase 8: api-server + infra notifications
                Thread.sleep(forTimeInterval: 1)
                sendNotificationEvents()

                // Phase 9: dismiss notifications after 6s
                Thread.sleep(forTimeInterval: 6)
                DispatchQueue.main.async {
                    appDelegate.highlightNotificationDismissButtons()
                }
                Thread.sleep(forTimeInterval: 0.4)
                DispatchQueue.main.async {
                    appDelegate.dismissAllNotificationsClicked()
                }

                // Phase 10: New Project panel
                Thread.sleep(forTimeInterval: 1.5)
                DispatchQueue.main.async {
                    appDelegate.rail?.showNewProjectPanel()
                }
                Thread.sleep(forTimeInterval: 0.8)
                let demoName = "terminal-project"
                for (i, ch) in demoName.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.06) {
                        let partial = String(demoName.prefix(i + 1))
                        appDelegate.rail?.newProjectPanel.setName(partial)
                    }
                }
                let typeTime = Double(demoName.count) * 0.06 + 0.4
                Thread.sleep(forTimeInterval: typeTime)
                DispatchQueue.main.async {
                    appDelegate.rail?.newProjectPanel.selectColor(3)
                }
                Thread.sleep(forTimeInterval: 0.6)
                DispatchQueue.main.async {
                    appDelegate.rail?.newProjectPanel.selectIcon("sparkles")
                }
                Thread.sleep(forTimeInterval: 1.5)
                DispatchQueue.main.async {
                    appDelegate.rail?.newProjectPanel.dismiss()
                }
                Thread.sleep(forTimeInterval: 0.6)
                DispatchQueue.main.async {
                    if let sc = tc.splitController, sc.isSplit,
                       let project = tc.selectedProject {
                        sc.unsplit(project: project)
                    }
                    tc.addProject(cwd: demoDir + "/terminal-project")
                }

                Thread.sleep(forTimeInterval: 18)
                restoreBridgeSettings()
            }
        })
    }

    // MARK: - File Creation

    static func createDemoFiles() {
        let fm = FileManager.default
        try? fm.removeItem(atPath: demoDir)

        // webapp
        let webapp = demoDir + "/webapp"
        try? fm.createDirectory(atPath: webapp + "/src/components", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: webapp + "/src/api", withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: webapp + "/.crystl", withIntermediateDirectories: true)
        try? "{ \"color\": \"#7AA2F7\", \"icon\": \"rocket\" }".write(toFile: webapp + "/.crystl/project.json", atomically: true, encoding: .utf8)

        let dashboardCode = """
        import React, { useState, useEffect } from 'react';
        import { Card, Grid, Metric, Text, AreaChart } from '@tremor/react';
        import { fetchAnalytics, AnalyticsData } from '../api/analytics';

        interface DashboardProps {
          projectId: string;
          dateRange: [Date, Date];
        }

        export default function Dashboard({ projectId, dateRange }: DashboardProps) {
          const [data, setData] = useState<AnalyticsData | null>(null);
          const [loading, setLoading] = useState(true);

          useEffect(() => {
            setLoading(true);
            fetchAnalytics(projectId, dateRange)
              .then(setData)
              .finally(() => setLoading(false));
          }, [projectId, dateRange]);

          if (loading) return <Skeleton rows={4} />;

          return (
            <Grid numItems={3} className="gap-6">
              <Card decoration="top" decorationColor="blue">
                <Text>Active Users</Text>
                <Metric>{data?.activeUsers.toLocaleString()}</Metric>
              </Card>
              <Card decoration="top" decorationColor="emerald">
                <Text>Revenue</Text>
                <Metric>${data?.revenue.toLocaleString()}</Metric>
              </Card>
              <Card decoration="top" decorationColor="amber">
                <Text>Conversion Rate</Text>
                <Metric>{data?.conversionRate}%</Metric>
              </Card>
              <AreaChart
                className="h-72 mt-4"
                data={data?.timeline ?? []}
                index="date"
                categories={["pageViews", "uniqueVisitors"]}
                colors={["blue", "cyan"]}
                showAnimation={true}
              />
            </Grid>
          );
        }
        """
        try? dashboardCode.write(toFile: webapp + "/src/components/Dashboard.tsx", atomically: true, encoding: .utf8)

        // Autorun script for webapp
        // Timeline: t=0 clear, t=0.5 type "claude", t=2 banner, t=5 type prompt,
        //           t=8.5 thinking animation, t=13 explanation, t=13.5 "Waiting for approval..."
        let autorun = """
        clear
        sleep 0.5
        echo -e "\\033[0;36m\u{276F}\\033[0m \\c"
        for c in c l a u d e; do echo -n "$c"; sleep 0.08; done
        echo ""
        sleep 1
        echo ""
        O="\\033[38;5;208m"; W="\\033[1;37m"; D="\\033[38;5;245m"; R="\\033[0m"; G="\\033[0;37m"
        echo -e "${O}\u{256D}\u{2500}\u{2500}\u{2500} Claude Code v2.1.75 \u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{256E}${R}"
        echo -e "${O}\u{2502}${R}                                             ${O}\u{2502}${R} ${W}Tips for getting started${R}                 ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}             ${W}Welcome back Chris!${R}             ${O}\u{2502}${R} Run ${W}/init${R} to create a CLAUDE.md file     ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}                                             ${O}\u{2502}${R} ${D}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}${R}  ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}                   ${O}\u{258C}\u{259B}\u{2588}\u{2588}\u{2588}\u{259C}\u{258C}${R}                   ${O}\u{2502}${R} ${W}Recent activity${R}                          ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}                  ${O}\u{259D}\u{259C}\u{2588}\u{2588}\u{2588}\u{2588}\u{2588}\u{259B}\u{2598}${R}                  ${O}\u{2502}${R} ${D}No recent activity${R}                       ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}                    ${O}\u{2598}\u{2598} \u{259D}\u{259D}${R}                    ${O}\u{2502}${R}                                          ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}                                             ${O}\u{2502}${R}                                          ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}   ${D}Opus 4.6 (1M context) \u{00B7} Claude Max \u{00B7}${R}      ${O}\u{2502}${R}                                          ${O}\u{2502}${R}"
        echo -e "${O}\u{2502}${R}        ${G}/tmp/crystl-demo/webapp${R}              ${O}\u{2502}${R}                                          ${O}\u{2502}${R}"
        echo -e "${O}\u{2570}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{256F}${R}"
        echo ""
        echo -e "  ${D}\u{2191} Opus now defaults to 1M context \u{00B7} 5x more room, same pricing${R}"
        echo ""
        sleep 3
        echo -ne "\\033[1;35m\u{276F}\\033[0m "
        prompt="Add error handling with a retry button to the Dashboard component"
        for (( i=0; i<${#prompt}; i++ )); do
            echo -n "${prompt:$i:1}"
            sleep 0.025
        done
        echo ""
        sleep 1.5
        echo ""
        echo -ne "${O}\u{25CF} Reading...${R}"
        sleep 1.0
        echo -ne "\\r\\033[2K${O}\u{25CF} Analyzing...${R}"
        sleep 1.2
        echo -ne "\\r\\033[2K${O}\u{25CF} Crystalizing...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K${O}\u{25CF} Fermenting...${R}"
        sleep 1.0
        echo -ne "\\r\\033[2K"
        echo ""
        echo -e "I'll add error handling with a retry mechanism. This requires:"
        echo ""
        echo -e "  1. Adding error state and refetch logic to the hook"
        echo -e "  2. Creating an \\033[1mErrorCard\\033[0m component with a retry button"
        echo -e "  3. Running the test suite to verify"
        echo ""
        sleep 0.5
        echo -e "\\033[0;33m\u{23F3} Waiting for approval...\\033[0m"
        """
        try? autorun.write(toFile: webapp + "/.crystl/autorun.sh", atomically: true, encoding: .utf8)

        // wordpress-site — config + autorun showing Claude active
        let apiServer = demoDir + "/wordpress-site"
        try? fm.createDirectory(atPath: apiServer + "/.crystl", withIntermediateDirectories: true)
        try? "{ \"color\": \"#F7768E\", \"icon\": \"zap\" }".write(toFile: apiServer + "/.crystl/project.json", atomically: true, encoding: .utf8)

        // Timeline: t=0 clear, t=3 thinking starts, t=11.5 explanation + question prompt.
        // We switch to this tab at ~13s, so the user sees the question prompt on screen.
        let apiAutorun = """
        clear
        sleep 0.5
        O="\\033[38;5;208m"; W="\\033[1;37m"; D="\\033[38;5;245m"; R="\\033[0m"
        echo -e "\\033[0;36m\u{276F}\\033[0m claude"
        sleep 0.8
        echo ""
        echo -e "${O}\u{256D}\u{2500}\u{2500}\u{2500} Claude Code v2.1.75 \u{2500}\u{2500}\u{2500}\u{256E}${R}"
        echo -e "${O}\u{2502}${R}  ${D}Opus 4.6 \u{00B7} Claude Max${R}  ${O}\u{2502}${R}"
        echo -e "${O}\u{2570}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{256F}${R}"
        echo ""
        echo -e "\\033[1;35m\u{276F}\\033[0m Can you update the hero section on homepage to be more conversion focused?"
        echo ""
        echo -ne "${O}\u{25CF} Reading...${R}"
        sleep 1.2
        echo -ne "\\r\\033[2K${O}\u{25CF} Analyzing...${R}"
        sleep 1.2
        echo -ne "\\r\\033[2K${O}\u{25CF} Drafting...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K${O}\u{25CF} Crystalizing...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K${O}\u{25CF} Formatting...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K${O}\u{25CF} Validating...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K"
        echo ""
        echo -e "I'll update the hero section content and publish it via"
        echo -e "${W}wp-json/wp/v2/pages${R} using the REST API."
        echo ""
        echo -e "${W}Should I also update the meta description for SEO?${R}"
        echo ""
        echo -e "\\033[0;36m\u{276F}\\033[0m ${W}1.${R} ${W}Yes${R}"
        echo -e "     ${D}Update meta description too${R}"
        echo -e "  ${W}2.${R} ${W}Yes, and don't ask again${R}"
        echo -e "     ${D}Always update SEO fields with content changes${R}"
        echo -e "  ${W}3.${R} ${W}No${R}"
        echo -e "     ${D}Just update the hero content${R}"
        echo -e "  ${W}4.${R} Type something."
        echo ""
        echo -e "${D}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}${R}"
        echo ""
        echo -e "  ${W}5.${R} Chat about this"
        echo ""
        echo -e "${D}Enter to select \u{00B7} \u{2191}/\u{2193} to navigate \u{00B7} Esc to cancel${R}"
        sleep 7
        echo ""
        echo -e "  ${W}\u{2713} Yes${R}"
        echo ""
        echo -ne "${O}\u{25CF} Implementing...${R}"
        sleep 1.2
        echo -ne "\\r\\033[2K${O}\u{25CF} Dilly-dallying...${R}"
        sleep 1.0
        echo -ne "\\r\\033[2K${O}\u{25CF} Deciphering...${R}"
        sleep 1.2
        echo -ne "\\r\\033[2K${O}\u{25CF} Compiling...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K${O}\u{25CF} Crystalizing...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K${O}\u{25CF} Percolating...${R}"
        sleep 1.5
        echo -ne "\\r\\033[2K${O}\u{25CF} Transmuting...${R}"
        sleep 30
        """
        try? apiAutorun.write(toFile: apiServer + "/.crystl/autorun.sh", atomically: true, encoding: .utf8)

        // Other projects — just config + icon
        for proj in projects where proj.name != "webapp" && proj.name != "wordpress-site" {
            let dir = demoDir + "/" + proj.name
            try? fm.createDirectory(atPath: dir + "/.crystl", withIntermediateDirectories: true)
            let config = "{ \"color\": \"\(proj.color)\", \"icon\": \"\(proj.icon)\" }"
            try? config.write(toFile: dir + "/.crystl/project.json", atomically: true, encoding: .utf8)
        }

        // terminal-project — created via New Project panel in demo, shows Claude features output
        let saas = demoDir + "/terminal-project"
        try? fm.createDirectory(atPath: saas + "/.crystl", withIntermediateDirectories: true)
        try? "{ \"color\": \"#9ECE6A\", \"icon\": \"sparkles\" }".write(toFile: saas + "/.crystl/project.json", atomically: true, encoding: .utf8)

        let saasAutorun = """
        clear
        sleep 0.5
        O="\\033[38;5;208m"; W="\\033[1;37m"; D="\\033[38;5;245m"; R="\\033[0m"
        echo -e "\\033[0;36m\u{276F}\\033[0m \\c"
        for c in c l a u d e; do echo -n "$c"; sleep 0.08; done
        echo ""
        sleep 0.8
        echo ""
        echo -e "${O}\u{256D}\u{2500}\u{2500}\u{2500} Claude Code v2.1.75 \u{2500}\u{2500}\u{2500}\u{256E}${R}"
        echo -e "${O}\u{2502}${R}  ${D}Opus 4.6 \u{00B7} Claude Max${R}  ${O}\u{2502}${R}"
        echo -e "${O}\u{2570}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{256F}${R}"
        echo ""
        sleep 0.5
        echo -ne "\\033[1;35m\u{276F}\\033[0m "
        prompt="What features does Crystl offer?"
        for (( i=0; i<${#prompt}; i++ )); do
            echo -n "${prompt:$i:1}"
            sleep 0.025
        done
        echo ""
        sleep 1
        echo ""
        echo -ne "${O}\u{25CF} Reading...${R}"
        sleep 0.8
        echo -ne "\\r\\033[2K${O}\u{25CF} Crystalizing...${R}"
        sleep 1.0
        echo -ne "\\r\\033[2K${O}\u{25CF} Polishing...${R}"
        sleep 0.8
        echo -ne "\\r\\033[2K"
        echo ""
        echo -e "Crystl is a glass-aesthetic terminal manager designed for Claude Code:"
        echo ""
        sleep 0.3
        echo -e "  ${W}\u{25C6} Gems${R} \u{2500} Tabbed projects with custom icons and colors"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Shards${R} \u{2500} Multiple terminal sessions within each project"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Isolated Shards${R} \u{2500} Git worktree-backed shards for parallel agents"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Crystal Rail${R} \u{2500} Screen-edge dock for quick project switching"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Approval Panels${R} \u{2500} Floating glass panels for permissions"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Smart Approvals${R} \u{2500} Manual, Smart, or Auto approval modes"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Notifications${R} \u{2500} Alerts when Claude finishes or needs attention"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Split View${R} \u{2500} Side-by-side terminal comparison"
        sleep 0.15
        echo -e "  ${W}\u{25C6} API Keys${R} \u{2500} Secure keychain storage, auto-injected into sessions"
        sleep 0.15
        echo -e "  ${W}\u{25C6} Click-to-Open${R} \u{2500} Click file paths to open in your editor"
        echo ""
        sleep 0.3
        echo -e "Crystl keeps you in flow while Claude works across all your"
        echo -e "projects \u{2500} one interface for permissions, progress, and attention."
        sleep 30
        """
        try? saasAutorun.write(toFile: saas + "/.crystl/autorun.sh", atomically: true, encoding: .utf8)
    }

    // MARK: - Bridge Communication

    private static var savedSettings: String?

    /// Read the bridge auth token from ~/.crystl-bridge-token
    private static var authToken: String? = {
        let tokenPath = NSHomeDirectory() + "/.crystl-bridge-token"
        return try? String(contentsOfFile: tokenPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    /// Add auth header to a URLRequest if token is available.
    private static func addAuth(_ req: inout URLRequest) {
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    static func saveBridgeSettings() {
        guard let url = URL(string: bridge + "/settings") else { return }
        var req = URLRequest(url: url)
        addAuth(&req)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data { savedSettings = String(data: data, encoding: .utf8) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 2)
    }

    static func setBridgeManualMode() {
        guard let url = URL(string: bridge + "/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&req)
        let body = """
        {"autoApproveMode":"manual","enabledNotifications":{"Stop":true,"PostToolUse":true,"SubagentStop":true,"TaskCompleted":true,"Notification":true,"TeammateIdle":true,"SessionEnd":true}}
        """
        req.httpBody = body.data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
    }

    static func restoreBridgeSettings() {
        guard let saved = savedSettings, let url = URL(string: bridge + "/settings") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        addAuth(&req)
        req.httpBody = saved.data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
        savedSettings = nil
    }

    static func postBridge(path: String, json: String) {
        guard let url = URL(string: bridge + path) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = json.data(using: .utf8)
        URLSession.shared.dataTask(with: req).resume()
    }

    static func sendApprovalEvents() {
        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Edit","tool_input":{"file_path":"src/components/Dashboard.tsx","old_string":"if (loading) return <Skeleton rows={4} />;","new_string":"if (loading) return <Skeleton rows={4} />;\\n  if (error) return <ErrorCard message={error} onRetry={refetch} />;"},"cwd":"/tmp/crystl-demo/webapp","session_id":"demo-webapp-001","permission_mode":"default"}
        """)
        Thread.sleep(forTimeInterval: 1)

        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Write","tool_input":{"file_path":"src/components/ErrorCard.tsx","content":"export function ErrorCard({ message, onRetry }) { ... }"},"cwd":"/tmp/crystl-demo/webapp","session_id":"demo-webapp-001","permission_mode":"default"}
        """)
        Thread.sleep(forTimeInterval: 1)

        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Bash","tool_input":{"command":"npm test -- --run src/components/Dashboard.test.tsx"},"cwd":"/tmp/crystl-demo/webapp","session_id":"demo-webapp-001","permission_mode":"default"}
        """)
    }

    static func sendApiServerApprovalEvents() {
        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Edit","tool_input":{"file_path":"update-homepage.sh","old_string":"title: Welcome","new_string":"title: Build Faster with AI"},"cwd":"/tmp/crystl-demo/wordpress-site","session_id":"demo-wp-002","permission_mode":"default"}
        """)
        Thread.sleep(forTimeInterval: 1)

        postBridge(path: "/hook?type=PermissionRequest", json: """
        {"tool_name":"Bash","tool_input":{"command":"curl -X POST https://mysite.com/wp-json/wp/v2/pages/2 -H 'Authorization: Bearer $WP_TOKEN' -d @homepage.json"},"cwd":"/tmp/crystl-demo/wordpress-site","session_id":"demo-wp-002","permission_mode":"default"}
        """)
    }

    static func sendWebappNotification() {
        postBridge(path: "/hook?type=Stop", json: """
        {"session_id":"demo-webapp-001","cwd":"/tmp/crystl-demo/webapp","last_assistant_message":"Error handling with retry button added to Dashboard. All tests passing.","stop_hook_active":true}
        """)
    }

    static func sendNotificationEvents() {
        postBridge(path: "/hook?type=Stop", json: """
        {"session_id":"demo-wp-002","cwd":"/tmp/crystl-demo/wordpress-site","last_assistant_message":"Homepage hero updated and published. Meta description refreshed for SEO.","stop_hook_active":true}
        """)
        Thread.sleep(forTimeInterval: 0.8)

        postBridge(path: "/hook?type=Stop", json: """
        {"session_id":"demo-infra-003","cwd":"/tmp/crystl-demo/infra","last_assistant_message":"Terraform plan ready. 3 resources to add, 1 to modify, 0 to destroy.","stop_hook_active":true}
        """)
    }
}

// ── Window Open Animation ──

extension TerminalWindowController {
    func animateWindowOpen(container: NSView) {
        guard let layer = container.layer else {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let duration: CFTimeInterval = 0.9
        let fluidTiming = CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: container.bounds.midX, y: container.bounds.midY)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.0
        scale.toValue = 1.0
        scale.duration = duration
        scale.timingFunction = fluidTiming

        let corners = CABasicAnimation(keyPath: "cornerRadius")
        corners.fromValue = container.bounds.width / 2
        corners.toValue = 16
        corners.duration = duration * 0.7
        corners.timingFunction = fluidTiming

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.0
        opacity.toValue = 1.0
        opacity.duration = duration * 0.4
        opacity.timingFunction = CAMediaTimingFunction(name: .easeIn)

        if let blur = CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 0.0]) {
            layer.filters = [blur]
            layer.setValue(0, forKeyPath: "filters.gaussianBlur.inputRadius")
            let blurAnim = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
            blurAnim.fromValue = 12.0
            blurAnim.toValue = 0.0
            blurAnim.duration = duration * 0.8
            blurAnim.timingFunction = fluidTiming
            layer.add(blurAnim, forKey: "openBlur")
        }

        layer.transform = CATransform3DIdentity
        layer.cornerRadius = 16
        layer.opacity = 1.0

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.window.alphaValue = 1.0
            layer.filters = nil
        }
        layer.add(scale, forKey: "openScale")
        layer.add(corners, forKey: "openCorners")
        layer.add(opacity, forKey: "openOpacity")
        CATransaction.commit()

        window.alphaValue = 1.0

        addShimmerSweep(
            to: layer, bounds: container.bounds, cornerRadius: 16,
            delay: duration * 0.25,
            fadeInDuration: 0.15, sweepDuration: 0.5, fadeOutDuration: 0.3
        )
    }
}
