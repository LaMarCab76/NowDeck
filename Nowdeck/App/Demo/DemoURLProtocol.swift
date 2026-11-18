#if DEBUG
import Foundation

/// Answers every request of the demo session on the device (see `DemoMode`).
///
/// - `api.spotify.com/v1`: reads from `DemoContent`; commands answer `204` and change
///   nothing, so the screens stay as the screenshots expect.
/// - `lrclib.net/api/get`: the invented lyrics of the track that plays, `404` for the rest.
/// - `demo.nowdeck.invalid/art/…`: covers drawn by `DemoArtwork`.
/// - Anything else, `accounts.spotify.com` included: `404`. Nothing goes to the network.
final class DemoURLProtocol: URLProtocol, @unchecked Sendable {
    struct Answer {
        var status: Int
        var body: Data
        var contentType: String
    }

    override class func canInit(with request: URLRequest) -> Bool {
        // Every request, so none can leave the device by accident.
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let answer = Self.answer(method: request.httpMethod ?? "GET", url: url)
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": answer.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    // MARK: Routing

    static func answer(method: String, url: URL) -> Answer {
        let path = url.path
        switch url.host {
        case "api.spotify.com" where path.hasPrefix("/v1/"):
            return spotify(method: method, path: String(path.dropFirst("/v1".count)), url: url)
        case "lrclib.net" where path == "/api/get":
            let trackName = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "track_name" }?.value
            return DemoContent.lyricsRecord(trackName: trackName).map(json) ?? notFound
        case DemoArtwork.host:
            guard let png = DemoArtwork.png(forPath: path) else { return notFound }
            return Answer(status: 200, body: png, contentType: "image/png")
        default:
            return notFound
        }
    }

    private static func spotify(method: String, path: String, url: URL) -> Answer {
        // Commands (play, pause, next, volume, seek, transfer…) are accepted and ignored.
        if method == "PUT" || method == "DELETE" {
            return Answer(status: 204, body: Data(), contentType: "application/json")
        }
        if method == "POST" {
            if path.hasSuffix("/items") {
                return Answer(status: 201, body: body(["snapshot_id": "demo"]),
                              contentType: "application/json")
            }
            return Answer(status: 204, body: Data(), contentType: "application/json")
        }

        let parts = path.split(separator: "/").map(String.init)
        switch parts {
        case ["me", "player"]: return json(DemoContent.playbackState())
        case ["me", "player", "queue"]: return json(DemoContent.queueJSON())
        case ["me", "player", "devices"]: return json(DemoContent.devicesJSON())
        case ["me", "player", "recently-played"]: return json(DemoContent.recentlyPlayedJSON())
        case ["me"]: return json(["id": "demouser", "display_name": "You"])
        case ["me", "playlists"]: return json(DemoContent.playlistsPage())
        case ["me", "albums"]: return json(DemoContent.albumsPage())
        case ["me", "shows"]: return json(DemoContent.showsPage())
        case ["me", "audiobooks"]: return json(DemoContent.audiobooksPage())
        case ["search"]: return json(DemoContent.searchJSON())
        default: break
        }
        if parts.count == 2, parts[0] == "playlists" {
            return DemoContent.playlistName(id: parts[1]).map(json) ?? notFound
        }
        if parts.count == 3, parts[0] == "playlists", parts[2] == "items" {
            return json(DemoContent.collectionTracksPage(wrapped: true))
        }
        if parts.count == 3, parts[0] == "albums", parts[2] == "tracks" {
            return json(DemoContent.collectionTracksPage(wrapped: false))
        }
        if parts.count == 2, parts[0] == "artists" {
            return json(DemoContent.artistJSON(id: parts[1]))
        }
        return notFound
    }

    // MARK: Helpers

    private static let notFound = Answer(
        status: 404,
        body: body(["error": ["status": 404, "message": "Not found (demo mode)"]]),
        contentType: "application/json")

    private static func json(_ object: DemoContent.JSON) -> Answer {
        Answer(status: 200, body: body(object), contentType: "application/json")
    }

    private static func body(_ object: DemoContent.JSON) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
}
#endif
