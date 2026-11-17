import XCTest
@testable import Nowdeck

/// Milestone 8: what VoiceOver hears from the volume panel.
@MainActor
final class VolumeAnnouncementTests: XCTestCase {
    private func makeVolume() -> VolumeController {
        let (session, _) = StubURLProtocol.session { _ in (.stub(204), Data()) }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session,
                             sleep: { _ in }, jitter: { 0 })
        return VolumeController(api: api, debounce: 0.05, hideAfter: 30)
    }

    private func device(_ volume: Int?, supportsVolume: Bool? = true) -> SpotifyDevice {
        SpotifyDevice(id: "device-1", isRestricted: false, name: "MacBook Pro", type: "Computer",
                      volumePercent: volume, supportsVolume: supportsVolume)
    }

    func testNothingIsAnnouncedWhileThePanelIsHidden() {
        let volume = makeVolume()
        volume.observe(device(50))
        XCTAssertNil(volume.announcement)
    }

    func testTapsAnnounceTheNewLevel() {
        let volume = makeVolume()
        volume.observe(device(50))
        volume.increase()
        volume.increase()
        XCTAssertEqual(volume.announcement, .level(60))
        volume.hidePanel()
        XCTAssertNil(volume.announcement)
    }

    func testAChangeFromAnotherDeviceIsAnnounced() {
        let volume = makeVolume()
        volume.observe(device(50))
        volume.observe(device(35))
        XCTAssertEqual(volume.announcement, .level(35))
    }

    func testDevicesWithoutVolumeControlSaySo() {
        let volume = makeVolume()
        volume.observe(device(50, supportsVolume: false))
        volume.toggleButton()
        XCTAssertEqual(volume.announcement, .notAdjustable)
    }

    func testNoDevice() {
        XCTAssertEqual(VolumeAnnouncement(isPanelVisible: true, level: nil, isAdjustable: false,
                                          hasDevice: false), .noDevice)
    }

    func testMessagesMatchThePanel() {
        XCTAssertEqual(String(localized: VolumeAnnouncement.level(45).message), "Volumen: 45 de 100")
        XCTAssertEqual(String(localized: VolumeAnnouncement.notAdjustable.message),
                       "Este dispositivo no permite cambiar el volumen")
        XCTAssertEqual(String(localized: VolumeAnnouncement.noDevice.message),
                       "No hay un dispositivo activo")
    }
}
