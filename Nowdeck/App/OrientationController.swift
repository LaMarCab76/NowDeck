import SwiftUI
import UIKit

/// Locks the interface orientation per screen.
///
/// SwiftUI has no per-view orientation API, so we use UIKit: the app delegate returns
/// `mask` from `application(_:supportedInterfaceOrientationsFor:)`, and changing it asks the
/// scene to rotate with `requestGeometryUpdate` (iOS 16+).
///
/// The lock follows `AppState.Route` (see `RootView`): onboarding is portrait, the rest is
/// landscape. `AppState` sets the first mask before any window exists (`prepare(for:)`), so
/// UIKit never caches the wrong one at launch.
@MainActor
final class OrientationController {
    static let shared = OrientationController()

    /// Landscape until `AppState` says where the app starts.
    private(set) var mask: UIInterfaceOrientationMask = .landscape

    private init() {}

    static func mask(for route: AppState.Route) -> UIInterfaceOrientationMask {
        switch route {
        case .onboarding: return .portrait
        case .player: return .landscape
        }
    }

    /// Sets the mask without asking any window to rotate. Used once at launch, before the
    /// window asks the app delegate for its supported orientations.
    func prepare(for route: AppState.Route) {
        mask = Self.mask(for: route)
    }

    func lock(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            // Tell UIKit the supported orientations changed, then ask for the rotation.
            // Every window, not only the key one: right after launch there may be no key
            // window yet, and UIKit would keep the orientations it cached before.
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in
                // The request fails only when the mask is not allowed by Info.plist, which
                // would be a programming error; there is nothing useful to do at runtime.
            }
        }
    }
}

extension View {
    /// Locks the screen to the orientation of `route` when this view appears and every time
    /// the route changes.
    func orientationLock(following route: AppState.Route) -> some View {
        self
            .onAppear { OrientationController.shared.lock(OrientationController.mask(for: route)) }
            .onChange(of: route) { newRoute in
                OrientationController.shared.lock(OrientationController.mask(for: newRoute))
            }
    }
}
