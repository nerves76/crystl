// Helpers.swift — Shared visual helpers, color palette, and utility functions
//
// Contains reusable components used by both the terminal window and
// notification panels: gradient glow effects, session color assignment,
// path formatting, and tool input display helpers.

import Cocoa

// ── Visual Helpers ──

/// Draws a vertical gradient glow from top (strong) to bottom (transparent).
/// Used at the top of approval panels for session-colored accents.
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

/// Creates a black rounded-rect mask image for use with NSVisualEffectView.maskImage.
/// This clips the frosted glass effect to rounded corners on notification panels.
func roundedMaskImage(size: NSSize, radius: CGFloat) -> NSImage {
    NSImage(size: size, flipped: false) { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSColor.black.setFill()
        path.fill()
        return true
    }
}

// ── Gray Slider Cell ──

/// NSSliderCell that draws a neutral gray track and knob instead of the system accent color.
class GraySliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let trackRect = NSRect(x: rect.origin.x, y: rect.midY - 1.5, width: rect.width, height: 3)
        NSColor(white: 1.0, alpha: 0.15).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 1.5, yRadius: 1.5).fill()

        // Filled portion
        let fraction = CGFloat((doubleValue - minValue) / (maxValue - minValue))
        let filledWidth = trackRect.width * fraction
        let filledRect = NSRect(x: trackRect.origin.x, y: trackRect.origin.y, width: filledWidth, height: trackRect.height)
        NSColor(white: 1.0, alpha: 0.4).setFill()
        NSBezierPath(roundedRect: filledRect, xRadius: 1.5, yRadius: 1.5).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let knobSize: CGFloat = 10
        let barRect = barRect(flipped: controlView?.isFlipped ?? false)
        let centerY = barRect.midY
        let r = NSRect(x: knobRect.midX - knobSize / 2, y: centerY - knobSize / 2, width: knobSize, height: knobSize)
        NSColor(white: 0.85, alpha: 1.0).setFill()
        NSBezierPath(ovalIn: r).fill()
    }
}

// ── Session Colors ──
// Each Claude Code session gets a unique muted color for visual identification
// across approval panels and tab accents.

let sessionColors: [NSColor] = [
    NSColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 1.0),  // soft blue
    NSColor(red: 0.72, green: 0.58, blue: 0.90, alpha: 1.0),  // lavender
    NSColor(red: 0.90, green: 0.62, blue: 0.55, alpha: 1.0),  // warm coral
    NSColor(red: 0.55, green: 0.82, blue: 0.72, alpha: 1.0),  // sage
    NSColor(red: 0.88, green: 0.75, blue: 0.55, alpha: 1.0),  // amber
    NSColor(red: 0.75, green: 0.55, blue: 0.72, alpha: 1.0),  // mauve
    NSColor(red: 0.55, green: 0.78, blue: 0.82, alpha: 1.0),  // frost
    NSColor(red: 0.85, green: 0.65, blue: 0.78, alpha: 1.0),  // rose
]

var sessionColorMap: [String: Int] = [:]
var nextColorIndex = 0

/// Returns a stable color for a given session ID. Colors are assigned
/// round-robin on first encounter and cached for the app lifetime.
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

// ── Utilities ──

/// Extracts a human-readable project name from a path by taking the last
/// two components (e.g., "/Users/chris/Nextcloud/myproject" -> "Nextcloud/myproject").
func extractProjectName(_ cwd: String?) -> String {
    guard let cwd = cwd, !cwd.isEmpty else { return "" }
    let parts = cwd.split(separator: "/")
    if parts.count >= 2 {
        return parts.suffix(2).joined(separator: "/")
    }
    return String(parts.last ?? "")
}

/// Extracts the most relevant field from a tool's input for display.
/// Checks common keys (command, file_path, pattern, query, prompt) in
/// priority order, falling back to a truncated JSON representation.
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

/// Formats a millisecond timestamp as a relative time string (e.g., "5s", "3m", "1h").
func formatTimeAgo(_ timestamp: Double) -> String {
    let seconds = Int((Date().timeIntervalSince1970 * 1000 - timestamp) / 1000)
    if seconds < 60 { return "\(seconds)s" }
    if seconds < 3600 { return "\(seconds / 60)m" }
    return "\(seconds / 3600)h"
}

// ── Glass Panel Factory ──

/// Creates a floating glass-style NSPanel with an NSVisualEffectView using
/// .hudWindow material, dark appearance, rounded corners, and a subtle border.
/// Returns both the panel and the glass view so callers can add subviews to the glass.
func makeGlassPanel(
    width: CGFloat,
    height: CGFloat,
    x: CGFloat,
    y: CGFloat,
    cornerRadius: CGFloat = 16,
    glassAlpha: CGFloat = -1,
    borderAlpha: CGFloat = 0.7,
    movable: Bool = false
) -> (NSPanel, NSVisualEffectView) {
    let panel = NSPanel(
        contentRect: NSRect(x: x, y: y, width: width, height: height),
        styleMask: [.nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isMovableByWindowBackground = movable
    panel.titlebarAppearsTransparent = true
    panel.titleVisibility = .hidden
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true

    let resolvedAlpha: CGFloat = {
        if glassAlpha >= 0 { return glassAlpha }
        let saved = UserDefaults.standard.double(forKey: "windowOpacity")
        return saved > 0.01 ? CGFloat(saved) : 0.85
    }()
    let glass = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    glass.material = .hudWindow
    glass.alphaValue = resolvedAlpha
    glass.blendingMode = .behindWindow
    glass.state = .active
    glass.appearance = NSAppearance(named: .darkAqua)
    glass.maskImage = roundedMaskImage(size: NSSize(width: width, height: height), radius: cornerRadius)
    glass.wantsLayer = true
    glass.layer?.borderWidth = 0.5
    glass.layer?.borderColor = NSColor(white: 1.0, alpha: borderAlpha).cgColor

    return (panel, glass)
}

// ── Shimmer Sweep Animation ──

/// Adds a prismatic shimmer gradient to the given layer and animates it sweeping
/// across after a delay. The shimmer fades in, sweeps left-to-right, then fades out
/// and removes itself. Used by both panel and window open animations.
func addShimmerSweep(
    to layer: CALayer,
    bounds: NSRect,
    cornerRadius: CGFloat,
    delay: CFTimeInterval,
    fadeInDuration: CFTimeInterval = 0.1,
    sweepDuration: CFTimeInterval = 0.35,
    fadeOutDuration: CFTimeInterval = 0.2
) {
    let shimmer = CAGradientLayer()
    shimmer.frame = bounds
    shimmer.type = .axial
    shimmer.startPoint = CGPoint(x: 0, y: 0.5)
    shimmer.endPoint = CGPoint(x: 1, y: 0.5)
    shimmer.colors = [
        NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.0).cgColor,
        NSColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 0.35).cgColor,
        NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.5).cgColor,
        NSColor(red: 0.5, green: 0.9, blue: 1.0, alpha: 0.35).cgColor,
        NSColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 0.0).cgColor,
    ]
    shimmer.locations = [0, 0.25, 0.5, 0.75, 1.0]
    shimmer.cornerRadius = cornerRadius
    shimmer.opacity = 0
    layer.addSublayer(shimmer)

    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        let shimmerIn = CABasicAnimation(keyPath: "opacity")
        shimmerIn.fromValue = 0
        shimmerIn.toValue = 1
        shimmerIn.duration = fadeInDuration

        let sweep = CABasicAnimation(keyPath: "startPoint.x")
        sweep.fromValue = -1.0
        sweep.toValue = 2.0
        sweep.duration = sweepDuration
        sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)

        let sweepEnd = CABasicAnimation(keyPath: "endPoint.x")
        sweepEnd.fromValue = 0.0
        sweepEnd.toValue = 3.0
        sweepEnd.duration = sweepDuration
        sweepEnd.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)

        let shimmerOut = CABasicAnimation(keyPath: "opacity")
        shimmerOut.fromValue = 1
        shimmerOut.toValue = 0
        shimmerOut.duration = fadeOutDuration
        shimmerOut.beginTime = CACurrentMediaTime() + (sweepDuration - fadeOutDuration)

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            shimmer.removeFromSuperlayer()
        }
        shimmer.opacity = 0
        shimmer.add(shimmerIn, forKey: "shimmerIn")
        shimmer.add(sweep, forKey: "shimmerSweep")
        shimmer.add(sweepEnd, forKey: "shimmerSweepEnd")
        shimmer.add(shimmerOut, forKey: "shimmerOut")
        CATransaction.commit()
    }
}
