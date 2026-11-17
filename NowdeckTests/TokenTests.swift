import XCTest
@testable import Nowdeck

final class TokenTests: XCTestCase {
    private let clientID = "0123456789abcdef0123456789abcdef"
    private let start = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Token model

    func testNeedsRefreshSixtySecondsBeforeExpiry() {
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r",
                                 expiresAt: start.addingTimeInterval(3600), scope: "")
        XCTAssertFalse(tokens.needsRefresh(now: start))
        XCTAssertFalse(tokens.needsRefresh(now: start.addingTimeInterval(3539)))
        XCTAssertTrue(tokens.needsRefresh(now: start.addingTimeInterval(3540)))
        XCTAssertTrue(tokens.needsRefresh(now: start.addingTimeInterval(4000)))
    }

    func testRefreshResponseWithoutRefreshTokenKeepsThePreviousOne() throws {
        let previous = OAuthTokens(accessToken: "old", refreshToken: "keep-me",
                                   expiresAt: start, scope: "s")
        let response = try JSONDecoder().decode(TokenResponse.self,
                                                from: tokenJSON(access: "new", refresh: nil))
        let tokens = try response.tokens(receivedAt: start, previous: previous)
        XCTAssertEqual(tokens.accessToken, "new")
        XCTAssertEqual(tokens.refreshToken, "keep-me")
        XCTAssertEqual(tokens.expiresAt, start.addingTimeInterval(3600))
    }

    func testFirstExchangeWithoutRefreshTokenFails() throws {
        let response = try JSONDecoder().decode(TokenResponse.self,
                                                from: tokenJSON(access: "a", refresh: nil))
        XCTAssertThrowsError(try response.tokens(receivedAt: start)) {
            XCTAssertEqual($0 as? AuthError, .invalidTokenResponse)
        }
    }

    // MARK: Credential store

    func testCredentialStoreRoundTrip() throws {
        let store = CredentialStore(store: InMemorySecureStore())
        XCTAssertNil(try store.clientID())
        XCTAssertNil(try store.tokens())

        try store.setClientID(clientID)
        let tokens = OAuthTokens(accessToken: "a", refreshToken: "r", expiresAt: start, scope: "s")
        try store.setTokens(tokens)
        XCTAssertEqual(try store.clientID(), clientID)
        XCTAssertEqual(try store.tokens(), tokens)

        try store.removeTokens()
        XCTAssertNil(try store.tokens())
        XCTAssertEqual(try store.clientID(), clientID, "Removing tokens keeps the Client ID")
    }

    /// The real Keychain, with a throwaway service name.
    func testKeychainStoreRoundTrip() throws {
        let keychain = KeychainStore(service: "nowdeck.tests.\(UUID().uuidString)")
        defer { try? keychain.removeAll() }

        XCTAssertNil(try keychain.data(forKey: "k"))
        try keychain.set(Data("one".utf8), forKey: "k")
        XCTAssertEqual(try keychain.data(forKey: "k"), Data("one".utf8))
        try keychain.set(Data("two".utf8), forKey: "k")
        XCTAssertEqual(try keychain.data(forKey: "k"), Data("two".utf8))
        try keychain.removeValue(forKey: "k")
        XCTAssertNil(try keychain.data(forKey: "k"))
        XCTAssertNoThrow(try keychain.removeValue(forKey: "k"), "Removing a missing item is fine")
    }

    // MARK: Accounts client

    func testCodeExchangeSendsPKCEFormFields() async throws {
        let (session, recorder) = StubURLProtocol.session { _ in
            (.stub(200), tokenJSON(access: "a", refresh: "r"))
        }
        let client = SpotifyAccountsClient(session: session)
        let response = try await client.exchangeCode("CODE", codeVerifier: "VERIFIER", clientID: clientID)
        XCTAssertEqual(response.accessToken, "a")

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url, SpotifyAuthorization.tokenURL)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "No client secret")
        XCTAssertEqual(request.formFields, [
            "grant_type": "authorization_code",
            "code": "CODE",
            "redirect_uri": "nowdeck://callback",
            "client_id": clientID,
            "code_verifier": "VERIFIER",
        ])
    }

    func testRefreshSendsRefreshTokenFields() async throws {
        let (session, recorder) = StubURLProtocol.session { _ in
            (.stub(200), tokenJSON(access: "a", refresh: nil))
        }
        _ = try await SpotifyAccountsClient(session: session).refresh(refreshToken: "R/T+1",
                                                                      clientID: clientID)
        XCTAssertEqual(recorder.requests.first?.formFields, [
            "grant_type": "refresh_token",
            "refresh_token": "R/T+1",
            "client_id": clientID,
        ])
    }

    func testTokenErrorsAreMapped() async {
        let cases: [(Int, Data, AuthError)] = [
            (400, tokenErrorJSON("invalid_grant"), .invalidGrant),
            (400, tokenErrorJSON("invalid_client"), .invalidClient),
            (400, tokenErrorJSON("invalid_request"), .tokenRequestFailed(status: 400, error: "invalid_request")),
            (503, Data(), .tokenRequestFailed(status: 503, error: nil)),
            (200, Data("not json".utf8), .invalidTokenResponse),
        ]
        for (status, body, expected) in cases {
            let (session, _) = StubURLProtocol.session { _ in (.stub(status), body) }
            do {
                _ = try await SpotifyAccountsClient(session: session).refresh(refreshToken: "r",
                                                                              clientID: clientID)
                XCTFail("Expected \(expected)")
            } catch {
                XCTAssertEqual(error as? AuthError, expected)
            }
        }
    }

    func testNetworkErrorsAreMapped() async {
        let (session, _) = StubURLProtocol.session { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await SpotifyAccountsClient(session: session).refresh(refreshToken: "r",
                                                                          clientID: clientID)
            XCTFail("Expected a network error")
        } catch {
            XCTAssertEqual(error as? AuthError, .network(.notConnectedToInternet))
        }
    }
}
