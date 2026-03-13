// CommandHistory.swift — Terminal command history logging
//
// Two components:
//   - ShellIntegration: Sets up ZDOTDIR to inject zsh preexec/precmd hooks
//     that emit OSC 7770 escape sequences marking command start/end.
//   - CommandHistoryLogger: Registers an OSC 7770 handler on a SwiftTerm
//     terminal, parses the sequences, and writes entries to .crystl-agent-history/history/
//     in the project directory. Format is agent-friendly markdown with
//     timestamps, exit codes, duration, and working directory.

import Foundation
import SwiftTerm

// MARK: - Shell Integration

/// Manages ZDOTDIR-based injection of zsh hooks for command history logging.
/// Creates a temporary directory with wrapper startup files that source the
/// user's real config then add Crystl's preexec/precmd hooks.
class ShellIntegration {
    static let shared = ShellIntegration()

    let zdotdir: String
    private let originalZdotdir: String

    private init() {
        originalZdotdir = ProcessInfo.processInfo.environment["ZDOTDIR"] ?? NSHomeDirectory()
        let tmpBase = NSTemporaryDirectory() + "crystl-shell-\(ProcessInfo.processInfo.processIdentifier)"
        zdotdir = tmpBase
        writeFiles()
    }

    private func writeFiles() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: zdotdir, withIntermediateDirectories: true)

        let integrationPath = zdotdir + "/crystl-integration.zsh"
        try? Self.integrationScript.write(toFile: integrationPath, atomically: true, encoding: .utf8)

        // Proxy .zshenv — source original then nothing extra
        let zshenv = "[[ -f \"\(originalZdotdir)/.zshenv\" ]] && source \"\(originalZdotdir)/.zshenv\"\n"
        try? zshenv.write(toFile: zdotdir + "/.zshenv", atomically: true, encoding: .utf8)

        // Proxy .zprofile
        let zprofile = "[[ -f \"\(originalZdotdir)/.zprofile\" ]] && source \"\(originalZdotdir)/.zprofile\"\n"
        try? zprofile.write(toFile: zdotdir + "/.zprofile", atomically: true, encoding: .utf8)

        // Proxy .zshrc — source original then add our integration
        let zshrc = """
        [[ -f "\(originalZdotdir)/.zshrc" ]] && source "\(originalZdotdir)/.zshrc"
        source "\(integrationPath)"
        """
        try? zshrc.write(toFile: zdotdir + "/.zshrc", atomically: true, encoding: .utf8)

        // Proxy .zlogin
        let zlogin = "[[ -f \"\(originalZdotdir)/.zlogin\" ]] && source \"\(originalZdotdir)/.zlogin\"\n"
        try? zlogin.write(toFile: zdotdir + "/.zlogin", atomically: true, encoding: .utf8)
    }

    /// Removes the temporary ZDOTDIR directory and its contents.
    /// Call this during app termination (e.g. applicationWillTerminate) to
    /// avoid leaking temp files at /tmp/crystl-shell-{pid}/.
    func cleanup() {
        try? FileManager.default.removeItem(atPath: zdotdir)
    }

    /// Returns the current process environment with ZDOTDIR overridden
    /// and terminal capability variables set so TUI apps (Claude Code, etc.)
    /// know they can use truecolor and Unicode box-drawing characters.
    func environment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["ZDOTDIR"] = zdotdir
        env["CRYSTL_SHELL_INTEGRATION"] = "1"
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Crystl"
        // Remove Claude Code session marker so terminals can launch fresh claude instances
        env.removeValue(forKey: "CLAUDECODE")
        return env.map { "\($0.key)=\($0.value)" }
    }

    // The zsh integration script. preexec emits OSC 7770 "start" with the
    // command text, cwd, and project root (git root or cwd). precmd emits
    // OSC 7770 "end" with exit code and duration. Data is base64-encoded
    // to avoid delimiter collisions.
    static let integrationScript = """
    # Crystl Shell Integration — command history logging
    # Injected via ZDOTDIR; do not edit manually.
    [[ -n "$__CRYSTL_INTEGRATED" ]] && return
    export __CRYSTL_INTEGRATED=1
    zmodload zsh/datetime 2>/dev/null

    __crystl_preexec() {
        local cmd="$1"
        __crystl_start_ts=$EPOCHSECONDS
        local project_dir
        project_dir=$(git rev-parse --show-toplevel 2>/dev/null) || project_dir="$PWD"
        local encoded_cmd encoded_cwd encoded_project
        encoded_cmd=$(printf '%s' "$cmd" | base64 | tr -d '\\n')
        encoded_cwd=$(printf '%s' "$PWD" | base64 | tr -d '\\n')
        encoded_project=$(printf '%s' "$project_dir" | base64 | tr -d '\\n')
        printf '\\033]7770;s|%s|%s|%s|%s\\007' "$__crystl_start_ts" "$encoded_cmd" "$encoded_cwd" "$encoded_project"
    }

    __crystl_precmd() {
        local exit_code=$?
        # Skip if no command was run (first prompt, empty enter)
        [[ -z "$__crystl_start_ts" ]] && return
        local end_ts=$EPOCHSECONDS
        local duration=$(( end_ts - __crystl_start_ts ))
        printf '\\033]7770;e|%s|%d|%d\\007' "$end_ts" "$exit_code" "$duration"
        unset __crystl_start_ts
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook preexec __crystl_preexec
    add-zsh-hook precmd __crystl_precmd

    """
}

// MARK: - Command History Logger

/// Tracks pending command state between start and end OSC events.
private struct PendingCommand {
    let command: String
    let cwd: String
    let projectDir: String
    let startTime: TimeInterval
}

/// Registers an OSC 7770 handler on a SwiftTerm terminal and writes
/// command history to .crystl-agent-history/history/ in the project directory.
class CommandHistoryLogger {
    private var pending: PendingCommand?
    private weak var terminalView: LocalProcessTerminalView?
    private let writeQueue = DispatchQueue(label: "crystl.history.write", qos: .utility)
    private var initializedDirs: Set<String> = []

    init(terminalView: LocalProcessTerminalView) {
        self.terminalView = terminalView
    }

    /// Call after the terminal has started to register the OSC handler.
    func registerHandler() {
        guard let tv = terminalView else { return }
        let terminal = tv.getTerminal()
        terminal.registerOscHandler(code: 7770) { [weak self] data in
            self?.handleOsc(data: data)
        }
    }

    private func handleOsc(data: ArraySlice<UInt8>) {
        guard let str = String(bytes: data, encoding: .utf8) else { return }
        // Dispatch all state access onto writeQueue for thread safety.
        // The OSC handler may be called from SwiftTerm's background thread,
        // so we serialize access to `pending` and `initializedDirs`.
        writeQueue.async { [weak self] in
            let parts = str.components(separatedBy: "|")
            guard let kind = parts.first else { return }

            if kind == "s" {
                self?.handleStart(parts: parts)
            } else if kind == "e" {
                self?.handleEnd(parts: parts)
            }
        }
    }

    // OSC 7770: s|timestamp|base64_cmd|base64_cwd|base64_project
    // Must be called on writeQueue.
    private func handleStart(parts: [String]) {
        guard parts.count >= 5 else { return }
        let ts = TimeInterval(parts[1]) ?? Date().timeIntervalSince1970
        let cmd = decodeBase64(parts[2])
        let cwd = decodeBase64(parts[3])
        let project = decodeBase64(parts[4])

        pending = PendingCommand(
            command: cmd,
            cwd: cwd,
            projectDir: project,
            startTime: ts
        )
    }

    // OSC 7770: e|timestamp|exit_code|duration
    // Must be called on writeQueue.
    private func handleEnd(parts: [String]) {
        guard parts.count >= 4, let pending = pending else { return }
        let exitCode = Int(parts[2]) ?? 0
        let duration = Int(parts[3]) ?? 0

        self.pending = nil

        writeEntry(
            command: pending.command,
            cwd: pending.cwd,
            projectDir: pending.projectDir,
            exitCode: exitCode,
            duration: duration,
            startTime: pending.startTime
        )
    }

    private func writeEntry(command: String, cwd: String, projectDir: String, exitCode: Int, duration: Int, startTime: TimeInterval) {
        let fm = FileManager.default
        let historyDir = projectDir + "/.crystl-agent-history/history"

        // Initialize directory structure on first write
        if !initializedDirs.contains(projectDir) {
            initializeDirectory(projectDir: projectDir)
            initializedDirs.insert(projectDir)
        }

        // Create history dir if needed
        if !fm.fileExists(atPath: historyDir) {
            try? fm.createDirectory(atPath: historyDir, withIntermediateDirectories: true)
        }

        // Format timestamp
        let date = Date(timeIntervalSince1970: startTime)
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        let dayString = dayFormatter.string(from: date)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm:ss"
        let timeString = timeFormatter.string(from: date)

        // Format the command for the header (collapse newlines)
        let headerCmd = command.replacingOccurrences(of: "\n", with: " \\\n  ")

        // Build the entry
        var entry = "\n## \(timeString) | \(headerCmd)\n"
        entry += "> CWD: \(cwd)\n"
        entry += "> Exit: \(exitCode) | Duration: \(formatDuration(duration))\n"

        // Append to daily file
        let filePath = historyDir + "/\(dayString).md"
        appendToFile(path: filePath, content: entry, date: dayString)
    }

    private func appendToFile(path: String, content: String, date: String) {
        let fm = FileManager.default
        if fm.fileExists(atPath: path) {
            // Append
            guard let handle = FileHandle(forWritingAtPath: path) else { return }
            handle.seekToEndOfFile()
            if let data = content.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            // Create with header
            let header = "# \(date) Terminal History\n"
            try? (header + content).write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func initializeDirectory(projectDir: String) {
        let fm = FileManager.default
        let crystlDir = projectDir + "/.crystl-agent-history"

        try? fm.createDirectory(atPath: crystlDir + "/history", withIntermediateDirectories: true)

        // .gitignore so history is never committed
        let gitignorePath = crystlDir + "/.gitignore"
        if !fm.fileExists(atPath: gitignorePath) {
            try? "*\n".write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        }

        // index.md — static reference for agents
        let indexPath = crystlDir + "/index.md"
        if !fm.fileExists(atPath: indexPath) {
            let index = """
            # .crystl-agent-history — Terminal Command History

            Command history logged by [Crystl](https://github.com/nerves76/crystl-app).
            Each command records timestamp, working directory, exit code, and duration.
            Useful for agents to understand what commands have been run in this project.

            ## Files
            - `history/YYYY-MM-DD.md` — Daily logs with timestamped command entries

            ## Search examples
            ```
            grep "swift build" .crystl-agent-history/history/
            grep "Exit: [^0]" .crystl-agent-history/history/
            grep "| npm" .crystl-agent-history/history/2026-03-12.md
            ```

            ## Entry format
            ```
            ## HH:MM:SS | command text
            > CWD: /absolute/path
            > Exit: CODE | Duration: Ns
            ```
            """
            try? index.write(toFile: indexPath, atomically: true, encoding: .utf8)
        }
    }

    private func decodeBase64(_ encoded: String) -> String {
        guard let data = Data(base64Encoded: encoded) else { return encoded }
        return String(data: data, encoding: .utf8) ?? encoded
    }

    private func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)m \(seconds % 60)s"
        } else {
            return "\(seconds / 3600)h \(seconds % 3600 / 60)m"
        }
    }
}
