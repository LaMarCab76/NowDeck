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
    /// Called once when the refresh token is rejected (`invalid_grant`). The stored tokens are
    /// already deleted at that point.
    private let onSessionExpired: @Sendable () async -> Void

    private var refreshTask: Task<OAuthTokens, Error>?

    init(
        clientID: String,
        credentials: CredentialStore,
        accounts: SpotifyAccountsClient,
        now: @escaping @Sendable () -> Date = { Date() },
        onSessionExpired: @escaping @Sendable () async -> Void = {}
    ) {
        self.clientID = clientID
        self.credentials = credentials
        self.accounts = accounts
        self.now = now
        self.onSessionExpired = onSessionExpired
    }

    /// A token that is valid for at least another 60 s.
    func validAccessToken() async throws -> String {
        if let refreshTask {
            return try await refreshTask.value.accessToken
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
            return try await refreshTask.value.accessToken
        }
        guard let tokens = try credentials.tokens() else { throw AuthError.notLoggedIn }
        if tokens.accessToken != rejectedToken {
            return tokens.accessToken
        }
        return try await refresh(from: tokens).accessToken
    }

    private func refresh(from tokens: OAuthTokens) async throws -> OAuthTokens {
        // No `await` between checking `refreshTask` (in the callers) and setting it here, so
        // no other call can slip in and start a second refresh.
        let task = Task { [clientID, credentials, accounts, now] in
            let response = try await accounts.refresh(refreshToken: tokens.refreshToken,
                                                      clientID: clientID)
            let newTokens = try response.tokens(receivedAt: now(), previous: tokens)
            try credentials.setTokens(newTokens)
            return newTokens
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            return try await task.value
        } catch AuthError.invalidGrant {
            try? credentials.removeTokens()
            await onSessionExpired()
            throw AuthError.invalidGrant
        }
    }
}
