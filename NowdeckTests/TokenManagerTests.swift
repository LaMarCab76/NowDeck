import XCTest
@testable import Nowdeck

final class TokenManagerTests: XCTestCase {
    private let clientID = "0123456789abcdef0123456789abcdef"
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeManager(
        tokens: OAuthTokens?,
        onSessionRejected: @escaping @Sendable (AuthError) async -> Void = { _ in },
        handler: @escaping StubURLProtocol.Handler
    ) throws -> (TokenManager, CredentialStore, StubRecorder) {
        let credentials = CredentialStore(store: InMemorySecureStore())
        if let tokens { try credentials.setTokens(tokens) }
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let fixedNow = now
        let manager = TokenManager(clientID: clientID, credentials: credentials,
                                   accounts: SpotifyAccountsClient(session: session),
                                   now: { fixedNow }, onSessionRejected: onSessionRejected)
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

    func testInvalidGrantDeletesTokensAndReportsRejectedSession() async throws {
        try await assertRejectedCredentials(spotifyError: "invalid_grant", expected: .invalidGrant)
    }

    /// For example, the Spotify app was deleted in the dashboard after a reinstall.
    func testInvalidClientDeletesTokensAndReportsRejectedSession() async throws {
        try await assertRejectedCredentials(spotifyError: "invalid_client", expected: .invalidClient)
    }

    private func assertRejectedCredentials(spotifyError: String, expected: AuthError) async throws {
        let rejected = expectation(description: "session rejected callback")
        let (manager, credentials, _) = try makeManager(
            tokens: tokens(expiresIn: -10),
            onSessionRejected: { error in
                XCTAssertEqual(error, expected)
                rejected.fulfill()
            }
        ) { _ in
            (.stub(400), tokenErrorJSON(spotifyError))
        }

        do {
            _ = try await manager.validAccessToken()
            XCTFail("Expected \(expected)")
        } catch {
            XCTAssertEqual(error as? AuthError, expected)
        }
        await fulfillment(of: [rejected], timeout: 1)
        XCTAssertNil(try credentials.tokens())
    }

    // MARK: install(_:) (Agregar a una playlist, 2026-11-18)

    /// Starts a refresh whose answer waits for `release`, then installs new tokens while it is
    /// out.
    private func refreshRacingInstall(answer: @escaping @Sendable () -> (HTTPURLResponse, Data))
        async throws -> (CredentialStore, Result<String, Error>, Result<String, Error>, Bool) {
        let release = DispatchSemaphore(value: 0)
        let rejected = RejectionFlag()
        let (manager, credentials, recorder) = try makeManager(
            tokens: tokens(expiresIn: -10),
            onSessionRejected: { _ in rejected.set() }
        ) { _ in
            _ = release.wait(timeout: .now() + 5)
            return answer()
        }

        let refresh = Task { try await manager.validAccessToken() }
        while recorder.requests.isEmpty { await Task.yield() }
        // A second caller joins the same refresh before the new login lands.
        let joined = Task { try await manager.accessTokenAfterUnauthorized(rejectedToken: "old-access") }
        while await manager.joinedRefreshes < 1 { await Task.yield() }
        try await manager.install(OAuthTokens(accessToken: "upgraded", refreshToken: "r2",
                                              expiresAt: now.addingTimeInterval(3600),
                                              scope: "playlist-modify-private"))
        release.signal()
        let result = await refresh.result
        let joinedResult = await joined.result
        return (credentials, result, joinedResult, rejected.value)
    }

    func testARefreshThatStartedBeforeInstallDoesNotOverwriteTheNewTokens() async throws {
        let (credentials, result, joined, rejected) = try await refreshRacingInstall {
            (.stub(200), tokenJSON(access: "refreshed-old", refresh: "old-refresh"))
        }

        XCTAssertEqual(try credentials.tokens()?.accessToken, "upgraded")
        XCTAssertEqual(try result.get(), "upgraded")
        XCTAssertEqual(try joined.get(), "upgraded", "A caller that joined gets the same outcome")
        XCTAssertFalse(rejected)
    }

    func testAStaleRefreshRejectionDoesNotDeleteTheNewTokens() async throws {
        let (credentials, result, joined, rejected) = try await refreshRacingInstall {
            (.stub(400), tokenErrorJSON("invalid_grant"))
        }

        XCTAssertEqual(try credentials.tokens()?.accessToken, "upgraded")
        XCTAssertEqual(try result.get(), "upgraded")
        XCTAssertEqual(try joined.get(), "upgraded", "A caller that joined gets the same outcome")
        XCTAssertFalse(rejected, "The session that was rejected is no longer in use")
    }

    func testAFailedInstallLetsTheRefreshStoreItsTokens() async throws {
        let store = FailingWritesStore()
        let credentials = CredentialStore(store: store)
        try credentials.setTokens(tokens(expiresIn: -10))
        let release = DispatchSemaphore(value: 0)
        let (session, recorder) = StubURLProtocol.session { _ in
            _ = release.wait(timeout: .now() + 5)
            return (.stub(200), tokenJSON(access: "rotated", refresh: "rotated-refresh"))
        }
        let fixedNow = now
        let manager = TokenManager(clientID: clientID, credentials: credentials,
                                   accounts: SpotifyAccountsClient(session: session),
                                   now: { fixedNow })

        let refresh = Task { try await manager.validAccessToken() }
        while recorder.requests.isEmpty { await Task.yield() }
        store.failsWrites = true
        do {
            try await manager.install(OAuthTokens(accessToken: "upgraded", refreshToken: "r2",
                                                  expiresAt: .distantFuture, scope: ""))
            XCTFail("Expected the write to fail")
        } catch {}
        store.failsWrites = false
        release.signal()

        let token = try await refresh.value
        XCTAssertEqual(token, "rotated")
        XCTAssertEqual(try credentials.tokens()?.refreshToken, "rotated-refresh",
                       "The rotated refresh token must not be lost")
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

private final class RejectionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var isSet = false

    var value: Bool { lock.withLock { isSet } }

    func set() { lock.withLock { isSet = true } }
}

/// A store whose writes can be made to fail, like a Keychain error.
private final class FailingWritesStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private var failing = false

    var failsWrites: Bool {
        get { lock.withLock { failing } }
        set { lock.withLock { failing = newValue } }
    }

    func data(forKey key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func set(_ data: Data, forKey key: String) throws {
        try lock.withLock {
            if failing { throw KeychainError.unexpectedStatus(-1) }
            values[key] = data
        }
    }

    func removeValue(forKey key: String) throws {
        lock.withLock { values[key] = nil }
    }
}
