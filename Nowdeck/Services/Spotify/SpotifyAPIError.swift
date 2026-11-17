import Foundation

/// Errors of the Web API client (`api.spotify.com`). Token errors (`AuthError`) are passed
/// through unchanged: `invalid_grant` and `invalid_client` already send the user back to
/// the setup through `TokenManager`.
enum SpotifyAPIError: Error, Equatable {
    /// `401` again after refreshing the token once.
    case unauthorized
    /// `403`. Spotify does not document a reason that tells the cases apart, so the app
    /// treats them together (docs/03-spotify-api.md, "Errores"):
    /// - the account is not (or no longer) in the app's *Users Management* list;
    /// - the app owner's Premium lapsed ("the app will stop working");
    /// - on playback commands, the user has no Premium.
    case forbidden(message: String?)
    /// `404`, for example a playlist the app may not read.
    case notFound(message: String?)
    /// `429`. `retryAfter` comes from the `Retry-After` header (seconds). `quotaExceeded` is
    /// true when the body says `"reason": "QUOTA_EXCEEDED"` (Development Mode quota).
    case rateLimited(retryAfter: TimeInterval, quotaExceeded: Bool)
    /// `5xx` after the automatic retries.
    case server(status: Int)
    /// Any other unexpected status.
    case http(status: Int, message: String?)
    /// No connection, timeout, etc.
    case network(URLError.Code)
    /// A success answer whose body we could not read.
    case invalidResponse
}

/// The documented error body: `{"error": {"status": 400, "message": "…", "reason": "…"}}`
/// (developer.spotify.com, "API calls"). `reason` is optional; the only documented value is
/// `QUOTA_EXCEEDED`.
struct SpotifyErrorBody: Decodable, Equatable {
    struct Detail: Decodable, Equatable {
        let status: Int?
        let message: String?
        let reason: String?
    }

    let error: Detail

    static let quotaExceededReason = "QUOTA_EXCEEDED"
}
