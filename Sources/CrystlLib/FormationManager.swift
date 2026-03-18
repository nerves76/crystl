// FormationManager.swift — Named collections of project directories
//
// Contains:
//   - FormationProject: A single project entry with path and optional display name
//   - Formation: A named group of projects that can be saved and restored
//   - FormationManager: Singleton that persists formations to ~/.config/crystl/formations.json
//     Supports CRUD, default formation for startup auto-load.

import Foundation

// MARK: - Data Model

/// A single project entry within a formation.
struct FormationProject: Codable {
    var path: String
    var name: String?
}

/// A named collection of projects that can be loaded together.
struct Formation: Codable {
    var id: UUID
    var name: String
    var projects: [FormationProject]
    var isDefault: Bool

    init(name: String, projects: [FormationProject], isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.projects = projects
        self.isDefault = isDefault
    }
}

// MARK: - Manager

class FormationManager {
    static let shared = FormationManager()

    private let configDir: String
    private let configPath: String
    private(set) var formations: [Formation] = []

    private init() {
        let home = NSHomeDirectory()
        configDir = home + "/.config/crystl"
        configPath = configDir + "/formations.json"
        load()
    }

    // MARK: - Load / Save

    func load() {
        if let data = FileManager.default.contents(atPath: configPath),
           let decoded = try? JSONDecoder().decode([Formation].self, from: data) {
            formations = decoded
        }
    }

    func save() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir) {
            try? fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(formations) {
            try? data.write(to: URL(fileURLWithPath: configPath))
        }
    }

    // MARK: - CRUD

    @discardableResult
    func add(name: String, projects: [FormationProject]) -> Formation {
        let formation = Formation(name: name, projects: projects)
        formations.append(formation)
        save()
        return formation
    }

    func remove(id: UUID) {
        formations.removeAll { $0.id == id }
        save()
    }

    func rename(id: UUID, newName: String) {
        guard let idx = formations.firstIndex(where: { $0.id == id }) else { return }
        formations[idx].name = newName
        save()
    }

    func setDefault(id: UUID) {
        for i in formations.indices {
            formations[i].isDefault = (formations[i].id == id)
        }
        save()
    }

    func clearDefault() {
        for i in formations.indices {
            formations[i].isDefault = false
        }
        save()
    }

    func defaultFormation() -> Formation? {
        formations.first(where: { $0.isDefault })
    }
}
