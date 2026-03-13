// ProjectConfig.swift — Per-project configuration stored in .crystl/project.json
//
// Each project can have a custom icon (Lucide icon name) and color (hex string).
// The config file lives at {projectDir}/.crystl/project.json and travels with
// the project, so it can be version-controlled if desired.

import Cocoa

// MARK: - Project Config Model

struct ProjectConfig: Codable {
    var icon: String?
    var color: String?

    /// Reads config from {projectDir}/.crystl/project.json.
    /// Returns nil if the file doesn't exist or can't be parsed.
    static func load(from projectDir: String) -> ProjectConfig? {
        let path = configPath(for: projectDir)
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(ProjectConfig.self, from: data)
    }

    /// Writes config to {projectDir}/.crystl/project.json.
    /// Creates the .crystl directory if it doesn't exist.
    func save(to projectDir: String) {
        let fm = FileManager.default
        let crystlDir = projectDir + "/.crystl"

        // Ensure .crystl directory exists
        if !fm.fileExists(atPath: crystlDir) {
            try? fm.createDirectory(atPath: crystlDir, withIntermediateDirectories: true)
            // Add .gitignore so .crystl contents aren't committed by default
            let gitignorePath = crystlDir + "/.gitignore"
            if !fm.fileExists(atPath: gitignorePath) {
                try? "*\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)
            }
        }

        let path = ProjectConfig.configPath(for: projectDir)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func configPath(for projectDir: String) -> String {
        return projectDir + "/.crystl/project.json"
    }
}

// MARK: - Color Conversion Helpers

extension NSColor {
    /// Creates an NSColor from a hex string like "#7AA2F7" or "7AA2F7".
    convenience init?(hex: String) {
        var hexStr = hex.trimmingCharacters(in: .whitespaces)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        guard hexStr.count == 6 else { return nil }

        var rgb: UInt64 = 0
        guard Scanner(string: hexStr).scanHexInt64(&rgb) else { return nil }

        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    /// Returns the color as a hex string like "#7AA2F7".
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) else { return "#FFFFFF" }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
