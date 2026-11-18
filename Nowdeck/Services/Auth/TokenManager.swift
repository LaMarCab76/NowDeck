import Foundation

/// Hands out a valid access token and refreshes it when needed.
///
/// It is an actor so that only one refresh runs at a time: if several API calls find the token
/// expired at once, the first one starts the refresh and the others wait for the same task
/// instead of sending their own requests. That matters because Spotify may rotate the refresh
/// token, and two parallel refreshes with the old one could invalidate each other.
actor TokenManager {
    private let clientID: String
    private let credentials: CredentialStore
    private let accounts: SpotifyAccountsClient
    private let now: @Sendable () -> Date
    /// Called once when Spotify rejects the stored credentials: the refresh token
    /// (`invalid_grant`) or the Client ID (`invalid_client`, for example after the app was
    /// deleted in the dashboard). The stored tokens are already deleted at that point.
    private let onSessionRejected: @Sendable (AuthError) async -> Void

    private var refreshTask: Task<OAuthTokens, Error>?
    /// Goes up when `install(_:)` replaces the session. A refresh that started before keeps
    /// its hands off the stored tokens: they belong to the new login.
    private var generation = 0

    init(
        clientID: String,
        credentials: CredentialStore,
        accounts: SpotifyAccountsClient,
        now: @escaping @Sendable () -> Date = { Date() },
        onSessionRejected: @escaping @Sendable (AuthError) async -> Void = { _ in }
    ) {
        self.clientID = clientID
        self.credentials = credentials
        self.accounts = accounts
        self.now = now
        self.onSessionRejected = onSessionRejected
    }

    /// A token that is valid for at least another 60 s.
    func validAccessToken() async throws -> String {
        if let refreshTask {
            return try await join(refreshTask).accessToken
        }
        guard let tokens = try credentials.tokens() else { throw AuthError.notLoggedIn }
        if !tokens.needsRefresh(now: now()) {
            return tokens.accessToken
        }
        return try await refresh(from: tokens).accessToken
    }

    /// Called after a `401`: refreshes unless another call already replaced the token that
    /// failed, so a burst of `401`s still produces a single refresh.
    func accessTokenAfterUnauthorized(rejectedToken: String) async throws -> String {
        if let refreshTask {
            return try await join(refreshTask).accessToken
        }
        guard let tokens = try credentials.tokens() else { throw AuthError.notLoggedIn }
        if tokens.accessToken != rejectedToken {
            return tokens.accessToken
        }
        return try await refresh(from: tokens).accessToken
    }

    /// Stores the tokens of a new login of the same session (Agregar a una playlist asks for
    /// more scopes). Goes through the actor so a refresh that is still out can neither
    /// overwrite them with the old scopes nor delete them if the old refresh token fails.
    ///
    /// The generation moves only once the write worked: if it fails, a refresh that is out
    /// still stores its (possibly rotated) tokens as usual.
    func install(_ tokens: OAuthTokens) throws {
        try credentials.setTokens(tokens)
        generation += 1
        refreshTask = nil
    }

    /// Callers that joined a refresh already running. Only read by tests, to know that a
    /// second caller is really waiting on the shared refresh.
    private(set) var joinedRefreshes = 0

    private func join(_ task: Task<OAuthTokens, Error>) async throws -> OAuthTokens {
        joinedRefreshes += 1
        return try await task.value
    }

    private func refresh(from tokens: OAuthTokens) async throws -> OAuthTokens {
        // No `await` between checking `refreshTask` (in the callers) and setting it here, so
        // no other call can slip in and start a second refresh.
        let startedIn = generation
        // The whole refresh, including deciding what to store, runs in this one task, so the
        // caller that started it and every caller that joined get the same outcome.
        let task = Task { try await self.completeRefresh(from: tokens, startedIn: startedIn) }
        refreshTask = task
        return try await task.value
    }

    private func completeRefresh(from tokens: OAuthTokens,
                                 startedIn: Int) async throws -> OAuthTokens {
        // After `install(_:)` another refresh may already be running: leave it alone.
        defer { if generation == startedIn { refreshTask = nil } }
        do {
            let response = try await accounts.refresh(refreshToken: tokens.refreshToken,
                                                      clientID: clientID)
            let newTokens = try response.tokens(receivedAt: now(), previous: tokens)
            guard generation == startedIn else { return try installedTokens(newTokens) }
            try credentials.setTokens(newTokens)
            return newTokens
        } catch let error as AuthError where error == .invalidGrant || error == .invalidClient {
            // The old refresh token was rejected, but a new login already replaced it.
            guard generation == startedIn else { return try installedTokens(nil) }
            // Retrying cannot fix these: the user has to configure the app again.
            try? credentials.removeTokens()
            await onSessionRejected(error)
            throw error
        }
    }

    /// What a refresh that lost the race to `install(_:)` returns: the installed tokens,
    /// never its own.
    private func installedTokens(_ fallback: OAuthTokens?) throws -> OAuthTokens {
        if let installed = try credentials.tokens() { return installed }
        if let fallback { return fallback }
        throw AuthError.notLoggedIn
    }
}
