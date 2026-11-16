import XCTest
@testable import Nowdeck

final class TokenManagerTests: XCTestCase {
    private let clientID = "0123456789abcdef0123456789abcdef"
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeManager(
        tokens: OAuthTokens?,
        onSessionExpired: @escaping @Sendable () async -> Void = {},
        handler: @escaping StubURLProtocol.Handler
    ) throws -> (TokenManager, CredentialStore, StubRecorder) {
        let credentials = CredentialStore(store: InMemorySecureStore())
        if let tokens { try credentials.setTokens(tokens) }
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let fixedNow = now
        let manager = TokenManager(clientID: clientID, credentials: credentials,
                                   accounts: SpotifyAccountsClient(session: session),
                                   now: { fixedNow }, onSessionExpired: onSessionExpired)
        return (manager, credentials, recorder)
    }

    private func tokens(access: String = "old-access", expiresIn: TimeInterval) -> OAuthTokens {
        OAuthTokens(accessToken: access, refreshToken: "old-refresh",
                    expiresAt: now.addingTimeInterval(expiresIn), scope: "s")
    }

    func testValidTokenIsReturnedWithoutRequests() async throws {
        let (manager, _, recorder) = try makeManager(tokens: tokens(expiresIn: 600)) { _ in
            XCTFail("No request expected")
            return (.stub(500), Data())
        }
        let token = try await manager.validAccessToken()
        XCTAssertEqual(token, "old-access")
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testExpiringTokenIsRefreshedAndRotatedRefreshTokenIsStored() async throws {
        let (manager, credentials, recorder) = try makeManager(tokens: tokens(expiresIn: 30)) { _ in
            (.stub(200), tokenJSON(access: "new-access", refresh: "new-refresh"))
        }
        let token = try await manager.validAccessToken()
        XCTAssertEqual(token, "new-access")
        XCTAssertEqual(recorder.requests.count, 1)

        let stored = try XCTUnwrap(try credentials.tokens())
        XCTAssertEqual(stored.accessToken, "new-access")
        XCTAssertEqual(stored.refreshToken, "new-refresh", "A rotated refresh token replaces the old one")
        XCTAssertEqual(stored.expiresAt, now.addingTimeInterval(3600))
    }

    /// Many callers find the token expired at the same time: only one refresh request goes out.
    func testConcurrentCallersShareOneRefresh() async throws {
        let (manager, _, recorder) = try makeManager(tokens: tokens(expiresIn: -10)) { _ in
            // Slow answer, so every caller arrives while the refresh is in flight.
            Thread.sleep(forTimeInterval: 0.2)
            return (.stub(200), tokenJSON(access: "new-access", refresh: "new-refresh"))
        }

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<10 {
                group.addTask { try await manager.validAccessToken() }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        XCTAssertEqual(results, Array(repeating: "new-access", count: 10))
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testUnauthorizedRefreshesOnlyIfTokenIsStillTheRejectedOne() async throws {
        let (manager, _, recorder) = try makeManager(tokens: tokens(expiresIn: 600)) { _ in
            (.stub(200), tokenJSON(access: "new-access", refresh: nil))
        }
        // Another call already refreshed: the stored token is not the rejected one.
        let same = try await manager.accessTokenAfterUnauthorized(rejectedToken: "something-else")
        XCTAssertEqual(same, "old-access")
        XCTAssertTrue(recorder.requests.isEmpty)

        let refreshed = try await manager.accessTokenAfterUnauthorized(rejectedToken: "old-access")
        XCTAssertEqual(refreshed, "new-access")
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testInvalidGrantDeletesTokensAndReportsExpiredSession() async throws {
        let expired = expectation(description: "session expired callback")
        let (manager, credentials, _) = try makeManager(
            tokens: tokens(expiresIn: -10),
            onSessionExpired: { expired.fulfill() }
        ) { _ in
            (.stub(400), tokenErrorJSON("invalid_grant"))
        }

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected invalid_grant")
        } catch {
            XCTAssertEqual(error as? AuthError, .invalidGrant)
        }
        await fulfillment(of: [expired], timeout: 1)
        XCTAssertNil(try credentials.tokens())
    }

    func testNetworkFailureKeepsTokens() async throws {
        let (manager, credentials, _) = try makeManager(tokens: tokens(expiresIn: -10)) { _ in
            throw URLError(.timedOut)
        }
        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected a network error")
        } catch {
            XCTAssertEqual(error as? AuthError, .network(.timedOut))
        }
        XCTAssertNotNil(try credentials.tokens(), "A temporary failure must not log the user out")
    }

    func testNoTokensMeansNotLoggedIn() async throws {
        let (manager, _, _) = try makeManager(tokens: nil) { _ in (.stub(500), Data()) }
        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected notLoggedIn")
        } catch {
            XCTAssertEqual(error as? AuthError, .notLoggedIn)
        }
    }
}
