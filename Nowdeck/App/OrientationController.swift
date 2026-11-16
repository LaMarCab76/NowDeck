import SwiftUI
import UIKit

/// Locks the interface orientation per screen.
///
/// SwiftUI has no per-view orientation API, so we use UIKit: the app delegate returns
/// `mask` from `application(_:supportedInterfaceOrientationsFor:)`, and changing it asks the
/// scene to rotate with `requestGeometryUpdate` (iOS 16+).
@MainActor
final class OrientationController {
    static let shared = OrientationController()

    /// Landscape by default: only onboarding is portrait.
    private(set) var mask: UIInterfaceOrientationMask = .landscape

    private init() {}

    func lock(_ newMask: UIInterfaceOrientationMask) {
        mask = newMask
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes {
            // Tell UIKit the supported orientations changed, then ask for the rotation.
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: newMask)) { _ in
                // The request fails only when the mask is not allowed by Info.plist, which
                // would be a programming error; there is nothing useful to do at runtime.
            }
        }
    }
}

extension View {
    /// Locks the screen to the given orientations while this view is on screen.
    func orientationLock(_ mask: UIInterfaceOrientationMask) -> some View {
        onAppear { OrientationController.shared.lock(mask) }
    }
}
