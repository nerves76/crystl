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

struct BridgeSettings: Codable {
    var autoApproveMode: String
    var paused: Bool?
    var sessionOverrides: [String: String]?
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
