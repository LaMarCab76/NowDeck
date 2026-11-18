import Foundation

/// Fixed values of Spotify's Authorization Code with PKCE flow (docs/03-spotify-api.md).
enum SpotifyAuthorization {
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    /// Registered as a URL scheme in Info.plist and, by the user, in their Spotify app.
    static let callbackScheme = "nowdeck"
    static let redirectURI = "nowdeck://callback"

    /// Only what the app uses. Onboarding explains them in plain words.
    static let scopes = [
        "user-read-playback-state",
        "user-modify-playback-state",
        "user-read-currently-playing",
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-read-playback-position",
        // Since 2026-11-18: the last track heard, for the sample photo of Ajustes' background
        // preview. Sessions from before must log in again to grant it; until then the
        // preview uses what the app saw playing.
        "user-read-recently-played",
    ] + playlistEditingScopes

    /// Since 2026-11-18: adding the item that plays to the user's playlists
    /// (`POST /playlists/{id}/items`). Sessions from before do not have them; the sheet
    /// asks to log in again (`AppState.requestPlaylistEditing()`).
    static let playlistEditingScopes = [
        "playlist-modify-public",
        "playlist-modify-private",
    ]

    /// The URL that opens Spotify's login and consent page.
    static func authorizeURL(clientID: String, codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
        ]
        return components.url!
    }

    /// Reads the authorization code from the redirect, checking `state` first.
    ///
    /// The state check protects against a callback that this app did not start (CSRF): any
    /// mismatch is rejected before looking at the code.
    static func authorizationCode(from callbackURL: URL, expectedState: String) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              components.scheme == callbackScheme
        else { throw AuthError.invalidCallback }

        func value(_ name: String) -> String? {
            components.queryItems?.first { $0.name == name }?.value
        }

        guard let state = value("state"), state == expectedState else {
            throw AuthError.stateMismatch
        }
        if let error = value("error") {
            // The user tapped "Cancel" on Spotify's consent page.
            if error == "access_denied" { throw AuthError.accessDenied }
            throw AuthError.authorizationFailed(error)
        }
        guard let code = value("code"), !code.isEmpty else { throw AuthError.invalidCallback }
        return code
    }
}
