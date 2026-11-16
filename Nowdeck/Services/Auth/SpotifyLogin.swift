import Foundation

/// The full login: opens Spotify's consent page with PKCE, checks the redirect and exchanges
/// the code for tokens.
@MainActor
struct SpotifyLogin {
    let webAuthenticator: any WebAuthenticating
    let accounts: SpotifyAccountsClient
    var now: @Sendable () -> Date = { Date() }

    func logIn(clientID: String) async throws -> OAuthTokens {
        let pkce = try PKCE.generate()
        let state = try PKCE.randomString(length: 32)
        let url = SpotifyAuthorization.authorizeURL(clientID: clientID,
                                                    codeChallenge: pkce.challenge,
                                                    state: state)

        let callbackURL = try await webAuthenticator.authenticate(
            url: url,
            callbackScheme: SpotifyAuthorization.callbackScheme
        )
        let code = try SpotifyAuthorization.authorizationCode(from: callbackURL,
                                                              expectedState: state)
        let response = try await accounts.exchangeCode(code, codeVerifier: pkce.verifier,
                                                       clientID: clientID)
        return try response.tokens(receivedAt: now())
    }
}
