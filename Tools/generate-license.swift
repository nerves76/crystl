#!/usr/bin/env swift
// generate-license.swift — Offline Ed25519 license key generator for Crystl
//
// Usage:
//   swift Tools/generate-license.swift --generate-keys
//     → Creates ~/.crystl-signing-key (private) and prints the public key Base64
//
//   swift Tools/generate-license.swift --email user@example.com --type pro --expires 2027-03-15
//   swift Tools/generate-license.swift --email user@example.com --type pro --lifetime
//     → Signs a license payload and prints the license key string
//
// The private key is stored at ~/.crystl-signing-key (never commit this file).
// The public key Base64 should be pasted into LicenseManager.swift.

import Foundation
import CryptoKit

let keyPath = NSHomeDirectory() + "/.crystl-signing-key"

// MARK: - Key Management

func loadOrCreatePrivateKey() -> Curve25519.Signing.PrivateKey {
    if let data = try? Data(contentsOf: URL(fileURLWithPath: keyPath)) {
        if let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: data) {
            return key
        }
    }
    let key = Curve25519.Signing.PrivateKey()
    try! key.rawRepresentation.write(to: URL(fileURLWithPath: keyPath))
    // Restrict permissions
    chmod(keyPath, 0o600)
    print("Created new signing key at \(keyPath)")
    return key
}

// MARK: - Argument Parsing

let args = CommandLine.arguments

if args.contains("--generate-keys") {
    let key = loadOrCreatePrivateKey()
    let pubBase64 = key.publicKey.rawRepresentation.base64EncodedString()
    print("\nPublic key (paste into LicenseManager.swift):")
    print(pubBase64)
    print("\nPrivate key stored at: \(keyPath)")
    exit(0)
}

// Parse license parameters
guard let emailIdx = args.firstIndex(of: "--email"), emailIdx + 1 < args.count else {
    print("Usage: swift generate-license.swift --email <email> --type <pro> [--expires <YYYY-MM-DD> | --lifetime]")
    exit(1)
}
let email = args[emailIdx + 1]

let type: String
if let typeIdx = args.firstIndex(of: "--type"), typeIdx + 1 < args.count {
    type = args[typeIdx + 1]
} else {
    type = "pro"
}

let expires: String
if args.contains("--lifetime") {
    expires = "lifetime"
} else if let expIdx = args.firstIndex(of: "--expires"), expIdx + 1 < args.count {
    expires = args[expIdx + 1]
} else {
    // Default: 1 year from today
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    fmt.timeZone = TimeZone(identifier: "UTC")
    expires = fmt.string(from: Calendar.current.date(byAdding: .year, value: 1, to: Date())!)
    print("No expiry specified, defaulting to 1 year: \(expires)")
}

let fmt = DateFormatter()
fmt.dateFormat = "yyyy-MM-dd"
fmt.timeZone = TimeZone(identifier: "UTC")
let issued = fmt.string(from: Date())

// MARK: - Generate License

let payload: [String: String] = [
    "email": email,
    "type": type,
    "expires": expires,
    "issued": issued,
]

let jsonData = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
let payloadBase64 = jsonData.base64EncodedString()

let key = loadOrCreatePrivateKey()
let signature = try! key.signature(for: jsonData)
let signatureBase64 = signature.rawRepresentation.base64EncodedString()

let licenseKey = "\(payloadBase64).\(signatureBase64)"

print("\nLicense Key:")
print(licenseKey)
print("\nPayload:")
print(String(data: jsonData, encoding: .utf8)!)
print("\nEmail: \(email)")
print("Type: \(type)")
print("Expires: \(expires)")
print("Issued: \(issued)")
