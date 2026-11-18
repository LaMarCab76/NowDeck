import Combine
import XCTest
@testable import Nowdeck

@MainActor
final class PlayerControlsModelTests: XCTestCase {
    private struct Harness {
        let model: PlayerModel
        let controls: PlayerControlsModel
        let recorder: StubRecorder
        /// What `GET /me/player` answers.
        let playback: StubBox<PlaybackJSON>
        /// Status of every command.
        let commandStatus: StubBox<Int>

        var commandRequests: [URLRequest] {
            recorder.requests.filter { $0.httpMethod != "GET" }
        }

        var commands: [String] {
            commandRequests.map(\.commandLine)
        }

        var playbackReads: Int {
            recorder.requests.filter { $0.httpMethod == "GET" && $0.url?.path == "/v1/me/player" }.count
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    /// A model with one poll answered, not polling on its own (unless the test starts it).
    private func make(_ initial: PlaybackJSON = PlaybackJSON(),
                      commandDelay: TimeInterval = 0,
                      commandGate: DispatchSemaphore? = nil) async throws -> Harness {
        let playback = StubBox(initial)
        let commandStatus = StubBox(204)
        let clock = TestClock()
        let (session, recorder) = StubURLProtocol.session { request in
            guard request.url?.host == "api.spotify.com" else { return (.stub(404), Data()) }
            let path = request.url?.path ?? ""
            if path.hasPrefix("/v1/playlists") { return (.stub(404), Data()) }
            if request.httpMethod == "GET" { return (.stub(200), try playback.value.data()) }
            if commandDelay > 0 { Thread.sleep(forTimeInterval: commandDelay) }
            // Commands wait here until the test signals the gate.
            commandGate?.wait()
            let status = commandStatus.value
            let body = status == 204 ? Data() : spotifyErrorJSON(status: status, message: "test")
            return (.stub(status), body)
        }
        let api = SpotifyAPI(tokens: FakeTokenProvider(), session: session, now: { clock.now },
                             sleep: { _ in }, jitter: { 0 })
        let model = PlayerModel(api: api, artworkLoader: ArtworkLoader(session: session),
                                now: { clock.now })
        let controls = PlayerControlsModel(player: model, confirmDelay: 0.05, noticeDuration: 30)
        addTeardownBlock { @MainActor in model.stop() }
        await model.poll()
        XCTAssertEqual(model.status, .active)
        return Harness(model: model, controls: controls, recorder: recorder,
                       playback: playback, commandStatus: commandStatus)
    }

    /// Lets queued commands run when the test expects nothing to happen.
    private func settle() async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    // MARK: Optimistic update and confirmation

    func testPauseChangesTheScreenAtOnceAndPollsAgainShortlyAfter() async throws {
        let h = try await make(PlaybackJSON(isPlaying: true))
        h.model.start()
        try await eventually { h.playbackReads >= 2 }
        let readsBefore = h.playbackReads

        h.controls.playPause()
        XCTAssertEqual(h.model.playback?.isPlaying, false, "Optimistic: no wait for Spotify")

        h.playback.value.isPlaying = false
        try await eventually { h.commands == ["PUT /me/player/pause"] }
        try await eventually("Polls again ~confirmDelay after the command") {
            h.playbackReads > readsBefore
        }
        XCTAssertEqual(h.model.playback?.isPlaying, false)
    }

    func testStartingThePlayerDuringACommandWaitsForTheCommand() async throws {
        // The pause stays on its way until the gate opens, whatever the executor's timing.
        let gate = DispatchSemaphore(value: 0)
        addTeardownBlock { gate.signal() } // never leave the stub blocked
        let h = try await make(PlaybackJSON(isPlaying: true), commandGate: gate)
        let readsBefore = h.playbackReads

        h.controls.playPause()
        // Cola opening, or the app coming back, while the pause is on its way.
        h.model.start()
        h.model.refresh()
        try await settle()
        XCTAssertEqual(h.playbackReads, readsBefore,
                       "A read during the command could undo the optimistic pause")
        XCTAssertEqual(h.model.playback?.isPlaying, false)

        // The command ends: its confirmation read restarts the polling.
        h.playback.value.isPlaying = false
        gate.signal()
        try await eventually { h.playbackReads > readsBefore }
        XCTAssertEqual(h.model.playback?.isPlaying, false)
    }

    func testACommandAfterARefreshStillResumesThePolling() async throws {
        let h = try await make(PlaybackJSON(isPlaying: true))
        h.model.start()
        // After a device transfer, Dispositivos asks for a fresh read.
        h.model.refresh()
        try await eventually { h.playbackReads >= 2 }

        h.controls.playPause()
        let readsAfterCommand = h.playbackReads
        h.playback.value.isPlaying = false
        try await eventually("The command's confirmation read and the polling come back") {
            h.playbackReads > readsAfterCommand
        }
    }

    func testPausingFreezesTheProgressWhereItIs() async throws {
        let h = try await make(PlaybackJSON(isPlaying: true, progressMs: 84_000))
        h.controls.playPause()
        XCTAssertEqual(h.model.playback?.progressMs, 84_000)
        XCTAssertEqual(h.model.currentPositionMs, 84_000)
    }

    func testFailedCommandRollsBackAndIsNotRetried() async throws {
        let h = try await make(PlaybackJSON(isPlaying: true))
        h.commandStatus.value = 500

        h.controls.playPause()
        XCTAssertEqual(h.model.playback?.isPlaying, false)

        try await eventually { h.model.playback?.isPlaying == true }
        XCTAssertEqual(h.commands, ["PUT /me/player/pause"], "Commands are never retried")
        XCTAssertEqual(h.controls.notice, .failed)
    }

    func testShuffleAndRepeatRollBack() async throws {
        let h = try await make(PlaybackJSON(shuffle: false, repeatState: "off"))
        h.commandStatus.value = 429

        h.controls.toggleShuffle()
        h.controls.cycleRepeat()
        XCTAssertEqual(h.model.playback?.shuffleState, true)
        XCTAssertEqual(h.model.playback?.repeatState, .context)

        try await eventually {
            h.model.playback?.shuffleState == false && h.model.playback?.repeatState == .off
        }
        XCTAssertEqual(h.controls.notice, .rateLimited)
    }

    func testRepeatSendsTheNextMode() async throws {
        let h = try await make(PlaybackJSON(repeatState: "context"))
        h.controls.cycleRepeat()
        XCTAssertEqual(h.model.playback?.repeatState, .track)
        try await eventually { h.commands.count == 1 }
        let request = try XCTUnwrap(h.commandRequests.last)
        XCTAssertEqual(request.commandLine, "PUT /me/player/repeat")
        XCTAssertEqual(request.queryValue("state"), "track")
    }

    func testCommandsGoOutInTheOrderTheyWereTapped() async throws {
        let h = try await make(PlaybackJSON(isPlaying: true), commandDelay: 0.1)
        h.controls.playPause()
        h.controls.playPause()
        XCTAssertEqual(h.model.playback?.isPlaying, true)
        try await eventually { h.commands.count == 2 }
        XCTAssertEqual(h.commands, ["PUT /me/player/pause", "PUT /me/player/play"])
    }

    func testNextAndPrevious() async throws {
        let h = try await make()
        h.controls.next()
        h.controls.previous()
        try await eventually { h.commands.count == 2 }
        XCTAssertEqual(h.commands, ["POST /me/player/next", "POST /me/player/previous"])
    }

    // MARK: Disallows

    func testForbiddenActionsAreNeverSent() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, shuffle: false,
                                            disallows: ["resuming", "skipping_next",
                                                        "skipping_prev", "toggling_shuffle",
                                                        "toggling_repeat_context",
                                                        "toggling_repeat_track"]))
        h.controls.playPause()
        h.controls.next()
        h.controls.previous()
        h.controls.toggleShuffle()
        h.controls.cycleRepeat()
        try await settle()

        XCTAssertEqual(h.commands, [])
        XCTAssertEqual(h.model.playback?.isPlaying, false)
        XCTAssertEqual(h.model.playback?.shuffleState, false)
    }

    func testRestrictedDeviceGetsNoCommands() async throws {
        let h = try await make(PlaybackJSON(isRestricted: true))
        h.controls.playPause()
        h.controls.next()
        h.controls.cycleRepeat()
        h.controls.volume.increase()
        try await settle()
        XCTAssertEqual(h.commands, [])
    }

    // MARK: Errors

    func testForbiddenShowsTheGenericNotice() async throws {
        let h = try await make()
        h.commandStatus.value = 403
        h.controls.next()
        try await eventually { h.controls.notice == .notAllowed }
    }

    func testNoActiveDeviceAsksForTheDeviceList() async throws {
        let h = try await make()
        h.commandStatus.value = 404
        var requests = 0
        h.controls.noActiveDevice.sink { requests += 1 }.store(in: &cancellables)

        h.controls.playPause()

        try await eventually { requests == 1 }
        XCTAssertEqual(h.controls.notice, .noActiveDevice)
    }

    // MARK: ±15 s for episodes

    func testSeekMovesFifteenSecondsAndStopsAtTheEdges() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 10_000, episode: true))
        XCTAssertEqual(h.model.nowPlaying?.durationMs, 1_686_230)

        h.controls.skipBackward()
        XCTAssertEqual(h.model.playback?.progressMs, 0, "Never below the start")
        h.controls.skipForward()
        XCTAssertEqual(h.model.playback?.progressMs, 15_000)

        try await eventually { h.commands.count == 2 }
        let seeks = h.commandRequests
        XCTAssertEqual(seeks.map(\.commandLine), ["PUT /me/player/seek", "PUT /me/player/seek"])
        XCTAssertEqual(seeks.map { $0.queryValue("position_ms") }, ["0", "15000"])
    }

    func testSeekForwardStopsAtTheEnd() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 1_680_000, episode: true))
        h.controls.skipForward()
        try await eventually { h.commands.count == 1 }
        XCTAssertEqual(h.commandRequests.last?.queryValue("position_ms"), "1686230",
                       "Past the end Spotify would jump to the next item")
    }

    func testFailedSeekGoesBack() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 60_000, episode: true))
        h.commandStatus.value = 500
        h.controls.skipForward()
        XCTAssertEqual(h.model.playback?.progressMs, 75_000)
        try await eventually { h.model.playback?.progressMs == 60_000 }
    }

    func testSeekingDisallowed() async throws {
        let h = try await make(PlaybackJSON(disallows: ["seeking"], episode: true))
        h.controls.skipForward()
        try await settle()
        XCTAssertEqual(h.commands, [])
    }

    // MARK: Seeking to a position (progress bar, lyrics)

    func testSeekToPositionMovesThereAtOnce() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 84_000))
        h.controls.seek(toMs: 30_500)
        XCTAssertEqual(h.model.playback?.progressMs, 30_500, "Optimistic: the bar does not jump back")
        try await eventually { h.commands.count == 1 }
        XCTAssertEqual(h.commandRequests.map(\.commandLine), ["PUT /me/player/seek"])
        XCTAssertEqual(h.commandRequests.last?.queryValue("position_ms"), "30500")
    }

    func testSeekToPositionStaysWithinTheTrack() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 84_000))
        let duration = try XCTUnwrap(h.model.nowPlaying?.durationMs)
        h.controls.seek(toMs: duration + 10_000)
        h.controls.seek(toMs: -5_000)
        try await eventually { h.commands.count == 2 }
        XCTAssertEqual(h.commandRequests.map { $0.queryValue("position_ms") },
                       [String(duration), "0"])
    }

    func testSeekToPositionDisallowed() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 84_000,
                                            disallows: ["seeking"]))
        h.controls.seek(toMs: 10_000)
        try await settle()
        XCTAssertEqual(h.commands, [])
        XCTAssertEqual(h.model.playback?.progressMs, 84_000)
    }

    func testFailedSeekToPositionGoesBack() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 84_000))
        h.commandStatus.value = 500
        h.controls.seek(toMs: 120_000)
        XCTAssertEqual(h.model.playback?.progressMs, 120_000)
        try await eventually { h.model.playback?.progressMs == 84_000 }
    }

    func testSeekToPositionWorksWithoutAKnownPosition() async throws {
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: nil))
        XCTAssertNil(h.model.currentPositionMs)
        h.controls.seek(toMs: 30_000)
        XCTAssertEqual(h.model.playback?.progressMs, 30_000)
        try await eventually { h.commands.count == 1 }
        XCTAssertEqual(h.commandRequests.last?.queryValue("position_ms"), "30000")
    }

    func testAFailedSeekDoesNotUndoALaterOne() async throws {
        let gate = DispatchSemaphore(value: 0)
        addTeardownBlock { gate.signal(); gate.signal() } // never leave the stub blocked
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 84_000),
                               commandGate: gate)
        h.controls.seek(toMs: 30_000)
        h.controls.seek(toMs: 120_000)
        XCTAssertEqual(h.model.playback?.progressMs, 120_000)

        // The first seek fails while the second one is still on its way.
        h.commandStatus.value = 500
        gate.signal()
        try await eventually { h.controls.notice == .failed }
        XCTAssertEqual(h.model.playback?.progressMs, 120_000,
                       "Undoing the first seek would move the bar away from the second one")

        h.commandStatus.value = 204
        gate.signal()
        try await eventually { h.commands.count == 2 }
    }

    func testTwoFailedSeeksGoBackToTheLastAcceptedPosition() async throws {
        let gate = DispatchSemaphore(value: 0)
        addTeardownBlock { gate.signal(); gate.signal() } // never leave the stub blocked
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 84_000),
                               commandGate: gate)
        h.controls.seek(toMs: 30_000)
        h.controls.seek(toMs: 120_000)
        // Spotify stays at 84 s, so the confirmation read cannot hide a wrong rollback.
        h.commandStatus.value = 500
        gate.signal()
        try await eventually { h.controls.notice == .failed }
        XCTAssertEqual(h.model.playback?.progressMs, 120_000, "The second seek is still on its way")

        gate.signal()
        try await eventually { h.commandRequests.count == 2 && h.model.playback?.progressMs != 120_000 }
        XCTAssertEqual(h.model.playback?.progressMs, 84_000,
                       "Not 30 s: the first seek failed too")
    }

    func testAFailedSeekAfterAnAcceptedOneGoesBackToTheAcceptedOne() async throws {
        let gate = DispatchSemaphore(value: 0)
        addTeardownBlock { gate.signal(); gate.signal() } // never leave the stub blocked
        let h = try await make(PlaybackJSON(isPlaying: false, progressMs: 84_000),
                               commandGate: gate)
        h.controls.seek(toMs: 30_000)
        h.controls.seek(toMs: 120_000)
        gate.signal()
        // The second request reaches the stub (and waits at the gate) once the first one
        // has been answered.
        try await eventually { h.commandRequests.count == 2 }
        // Spotify took the first seek: the confirmation read agrees with the rollback.
        h.playback.value.progressMs = 30_000
        h.commandStatus.value = 500
        gate.signal()
        try await eventually { h.controls.notice == .failed }
        XCTAssertEqual(h.model.playback?.progressMs, 30_000)
    }

    // MARK: Volume from polls

    func testPolledVolumeChangeShowsThePanel() async throws {
        let h = try await make(PlaybackJSON(volume: 50))
        XCTAssertEqual(h.controls.volume.level, 50)
        XCTAssertFalse(h.controls.volume.isPanelVisible, "The first reading is not a change")

        h.playback.value.volume = 70
        await h.model.poll()

        XCTAssertTrue(h.controls.volume.isPanelVisible)
        XCTAssertEqual(h.controls.volume.level, 70)
    }
}
