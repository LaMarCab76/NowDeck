import Combine
import Foundation

/// The player's commands: play/pause, previous, next, shuffle, repeat, seeking (the ±15 s of
/// podcast episodes, the progress bar and the stanzas of lyrics mode), plus the volume panel
/// (`volume`).
///
/// Every command follows the same steps (docs/03-spotify-api.md, "Polling y estado local"):
/// 1. Check `ControlAvailability`: a forbidden action is never sent.
/// 2. Hold the polling and change the screen at once (optimistic update).
/// 3. Send the command. Commands run one after the other, in the order they were tapped:
///    two quick taps on play/pause must reach Spotify as "play" then "pause".
/// 4. On success, poll again after `confirmDelay` (~0.6 s) to confirm. On failure, take the
///    optimistic change back, show a notice and poll at once. **Never retry**: repeating
///    "next" would skip two tracks.
@MainActor
final class PlayerControlsModel: ObservableObject {
    /// The pill shown at the top for 3 s after a failed command.
    enum Notice: Equatable {
        /// `403`. Spotify documents no reason for it (`PREMIUM_REQUIRED` is gone), so it is a
        /// generic message: Premium is the most likely cause on commands.
        case notAllowed
        /// `404`, typically "No active device".
        case noActiveDevice
        /// `429`.
        case rateLimited
        /// Network, server or any other error.
        case failed
    }

    @Published private(set) var notice: Notice?
    /// Fires after a `404` (no active device). The screen answers by opening Dispositivos
    /// (`PlayerActions.devices`, wired by milestone 4).
    let noActiveDevice = PassthroughSubject<Void, Never>()
    let volume: VolumeController

    /// Step of the podcast buttons (Spotify's design guidelines: "Podcasts need to have the
    /// option to seek 15 seconds forward or backwards").
    static let seekStepMs = 15_000

    private weak var player: PlayerModel?
    private let api: SpotifyAPI
    private let confirmDelay: TimeInterval
    private let noticeDuration: TimeInterval

    /// The last queued command; the next one waits for it.
    private var lastCommand: Task<Void, Never>?
    @Published private var pendingCommands = 0
    @Published private(set) var isStartingQueuedTrack = false
    private var batchFailed = false
    private var noticeTask: Task<Void, Never>?
    private var playbackSubscription: AnyCancellable?
    /// Seeks sent and not answered yet.
    private var pendingSeeks = 0
    /// Where Spotify is as far as answered commands tell: read from the screen when a burst
    /// of commands starts, then moved only by accepted commands (see `seekFinished`).
    private var confirmed: ConfirmedPosition?

    init(player: PlayerModel,
         confirmDelay: TimeInterval = 0.6,
         noticeDuration: TimeInterval = Metrics.Notice.duration,
         volume: VolumeController? = nil) {
        self.player = player
        self.api = player.api
        self.confirmDelay = confirmDelay
        self.noticeDuration = noticeDuration
        self.volume = volume ?? VolumeController(api: player.api)

        self.volume.onFailure = { [weak self] error in self?.handleFailure(error) }
        // Every poll (and every optimistic change) reports the device to the volume panel,
        // which detects changes made elsewhere.
        playbackSubscription = player.$playback
            .sink { [weak volume = self.volume] playback in
                volume?.observe(playback?.device)
            }
    }

    /// What can be tapped right now.
    var availability: ControlAvailability {
        guard !isStartingQueuedTrack else { return .none }
        var availability = ControlAvailability(playback: player?.playback)
        if player?.isWaitingForQueuedSeekConfirmation == true { availability.seek = false }
        return availability
    }

    /// The library and queue wait for player commands before starting another context.
    var isSendingCommand: Bool { pendingCommands > 0 || isStartingQueuedTrack }

    // MARK: Commands

    /// Starting a queue item replaces the current playback. Keep commands targeting the
    /// old item out of that request, even if the user closes the queue while it is in flight.
    func playQueuedTrack(_ entry: QueueEntry, in queue: QueueModel) async {
        guard let player, !isSendingCommand, let uri = entry.playURI else { return }
        isStartingQueuedTrack = true
        player.holdPolling()
        let started = await queue.play(entry, context: player.playback?.context)
        if started { player.waitForQueuedSeekConfirmation(requestedURI: uri) }
        player.resumePolling(after: started ? confirmDelay : 0)
        isStartingQueuedTrack = false
    }

    func playPause() {
        guard let playback = player?.playback, availability.playPause else { return }
        let resume = !playback.isPlaying
        run(resume ? .play : .pause,
            optimistic: { $0.isPlaying = resume },
            rollback: { if $0.isPlaying == resume { $0.isPlaying = !resume } },
            completion: { [weak self] succeeded in
                // A failed play or pause leaves Spotify as it was: nothing to record.
                if succeeded { self?.playStateChanged(isPlaying: resume) }
            })
    }

    func next() {
        guard availability.next else { return }
        // There is no honest optimistic change: the next item is unknown until Spotify says.
        run(.next, completion: { [weak self] in if $0 { self?.itemChanged() } })
    }

    func previous() {
        guard availability.previous else { return }
        run(.previous, completion: { [weak self] in if $0 { self?.itemChanged() } })
    }

    func toggleShuffle() {
        guard let playback = player?.playback, availability.shuffle else { return }
        let target = !playback.shuffleState
        run(.shuffle(target),
            optimistic: { $0.shuffleState = target },
            rollback: { if $0.shuffleState == target { $0.shuffleState = !target } })
    }

    /// off → context → track → off, skipping the modes `actions` forbids.
    func cycleRepeat() {
        guard let playback = player?.playback,
              availability.repeatMode,
              let target = ControlAvailability.nextRepeatMode(after: playback.repeatState,
                                                              actions: playback.actions)
        else { return }
        let previous = playback.repeatState
        run(.repeatMode(target),
            optimistic: { $0.repeatState = target },
            rollback: { if $0.repeatState == target { $0.repeatState = previous } })
    }

    func skipBackward() {
        seek(by: -Self.seekStepMs)
    }

    func skipForward() {
        seek(by: Self.seekStepMs)
    }

    private func seek(by deltaMs: Int) {
        guard let position = player?.currentPositionMs else { return }
        seek(toMs: position + deltaMs)
    }

    /// Moves the playback to `positionMs`: dragging the progress bar, or tapping a stanza in
    /// lyrics mode. Only where Spotify allows seeking (`ControlAvailability.seek`).
    ///
    /// Spotify can leave `progress_ms` empty; the target and the duration are enough to seek
    /// then, and a failure puts the empty position back.
    func seek(toMs positionMs: Int) {
        guard let player, availability.seek,
              let durationMs = player.nowPlaying?.durationMs, durationMs > 0
        else { return }
        // Past the end Spotify jumps to the next item: stop at the end instead.
        let target = min(max(0, positionMs), durationMs)
        let position = player.currentPositionMs
        guard target != position else { return }
        pendingSeeks += 1
        run(.seek(positionMs: target),
            optimistic: { $0.progressMs = target },
            completion: { [weak self] succeeded in
                self?.seekFinished(target: target, succeeded: succeeded)
            })
    }

    // MARK: Where Spotify is

    // Commands finish in the order they were sent, so `confirmed` follows Spotify's answers
    // one by one: a failed seek can go back to it without trusting the screen, which may
    // already show later optimistic changes.

    /// Play or pause accepted: the position keeps running, or stops, from now on.
    private func playStateChanged(isPlaying: Bool) {
        guard let player, let confirmed else { return }
        let date = player.now()
        self.confirmed = ConfirmedPosition(positionMs: confirmed.position(at: date),
                                           isPlaying: isPlaying, date: date)
    }

    /// Next or previous accepted: only a poll can tell where playback landed.
    private func itemChanged() {
        confirmed = nil
        player?.queuedStartWasSuperseded()
    }

    /// A failed seek is undone only once no seek is left on its way, and then back to the
    /// confirmed position: undoing it earlier would move the bar away from a newer target,
    /// and undoing it alone would land on the target of an earlier seek that may have
    /// failed too.
    private func seekFinished(target: Int, succeeded: Bool) {
        guard let player, pendingSeeks > 0 else { return }
        pendingSeeks -= 1
        let date = player.now()
        if succeeded {
            confirmed = ConfirmedPosition(positionMs: target,
                                          isPlaying: confirmed?.isPlaying
                                              ?? (player.playback?.isPlaying == true),
                                          date: date)
            return
        }
        // Without a confirmed position (another item started), the poll after the
        // failure tells.
        guard pendingSeeks == 0, let confirmed else { return }
        let durationMs = player.nowPlaying?.durationMs
        player.updatePlayback { state in
            // The confirmed position kept running while the seeks were out; it is not
            // rebuilt from the bar, which stops at the end of the track. An unknown
            // position goes back to unknown.
            state.progressMs = confirmed.position(at: date).map { position in
                durationMs.map { min(position, $0) } ?? position
            }
        }
    }

    // MARK: Running a command

    private func run(_ command: PlaybackCommand,
                     optimistic: ((inout PlaybackState) -> Void)? = nil,
                     rollback: ((inout PlaybackState) -> Void)? = nil,
                     completion: ((_ succeeded: Bool) -> Void)? = nil) {
        guard let player else { return }
        if pendingCommands == 0 {
            // Nothing optimistic on screen yet: it shows where Spotify is.
            confirmed = ConfirmedPosition(positionMs: player.currentPositionMs,
                                          isPlaying: player.playback?.isPlaying == true,
                                          date: player.now())
        }
        player.holdPolling()
        if let optimistic { player.updatePlayback(optimistic) }
        pendingCommands += 1

        let previous = lastCommand
        lastCommand = Task { [weak self, api] in
            await previous?.value
            let result: Result<Void, Error>
            do {
                try await api.sendCommand(command)
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.finish(result, rollback: rollback, completion: completion)
        }
    }

    private func finish(_ result: Result<Void, Error>,
                        rollback: ((inout PlaybackState) -> Void)?,
                        completion: ((_ succeeded: Bool) -> Void)?) {
        if case .failure(let error) = result {
            batchFailed = true
            if let rollback { player?.updatePlayback(rollback) }
            completion?(false)
            handleFailure(error)
        } else {
            completion?(true)
        }
        pendingCommands -= 1
        guard pendingCommands == 0 else { return }
        // After a failure, ask for the real state right away.
        player?.resumePolling(after: batchFailed ? 0 : confirmDelay)
        batchFailed = false
    }

    // MARK: Errors

    func handleFailure(_ error: Error) {
        switch error {
        case SpotifyAPIError.forbidden:
            show(.notAllowed)
        case SpotifyAPIError.notFound:
            show(.noActiveDevice)
            noActiveDevice.send()
        case SpotifyAPIError.rateLimited:
            show(.rateLimited)
        case is CancellationError:
            break
        case AuthError.invalidGrant, AuthError.invalidClient:
            // `TokenManager` already sends the user back to the setup.
            break
        default:
            show(.failed)
        }
    }

    private func show(_ notice: Notice) {
        noticeTask?.cancel()
        self.notice = notice
        let duration = noticeDuration
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.notice = nil
        }
    }
}

/// A playback position and when it was true, advancing with the clock while playing.
private struct ConfirmedPosition {
    /// `nil` when Spotify did not say (`progress_ms: null`).
    var positionMs: Int?
    var isPlaying: Bool
    var date: Date

    func position(at now: Date) -> Int? {
        guard let positionMs else { return nil }
        guard isPlaying else { return positionMs }
        let elapsed = max(0, now.timeIntervalSince(date))
        return positionMs + Int((elapsed * 1000).rounded(.down))
    }
}
