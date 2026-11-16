import Foundation

/// The tokens Nowdeck keeps in the Keychain.
struct OAuthTokens: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    /// Absolute expiry of `accessToken`, computed when the token arrives.
    var expiresAt: Date
    /// Space-separated scopes Spotify actually granted.
    var scope: String

    /// Whether the access token is expired or will be within `margin` seconds.
    /// Spotify access tokens last one hour; we refresh 60 s early (docs/03-spotify-api.md).
    func needsRefresh(now: Date, margin: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(margin) >= expiresAt
    }
}

/// The JSON body of a successful answer from `/api/token`.
struct TokenResponse: Decodable, Equatable, Sendable {
    let accessToken: String
    let tokenType: String
    let scope: String?
    let expiresIn: Int
    /// Present on the first exchange. On refresh it may come (and then replaces the stored
    /// one) or be missing (keep the stored one).
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }

    /// Builds the tokens to store. `previous` supplies the refresh token and scope when a
    /// refresh answer omits them.
    func tokens(receivedAt date: Date, previous: OAuthTokens? = nil) throws -> OAuthTokens {
        guard let refreshToken = refreshToken ?? previous?.refreshToken else {
            throw AuthError.invalidTokenResponse
        }
        return OAuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: date.addingTimeInterval(TimeInterval(expiresIn)),
            scope: scope ?? previous?.scope ?? ""
        )
    }
}

/// The JSON body of an error answer from `/api/token` (RFC 6749 §5.2).
struct TokenErrorResponse: Decodable, Sendable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
