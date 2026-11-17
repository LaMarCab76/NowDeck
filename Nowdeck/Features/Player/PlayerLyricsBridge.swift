import SwiftUI

/// Turns the player's state into the inputs of lyrics mode (milestone 6).

extension PlaybackState {
    /// The track to look up in LRCLIB. Episodes, ads and unknown items have no lyrics.
    var lyricsTrack: LyricsTrack? {
        guard case .track(let track) = item, let firstArtist = track.artists.first?.name else {
            return nil
        }
        return LyricsTrack(spotifyID: track.id, title: track.name, artist: firstArtist,
                           album: track.album?.name, durationMs: track.durationMs)
    }

    /// Position and play state for the lyrics' own interpolation.
    func lyricsPlayback(fetchedAt: Date) -> LyricsPlayback {
        LyricsPlayback(progressMs: progressMs ?? 0, isPlaying: isPlaying, timestamp: fetchedAt)
    }
}

extension PlaybackOrigin {
    /// "Desde la playlist", already localized, as lyrics mode shows it above the name.
    var lyricsSourceLabel: String {
        let named = !(name ?? "").isEmpty
        switch kind {
        case .playlist: return named ? String(localized: "Desde la playlist") : String(localized: "Desde una playlist")
        case .album: return named ? String(localized: "Desde el álbum") : String(localized: "Desde un álbum")
        case .artist: return named ? String(localized: "Desde el artista") : String(localized: "Desde un artista")
        case .show: return named ? String(localized: "Desde el podcast") : String(localized: "Desde un podcast")
        case .likedSongs: return String(localized: "Desde Tus me gusta")
        }
    }
}

extension LyricsModeContent {
    init(item: NowPlaying, origin: PlaybackOrigin?, deviceName: String?) {
        // Lyrics mode shows the name line only when there is a name; otherwise the label
        // ("Desde una playlist") is the line.
        let name = origin.flatMap { ($0.name ?? "").isEmpty ? $0.lyricsSourceLabel : $0.name }
        let label = origin.flatMap { ($0.name ?? "").isEmpty ? nil : $0.lyricsSourceLabel }
        self.init(title: item.title, artist: item.subtitle, sourceLabel: label,
                  sourceName: name, deviceName: deviceName)
    }
}
