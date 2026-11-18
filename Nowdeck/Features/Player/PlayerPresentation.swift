import Foundation

/// What the player screen presents on top of itself, and where things the player raises
/// on its own go.
///
/// The library is a full-screen cover over the player. While it is open, a devices sheet or
/// a notice shown by the player would end up **behind** it. So the player asks
/// `visibleSurface` first: with the library open, the library presents its own devices
/// sheet (`showsLibraryDevices`) and shows the control notices.
@MainActor
final class PlayerPresentation: ObservableObject {
    enum Surface: Equatable {
        case player
        case library
    }

    @Published var showsLibrary = false
    /// Dispositivos presented from the player.
    @Published var showsDevices = false
    /// Dispositivos presented from inside the library, which covers the player.
    @Published var showsLibraryDevices = false
    /// Cola, presented from the player (only the player has its button).
    @Published var showsQueue = false
    /// Agregar a una playlist, presented from the player.
    @Published var showsAddToPlaylist = false
    /// Agregar a una playlist, presented from inside the library (its mini player).
    @Published var showsLibraryAddToPlaylist = false

    /// The screen the user is looking at.
    var visibleSurface: Surface {
        showsLibrary ? .library : .player
    }

    /// Whether the player keeps polling while it is covered. Presenting a full-screen cover
    /// makes the player's `onDisappear` run, which would stop the polling. The library (its
    /// mini player) and Cola (its header, and reading the queue again on a track change)
    /// show the playback live, so the polling goes on under them (Ajustes opens inside the
    /// library). Dispositivos does not show it: polling stops there, as before, to save
    /// requests.
    var keepsPlayerPolling: Bool {
        showsLibrary || showsQueue
    }

    /// Opens Dispositivos on the visible screen: "Reproduciendo en …", "Suena en …", or a
    /// command answered "no active device" (`PlayerControlsModel.noActiveDevice`), which can
    /// come from the mini player's play button while the library is open.
    func showDevices() {
        switch visibleSurface {
        case .player: showsDevices = true
        case .library: showsLibraryDevices = true
        }
    }

    /// Opens Agregar a una playlist on the visible screen: the player's button, or the mini
    /// player's while the library covers the player.
    func showAddToPlaylist() {
        switch visibleSurface {
        case .player: showsAddToPlaylist = true
        case .library: showsLibraryAddToPlaylist = true
        }
    }
}
