import UIKit
import XCTest
@testable import Nowdeck

/// The track swipe that shows the next or previous item (owner's request, 2026-11-17): the
/// pages' offsets, the next item from `GET /me/player/queue` and the previous one from the
/// app's own history.
@MainActor
final class TrackSwipeTests: XCTestCase {
    // MARK: Gesture

    func testDirectionPicksTheItem() {
        let left = TrackSwipe(translation: -50)
        XCTAssertEqual(left.edge, .right, "Dragging left brings the next item from the right")
        XCTAssertEqual(left.distance, 50)
        XCTAssertFalse(left.isCommitted)
        XCTAssertEqual(TrackSwipe(translation: 120).edge, .left)
        XCTAssertTrue(TrackSwipe(translation: TrackSwipe.commitDistance).isCommitted)
    }

    func testStartsAnywhereInTheBandAndOnlyHorizontally() {
        let band: ClosedRange<CGFloat> = 64...280
        let sideways = CGSize(width: -12, height: 3)
        for x: CGFloat in [10, 450, 886] {
            XCTAssertTrue(TrackSwipe.canStart(at: CGPoint(x: x, y: 150), translation: sideways,
                                              band: band),
                          "Anywhere across the cover and title, edge to edge (x \(x))")
        }
        XCTAssertFalse(TrackSwipe.canStart(at: CGPoint(x: 450, y: 360), translation: sideways,
                                           band: band),
                       "Not on the progress bar or the controls")
        XCTAssertFalse(TrackSwipe.canStart(at: CGPoint(x: 880, y: 360), translation: sideways,
                                           band: band),
                       "Not even next to a side edge, outside the band")
        XCTAssertFalse(TrackSwipe.canStart(at: CGPoint(x: 450, y: 150),
                                           translation: CGSize(width: 4, height: 10), band: band),
                       "A vertical drag is not a swipe")
        XCTAssertFalse(TrackSwipe.canStart(at: CGPoint(x: 450, y: 150), translation: sideways,
                                           band: nil))
    }

    func testAFlickCommitsEarlyOnlyInItsDirection() {
        let short = TrackSwipe(translation: -40)
        XCTAssertFalse(short.commitsOnRelease(predictedTranslation: -60))
        XCTAssertTrue(short.commitsOnRelease(predictedTranslation: -TrackSwipe.flickDistance))
        XCTAssertFalse(short.commitsOnRelease(predictedTranslation: TrackSwipe.flickDistance),
                       "Flicked back the other way")
    }

    // MARK: Page offsets

    func testPagesFollowTheFingerAndLandOneScreenAway() {
        let width: CGFloat = 896
        XCTAssertEqual(TrackSwipePhase.idle.offset(pageWidth: width), 0)
        XCTAssertEqual(TrackSwipePhase.dragging(edge: .right, distance: 120, isAllowed: true)
                           .offset(pageWidth: width), -120, "From the right edge: moves left")
        XCTAssertEqual(TrackSwipePhase.dragging(edge: .left, distance: 120, isAllowed: true)
                           .offset(pageWidth: width), 120)
        XCTAssertEqual(TrackSwipePhase.dragging(edge: .left, distance: 2_000, isAllowed: true)
                           .offset(pageWidth: width), width, "Never past the preview")
        XCTAssertEqual(TrackSwipePhase.landing(edge: .right, preview: nil, fromKey: nil)
                           .offset(pageWidth: width), -width)
    }

    func testAForbiddenSkipOnlyResists() {
        let phase = TrackSwipePhase.dragging(edge: .right, distance: 90, isAllowed: false)
        XCTAssertEqual(phase.offset(pageWidth: 896), -30)
        let far = TrackSwipePhase.dragging(edge: .right, distance: 600, isAllowed: false)
        XCTAssertEqual(far.offset(pageWidth: 896), -TrackSwipePhase.maxResisted)
    }

    // MARK: Previews in the model

    nonisolated private static let nextCover = "https://i.scdn.co/image/next-cover"

    nonisolated private static let png: Data = {
        UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }()

    /// The fixture's track with another name, ID and cover.
    nonisolated private static func otherTrack() throws -> [String: Any] {
        let playback = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: PlaybackJSON().data()) as? [String: Any])
        var item = try XCTUnwrap(playback["item"] as? [String: Any])
        item["name"] = "Siguiente Tema"
        item["id"] = "nextTrack0000000000000"
        item["uri"] = "spotify:track:nextTrack0000000000000"
        item["external_urls"] = ["spotify": "https://open.spotify.com/track/nextTrack0000000000000"]
        var album = try XCTUnwrap(item["album"] as? [String: Any])
        album["id"] = "nextAlbum0000000000000"
        album["images"] = [["url": nextCover, "width": 640, "height": 640]]
        item["album"] = album
        return item
    }

    nonisolated private static func playback(playingOther: Bool) throws -> Data {
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: PlaybackJSON().data()) as? [String: Any])
        if playingOther { object["item"] = try otherTrack() }
        return try JSONSerialization.data(withJSONObject: object)
    }

    nonisolated private static func queue() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["currently_playing": NSNull(),
                                                    "queue": [try otherTrack()]])
    }

    /// Which item `GET /me/player` reports, switched by the test.
    private final class Playing: @unchecked Sendable {
        private let lock = NSLock()
        private var other = false
        var playsOther: Bool {
            get { lock.withLock { other } }
            set { lock.withLock { other = newValue } }
        }
    }

    private func makeModel(queueStatus: Int = 200) -> (PlayerModel, StubRecorder, Playing) {
        let playing = Playing()
        let (session, recorder) = StubURLProtocol.session { request in
            let path = request.url?.path ?? ""
            if request.url?.host == "i.scdn.co" { return (.stub(200), Self.png) }
            if path == "/v1/me/player/queue" {
                return queueStatus == 200 ? (.stub(200), try Self.queue()) : (.stub(queueStatus), Data())
            }
            if path.hasPrefix("/v1/playlists") { return (.stub(404), Data()) }
            return (.stub(200), try Self.playback(playingOther: playing.playsOther))
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let model = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        model.loadsArtistImages = false
        return (model, recorder, playing)
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("Timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func queueRequests(_ recorder: StubRecorder) -> Int {
        recorder.requests.filter { $0.url?.path == "/v1/me/player/queue" }.count
    }

    func testUpNextIsTheFirstQueueItemWithItsCover() async throws {
        let (model, recorder, _) = makeModel()
        await model.poll()
        try await waitUntil { model.upNext?.artwork != nil }
        XCTAssertEqual(model.upNext?.item.title, "Siguiente Tema")
        XCTAssertNil(model.previousTrack, "Nothing seen before the first item")

        await model.poll()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(queueRequests(recorder), 1, "Read once per item, not on every poll")

        model.refreshUpNextIfStale()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(queueRequests(recorder), 1, "A fresh read is not repeated")
    }

    func testTheSwipedInItemShowsItsCoverAtOnceAndBecomesThePreviousOne() async throws {
        let (model, _, playing) = makeModel()
        await model.poll()
        let firstTitle = try XCTUnwrap(model.nowPlaying?.title)
        try await waitUntil { model.artwork != nil && model.upNext?.artwork != nil }

        playing.playsOther = true
        await model.poll()
        XCTAssertEqual(model.nowPlaying?.title, "Siguiente Tema")
        XCTAssertNotNil(model.artwork, "The preview's cover, without loading it again")
        XCTAssertEqual(model.previousTrack?.item.title, firstTitle)
        XCTAssertNotNil(model.previousTrack?.artwork)

        // Back to the first one: it leaves the history.
        playing.playsOther = false
        await model.poll()
        XCTAssertEqual(model.nowPlaying?.title, firstTitle)
        XCTAssertNil(model.previousTrack)
        XCTAssertNotNil(model.artwork, "Its cover was kept too")
    }

    func testAnUnreadableQueueOnlyLeavesThePreviewEmpty() async throws {
        let (model, recorder, _) = makeModel(queueStatus: 403)
        await model.poll()
        try await waitUntil { self.queueRequests(recorder) == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(model.upNext)
        XCTAssertEqual(model.status, .active)
    }

    func testQueueRequest() async throws {
        let (session, recorder) = StubURLProtocol.session { _ in
            (.stub(200), Data(#"{"currently_playing":null,"queue":null}"#.utf8))
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        let queue = try await api.playbackQueue()
        XCTAssertEqual(queue.queue, [], "A null list is an empty queue")
        XCTAssertEqual(recorder.requests.first?.url?.path, "/v1/me/player/queue")
        XCTAssertEqual(recorder.requests.first?.httpMethod, "GET")
    }
}
