import Foundation

/// State of the Dispositivos sheet: the device list and the playback transfer.
///
/// The sheet makes its own calls (the player's polling only knows the active device). It
/// loads the list when it opens and on "Actualizar lista"; tapping a device moves
/// playback there and, on success, calls `onTransferred` so the player re-reads its state.
@MainActor
final class DevicesModel: ObservableObject {
    /// `nil` until the first answer arrives.
    @Published private(set) var choices: DeviceChoices?
    @Published private(set) var isLoading = false
    /// The last problem, shown in the sheet until the next successful call.
    @Published private(set) var problem: DevicesProblem?
    /// The device being transferred to, to show progress on its row and block other taps.
    @Published private(set) var transferringID: String?

    /// The device the player showed when the sheet opened, for the header while the list
    /// loads. Replaced by the list's own active device once it arrives.
    let initialDevice: SpotifyDevice?

    /// `play: true` (docs/03): "ensure playback happens on new device". It also makes
    /// "Elegir dispositivo" in "Nada sonando" resume the last playback there.
    static let playAfterTransfer = true

    private let api: SpotifyAPI
    private let onTransferred: @MainActor () -> Void
    private var loadTask: Task<Void, Never>?

    init(api: SpotifyAPI, initialDevice: SpotifyDevice? = nil,
         onTransferred: @escaping @MainActor () -> Void = {}) {
        self.api = api
        self.initialDevice = initialDevice
        self.onTransferred = onTransferred
    }

    /// The device for the header: the list's active one, or the player's before the list.
    var currentDevice: SpotifyDevice? {
        if let choices { return choices.current }
        return initialDevice
    }

    // MARK: Loading

    /// Reads the list again. A reload while another is running waits for that one instead
    /// of sending a second request.
    func reload() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { await self.fetch() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func fetch() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let devices = try await api.availableDevices()
            choices = DeviceChoices(devices: devices)
            problem = nil
        } catch is CancellationError {
            return
        } catch {
            // The list on screen (if any) stays; the problem is shown above it.
            problem = DevicesProblem(error, duringTransfer: false)
        }
    }

    // MARK: Transfer

    /// Moves playback to `device`. Returns `true` when Spotify accepted it, so the sheet
    /// can close.
    @discardableResult
    func transfer(to device: SpotifyDevice) async -> Bool {
        guard transferringID == nil, device.acceptsTransfer, let id = device.id else {
            return false
        }
        transferringID = id
        defer { transferringID = nil }

        do {
            try await api.transferPlayback(to: id, play: Self.playAfterTransfer)
            problem = nil
            onTransferred()
            return true
        } catch is CancellationError {
            return false
        } catch {
            let problem = DevicesProblem(error, duringTransfer: true)
            if problem == .deviceGone {
                // The list is out of date: read it again, but keep the explanation.
                await reload()
            }
            self.problem = problem
            return false
        }
    }
}
