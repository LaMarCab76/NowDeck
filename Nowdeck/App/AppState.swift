import SwiftUI

/// App-wide navigation and session state.
///
/// Decides the first screen from what is stored in the Keychain, runs the login, and sends
/// the user back to the Client ID step when Spotify rejects the session.
@MainActor
final class AppState: ObservableObject {
    enum Route: Equatable {
        case onboarding(OnboardingStep)
        case player
    }

    enum OnboardingStep: Equatable {
        case welcome
        case createApp
        case clientID
    }

    /// A message shown on the Client ID step after a failed or expired login.
    enum Notice: Equatable {
        case sessionExpired
        case notAllowlisted
        case invalidClientID
        case accessDenied
        case loginClosed
        case offline
        case failed

        var message: LocalizedStringResource {
            switch self {
            case .sessionExpired:
                return "Tu sesión de Spotify venció. Conectate de nuevo para seguir."
            case .notAllowlisted:
                return "Spotify no deja usar tu app con esta cuenta. Entrá con la misma cuenta con la que creaste la app, o sumala en Users Management, en los ajustes de tu app en el panel de Spotify."
            case .invalidClientID:
                return "Spotify no reconoce este Client ID. Revisá que sea el de tu app."
            case .accessDenied:
                return "Para usar Nowdeck tenés que aceptar los permisos en Spotify."
            case .loginClosed:
                return "Se cerró el inicio de sesión. Si Spotify mostró un error, revisá el Client ID y que el Redirect URI sea nowdeck://callback."
            case .offline:
                return "No hay conexión a internet. Revisala y probá de nuevo."
            case .failed:
                return "No pudimos conectar con Spotify. Probá de nuevo en un rato."
            }
        }
    }

    @Published var route: Route
    @Published private(set) var notice: Notice?
    @Published private(set) var isConnecting = false
    /// The stored Client ID, used to prefill the field after an expired session.
    @Published private(set) var savedClientID: String?

    /// Available while logged in. The API client (milestone 2) gets its tokens from here.
    private(set) var tokenManager: TokenManager?

    private let credentials: CredentialStore
    private let accounts: SpotifyAccountsClient
    private let accessCheck: SpotifyAccessCheck
    private let webAuthenticator: any WebAuthenticating

    init(
        credentials: CredentialStore,
        accounts: SpotifyAccountsClient = SpotifyAccountsClient(),
        accessCheck: SpotifyAccessCheck = SpotifyAccessCheck(),
        webAuthenticator: any WebAuthenticating
    ) {
        self.credentials = credentials
        self.accounts = accounts
        self.accessCheck = accessCheck
        self.webAuthenticator = webAuthenticator

        // A Keychain read error is treated as "nothing stored": the user connects again.
        let clientID = try? credentials.clientID()
        let tokens = try? credentials.tokens()
        savedClientID = clientID

        switch (clientID, tokens) {
        case let (clientID?, _?):
            route = .player
            tokenManager = makeTokenManager(clientID: clientID)
        case (_?, nil):
            route = .onboarding(.clientID)
        case (nil, _):
            route = .onboarding(.welcome)
        }
    }

    /// The app's real dependencies.
    convenience init() {
        let keychain = KeychainStore()
        Self.clearKeychainOnFirstLaunch(keychain)
        self.init(credentials: CredentialStore(store: keychain),
                  webAuthenticator: WebAuthenticationSession())
    }

    // MARK: Onboarding

    func showOnboardingStep(_ step: OnboardingStep) {
        route = .onboarding(step)
    }

    func dismissNotice() {
        notice = nil
    }

    /// Saves the Client ID, logs in and checks API access. On success the app moves to the
    /// player; otherwise it stays on the Client ID step with a message.
    func connect(clientID rawClientID: String) async {
        let clientID = ClientID.normalized(rawClientID)
        guard ClientID.isValid(clientID), !isConnecting else { return }

        isConnecting = true
        notice = nil
        defer { isConnecting = false }

        do {
            try credentials.setClientID(clientID)
            savedClientID = clientID

            let login = SpotifyLogin(webAuthenticator: webAuthenticator, accounts: accounts)
            let tokens = try await login.logIn(clientID: clientID)

            switch try await accessCheck.run(accessToken: tokens.accessToken) {
            case .forbidden:
                // Keep nothing: these tokens cannot be used for anything.
                notice = .notAllowlisted
                return
            case .ok, .rateLimited, .failed:
                // Only a 403 means the account is wrong. Other answers are temporary and the
                // player handles them (milestone 2).
                break
            }

            try credentials.setTokens(tokens)
            tokenManager = makeTokenManager(clientID: clientID)
            route = .player
        } catch {
            notice = Self.notice(for: error)
        }
    }

    /// Called by the token manager when Spotify rejects the refresh token.
    func sessionDidExpire() {
        tokenManager = nil
        notice = .sessionExpired
        route = .onboarding(.clientID)
    }

    // MARK: Helpers

    private func makeTokenManager(clientID: String) -> TokenManager {
        TokenManager(clientID: clientID, credentials: credentials, accounts: accounts,
                     onSessionExpired: { [weak self] in
                         await self?.sessionDidExpire()
                     })
    }

    static func notice(for error: Error) -> Notice? {
        switch error {
        case AuthError.cancelled: return .loginClosed
        case AuthError.accessDenied: return .accessDenied
        case AuthError.invalidClient: return .invalidClientID
        case AuthError.invalidGrant: return .sessionExpired
        case AuthError.network: return .offline
        default: return .failed
        }
    }

    /// Keychain items survive deleting the app. Without this, reinstalling would silently log
    /// the user back in with old credentials. `UserDefaults` only stores a flag here, never a
    /// secret.
    private static func clearKeychainOnFirstLaunch(_ keychain: KeychainStore) {
        let key = "didLaunchBefore"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        try? keychain.removeAll()
        UserDefaults.standard.set(true, forKey: key)
    }
}
