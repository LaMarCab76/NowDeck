import SwiftUI
import UIKit

/// What lyrics mode shows around the lyrics, provided by the player (milestone 2).
///
/// Texts are shown as they come: the player passes Spotify's names untouched and the source
/// label already localized ("Desde la playlist", "Desde el álbum", …).
struct LyricsModeContent: Equatable {
    var title: String
    /// All the artists, as the player shows them.
    var artist: String
    /// Marked like in the player (docs/06, "Explícito").
    var isExplicit = false
    /// "Desde la playlist". `nil` hides the source.
    var sourceLabel: String?
    /// Name of the playlist or album.
    var sourceName: String?
    /// Device that is playing. `nil` hides it.
    var deviceName: String?
    /// Spotify Connect type of that device, for its icon (`DeviceSymbol`).
    var deviceType: String?
}

/// Lyrics mode (`Main.dc.html`, `letras` block; docs/02-diseno.md, "Modo letras").
///
/// It replaces the player's top block, so the player gives it that block's frame (256 pt
/// high on the reference screen). Progress and controls stay below it, owned by the player.
///
/// - Top row (44): Spotify icon and source on the left, as in the normal view (the owner moved
///   the logo there on 2026-11-17; the mockup had it on the right). It opens Spotify.
/// - Center: current stanza (30 pt) and next stanza (22 pt), `width` of the usable width.
/// - Bottom row (56): artwork, title, artist and device.
struct LyricsModeView: View {
    let content: LyricsModeContent
    /// `nil` while the lyrics of a new track load: the center stays empty.
    let lyrics: SyncedLyrics?
    let playback: LyricsPlayback
    /// "Ancho de las letras" (Ajustes → Reproductor, stored in the theme).
    var width: Theme.LyricsWidth = .twoThirds
    /// "Sincronía de las letras" (Ajustes → Reproductor). Positive shows them earlier.
    var offsetMs: Int = 0
    /// The track's artwork, already loaded by the player. Shown as is, never cropped.
    var artwork: Image?
    /// Opens the playlist or album in Spotify (milestone 2).
    var onOpenSource: () -> Void = {}
    /// Opens Spotify from the logo (milestone 2).
    var onOpenSpotify: () -> Void = {}
    /// Opens the devices sheet (milestone 4).
    var onShowDevices: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Metrics.Lyrics.headerHeight)
            LyricsStanzasView(lyrics: lyrics, playback: playback, width: width, offsetMs: offsetMs)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
                .frame(height: Metrics.Lyrics.footerHeight)
        }
    }

    // MARK: - Top row

    private var header: some View {
        HStack(spacing: 0) {
            if let sourceName = content.sourceName {
                LyricsSourceButton(label: content.sourceLabel, name: sourceName, action: onOpenSource)
            } else {
                Button(action: onOpenSpotify) {
                    SpotifyLogoImage(variant: .icon)
                        .frame(height: Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Abrir en Spotify"))
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bottom row

    private var footer: some View {
        HStack(spacing: Metrics.Lyrics.footerSpacing) {
            LyricsArtwork(image: artwork)
            LyricsTrackLabels(title: content.title, artist: content.artist,
                              isExplicit: content.isExplicit)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let deviceName = content.deviceName {
                LyricsDeviceButton(name: deviceName, type: content.deviceType ?? "",
                                   action: onShowDevices)
            }
        }
    }
}

// MARK: - Stanzas

/// The current and next stanza, refreshed from the interpolated playback position: about 10
/// times a second in word mode and twice a second in stanza mode (docs/04-letras.md).
private struct LyricsStanzasView: View {
    let lyrics: SyncedLyrics?
    let playback: LyricsPlayback
    let width: Theme.LyricsWidth
    let offsetMs: Int

    /// The snapshot used for interpolation. Polls closer than 1.5 s to it are ignored so the
    /// lyrics do not jitter (see `LyricsPlayback.reconciled(with:)`).
    @State private var anchor: LyricsPlayback?
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        GeometryReader { proxy in
            if let lyrics {
                TimelineView(.periodic(from: .now, by: refreshInterval(for: lyrics))) { context in
                    let position = (anchor ?? playback).lyricsPositionMs(at: context.date,
                                                                     offsetMs: offsetMs)
                    if let frame = LyricsTimeline.frame(for: lyrics, atMs: position) {
                        stanzas(lyrics, frame: frame, width: proxy.size.width * width.fraction)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                }
            }
        }
        .onAppear { anchor = playback }
        .onChange(of: playback) { polled in
            anchor = (anchor ?? polled).reconciled(with: polled)
        }
        .onChange(of: lyrics) { _ in
            anchor = playback
        }
    }

    private func refreshInterval(for lyrics: SyncedLyrics) -> TimeInterval {
        // While paused nothing moves; a slow tick is enough.
        guard (anchor ?? playback).isPlaying else { return 1 }
        switch lyrics.sync {
        case .word: return 0.1
        case .line: return 0.5
        }
    }

    private func stanzas(_ lyrics: SyncedLyrics, frame: LyricsFrame, width: CGFloat) -> some View {
        let primary = lyrics.stanzas[frame.primaryIndex]
        let next = frame.nextIndex.map { lyrics.stanzas[$0] }

        return VStack(spacing: Metrics.Lyrics.stanzaSpacing) {
            primaryText(primary, sync: lyrics.sync, frame: frame)
                .textStyle(.currentStanza)
                .multilineTextAlignment(.center)
                // 3 lines of 38 + 12 + one line of 30 = 156, the height of the lyrics area on
                // the reference screen. Longer stanzas shrink instead of pushing the rows.
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .frame(width: width)
                .layoutPriority(1)
                .accessibilityLabel(Text(verbatim: primary.text))

            if let next {
                Text(verbatim: next.text)
                    .textStyle(.nextStanza)
                    .foregroundColor(theme.palette.pendingLyric.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: width)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Word mode: sung words in `texto`, the rest in `letraPendiente`. Stanza mode: the whole
    /// stanza in `texto`. A stanza that has not started yet is all `letraPendiente`.
    private func primaryText(_ stanza: LyricsStanza, sync: SyncedLyrics.Sync, frame: LyricsFrame) -> Text {
        let sungColor = theme.palette.text.color
        let pendingColor = theme.palette.pendingLyric.color

        guard frame.isPrimaryActive else {
            return Text(verbatim: stanza.text).foregroundColor(pendingColor)
        }
        switch sync {
        case .line:
            return Text(verbatim: stanza.text).foregroundColor(sungColor)
        case .word:
            let words = stanza.words
            let sung = words.prefix(frame.sungWordCount).map(\.text).joined()
            let pending = words.dropFirst(frame.sungWordCount).map(\.text).joined()
            if pending.isEmpty {
                return Text(verbatim: sung.trimmingTrailingWhitespace).foregroundColor(sungColor)
            }
            return Text(verbatim: sung).foregroundColor(sungColor)
                + Text(verbatim: pending.trimmingTrailingWhitespace).foregroundColor(pendingColor)
        }
    }
}

private extension String {
    var trimmingTrailingWhitespace: String {
        var result = self
        while result.last?.isWhitespace == true { result.removeLast() }
        return result
    }
}

// MARK: - Pieces

/// Spotify icon, "Desde la playlist" and the name in two lines. All of it opens the source in
/// Spotify.
private struct LyricsSourceButton: View {
    let label: String?
    let name: String
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Player.iconClearSpace) {
                SpotifyLogoImage(variant: .icon)
                VStack(alignment: .leading, spacing: 0) {
                    if let label {
                        Text(verbatim: label)
                            .textStyle(.lyricsSourceLabel)
                            .foregroundColor(theme.palette.secondaryText.color)
                            .lineLimit(1)
                    }
                    MarqueeText(verbatim: name)
                        .textStyle(.lyricsSourceName)
                        .foregroundColor(theme.palette.text.color)
                }
            }
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Abre en Spotify"))
    }
}

/// 56 pt artwork with the Spotify radius of 4. Fitted, never cropped.
private struct LyricsArtwork: View {
    let image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Palette.subtleSurface
            }
        }
        .frame(width: Metrics.Lyrics.artworkSize, height: Metrics.Lyrics.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: Radius.artwork))
        .accessibilityHidden(true)
    }
}

private struct LyricsTrackLabels: View {
    let title: String
    let artist: String
    let isExplicit: Bool
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Lyrics.titleArtistSpacing) {
            HStack(spacing: Spacing.xs) {
                MarqueeText(verbatim: title)
                    .textStyle(.lyricsTrackTitle)
                    .foregroundColor(theme.palette.text.color)
                if isExplicit {
                    // Not in the mockup; Spotify asks to mark explicit content (docs/06).
                    Image(systemName: "e.square.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(theme.palette.secondaryText.color)
                        .accessibilityLabel(Text("Explícito"))
                }
            }
            MarqueeText(verbatim: artist)
                .textStyle(.lyricsArtist)
                .foregroundColor(theme.palette.secondaryText.color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Device name in the accent color. Opens the devices sheet.
private struct LyricsDeviceButton: View {
    let name: String
    let type: String
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Lyrics.deviceIconSpacing) {
                DeviceSymbol.image(for: type)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: Metrics.Lyrics.deviceIconSize, height: Metrics.Lyrics.deviceIconSize)
                    .accessibilityHidden(true)
                MarqueeText(verbatim: name)
                    .textStyle(.lyricsDevice)
            }
            .foregroundColor(theme.palette.accent.color)
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Reproduciendo en \(name)"))
        .accessibilityHint(Text("Abre la lista de dispositivos"))
    }
}
