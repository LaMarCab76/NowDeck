import XCTest
@testable import Nowdeck

/// Dispositivos: decoding, the list order, the transfer request and the sheet's states.
@MainActor
final class DevicesTests: XCTestCase {
    private func makeAPI(
        clock: TestClock = TestClock(),
        handler: @escaping StubURLProtocol.Handler
    ) -> (SpotifyAPI, StubRecorder) {
        let (session, recorder) = StubURLProtocol.session(handler: handler)
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, now: { clock.now },
                             sleep: { _ in }, jitter: { 0 })
        return (api, recorder)
    }

    private static func device(_ name: String, id: String? = nil, type: String = "Computer",
                               active: Bool = false, restricted: Bool = false,
                               privateSession: Bool? = nil) -> SpotifyDevice {
        SpotifyDevice(id: id ?? name.lowercased(), isActive: active,
                      isPrivateSession: privateSession, isRestricted: restricted, name: name,
                      type: type)
    }

    nonisolated private static func devicesJSON(_ devices: [[String: Any]]) -> Data {
        try! JSONSerialization.data(withJSONObject: ["devices": devices])
    }

    nonisolated private static let threeDevices = devicesJSON([
        ["id": "tv", "is_active": false, "is_private_session": false, "is_restricted": false,
         "name": "Tele del cuarto", "type": "TV", "volume_percent": 30, "supports_volume": true],
        ["id": "mac", "is_active": true, "is_private_session": false, "is_restricted": false,
         "name": "MacBook Pro", "type": "Computer", "volume_percent": 70,
         "supports_volume": true],
        ["id": "speaker", "is_active": false, "is_private_session": false,
         "is_restricted": false, "name": "Parlante del living", "type": "Speaker",
         "volume_percent": NSNull(), "supports_volume": false],
    ])

    // MARK: Decoding

    func testDecodesReferenceExample() async throws {
        let fixture = try Fixture.data("devices-reference")
        let (api, recorder) = makeAPI { _ in (.stub(200), fixture) }

        let devices = try await api.availableDevices()

        XCTAssertEqual(devices, [
            SpotifyDevice(id: "string", isActive: false, isPrivateSession: false,
                          isRestricted: false, name: "Kitchen speaker", type: "computer",
                          volumePercent: 59, supportsVolume: false),
        ])
        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://api.spotify.com/v1/me/player/devices")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-0")
    }

    func testDecodesNullIDAndVolumeAndMissingList() async throws {
        let json = Self.devicesJSON([
            ["id": NSNull(), "is_active": false, "is_restricted": true, "name": "Auto",
             "type": "Automobile", "volume_percent": NSNull()],
        ])
        let (api, _) = makeAPI { _ in (.stub(200), json) }
        let devices = try await api.availableDevices()
        XCTAssertNil(devices.first?.id)
        XCTAssertNil(devices.first?.volumePercent)
        XCTAssertEqual(devices.first?.isRestricted, true)
        XCTAssertEqual(devices.first?.acceptsTransfer, false)

        let (emptyAPI, _) = makeAPI { _ in (.stub(200), Data("{}".utf8)) }
        let none = try await emptyAPI.availableDevices()
        XCTAssertEqual(none, [])
    }

    // MARK: Order and active device

    func testActiveDeviceGoesToTheHeaderAndTheRestAreSorted() {
        let choices = DeviceChoices(devices: [
            Self.device("Tele del cuarto", type: "TV"),
            Self.device("auto", restricted: true),
            Self.device("MacBook Pro", active: true),
            Self.device("escritorio-linux"),
            Self.device("Parlante del living", type: "Speaker"),
        ])

        XCTAssertEqual(choices.current?.name, "MacBook Pro")
        XCTAssertEqual(choices.others.map(\.name),
                       ["escritorio-linux", "Parlante del living", "Tele del cuarto", "auto"],
                       "By name, ignoring case; restricted devices last")
        XCTAssertFalse(choices.isEmpty)
    }

    func testDeviceWithoutIDGoesLastAndCannotTakePlayback() {
        let noID = SpotifyDevice(id: nil, isActive: false, name: "Antiguo", type: "Speaker")
        let choices = DeviceChoices(devices: [noID, Self.device("Zeta")])
        XCTAssertNil(choices.current)
        XCTAssertEqual(choices.others.map(\.name), ["Zeta", "Antiguo"])
        XCTAssertFalse(noID.acceptsTransfer)
    }

    func testOnlyOneActiveDeviceIsTaken() {
        let choices = DeviceChoices(devices: [Self.device("A", active: true),
                                              Self.device("B", active: true)])
        XCTAssertEqual(choices.current?.name, "A")
        XCTAssertEqual(choices.others.map(\.name), ["B"])
    }

    func testEmptyList() {
        XCTAssertTrue(DeviceChoices(devices: []).isEmpty)
        XCTAssertFalse(DeviceChoices(devices: [Self.device("A", active: true)]).isEmpty)
    }

    func testPrivateSession() {
        XCTAssertTrue(Self.device("A", privateSession: true).isInPrivateSession)
        XCTAssertFalse(Self.device("A", privateSession: nil).isInPrivateSession)
    }

    // MARK: Transfer request

    func testTransferSendsOneDeviceAndPlay() async throws {
        let (api, recorder) = makeAPI { _ in (.stub(204), Data()) }

        try await api.transferPlayback(to: "74ASZWbe4lXaubB36ztrGX", play: true)

        let request = try XCTUnwrap(recorder.requests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.absoluteString, "https://api.spotify.com/v1/me/player")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.httpBody)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["device_ids"] as? [String], ["74ASZWbe4lXaubB36ztrGX"])
        XCTAssertEqual(object["play"] as? Bool, true)
        XCTAssertEqual(object.count, 2)
    }

    func testTransferIsNotRetriedAfterServerError() async throws {
        let (api, recorder) = makeAPI { _ in (.stub(503), Data()) }
        do {
            try await api.transferPlayback(to: "tv", play: true)
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SpotifyAPIError, .server(status: 503))
        }
        XCTAssertEqual(recorder.requests.count, 1, "Commands are not retried")
    }

    // MARK: Sheet model

    func testReloadShowsSortedListAndActiveDevice() async {
        let (api, _) = makeAPI { _ in (.stub(200), Self.threeDevices) }
        let initial = Self.device("MacBook Pro", id: "mac", active: true)
        let model = DevicesModel(api: api, initialDevice: initial)
        XCTAssertEqual(model.currentDevice, initial, "The player's device while loading")
        XCTAssertNil(model.choices)

        await model.reload()

        XCTAssertEqual(model.currentDevice?.id, "mac")
        XCTAssertEqual(model.choices?.others.map(\.id), ["speaker", "tv"])
        XCTAssertNil(model.problem)
        XCTAssertFalse(model.isLoading)
    }

    func testEmptyAnswerLeavesNoCurrentDevice() async {
        let (api, _) = makeAPI { _ in (.stub(200), Self.devicesJSON([])) }
        let model = DevicesModel(api: api, initialDevice: Self.device("Viejo", active: true))
        await model.reload()
        XCTAssertEqual(model.choices?.isEmpty, true)
        XCTAssertNil(model.currentDevice, "After loading, the list decides")
    }

    func testForbiddenListShowsGenericProblem() async {
        let (api, _) = makeAPI { _ in
            (.stub(403), spotifyErrorJSON(status: 403, message: "Forbidden"))
        }
        let model = DevicesModel(api: api)
        await model.reload()
        XCTAssertNil(model.choices)
        XCTAssertEqual(model.problem, .forbidden)
    }

    func testRateLimitedListIsNotAskedAgainBeforeRetryAfter() async {
        let clock = TestClock()
        let (api, recorder) = makeAPI(clock: clock) { _ in
            (.stub(429, headers: ["Retry-After": "20"]), Data())
        }
        let model = DevicesModel(api: api)

        await model.reload()
        XCTAssertEqual(model.problem, .rateLimited)

        // "Actualizar lista" before Retry-After passes: no request leaves the app.
        clock.advance(5)
        await model.reload()
        XCTAssertEqual(model.problem, .rateLimited)
        XCTAssertEqual(recorder.requests.count, 1)
    }

    func testFailedReloadKeepsTheListOnScreen() async {
        let fail = LockedFlag()
        let (api, _) = makeAPI { _ in
            if fail.value { throw URLError(.notConnectedToInternet) }
            return (.stub(200), Self.threeDevices)
        }
        let model = DevicesModel(api: api)
        await model.reload()
        fail.value = true
        await model.reload()
        XCTAssertEqual(model.choices?.others.count, 2)
        XCTAssertEqual(model.problem, .connection)
    }

    func testSuccessfulTransferNotifiesOnce() async throws {
        let (api, recorder) = makeAPI { request in
            request.httpMethod == "PUT" ? (.stub(204), Data()) : (.stub(200), Self.threeDevices)
        }
        var notifications = 0
        let model = DevicesModel(api: api, onTransferred: { notifications += 1 })
        await model.reload()

        let target = try XCTUnwrap(model.choices?.others.first { $0.id == "tv" })
        let accepted = await model.transfer(to: target)

        XCTAssertTrue(accepted)
        XCTAssertEqual(notifications, 1)
        XCTAssertNil(model.transferringID)
        let put = try XCTUnwrap(recorder.requests.first { $0.httpMethod == "PUT" })
        let body = try JSONDecoder().decode(TransferBodyProbe.self, from: XCTUnwrap(put.httpBody))
        XCTAssertEqual(body, TransferBodyProbe(device_ids: ["tv"], play: true))
    }

    func testRestrictedDeviceIsNeverSent() async {
        let (api, recorder) = makeAPI { _ in (.stub(204), Data()) }
        var notifications = 0
        let model = DevicesModel(api: api, onTransferred: { notifications += 1 })

        let accepted = await model.transfer(to: Self.device("Auto", restricted: true))

        XCTAssertFalse(accepted)
        XCTAssertEqual(notifications, 0)
        XCTAssertTrue(recorder.requests.isEmpty)
    }

    func testForbiddenTransferKeepsSheetOpen() async {
        let (api, _) = makeAPI { request in
            request.httpMethod == "PUT"
                ? (.stub(403), spotifyErrorJSON(status: 403, message: "Player command failed"))
                : (.stub(200), Self.threeDevices)
        }
        var notifications = 0
        let model = DevicesModel(api: api, onTransferred: { notifications += 1 })
        await model.reload()

        let accepted = await model.transfer(to: Self.device("Tele", id: "tv"))

        XCTAssertFalse(accepted)
        XCTAssertEqual(model.problem, .forbidden)
        XCTAssertEqual(notifications, 0, "No refresh when the transfer failed")
    }

    func testDeviceGoneReloadsTheList() async {
        let (api, recorder) = makeAPI { request in
            request.httpMethod == "PUT"
                ? (.stub(404), spotifyErrorJSON(status: 404, message: "Device not found"))
                : (.stub(200), Self.threeDevices)
        }
        let model = DevicesModel(api: api)

        let accepted = await model.transfer(to: Self.device("Viejo", id: "old"))

        XCTAssertFalse(accepted)
        XCTAssertEqual(model.problem, .deviceGone, "The explanation survives the reload")
        XCTAssertEqual(recorder.requests.filter { $0.httpMethod == "GET" }.count, 1)
        XCTAssertEqual(model.choices?.others.count, 2)
    }

    func testRateLimitedTransfer() async {
        let (api, _) = makeAPI { _ in (.stub(429, headers: ["Retry-After": "3"]), Data()) }
        let model = DevicesModel(api: api)
        let accepted = await model.transfer(to: Self.device("Tele", id: "tv"))
        XCTAssertFalse(accepted)
        XCTAssertEqual(model.problem, .rateLimited)
    }

    func testProblemMapping() {
        XCTAssertEqual(DevicesProblem(SpotifyAPIError.network(.timedOut), duringTransfer: false),
                       .connection)
        XCTAssertEqual(DevicesProblem(SpotifyAPIError.server(status: 502), duringTransfer: true),
                       .connection)
        XCTAssertEqual(DevicesProblem(SpotifyAPIError.notFound(message: nil),
                                      duringTransfer: false), .unknown)
        XCTAssertEqual(DevicesProblem(SpotifyAPIError.http(status: 400, message: nil),
                                      duringTransfer: true), .unknown)
    }

    // MARK: Player refresh

    /// The presenter's hook: after a transfer the player polls `GET /me/player` again and
    /// shows the new device.
    func testTransferRefreshesThePlayer() async throws {
        let transferred = LockedFlag()
        let playback = try Fixture.data("playback-state-playing")
        let (session, recorder) = StubURLProtocol.session { request in
            if request.httpMethod == "PUT" {
                transferred.value = true
                return (.stub(204), Data())
            }
            if request.url?.path == "/v1/me/player" {
                // Before the transfer nothing plays; after it, the playlist does.
                return transferred.value ? (.stub(200), playback) : (.stub(204), Data())
            }
            return (.stub(404), Data())
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, sleep: { _ in },
                             jitter: { 0 })
        let player = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session))
        await player.poll()
        XCTAssertEqual(player.status, .nothingPlaying)

        let model = DevicesModel(api: api, onTransferred: { [weak player] in
            player?.refresh(after: 0)
        })
        let accepted = await model.transfer(to: Self.device("Tele", id: "tv"))
        XCTAssertTrue(accepted)

        let deadline = Date().addingTimeInterval(2)
        while player.status != .active, Date() < deadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        player.stop()
        XCTAssertEqual(player.status, .active)
        let polls = recorder.requests.filter { $0.url?.path == "/v1/me/player"
            && $0.httpMethod == "GET" }
        XCTAssertGreaterThanOrEqual(polls.count, 2)
        XCTAssertEqual(DevicesSheetPresenter.playerRefreshDelay, 0.6,
                       "Same ~600 ms as the other commands (docs/03)")
    }
}

/// A Bool shared with the stub's handler, which runs on another thread.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private struct TransferBodyProbe: Decodable, Equatable {
    let device_ids: [String]
    let play: Bool
}
