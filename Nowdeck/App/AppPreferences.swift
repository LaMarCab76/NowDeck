import Foundation

/// Settings that belong to this iPhone rather than to a theme, kept in `UserDefaults`.
///
/// Nothing here is sensitive (tokens and the Client ID stay in the Keychain). They are not
/// part of the theme because they depend on the device and the network, not on the look:
/// a shared theme should not carry someone else's lyrics delay.
@MainActor
final class AppPreferences: ObservableObject {
    /// How far the lyrics are moved, in milliseconds. Positive shows them **earlier**
    /// (useful when Spotify's position arrives late), negative later.
    @Published var lyricsOffsetMs: Int {
        didSet {
            let clamped = Self.clampedOffset(lyricsOffsetMs)
            if clamped != lyricsOffsetMs { lyricsOffsetMs = clamped; return }
            defaults.set(lyricsOffsetMs, forKey: Keys.lyricsOffsetMs)
        }
    }

    /// Experimental: read playlist folders from Spotify's internal playlist service
    /// (`PlaylistFolderService`). Off unless the user turns it on after reading the warning.
    @Published var usesPlaylistFolders: Bool {
        didSet { defaults.set(usesPlaylistFolders, forKey: Keys.usesPlaylistFolders) }
    }

    /// Whether the user already answered the folders step of the setup. A new login after an
    /// expired session does not ask again.
    @Published private(set) var hasAnsweredPlaylistFolders: Bool {
        didSet { defaults.set(hasAnsweredPlaylistFolders, forKey: Keys.answeredPlaylistFolders) }
    }

    static let lyricsOffsetRange = -3000...3000
    static let lyricsOffsetStep = 100

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lyricsOffsetMs = Self.clampedOffset(defaults.integer(forKey: Keys.lyricsOffsetMs))
        usesPlaylistFolders = defaults.bool(forKey: Keys.usesPlaylistFolders)
        hasAnsweredPlaylistFolders = defaults.bool(forKey: Keys.answeredPlaylistFolders)
    }

    func answerPlaylistFolders(enabled: Bool) {
        usesPlaylistFolders = enabled
        hasAnsweredPlaylistFolders = true
    }

    /// Rounds to the step and keeps the value inside `lyricsOffsetRange`.
    static func clampedOffset(_ value: Int) -> Int {
        let step = Double(lyricsOffsetStep)
        let rounded = Int((Double(value) / step).rounded()) * lyricsOffsetStep
        return min(max(rounded, lyricsOffsetRange.lowerBound), lyricsOffsetRange.upperBound)
    }

    private enum Keys {
        static let lyricsOffsetMs = "lyricsOffsetMs"
        static let usesPlaylistFolders = "usesPlaylistFolders"
        static let answeredPlaylistFolders = "answeredPlaylistFolders"
    }
}
