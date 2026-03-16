// StarterManager.swift — Manages starter markdown templates for new projects
//
// Contains:
//   - StarterFile: A single template with name, target filename, and content
//   - StarterManager: Singleton that persists templates to ~/.config/crystl/starters.json
//     Supports CRUD, migration from legacy DefaultClaudeMd/DefaultAgentsMd, and
//     sync-to-project (writes selected starters into project directories).

import Foundation

// MARK: - Data Model

/// A starter markdown template written to new projects.
struct StarterFile: Codable {
    var id: UUID
    var name: String            // Display name, e.g. "CLAUDE.md"
    var filename: String        // Target filename in project, e.g. "CLAUDE.md"
    var content: String         // Template content
    var enabledByDefault: Bool  // Pre-checked in New Project panel

    init(name: String, filename: String, content: String = "", enabledByDefault: Bool = true) {
        self.id = UUID()
        self.name = name
        self.filename = filename
        self.content = content
        self.enabledByDefault = enabledByDefault
    }
}

// MARK: - Manager

class StarterManager {
    static let shared = StarterManager()

    private let configDir: String
    private let configPath: String
    private(set) var starters: [StarterFile] = []

    private init() {
        let home = NSHomeDirectory()
        configDir = home + "/.config/crystl"
        configPath = configDir + "/starters.json"
        load()
    }

    // MARK: - Load / Save

    func load() {
        if let data = FileManager.default.contents(atPath: configPath),
           let decoded = try? JSONDecoder().decode([StarterFile].self, from: data) {
            starters = decoded
        } else {
            migrate()
        }
    }

    func save() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(starters) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }

    /// Migrates legacy default-claude.md and default-agents.md into starters.json.
    private func migrate() {
        starters = []
        let fm = FileManager.default

        let claudePath = configDir + "/default-claude.md"
        if let data = fm.contents(atPath: claudePath),
           let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            starters.append(StarterFile(name: "CLAUDE.md", filename: "CLAUDE.md", content: text))
        }

        let agentsPath = configDir + "/default-agents.md"
        if let data = fm.contents(atPath: agentsPath),
           let text = String(data: data, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            starters.append(StarterFile(name: "AGENTS.md", filename: "AGENTS.md", content: text))
        }

        if !starters.isEmpty {
            save()
        }
    }

    // MARK: - CRUD

    @discardableResult
    func add(name: String, filename: String, content: String = "", enabledByDefault: Bool = true) -> StarterFile {
        let starter = StarterFile(name: name, filename: filename, content: content, enabledByDefault: enabledByDefault)
        starters.append(starter)
        save()
        return starter
    }

    func update(_ starter: StarterFile) {
        guard let idx = starters.firstIndex(where: { $0.id == starter.id }) else { return }
        starters[idx] = starter
        save()
    }

    func remove(id: UUID) {
        starters.removeAll { $0.id == id }
        save()
    }

    /// Returns starters that have non-empty content.
    func nonEmptyStarters() -> [StarterFile] {
        starters.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Sync to Project

    /// Writes selected starters to {project}/{starter.filename} if file doesn't already exist.
    func syncToProject(_ project: String, starterIds: Set<UUID>) {
        let fm = FileManager.default
        for starter in starters where starterIds.contains(starter.id) {
            let path = project + "/" + starter.filename
            guard !fm.fileExists(atPath: path) else { continue }
            let content = starter.content
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            try? content.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    /// Syncs all starters where enabledByDefault is true (used for drag-drop project opens).
    func syncAllDefaultsToProject(_ project: String) {
        let defaultIds = Set(starters.filter { $0.enabledByDefault }.map { $0.id })
        syncToProject(project, starterIds: defaultIds)
    }
}
