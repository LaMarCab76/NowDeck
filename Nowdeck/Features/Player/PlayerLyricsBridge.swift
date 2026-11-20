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

extension LyricsModeContent {
    init(item: NowPlaying, origin: PlaybackOrigin?, deviceName: String?,
         deviceType: String? = nil) {
        // The same two lines as the player: "Reproduciendo desde" over the name or the type.
        let name = origin?.displayName
        let label = origin == nil ? nil : PlaybackOrigin.heading
        self.init(title: item.title, artist: item.subtitle, isExplicit: item.isExplicit,
                  sourceLabel: label, sourceName: name, deviceName: deviceName,
                  deviceType: deviceType)
    }
}
