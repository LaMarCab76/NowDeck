import Foundation

/// Errors of the login and token flow.
enum AuthError: Error, Equatable {
    /// The user closed the login sheet. Not shown as an error.
    case cancelled
    /// The user rejected the permissions on Spotify's consent page.
    case accessDenied
    /// The redirect's `state` does not match the one we sent.
    case stateMismatch
    /// The redirect has no code or is not ours.
    case invalidCallback
    /// The redirect carried another OAuth `error` value.
    case authorizationFailed(String)
    /// The login sheet could not be opened.
    case webSessionFailed
    /// The refresh token was revoked or expired (`invalid_grant`). The user must log in again.
    case invalidGrant
    /// Spotify does not know this Client ID (`invalid_client`).
    case invalidClient
    /// Any other answer from the token endpoint.
    case tokenRequestFailed(status: Int, error: String?)
    /// The token endpoint answered something we could not read.
    case invalidTokenResponse
    /// No connection, timeout, etc.
    case network(URLError.Code)
    /// There are no tokens stored: the user is not logged in.
    case notLoggedIn
}
