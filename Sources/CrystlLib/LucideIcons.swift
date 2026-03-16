// LucideIcons.swift — Bundled Lucide icon library with SVG rendering
//
// Contains 120 Lucide icons as SVG element strings, plus a renderer that
// creates tinted NSImages from them. Icons are 24x24 viewBox with stroke-based
// rendering. The renderer substitutes the target color into the SVG and caches
// the resulting NSImage for performance.
//
// Lucide icons v0.577.0: https://lucide.dev — ISC License

import Cocoa

// MARK: - Icon Renderer

enum LucideIcons {

    /// All available icon names, sorted alphabetically.
    static var allNames: [String] { icons.keys.sorted() }

    /// Renders an icon as a tinted NSImage at the given size.
    /// Returns nil if the icon name is not found.
    static func render(name: String, size: CGFloat, color: NSColor) -> NSImage? {
        guard let elements = icons[name] else { return nil }

        let hex = color.hexString
        let cacheKey = "\(name)_\(Int(size))_\(hex)"
        if let cached = cache[cacheKey] { return cached }

        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" \
        viewBox="0 0 24 24" fill="none" stroke="\(hex)" \
        stroke-width="2" stroke-linecap="round" stroke-linejoin="round">\
        \(elements)</svg>
        """
        guard let data = svg.data(using: .utf8),
              let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: size, height: size)
        cache[cacheKey] = image
        return image
    }

    /// Clears the render cache (e.g. when colors change).
    static func clearCache() { cache.removeAll() }

    private static var cache: [String: NSImage] = [:]

    // Icon data is in LucideIconData.swift
}
