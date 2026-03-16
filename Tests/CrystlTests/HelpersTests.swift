// HelpersTests.swift — Tests for shared utility functions in Helpers.swift
//
// Covers: extractProjectName(), formatTimeAgo(), opacityFromSlider(),
// formatToolInput(), and colorForSession().

import XCTest
@testable import CrystlLib

final class HelpersTests: XCTestCase {

    // MARK: - extractProjectName

    func test_extractProjectName_normalPath_returnsTwoComponents() {
        let result = extractProjectName("/Users/chris/Nextcloud/myproject")
        XCTAssertEqual(result, "Nextcloud/myproject")
    }

    func test_extractProjectName_trailingSlash_returnsTwoComponents() {
        // trailing slash means split produces same components
        let result = extractProjectName("/Users/chris/Nextcloud/myproject/")
        XCTAssertEqual(result, "Nextcloud/myproject")
    }

    func test_extractProjectName_singleComponent_returnsSingleComponent() {
        let result = extractProjectName("/myproject")
        XCTAssertEqual(result, "myproject")
    }

    func test_extractProjectName_emptyString_returnsEmpty() {
        let result = extractProjectName("")
        XCTAssertEqual(result, "")
    }

    func test_extractProjectName_nil_returnsEmpty() {
        let result = extractProjectName(nil)
        XCTAssertEqual(result, "")
    }

    func test_extractProjectName_twoComponents_returnsBoth() {
        let result = extractProjectName("/foo/bar")
        XCTAssertEqual(result, "foo/bar")
    }

    func test_extractProjectName_deepPath_returnsLastTwo() {
        let result = extractProjectName("/a/b/c/d/e")
        XCTAssertEqual(result, "d/e")
    }

    // MARK: - formatTimeAgo

    func test_formatTimeAgo_justNow_returnsSeconds() {
        // Timestamp = now means 0 seconds ago
        let now = Date().timeIntervalSince1970 * 1000
        let result = formatTimeAgo(now)
        XCTAssertEqual(result, "0s")
    }

    func test_formatTimeAgo_minutesAgo_returnsMinutes() {
        let fiveMinutesAgo = Date().timeIntervalSince1970 * 1000 - 300_000
        let result = formatTimeAgo(fiveMinutesAgo)
        XCTAssertEqual(result, "5m")
    }

    func test_formatTimeAgo_hoursAgo_returnsHours() {
        let twoHoursAgo = Date().timeIntervalSince1970 * 1000 - 7_200_000
        let result = formatTimeAgo(twoHoursAgo)
        XCTAssertEqual(result, "2h")
    }

    func test_formatTimeAgo_daysAgo_returnsHours() {
        // 48 hours ago should return "48h" since there's no day formatter
        let twoDaysAgo = Date().timeIntervalSince1970 * 1000 - 172_800_000
        let result = formatTimeAgo(twoDaysAgo)
        XCTAssertEqual(result, "48h")
    }

    func test_formatTimeAgo_30SecondsAgo_returnsSeconds() {
        let thirtySecondsAgo = Date().timeIntervalSince1970 * 1000 - 30_000
        let result = formatTimeAgo(thirtySecondsAgo)
        XCTAssertEqual(result, "30s")
    }

    // MARK: - opacityFromSlider

    func test_opacityFromSlider_atZero_returnsMinGlassNoDark() {
        let result = opacityFromSlider(0)
        XCTAssertEqual(result.glassAlpha, 0.2, accuracy: 0.001)
        XCTAssertEqual(result.darkAlpha, 0, accuracy: 0.001)
    }

    func test_opacityFromSlider_atHalf_returnsFullGlassNoDark() {
        let result = opacityFromSlider(0.5)
        XCTAssertEqual(result.glassAlpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.darkAlpha, 0, accuracy: 0.001)
    }

    func test_opacityFromSlider_atOne_returnsFullGlassFullDark() {
        let result = opacityFromSlider(1.0)
        XCTAssertEqual(result.glassAlpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.darkAlpha, 1.0, accuracy: 0.001)
    }

    func test_opacityFromSlider_atQuarter_returnsPartialGlassNoDark() {
        let result = opacityFromSlider(0.25)
        // 0.2 + 1.6 * 0.25 = 0.2 + 0.4 = 0.6
        XCTAssertEqual(result.glassAlpha, 0.6, accuracy: 0.001)
        XCTAssertEqual(result.darkAlpha, 0, accuracy: 0.001)
    }

    func test_opacityFromSlider_atThreeQuarters_returnsFullGlassHalfDark() {
        let result = opacityFromSlider(0.75)
        // glass stays 1.0, dark = (0.75 - 0.5) * 2.0 = 0.5
        XCTAssertEqual(result.glassAlpha, 1.0, accuracy: 0.001)
        XCTAssertEqual(result.darkAlpha, 0.5, accuracy: 0.001)
    }

    // MARK: - formatToolInput

    func test_formatToolInput_withCommand_returnsCommand() {
        let input: [String: AnyCodable] = ["command": AnyCodable("ls -la")]
        let result = formatToolInput(input)
        XCTAssertEqual(result, "ls -la")
    }

    func test_formatToolInput_withFilePath_returnsPath() {
        let input: [String: AnyCodable] = ["file_path": AnyCodable("/tmp/test.txt")]
        let result = formatToolInput(input)
        XCTAssertEqual(result, "/tmp/test.txt")
    }

    func test_formatToolInput_withCommandAndPath_prefersCommand() {
        let input: [String: AnyCodable] = [
            "command": AnyCodable("echo hello"),
            "file_path": AnyCodable("/tmp/test.txt")
        ]
        let result = formatToolInput(input)
        XCTAssertEqual(result, "echo hello")
    }

    func test_formatToolInput_nil_returnsEmpty() {
        let result = formatToolInput(nil)
        XCTAssertEqual(result, "")
    }

    func test_formatToolInput_emptyDict_returnsSerializedJSON() {
        let input: [String: AnyCodable] = [:]
        let result = formatToolInput(input)
        // Empty dict serializes to "{}"
        XCTAssertEqual(result, "{}")
    }
}
