// LicenseManager.swift — Offline license key validation via Ed25519
//
// Contains:
//   - LicensePayload: Codable struct (email, type, expires, issued)
//   - LicenseTier: enum (.free, .pro)
//   - LicenseState: enum (.unlicensed, .valid, .expired)
//   - Feature: gated feature list
//   - LicenseManager: singleton for validation, storage, and feature checks

import Foundation
import CryptoKit
import Security

// MARK: - Data Types

struct LicensePayload: Codable {
    let email: String
    let type: String        // "pro"
    let expires: String     // ISO date "2027-03-15" or "lifetime"
    let issued: String      // ISO date "2026-03-15"

    var isLifetime: Bool { expires == "lifetime" }

    var expiryDate: Date? {
        guard !isLifetime else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.timeZone = TimeZone(identifier: "UTC")
        return fmt.date(from: expires)
    }

    var isExpired: Bool {
        guard let date = expiryDate else { return false }
        return Date() > date
    }
}

enum LicenseTier {
    case free
    case pro
}

enum LicenseState {
    case unlicensed
    case valid(LicensePayload)
    case expired(LicensePayload)
}

enum LicenseError: Error, LocalizedError {
    case invalidFormat
    case invalidSignature
    case decodeFailed
    case expired(String)  // expiry date string

    var errorDescription: String? {
        switch self {
        case .invalidFormat:     return "Invalid license key format"
        case .invalidSignature:  return "License key signature is invalid"
        case .decodeFailed:      return "Could not decode license data"
        case .expired(let date): return "License expired on \(date)"
        }
    }
}

/// Features gated behind a Pro license.
enum Feature {
    case unlimitedGems
    case unlimitedShards
    case isolatedShards
    case splitView
    case apiKeys
    case mcpConfig
    case formations
}

// MARK: - License Manager

class LicenseManager {
    static let shared = LicenseManager()

    /// Embedded Ed25519 public key (Base64, 32 bytes).
    /// Generate with: swift Tools/generate-license.swift --generate-keys
    private static let publicKeyBase64 = "REPLACE_WITH_PUBLIC_KEY"

    private let keychainService = "com.crystl.license"
    private let keychainAccount = "licenseKey"

    /// Cached state — checked at launch and on activation.
    private(set) var currentState: LicenseState = .unlicensed

    /// Current tier derived from state.
    var tier: LicenseTier {
        if ProcessInfo.processInfo.environment["CRYSTL_DEV"] != nil { return .pro }
        if case .valid = currentState { return .pro }
        return .free
    }

    /// Email from the current license, if any.
    var email: String? {
        switch currentState {
        case .valid(let p), .expired(let p): return p.email
        case .unlicensed: return nil
        }
    }

    /// Payload from the current license, if any.
    var payload: LicensePayload? {
        switch currentState {
        case .valid(let p), .expired(let p): return p
        case .unlicensed: return nil
        }
    }

    private init() {
        currentState = validate()
    }

    // MARK: - Activation

    /// Activate a license key string. Stores in Keychain on success.
    @discardableResult
    func activate(_ keyString: String) -> Result<LicensePayload, LicenseError> {
        let trimmed = keyString.trimmingCharacters(in: .whitespacesAndNewlines)

        switch verifyKey(trimmed) {
        case .success(let payload):
            if payload.isExpired {
                currentState = .expired(payload)
                return .failure(.expired(payload.expires))
            }
            saveToKeychain(trimmed)
            currentState = .valid(payload)
            return .success(payload)

        case .failure(let error):
            return .failure(error)
        }
    }

    /// Remove the stored license.
    func deactivate() {
        deleteFromKeychain()
        currentState = .unlicensed
    }

    /// Re-validate the stored key (called at launch).
    @discardableResult
    func validate() -> LicenseState {
        guard let stored = readFromKeychain() else {
            currentState = .unlicensed
            return .unlicensed
        }

        switch verifyKey(stored) {
        case .success(let payload):
            if payload.isExpired {
                currentState = .expired(payload)
            } else {
                currentState = .valid(payload)
            }
        case .failure:
            currentState = .unlicensed
        }
        return currentState
    }

    // MARK: - Feature Gating

    func isFeatureAvailable(_ feature: Feature) -> Bool {
        return tier == .pro
    }

    /// Free tier gem limit.
    static let freeGemLimit = 5
    /// Free tier shard limit per gem.
    static let freeShardLimit = 3

    // MARK: - Key Verification

    private func verifyKey(_ keyString: String) -> Result<LicensePayload, LicenseError> {
        let parts = keyString.split(separator: ".", maxSplits: 1)
        guard parts.count == 2 else { return .failure(.invalidFormat) }

        guard let payloadData = Data(base64Encoded: String(parts[0])),
              let signatureData = Data(base64Encoded: String(parts[1])) else {
            return .failure(.invalidFormat)
        }

        // Verify signature
        guard Self.publicKeyBase64 != "REPLACE_WITH_PUBLIC_KEY" else {
            // Development mode — accept any well-formed key without signature check
            print("[Crystl] WARNING: License validation running in development mode — no signature verification")
            return decodePayload(payloadData)
        }

        guard let pubKeyData = Data(base64Encoded: Self.publicKeyBase64) else {
            return .failure(.invalidSignature)
        }

        do {
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: pubKeyData)
            let signature = try payloadData.withUnsafeBytes { rawPayload in
                try signatureData.withUnsafeBytes { rawSig in
                    // Verify the signature over the raw payload bytes
                    guard publicKey.isValidSignature(signatureData, for: payloadData) else {
                        throw LicenseError.invalidSignature
                    }
                    return true
                }
            }
            guard signature else { return .failure(.invalidSignature) }
        } catch {
            return .failure(.invalidSignature)
        }

        return decodePayload(payloadData)
    }

    private func decodePayload(_ data: Data) -> Result<LicensePayload, LicenseError> {
        do {
            let payload = try JSONDecoder().decode(LicensePayload.self, from: data)
            return .success(payload)
        } catch {
            return .failure(.decodeFailed)
        }
    }

    // MARK: - Keychain

    private func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func saveToKeychain(_ value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "Crystl License Key"
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
