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
        /// The optional playlist-folders mode, asked once after the first login.
        case folders
        /// "¡Listo!" after a successful login, shown for a moment before the player.
        case connected
    }

    /// A message shown on the Client ID step after a failed or expired login.
    enum Notice: Equatable {
        case sessionExpired
        case savedClientIDRejected
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
            case .savedClientIDRejected:
                return "Spotify ya no reconoce el Client ID guardado. Puede que la app se haya borrado en el panel de Spotify: pegá el Client ID de tu app o creá una nueva."
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

    /// Settings of this iPhone (lyrics offset, playlist folders).
    let preferences: AppPreferences

    private let credentials: CredentialStore
    private let accounts: SpotifyAccountsClient
    private let accessCheck: SpotifyAccessCheck
    private let webAuthenticator: any WebAuthenticating

    init(
        credentials: CredentialStore,
        accounts: SpotifyAccountsClient = SpotifyAccountsClient(),
        accessCheck: SpotifyAccessCheck = SpotifyAccessCheck(),
        webAuthenticator: any WebAuthenticating,
        preferences: AppPreferences = AppPreferences()
    ) {
        self.preferences = preferences
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
        // Before any window exists, so the app launches in the right orientation.
        OrientationController.shared.prepare(for: route)
    }

    /// The app's real dependencies.
    ///
    /// Keychain items survive deleting the app, so after a reinstall the user may come back
    /// logged in. That is intended: if those credentials no longer work, the first refresh
    /// fails and `sessionWasRejected` sends the user back to the setup.
    convenience init() {
        self.init(credentials: CredentialStore(store: KeychainStore()),
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
            // The folders step is asked only once; "¡Listo!" calls `finishOnboarding()` when
            // its animation ends.
            route = .onboarding(preferences.hasAnsweredPlaylistFolders ? .connected : .folders)
        } catch {
            notice = Self.notice(for: error)
        }
    }

    /// Called by the token manager when Spotify rejects the stored credentials. The tokens
    /// are already deleted.
    func sessionWasRejected(_ error: AuthError) {
        tokenManager = nil
        if error == .invalidClient {
            // The Client ID itself is no longer valid: don't prefill it again.
            try? credentials.removeClientID()
            savedClientID = nil
            notice = .savedClientIDRejected
        } else {
            notice = .sessionExpired
        }
        route = .onboarding(.clientID)
    }

    // MARK: Playlist editing (2026-11-18)

    /// Whether the stored session was granted the playlist-editing scopes. `.unknown` when
    /// Spotify sent no `scope` with the tokens: the sheet lets the user add, and offers the
    /// permission only if Spotify answers `403`.
    func playlistEditingGrant() -> PlaylistEditingAccess.Grant {
        guard let tokens = try? credentials.tokens() else { return .missing }
        let granted = Set(tokens.scope.split(separator: " ").map(String.init))
        if granted.isEmpty { return .unknown }
        return SpotifyAuthorization.playlistEditingScopes.allSatisfy(granted.contains)
            ? .granted : .missing
    }

    /// Logs in again with the stored Client ID, asking for every scope, and keeps the user
    /// on the player. The token manager reads the Keychain on every request, so the new
    /// tokens apply right away without rebuilding the player. `nil` when it worked.
    ///
    /// The new tokens are kept only if they belong to the same account (`GET /me`): the
    /// player and the sheet's caches belong to the account that was logged in, so a
    /// different one is rejected instead of swapped in silently.
    func requestPlaylistEditing() async -> PlaylistEditingAccess.Failure? {
        guard let clientID = savedClientID, let tokenManager else { return .failed }
        guard !isConnecting else { return .failed }
        isConnecting = true
        defer { isConnecting = false }

        do {
            // Before opening Spotify: there is no point in logging in if this fails.
            let currentUserID = try await accessCheck.userID(
                accessToken: tokenManager.validAccessToken())

            let login = SpotifyLogin(webAuthenticator: webAuthenticator, accounts: accounts)
            let tokens = try await login.logIn(clientID: clientID)
            // Same check as the first login: a 403 means this account cannot use the app.
            if case .forbidden = try await accessCheck.run(accessToken: tokens.accessToken) {
                return .notAllowlisted
            }
            guard try await accessCheck.userID(accessToken: tokens.accessToken) == currentUserID
            else { return .differentAccount }
            try credentials.setTokens(tokens)
            return nil
        } catch AuthError.cancelled {
            return .cancelled
        } catch AuthError.accessDenied {
            return .denied
        } catch AuthError.network {
            return .offline
        } catch {
            return .failed
        }
    }

    /// What the player's Agregar a una playlist sheet needs from the session.
    var playlistEditingAccess: PlaylistEditingAccess {
        PlaylistEditingAccess(
            grant: { [weak self] in self?.playlistEditingGrant() ?? .missing },
            request: { [weak self] in
                guard let self else { return .failed }
                return await self.requestPlaylistEditing()
            })
    }

    /// The answer of the folders step. Then "¡Listo!".
    func answerPlaylistFolders(enabled: Bool) {
        guard route == .onboarding(.folders) else { return }
        preferences.answerPlaylistFolders(enabled: enabled)
        route = .onboarding(.connected)
    }

    /// Leaves the "¡Listo!" screen for the player. Does nothing from any other screen.
    func finishOnboarding() {
        guard route == .onboarding(.connected), tokenManager != nil else { return }
        route = .player
    }

    // MARK: Helpers

    private func makeTokenManager(clientID: String) -> TokenManager {
        TokenManager(clientID: clientID, credentials: credentials, accounts: accounts,
                     onSessionRejected: { [weak self] error in
                         await self?.sessionWasRejected(error)
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
}
