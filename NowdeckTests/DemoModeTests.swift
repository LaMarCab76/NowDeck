#if DEBUG
import XCTest
@testable import Nowdeck

/// The demo answers decode with the app's own decoders, and nothing outside the demo routes
/// gets an answer.
final class DemoModeTests: XCTestCase {
    private func answer(_ url: String) -> DemoURLProtocol.Answer {
        answer("GET", url)
    }

    private func answer(_ method: String, _ url: String) -> DemoURLProtocol.Answer {
        DemoURLProtocol.answer(method: method, url: URL(string: url)!)
    }

    /// Through `URLSession`, so `startLoading` is covered too. A session of its own instead
    /// of registering on `URLSession.shared`, which would leak into other tests.
    func testRequestsAreAnsweredThroughTheURLLoadingSystem() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DemoURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(
            from: URL(string: "https://api.spotify.com/v1/me/player")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let state = try SpotifyAPI.makeDecoder().decode(PlaybackState.self, from: data)
        XCTAssertTrue(state.isPlaying)

        let (_, missing) = try await session.data(from: URL(string: "https://example.invalid/")!)
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
    }

    func testUnknownHostsAndRoutesAnswerNotFound() {
        XCTAssertEqual(answer("https://example.com/").status, 404)
        XCTAssertEqual(answer("POST", "https://accounts.spotify.com/api/token").status, 404)
        XCTAssertEqual(answer("https://api.spotify.com/v1/me/following").status, 404)
        XCTAssertEqual(answer("https://\(DemoArtwork.host)/art/nothing.png").status, 404)
    }

    func testPlaybackStateDecodesAsAPlayingTrack() throws {
        let answer = answer("https://api.spotify.com/v1/me/player?additional_types=episode")
        XCTAssertEqual(answer.status, 200)
        let state = try SpotifyAPI.makeDecoder().decode(PlaybackState.self, from: answer.body)
        XCTAssertTrue(state.isPlaying)
        guard case .track(let track)? = state.item else { return XCTFail("Expected a track") }
        XCTAssertEqual(track.name, DemoContent.nowPlaying.name)
        XCTAssertEqual(state.context?.uri, "spotify:playlist:\(DemoContent.currentPlaylist.id)")
    }

    func testQueueDevicesAndLibraryDecode() throws {
        let decoder = SpotifyAPI.makeDecoder()
        let queue = try decoder.decode(
            PlaybackQueue.self, from: answer("https://api.spotify.com/v1/me/player/queue").body)
        XCTAssertEqual(queue.queue.count, DemoContent.queue.count)

        let playlists = try decoder.decode(
            Paging<SimplifiedPlaylist>.self,
            from: answer("https://api.spotify.com/v1/me/playlists?limit=20&offset=0").body)
        XCTAssertEqual(playlists.items.count, DemoContent.playlists.count)
        XCTAssertNil(playlists.nextOffset)

        let albums = try decoder.decode(
            Paging<SavedAlbum>.self, from: answer("https://api.spotify.com/v1/me/albums").body)
        XCTAssertEqual(albums.items.count, DemoContent.albums.count)
    }

    func testCommandsAreAcceptedWithoutContent() {
        XCTAssertEqual(answer("PUT", "https://api.spotify.com/v1/me/player/pause").status, 204)
        XCTAssertEqual(answer("POST", "https://api.spotify.com/v1/me/player/next").status, 204)
    }

    func testLyricsOnlyForTheTrackThatPlays() throws {
        let name = DemoContent.nowPlaying.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let found = answer("https://lrclib.net/api/get?track_name=\(name)&artist_name=x")
        XCTAssertEqual(found.status, 200)
        let record = try JSONDecoder().decode(LRCLIBRecord.self, from: found.body)
        XCTAssertNotNil(record.syncedLyricsForDisplay())

        XCTAssertEqual(answer("https://lrclib.net/api/get?track_name=Other&artist_name=x").status, 404)
    }

    func testDemoThemesAreKeptApartFromTheRealOnes() {
        XCTAssertNotEqual(DemoMode.themeStorage().directory.standardizedFileURL,
                          ThemeStorage.applicationSupport().directory.standardizedFileURL)
    }

    func testCoversAreDrawnFromTheirURL() throws {
        let url = DemoArtwork.url(from: "1b2a4a", to: "f2766b", shape: .rings)
        let answer = answer(url)
        XCTAssertEqual(answer.status, 200)
        let image = try XCTUnwrap(UIImage(data: answer.body))
        XCTAssertEqual(image.size.width, 640)
    }
}
#endif
