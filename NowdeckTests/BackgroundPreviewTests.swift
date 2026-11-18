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

    func testSamplePhotoUsesSpotifysHistoryWhenTheAppHeardNothing() async throws {
        let (api, loader, recorder) = makeAPI { [recentPath] request in
            if request.url?.path == recentPath { return (.stub(200), Self.recentJSON(artistID: "recent")) }
            if request.url?.path == "/v1/artists/recent" { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            return (.stub(404), Data())
        }
        // The app heard nothing yet (opened with nothing playing): history is all there is.
        let image = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader,
                                                             seenArtistID: { nil }).sample
        XCTAssertEqual(image?.artistID, "recent")
        XCTAssertEqual(image?.artistURL?.absoluteString, "https://open.spotify.com/artist/recent")
        XCTAssertEqual(recorder.requests.filter { $0.url?.path.hasPrefix("/v1/artists") == true }.count, 1)
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
                                                             seenArtistID: { "seen" }).sample
        XCTAssertEqual(image?.artistID, "seen")
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/v1/artists/seen" })
    }

    func testAHistoryArtistOtherThanTheOneHeardIsSkipped() async throws {
        // Spotify's history still shows an older track: the artist heard now wins.
        let (api, loader, recorder) = makeAPI { [recentPath] request in
            if request.url?.path == recentPath { return (.stub(200), Self.recentJSON(artistID: "old")) }
            if request.url?.path == "/v1/artists/seen" { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            return (.stub(404), Data())
        }
        let lookup = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader,
                                                              seenArtistID: { "seen" })
        XCTAssertEqual(lookup.sample?.artistID, "seen")
        XCTAssertFalse(recorder.requests.contains { $0.url?.path == "/v1/artists/old" })
    }

    func testNoSamplePhotoWithoutAnyArtist() async throws {
        let (api, loader, _) = makeAPI { _ in (.stub(200), Data(#"{"items":[]}"#.utf8)) }
        let image = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader,
                                                             seenArtistID: { nil }).sample
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

    func testPollsDuringADragDoNotRepeatTheLookup() async throws {
        let (session, recorder) = StubURLProtocol.session { [recentPath] request in
            if request.url?.path == recentPath {
                return (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden"))
            }
            return (.stub(204), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        let preview = BackgroundPreviewModel(player: player)
        preview.begin(.blur, blur: 0, dim: 30)
        try await waitUntil { !preview.isLookingUp }
        for _ in 0..<3 {
            _ = await player.poll()
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTAssertFalse(preview.isLookingUp)
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == self.recentPath }.count, 1,
                       "Polls with the same (no) artist ask nothing again")
    }

    func testANewArtistDuringADragStartsOneFollowUpLookup() async throws {
        // No photo anywhere: Spotify's history is not readable and the artist has none.
        let playing = StubBox(false)
        let playback = try PlaybackJSON().data()
        let (session, recorder) = StubURLProtocol.session { [recentPath] request in
            let path = request.url?.path ?? ""
            if path == recentPath { return (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden")) }
            if path.hasPrefix("/v1/artists") { return (.stub(404), Data()) }
            if path == "/v1/me/player" { return playing.value ? (.stub(200), playback) : (.stub(204), Data()) }
            return (.stub(404), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        // The preview is then the only one asking for the artist.
        player.loadsArtistImages = false
        let preview = BackgroundPreviewModel(player: player)
        let historyRequests = { recorder.requests.filter { $0.url?.path == self.recentPath }.count }
        preview.begin(.blur, blur: 0, dim: 30)
        try await waitUntil { !preview.isLookingUp }
        XCTAssertEqual(historyRequests(), 1)

        // An artist starts under the finger: one follow-up for it, and no more after that.
        playing.value = true
        _ = await player.poll()
        try await waitUntil { historyRequests() == 2 }
        try await waitUntil { !preview.isLookingUp }
        for _ in 0..<3 {
            _ = await player.poll()
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        XCTAssertEqual(historyRequests(), 2)
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/v1/artists/08td7MxkoHQkXnWAYD8d6Q" })
    }

    func testAHistoryAnswerForANewerArtistStillLooksUpItsPhoto() async throws {
        // The lookup starts while A is the last heard; B starts before history answers, and
        // history names B: B's photo is the one to ask for, once.
        let (api, loader, recorder) = makeAPI { [recentPath] request in
            let path = request.url?.path ?? ""
            if path == recentPath { return (.stub(200), Self.recentJSON(artistID: "artistB")) }
            if path == "/v1/artists/artistB" { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            return (.stub(404), Data())
        }
        // The artist heard is A until history has been asked, B after: reading it too early
        // would get A, whose history-mismatched lookup finds nothing.
        let lookup = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader, seenArtistID: {
            recorder.requests.contains { $0.url?.path == self.recentPath } ? "artistB" : "artistA"
        })
        XCTAssertEqual(lookup.sample?.artistID, "artistB")
        XCTAssertEqual(lookup.heardArtistID, "artistB")
        XCTAssertEqual(recorder.requests.filter { $0.url?.path == "/v1/artists/artistB" }.count, 1)
    }

    func testACancelledLookupStopsAndCanStartAgain() async throws {
        // History is held until the lookup is cancelled. Had the cancel not reached it, the
        // lookup would go on to the artist's photo and show it.
        let gate = DispatchSemaphore(value: 0)
        let (session, recorder) = StubURLProtocol.session { [recentPath] request in
            let path = request.url?.path ?? ""
            if path == recentPath {
                gate.wait()
                return (.stub(200), Self.recentJSON(artistID: "recent"))
            }
            if path == "/v1/artists/recent" { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            return (.stub(204), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let preview = BackgroundPreviewModel(
            player: PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session)))
        let historyRequests = { recorder.requests.filter { $0.url?.path == self.recentPath }.count }

        preview.prepare()
        try await waitUntil { historyRequests() == 1 }
        preview.cancel()
        gate.signal()
        try await waitUntil { !preview.isLookingUp }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(preview.image, "The cancelled lookup went no further")
        XCTAssertFalse(recorder.requests.contains { $0.url?.path == "/v1/artists/recent" })

        preview.prepare()
        XCTAssertTrue(preview.isLookingUp, "Not stuck on the cancelled task")
        gate.signal()
        try await waitUntil { preview.image != nil }
        XCTAssertEqual(historyRequests(), 2)
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

    func testAPhotoPickedWhilePausedIsNotKeptAsTheLastHeard() async throws {
        // Paused from the start: the player shows the artist's photo, but nothing was heard.
        let paused = try PlaybackJSON(isPlaying: false).data()
        let state = StubBox(paused)
        let (session, _) = StubURLProtocol.session { request in
            let path = request.url?.path ?? ""
            if path.hasPrefix("/v1/artists") { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            if path == "/v1/me/player" { return (.stub(200), state.value) }
            return (.stub(404), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        let preview = BackgroundPreviewModel(player: player)
        _ = await player.poll()
        try await waitUntil { player.artistImage != nil }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(preview.image, "Picked while paused: not heard")

        state.value = Data()
        _ = await player.poll()
        XCTAssertNil(player.nowPlaying)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(preview.image, "Still not heard once playback is idle")
    }

    func testResumingAPausedTrackMakesItsPhotoTheSample() async throws {
        let state = StubBox(try PlaybackJSON(isPlaying: false).data())
        let (session, _) = StubURLProtocol.session { request in
            let path = request.url?.path ?? ""
            if path.hasPrefix("/v1/artists") { return (.stub(200), Self.artistJSON) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            if path == "/v1/me/player" { return (.stub(200), state.value) }
            return (.stub(404), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        let preview = BackgroundPreviewModel(player: player)
        var photoUpdates = 0
        let counter = player.$artistImage.dropFirst().sink { _ in photoUpdates += 1 }
        defer { counter.cancel() }
        _ = await player.poll()
        try await waitUntil { player.artistImage != nil }
        let pausedPhoto = try XCTUnwrap(player.artistImage)
        // Let the photo event reach the preview first: it must not pick a paused track.
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(preview.image)
        XCTAssertEqual(photoUpdates, 1)

        // Same track, now playing: the photo is not published again, the playback change
        // alone makes it the sample.
        state.value = try PlaybackJSON(isPlaying: true).data()
        _ = await player.poll()
        try await waitUntil { preview.image != nil }
        XCTAssertTrue(preview.image === pausedPhoto)
        XCTAssertEqual(photoUpdates, 1, "No new photo: the playback change did it")
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
