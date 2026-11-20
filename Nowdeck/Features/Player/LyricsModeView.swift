import SwiftUI
import UIKit

/// What lyrics mode shows around the lyrics, provided by the player (milestone 2).
///
/// Texts are shown as they come: the player passes Spotify's names untouched and the source
/// label already localized ("Reproduciendo desde").
struct LyricsModeContent: Equatable {
    var title: String
    /// All the artists, as the player shows them.
    var artist: String
    /// Marked like in the player (docs/06, "Explícito").
    var isExplicit = false
    /// "Reproduciendo desde". `nil` hides the source.
    var sourceLabel: String?
    /// Name of the playlist or album, or its type when the name is unknown.
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
///   Dragging up or down browses the stanzas; tapping one moves the playback there
///   (`LyricsBrowsing`).
/// - Bottom row (56): artwork, title, artist and device. It is the band of the track swipe.
struct LyricsModeView: View {
    let content: LyricsModeContent
    /// `nil` while the lyrics of a new track load: the center stays empty.
    let lyrics: SyncedLyrics?
    let playback: LyricsPlayback
    /// "Ancho de las letras" (Ajustes → Reproductor, stored in the theme).
    var width: Theme.LyricsWidth = .twoThirds
    /// "Sincronía de las letras" (Ajustes → Reproductor). Positive shows them earlier.
    var offsetMs: Int = 0
    /// "Estilo de las letras" (Ajustes → Reproductor). Stanza style drops the word highlight.
    var style: LyricsStyle = .byWord
    /// The track's artwork, already loaded by the player. Shown as is, never cropped.
    var artwork: Image?
    /// Opens the playlist or album in Spotify (milestone 2).
    var onOpenSource: () -> Void = {}
    /// Opens Spotify from the logo (milestone 2).
    var onOpenSpotify: () -> Void = {}
    /// Opens the devices sheet (milestone 4).
    var onShowDevices: () -> Void = {}
    /// Moves the playback to a position in ms: tapping a stanza (`LyricsBrowsing`). `nil`
    /// where Spotify forbids seeking: the lyrics then take no touches.
    var onSeek: ((Int) -> Void)?
    /// The track swipe works on the bottom row only, never on the lyrics: the row follows
    /// the finger and the next or previous item's row comes in from the side.
    var swipe: TrackSwipePhase = .idle
    var pageWidth: CGFloat = 0
    var upNext: TrackPreview?
    var previousTrack: TrackPreview?

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: Metrics.Lyrics.headerHeight)
            LyricsStanzasView(lyrics: lyrics?.displayed(as: style), playback: playback, width: width,
                              offsetMs: offsetMs, onSeek: onSeek)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var theme: ThemeStore

    /// Changes with the track, for the footer's animations.
    private var trackKey: String { content.title + "|" + content.artist }

    private var footer: some View {
        ZStack(alignment: .leading) {
            currentFooter
                .offset(x: swipe.offset(pageWidth: pageWidth))
            if let edge = swipe.edge {
                previewFooter(edge: edge)
                    .offset(x: swipe.previewOffset(pageWidth: pageWidth))
            }
        }
        .trackSwipeBand()
    }

    /// While a swiped-in item settles, the row swaps to it without animation (see
    /// `PlayerView.animatesTrackChange`).
    private var animatesTrackChange: Bool { !swipe.isLanding }

    private var currentFooter: some View {
        HStack(spacing: Metrics.Lyrics.footerSpacing) {
            ZStack {
                LyricsArtwork(image: artwork)
                    .id(trackKey)
                    .transition(.opacity)
            }
            .animation(animatesTrackChange ? Motion.artworkCrossfade : nil, value: trackKey)
            ZStack(alignment: .leading) {
                LyricsTrackLabels(title: content.title, artist: content.artist,
                                  isExplicit: content.isExplicit)
                    .id(trackKey)
                    .transition(Motion.rise(Motion.trackRise, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(animatesTrackChange ? Motion.trackChange : nil, value: trackKey)
            deviceButton(action: onShowDevices)
        }
    }

    private func previewFooter(edge: TrackSwipe.Edge) -> some View {
        let preview: TrackPreview?
        switch swipe {
        case .landing(_, let frozen, _): preview = frozen
        default: preview = edge == .right ? upNext : previousTrack
        }
        return HStack(spacing: Metrics.Lyrics.footerSpacing) {
            LyricsArtwork(image: preview?.artwork.map(Image.init(uiImage:)))
            Group {
                if let item = preview?.item {
                    LyricsTrackLabels(title: item.title, artist: item.subtitle,
                                      isExplicit: item.isExplicit)
                } else {
                    Text(edge == .right ? "Siguiente" : "Anterior")
                        .textStyle(.lyricsTrackTitle)
                        .foregroundColor(theme.palette.secondaryText.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            deviceButton(action: {})
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func deviceButton(action: @escaping () -> Void) -> some View {
        if let deviceName = content.deviceName {
            LyricsDeviceButton(name: deviceName, type: content.deviceType ?? "", action: action)
        }
    }
}

// MARK: - Stanzas

/// The current and next stanza, refreshed from the interpolated playback position: about 10
/// times a second in word mode and twice a second in stanza mode (docs/04-letras.md).
///
/// With `onSeek`, the stanzas can be browsed and tapped (`LyricsBrowsing`).
private struct LyricsStanzasView: View {
    let lyrics: SyncedLyrics?
    let playback: LyricsPlayback
    let width: Theme.LyricsWidth
    let offsetMs: Int
    let onSeek: ((Int) -> Void)?

    /// The snapshot used for interpolation. Polls closer than 1.5 s to it are ignored so the
    /// lyrics do not jitter (see `LyricsPlayback.reconciled(with:)`).
    @State private var anchor: LyricsPlayback?
    /// The stanza the user browsed to, shown instead of the playback's; `nil` follows the
    /// playback.
    @State private var browseIndex: Int?
    /// The stanza the current drag started from.
    @State private var dragStartIndex: Int?
    /// Changes with every browsing touch, to restart the idle timeout.
    @State private var browseTouches = 0
    @GestureState private var isDragging = false
    @EnvironmentObject private var theme: ThemeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            if let lyrics {
                TimelineView(.periodic(from: .now, by: refreshInterval(for: lyrics))) { context in
                    let frame = browseIndex.flatMap { LyricsBrowsing.frame(browsing: $0, in: lyrics) }
                        ?? LyricsTimeline.frame(for: lyrics, atMs: position(at: context.date))
                    // The ZStack keeps its identity between ticks, so when the stanza index
                    // changes the old stanzas rise away and the new ones come in. While
                    // browsing they cross-fade instead: rising would look wrong going back.
                    ZStack {
                        if let frame {
                            stanzas(lyrics, frame: frame, width: proxy.size.width * width.fraction)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                                .id(frame.primaryIndex)
                                .transition(browseIndex == nil
                                    ? Motion.rise(Motion.stanzaRise, reduceMotion: reduceMotion)
                                    : .opacity)
                        }
                    }
                    .animation(Motion.stanzaChange, value: frame?.primaryIndex)
                }
                .transition(.opacity)
                // The whole lyrics area, also when no stanza is shown (after the last one):
                // an empty ZStack has no size and would take no touches.
                .frame(width: proxy.size.width, height: proxy.size.height)
                .contentShape(Rectangle())
                .simultaneousGesture(onSeek == nil ? nil : browseGesture(lyrics))
            }
        }
        // New lyrics (another track) fade in instead of popping.
        .animation(Motion.modeChange, value: lyrics == nil)
        .onAppear { anchor = playback }
        .onChange(of: playback) { polled in
            anchor = (anchor ?? polled).reconciled(with: polled)
        }
        .onChange(of: lyrics) { _ in
            anchor = playback
            browseIndex = nil
        }
        .onChange(of: isDragging) { dragging in
            // Every drag that ends, also one the system cancels (when `onEnded` is not
            // called), forgets where it started and restarts the idle timeout. Otherwise a
            // cancelled first drag would leave the lyrics on the browsed stanza for good.
            guard !dragging else { return }
            dragStartIndex = nil
            browseTouches += 1
        }
        .onChange(of: onSeek == nil) { forbidden in
            if forbidden { browseIndex = nil }
        }
        .task(id: browseTouches) {
            guard browseIndex != nil else { return }
            try? await Task.sleep(nanoseconds: UInt64(LyricsBrowsing.idleTimeout * 1_000_000_000))
            guard !Task.isCancelled, !isDragging else { return }
            withAnimation(Motion.lyricsBrowseEnd) { browseIndex = nil }
        }
    }

    private func position(at date: Date) -> Int {
        (anchor ?? playback).lyricsPositionMs(at: date, offsetMs: offsetMs)
    }

    // MARK: Browsing and seeking

    private func browseGesture(_ lyrics: SyncedLyrics) -> some Gesture {
        DragGesture(minimumDistance: LyricsBrowsing.dragMinimumDistance)
            .updating($isDragging) { _, dragging, _ in dragging = true }
            .onChanged { drag in
                let start = dragStartIndex ?? browseIndex
                    ?? LyricsBrowsing.startIndex(for: lyrics, atMs: position(at: Date()))
                dragStartIndex = start
                let index = LyricsBrowsing.index(from: start, translation: drag.translation.height,
                                                 count: lyrics.stanzas.count)
                if index != browseIndex {
                    // Each stanza passing under the finger is felt, like a picker's notches.
                    if browseIndex != nil || index != start {
                        UISelectionFeedbackGenerator().selectionChanged()
                    }
                    browseIndex = index
                }
            }
    }

    /// Moves the playback to where `index` starts and follows the playback again.
    private func seek(to index: Int, in lyrics: SyncedLyrics) {
        guard let onSeek, lyrics.stanzas.indices.contains(index) else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let target = LyricsBrowsing.seekTarget(for: lyrics.stanzas[index], offsetMs: offsetMs)
        onSeek(target)
        // The new position reaches `playback` only on the next render; anchoring it now
        // keeps the old stanza from flashing between the browsed one and the playback.
        anchor = LyricsPlayback(progressMs: target, isPlaying: (anchor ?? playback).isPlaying,
                                timestamp: Date())
        browseIndex = nil
    }

    /// When a stanza starts, in the playback's time, for the label shown while browsing.
    private func startLabel(for stanza: LyricsStanza) -> String {
        PlaybackProgress.formatted(ms: LyricsBrowsing.seekTarget(for: stanza, offsetMs: offsetMs))
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
            if browseIndex != nil {
                // Where a tap on the stanza below jumps to.
                Label(startLabel(for: primary), systemImage: "play.fill")
                    .textStyle(.lyricsBrowseTime)
                    .foregroundColor(theme.palette.accent.color)
                    .accessibilityHidden(true)
            }

            primaryText(primary, sync: lyrics.sync, frame: frame)
                .textStyle(.currentStanza)
                .multilineTextAlignment(.center)
                // 3 lines of 38 + 12 + one line of 30 = 156, the height of the lyrics area on
                // the reference screen. Longer stanzas shrink instead of pushing the rows.
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .frame(width: width)
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture { seek(to: frame.primaryIndex, in: lyrics) }
                .allowsHitTesting(onSeek != nil)
                .accessibilityLabel(Text(verbatim: primary.text))
                .modifier(SeekToStanzaAction(isEnabled: onSeek != nil) {
                    seek(to: frame.primaryIndex, in: lyrics)
                })

            if let next, let nextIndex = frame.nextIndex {
                Text(verbatim: next.text)
                    .textStyle(.nextStanza)
                    .foregroundColor(theme.palette.pendingLyric.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: width)
                    .contentShape(Rectangle())
                    .onTapGesture { seek(to: nextIndex, in: lyrics) }
                    .allowsHitTesting(onSeek != nil)
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

/// VoiceOver: "Reproducir desde acá" on the current stanza, where seeking is allowed.
private struct SeekToStanzaAction: ViewModifier {
    var isEnabled: Bool
    var action: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAction(named: Text("Reproducir desde acá"), action)
        } else {
            content
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

/// Spotify icon, "Reproduciendo desde" and the name in two lines. All of it opens the source in
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
