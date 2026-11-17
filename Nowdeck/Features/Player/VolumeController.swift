import Foundation

/// State of the floating volume panel (docs/02-diseno.md, "Panel de volumen").
///
/// - Each tap on − or + moves the shown level 5 % at once. Taps are **coalesced**: only one
///   `PUT /me/player/volume` goes out, `debounce` (250 ms) after the last tap, with the final
///   value. Requests go out one after the other, never in parallel.
/// - Dragging on the bar moves the shown level with the finger. While it moves, the level is
///   sent at most once every `debounce` (a throttle, so the speaker follows along), and the
///   final level goes out as soon as the finger lifts.
/// - The panel appears when the volume button, − or + are tapped, or when a poll brings a
///   level that the app did not set (changed on the computer, the speaker, another phone…),
///   and hides `hideAfter` (3 s) after the last interaction.
/// - Right after the app changes the volume, polls may still bring the old level for a
///   moment. Those answers are ignored for `settleTime` after the request; a poll with the
///   level the app sent ends that wait early.
/// - Devices with `supports_volume: false` or `is_restricted: true` cannot change the volume:
///   the panel says so and − and + are disabled. Nothing is sent.
@MainActor
final class VolumeController: ObservableObject {
    @Published private(set) var isPanelVisible = false
    /// The level shown in the panel, 0–100. `nil` while unknown (`volume_percent` is `null`).
    @Published private(set) var level: Int?
    /// Whether − and + work on the current device.
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
    /// The last level Spotify reported, or that it accepted from us.
    private var confirmedLevel: Int?
    /// The level the user asked for that Spotify has not reported back yet.
    private var pendingLevel: Int?
    /// Polls that disagree with `pendingLevel` are ignored until this date.
    private var settleDeadline: Date?
    /// Running between a tap and the moment its request goes out.
    private var debounceTask: Task<Void, Never>?
    private var lastRequest: Task<Void, Never>?
    private var requestsInFlight = 0
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

    /// The finger left the bar: send the last level now instead of waiting.
    func endDrag() {
        guard let task = debounceTask else { return }
        task.cancel()
        sendPending()
    }

    func hidePanel() {
        hideTask?.cancel()
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
            guard !Task.isCancelled else { return }
            self?.sendPending()
        }
    }

    private func sendPending() {
        debounceTask = nil
        guard let target = pendingLevel else { return }
        requestsInFlight += 1
        let previous = lastRequest
        lastRequest = Task { [weak self, api] in
            await previous?.value
            let result: Result<Void, Error>
            do {
                try await api.sendCommand(.volume(target))
                result = .success(())
            } catch {
                result = .failure(error)
            }
            self?.requestFinished(target: target, result: result)
        }
    }

    private func requestFinished(target: Int, result: Result<Void, Error>) {
        requestsInFlight -= 1
        switch result {
        case .success:
            settleDeadline = now().addingTimeInterval(settleTime)
        case .failure(let error):
            // Only undo if the user has not asked for another level meanwhile.
            if pendingLevel == target {
                pendingLevel = nil
                settleDeadline = nil
                level = confirmedLevel
                hidePanel()
            }
            onFailure?(error)
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
                if debounceTask == nil && requestsInFlight == 0 {
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
        if debounceTask != nil || requestsInFlight > 0 { return true }
        if let settleDeadline, now() < settleDeadline { return true }
        return false
    }

    private func reset(to device: SpotifyDevice?) {
        deviceID = device?.id
        hasDevice = device != nil
        confirmedLevel = device?.volumePercent
        level = device?.volumePercent
        pendingLevel = nil
        settleDeadline = nil
        debounceTask?.cancel()
        debounceTask = nil
        if device == nil {
            isAdjustable = false
            hidePanel()
        }
    }

    // MARK: Panel

    private func showPanel() {
        isPanelVisible = true
        hideTask?.cancel()
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
/// so without an announcement a change made with − and +, or on another device, is silent.
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
