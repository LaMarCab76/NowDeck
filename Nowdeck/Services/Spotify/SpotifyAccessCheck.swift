import Foundation

/// Checks, right after logging in, that the account can actually use the Web API.
///
/// In Development Mode a Spotify account that is not in the app's user list can log in but
/// gets `403` on every API call (developer.spotify.com, "Quota modes"). Catching it here lets
/// onboarding explain what to fix instead of failing later on the player.
///
/// It calls `GET /me/player` because its scope (`user-read-playback-state`) is one we request;
/// `GET /me` lists scopes we do not ask for. Milestone 2 replaces this with the full API client.
struct SpotifyAccessCheck: Sendable {
    enum Result: Equatable, Sendable {
        case ok
        /// `403`: not in the app's User Management list (or another account restriction).
        case forbidden
        /// `429`: too many requests or quota exceeded. Not fatal for logging in.
        case rateLimited
        case failed(status: Int)
    }

    static let endpoint = URL(string: "https://api.spotify.com/v1/me/player")!

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func run(accessToken: String) async throws -> Result {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AuthError.network(error.code)
        }
        guard let http = response as? HTTPURLResponse else { return .failed(status: 0) }

        switch http.statusCode {
        case 200, 204: return .ok
        case 403: return .forbidden
        case 429: return .rateLimited
        default: return .failed(status: http.statusCode)
        }
    }

    static let currentUserEndpoint = URL(string: "https://api.spotify.com/v1/me")!

    /// `GET /me`, only for the account's `id` (the reference lists scopes for the email and
    /// subscription fields, not for `id`). Used when asking for a new permission, to make
    /// sure the user logged in with the same account (`AppState.requestPlaylistEditing()`).
    func userID(accessToken: String) async throws -> String {
        var request = URLRequest(url: Self.currentUserEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AuthError.network(error.code)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let user = try? JSONDecoder().decode(CurrentUser.self, from: data),
              !user.id.isEmpty
        else { throw SpotifyAPIError.invalidResponse }
        return user.id
    }

    private struct CurrentUser: Decodable {
        let id: String
    }
}
