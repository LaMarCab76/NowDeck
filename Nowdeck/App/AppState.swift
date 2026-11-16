import SwiftUI

/// App-wide navigation state.
///
/// Milestone 0 has a single empty screen. Milestone 1 adds the onboarding route and decides
/// the initial route from the credentials stored in the Keychain.
@MainActor
final class AppState: ObservableObject {
    enum Route: Equatable {
        case player
    }

    @Published var route: Route = .player
}
