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
            // Assigning inside `didSet` does not run the observer again, so the clamped
            // value is written below in the same pass.
            let clamped = Self.clampedOffset(lyricsOffsetMs)
            if clamped != lyricsOffsetMs { lyricsOffsetMs = clamped }
            defaults.set(lyricsOffsetMs, forKey: Keys.lyricsOffsetMs)
        }
    }

    /// "Estilo de las letras": highlight word by word, or show the whole stanza.
    @Published var lyricsStyle: LyricsStyle {
        didSet { defaults.set(lyricsStyle.rawValue, forKey: Keys.lyricsStyle) }
    }

    /// Right of the progress bar: the time left ("−2:11") instead of the total duration.
    @Published var showsRemainingTime: Bool {
        didSet { defaults.set(showsRemainingTime, forKey: Keys.showsRemainingTime) }
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
    /// Kept in memory so reopening Biblioteca does not reset the notices.
    private var hasStartedPlaylistFolderSearch = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        lyricsOffsetMs = Self.clampedOffset(defaults.integer(forKey: Keys.lyricsOffsetMs))
        lyricsStyle = defaults.string(forKey: Keys.lyricsStyle).flatMap(LyricsStyle.init(rawValue:))
            ?? LyricsStyle.defaultStyle
        showsRemainingTime = defaults.bool(forKey: Keys.showsRemainingTime)
        usesPlaylistFolders = defaults.bool(forKey: Keys.usesPlaylistFolders)
        hasAnsweredPlaylistFolders = defaults.bool(forKey: Keys.answeredPlaylistFolders)
    }

    func answerPlaylistFolders(enabled: Bool) {
        usesPlaylistFolders = enabled
        hasAnsweredPlaylistFolders = true
    }

    /// The search and its possible failure are announced only on the first attempt.
    func beginPlaylistFolderSearch() -> Bool {
        guard !hasStartedPlaylistFolderSearch else { return false }
        hasStartedPlaylistFolderSearch = true
        return true
    }

    /// Rounds to the step and keeps the value inside `lyricsOffsetRange`.
    static func clampedOffset(_ value: Int) -> Int {
        let step = Double(lyricsOffsetStep)
        let rounded = Int((Double(value) / step).rounded()) * lyricsOffsetStep
        return min(max(rounded, lyricsOffsetRange.lowerBound), lyricsOffsetRange.upperBound)
    }

    private enum Keys {
        static let lyricsOffsetMs = "lyricsOffsetMs"
        static let lyricsStyle = "lyricsStyle"
        static let showsRemainingTime = "showsRemainingTime"
        static let usesPlaylistFolders = "usesPlaylistFolders"
        static let answeredPlaylistFolders = "answeredPlaylistFolders"
    }
}
