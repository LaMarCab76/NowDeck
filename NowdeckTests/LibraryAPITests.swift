import XCTest
@testable import Nowdeck

/// Requests of `SpotifyAPI+Library`: paths, pagination, search parameters and the
/// start-playback body.
final class LibraryAPITests: XCTestCase {
    // MARK: Library pages

    func testLibraryRequestsUsePathLimitAndOffset() async throws {
        let (api, recorder) = makeLibraryTestAPI { _ in (.stub(200), LibraryJSON.page([])) }

        _ = try await api.savedPlaylists()
        _ = try await api.savedAlbums(offset: 20)
        _ = try await api.savedShows(limit: 5)
        _ = try await api.savedAudiobooks(limit: 80, offset: -3)

        let urls = recorder.requests.map { $0.url?.absoluteString }
        XCTAssertEqual(urls, [
            "https://api.spotify.com/v1/me/playlists?limit=20&offset=0",
            "https://api.spotify.com/v1/me/albums?limit=20&offset=20",
            "https://api.spotify.com/v1/me/shows?limit=5&offset=0",
            // The references allow 1–50 and offsets from 0.
            "https://api.spotify.com/v1/me/audiobooks?limit=50&offset=0",
        ])
        XCTAssertTrue(recorder.requests.allSatisfy { $0.httpMethod == "GET" })
    }

    func testLibraryPageDecodesItems() async throws {
        let body = LibraryJSON.page([LibraryJSON.savedAlbum("Costanera", id: "a1")],
                                    total: 31, hasNext: true)
        let (api, _) = makeLibraryTestAPI { _ in (.stub(200), body) }

        let page = try await api.savedAlbums()

        XCTAssertEqual(page.items.first?.album.name, "Costanera")
        XCTAssertEqual(page.total, 31)
        XCTAssertEqual(page.nextOffset, 20)
    }

    func testLibraryForbiddenIsReported() async {
        let (api, _) = makeLibraryTestAPI { _ in
            (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden"))
        }
        do {
            _ = try await api.savedPlaylists()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError, .forbidden(message: "Forbidden"))
        }
    }

    // MARK: Start playback

    func testPlayContextSendsContextURIOnActiveDevice() async throws {
        let (api, recorder) = makeLibraryTestAPI { _ in (.stub(204), Data()) }

        try await api.playContext(uri: "spotify:album:5ht7ItJgpBH7W6vJ5BqpPr")

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString, "https://api.spotify.com/v1/me/player/play",
                       "No device_id: Spotify targets the active device")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["context_uri": "spotify:album:5ht7ItJgpBH7W6vJ5BqpPr"])
    }

    func testPlayContextBodyIsExactJSON() throws {
        let body = try SpotifyAPI.playContextBody(uri: "spotify:playlist:37i9dQZF1DXcBWIGoYBM5M")
        XCTAssertEqual(String(decoding: body, as: UTF8.self),
                       #"{"context_uri":"spotify:playlist:37i9dQZF1DXcBWIGoYBM5M"}"#)
    }

    func testPlayContextWithoutActiveDeviceIsNotFound() async {
        let (api, _) = makeLibraryTestAPI { _ in
            (.stub(404), spotifyErrorJSON(status: 404, message: "Player command failed: No active device found"))
        }
        do {
            try await api.playContext(uri: "spotify:album:a")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError,
                           .notFound(message: "Player command failed: No active device found"))
        }
    }

    func testPlayContextIsNotRetriedOnServerError() async {
        let (api, recorder) = makeLibraryTestAPI { _ in (.stub(502), Data()) }
        do {
            try await api.playContext(uri: "spotify:album:a")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError, .server(status: 502))
        }
        XCTAssertEqual(recorder.requests.count, 1, "Commands are never repeated automatically")
    }

    // MARK: Search

    func testSearchRequestUsesTypesAndMaximumLimit() async throws {
        let (api, recorder) = makeLibraryTestAPI { _ in
            (.stub(200), try Fixture.data("search-reference"))
        }

        let results = try await api.search(try XCTUnwrap(SearchQuery(text: "  vereda mojada ")))

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, "/v1/search")
        XCTAssertEqual(request.queryValues, [
            "q": "vereda mojada",
            "type": "track,album,playlist,show,audiobook",
            "limit": "10",
            "offset": "0",
        ])
        XCTAssertEqual(results.albums?.items.count, 1)
    }

    func testSearchQueryIsPercentEncoded() async throws {
        let (api, recorder) = makeLibraryTestAPI { _ in (.stub(200), Data("{}".utf8)) }

        _ = try await api.search(try XCTUnwrap(SearchQuery(text: "AC+DC & Él=1", types: [.track])))

        let request = try XCTUnwrap(recorder.requests.first)
        let query = try XCTUnwrap(request.url?.query)
        XCTAssertTrue(query.hasPrefix("q=AC%2BDC%20%26%20%C3%89l%3D1&"), query)
        XCTAssertEqual(request.queryValues["q"], "AC+DC & Él=1",
                       "Spotify must receive the plus sign, not a space")
        XCTAssertEqual(request.queryValues["type"], "track")
    }

    func testSearchQueryLimits() {
        XCTAssertNil(SearchQuery(text: ""))
        XCTAssertNil(SearchQuery(text: "   \n"))
        XCTAssertNil(SearchQuery(text: "tango", types: []))
        XCTAssertEqual(SearchQuery(text: "tango", limit: 50)?.limit, 10,
                       "Maximum limit since February 2026")
        XCTAssertEqual(SearchQuery(text: "tango", limit: 0)?.limit, 1)
        XCTAssertEqual(SearchQuery(text: "tango", offset: 5000)?.offset, 1000)
        XCTAssertEqual(SearchQuery(text: "tango", offset: -1)?.offset, 0)
    }

    func testSearchRateLimitIsReported() async {
        let (api, _) = makeLibraryTestAPI { _ in
            (.stub(429, headers: ["Retry-After": "4"]),
             spotifyErrorJSON(status: 429, message: "Too many", reason: "QUOTA_EXCEEDED"))
        }
        do {
            _ = try await api.search(SearchQuery(text: "tango")!)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError, .rateLimited(retryAfter: 4, quotaExceeded: true))
        }
    }
}
