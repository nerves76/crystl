// MCPConfig.swift — MCP server catalog with per-project overrides
//
// Maintains a global catalog of MCP servers at ~/.config/crystl/mcps.json.
// Each server has an enabledByDefault flag. Projects can override to
// force-enable or force-disable specific servers, and can add project-only
// servers. The resolved set is synced to {project}/.mcp.json for Claude Code.

import Foundation

// MARK: - Data Models

/// An MCP server definition in the Crystl catalog
struct MCPServer: Codable {
    var command: String?
    var args: [String]?
    var url: String?
    var env: [String: String]?
    var enabledByDefault: Bool

    init(command: String? = nil, args: [String]? = nil, url: String? = nil,
         env: [String: String]? = nil, enabledByDefault: Bool = true) {
        self.command = command
        self.args = args
        self.url = url
        self.env = env
        self.enabledByDefault = enabledByDefault
    }
}

/// Per-project MCP overrides
struct ProjectMCPOverrides: Codable {
    /// Server names to force-enable (even if enabledByDefault is false)
    var enabled: [String]?
    /// Server names to force-disable (even if enabledByDefault is true)
    var disabled: [String]?
    /// Project-only servers (not in global catalog)
    var servers: [String: MCPServer]?
}

/// Top-level MCP catalog
struct MCPCatalog: Codable {
    var servers: [String: MCPServer]
    var projects: [String: ProjectMCPOverrides]

    init() {
        self.servers = [:]
        self.projects = [:]
    }
}

// MARK: - Config Manager

class MCPConfigManager {
    static let shared = MCPConfigManager()

    private let configDir: String
    private let configPath: String
    private(set) var catalog: MCPCatalog

    private init() {
        let home = NSHomeDirectory()
        configDir = home + "/.config/crystl"
        configPath = configDir + "/mcps.json"
        catalog = MCPCatalog()
        load()
    }

    // MARK: - Load / Save

    func load() {
        guard let data = FileManager.default.contents(atPath: configPath) else { return }
        if let decoded = try? JSONDecoder().decode(MCPCatalog.self, from: data) {
            catalog = decoded
        }
    }

    func save() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(catalog) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // MARK: - Server CRUD

    func addServer(name: String, server: MCPServer) {
        catalog.servers[name] = server
        save()
    }

    func removeServer(name: String) {
        catalog.servers.removeValue(forKey: name)
        // Clean up project references
        for (project, var overrides) in catalog.projects {
            overrides.enabled?.removeAll { $0 == name }
            overrides.disabled?.removeAll { $0 == name }
            cleanAndStore(overrides: overrides, project: project)
        }
        save()
    }

    func updateServer(name: String, server: MCPServer) {
        catalog.servers[name] = server
        save()
    }

    // MARK: - Per-Project Overrides

    func setProjectOverride(project: String, server: String, enabled: Bool) {
        var overrides = catalog.projects[project] ?? ProjectMCPOverrides()

        if enabled {
            if overrides.enabled == nil { overrides.enabled = [] }
            if !overrides.enabled!.contains(server) { overrides.enabled!.append(server) }
            overrides.disabled?.removeAll { $0 == server }
        } else {
            if overrides.disabled == nil { overrides.disabled = [] }
            if !overrides.disabled!.contains(server) { overrides.disabled!.append(server) }
            overrides.enabled?.removeAll { $0 == server }
        }

        cleanAndStore(overrides: overrides, project: project)
        save()
    }

    func clearProjectOverride(project: String, server: String) {
        guard var overrides = catalog.projects[project] else { return }
        overrides.enabled?.removeAll { $0 == server }
        overrides.disabled?.removeAll { $0 == server }
        cleanAndStore(overrides: overrides, project: project)
        save()
    }

    func addProjectServer(project: String, name: String, server: MCPServer) {
        var overrides = catalog.projects[project] ?? ProjectMCPOverrides()
        if overrides.servers == nil { overrides.servers = [:] }
        overrides.servers![name] = server
        catalog.projects[project] = overrides
        save()
    }

    func removeProjectServer(project: String, name: String) {
        guard var overrides = catalog.projects[project] else { return }
        overrides.servers?.removeValue(forKey: name)
        cleanAndStore(overrides: overrides, project: project)
        save()
    }

    // MARK: - Resolution

    enum OverrideState {
        case `default`, enabled, disabled
    }

    /// Returns the effective set of MCP servers for a given project path.
    func resolve(for project: String) -> [String: MCPServer] {
        let overrides = catalog.projects[project]
        var result: [String: MCPServer] = [:]

        for (name, server) in catalog.servers {
            var isEnabled = server.enabledByDefault

            if let overrides = overrides {
                if overrides.disabled?.contains(name) == true { isEnabled = false }
                if overrides.enabled?.contains(name) == true { isEnabled = true }
            }

            if isEnabled { result[name] = server }
        }

        // Merge project-only servers
        if let projectServers = overrides?.servers {
            for (name, server) in projectServers {
                result[name] = server
            }
        }

        return result
    }

    /// Returns the override state for a server in a project.
    func overrideState(project: String, server: String) -> OverrideState {
        guard let overrides = catalog.projects[project] else { return .default }
        if overrides.enabled?.contains(server) == true { return .enabled }
        if overrides.disabled?.contains(server) == true { return .disabled }
        return .default
    }

    /// Whether a server is effectively active for a project.
    func isActive(project: String, server: String) -> Bool {
        let state = overrideState(project: project, server: server)
        switch state {
        case .enabled: return true
        case .disabled: return false
        case .default: return catalog.servers[server]?.enabledByDefault ?? false
        }
    }

    // MARK: - Read Project Config

    /// Reads the project's existing .mcp.json and returns server names not in the catalog.
    /// These are "project-local" servers managed outside Crystl.
    func readProjectServers(_ project: String) -> [String: MCPServer] {
        let mcpPath = project + "/.mcp.json"
        guard let data = FileManager.default.contents(atPath: mcpPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = json["mcpServers"] as? [String: [String: Any]] else {
            return [:]
        }

        var result: [String: MCPServer] = [:]
        for (name, config) in servers {
            // Skip servers managed by Crystl's catalog
            if catalog.servers[name] != nil { continue }
            if catalog.projects[project]?.servers?[name] != nil { continue }

            result[name] = MCPServer(
                command: config["command"] as? String,
                args: config["args"] as? [String],
                url: config["url"] as? String,
                env: config["env"] as? [String: String],
                enabledByDefault: true
            )
        }
        return result
    }

    // MARK: - Sync to Claude Code

    /// Writes default MCP config to {project}/.mcp.json for Claude Code.
    /// Only writes if .mcp.json doesn't already exist (preserves existing configs).
    /// Use `forceSyncToProject` to overwrite.
    func syncToProject(_ project: String) {
        let mcpPath = project + "/.mcp.json"
        if FileManager.default.fileExists(atPath: mcpPath) { return }
        forceSyncToProject(project)
    }

    /// Writes the resolved MCP config to {project}/.mcp.json for Claude Code.
    /// Preserves any existing entries not managed by Crystl's catalog.
    func forceSyncToProject(_ project: String) {
        let resolved = resolve(for: project)
        let mcpPath = project + "/.mcp.json"
        let fm = FileManager.default

        // Read existing .mcp.json to preserve user-managed entries
        var existing: [String: Any] = [:]
        if let data = fm.contents(atPath: mcpPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let servers = json["mcpServers"] as? [String: Any] {
            // Keep entries that aren't in our catalog (user-managed)
            for (name, value) in servers {
                let inCatalog = catalog.servers[name] != nil
                let inProjectServers = catalog.projects[project]?.servers?[name] != nil
                if !inCatalog && !inProjectServers {
                    existing[name] = value
                }
            }
        }

        // Build merged output
        var mcpServers: [String: Any] = existing
        for (name, server) in resolved {
            var entry: [String: Any] = [:]
            if let command = server.command { entry["command"] = command }
            if let args = server.args { entry["args"] = args }
            if let url = server.url { entry["url"] = url }
            if let env = server.env, !env.isEmpty { entry["env"] = env }
            mcpServers[name] = entry
        }

        if mcpServers.isEmpty {
            try? fm.removeItem(atPath: mcpPath)
            return
        }

        let root: [String: Any] = ["mcpServers": mcpServers]
        if let data = try? JSONSerialization.data(
            withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: mcpPath))
        }
    }

    // MARK: - Import

    /// Imports MCP servers from ~/.claude/settings.json into the catalog.
    /// Skips servers that already exist. Returns the number of servers imported.
    @discardableResult
    func importFromClaude() -> Int {
        let path = NSHomeDirectory() + "/.claude/settings.json"
        guard let data = FileManager.default.contents(atPath: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mcpServers = json["mcpServers"] as? [String: [String: Any]] else {
            return 0
        }

        var count = 0
        for (name, config) in mcpServers {
            guard catalog.servers[name] == nil else { continue }

            let server = MCPServer(
                command: config["command"] as? String,
                args: config["args"] as? [String],
                url: config["url"] as? String,
                env: config["env"] as? [String: String],
                enabledByDefault: true
            )
            catalog.servers[name] = server
            count += 1
        }

        if count > 0 { save() }
        return count
    }

    // MARK: - Helpers

    /// Cleans empty arrays/dicts and removes project entry if fully empty.
    private func cleanAndStore(overrides: ProjectMCPOverrides, project: String) {
        var o = overrides
        if o.enabled?.isEmpty == true { o.enabled = nil }
        if o.disabled?.isEmpty == true { o.disabled = nil }
        if o.servers?.isEmpty == true { o.servers = nil }

        if o.enabled == nil && o.disabled == nil && o.servers == nil {
            catalog.projects.removeValue(forKey: project)
        } else {
            catalog.projects[project] = o
        }
    }
}
