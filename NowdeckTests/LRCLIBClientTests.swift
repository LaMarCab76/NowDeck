import XCTest
@testable import Nowdeck

final class LRCLIBClientTests: XCTestCase {
    private let track = LyricsTrack(
        spotifyID: "4uLU6hMCjMI75M1A2tKUQC",
        title: "I Want to Live",
        artist: "Borislav Slavov",
        album: "Baldur's Gate 3 (Original Game Soundtrack)",
        durationMs: 233_412
    )

    /// Answer of the docs' `/api/get` example, shortened.
    private let recordJSON = Data("""
    {
      "id": 3396226,
      "name": "I Want to Live",
      "trackName": "I Want to Live",
      "artistName": "Borislav Slavov",
      "albumName": "Baldur's Gate 3 (Original Game Soundtrack)",
      "duration": 233.0,
      "instrumental": false,
      "hasWordSync": false,
      "plainLyrics": "I feel your breath upon my neck\\n",
      "syncedLyrics": "[00:17.12] I feel your breath upon my neck\\n[03:25.72] ",
      "lyricsfile": "version: '1.0'\\nmetadata:\\n  title: I Want to Live\\n  artist: Borislav Slavov\\n"
    }
    """.utf8)

    private func queryItems(_ request: URLRequest) -> [String: String] {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    // MARK: Request

    func testRequestFollowsTheDocumentedSignature() {
        let request = LRCLIBClient(userAgent: "Nowdeck/1.2.3 (x)").makeRequest(for: track)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.scheme, "https")
        XCTAssertEqual(request.url?.host, "lrclib.net")
        XCTAssertEqual(request.url?.path, "/api/get")
        XCTAssertEqual(queryItems(request), [
            "track_name": "I Want to Live",
            "artist_name": "Borislav Slavov",
            "album_name": "Baldur's Gate 3 (Original Game Soundtrack)",
            "duration": "233",
        ])
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Nowdeck/1.2.3 (x)")
    }

    func testDurationIsRoundedToWholeSeconds() {
        var track = track
        track.durationMs = 233_500
        XCTAssertEqual(queryItems(LRCLIBClient().makeRequest(for: track))["duration"], "234")
    }

    func testAlbumAndOutOfRangeDurationAreLeftOut() {
        var track = track
        track.album = " "
        track.durationMs = 3_700_000
        let items = queryItems(LRCLIBClient().makeRequest(for: track))
        XCTAssertNil(items["album_name"])
        XCTAssertNil(items["duration"], "LRCLIB rejects durations outside 1–3600 s")
    }

    func testPlusSignIsEncoded() {
        var track = track
        track.title = "1+1"
        let request = LRCLIBClient().makeRequest(for: track)
        XCTAssertTrue(request.url!.absoluteString.contains("track_name=1%2B1"))
        XCTAssertEqual(queryItems(request)["track_name"], "1+1")
    }

    func testDefaultUserAgentNamesTheAppVersionAndProjectPage() {
        XCTAssertEqual(LRCLIBClient.userAgent(version: "0.1.0"),
                       "Nowdeck/0.1.0 (https://github.com/<usuario>/Nowdeck)")
        XCTAssertTrue(LRCLIBClient.defaultUserAgent.hasPrefix("Nowdeck/"))
    }

    // MARK: Responses

    func testFoundRecordIsDecoded() async throws {
        let body = recordJSON
        let (session, recorder) = StubURLProtocol.session { _ in (.stub(200), body) }
        let record = try await LRCLIBClient(session: session).lyrics(for: track)
        XCTAssertEqual(record?.id, 3_396_226)
        XCTAssertEqual(record?.hasWordSync, false)
        XCTAssertEqual(record?.duration, 233)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testNotFoundReturnsNil() async throws {
        let body = Data(#"{"message":"Failed to find specified track","name":"TrackNotFound","statusCode":404}"#.utf8)
        let (session, _) = StubURLProtocol.session { _ in (.stub(404), body) }
        let record = try await LRCLIBClient(session: session).lyrics(for: track)
        XCTAssertNil(record)
    }

    func testRateLimitReadsRetryAfter() async {
        let (session, _) = StubURLProtocol.session { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                                           headerFields: ["Retry-After": "12"])!
            return (response, Data("Too many".utf8))
        }
        do {
            _ = try await LRCLIBClient(session: session).lyrics(for: track)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? LRCLIBError, .rateLimited(retryAfter: 12))
        }
    }

    func testServerErrorsAndBadBodiesThrow() async {
        for (status, body, expected) in [
            (500, Data(), LRCLIBError.server(status: 500)),
            (200, Data("not json".utf8), LRCLIBError.invalidResponse),
            (503, Data(), LRCLIBError.rateLimited(retryAfter: 1)),
        ] {
            let (session, _) = StubURLProtocol.session { _ in (.stub(status), body) }
            do {
                _ = try await LRCLIBClient(session: session).lyrics(for: track)
                XCTFail("Expected an error for \(status)")
            } catch {
                XCTAssertEqual(error as? LRCLIBError, expected)
            }
        }
    }

    func testNetworkErrorsAreReported() async {
        let (session, _) = StubURLProtocol.session { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await LRCLIBClient(session: session).lyrics(for: track)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? LRCLIBError, .network(.notConnectedToInternet))
        }
    }
}
