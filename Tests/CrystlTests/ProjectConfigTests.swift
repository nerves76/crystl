// ProjectConfigTests.swift — Tests for ProjectConfig and NSColor hex extensions
//
// Covers: NSColor(hex:) initialization, hexString round-trip conversion,
// and ProjectConfig Codable encode/decode with all fields and nil fields.

import XCTest
@testable import CrystlLib
import Cocoa

final class ProjectConfigTests: XCTestCase {

    // MARK: - NSColor(hex:) Init

    func test_NSColor_hex_valid6Char_createsColor() {
        let color = NSColor(hex: "FF0000")
        XCTAssertNotNil(color)
        let rgb = color?.usingColorSpace(.sRGB)
        XCTAssertNotNil(rgb)
        XCTAssertEqual(rgb!.redComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.greenComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.blueComponent, 0.0, accuracy: 0.01)
    }

    func test_NSColor_hex_withHashPrefix_createsColor() {
        let color = NSColor(hex: "#00FF00")
        XCTAssertNotNil(color)
        let rgb = color?.usingColorSpace(.sRGB)
        XCTAssertNotNil(rgb)
        XCTAssertEqual(rgb!.redComponent, 0.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.greenComponent, 1.0, accuracy: 0.01)
        XCTAssertEqual(rgb!.blueComponent, 0.0, accuracy: 0.01)
    }

    func test_NSColor_hex_invalidChars_returnsNil() {
        let color = NSColor(hex: "ZZZZZZ")
        XCTAssertNil(color)
    }

    func test_NSColor_hex_wrongLength_short_returnsNil() {
        let color = NSColor(hex: "FFF")
        XCTAssertNil(color)
    }

    func test_NSColor_hex_wrongLength_long_returnsNil() {
        let color = NSColor(hex: "FF00FF00")
        XCTAssertNil(color)
    }

    func test_NSColor_hex_emptyString_returnsNil() {
        let color = NSColor(hex: "")
        XCTAssertNil(color)
    }

    func test_NSColor_hex_whitespace_trimmed() {
        let color = NSColor(hex: "  #0000FF  ")
        XCTAssertNotNil(color)
        let rgb = color?.usingColorSpace(.sRGB)
        XCTAssertEqual(rgb!.blueComponent, 1.0, accuracy: 0.01)
    }

    func test_NSColor_hex_mixedCase_works() {
        let color = NSColor(hex: "aAbBcC")
        XCTAssertNotNil(color)
    }

    // MARK: - hexString Round-Trip

    func test_hexString_roundTrip_red() {
        let original = NSColor(hex: "#FF0000")!
        let hex = original.hexString
        XCTAssertEqual(hex, "#FF0000")
    }

    func test_hexString_roundTrip_green() {
        let original = NSColor(hex: "#00FF00")!
        let hex = original.hexString
        XCTAssertEqual(hex, "#00FF00")
    }

    func test_hexString_roundTrip_blue() {
        let original = NSColor(hex: "#0000FF")!
        let hex = original.hexString
        XCTAssertEqual(hex, "#0000FF")
    }

    func test_hexString_roundTrip_arbitrary() {
        let original = NSColor(hex: "#7AA2F7")!
        let hex = original.hexString
        XCTAssertEqual(hex, "#7AA2F7")
    }

    func test_hexString_roundTrip_black() {
        let original = NSColor(hex: "#000000")!
        let hex = original.hexString
        XCTAssertEqual(hex, "#000000")
    }

    func test_hexString_roundTrip_white() {
        let original = NSColor(hex: "#FFFFFF")!
        let hex = original.hexString
        XCTAssertEqual(hex, "#FFFFFF")
    }

    // MARK: - ProjectConfig Codable (All Fields)

    func test_ProjectConfig_encode_allFields() throws {
        let config = ProjectConfig(name: "MyProject", icon: "folder", color: "#FF5500")
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)

        XCTAssertEqual(decoded.name, "MyProject")
        XCTAssertEqual(decoded.icon, "folder")
        XCTAssertEqual(decoded.color, "#FF5500")
    }

    func test_ProjectConfig_encode_nilFields() throws {
        let config = ProjectConfig(name: nil, icon: nil, color: nil)
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)

        XCTAssertNil(decoded.name)
        XCTAssertNil(decoded.icon)
        XCTAssertNil(decoded.color)
    }

    func test_ProjectConfig_decode_partialJSON() throws {
        let json = """
        {"icon": "star"}
        """
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)

        XCTAssertNil(config.name)
        XCTAssertEqual(config.icon, "star")
        XCTAssertNil(config.color)
    }

    func test_ProjectConfig_decode_emptyJSON() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(ProjectConfig.self, from: data)

        XCTAssertNil(config.name)
        XCTAssertNil(config.icon)
        XCTAssertNil(config.color)
    }

    func test_ProjectConfig_roundTrip_preservesAllData() throws {
        let original = ProjectConfig(name: "Crystl", icon: "terminal", color: "#7AA2F7")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: data)

        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.icon, original.icon)
        XCTAssertEqual(decoded.color, original.color)
    }

    // MARK: - ProjectConfig File Operations

    func test_ProjectConfig_loadFromNonexistentDir_returnsNil() {
        let config = ProjectConfig.load(from: "/tmp/crystl-test-nonexistent-\(UUID().uuidString)")
        XCTAssertNil(config)
    }

    func test_ProjectConfig_saveAndLoad_roundTrip() throws {
        let tmpDir = NSTemporaryDirectory() + "crystl-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let original = ProjectConfig(name: "TestProj", icon: "zap", color: "#AABBCC")
        original.save(to: tmpDir)

        let loaded = ProjectConfig.load(from: tmpDir)
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.name, "TestProj")
        XCTAssertEqual(loaded?.icon, "zap")
        XCTAssertEqual(loaded?.color, "#AABBCC")

        // Verify .crystl directory was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir + "/.crystl"))
        // Verify .gitignore was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir + "/.crystl/.gitignore"))
    }
}
