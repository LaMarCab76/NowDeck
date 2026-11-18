import SwiftUI

extension View {
    /// Presents Cola for the player's account. Like Dispositivos, it is a full-screen cover
    /// that draws its own 640×398 sheet: a system sheet in landscape on iPhone takes the
    /// whole screen.
    func queueSheet(isPresented: Binding<Bool>, player: PlayerModel) -> some View {
        modifier(QueueSheetPresenter(isPresented: isPresented, player: player))
    }
}

struct QueueSheetPresenter: ViewModifier {
    @Binding var isPresented: Bool
    let player: PlayerModel

    @EnvironmentObject private var theme: ThemeStore

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                QueueSheetHost(player: player, dismiss: { isPresented = false })
                    // Passed explicitly: a cover is a new view hierarchy.
                    .environmentObject(theme)
            }
    }
}

/// Owns the sheet's model while the sheet is on screen (every opening reads the queue
/// again) and follows the player: when an item starts (even the same track again), the queue
/// is read again.
private struct QueueSheetHost: View {
    @ObservedObject var player: PlayerModel
    @StateObject private var model: QueueModel
    let dismiss: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    init(player: PlayerModel, dismiss: @escaping () -> Void) {
        self.player = player
        _model = StateObject(wrappedValue: QueueModel(api: player.api))
        self.dismiss = dismiss
    }

    var body: some View {
        QueueSheetView(model: model, nowPlaying: player.nowPlaying, artwork: player.artwork,
                       context: player.playback?.context,
                       // Same delay as a library card: Spotify needs a moment before the
                       // state shows the new track. Not when the app left the foreground
                       // while the request ran: `refresh(after:)` would restart the polling
                       // that `stop()` ended. The next `start()` reads the state anyway.
                       onPlayed: {
                           if UIApplication.shared.applicationState == .active {
                               player.refresh(after: 0.6)
                           }
                       },
                       dismiss: dismiss)
            .task { await model.reload() }
            // `itemStarts`, not `transitionKey`: the same track queued twice in a row also
            // consumes an entry, without changing the key.
            .onChange(of: player.itemStarts) { _ in
                Task { await model.trackDidChange() }
            }
            // The header and the reading on a track change need the player's polling. The
            // player keeps it while Cola covers it (`keepsPlayerPolling`); this also covers
            // coming back from the background with the sheet open, like the library does.
            // `start()` does nothing if the player is already polling.
            .onAppear { if scenePhase == .active { player.start() } }
            .onChange(of: scenePhase) { phase in
                if phase == .active { player.start() } else { player.stop() }
            }
    }
}
