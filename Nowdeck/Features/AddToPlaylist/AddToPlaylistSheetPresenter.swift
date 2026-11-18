import SwiftUI

extension View {
    /// Presents Agregar a una playlist for what the player shows now. Like Dispositivos and
    /// Cola, it is a full-screen cover that draws its own 640×398 sheet: a system sheet in
    /// landscape on iPhone takes the whole screen.
    func addToPlaylistSheet(isPresented: Binding<Bool>, player: PlayerModel,
                            access: PlaylistEditingAccess) -> some View {
        modifier(AddToPlaylistSheetPresenter(isPresented: isPresented, player: player,
                                             access: access))
    }
}

struct AddToPlaylistSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let player: PlayerModel
    let access: PlaylistEditingAccess

    @EnvironmentObject private var theme: ThemeStore

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                AddToPlaylistSheetHost(player: player, access: access,
                                       dismiss: { isPresented = false })
                    // Passed explicitly: a cover is a new view hierarchy.
                    .environmentObject(theme)
            }
    }
}

/// Captures the item when the sheet opens, so a track change while the user picks a
/// playlist never adds the wrong song.
private struct AddToPlaylistSheetHost: View {
    @ObservedObject var model: AddToPlaylistModel
    let access: PlaylistEditingAccess
    let dismiss: () -> Void

    /// Captured once: `State` keeps its first value even if SwiftUI builds the host again.
    @State private var item: NowPlaying?
    @State private var artwork: UIImage?

    init(player: PlayerModel, access: PlaylistEditingAccess, dismiss: @escaping () -> Void) {
        model = player.playlists
        self.access = access
        self.dismiss = dismiss
        _item = State(initialValue: player.nowPlaying)
        _artwork = State(initialValue: player.artwork)
    }

    var body: some View {
        Group {
            if let item, let uri = item.playlistURI {
                AddToPlaylistSheetView(model: model, item: item, artwork: artwork,
                                       dismiss: dismiss)
                    .onAppear { model.open(for: uri, access: access) }
                    .task { await model.prepare() }
            } else {
                // The button is disabled without an addable item; if the item ended while
                // the cover was opening, there is nothing to add.
                Color.clear.onAppear(perform: dismiss)
            }
        }
    }
}
