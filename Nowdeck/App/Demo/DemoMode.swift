#if DEBUG
import Foundation

/// Demo mode for screenshots: the app runs on made-up data and never talks to Spotify or
/// LRCLIB. Debug builds only, and only when launched with the `-demoMode` argument:
///
///     xcrun simctl launch <device> <bundle id> -demoMode YES
///
/// How it works: the app's network clients (`SpotifyAPI`, `LRCLIBClient`, `ArtworkLoader`)
/// use `URLSession.shared`, and a `URLProtocol` registered with `URLProtocol.registerClass`
/// answers every request of that session. `DemoURLProtocol` answers from `DemoContent`, draws
/// the covers (`DemoArtwork`) and returns `404` for anything else, so no request leaves the
/// device. `AsyncImage` uses its own session, so `CardArtwork` draws the demo covers itself.
///
/// The session lives in an in-memory store with fake tokens: the real Keychain is neither
/// read nor written. Preferences and themes are kept apart from the real ones too.
enum DemoMode {
    static let launchArgument = "-demoMode"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Answers the app's requests from now on. Call before any request is made.
    static func start() {
        URLProtocol.registerClass(DemoURLProtocol.self)
    }

    /// Credentials that look logged in, so the app opens on the player.
    static func credentials() -> CredentialStore {
        let credentials = CredentialStore(store: DemoSecureStore())
        try? credentials.setClientID("00000000000000000000000000000000")
        try? credentials.setTokens(OAuthTokens(
            accessToken: "demo-access-token",
            refreshToken: "demo-refresh-token",
            // Never expires during a session, so the token manager never refreshes.
            expiresAt: Date().addingTimeInterval(365 * 24 * 60 * 60),
            scope: SpotifyAuthorization.scopes.joined(separator: " ")))
        return credentials
    }

    /// Themes in a temporary folder, emptied on every demo launch: switching themes for a
    /// screenshot never touches the real `active` and `custom` theme files, and each demo
    /// session starts on the default theme.
    static func themeStorage() -> ThemeStorage {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NowdeckDemo/Theme", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        return ThemeStorage(directory: directory)
    }

    /// Separate settings, so the demo leaves the real ones alone.
    @MainActor
    static func preferences() -> AppPreferences {
        let defaults = UserDefaults(suiteName: "nowdeck.demo") ?? .standard
        return AppPreferences(defaults: defaults)
    }
}

/// `SecureStore` kept in memory for the demo session.
private final class DemoSecureStore: SecureStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    func data(forKey key: String) throws -> Data? {
        lock.withLock { values[key] }
    }

    func set(_ data: Data, forKey key: String) throws {
        lock.withLock { values[key] = data }
    }

    func removeValue(forKey key: String) throws {
        lock.withLock { values[key] = nil }
    }
}
#endif
