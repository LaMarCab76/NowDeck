import UIKit
import XCTest
@testable import Nowdeck

/// Ajustes' background preview (2026-11-18): the sample photo, the recently played request,
/// and the "Oscurecer" values.
@MainActor
final class BackgroundPreviewTests: XCTestCase {
    private let recentPath = "/v1/me/player/recently-played"

    nonisolated private static let png: Data = {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }()

    nonisolated private static func recentJSON(artistID: String) -> Data {
        Data(#"""
        {"items":[{"track":{"type":"track","id":"t1","name":"Tema","duration_ms":1000,
        "explicit":false,"is_local":false,"artists":[{"id":"\#(artistID)","name":"Artista"}]},
        "played_at":"2026-11-18T10:00:00.000Z","context":null}],
        "next":null,"cursors":{"after":"1","before":"0"},"limit":1,"href":"x"}
        """#.utf8)
    }

    nonisolated private static let artistJSON = Data(
        #"{"images":[{"url":"https://i.scdn.co/image/sample","width":640,"height":640}]}"#.utf8)

    private func makeAPI(_ handler: @escaping StubURLProtocol.Handler)
        -> (SpotifyAPI, ArtworkLoader, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        return (api, ArtworkLoader(session: session), recorder)
    }

    func testRecentlyPlayedRequestAndDecoding() async throws {
        let (api, _, recorder) = makeAPI { _ in (.stub(200), Self.recentJSON(artistID: "a1")) }
        let items = try await api.recentlyPlayedTracks(limit: 1)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first.flatMap { NowPlaying(item: $0) }?.artistID, "a1")
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.url?.path, recentPath)
        XCTAssertEqual(request.url?.query, "limit=1")
        XCTAssertEqual(request.httpMethod, "GET")
    }

    func testRecentlyPlayedWithoutItemsIsEmpty() async throws {
        let (api, _, _) = makeAPI { _ in (.stub(200), Data(#"{"items":[]}"#.utf8)) }
        let items = try await api.recentlyPlayedTracks()
        XCTAssertEqual(items, [])
    }

    func testSamplePhotoUsesTheLastTrackHeard() async throws {
        let (api, loader, recorder) = makeAPI { [recentPath] request in
            if request.url?.path == recentPath { return (.stub(200), Self.recentJSON(artistID: "recent")) }
            if request.url?.path == "/v1/artists/recent" { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            return (.stub(404), Data())
        }
        let image = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader,
                                                             seenArtistID: { "seen" })
        XCTAssertEqual(image?.artistID, "recent")
        XCTAssertEqual(image?.artistURL?.absoluteString, "https://open.spotify.com/artist/recent")
        XCTAssertFalse(recorder.requests.contains { $0.url?.path == "/v1/artists/seen" },
                       "Spotify's history wins over what the app saw")
    }

    func testSamplePhotoFallsBackToWhatTheAppSawWithoutTheScope() async throws {
        // Sessions from before the scope was added: Spotify answers 403.
        let (api, loader, recorder) = makeAPI { [recentPath] request in
            if request.url?.path == recentPath {
                return (.stub(403), spotifyErrorJSON(status: 403, message: "Insufficient client scope"))
            }
            if request.url?.path == "/v1/artists/seen" { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            return (.stub(404), Data())
        }
        let image = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader,
                                                             seenArtistID: { "seen" })
        XCTAssertEqual(image?.artistID, "seen")
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/v1/artists/seen" })
    }

    func testNoSamplePhotoWithoutAnyArtist() async throws {
        let (api, loader, _) = makeAPI { _ in (.stub(200), Data(#"{"items":[]}"#.utf8)) }
        let image = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader,
                                                             seenArtistID: { nil })
        XCTAssertNil(image)
    }

    /// A player whose `GET /me/player` answers `playing` (track of artist 08td…) or `204`.
    private func makePlayer(playing: StubBox<Bool>) throws -> PlayerModel {
        let playback = try PlaybackJSON().data()
        let (session, _) = StubURLProtocol.session { request in
            let path = request.url?.path ?? ""
            if path.hasPrefix("/v1/artists") { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            if path == "/v1/me/player" { return playing.value ? (.stub(200), playback) : (.stub(204), Data()) }
            return (.stub(404), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        return PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func testTheLastHeardArtistStaysWhenPlaybackStops() async throws {
        let playing = StubBox(true)
        let player = try makePlayer(playing: playing)
        XCTAssertNil(player.lastHeardArtistID)
        _ = await player.poll()
        XCTAssertEqual(player.lastHeardArtistID, "08td7MxkoHQkXnWAYD8d6Q")
        XCTAssertNil(player.previousTrack, "One track only: the swipe history is still empty")
        playing.value = false
        _ = await player.poll()
        XCTAssertNil(player.nowPlaying)
        XCTAssertEqual(player.lastHeardArtistID, "08td7MxkoHQkXnWAYD8d6Q",
                       "Kept for the preview's fallback")
    }

    func testThePreviewKeepsThePlayersPhotoWhenPlaybackStops() async throws {
        let playing = StubBox(true)
        let player = try makePlayer(playing: playing)
        let preview = BackgroundPreviewModel(player: player)
        _ = await player.poll()
        try await waitUntil { preview.image != nil }
        let photo = preview.image
        playing.value = false
        _ = await player.poll()
        XCTAssertNil(player.artistImage)
        XCTAssertTrue(preview.image === photo, "The newest photo stays, not an older lookup")
        XCTAssertEqual(preview.artistURL?.absoluteString,
                       "https://open.spotify.com/artist/08td7MxkoHQkXnWAYD8d6Q", "The icon opens that artist")
    }

    func testAFailedLookupIsTriedAgainOnTheNextTouch() async throws {
        let available = StubBox(false)
        let (session, recorder) = StubURLProtocol.session { [recentPath] request in
            if request.url?.path == recentPath {
                // 403 is not retried by `SpotifyAPI`, so the first lookup ends after one request.
                return available.value ? (.stub(200), Self.recentJSON(artistID: "recent"))
                                       : (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden"))
            }
            if request.url?.path == "/v1/artists/recent" { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            return (.stub(204), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        let preview = BackgroundPreviewModel(player: player)
        let historyRequests = { recorder.requests.filter { $0.url?.path == self.recentPath }.count }
        preview.prepare()
        XCTAssertTrue(preview.isLookingUp)
        try await waitUntil { !preview.isLookingUp }
        XCTAssertEqual(historyRequests(), 1)
        XCTAssertNil(preview.image)

        available.value = true
        preview.begin(.blur, blur: 0, dim: 30)
        XCTAssertTrue(preview.isLookingUp, "The touch starts a new lookup")
        try await waitUntil { preview.image != nil }
        XCTAssertEqual(historyRequests(), 2)
        XCTAssertEqual(preview.artistURL?.absoluteString, "https://open.spotify.com/artist/recent")
    }

    func testACancelledLookupCanStartAgain() async throws {
        let (session, _) = StubURLProtocol.session { _ in (.stub(200), Data(#"{"items":[]}"#.utf8)) }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let preview = BackgroundPreviewModel(
            player: PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session)))
        preview.prepare()
        preview.cancel()
        try await waitUntil { !preview.isLookingUp }
        preview.prepare()
        XCTAssertTrue(preview.isLookingUp, "Not stuck on the cancelled task")
    }

    func testOnlyAPlayingTrackCountsAsHeard() async throws {
        let paused = try PlaybackJSON(isPlaying: false).data()
        let (session, _) = StubURLProtocol.session { request in
            if request.url?.path == "/v1/me/player" { return (.stub(200), paused) }
            return (.stub(404), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        _ = await player.poll()
        XCTAssertNotNil(player.nowPlaying)
        XCTAssertNil(player.lastHeardArtistID)
    }

    func testNoLookupOnceThePlayerShowedAPhoto() async throws {
        let playing = StubBox(true)
        let player = try makePlayer(playing: playing)
        let preview = BackgroundPreviewModel(player: player)
        _ = await player.poll()
        try await waitUntil { preview.image != nil }
        preview.prepare()
        XCTAssertFalse(preview.isLookingUp, "The player's photo wins for the whole visit")
    }

    func testSlidersDriveThePreview() {
        let preview = BackgroundPreviewModel(player: nil)
        XCTAssertNil(preview.editing)
        preview.begin(.dim, blur: 20, dim: 30)
        preview.update(.dim, to: 55)
        XCTAssertEqual(preview.editing, .dim)
        XCTAssertEqual(preview.blur, 20, "The other value stays as saved")
        XCTAssertEqual(preview.dim, 55)
        preview.end()
        XCTAssertNil(preview.editing)
    }

    func testDimMapsToABlackLayerThatNeverHidesThePhoto() {
        XCTAssertEqual(Metrics.ArtistPhoto.dimOpacity(for: 0), 0)
        XCTAssertEqual(Metrics.ArtistPhoto.dimOpacity(for: 100), 0.8, accuracy: 0.0001)
        XCTAssertEqual(Metrics.ArtistPhoto.dimOpacity(for: 50), 0.4, accuracy: 0.0001)
        XCTAssertEqual(Metrics.ArtistPhoto.dimOpacity(for: 250), 0.8, accuracy: 0.0001, "Clamped")
        XCTAssertEqual(Metrics.ArtistPhoto.blurRadius(for: 100), 30)
    }
}
