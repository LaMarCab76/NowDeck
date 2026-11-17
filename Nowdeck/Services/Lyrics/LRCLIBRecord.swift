import Foundation

/// The track to look up, taken from the Spotify item that is playing.
struct LyricsTrack: Equatable, Hashable, Sendable {
    /// Spotify `item.id`, the cache key. `nil` for local files, which are not cached.
    var spotifyID: String?
    var title: String
    /// The first artist only (docs/04-letras.md).
    var artist: String
    var album: String?
    var durationMs: Int
}

/// A lyrics record of the LRCLIB API (`/api/get`), as documented in "Lyrics record fields" of
/// https://lrclib.net/docs (checked 2026-11-17).
///
/// Only the fields Nowdeck uses are decoded. Everything that the docs mark as nullable, plus
/// `hasWordSync` and `lyricsfile` (added to the API in 2026), is optional so that an older or
/// partial answer still decodes.
struct LRCLIBRecord: Codable, Equatable, Sendable {
    var id: Int
    var trackName: String?
    var artistName: String?
    var albumName: String?
    /// Seconds. The docs call it a number; it can have decimals.
    var duration: Double?
    var instrumental: Bool?
    var hasWordSync: Bool?
    var plainLyrics: String?
    var syncedLyrics: String?
    var lyricsfile: String?
}

extension LRCLIBRecord {
    /// Picks the display mode of docs/04-letras.md ("Qué modo usar"):
    /// 1. `hasWordSync` → word by word, from `lyricsfile`;
    /// 2. `syncedLyrics` → whole stanzas, from the LRC;
    /// 3. otherwise (plain text only, instrumental) → `nil`, "sin letra".
    ///
    /// If the Lyricsfile cannot be read (unknown version, broken YAML), it falls back to the
    /// LRC instead of giving up.
    func syncedLyricsForDisplay() -> SyncedLyrics? {
        if instrumental == true { return nil }
        if hasWordSync == true, let lyricsfile,
           let wordSynced = try? LyricsfileParser.parse(lyricsfile) {
            return wordSynced
        }
        if let syncedLyrics, let lineSynced = LRCParser.parse(syncedLyrics) {
            return lineSynced
        }
        return nil
    }
}
