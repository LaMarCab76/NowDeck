import XCTest
@testable import Nowdeck

/// A clock tests can move.
private final class LyricsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }
}

/// Records the waits the service asks for, without waiting.
private final class LyricsSleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [TimeInterval] = []

    var waits: [TimeInterval] { lock.withLock { recorded } }
    func record(_ seconds: TimeInterval) { lock.withLock { recorded.append(seconds) } }
}

private let foundJSON = Data("""
{"id": 7, "trackName": "Song", "artistName": "Artist", "albumName": "Album", "duration": 200,
 "instrumental": false, "hasWordSync": false, "plainLyrics": "One",
 "syncedLyrics": "[00:01.00] One", "lyricsfile": "version: '1.0'"}
""".utf8)

private func response(_ status: Int, retryAfter: String? = nil) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://lrclib.net/api/get")!, statusCode: status, httpVersion: nil,
                    headerFields: retryAfter.map { ["Retry-After": $0] })!
}

final class LyricsServiceTests: XCTestCase {
    private var directory: URL!
    private let clock = LyricsTestClock()

    private let track = LyricsTrack(spotifyID: "4uLU6hMCjMI75M1A2tKUQC", title: "Song", artist: "Artist",
                                    album: "Album", durationMs: 200_000)


    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LyricsServiceTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeCache() -> LyricsCache {
        LyricsCache(directory: directory, now: { [clock] in clock.now })
    }

    private func makeService(
        cache: LyricsCache? = nil,
        sleeps: LyricsSleepRecorder = LyricsSleepRecorder(),
        handler: @escaping StubURLProtocol.Handler
    ) -> (LyricsService, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let service = LyricsService(
            client: LRCLIBClient(session: session, userAgent: "Nowdeck/test (x)"),
            cache: cache ?? makeCache(),
            now: { [clock] in clock.now },
            jitter: { 0.3 },
            sleep: { seconds in sleeps.record(seconds) }
        )
        return (service, recorder)
    }

    // MARK: Cache

    func testFoundLyricsAreCachedBySpotifyID() async {
        let (service, recorder) = makeService { _ in (response(200), foundJSON) }

        let first = await service.lyrics(for: track)
        let second = await service.lyrics(for: track)
        guard case .found(let lyrics) = first else { return XCTFail("Expected lyrics, got \(first)") }
        XCTAssertEqual(lyrics.stanzas.map(\.text), ["One"])
        XCTAssertEqual(second, first)
        XCTAssertEqual(recorder.requests.count, 1, "The second lookup comes from the cache")
    }

    func testCacheSurvivesANewServiceInstance() async {
        let (service, _) = makeService { _ in (response(200), foundJSON) }
        _ = await service.lyrics(for: track)

        let (secondService, secondRecorder) = makeService { _ in (response(500), Data()) }
        let result = await secondService.lyrics(for: track)
        XCTAssertNotEqual(result, .failed)
        XCTAssertEqual(secondRecorder.requests.count, 0)
    }

    func testNotFoundIsCachedForSevenDays() async {
        let (service, recorder) = makeService { _ in (response(404), Data()) }

        let first = await service.lyrics(for: track)
        XCTAssertEqual(first, .notFound)
        clock.advance(6 * 24 * 3600)
        let cached = await service.lyrics(for: track)
        XCTAssertEqual(cached, .notFound)
        XCTAssertEqual(recorder.requests.count, 1)

        clock.advance(2 * 24 * 3600)
        _ = await service.lyrics(for: track)
        XCTAssertEqual(recorder.requests.count, 2, "After 7 days LRCLIB is asked again")
    }

    func testFoundLyricsExpireAfterThirtyDays() async {
        let cache = makeCache()
        await cache.store(LRCLIBRecord(id: 1, syncedLyrics: "[00:01.00] Old"), forSpotifyID: "abc")
        clock.advance(29 * 24 * 3600)
        let fresh = await cache.lookup(spotifyID: "abc")
        XCTAssertEqual(fresh, .found(LRCLIBRecord(id: 1, syncedLyrics: "[00:01.00] Old")))
        clock.advance(2 * 24 * 3600)
        let expired = await cache.lookup(spotifyID: "abc")
        XCTAssertEqual(expired, .miss)
    }

    func testPlainOnlyAnswerIsCachedAndShownAsNoLyrics() async {
        let plain = Data(#"{"id": 9, "instrumental": false, "hasWordSync": false, "plainLyrics": "Text", "syncedLyrics": null}"#.utf8)
        let (service, recorder) = makeService { _ in (response(200), plain) }
        let first = await service.lyrics(for: track)
        let second = await service.lyrics(for: track)
        XCTAssertEqual(first, .notFound)
        XCTAssertEqual(second, .notFound)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testErrorsAreNotCached() async {
        let (service, recorder) = makeService { _ in throw URLError(.notConnectedToInternet) }
        let first = await service.lyrics(for: track)
        let second = await service.lyrics(for: track)
        XCTAssertEqual(first, .failed)
        XCTAssertEqual(second, .failed)
        XCTAssertEqual(recorder.requests.count, 2)
    }

    func testTracksWithoutSpotifyIDAreNotCached() async {
        var local = track
        local.spotifyID = nil
        let (service, recorder) = makeService { _ in (response(200), foundJSON) }
        _ = await service.lyrics(for: local)
        _ = await service.lyrics(for: local)
        XCTAssertEqual(recorder.requests.count, 2)
    }

    func testUnsafeIDsNeverBecomeFileNames() async {
        let cache = makeCache()
        await cache.store(nil, forSpotifyID: "../../escape")
        let lookup = await cache.lookup(spotifyID: "../../escape")
        XCTAssertEqual(lookup, .miss)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path), "Nothing was written")
    }

    // MARK: Rate limit

    func testShortRetryAfterIsHonoredWithJitterAndRetriedOnce() async {
        let sleeps = LyricsSleepRecorder()
        let attempts = LyricsSleepRecorder()
        let (service, recorder) = makeService(sleeps: sleeps) { _ in
            attempts.record(0)
            if attempts.waits.count == 1 { return (response(429, retryAfter: "2"), Data()) }
            return (response(200), foundJSON)
        }

        let result = await service.lyrics(for: track)
        guard case .found = result else { return XCTFail("Expected lyrics, got \(result)") }
        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(sleeps.waits.count, 1)
        XCTAssertEqual(sleeps.waits[0], 2.6, accuracy: 0.001, "Retry-After plus 30 % jitter")
    }

    func testLongRetryAfterFailsAndBlocksRequestsUntilItPasses() async {
        let sleeps = LyricsSleepRecorder()
        let (service, recorder) = makeService(sleeps: sleeps) { _ in
            (response(429, retryAfter: "60"), Data())
        }

        let first = await service.lyrics(for: track)
        XCTAssertEqual(first, .failed)
        XCTAssertEqual(recorder.requests.count, 1)

        clock.advance(30)
        let blocked = await service.lyrics(for: track)
        XCTAssertEqual(blocked, .failed)
        XCTAssertEqual(recorder.requests.count, 1, "No request while Retry-After has not passed")
        XCTAssertTrue(sleeps.waits.isEmpty)

        clock.advance(60)
        _ = await service.lyrics(for: track)
        XCTAssertEqual(recorder.requests.count, 2)
    }
}
