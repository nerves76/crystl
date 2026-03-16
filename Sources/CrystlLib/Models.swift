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

struct HookNotification: Codable, Equatable {
    let id: String
    let type: String              // "Stop", "PostToolUse", "SubagentStop", etc.
    let session_id: String?
    let cwd: String?
    let created: Double

    // Type-specific fields (optional, vary by type)
    let tool_name: String?        // PostToolUse
    let tool_response: String?    // PostToolUse (truncated)
    let message: String?          // Stop (last_assistant_message), Notification
    let title: String?            // Notification
    let notification_type: String? // Notification subtype
    let agent_id: String?         // SubagentStop
    let agent_type: String?       // SubagentStop
    let task_subject: String?     // TaskCompleted
    let teammate_name: String?    // TeammateIdle
    let team_name: String?        // TeammateIdle
    let reason: String?           // SessionEnd
    let error: String?            // PostToolUseFailure

    static func == (lhs: HookNotification, rhs: HookNotification) -> Bool {
        lhs.id == rhs.id
    }

    /// Human-readable headline for the notification panel
    var headline: String {
        switch type {
        case "Stop":              return "Claude finished"
        case "SessionEnd":        return "Session ended"
        case "PostToolUse":       return "Tool completed: \(tool_name ?? "Unknown")"
        case "PostToolUseFailure":return "Tool failed: \(tool_name ?? "Unknown")"
        case "SubagentStop":      return "Agent finished"
        case "TaskCompleted":     return "Task completed"
        case "TeammateIdle":      return "\(teammate_name ?? "Teammate") is idle"
        case "Notification":      return title ?? "Claude notification"
        default:                  return type
        }
    }

    /// Human-readable subtitle for the notification panel
    var subtitle: String {
        switch type {
        case "Stop":
            if let msg = message, !msg.isEmpty {
                return String(msg.prefix(80))
            }
            return "Session idle"
        case "SessionEnd":
            if let r = reason { return r }
            if let cwd = cwd { return (cwd as NSString).lastPathComponent }
            return ""
        case "PostToolUse":
            return tool_response.map { String($0.prefix(80)) } ?? ""
        case "PostToolUseFailure":
            return error.map { String($0.prefix(80)) } ?? "Unknown error"
        case "SubagentStop":
            return agent_type ?? "Subagent"
        case "TaskCompleted":
            return task_subject ?? ""
        case "TeammateIdle":
            return team_name ?? ""
        case "Notification":
            return message ?? ""
        default:
            return ""
        }
    }
}

struct EnabledNotifications: Codable {
    var Stop: Bool?
    var PostToolUse: Bool?
    var SubagentStop: Bool?
    var TaskCompleted: Bool?
    var Notification: Bool?
    var TeammateIdle: Bool?
    var SessionEnd: Bool?
}

struct BridgeSettings: Codable {
    var autoApproveMode: String
    var paused: Bool?
    var sessionOverrides: [String: String]?
    var enabledNotifications: EnabledNotifications?
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
    let notifications: [HookNotification]?
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
