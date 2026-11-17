import Foundation

enum LRCLIBError: Error, Equatable {
    /// `429` or `503`: wait at least `retryAfter` seconds before the next request.
    case rateLimited(retryAfter: TimeInterval)
    case server(status: Int)
    case network(URLError.Code)
    case invalidResponse
}

/// Talks to LRCLIB's `GET /api/get` (https://lrclib.net/docs, checked 2026-11-17).
///
/// - Identifies itself with a `User-Agent` (name, version and project page), as LRCLIB
///   requires: identified clients get about twice the rate limit of anonymous ones.
/// - `404` means "no lyrics" and returns `nil`; other failures throw `LRCLIBError`.
/// - It does not retry nor cache: `LyricsService` does that.
struct LRCLIBClient: Sendable {
    static let baseURL = URL(string: "https://lrclib.net")!

    /// Public page of the project for the User-Agent. Placeholder until the owner picks the
    /// GitHub user or organization (docs/01-producto.md, "Decisiones pendientes"). Do not put
    /// personal data here: LRCLIB receives it with every request.
    static let projectURL = "https://github.com/<usuario>/Nowdeck"

    let session: URLSession
    let userAgent: String

    init(session: URLSession = .shared, userAgent: String = LRCLIBClient.defaultUserAgent) {
        self.session = session
        self.userAgent = userAgent
    }

    /// `Nowdeck/0.1.0 (https://github.com/<usuario>/Nowdeck)`.
    static var defaultUserAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return userAgent(version: version ?? "0")
    }

    static func userAgent(version: String) -> String {
        "Nowdeck/\(version) (\(projectURL))"
    }

    /// The record for the track, or `nil` if LRCLIB has none (`404`).
    func lyrics(for track: LyricsTrack) async throws -> LRCLIBRecord? {
        let request = makeRequest(for: track)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw LRCLIBError.network(error.code)
        }
        guard let http = response as? HTTPURLResponse else { throw LRCLIBError.invalidResponse }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder().decode(LRCLIBRecord.self, from: data)
            } catch {
                throw LRCLIBError.invalidResponse
            }
        case 404:
            return nil
        case 429, 503:
            throw LRCLIBError.rateLimited(retryAfter: Self.retryAfter(from: http))
        default:
            throw LRCLIBError.server(status: http.statusCode)
        }
    }

    /// `GET /api/get?track_name=…&artist_name=…&album_name=…&duration=…`.
    ///
    /// The album is optional; the duration is sent in whole seconds and only inside the range
    /// LRCLIB accepts (1–3600 s), because a value outside it is a `400`.
    func makeRequest(for track: LyricsTrack) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("api/get"),
                                       resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
        ]
        if let album = track.album, !album.trimmingCharacters(in: .whitespaces).isEmpty {
            items.append(URLQueryItem(name: "album_name", value: album))
        }
        let seconds = Int((Double(track.durationMs) / 1000).rounded())
        if (1...3600).contains(seconds) {
            items.append(URLQueryItem(name: "duration", value: String(seconds)))
        }
        components.queryItems = items
        // `URLComponents` leaves `+` as is, and a server reads it as a space. Encode it.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
    }

    /// `Retry-After` in seconds. Without a usable header, wait 1 s (the docs say `503` usually
    /// asks for 1 s).
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds >= 0
        else { return 1 }
        return seconds
    }
}
