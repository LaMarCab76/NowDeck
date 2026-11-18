import XCTest
@testable import Nowdeck

/// Plays Spotify's consent page: reads the `state` from the authorize URL and answers with a
/// redirect built by `respond`.
@MainActor
final class FakeWebAuthenticator: WebAuthenticating {
    var respond: (_ state: String) throws -> URL
    private(set) var openedURL: URL?

    init(respond: @escaping (_ state: String) throws -> URL) {
        self.respond = respond
    }

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        openedURL = url
        let state = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "state" }?.value ?? ""
        return try respond(state)
    }

    static func approving(code: String = "CODE") -> FakeWebAuthenticator {
        FakeWebAuthenticator { state in URL(string: "nowdeck://callback?code=\(code)&state=\(state)")! }
    }
}

@MainActor
final class LoginFlowTests: XCTestCase {
    private let clientID = "0123456789abcdef0123456789abcdef"

    /// Routes token requests and the access check to separate answers. `GET /me` answers
    /// `user-a` for the stored token ("old") and `newUserID` for the new login's ("access").
    private func session(
        tokenStatus: Int = 200,
        tokenError: String = "invalid_client",
        playerStatus: Int = 204,
        newUserID: String = "user-a",
        grantedScope: String = "user-read-playback-state"
    ) -> (URLSession, StubRecorder) {
        StubURLProtocol.session { request in
            if request.url?.host == "accounts.spotify.com" {
                let body = tokenStatus == 200
                    ? tokenJSON(access: "access", refresh: "refresh", scope: grantedScope)
                    : tokenErrorJSON(tokenError)
                return (.stub(tokenStatus), body)
            }
            if request.url?.path == "/v1/me" {
                let isOld = request.value(forHTTPHeaderField: "Authorization") == "Bearer old"
                let id = isOld ? "user-a" : newUserID
                return (.stub(200), try JSONSerialization.data(withJSONObject: ["id": id]))
            }
            return (.stub(playerStatus), Data())
        }
    }

    private func makeAppState(
        credentials: CredentialStore = CredentialStore(store: InMemorySecureStore()),
        web: FakeWebAuthenticator = .approving(),
        tokenStatus: Int = 200,
        tokenError: String = "invalid_client",
        playerStatus: Int = 204,
        newUserID: String = "user-a",
        grantedScope: String = "user-read-playback-state"
    ) -> (AppState, CredentialStore, StubRecorder) {
        let (session, recorder) = session(tokenStatus: tokenStatus, tokenError: tokenError,
                                          playerStatus: playerStatus, newUserID: newUserID,
                                          grantedScope: grantedScope)
        let appState = AppState(credentials: credentials,
                                accounts: SpotifyAccountsClient(session: session),
                                accessCheck: SpotifyAccessCheck(session: session),
                                webAuthenticator: web,
                                preferences: AppPreferences(defaults: Self.freshDefaults()))
        return (appState, credentials, recorder)
    }

    private static func freshDefaults() -> UserDefaults {
        let name = "LoginFlowTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testFoldersAnswerLeadsToDoneThenPlayer() async throws {
        let (appState, _, _) = makeAppState()
        appState.showOnboardingStep(.clientID)
        await appState.connect(clientID: clientID)

        appState.answerPlaylistFolders(enabled: true)
        XCTAssertEqual(appState.route, .onboarding(.connected))
        XCTAssertTrue(appState.preferences.usesPlaylistFolders)
        XCTAssertTrue(appState.preferences.hasAnsweredPlaylistFolders)

        appState.finishOnboarding()
        XCTAssertEqual(appState.route, .player)
    }

    func testFoldersStepIsSkippedOnceAnswered() async throws {
        let (appState, _, _) = makeAppState()
        appState.preferences.answerPlaylistFolders(enabled: false)
        appState.showOnboardingStep(.clientID)

        await appState.connect(clientID: clientID)

        XCTAssertEqual(appState.route, .onboarding(.connected))
    }

    func testFinishOnboardingDoesNothingBeforeLoggingIn() {
        let (appState, _, _) = makeAppState()
        appState.finishOnboarding()
        XCTAssertEqual(appState.route, .onboarding(.welcome))
    }

    // MARK: SpotifyLogin

    func testLoginSendsVerifierMatchingTheChallenge() async throws {
        let web = FakeWebAuthenticator.approving(code: "THE_CODE")
        let (session, recorder) = session()
        let login = SpotifyLogin(webAuthenticator: web, accounts: SpotifyAccountsClient(session: session))

        let tokens = try await login.logIn(clientID: clientID)
        XCTAssertEqual(tokens.accessToken, "access")
        XCTAssertEqual(tokens.refreshToken, "refresh")

        let opened = try XCTUnwrap(web.openedURL)
        let challenge = URLComponents(url: opened, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "code_challenge" }?.value
        let fields = try XCTUnwrap(recorder.requests.first?.formFields)
        XCTAssertEqual(fields["code"], "THE_CODE")
        XCTAssertEqual(PKCE.challenge(for: try XCTUnwrap(fields["code_verifier"])), challenge)
    }

    func testLoginRejectsForgedState() async {
        let web = FakeWebAuthenticator { _ in URL(string: "nowdeck://callback?code=C&state=forged")! }
        let (session, recorder) = session()
        let login = SpotifyLogin(webAuthenticator: web, accounts: SpotifyAccountsClient(session: session))
        do {
            _ = try await login.logIn(clientID: clientID)
            XCTFail("Expected stateMismatch")
        } catch {
            XCTAssertEqual(error as? AuthError, .stateMismatch)
        }
        XCTAssertTrue(recorder.requests.isEmpty, "The code is never exchanged")
    }

    // MARK: AppState routing

    func testFirstLaunchStartsAtWelcome() {
        let (appState, _, _) = makeAppState()
        XCTAssertEqual(appState.route, .onboarding(.welcome))
    }

    func testStoredClientIDWithoutTokensStartsAtClientIDStep() throws {
        let credentials = CredentialStore(store: InMemorySecureStore())
        try credentials.setClientID(clientID)
        let (appState, _, _) = makeAppState(credentials: credentials)
        XCTAssertEqual(appState.route, .onboarding(.clientID))
        XCTAssertEqual(appState.savedClientID, clientID)
    }

    func testStoredSessionStartsAtPlayer() throws {
        let credentials = CredentialStore(store: InMemorySecureStore())
        try credentials.setClientID(clientID)
        try credentials.setTokens(OAuthTokens(accessToken: "a", refreshToken: "r",
                                              expiresAt: .distantFuture, scope: ""))
        let (appState, _, _) = makeAppState(credentials: credentials)
        XCTAssertEqual(appState.route, .player)
        XCTAssertNotNil(appState.tokenManager)
    }

    // MARK: Playlist editing (2026-11-18)

    private func loggedInAppState(scope: String, web: FakeWebAuthenticator = .approving(),
                                  playerStatus: Int = 204,
                                  newUserID: String = "user-a",
                                  grantedScope: String = "user-read-playback-state playlist-modify-public playlist-modify-private"
    ) throws -> (AppState, CredentialStore) {
        let credentials = CredentialStore(store: InMemorySecureStore())
        try credentials.setClientID(clientID)
        try credentials.setTokens(OAuthTokens(accessToken: "old", refreshToken: "r",
                                              expiresAt: .distantFuture, scope: scope))
        let (appState, _, _) = makeAppState(credentials: credentials, web: web,
                                            playerStatus: playerStatus, newUserID: newUserID,
                                            grantedScope: grantedScope)
        return (appState, credentials)
    }

    func testPlaylistEditingNeedsBothModifyScopes() throws {
        XCTAssertEqual(try loggedInAppState(scope: "user-read-playback-state").0
            .playlistEditingGrant(), .missing)
        XCTAssertEqual(try loggedInAppState(scope: "playlist-modify-public").0
            .playlistEditingGrant(), .missing)
        XCTAssertEqual(try loggedInAppState(
            scope: "user-read-playback-state playlist-modify-public playlist-modify-private")
            .0.playlistEditingGrant(), .granted)
    }

    func testEmptyGrantedScopesAreUnknown() throws {
        XCTAssertEqual(try loggedInAppState(scope: "").0.playlistEditingGrant(), .unknown)
    }

    func testRequestingPlaylistEditingFailsWhenSpotifyGrantsFewerScopes() async throws {
        let (appState, credentials) = try loggedInAppState(
            scope: "x", grantedScope: "user-read-playback-state playlist-modify-public")

        let failure = await appState.requestPlaylistEditing()

        XCTAssertEqual(failure, .denied)
        XCTAssertEqual(try credentials.tokens()?.accessToken, "old")
    }

    func testRequestingPlaylistEditingWithADifferentAccountIsRejected() async throws {
        let (appState, credentials) = try loggedInAppState(scope: "x", newUserID: "user-b")

        let failure = await appState.requestPlaylistEditing()

        XCTAssertEqual(failure, .differentAccount)
        XCTAssertEqual(try credentials.tokens()?.accessToken, "old")
    }

    func testRequestingPlaylistEditingStoresNewTokensAndStaysOnThePlayer() async throws {
        let (appState, credentials) = try loggedInAppState(scope: "user-read-playback-state")
        let manager = appState.tokenManager

        let failure = await appState.requestPlaylistEditing()

        XCTAssertNil(failure)
        XCTAssertEqual(try credentials.tokens()?.accessToken, "access")
        XCTAssertEqual(appState.route, .player)
        // Same token manager: it reads the Keychain on every request.
        XCTAssertTrue(appState.tokenManager === manager)
    }

    func testRequestingPlaylistEditingReportsACancelledLogin() async throws {
        let web = FakeWebAuthenticator { _ in throw AuthError.cancelled }
        let (appState, credentials) = try loggedInAppState(scope: "x", web: web)

        let failure = await appState.requestPlaylistEditing()

        XCTAssertEqual(failure, .cancelled)
        XCTAssertEqual(try credentials.tokens()?.accessToken, "old")
    }

    func testRequestingPlaylistEditingWithAnotherAccountKeepsTheOldSession() async throws {
        let (appState, credentials) = try loggedInAppState(scope: "x", playerStatus: 403)

        let failure = await appState.requestPlaylistEditing()

        XCTAssertEqual(failure, .notAllowlisted)
        XCTAssertEqual(try credentials.tokens()?.accessToken, "old")
    }

    // MARK: AppState.connect

    func testSuccessfulConnectStoresEverythingAndAsksAboutFolders() async throws {
        let (appState, credentials, _) = makeAppState()
        appState.showOnboardingStep(.clientID)

        await appState.connect(clientID: " \(clientID)\n")

        XCTAssertEqual(appState.route, .onboarding(.folders))
        XCTAssertNil(appState.notice)
        XCTAssertEqual(try credentials.clientID(), clientID)
        XCTAssertEqual(try credentials.tokens()?.refreshToken, "refresh")
    }

    func testForbiddenAccountShowsAllowlistNoticeAndStoresNoTokens() async throws {
        let (appState, credentials, _) = makeAppState(playerStatus: 403)
        appState.showOnboardingStep(.clientID)

        await appState.connect(clientID: clientID)

        XCTAssertEqual(appState.route, .onboarding(.clientID))
        XCTAssertEqual(appState.notice, .notAllowlisted)
        XCTAssertNil(try credentials.tokens())
        XCTAssertEqual(try credentials.clientID(), clientID, "The ID stays for the next try")
    }

    func testInvalidClientShowsNotice() async {
        let (appState, _, _) = makeAppState(tokenStatus: 400)
        appState.showOnboardingStep(.clientID)
        await appState.connect(clientID: clientID)
        XCTAssertEqual(appState.notice, .invalidClientID)
        XCTAssertEqual(appState.route, .onboarding(.clientID))
    }

    func testClosingTheLoginShowsAHint() async {
        let web = FakeWebAuthenticator { _ in throw AuthError.cancelled }
        let (appState, _, recorder) = makeAppState(web: web)
        await appState.connect(clientID: clientID)
        XCTAssertEqual(appState.notice, .loginClosed)
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testInvalidClientIDFormatDoesNothing() async {
        let (appState, credentials, recorder) = makeAppState()
        await appState.connect(clientID: "too-short")
        XCTAssertNil(try credentials.clientID())
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testExpiredSessionReturnsToClientIDWithNotice() async throws {
        let credentials = CredentialStore(store: InMemorySecureStore())
        try credentials.setClientID(clientID)
        try credentials.setTokens(OAuthTokens(accessToken: "a", refreshToken: "r",
                                              expiresAt: .distantPast, scope: ""))
        let (appState, _, _) = makeAppState(credentials: credentials, tokenStatus: 400,
                                            tokenError: "invalid_grant")
        XCTAssertEqual(appState.route, .player)

        // The player's first API call finds the token expired and the refresh is rejected.
        let manager = try XCTUnwrap(appState.tokenManager)
        _ = try? await manager.validAccessToken()

        XCTAssertEqual(appState.route, .onboarding(.clientID))
        XCTAssertEqual(appState.notice, .sessionExpired)
        XCTAssertEqual(appState.savedClientID, clientID)
        XCTAssertNil(try credentials.tokens())
    }

    /// After a reinstall the old credentials come back from the Keychain. If the Spotify app
    /// behind them is gone, the user goes back to the setup with an empty field.
    func testRejectedSavedClientIDReturnsToSetupWithoutPrefill() async throws {
        let credentials = CredentialStore(store: InMemorySecureStore())
        try credentials.setClientID(clientID)
        try credentials.setTokens(OAuthTokens(accessToken: "a", refreshToken: "r",
                                              expiresAt: .distantPast, scope: ""))
        let (appState, _, _) = makeAppState(credentials: credentials, tokenStatus: 400,
                                            tokenError: "invalid_client")
        XCTAssertEqual(appState.route, .player)

        let manager = try XCTUnwrap(appState.tokenManager)
        _ = try? await manager.validAccessToken()

        XCTAssertEqual(appState.route, .onboarding(.clientID))
        XCTAssertEqual(appState.notice, .savedClientIDRejected)
        XCTAssertNil(appState.savedClientID)
        XCTAssertNil(try credentials.clientID())
        XCTAssertNil(try credentials.tokens())
    }
}
