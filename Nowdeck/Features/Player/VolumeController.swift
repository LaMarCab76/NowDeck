import Foundation

/// State of the volume bar in the controls row (docs/02-diseno.md, "Barra de volumen").
///
/// - Each step (a VoiceOver swipe on the bar) moves the shown level 5 % at once. Steps are
///   **coalesced**: only one `PUT /me/player/volume` goes out, `debounce` (250 ms) after the
///   last one, with the final value. Requests go out one after the other, never in parallel.
/// - Dragging on the bar moves the shown level with the finger. While it moves, the level is
///   sent at most once every `debounce` (a throttle, so the speaker follows along), and the
///   final level goes out as soon as the finger lifts.
/// - Only one request is out at a time. Levels chosen while it travels are not queued: when
///   it finishes, only the newest one goes out (a slow network never replays a whole drag).
/// - The bar opens when the volume button is tapped, on a step, or when a poll brings a
///   level that the app did not set (changed on the computer, the speaker, another phone…),
///   and hides `hideAfter` (3 s) after the last interaction. While the finger is on the bar
///   it stays, however long the finger rests there.
/// - Right after the app changes the volume, polls may still bring the old level for a
///   moment. Those answers are ignored for `settleTime` after the request; a poll with the
///   level the app sent ends that wait early.
/// - Devices with `supports_volume: false` or `is_restricted: true` cannot change the volume:
///   the bar's place says so. Nothing is sent.
@MainActor
final class VolumeController: ObservableObject {
    @Published private(set) var isPanelVisible = false
    /// The level shown in the panel, 0–100. `nil` while unknown (`volume_percent` is `null`).
    @Published private(set) var level: Int?
    /// Whether the level can change on the current device.
    @Published private(set) var isAdjustable = false
    /// There is a device at all (to tell "no device" from "this device can't").
    @Published private(set) var hasDevice = false

    /// Called when a volume request fails (the controls model shows a notice).
    var onFailure: ((Error) -> Void)?

    static let step = 5

    private let api: SpotifyAPI
    private let debounce: TimeInterval
    private let hideAfter: TimeInterval
    private let settleTime: TimeInterval
    private let now: () -> Date

    /// The device whose volume `confirmedLevel` belongs to.
    private var deviceID: String?
    /// Distinguishes requests sent before a device switch, even if its ID comes back later.
    private var deviceGeneration = 0
    /// The last level Spotify reported, or that it accepted from us.
    private var confirmedLevel: Int?
    /// The level the user asked for that Spotify has not reported back yet.
    private var pendingLevel: Int?
    /// Polls that disagree with `pendingLevel` are ignored until this date.
    private var settleDeadline: Date?
    /// Running between a tap and the moment its request goes out.
    private var debounceTask: Task<Void, Never>?
    /// A `PUT /me/player/volume` is on its way.
    private var isRequestInFlight = false
    /// A send was due while a request was on its way; `pendingLevel` goes out when it ends.
    private var sendsWhenRequestEnds = false
    /// The finger is on the bar: the panel does not hide on its own.
    private var isDragging = false
    private var hideTask: Task<Void, Never>?

    init(api: SpotifyAPI,
         debounce: TimeInterval = 0.25,
         hideAfter: TimeInterval = 3,
         settleTime: TimeInterval = 3,
         now: @escaping () -> Date = { Date() }) {
        self.api = api
        self.debounce = debounce
        self.hideAfter = hideAfter
        self.settleTime = settleTime
        self.now = now
    }

    /// What VoiceOver should say about the panel right now; `nil` while it is hidden.
    var announcement: VolumeAnnouncement? {
        VolumeAnnouncement(isPanelVisible: isPanelVisible, level: level,
                           isAdjustable: isAdjustable, hasDevice: hasDevice)
    }

    // MARK: Taps

    /// The Volumen button: opens the panel, or closes it if it is open.
    func toggleButton() {
        if isPanelVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func increase() {
        change(by: Self.step)
    }

    func decrease() {
        change(by: -Self.step)
    }

    /// The finger is on the bar, at `target` (0–100).
    func drag(to target: Int) {
        isDragging = true
        showPanel()
        guard isAdjustable, let current = level else { return }
        let target = min(100, max(0, target))
        guard target != current else { return }
        level = target
        pendingLevel = target
        // Throttle: a send already scheduled will carry this newer value.
        guard debounceTask == nil else { return }
        scheduleSend()
    }

    /// The finger left the bar (or the gesture was cancelled): send the last level now
    /// instead of waiting, and start the hide delay again. Calling it twice is harmless.
    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        showPanel()
        if debounceTask != nil { sendPending() }
    }

    func hidePanel() {
        hideTask?.cancel()
        isDragging = false
        isPanelVisible = false
    }

    private func change(by delta: Int) {
        showPanel()
        guard isAdjustable, let current = level else { return }
        let target = min(100, max(0, current + delta))
        guard target != current else { return }
        level = target
        pendingLevel = target

        // Coalescing: every tap restarts the wait; only the last value is sent.
        debounceTask?.cancel()
        scheduleSend()
    }

    private func scheduleSend() {
        let wait = debounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            debounceTask = nil
            sendPending()
        }
    }

    private func cancelScheduledSend() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    private func sendPending() {
        cancelScheduledSend()
        guard let target = pendingLevel else { return }
        // One request at a time, and no queue: whatever is newest when it ends goes next.
        guard !isRequestInFlight else {
            sendsWhenRequestEnds = true
            return
        }
        isRequestInFlight = true
        let generation = deviceGeneration
        Task { [weak self, api] in
            let result: Result<Void, Error>
            do {
                try await api.sendCommand(.volume(target))
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.requestFinished(target: target, generation: generation, result: result)
        }
    }

    private func requestFinished(target: Int, generation: Int, result: Result<Void, Error>) {
        isRequestInFlight = false
        let isCurrentDevice = generation == deviceGeneration
        if isCurrentDevice {
            switch result {
            case .success:
                settleDeadline = now().addingTimeInterval(settleTime)
            case .failure(let error):
                // Only undo if the user has not asked for another level meanwhile.
                if pendingLevel == target {
                    pendingLevel = nil
                    settleDeadline = nil
                    level = confirmedLevel
                    cancelScheduledSend()
                    hidePanel()
                }
                onFailure?(error)
            }
        }

        let shouldSend = sendsWhenRequestEnds
        sendsWhenRequestEnds = false
        if isCurrentDevice && pendingLevel == target {
            cancelScheduledSend()
        } else if shouldSend {
            sendPending()
        }
    }

    // MARK: Polls

    /// The device of each new playback state.
    func observe(_ device: SpotifyDevice?) {
        guard let device else {
            reset(to: nil)
            return
        }
        hasDevice = true
        isAdjustable = device.supportsVolume != false && !device.isRestricted
            && device.volumePercent != nil
        let reported = device.volumePercent

        // Another device: its level is the new reference, without showing the panel.
        if device.id != deviceID {
            reset(to: device)
            return
        }
        guard let reported else {
            confirmedLevel = nil
            if pendingLevel == nil { level = nil }
            return
        }

        if let pending = pendingLevel {
            if reported == pending {
                // Spotify caught up with the taps (unless more are still on their way).
                if debounceTask == nil && !isRequestInFlight {
                    pendingLevel = nil
                    settleDeadline = nil
                }
                confirmedLevel = reported
                return
            }
            if isWaitingForOwnChange { return }
            // The change never showed up (or someone changed it again): trust Spotify.
            pendingLevel = nil
            settleDeadline = nil
        }

        guard reported != confirmedLevel else {
            level = reported
            return
        }
        let isFirstReading = confirmedLevel == nil
        confirmedLevel = reported
        level = reported
        if !isFirstReading {
            // Changed outside the app.
            showPanel()
        }
    }

    /// Still within the wait that follows a tap (debouncing, request on its way, or polls
    /// that may predate it).
    private var isWaitingForOwnChange: Bool {
        if debounceTask != nil || isRequestInFlight { return true }
        if let settleDeadline, now() < settleDeadline { return true }
        return false
    }

    private func reset(to device: SpotifyDevice?) {
        deviceGeneration += 1
        deviceID = device?.id
        hasDevice = device != nil
        confirmedLevel = device?.volumePercent
        level = device?.volumePercent
        pendingLevel = nil
        settleDeadline = nil
        cancelScheduledSend()
        sendsWhenRequestEnds = false
        if device == nil {
            isAdjustable = false
            hidePanel()
        }
    }

    // MARK: Panel

    private func showPanel() {
        isPanelVisible = true
        hideTask?.cancel()
        // While the finger is on the bar the panel stays; `endDrag()` starts the wait again.
        guard !isDragging else { return }
        let delay = hideAfter
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.isPanelVisible = false
        }
    }
}

/// What VoiceOver says when the volume panel appears or its level changes (docs/07, Hito 8:
/// "anuncios del aviso y del panel de volumen"). The panel never takes the VoiceOver focus,
/// so without an announcement a change made on another device is silent.
enum VolumeAnnouncement: Equatable {
    case level(Int)
    /// The device does not let the app change its volume (`supports_volume: false`,
    /// restricted, or no level reported).
    case notAdjustable
    case noDevice

    init?(isPanelVisible: Bool, level: Int?, isAdjustable: Bool, hasDevice: Bool) {
        guard isPanelVisible else { return nil }
        if !hasDevice {
            self = .noDevice
        } else if isAdjustable, let level {
            self = .level(level)
        } else {
            self = .notAdjustable
        }
    }

    /// Same wording as the panel: its level bar reads "N de 100", and the unavailable states
    /// reuse the panel's own messages.
    var message: LocalizedStringResource {
        switch self {
        case .level(let level): return "Volumen: \(level) de 100"
        case .notAdjustable: return "Este dispositivo no permite cambiar el volumen"
        case .noDevice: return "No hay un dispositivo activo"
        }
    }
}
