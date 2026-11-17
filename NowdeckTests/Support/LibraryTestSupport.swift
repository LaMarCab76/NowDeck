import Foundation
import XCTest
@testable import Nowdeck

/// JSON builders for library answers, with the shape of the references.
enum LibraryJSON {
    static func page(_ items: [Any], offset: Int = 0, limit: Int = 20, total: Int? = nil,
                     hasNext: Bool = false) -> Data {
        var object: [String: Any] = [
            "href": "https://api.spotify.com/v1/me/x?offset=\(offset)&limit=\(limit)",
            "limit": limit,
            "offset": offset,
            "total": total ?? items.count,
            "previous": NSNull(),
            "items": items,
        ]
        object["next"] = hasNext
            ? "https://api.spotify.com/v1/me/x?offset=\(offset + limit)&limit=\(limit)"
            : NSNull()
        return try! JSONSerialization.data(withJSONObject: object)
    }

    static func playlist(_ name: String, id: String, count: Int = 10) -> [String: Any] {
        [
            "id": id,
            "name": name,
            "uri": "spotify:playlist:\(id)",
            "images": [["url": "https://i.scdn.co/image/\(id)", "width": 300, "height": 300]],
            "items": ["href": "https://api.spotify.com/v1/playlists/\(id)/items", "total": count],
            "external_urls": ["spotify": "https://open.spotify.com/playlist/\(id)"],
            "type": "playlist",
        ]
    }

    static func savedAlbum(_ name: String, id: String, artist: String = "Artista") -> [String: Any] {
        [
            "added_at": "2026-01-01T00:00:00Z",
            "album": [
                "id": id,
                "name": name,
                "uri": "spotify:album:\(id)",
                "album_type": "album",
                "total_tracks": 10,
                "images": [["url": "https://i.scdn.co/image/\(id)", "width": 640, "height": 640]],
                "artists": [["id": "a1", "name": artist, "uri": "spotify:artist:a1"]],
            ] as [String: Any],
        ]
    }

    static func savedShow(_ name: String, id: String, episodes: Int = 12) -> [String: Any] {
        [
            "added_at": "2026-01-01T00:00:00Z",
            "show": [
                "id": id,
                "name": name,
                "uri": "spotify:show:\(id)",
                "total_episodes": episodes,
                "images": [] as [Any],
            ] as [String: Any],
        ]
    }

    static func audiobook(_ name: String, id: String, author: String = "Autora") -> [String: Any] {
        [
            "id": id,
            "name": name,
            "uri": "spotify:audiobook:\(id)",
            "authors": [["name": author]],
            "narrators": [["name": "Narrador"]],
            "total_chapters": 20,
            "images": [] as [Any],
        ]
    }
}

func makeLibraryTestAPI(handler: @escaping StubURLProtocol.Handler) -> (SpotifyAPI, StubRecorder) {
    let (session, recorder) = StubURLProtocol.session(handler: handler)
    // No real waits: 5xx retries sleep through this stub.
    let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                         sleep: { _ in }, jitter: { 0 })
    return (api, recorder)
}

extension URLRequest {
    /// The query items of the request URL, by name.
    var queryValues: [String: String] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems else { return [:] }
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }
}
