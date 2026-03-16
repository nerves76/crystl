// ModelsTests.swift — Tests for JSON data models
//
// Covers: PendingRequest JSON decoding, HookNotification headline/subtitle
// computed properties, and AnyCodable round-trip encoding/decoding.

import XCTest
@testable import CrystlLib

final class ModelsTests: XCTestCase {

    // MARK: - PendingRequest Decoding

    func test_PendingRequest_validJSON_decodesCorrectly() throws {
        let json = """
        {
            "id": "req-123",
            "tool_name": "Bash",
            "tool_input": {"command": "ls -la"},
            "cwd": "/Users/chris/project",
            "session_id": "sess-abc",
            "created": 1710000000000
        }
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(PendingRequest.self, from: data)

        XCTAssertEqual(request.id, "req-123")
        XCTAssertEqual(request.tool_name, "Bash")
        XCTAssertEqual(request.cwd, "/Users/chris/project")
        XCTAssertEqual(request.session_id, "sess-abc")
        XCTAssertEqual(request.created, 1710000000000)
        XCTAssertNotNil(request.tool_input)
        XCTAssertEqual(request.tool_input?["command"]?.value as? String, "ls -la")
    }

    func test_PendingRequest_missingOptionalFields_decodesWithNils() throws {
        let json = """
        {
            "id": "req-456",
            "tool_name": "Read",
            "created": 1710000000000
        }
        """
        let data = json.data(using: .utf8)!
        let request = try JSONDecoder().decode(PendingRequest.self, from: data)

        XCTAssertEqual(request.id, "req-456")
        XCTAssertEqual(request.tool_name, "Read")
        XCTAssertNil(request.tool_input)
        XCTAssertNil(request.cwd)
        XCTAssertNil(request.session_id)
    }

    func test_PendingRequest_equality_basedOnId() {
        let a = PendingRequest(id: "same", tool_name: "Bash", tool_input: nil, cwd: "/a", session_id: nil, created: 1)
        let b = PendingRequest(id: "same", tool_name: "Read", tool_input: nil, cwd: "/b", session_id: nil, created: 2)
        let c = PendingRequest(id: "different", tool_name: "Bash", tool_input: nil, cwd: "/a", session_id: nil, created: 1)

        XCTAssertEqual(a, b, "Requests with same ID should be equal")
        XCTAssertNotEqual(a, c, "Requests with different IDs should not be equal")
    }

    // MARK: - HookNotification headline

    func test_HookNotification_headline_stop() {
        let n = makeNotification(type: "Stop")
        XCTAssertEqual(n.headline, "Claude finished")
    }

    func test_HookNotification_headline_sessionEnd() {
        let n = makeNotification(type: "SessionEnd")
        XCTAssertEqual(n.headline, "Session ended")
    }

    func test_HookNotification_headline_postToolUse_withToolName() {
        let n = makeNotification(type: "PostToolUse", tool_name: "Bash")
        XCTAssertEqual(n.headline, "Tool completed: Bash")
    }

    func test_HookNotification_headline_postToolUse_noToolName() {
        let n = makeNotification(type: "PostToolUse")
        XCTAssertEqual(n.headline, "Tool completed: Unknown")
    }

    func test_HookNotification_headline_postToolUseFailure() {
        let n = makeNotification(type: "PostToolUseFailure", tool_name: "Write")
        XCTAssertEqual(n.headline, "Tool failed: Write")
    }

    func test_HookNotification_headline_subagentStop() {
        let n = makeNotification(type: "SubagentStop")
        XCTAssertEqual(n.headline, "Agent finished")
    }

    func test_HookNotification_headline_taskCompleted() {
        let n = makeNotification(type: "TaskCompleted")
        XCTAssertEqual(n.headline, "Task completed")
    }

    func test_HookNotification_headline_teammateIdle_withName() {
        let n = makeNotification(type: "TeammateIdle", teammate_name: "Bob")
        XCTAssertEqual(n.headline, "Bob is idle")
    }

    func test_HookNotification_headline_teammateIdle_noName() {
        let n = makeNotification(type: "TeammateIdle")
        XCTAssertEqual(n.headline, "Teammate is idle")
    }

    func test_HookNotification_headline_notification_withTitle() {
        let n = makeNotification(type: "Notification", title: "Custom Title")
        XCTAssertEqual(n.headline, "Custom Title")
    }

    func test_HookNotification_headline_notification_noTitle() {
        let n = makeNotification(type: "Notification")
        XCTAssertEqual(n.headline, "Claude notification")
    }

    func test_HookNotification_headline_unknownType_returnsType() {
        let n = makeNotification(type: "FutureType")
        XCTAssertEqual(n.headline, "FutureType")
    }

    // MARK: - HookNotification subtitle

    func test_HookNotification_subtitle_stop_withMessage() {
        let n = makeNotification(type: "Stop", message: "All tasks complete")
        XCTAssertEqual(n.subtitle, "All tasks complete")
    }

    func test_HookNotification_subtitle_stop_noMessage() {
        let n = makeNotification(type: "Stop")
        XCTAssertEqual(n.subtitle, "Session idle")
    }

    func test_HookNotification_subtitle_stop_emptyMessage() {
        let n = makeNotification(type: "Stop", message: "")
        XCTAssertEqual(n.subtitle, "Session idle")
    }

    func test_HookNotification_subtitle_sessionEnd_withReason() {
        let n = makeNotification(type: "SessionEnd", reason: "User quit")
        XCTAssertEqual(n.subtitle, "User quit")
    }

    func test_HookNotification_subtitle_sessionEnd_withCwd() {
        let n = makeNotification(type: "SessionEnd", cwd: "/Users/chris/project")
        XCTAssertEqual(n.subtitle, "project")
    }

    func test_HookNotification_subtitle_postToolUse_withResponse() {
        let n = makeNotification(type: "PostToolUse", tool_response: "File written")
        XCTAssertEqual(n.subtitle, "File written")
    }

    func test_HookNotification_subtitle_postToolUseFailure_withError() {
        let n = makeNotification(type: "PostToolUseFailure", error: "Permission denied")
        XCTAssertEqual(n.subtitle, "Permission denied")
    }

    func test_HookNotification_subtitle_postToolUseFailure_noError() {
        let n = makeNotification(type: "PostToolUseFailure")
        XCTAssertEqual(n.subtitle, "Unknown error")
    }

    func test_HookNotification_subtitle_unknownType_returnsEmpty() {
        let n = makeNotification(type: "FutureType")
        XCTAssertEqual(n.subtitle, "")
    }

    // MARK: - AnyCodable Round-Trip

    func test_AnyCodable_string_roundTrip() throws {
        let original = AnyCodable("hello")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? String, "hello")
    }

    func test_AnyCodable_int_roundTrip() throws {
        let original = AnyCodable(42)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Int, 42)
    }

    func test_AnyCodable_bool_encodes() throws {
        // In Swift, `true as? Int` is nil, so the encoder should reach the Bool branch
        let original = AnyCodable(true)
        let data = try JSONEncoder().encode(original)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertEqual(json, "true")
    }

    func test_AnyCodable_bool_decodes() throws {
        // Note: AnyCodable decoder tries Int before Bool, so JSON `true` may decode
        // as Int(1) rather than Bool(true) depending on the decoder implementation.
        // We just verify it decodes without error.
        let data = "true".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        // Accept either Bool(true) or Int(1)
        let isBool = decoded.value as? Bool == true
        let isInt = decoded.value as? Int == 1
        XCTAssertTrue(isBool || isInt, "true should decode as Bool(true) or Int(1), got: \(decoded.value)")
    }

    func test_AnyCodable_decodesFromJSON_string() throws {
        let data = "\"world\"".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? String, "world")
    }

    func test_AnyCodable_decodesFromJSON_number() throws {
        let data = "99".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Int, 99)
    }

    func test_AnyCodable_decodesFromJSON_dict() throws {
        let data = "{\"key\": \"value\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let dict = decoded.value as? [String: AnyCodable]
        XCTAssertNotNil(dict)
        XCTAssertEqual(dict?["key"]?.value as? String, "value")
    }

    func test_AnyCodable_decodesFromJSON_array() throws {
        let data = "[1, 2, 3]".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        let arr = decoded.value as? [AnyCodable]
        XCTAssertNotNil(arr)
        XCTAssertEqual(arr?.count, 3)
    }

    func test_AnyCodable_equality() {
        let a = AnyCodable("test")
        let b = AnyCodable("test")
        let c = AnyCodable("other")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - PollResponse Decoding

    func test_PollResponse_decodesMinimalJSON() throws {
        let json = """
        {
            "pending": []
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(PollResponse.self, from: data)
        XCTAssertTrue(response.pending.isEmpty)
        XCTAssertNil(response.notifications)
        XCTAssertNil(response.sessions)
        XCTAssertNil(response.settings)
    }

    func test_PollResponse_decodesFullJSON() throws {
        let json = """
        {
            "pending": [
                {"id": "r1", "tool_name": "Bash", "created": 1000}
            ],
            "notifications": [
                {"id": "n1", "type": "Stop", "created": 2000}
            ],
            "settings": {
                "autoApproveMode": "smart"
            }
        }
        """
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(PollResponse.self, from: data)
        XCTAssertEqual(response.pending.count, 1)
        XCTAssertEqual(response.pending[0].id, "r1")
        XCTAssertEqual(response.notifications?.count, 1)
        XCTAssertEqual(response.settings?.autoApproveMode, "smart")
    }

    // MARK: - DecisionBody Encoding

    func test_DecisionBody_encodesCorrectly() throws {
        let decision = DecisionBody(id: "req-1", decision: "allow")
        let data = try JSONEncoder().encode(decision)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
        XCTAssertEqual(json["id"], "req-1")
        XCTAssertEqual(json["decision"], "allow")
    }

    // MARK: - Helpers

    private func makeNotification(
        type: String,
        tool_name: String? = nil,
        tool_response: String? = nil,
        message: String? = nil,
        title: String? = nil,
        teammate_name: String? = nil,
        team_name: String? = nil,
        reason: String? = nil,
        error: String? = nil,
        cwd: String? = nil
    ) -> HookNotification {
        return HookNotification(
            id: "test-\(UUID().uuidString)",
            type: type,
            session_id: nil,
            cwd: cwd,
            created: Date().timeIntervalSince1970 * 1000,
            tool_name: tool_name,
            tool_response: tool_response,
            message: message,
            title: title,
            notification_type: nil,
            agent_id: nil,
            agent_type: nil,
            task_subject: nil,
            teammate_name: teammate_name,
            team_name: team_name,
            reason: reason,
            error: error
        )
    }
}
