import XCTest
@testable import Nowdeck

@MainActor
final class VolumeControllerTests: XCTestCase {
    private func make(status: Int = 204, settleTime: TimeInterval = 3)
        -> (VolumeController, StubRecorder, TestClock, StubBox<Int>) {
        let statusBox = StubBox(status)
        let clock = TestClock()
        let (session, recorder) = StubURLProtocol.session { _ in
            let status = statusBox.value
            return (.stub(status), status == 204 ? Data() : spotifyErrorJSON(status: status, message: "x"))
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, now: { clock.now },
                             sleep: { _ in }, jitter: { 0 })
        // A long hide delay, so the tests decide when the panel closes (`hidePanel()`).
        let volume = VolumeController(api: api, debounce: 0.05, hideAfter: 30,
                                      settleTime: settleTime, now: { clock.now })
        return (volume, recorder, clock, statusBox)
    }

    private func device(_ volume: Int?, id: String = "device-1", supportsVolume: Bool? = true,
                        isRestricted: Bool = false) -> SpotifyDevice {
        SpotifyDevice(id: id, isRestricted: isRestricted, name: "MacBook Pro", type: "Computer",
                      volumePercent: volume, supportsVolume: supportsVolume)
    }

    private func sentLevels(_ recorder: StubRecorder) -> [String?] {
        recorder.requests.map { $0.queryValue("volume_percent") }
    }

    // MARK: Coalescing

    func testQuickTapsSendOneRequestWithTheFinalLevel() async throws {
        let (volume, recorder, _, _) = make()
        volume.observe(device(50))

        volume.increase()
        volume.increase()
        volume.increase()
        XCTAssertEqual(volume.level, 65, "Every tap moves the level at once")
        XCTAssertTrue(volume.isPanelVisible)

        try await eventually { !recorder.requests.isEmpty }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recorder.requests.map(\.commandLine), ["PUT /me/player/volume"])
        XCTAssertEqual(sentLevels(recorder), ["65"])
    }

    func testTapsAfterTheWaitSendAnotherRequest() async throws {
        let (volume, recorder, _, _) = make()
        volume.observe(device(50))
        volume.decrease()
        try await eventually { recorder.requests.count == 1 }
        volume.decrease()
        try await eventually { recorder.requests.count == 2 }
        XCTAssertEqual(sentLevels(recorder), ["45", "40"])
    }

    func testLevelStaysBetweenZeroAndOneHundred() async throws {
        let (volume, recorder, _, _) = make()
        volume.observe(device(98))
        volume.increase()
        XCTAssertEqual(volume.level, 100)
        volume.increase()
        XCTAssertEqual(volume.level, 100)
        try await eventually { recorder.requests.count == 1 }
        XCTAssertEqual(sentLevels(recorder), ["100"])
    }

    // MARK: External changes

    func testChangeFromAnotherDeviceShowsThePanel() {
        let (volume, _, _, _) = make()
        volume.observe(device(50))
        XCTAssertFalse(volume.isPanelVisible, "The first reading is not a change")
        volume.observe(device(50))
        XCTAssertFalse(volume.isPanelVisible)

        volume.observe(device(35))
        XCTAssertTrue(volume.isPanelVisible)
        XCTAssertEqual(volume.level, 35)
    }

    func testSwitchingDevicesIsNotAVolumeChange() {
        let (volume, _, _, _) = make()
        volume.observe(device(50, id: "a"))
        volume.observe(device(20, id: "b"))
        XCTAssertFalse(volume.isPanelVisible)
        XCTAssertEqual(volume.level, 20)
    }

    func testOldPollsAfterATapAreIgnored() async throws {
        let (volume, recorder, clock, _) = make()
        volume.observe(device(50))
        volume.increase()
        try await eventually { recorder.requests.count == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)
        volume.hidePanel()

        // Spotify has not applied it yet: the poll still says 50.
        volume.observe(device(50))
        XCTAssertEqual(volume.level, 55, "The user's level stays on screen")
        XCTAssertFalse(volume.isPanelVisible, "Not an external change")

        // It catches up.
        volume.observe(device(55))
        XCTAssertEqual(volume.level, 55)
        XCTAssertFalse(volume.isPanelVisible)

        // From now on a different level is a real external change.
        clock.advance(10)
        volume.observe(device(30))
        XCTAssertTrue(volume.isPanelVisible)
        XCTAssertEqual(volume.level, 30)
    }

    func testPollsDuringTheWaitBeforeSendingAreIgnored() {
        let (volume, _, _, _) = make()
        volume.observe(device(50))
        volume.increase()
        volume.observe(device(50))
        XCTAssertEqual(volume.level, 55)
    }

    func testAfterTheSettleTimeSpotifyWins() async throws {
        let (volume, recorder, clock, _) = make(settleTime: 3)
        volume.observe(device(50))
        volume.increase()
        try await eventually { recorder.requests.count == 1 }
        try await Task.sleep(nanoseconds: 50_000_000)

        clock.advance(4)
        // The device never applied it (or capped it): show what it really has.
        volume.observe(device(50))
        XCTAssertEqual(volume.level, 50)
    }

    // MARK: Failures

    func testFailedRequestGoesBackAndReports() async throws {
        let (volume, recorder, _, _) = make(status: 403)
        var failures: [Error] = []
        volume.onFailure = { failures.append($0) }
        volume.observe(device(50))

        volume.increase()
        XCTAssertEqual(volume.level, 55)

        try await eventually { failures.count == 1 }
        XCTAssertEqual(volume.level, 50)
        XCTAssertEqual(recorder.requests.count, 1, "Not retried")
        XCTAssertEqual(failures.first as? SpotifyAPIError, .forbidden(message: "x"))
    }

    // MARK: Devices that can't change the volume

    func testDeviceWithoutVolumeSupport() async throws {
        let (volume, recorder, _, _) = make()
        volume.observe(device(100, supportsVolume: false))
        XCTAssertFalse(volume.isAdjustable)

        volume.toggleButton()
        XCTAssertTrue(volume.isPanelVisible, "The panel opens to say why")
        volume.increase()
        volume.decrease()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recorder.requests.count, 0)
        XCTAssertEqual(volume.level, 100)
    }

    func testRestrictedDevice() async throws {
        let (volume, recorder, _, _) = make()
        volume.observe(device(40, isRestricted: true))
        XCTAssertFalse(volume.isAdjustable)
        volume.increase()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(recorder.requests.count, 0)
    }

    func testUnknownLevelCannotBeChanged() {
        let (volume, _, _, _) = make()
        volume.observe(device(nil))
        XCTAssertFalse(volume.isAdjustable)
        XCTAssertNil(volume.level)
    }

    func testNoDevice() {
        let (volume, _, _, _) = make()
        volume.observe(device(50))
        volume.toggleButton()
        volume.observe(nil)
        XCTAssertFalse(volume.hasDevice)
        XCTAssertFalse(volume.isPanelVisible)
    }

    // MARK: Panel

    func testButtonOpensAndClosesThePanel() {
        let (volume, _, _, _) = make()
        volume.observe(device(50))
        volume.toggleButton()
        XCTAssertTrue(volume.isPanelVisible)
        volume.toggleButton()
        XCTAssertFalse(volume.isPanelVisible)
    }

    func testPanelHidesAfterTheDelay() async throws {
        let (session, _) = StubURLProtocol.session { _ in (.stub(204), Data()) }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session)
        let volume = VolumeController(api: api, hideAfter: 0.1)
        volume.observe(device(50))
        volume.toggleButton()
        XCTAssertTrue(volume.isPanelVisible)
        try await eventually { !volume.isPanelVisible }
    }
}
