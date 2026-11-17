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

    /// The screen the user is looking at.
    var visibleSurface: Surface {
        showsLibrary ? .library : .player
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
}
