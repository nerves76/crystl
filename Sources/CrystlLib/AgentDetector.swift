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

    /// Cache of parent→children mappings to avoid repeated sysctl calls.
    private var cachedChildren: [pid_t: [pid_t]] = [:]
    private var cacheTimestamp: Date = .distantPast
    private let cacheTTL: TimeInterval = 2.0

    func clearCache() {
        cachedChildren.removeAll()
        cacheTimestamp = .distantPast
    }

    /// Process name -> agent kind for direct binary matches.
    private static let knownBinaries: [(String, AgentKind)] = [
        ("claude", .claude),
        ("aider", .aider),
        ("codex", .codex),
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
    /// Returns the agent kind and its PID.
    func detect(shellPid: pid_t) -> (kind: AgentKind, pid: pid_t) {
        guard shellPid > 0 else { return (.none, 0) }

        let children = childPids(of: shellPid)
        for child in children {
            if let agent = identify(pid: child) { return (agent, child) }
            // Check grandchildren (agents launched via wrapper scripts)
            for grandchild in childPids(of: child) {
                if let agent = identify(pid: grandchild) { return (agent, grandchild) }
            }
        }
        return (.none, 0)
    }

    /// Get total CPU time (user + system) in nanoseconds for a process.
    func cpuTime(pid: pid_t) -> UInt64 {
        guard pid > 0 else { return 0 }
        var taskInfo = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, size)
        guard result == size else { return 0 }
        return taskInfo.pti_total_user + taskInfo.pti_total_system
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

    /// Get direct child PIDs of a process using sysctl KERN_PROC.
    /// Results are cached for `cacheTTL` seconds to avoid repeated sysctl calls
    /// when scanning multiple sessions in the same tick.
    private func childPids(of parentPid: pid_t) -> [pid_t] {
        // Return cached result if still fresh
        if Date().timeIntervalSince(cacheTimestamp) < cacheTTL, let cached = cachedChildren[parentPid] {
            return cached
        }

        // Cache is stale — rebuild the complete parent→children map
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size: Int = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let count = size / MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return [] }

        let actualCount = size / MemoryLayout<kinfo_proc>.stride

        // Build complete mapping
        cachedChildren.removeAll()
        for i in 0..<actualCount {
            let p = procs[i]
            let parent = p.kp_eproc.e_ppid
            let child = p.kp_proc.p_pid
            cachedChildren[parent, default: []].append(child)
        }
        cacheTimestamp = Date()
        return cachedChildren[parentPid] ?? []
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
/// Tracks CPU time to distinguish idle agents from working ones.
class AgentMonitor {
    private var timer: Timer?
    private let detector = AgentDetector()

    /// Sessions to monitor — update this when tabs are added/removed.
    var sessions: [TerminalSession] = []

    /// Called on main thread when a session's detected agent changes.
    var onAgentChanged: ((UUID, AgentKind) -> Void)?

    /// Called when an agent's working state changes (idle vs actively processing).
    var onAgentWorkingChanged: ((UUID, Bool) -> Void)?

    /// Tracks per-session agent PID and last CPU time for activity detection.
    private var agentPids: [UUID: pid_t] = [:]
    private var lastCPUTime: [UUID: UInt64] = [:]
    private var idleCount: [UUID: Int] = [:]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
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
        detector.clearCache()
        for session in sessions {
            let pid = session.terminalView.process?.shellPid ?? 0
            let (agent, agentPid) = detector.detect(shellPid: pid)

            if agent != session.detectedAgent {
                session.detectedAgent = agent
                agentPids[session.id] = agentPid
                lastCPUTime[session.id] = 0
                idleCount[session.id] = 0
                onAgentChanged?(session.id, agent)
            }

            // Track CPU activity for detected agents
            if agent.isAgent && agentPid > 0 {
                let cpu = detector.cpuTime(pid: agentPid)
                let prev = lastCPUTime[session.id] ?? 0
                let wasWorking = session.isAgentWorking

                if cpu > prev && prev > 0 {
                    // CPU time increased — agent is working
                    idleCount[session.id] = 0
                    if !wasWorking {
                        session.isAgentWorking = true
                        onAgentWorkingChanged?(session.id, true)
                    }
                } else if prev > 0 {
                    // CPU time unchanged — might be idle
                    let count = (idleCount[session.id] ?? 0) + 1
                    idleCount[session.id] = count
                    // Wait 3 consecutive idle scans before declaring idle
                    if count >= 3 && wasWorking {
                        session.isAgentWorking = false
                        onAgentWorkingChanged?(session.id, false)
                    }
                }
                lastCPUTime[session.id] = cpu
            } else {
                if session.isAgentWorking {
                    session.isAgentWorking = false
                    onAgentWorkingChanged?(session.id, false)
                }
                agentPids.removeValue(forKey: session.id)
                lastCPUTime.removeValue(forKey: session.id)
                idleCount.removeValue(forKey: session.id)
            }
        }
    }
}
