import XCTest
@testable import Nowdeck

/// Cola: the request, decoding, the rows and the sheet's model.
@MainActor
final class QueueTests: XCTestCase {
    private func makeAPI(handler: @escaping StubURLProtocol.Handler) -> (SpotifyAPI, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let clock = TestClock()
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, now: { clock.now },
                             sleep: { _ in }, jitter: { 0 })
        return (api, recorder)
    }

    nonisolated private static func json(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object)
    }

    nonisolated private static func track(_ name: String, explicit: Bool = false) -> [String: Any] {
        ["type": "track", "name": name, "duration_ms": 200_000, "explicit": explicit,
         "is_local": false, "uri": "spotify:track:\(name.replacingOccurrences(of: " ", with: ""))",
         "artists": [["name": "Artista"]], "album": ["name": "Álbum", "images": []]]
    }

    // MARK: Request and decoding

    func testRequestsTheQueue() async throws {
        let fixture = try Fixture.data("queue-playing")
        let (api, recorder) = makeAPI { _ in (.stub(200), fixture) }

        _ = try await api.playbackQueue()

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.spotify.com/v1/me/player/queue")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-0")
    }

    func testDecodesTracksEpisodesAndUnknownTypes() async throws {
        let fixture = try Fixture.data("queue-playing")
        let (api, _) = makeAPI { _ in (.stub(200), fixture) }

        let queue = try await api.playbackQueue()

        guard case .track(let current) = queue.currentlyPlaying else {
            return XCTFail("Expected the current track")
        }
        XCTAssertEqual(current.name, "Vereda Mojada")
        XCTAssertEqual(queue.queue.count, 4)
        guard case .episode(let episode) = queue.queue[1] else {
            return XCTFail("Expected an episode")
        }
        XCTAssertEqual(episode.show?.name, "Sobremesa")
        XCTAssertEqual(queue.queue[3], .unsupported(type: "audiobook_chapter"))
    }

    func testNullCurrentItemAndMissingQueue() async throws {
        let (api, _) = makeAPI { _ in (.stub(200), Self.json(["currently_playing": NSNull()])) }

        let queue = try await api.playbackQueue()

        XCTAssertEqual(queue, PlaybackQueue(currentlyPlaying: nil, queue: []))
    }

    func testForbiddenIsReported() async {
        let (api, _) = makeAPI { _ in
            (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden"))
        }

        do {
            _ = try await api.playbackQueue()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(QueueProblem(error), .forbidden)
        }
    }

    // MARK: Rows

    func testRowsFromTheFixture() async throws {
        let fixture = try Fixture.data("queue-playing")
        let (api, _) = makeAPI { _ in (.stub(200), fixture) }
        let queue = try await api.playbackQueue()

        let entries = QueueEntry.entries(from: queue)

        // The audiobook chapter is skipped; numbers stay consecutive.
        XCTAssertEqual(entries.map(\.track.number), [1, 2, 3])

        let first = entries[0].track
        XCTAssertEqual(first.title, "Fiebre de Sábado")
        XCTAssertEqual(first.subtitle, "Club Atlántico, Nina Ferro")
        XCTAssertTrue(first.isExplicit)
        XCTAssertEqual(first.durationMs, 178_000)
        XCTAssertEqual(first.pageURL?.absoluteString,
                       "https://open.spotify.com/track/4iV5W9uYEdYUVa79Axb7Rh")
        XCTAssertEqual(entries[0].artworkURL?.absoluteString,
                       "https://i.scdn.co/image/ab67616d00001e02bbbbbbbbbbbbbbbbbbbbbbbb")

        let episode = entries[1]
        XCTAssertEqual(episode.track.title, "Charlas de domingo")
        XCTAssertEqual(episode.track.subtitle, "Sobremesa")
        XCTAssertEqual(episode.artworkURL?.absoluteString,
                       "https://i.scdn.co/image/ab67656300005f1fcccccccccccccccccccccccc")

        let local = entries[2]
        XCTAssertEqual(local.track.title, "Demo grabada en casa")
        XCTAssertFalse(local.track.isAvailable)
        XCTAssertNil(local.track.pageURL)
        XCTAssertNil(local.artworkURL)
    }

    func testAtMostTwentyRows() {
        let items = (1...30).map { PlaybackItem.track(SpotifyTrack(name: "Tema \($0)",
                                                                   durationMs: 1000)) }
        let entries = QueueEntry.entries(from: PlaybackQueue(queue: items))

        XCTAssertEqual(entries.count, 20)
        XCTAssertEqual(entries.last?.track.title, "Tema 20")
        XCTAssertEqual(entries.map(\.id), Array(0..<20))
    }

    func testItemsWithoutNameAreSkipped() {
        let entries = QueueEntry.entries(from: PlaybackQueue(queue: [
            .track(SpotifyTrack(name: "", durationMs: 1000)),
            .track(SpotifyTrack(name: "Con nombre", durationMs: 1000)),
        ]))

        XCTAssertEqual(entries.map(\.track.title), ["Con nombre"])
        XCTAssertEqual(entries.first?.track.number, 1)
    }

    func testThumbnailIsTheSmallestSharpImage() {
        let images = [
            SpotifyImage(url: "https://i.scdn.co/640", width: 640, height: 640),
            SpotifyImage(url: "https://i.scdn.co/64", width: 64, height: 64),
            SpotifyImage(url: "https://i.scdn.co/300", width: 300, height: 300),
        ]
        XCTAssertEqual(QueueEntry.thumbnail(images)?.absoluteString, "https://i.scdn.co/300")
    }

    func testThumbnailFallbacks() {
        // Only small images: the largest one.
        XCTAssertEqual(QueueEntry.thumbnail([
            SpotifyImage(url: "https://i.scdn.co/64", width: 64),
            SpotifyImage(url: "https://i.scdn.co/100", width: 100),
        ])?.absoluteString, "https://i.scdn.co/100")
        // No sizes: the first one.
        XCTAssertEqual(QueueEntry.thumbnail([
            SpotifyImage(url: "https://i.scdn.co/a"),
            SpotifyImage(url: "https://i.scdn.co/b"),
        ])?.absoluteString, "https://i.scdn.co/a")
        // Never a non-HTTPS address.
        XCTAssertNil(QueueEntry.thumbnail([SpotifyImage(url: "http://i.scdn.co/300", width: 300)]))
        XCTAssertNil(QueueEntry.thumbnail([]))
    }

    // MARK: Model

    func testReloadShowsTheRows() async {
        let body = Self.json(["currently_playing": NSNull(), "queue": [Self.track("Uno")]])
        let (api, _) = makeAPI { _ in (.stub(200), body) }
        let model = QueueModel(api: api)

        XCTAssertNil(model.entries)
        await model.reload()

        XCTAssertEqual(model.entries?.map(\.track.title), ["Uno"])
        XCTAssertNil(model.problem)
        XCTAssertFalse(model.isLoading)
    }

    func testEmptyQueue() async {
        let body = Self.json(["currently_playing": NSNull(), "queue": []])
        let (api, _) = makeAPI { _ in (.stub(200), body) }
        let model = QueueModel(api: api)

        await model.reload()

        XCTAssertEqual(model.entries, [])
    }

    func testFirstReadFails() async {
        let (api, _) = makeAPI { _ in throw URLError(.notConnectedToInternet) }
        let model = QueueModel(api: api)

        await model.reload()

        XCTAssertNil(model.entries)
        XCTAssertEqual(model.problem, .connection)
    }

    func testAFailureKeepsTheListAndASuccessClearsTheProblem() async {
        let ok = Self.json(["queue": [Self.track("Uno")]])
        let answers = AnswerQueue([
            .success((.stub(200), ok)),
            .success((.stub(429, headers: ["Retry-After": "0"]),
                      spotifyErrorJSON(status: 429, message: "Too many"))),
            .success((.stub(200), ok)),
        ])
        let (api, _) = makeAPI { _ in try answers.next() }
        let model = QueueModel(api: api)

        await model.reload()
        await model.reload()
        XCTAssertEqual(model.entries?.map(\.track.title), ["Uno"])
        XCTAssertEqual(model.problem, .rateLimited)

        await model.reload()
        XCTAssertNil(model.problem)
    }

    func testConcurrentReloadsShareOneRequest() async {
        let body = Self.json(["queue": []])
        let gate = FirstRequestGate(started: expectation(description: "first read started"))
        let (api, recorder) = makeAPI { _ in
            gate.pass()
            return (.stub(200), body)
        }
        let model = QueueModel(api: api)

        let first = Task { await model.reload() }
        await fulfillment(of: [gate.started], timeout: 2)
        // The first read is now waiting for its answer. The second reload joins it.
        let second = Task { await model.reload() }
        await Task.yield()
        gate.open()
        _ = await (first.value, second.value)

        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testTrackChangeAlwaysReadsAgain() async {
        let gate = FirstRequestGate(started: expectation(description: "first read started"))
        let answers = AnswerQueue([
            .success((.stub(200), Self.json(["queue": [Self.track("Viejo")]]))),
            .success((.stub(200), Self.json(["queue": [Self.track("Nuevo")]]))),
        ])
        let (api, recorder) = makeAPI { _ in
            gate.pass()
            return try answers.next()
        }
        let model = QueueModel(api: api)

        let first = Task { await model.reload() }
        await fulfillment(of: [gate.started], timeout: 2)
        // The track changes while the first read is still waiting: its answer may be old.
        let change = Task { await model.trackDidChange() }
        await Task.yield()
        gate.open()
        _ = await (first.value, change.value)

        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(model.entries?.map(\.track.title), ["Nuevo"])
    }

    func testSeveralTrackChangesDuringOneReadAskForOneMoreRead() async {
        let gate = FirstRequestGate(started: expectation(description: "first read started"))
        let answers = AnswerQueue([
            .success((.stub(200), Self.json(["queue": [Self.track("Viejo")]]))),
            .success((.stub(200), Self.json(["queue": [Self.track("Nuevo")]]))),
        ])
        let (api, recorder) = makeAPI { _ in
            gate.pass()
            return try answers.next()
        }
        let model = QueueModel(api: api)

        let first = Task { await model.reload() }
        await fulfillment(of: [gate.started], timeout: 2)
        // Two changes wait for the same read. They must not start two overlapping reads,
        // where the older answer could land last.
        let change1 = Task { await model.trackDidChange() }
        let change2 = Task { await model.trackDidChange() }
        await Task.yield()
        gate.open()
        _ = await (first.value, change1.value, change2.value)

        XCTAssertEqual(recorder.requests.count, 2)
        XCTAssertEqual(model.entries?.map(\.track.title), ["Nuevo"])
    }
}

/// Holds the first request open until the test calls `open()`, so the test can start a
/// second operation while that read is certainly still waiting. Later requests answer at
/// once.
private final class FirstRequestGate: @unchecked Sendable {
    let started: XCTestExpectation
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0

    init(started: XCTestExpectation) {
        self.started = started
    }

    /// Called by the stub on the loading thread for each request.
    func pass() {
        let isFirst = lock.withLock { () -> Bool in
            count += 1
            return count == 1
        }
        guard isFirst else { return }
        started.fulfill()
        release.wait()
    }

    func open() {
        release.signal()
    }
}

/// Hands out canned answers in order, one per request.
private final class AnswerQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [Result<(HTTPURLResponse, Data), Error>]

    init(_ answers: [Result<(HTTPURLResponse, Data), Error>]) {
        self.answers = answers
    }

    func next() throws -> (HTTPURLResponse, Data) {
        try lock.withLock { try answers.removeFirst().get() }
    }
}
