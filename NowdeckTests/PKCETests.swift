import XCTest
@testable import Nowdeck

final class PKCETests: XCTestCase {
    /// Test vector from RFC 7636, appendix B.
    func testChallengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(PKCE.challenge(for: verifier), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifierHasValidLengthAndCharacters() throws {
        let allowed = Set(PKCE.verifierAlphabet)
        for _ in 0..<50 {
            let pkce = try PKCE.generate()
            XCTAssertTrue(PKCE.verifierLengthRange.contains(pkce.verifier.count))
            XCTAssertTrue(pkce.verifier.allSatisfy(allowed.contains), pkce.verifier)
            XCTAssertEqual(pkce.challenge, PKCE.challenge(for: pkce.verifier))
        }
    }

    func testChallengeIsBase64URLWithoutPadding() throws {
        let challenge = try PKCE.generate().challenge
        // SHA-256 is 32 bytes → 43 base64url characters without padding.
        XCTAssertEqual(challenge.count, 43)
        XCTAssertFalse(challenge.contains("="))
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
    }

    func testVerifiersAreRandom() throws {
        let verifiers = try (0..<20).map { _ in try PKCE.generate().verifier }
        XCTAssertEqual(Set(verifiers).count, verifiers.count)
    }

    func testRandomStringHasRequestedLength() throws {
        XCTAssertEqual(try PKCE.randomString(length: 32).count, 32)
        XCTAssertEqual(try PKCE.randomString(length: 128).count, 128)
    }
}
