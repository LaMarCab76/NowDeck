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
                                                             seenArtistID: "seen")
        XCTAssertNotNil(image)
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
                                                             seenArtistID: "seen")
        XCTAssertNotNil(image)
        XCTAssertTrue(recorder.requests.contains { $0.url?.path == "/v1/artists/seen" })
    }

    func testNoSamplePhotoWithoutAnyArtist() async throws {
        let (api, loader, _) = makeAPI { _ in (.stub(200), Data(#"{"items":[]}"#.utf8)) }
        let image = await BackgroundPreviewModel.samplePhoto(api: api, loader: loader,
                                                             seenArtistID: nil)
        XCTAssertNil(image)
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
