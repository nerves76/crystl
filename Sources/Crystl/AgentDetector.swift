// AgentDetector.swift — Detect AI agents running in terminal sessions
//
// Contains:
//   - AgentKind: enum of known agent types (Claude, Aider, Copilot, etc.)
//   - AgentDetector: inspects child processes of a shell PID for known agents
//   - AgentMonitor: periodic scanner that tracks agent state per session
//
// Uses Darwin proc_* APIs (proc_listchildpids, proc_name, proc_pidpath)
// to walk the process tree. No sandbox entitlement required.

import Cocoa
import Darwin

// MARK: - Agent Kind

/// Represents a detected AI agent running in a terminal session.
enum AgentKind: Equatable {
    case claude
    case aider
    case copilot
    case codex       // OpenAI Codex CLI
    case goose       // Block Goose
    case none

    var displayName: String {
        switch self {
        case .claude:   return "Claude"
        case .aider:    return "Aider"
        case .copilot:  return "Copilot"
        case .codex:    return "Codex"
        case .goose:    return "Goose"
        case .none:     return ""
        }
    }

    var isAgent: Bool { self != .none }
}

// MARK: - Agent Detector

/// Inspects the process tree below a shell PID to find known AI agents.
class AgentDetector {

    /// Process name -> agent kind for direct binary matches.
    private static let knownBinaries: [(String, AgentKind)] = [
        ("claude", .claude),
        ("aider", .aider),
        ("goose", .goose),
    ]

    /// Substrings to look for in full argv when the binary is ambiguous
    /// (e.g. "node", "python"). Checked against proc_pidpath + sysctl args.
    private static let argPatterns: [(String, AgentKind)] = [
        ("claude", .claude),
        ("aider", .aider),
        ("copilot", .copilot),
        ("codex", .codex),
        ("goose", .goose),
    ]

    /// Ambiguous binary names that require argument inspection.
    private static let ambiguousBinaries: Set<String> = ["node", "python", "python3", "npx", "deno", "bun"]

    // MARK: - Public API

    /// Detect which agent (if any) is running under the given shell PID.
    /// Checks direct children and grandchildren (depth 2).
    func detect(shellPid: pid_t) -> AgentKind {
        guard shellPid > 0 else { return .none }

        let children = childPids(of: shellPid)
        for child in children {
            if let agent = identify(pid: child) { return agent }
            // Check grandchildren (agents launched via wrapper scripts)
            for grandchild in childPids(of: child) {
                if let agent = identify(pid: grandchild) { return agent }
            }
        }
        return .none
    }

    // MARK: - Process Inspection

    private func identify(pid: pid_t) -> AgentKind? {
        guard let name = processName(pid: pid) else { return nil }

        // Direct binary name match
        for (binary, kind) in Self.knownBinaries {
            if name == binary { return kind }
        }

        // Ambiguous binary — inspect full path and arguments
        if Self.ambiguousBinaries.contains(name) {
            let fullPath = processPath(pid: pid) ?? ""
            let args = processArgs(pid: pid)
            let combined = fullPath + " " + args

            for (pattern, kind) in Self.argPatterns {
                if combined.localizedCaseInsensitiveContains(pattern) { return kind }
            }
        }

        return nil
    }

    /// Get direct child PIDs of a process.
    private func childPids(of parentPid: pid_t) -> [pid_t] {
        // First call with nil buffer to get count
        let count = proc_listchildpids(parentPid, nil, 0)
        guard count > 0 else { return [] }

        let bufferSize = Int(count) * MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: Int(count))
        let actual = proc_listchildpids(parentPid, &pids, Int32(bufferSize))
        guard actual > 0 else { return [] }

        let resultCount = Int(actual) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(resultCount)).filter { $0 > 0 }
    }

    /// Get the short process name (max 32 chars) via proc_name.
    private func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        let len = proc_name(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Get the full executable path via proc_pidpath.
    private func processPath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let len = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(cString: buffer)
    }

    /// Get the full argument string via sysctl KERN_PROCARGS2.
    private func processArgs(pid: pid_t) -> String {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return "" }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return "" }

        // KERN_PROCARGS2 layout: int32 argc, then exec_path\0, then argv strings\0-separated
        guard size > MemoryLayout<Int32>.size else { return "" }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }

        // Find the start of argv (skip past exec path null terminator and padding)
        var offset = MemoryLayout<Int32>.size
        // Skip exec path
        while offset < size && buffer[offset] != 0 { offset += 1 }
        // Skip null terminators between exec path and first arg
        while offset < size && buffer[offset] == 0 { offset += 1 }

        // Collect up to argc arguments
        var args: [String] = []
        var collected = 0
        while offset < size && collected < argc {
            var end = offset
            while end < size && buffer[end] != 0 { end += 1 }
            if end > offset {
                args.append(String(bytes: buffer[offset..<end], encoding: .utf8) ?? "")
            }
            collected += 1
            offset = end + 1
        }

        return args.joined(separator: " ")
    }
}

// MARK: - Agent Monitor

/// Periodically scans terminal sessions for running agents.
/// Fires `onAgentChanged` when a session's detected agent changes.
class AgentMonitor {
    private var timer: Timer?
    private let detector = AgentDetector()

    /// Sessions to monitor — update this when tabs are added/removed.
    var sessions: [TerminalSession] = []

    /// Called on main thread when a session's detected agent changes.
    var onAgentChanged: ((UUID, AgentKind) -> Void)?

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.scan()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Run a scan immediately (e.g. when terminal title changes).
    func scanNow() {
        scan()
    }

    private func scan() {
        for session in sessions {
            let pid = session.terminalView.process?.shellPid ?? 0
            let agent = detector.detect(shellPid: pid)
            if agent != session.detectedAgent {
                session.detectedAgent = agent
                onAgentChanged?(session.id, agent)
            }
        }
    }
}
