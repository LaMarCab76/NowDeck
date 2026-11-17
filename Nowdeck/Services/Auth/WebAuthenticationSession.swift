import AuthenticationServices
import UIKit

/// Opens a login page and returns the redirect URL. A protocol so the login flow can be
/// tested without a browser.
@MainActor
protocol WebAuthenticating {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// `ASWebAuthenticationSession` with async/await.
///
/// `prefersEphemeralWebBrowserSession = false` reuses the Spotify login the user may already
/// have in Safari, so most of the time they only see the consent page. The trade-off is the
/// system alert "Nowdeck wants to use spotify.com to sign in", which iOS shows in that mode.
@MainActor
final class WebAuthenticationSession: NSObject, WebAuthenticating {
    /// The session must stay alive while it is on screen.
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: AuthError.webSessionFailed)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AuthError.webSessionFailed)
            }
        }
    }
}

extension WebAuthenticationSession: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // UIKit calls this on the main thread.
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            if let window = scenes.lazy.compactMap(\.keyWindow).first {
                return window
            }
            return ASPresentationAnchor()
        }
    }
}
