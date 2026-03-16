// LicenseManagerTests.swift — Tests for license validation logic
//
// Covers: LicensePayload properties (isLifetime, isExpired, expiryDate),
// key format validation, dev mode bypass, and state transitions.
// NOTE: LicenseManager is a singleton with Keychain access, so we test
// the data types and verifyKey logic via the public activate() method.

import XCTest
@testable import CrystlLib

final class LicenseManagerTests: XCTestCase {

    // MARK: - Helper: Build a dev-mode key

    /// Creates a well-formed license key string (base64 payload . base64 signature).
    /// In dev mode (publicKeyBase64 == "REPLACE_WITH_PUBLIC_KEY"), signature is not checked.
    private func makeKey(
        email: String = "test@example.com",
        type: String = "pro",
        expires: String = "2099-12-31",
        issued: String = "2025-01-01"
    ) -> String {
        let payload = """
        {"email":"\(email)","type":"\(type)","expires":"\(expires)","issued":"\(issued)"}
        """
        let payloadB64 = Data(payload.utf8).base64EncodedString()
        let fakeSignature = Data("fake-signature-bytes".utf8).base64EncodedString()
        return "\(payloadB64).\(fakeSignature)"
    }

    // MARK: - LicensePayload.isLifetime

    func test_LicensePayload_isLifetime_true() throws {
        let payload = try decodeLicensePayload(expires: "lifetime")
        XCTAssertTrue(payload.isLifetime)
    }

    func test_LicensePayload_isLifetime_false() throws {
        let payload = try decodeLicensePayload(expires: "2099-12-31")
        XCTAssertFalse(payload.isLifetime)
    }

    // MARK: - LicensePayload.expiryDate

    func test_LicensePayload_expiryDate_validDate() throws {
        let payload = try decodeLicensePayload(expires: "2025-06-15")
        XCTAssertNotNil(payload.expiryDate)
        let cal = Calendar(identifier: .gregorian)
        let components = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: payload.expiryDate!)
        XCTAssertEqual(components.year, 2025)
        XCTAssertEqual(components.month, 6)
        XCTAssertEqual(components.day, 15)
    }

    func test_LicensePayload_expiryDate_lifetime_returnsNil() throws {
        let payload = try decodeLicensePayload(expires: "lifetime")
        XCTAssertNil(payload.expiryDate)
    }

    // MARK: - LicensePayload.isExpired

    func test_LicensePayload_isExpired_futureDate_notExpired() throws {
        let payload = try decodeLicensePayload(expires: "2099-12-31")
        XCTAssertFalse(payload.isExpired)
    }

    func test_LicensePayload_isExpired_pastDate_expired() throws {
        let payload = try decodeLicensePayload(expires: "2020-01-01")
        XCTAssertTrue(payload.isExpired)
    }

    func test_LicensePayload_isExpired_lifetime_neverExpires() throws {
        let payload = try decodeLicensePayload(expires: "lifetime")
        XCTAssertFalse(payload.isExpired)
    }

    // MARK: - Key Format Validation

    func test_verifyKey_missingDotSeparator_returnsInvalidFormat() {
        let manager = LicenseManager.shared
        let result = manager.activate("nodothere")
        if case .failure(let error) = result {
            XCTAssertEqual(error.errorDescription, "Invalid license key format")
        } else {
            XCTFail("Expected failure for key without dot separator")
        }
    }

    func test_verifyKey_emptyString_returnsInvalidFormat() {
        let manager = LicenseManager.shared
        let result = manager.activate("")
        if case .failure(let error) = result {
            XCTAssertEqual(error.errorDescription, "Invalid license key format")
        } else {
            XCTFail("Expected failure for empty key")
        }
    }

    func test_verifyKey_singlePart_returnsInvalidFormat() {
        let manager = LicenseManager.shared
        let result = manager.activate("onlyonepart")
        if case .failure(let error) = result {
            XCTAssertEqual(error.errorDescription, "Invalid license key format")
        } else {
            XCTFail("Expected failure for single-part key")
        }
    }

    func test_verifyKey_invalidBase64_returnsInvalidFormat() {
        let manager = LicenseManager.shared
        let result = manager.activate("not!valid!base64.also!not!valid")
        if case .failure(let error) = result {
            XCTAssertEqual(error.errorDescription, "Invalid license key format")
        } else {
            XCTFail("Expected failure for invalid base64")
        }
    }

    // MARK: - Dev Mode Bypass

    func test_devMode_wellFormedKey_acceptedWithoutSignatureCheck() {
        let manager = LicenseManager.shared
        let key = makeKey(expires: "2099-12-31")
        let result = manager.activate(key)

        switch result {
        case .success(let payload):
            XCTAssertEqual(payload.email, "test@example.com")
            XCTAssertEqual(payload.type, "pro")
        case .failure(let error):
            XCTFail("Dev mode should accept well-formed key, got: \(error)")
        }

        // Clean up
        manager.deactivate()
    }

    func test_devMode_malformedPayload_returnsDecodeFailed() {
        let manager = LicenseManager.shared
        // Valid base64 but not valid JSON
        let badPayload = Data("this is not json".utf8).base64EncodedString()
        let fakeSig = Data("sig".utf8).base64EncodedString()
        let result = manager.activate("\(badPayload).\(fakeSig)")

        if case .failure(let error) = result {
            XCTAssertEqual(error.errorDescription, "Could not decode license data")
        } else {
            XCTFail("Expected decodeFailed for non-JSON payload")
        }
    }

    // MARK: - State Transitions

    func test_stateTransition_unlicensed_to_valid() {
        let manager = LicenseManager.shared
        manager.deactivate()
        XCTAssertTrue(isUnlicensed(manager.currentState))

        let key = makeKey(expires: "2099-12-31")
        let result = manager.activate(key)

        if case .success = result {
            if case .valid(let p) = manager.currentState {
                XCTAssertEqual(p.email, "test@example.com")
            } else {
                XCTFail("Expected .valid state after activation")
            }
        } else {
            XCTFail("Activation should succeed")
        }

        manager.deactivate()
    }

    func test_stateTransition_unlicensed_to_expired() {
        let manager = LicenseManager.shared
        manager.deactivate()
        XCTAssertTrue(isUnlicensed(manager.currentState))

        let key = makeKey(expires: "2020-01-01")
        let result = manager.activate(key)

        if case .failure(let error) = result {
            // Should report expired
            if case .expired = error {
                // Good — expired error
            } else {
                XCTFail("Expected expired error, got: \(error)")
            }
        } else {
            XCTFail("Expired key should fail activation")
        }

        if case .expired(let p) = manager.currentState {
            XCTAssertEqual(p.expires, "2020-01-01")
        } else {
            XCTFail("Expected .expired state after expired key activation")
        }

        manager.deactivate()
    }

    func test_deactivate_resetsToUnlicensed() {
        let manager = LicenseManager.shared
        let key = makeKey(expires: "2099-12-31")
        _ = manager.activate(key)

        manager.deactivate()
        XCTAssertTrue(isUnlicensed(manager.currentState))
        XCTAssertNil(manager.email)
        XCTAssertNil(manager.payload)
    }

    // MARK: - Tier

    func test_tier_valid_returnsPro() {
        let manager = LicenseManager.shared
        let key = makeKey(expires: "2099-12-31")
        _ = manager.activate(key)
        XCTAssertEqual(manager.tier, .pro)
        manager.deactivate()
    }

    func test_tier_unlicensed_returnsFree() {
        let manager = LicenseManager.shared
        manager.deactivate()
        XCTAssertEqual(manager.tier, .free)
    }

    // MARK: - Feature Gating

    func test_featureAvailable_pro_returnsTrue() {
        let manager = LicenseManager.shared
        let key = makeKey(expires: "2099-12-31")
        _ = manager.activate(key)
        XCTAssertTrue(manager.isFeatureAvailable(.unlimitedGems))
        XCTAssertTrue(manager.isFeatureAvailable(.splitView))
        manager.deactivate()
    }

    func test_featureAvailable_free_returnsFalse() {
        let manager = LicenseManager.shared
        manager.deactivate()
        XCTAssertFalse(manager.isFeatureAvailable(.unlimitedGems))
        XCTAssertFalse(manager.isFeatureAvailable(.splitView))
    }

    // MARK: - Helpers

    private func isUnlicensed(_ state: LicenseState) -> Bool {
        if case .unlicensed = state { return true }
        return false
    }

    private func decodeLicensePayload(
        email: String = "test@example.com",
        type: String = "pro",
        expires: String = "2099-12-31",
        issued: String = "2025-01-01"
    ) throws -> LicensePayload {
        let json = """
        {"email":"\(email)","type":"\(type)","expires":"\(expires)","issued":"\(issued)"}
        """
        return try JSONDecoder().decode(LicensePayload.self, from: json.data(using: .utf8)!)
    }
}
