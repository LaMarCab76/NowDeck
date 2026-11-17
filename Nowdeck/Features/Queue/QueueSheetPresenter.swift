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
/// again) and follows the player: when another track starts, the queue is read again.
private struct QueueSheetHost: View {
    @ObservedObject var player: PlayerModel
    @StateObject private var model: QueueModel
    let dismiss: () -> Void

    init(player: PlayerModel, dismiss: @escaping () -> Void) {
        self.player = player
        _model = StateObject(wrappedValue: QueueModel(api: player.api))
        self.dismiss = dismiss
    }

    var body: some View {
        QueueSheetView(model: model, nowPlaying: player.nowPlaying, artwork: player.artwork,
                       dismiss: dismiss)
            .task { await model.reload() }
            .onChange(of: player.nowPlaying?.transitionKey) { _ in
                Task { await model.trackDidChange() }
            }
    }
}
