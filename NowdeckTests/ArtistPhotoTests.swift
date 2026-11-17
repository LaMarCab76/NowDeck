import UIKit
import XCTest
@testable import Nowdeck

/// The artist's photo behind the player (`GET /artists/{id}`, 2026-11-17).
@MainActor
final class ArtistPhotoTests: XCTestCase {
    private let artistPath = "/v1/artists/08td7MxkoHQkXnWAYD8d6Q"
    private let photoURL = "https://i.scdn.co/image/artist-photo-640"

    private func makeModel(handler: @escaping StubURLProtocol.Handler) -> (PlayerModel, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        return (PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session)), recorder)
    }

    nonisolated private static let png: Data = {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }()

    nonisolated private static func artistJSON(images: [(String, Int)]) -> Data {
        let list = images.map { #"{"url":"\#($0.0)","width":\#($0.1),"height":\#($0.1)}"# }
        return Data(#"{"id":"08td7MxkoHQkXnWAYD8d6Q","name":"Los Tilos del Sur","images":[\#(list.joined(separator: ","))]}"#.utf8)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func requests(_ recorder: StubRecorder, path: String) -> Int {
        recorder.requests.filter { $0.url?.path == path }.count
    }

    func testNowPlayingKeepsTheFirstArtistID() throws {
        let item = try XCTUnwrap(NowPlaying(state: PlaybackJSON().state()))
        XCTAssertEqual(item.artistID, "08td7MxkoHQkXnWAYD8d6Q")
        let episode = try XCTUnwrap(NowPlaying(state: PlaybackJSON(episode: true).state()))
        XCTAssertNil(episode.artistID, "Episodes have no artist photo")
    }

    func testLoadsTheWidestPhotoOncePerArtist() async throws {
        let playback = try PlaybackJSON().data()
        let (model, recorder) = makeModel { [artistPath, photoURL] request in
            if request.url?.path == artistPath {
                return (.stub(200), Self.artistJSON(images: [("https://i.scdn.co/image/small", 160),
                                                            (photoURL, 640)]))
            }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            if request.url?.path.hasPrefix("/v1/playlists") == true { return (.stub(404), Data()) }
            return (.stub(200), playback)
        }

        await model.poll()
        try await waitUntil { model.artistImage != nil }
        XCTAssertTrue(recorder.requests.contains { $0.url?.absoluteString == photoURL },
                      "The widest image")

        await model.poll()
        await model.poll()
        XCTAssertEqual(requests(recorder, path: artistPath), 1, "Cached for the same artist")
        XCTAssertNotNil(model.artistImage)
    }

    func testTurningTheOptionOffMakesNoRequestAndClearsThePhoto() async throws {
        let playback = try PlaybackJSON().data()
        let (model, recorder) = makeModel { [artistPath] request in
            if request.url?.path == artistPath {
                return (.stub(200), Self.artistJSON(images: [("https://i.scdn.co/image/p", 640)]))
            }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            if request.url?.path.hasPrefix("/v1/playlists") == true { return (.stub(404), Data()) }
            return (.stub(200), playback)
        }
        model.loadsArtistImages = false
        await model.poll()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(requests(recorder, path: artistPath), 0)
        XCTAssertNil(model.artistImage)

        model.loadsArtistImages = true
        try await waitUntil { model.artistImage != nil }
        model.loadsArtistImages = false
        XCTAssertNil(model.artistImage)
    }

    func testAnUnreadableArtistIsNotAskedAgain() async throws {
        let playback = try PlaybackJSON().data()
        let (model, recorder) = makeModel { [artistPath] request in
            if request.url?.path == artistPath { return (.stub(404), Data()) }
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            if request.url?.path.hasPrefix("/v1/playlists") == true { return (.stub(404), Data()) }
            return (.stub(200), playback)
        }
        await model.poll()
        try await waitUntil { self.requests(recorder, path: artistPath) == 1 }
        try await Task.sleep(nanoseconds: 100_000_000)
        await model.poll()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(requests(recorder, path: artistPath), 1)
        XCTAssertNil(model.artistImage)
    }

    func testArtistImagesRequest() async throws {
        let (session, recorder) = StubURLProtocol.session { _ in
            (.stub(200), Data(#"{"images":[{"url":"https://i.scdn.co/image/x","width":null,"height":null}]}"#.utf8))
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let images = try await api.artistImages(id: "abc123")
        XCTAssertEqual(images, [SpotifyImage(url: "https://i.scdn.co/image/x")])
        XCTAssertEqual(recorder.requests.first?.url?.path, "/v1/artists/abc123")
        XCTAssertEqual(recorder.requests.first?.httpMethod, "GET")
    }
}
