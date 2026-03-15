// APIKeyStore.swift — Secure API key storage via Keychain
//
// Stores API keys for AI providers (Anthropic, OpenAI, Google, etc.) in the
// macOS Keychain. Keys are injected as environment variables into terminal
// sessions so CLI tools (Claude Code, Codex, etc.) can use them automatically.

import Foundation
import Security

// MARK: - API Key Definitions

/// An API key slot: maps a display name to an environment variable.
struct APIKeySlot {
    let name: String       // e.g. "Anthropic"
    let envVar: String     // e.g. "ANTHROPIC_API_KEY"
    let placeholder: String // e.g. "sk-ant-..."
}

/// All supported API key slots.
let apiKeySlots: [APIKeySlot] = [
    APIKeySlot(name: "Anthropic",  envVar: "ANTHROPIC_API_KEY", placeholder: "sk-ant-..."),
    APIKeySlot(name: "OpenAI",     envVar: "OPENAI_API_KEY",    placeholder: "sk-..."),
    APIKeySlot(name: "Google AI",  envVar: "GEMINI_API_KEY",    placeholder: "AIza..."),
    APIKeySlot(name: "OpenRouter", envVar: "OPENROUTER_API_KEY", placeholder: "sk-or-..."),
]

// MARK: - Keychain Storage

class APIKeyStore {
    static let shared = APIKeyStore()
    private let service = "com.crystl.api-keys"

    /// Read a key from Keychain.
    func get(_ envVar: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: envVar,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Write a key to Keychain (or update if it exists).
    func set(_ envVar: String, value: String) {
        guard !value.isEmpty else { delete(envVar); return }
        let data = value.data(using: .utf8)!

        // Try update first
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: envVar,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)

        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Remove a key from Keychain.
    func delete(_ envVar: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: envVar,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Returns all stored keys as a dictionary of envVar → value.
    /// Only includes keys that are non-empty.
    func allKeys() -> [String: String] {
        var result: [String: String] = [:]
        for slot in apiKeySlots {
            if let val = get(slot.envVar), !val.isEmpty {
                result[slot.envVar] = val
            }
        }
        return result
    }
}
