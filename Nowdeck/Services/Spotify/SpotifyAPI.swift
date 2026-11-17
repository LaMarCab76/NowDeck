import Foundation

/// Where the API client gets its access tokens. `TokenManager` is the real one; tests use a
/// fake to count refreshes.
protocol AccessTokenProvider: Sendable {
    /// A token valid for at least another minute (refreshing first if needed).
    func validAccessToken() async throws -> String
    /// Called after a `401` with the token that was rejected.
    func accessTokenAfterUnauthorized(rejectedToken: String) async throws -> String
}

extension TokenManager: AccessTokenProvider {}

/// Client of the Spotify Web API (`https://api.spotify.com/v1`).
///
/// Every request goes through `send(_:)`, which:
/// - adds the bearer token from the token provider;
/// - on `401`, refreshes the token and retries **once**;
/// - on `429`, remembers `Retry-After` and fails fast (without touching the network) until it
///   passes, so no caller keeps hammering a rate-limited API;
/// - on `5xx`, retries GET requests twice with a growing wait. Commands (PUT/POST) are not
///   retried automatically: repeating "next" could skip two tracks.
///
/// The polling loop decides how long to wait after an error (`PollingPolicy`).
final class SpotifyAPI: Sendable {
    static let baseURL = URL(string: "https://api.spotify.com/v1")!

    struct Request: Sendable {
        var method: String = "GET"
        /// Path below `/v1`, starting with `/`.
        var path: String
        var query: [URLQueryItem] = []
        /// JSON body for commands (milestone 3).
        var body: Data?

        /// Only reads are retried after a server error.
        var isRetriableOnServerError: Bool { method == "GET" }
    }

    /// When no `Retry-After` comes with a `429`, wait this long.
    static let defaultRetryAfter: TimeInterval = 5
    /// Waits before the automatic retries of a GET after a `5xx`.
    static let serverRetryDelays: [TimeInterval] = [0.5, 1.5]

    private let tokens: any AccessTokenProvider
    private let session: URLSession
    private let baseURL: URL
    private let gate = RateLimitGate()
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let jitter: @Sendable () -> TimeInterval

    init(
        tokens: any AccessTokenProvider,
        session: URLSession = .shared,
        baseURL: URL = SpotifyAPI.baseURL,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        },
        jitter: @escaping @Sendable () -> TimeInterval = { Double.random(in: 0...0.25) }
    ) {
        self.tokens = tokens
        self.session = session
        self.baseURL = baseURL
        self.now = now
        self.sleep = sleep
        self.jitter = jitter
    }

    // MARK: Endpoints

    /// `GET /me/player?additional_types=episode` (scope `user-read-playback-state`).
    /// Returns `nil` on `204`: nothing is playing and there is no active device.
    func playbackState() async throws -> PlaybackState? {
        let request = Request(path: "/me/player",
                              query: [URLQueryItem(name: "additional_types", value: "episode")])
        let (data, status) = try await send(request)
        if status == 204 || data.isEmpty { return nil }
        return try Self.decode(PlaybackState.self, from: data)
    }

    /// `GET /playlists/{id}?fields=name`.
    ///
    /// Still available in Development Mode (verified 2026-11-17): since February 2026 it
    /// returns only metadata, without `items`, for playlists the user does not own or
    /// collaborate on, and `name` is part of that metadata. Spotify's own editorial and
    /// algorithmic playlists may answer `404` to Development Mode apps; callers then show the
    /// context type only.
    func playlistName(id: String) async throws -> String {
        let request = Request(path: "/playlists/\(Self.pathComponent(id))",
                              query: [URLQueryItem(name: "fields", value: "name")])
        let (data, _) = try await send(request)
        return try Self.decode(PlaylistName.self, from: data).name
    }

    // MARK: Transport

    /// Sends a request with the rules described on the type. Returns the body and the status
    /// (always 2xx).
    func send(_ request: Request) async throws -> (Data, Int) {
        try await gate.check(now: now())

        var token = try await tokens.validAccessToken()
        var refreshedAfterUnauthorized = false
        var serverRetries = 0

        while true {
            let (data, response) = try await perform(request, token: token)
            let status = response.statusCode

            switch status {
            case 200..<300:
                return (data, status)

            case 401 where !refreshedAfterUnauthorized:
                refreshedAfterUnauthorized = true
                token = try await tokens.accessTokenAfterUnauthorized(rejectedToken: token)

            case 401:
                throw SpotifyAPIError.unauthorized

            case 403:
                throw SpotifyAPIError.forbidden(message: Self.errorBody(data)?.error.message)

            case 404:
                throw SpotifyAPIError.notFound(message: Self.errorBody(data)?.error.message)

            case 429:
                let retryAfter = Self.retryAfter(response) ?? Self.defaultRetryAfter
                let quotaExceeded =
                    Self.errorBody(data)?.error.reason == SpotifyErrorBody.quotaExceededReason
                await gate.block(until: now().addingTimeInterval(retryAfter),
                                 quotaExceeded: quotaExceeded)
                throw SpotifyAPIError.rateLimited(retryAfter: retryAfter,
                                                  quotaExceeded: quotaExceeded)

            case 500...599:
                guard request.isRetriableOnServerError,
                      serverRetries < Self.serverRetryDelays.count
                else { throw SpotifyAPIError.server(status: status) }
                // Exponential wait plus jitter, so many clients don't retry in lockstep.
                try await sleep(Self.serverRetryDelays[serverRetries] + jitter())
                serverRetries += 1

            default:
                throw SpotifyAPIError.http(status: status,
                                           message: Self.errorBody(data)?.error.message)
            }
        }
    }

    private func perform(_ request: Request, token: String) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(string: baseURL.absoluteString + request.path) else {
            throw SpotifyAPIError.invalidResponse
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
            // `URLComponents` leaves `+` as is, and servers read it as a space: a search
            // for "AC+DC" would arrive as "AC DC".
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = request.method
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw SpotifyAPIError.invalidResponse
            }
            return (data, http)
        } catch let error as URLError {
            // A cancelled task (the poller stopped) is not a network problem.
            if error.code == .cancelled { throw CancellationError() }
            throw SpotifyAPIError.network(error.code)
        }
    }

    // MARK: Helpers

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try makeDecoder().decode(type, from: data)
        } catch {
            throw SpotifyAPIError.invalidResponse
        }
    }

    private static func errorBody(_ data: Data) -> SpotifyErrorBody? {
        try? JSONDecoder().decode(SpotifyErrorBody.self, from: data)
    }

    /// `Retry-After` in seconds ("API calls" and "Rate limits" pages).
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds >= 0
        else { return nil }
        return seconds
    }

    /// IDs come from Spotify URIs; percent-encode them anyway so a malformed one cannot
    /// change the path.
    static func pathComponent(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    private struct PlaylistName: Decodable {
        let name: String
    }
}

/// Remembers a `429` so the following calls fail fast until `Retry-After` passes.
private actor RateLimitGate {
    private var blockedUntil: Date?
    private var quotaExceeded = false

    func check(now: Date) throws {
        guard let blockedUntil, now < blockedUntil else { return }
        throw SpotifyAPIError.rateLimited(retryAfter: blockedUntil.timeIntervalSince(now),
                                          quotaExceeded: quotaExceeded)
    }

    func block(until date: Date, quotaExceeded: Bool) {
        blockedUntil = date
        self.quotaExceeded = quotaExceeded
    }
}
