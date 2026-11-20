import XCTest
@testable import Nowdeck

final class SpotifyAuthorizationTests: XCTestCase {
    // MARK: Authorize URL

    func testAuthorizeURLHasAllPKCEParameters() throws {
        let url = SpotifyAuthorization.authorizeURL(clientID: "abc123", codeChallenge: "CHALLENGE",
                                                    state: "STATE")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "accounts.spotify.com")
        XCTAssertEqual(components.path, "/authorize")

        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(items["client_id"], "abc123")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["redirect_uri"], "nowdeck://callback")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["code_challenge"], "CHALLENGE")
        XCTAssertEqual(items["state"], "STATE")
        XCTAssertEqual(items["scope"], """
            user-read-playback-state user-modify-playback-state user-read-currently-playing \
            playlist-read-private playlist-read-collaborative user-library-read \
            user-read-playback-position user-read-recently-played \
            playlist-modify-public playlist-modify-private
            """)
        XCTAssertEqual(items.count, 7)
    }

    func testAuthorizeURLPercentEncodesSpacesAndRedirect() {
        let url = SpotifyAuthorization.authorizeURL(clientID: "id", codeChallenge: "c", state: "s")
        let string = url.absoluteString
        XCTAssertTrue(string.contains("redirect_uri=nowdeck://callback")
                      || string.contains("redirect_uri=nowdeck%3A%2F%2Fcallback"))
        XCTAssertFalse(string.contains(" "))
    }

    // MARK: Callback

    func testCallbackReturnsCodeWhenStateMatches() throws {
        let url = URL(string: "nowdeck://callback?code=THE_CODE&state=xyz")!
        XCTAssertEqual(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz"),
                       "THE_CODE")
    }

    func testCallbackRejectsDifferentState() {
        let url = URL(string: "nowdeck://callback?code=THE_CODE&state=attacker")!
        XCTAssertThrowsError(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz")) {
            XCTAssertEqual($0 as? AuthError, .stateMismatch)
        }
    }

    func testCallbackRejectsMissingState() {
        let url = URL(string: "nowdeck://callback?code=THE_CODE")!
        XCTAssertThrowsError(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz")) {
            XCTAssertEqual($0 as? AuthError, .stateMismatch)
        }
    }

    /// The state is checked before anything else, even before the error parameter.
    func testCallbackChecksStateBeforeError() {
        let url = URL(string: "nowdeck://callback?error=access_denied&state=attacker")!
        XCTAssertThrowsError(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz")) {
            XCTAssertEqual($0 as? AuthError, .stateMismatch)
        }
    }

    func testCallbackWithAccessDenied() {
        let url = URL(string: "nowdeck://callback?error=access_denied&state=xyz")!
        XCTAssertThrowsError(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz")) {
            XCTAssertEqual($0 as? AuthError, .accessDenied)
        }
    }

    func testCallbackWithOtherError() {
        let url = URL(string: "nowdeck://callback?error=server_error&state=xyz")!
        XCTAssertThrowsError(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz")) {
            XCTAssertEqual($0 as? AuthError, .authorizationFailed("server_error"))
        }
    }

    func testCallbackWithoutCode() {
        let url = URL(string: "nowdeck://callback?state=xyz")!
        XCTAssertThrowsError(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz")) {
            XCTAssertEqual($0 as? AuthError, .invalidCallback)
        }
    }

    func testCallbackWithOtherScheme() {
        let url = URL(string: "https://evil.example/callback?code=c&state=xyz")!
        XCTAssertThrowsError(try SpotifyAuthorization.authorizationCode(from: url, expectedState: "xyz")) {
            XCTAssertEqual($0 as? AuthError, .invalidCallback)
        }
    }

    // MARK: Client ID

    func testClientIDValidation() {
        XCTAssertTrue(ClientID.isValid("0123456789abcdef0123456789abcdef"))
        XCTAssertTrue(ClientID.isValid("0123456789ABCDEF0123456789abcdef"))
        XCTAssertFalse(ClientID.isValid(""))
        XCTAssertFalse(ClientID.isValid("0123456789abcdef0123456789abcde"))   // 31
        XCTAssertFalse(ClientID.isValid("0123456789abcdef0123456789abcdef0")) // 33
        XCTAssertFalse(ClientID.isValid("0123456789abcdef0123456789abcde-"))
        XCTAssertFalse(ClientID.isValid("0123456789abcdef0123456789abcdé1"))  // not ASCII
        XCTAssertFalse(ClientID.isValid("0123456789abcdef 123456789abcdef"))
    }

    func testClientIDNormalizationStripsWhitespace() {
        XCTAssertEqual(ClientID.normalized("  0123456789abcdef\n0123456789abcdef \t"),
                       "0123456789abcdef0123456789abcdef")
    }
}
