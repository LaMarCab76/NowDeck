import SwiftUI

// How a screen shows Dispositivos. Any screen with a "… en <dispositivo>" button attaches
// one modifier and flips a Bool:
//
//     @State private var showsDevices = false
//     …
//     Button { showsDevices = true } label: { … }
//     …
//     .devicesSheet(isPresented: $showsDevices, player: model)
//
// The player (`PlayerScreen`), "Nada sonando" and lyrics mode go through
// `PlayerActions.devices`; the mini player of Biblioteca (milestone 5) uses the same
// modifier.

extension View {
    /// Presents Dispositivos for the player's account. After a successful transfer the
    /// player re-reads its state (`PlayerModel.refresh(after:)`), so "Reproduciendo en …"
    /// and the mini player's "Suena en …" show the new device.
    func devicesSheet(isPresented: Binding<Bool>, player: PlayerModel) -> some View {
        devicesSheet(
            isPresented: isPresented,
            api: player.api,
            currentDevice: { player.playback?.device },
            onTransferred: { [weak player] in
                player?.refresh(after: DevicesSheetPresenter.playerRefreshDelay)
            }
        )
    }

    /// Presents Dispositivos with an explicit API client. `currentDevice` is read when the
    /// sheet opens, for the header while the list loads.
    func devicesSheet(isPresented: Binding<Bool>, api: SpotifyAPI,
                      currentDevice: @escaping @MainActor () -> SpotifyDevice? = { nil },
                      onTransferred: @escaping @MainActor () -> Void) -> some View {
        modifier(DevicesSheetPresenter(isPresented: isPresented, api: api,
                                       currentDevice: currentDevice,
                                       onTransferred: onTransferred))
    }
}

struct DevicesSheetPresenter: ViewModifier {
    /// Re-read the playback state this long after a transfer: the same ~600 ms as the
    /// other commands (docs/03, "Polling y estado local"). The transfer is asynchronous on
    /// Spotify's side, and the next regular poll (3 s) corrects a too-early answer.
    static let playerRefreshDelay: TimeInterval = 0.6

    @Binding var isPresented: Bool
    let api: SpotifyAPI
    let currentDevice: @MainActor () -> SpotifyDevice?
    let onTransferred: @MainActor () -> Void

    @EnvironmentObject private var theme: ThemeStore

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                DevicesSheetHost(api: api, initialDevice: currentDevice(),
                                 onTransferred: onTransferred,
                                 dismiss: { isPresented = false })
                    // Passed explicitly: a cover is a new view hierarchy.
                    .environmentObject(theme)
            }
    }
}

/// Owns the sheet's model for as long as the sheet is on screen: every opening starts
/// with a fresh list.
private struct DevicesSheetHost: View {
    @StateObject private var model: DevicesModel
    let dismiss: () -> Void

    init(api: SpotifyAPI, initialDevice: SpotifyDevice?,
         onTransferred: @escaping @MainActor () -> Void, dismiss: @escaping () -> Void) {
        _model = StateObject(wrappedValue: DevicesModel(api: api, initialDevice: initialDevice,
                                                        onTransferred: onTransferred))
        self.dismiss = dismiss
    }

    var body: some View {
        DevicesSheetView(model: model, dismiss: dismiss)
    }
}
