import SwiftUI

/// The player (`Main.dc.html`, rearranged on 2026-11-17): the origin row across the top,
/// artwork and text below it, then progress and controls.
struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var lyrics: LyricsModeController
    var actions: PlayerActions
    var showsLyricsButton: Bool
    /// Full screen width, to adapt to the iPhone 8 Plus (736 pt).
    var screenWidth: CGFloat
    /// The track swipe (`PlayerContent`, `TrackSwipe`): moves the cover and title, and shows the next or
    /// previous item beside them.
    var swipe: TrackSwipePhase = .idle

    private typealias Layout = Metrics.Player

    var body: some View {
        // The gap is the spacer's minimum: a VStack spacing would also be added on both
        // sides of the spacer (40 pt instead of 20), and the screen has none to spare
        // (16 + 264 + 20 + 94 + 20 = 414).
        VStack(spacing: 0) {
            topBlock
            Spacer(minLength: Spacing.Player.blockGap)
            bottomBlock
        }
    }

    // MARK: Top block

    private var artworkSide: CGFloat {
        min(Layout.artworkSize, (screenWidth * Layout.artworkWidthFraction).rounded(.down))
    }

    @EnvironmentObject private var theme: ThemeStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The normal top block, or lyrics mode in its place (docs/02, "Modo letras"). They
    /// cross-fade.
    private var topBlock: some View {
        ZStack {
            topBlockContent
        }
        .animation(Motion.modeChange, value: lyrics.showsLyricsMode)
    }

    @ViewBuilder
    private var topBlockContent: some View {
        if lyrics.showsLyricsMode, let item = model.nowPlaying, let playback = model.playback {
            LyricsModeView(
                content: LyricsModeContent(item: item, origin: model.origin,
                                           deviceName: playback.device?.name,
                                           deviceType: playback.device?.type),
                lyrics: lyrics.lyrics,
                playback: playback.lyricsPlayback(fetchedAt: model.fetchedAt),
                width: theme.lyricsWidth,
                offsetMs: preferences.lyricsOffsetMs,
                style: preferences.lyricsStyle,
                artwork: model.artwork.map(Image.init(uiImage:)),
                // Never a dead tap (both buttons): without the source's link, the item; without either,
                // `SpotifyLink.open` falls back to Spotify's home page, as the normal view does.
                onOpenSource: { [url = model.origin?.url ?? item.itemURL] in
                    SpotifyLink.open(url)
                },
                onOpenSpotify: { [url = model.origin?.url ?? item.itemURL] in
                    SpotifyLink.open(url)
                },
                onShowDevices: actions.devices,
                onSeek: canSeek ? actions.seek : nil,
                swipe: swipe,
                pageWidth: screenWidth,
                upNext: model.upNext,
                previousTrack: model.previousTrack
            )
            .frame(height: Layout.upperAreaHeight)
            .transition(.opacity)
        } else {
            normalTopBlock
                .transition(.opacity)
        }
    }

    /// The origin row across the whole width, so "Reproduciendo desde …" always sits in the
    /// top-left corner, and below it the artwork with the title, artist and device.
    ///
    /// The cover, title and device row form a page that follows the track swipe; the page of
    /// the next or previous item comes in one screen width away, from the side it belongs
    /// to. The device row moves with its page: if it stayed still, the moving cover
    /// would pass under it (docs/06: nothing on top of the cover). The origin and everything
    /// below stay still.
    private var normalTopBlock: some View {
        VStack(spacing: Layout.topRowBottomGap) {
            PlayerTopRow(origin: model.origin, logoURL: model.nowPlaying?.itemURL,
                         actions: actions)
            ZStack(alignment: .topLeading) {
                currentPage
                    .offset(x: swipe.offset(pageWidth: screenWidth))
                if let edge = swipe.edge {
                    previewPage(edge: edge)
                        .offset(x: swipe.previewOffset(pageWidth: screenWidth))
                }
            }
            .frame(height: Layout.topBlockHeight, alignment: .top)
            .trackSwipeBand()
        }
        .frame(height: Layout.upperAreaHeight, alignment: .top)
    }

    /// While a swiped-in item settles in the middle, the current page swaps to it without
    /// its usual cross-fade and rise: it is off screen, and comes back already showing it.
    private var animatesTrackChange: Bool { !swipe.isLanding }

    private var currentPage: some View {
        TrackPage(artworkSide: artworkSide, artwork: model.artwork,
                  animatesArtwork: animatesTrackChange,
                  deviceRow: DeviceRow(device: model.playback?.device, freshness: model.freshness,
                                       action: actions.devices)) {
            ZStack(alignment: .leading) {
                if let item = model.nowPlaying {
                    // A new track: the old title rises away and the new one comes in.
                    TitleBlock(item: item)
                        .id(item.transitionKey)
                        .transition(Motion.rise(Motion.trackRise, reduceMotion: reduceMotion))
                }
            }
            .animation(animatesTrackChange ? Motion.trackChange : nil,
                       value: model.nowPlaying?.transitionKey)
        }
    }

    private func previewPage(edge: TrackSwipe.Edge) -> some View {
        let preview: TrackPreview?
        switch swipe {
        case .landing(_, let frozen, _): preview = frozen
        default: preview = edge == .right ? model.upNext : model.previousTrack
        }
        return TrackPage(artworkSide: artworkSide, artwork: preview?.artwork,
                         animatesArtwork: true,
                         // The same device: the item will play there too.
                         deviceRow: DeviceRow(device: model.playback?.device,
                                              freshness: model.freshness, action: {}),
                         placeholderSymbol: preview == nil
                             ? (edge == .right ? "forward.end.fill" : "backward.end.fill") : nil) {
            if let item = preview?.item {
                TitleBlock(item: item)
            } else {
                // Not known yet (queue not read, or nothing seen before this one).
                Text(edge == .right ? "Siguiente" : "Anterior")
                    .textStyle(.trackTitle)
                    .foregroundStyle(theme.palette.secondaryText.color)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Bottom block

    /// The theme's optional controls in its order. `showsLyricsButton` comes from the same
    /// theme list; it is applied again here so callers can still turn the button off.
    private var optionalControls: [Theme.PlayerControl] {
        theme.playerControls.filter { $0 != .lyrics || showsLyricsButton }
    }

    /// Spotify allows moving the playback here (`actions.disallows.seeking`, restricted
    /// device): the progress bar and the stanzas of lyrics mode take the finger.
    private var canSeek: Bool {
        ControlAvailability(playback: model.playback).seek
    }

    private var bottomBlock: some View {
        VStack(spacing: Layout.bottomBlockGap) {
            if let item = model.nowPlaying, let playback = model.playback {
                ProgressRow(itemKey: item.transitionKey,
                            progressMs: playback.progressMs ?? 0, durationMs: item.durationMs,
                            isPlaying: playback.isPlaying, fetchedAt: model.fetchedAt,
                            showsRemainingTime: preferences.showsRemainingTime,
                            onToggleTime: { preferences.showsRemainingTime.toggle() },
                            onSeek: canSeek ? actions.seek : nil)
            }
            PlayerControls(playback: model.playback, actions: actions,
                           controls: optionalControls,
                           lyricsActive: lyrics.isButtonActive,
                           canAddToPlaylist: model.nowPlaying?.playlistURI != nil,
                           volume: model.controls.volume)
        }
    }
}

// MARK: - Artwork

/// The cover as Spotify sends it: fitted (never cropped), with the 4 pt radius of the
/// guidelines, and nothing on top of it (docs/06-cumplimiento.md).
///
/// A new cover cross-fades over the previous one (only covers are layered, never text or
/// controls).
struct ArtworkView: View {
    var image: UIImage?
    var side: CGFloat
    /// `false` swaps covers at once (an item that arrived by swiping).
    var animates = true
    /// Drawn on the empty square (never on a cover): the swipe preview of an unknown item.
    var placeholderSymbol: String?

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    // While it loads, or when the item has no cover (local files, ads).
                    Palette.subtleSurface
                        .overlay {
                            if let placeholderSymbol {
                                Image(systemName: placeholderSymbol)
                                    .font(.system(size: Metrics.Player.previewSymbolSize,
                                                  weight: .semibold))
                                    .opacity(0.5)
                            }
                        }
                }
            }
            .id(image.map(ObjectIdentifier.init))
            .transition(.opacity)
        }
        .animation(animates ? Motion.artworkCrossfade : nil,
                   value: image.map(ObjectIdentifier.init))
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// One page of the track swipe: the cover and, beside it, the title centered above the device
/// row.
private struct TrackPage<Title: View, DeviceSpace: View>: View {
    var artworkSide: CGFloat
    var artwork: UIImage?
    var animatesArtwork: Bool
    var deviceRow: DeviceSpace
    var placeholderSymbol: String?
    @ViewBuilder var title: Title

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.Player.artworkGap) {
            ArtworkView(image: artwork, side: artworkSide, animates: animatesArtwork,
                        placeholderSymbol: placeholderSymbol)
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 0)
                title
                Spacer(minLength: 0)
                deviceRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Top row

/// Spotify icon and the origin ("Reproduciendo desde …") at the left, Cola and Biblioteca at
/// the right. Ajustes is reached from the library (owner's request, 2026-11-17), so it is not
/// always on screen.
///
/// Since 2026-11-18 (owner's request) nothing in this row has a pill behind it: the origin
/// and the two buttons are plain text and icons on the background.
struct PlayerTopRow: View {
    var origin: PlaybackOrigin?
    var logoURL: URL?
    var actions: PlayerActions
    var showsLibrary = true

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Player

    var body: some View {
        HStack(spacing: Layout.topRowGap) {
            HStack(spacing: Layout.iconClearSpace) {
                // The logo stays outside the origin button, with its clear space (docs/06).
                SpotifyLogoLink(url: origin?.url ?? logoURL, variant: .icon)
                if let origin {
                    Button {
                        SpotifyLink.open(origin.url)
                    } label: {
                        OriginText(origin: origin)
                            .frame(height: Metrics.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Abre en Spotify"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Cola sits here, not in the controls row: since the 2026-11-17 redesign that row
            // is centered with 36 between buttons, and one more button no longer fits the
            // iPhone 8 Plus (owner's choice). It is not a theme control either: themes saved
            // before it existed list their controls explicitly and would never show it.
            TopRowButton(systemName: "list.bullet", label: "Cola", action: actions.queue)
                .accessibilityHint(Text("Muestra lo que sigue"))

            if showsLibrary {
                TopRowButton(systemName: "books.vertical", label: "Biblioteca",
                             action: actions.library)
            }
        }
        .frame(height: Layout.topRowHeight)
    }
}

/// A button of the top row: icon and label, with no background (Biblioteca, Cola). The tap
/// zone is the row's 44 pt.
private struct TopRowButton: View {
    var systemName: String
    var label: LocalizedStringKey
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Player

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.libraryPillIconGap) {
                Image(systemName: systemName)
                    .font(.system(size: Layout.libraryIconSize - 3, weight: .medium))
                    .frame(width: Layout.libraryIconSize, height: Layout.libraryIconSize)
                    .accessibilityHidden(true)
                Text(label)
                    .textStyle(.libraryPill)
            }
            .foregroundStyle(theme.palette.text.color)
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The official Spotify logo, linking back to Spotify.
///
/// Both images come from Spotify's Design Resources (white RGB versions, 2024 kit), only
/// re-saved with the fill inlined so the asset catalog renders them: never drawn or
/// approximated (docs/06-cumplimiento.md). On dark backgrounds the white version is the
/// one allowed, so the code never tints them.
/// - `.icon` (`SpotifyIcon`): next to the playback origin, in the player and in lyrics mode.
/// - `.full` (`SpotifyLogo`): the library header.
struct SpotifyLogoLink: View {
    enum Variant {
        case full
        case icon
    }

    var url: URL?
    var variant: Variant = .full

    var body: some View {
        Button {
            SpotifyLink.open(url)
        } label: {
            SpotifyLogoImage(variant: variant)
                .frame(height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Abrir en Spotify"))
    }
}

/// The logo image alone, at its size, for places where the button is drawn around it.
struct SpotifyLogoImage: View {
    var variant: SpotifyLogoLink.Variant

    var body: some View {
        switch variant {
        case .full:
            Image("SpotifyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.Player.logoSize.width, height: Metrics.Player.logoSize.height,
                       alignment: .leading)
                .accessibilityHidden(true)
        case .icon:
            Image("SpotifyIcon")
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.Player.iconSize, height: Metrics.Player.iconSize)
                .accessibilityHidden(true)
        }
    }
}

/// "Reproduciendo desde" over the source's name, or over its type while the name is unknown
/// ("Una playlist", "Playlist de Spotify"). Two lines, as in lyrics mode (owner's request,
/// 2026-11-18).
struct OriginText: View {
    var origin: PlaybackOrigin

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: PlaybackOrigin.heading)
                .textStyle(.originHeading)
                .foregroundColor(theme.palette.secondaryText.color)
                .lineLimit(1)
            // Long names scroll instead of staying cut (docs/06, "Metadatos"). Names are
            // shown verbatim: never localized nor parsed as Markdown.
            MarqueeText(verbatim: origin.displayName)
                .textStyle(.originName)
                .foregroundColor(theme.palette.text.color)
        }
    }
}

// MARK: - Title and artist

struct TitleBlock: View {
    var item: NowPlaying

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Player.titleArtistGap) {
            // Two lines; a title that still does not fit scrolls on one line instead.
            WrappingMarqueeText(text: Text(verbatim: item.title), id: item.title,
                                lineLimit: Metrics.Player.titleLineLimit)
                .textStyle(.trackTitle)
                .foregroundStyle(theme.palette.text.color)

            if !item.subtitle.isEmpty || item.isExplicit {
                HStack(spacing: 8) {
                    if item.isExplicit {
                        // Spotify asks to mark explicit content (docs/06). Not in the mockup.
                        Image(systemName: "e.square.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.palette.secondaryText.color)
                            .accessibilityLabel(Text("Explícito"))
                    }
                    MarqueeText(verbatim: item.subtitle)
                        .textStyle(.artist)
                        .foregroundStyle(theme.palette.secondaryText.color)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Device row

/// "Reproduciendo en **Dispositivo**" (opens Dispositivos in milestone 4), plus a small
/// notice when the data on screen may be old.
struct DeviceRow: View {
    var device: SpotifyDevice?
    var freshness: PlayerModel.Freshness
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Player

    var body: some View {
        HStack(spacing: Spacing.m) {
            if let device, !device.name.isEmpty {
                Button(action: action) {
                    HStack(spacing: Layout.deviceIconGap) {
                        DeviceSymbol.image(for: device.type)
                            .font(.system(size: Layout.deviceIconSize - 3, weight: .medium))
                            .frame(width: Layout.deviceIconSize, height: Layout.deviceIconSize)
                            .accessibilityHidden(true)
                        MarqueeText(Text("Reproduciendo en").font(TextStyle.devicePrefix.fixedFont)
                                        + Text(verbatim: " ")
                                        + Text(verbatim: device.name).font(TextStyle.deviceName.fixedFont),
                                    id: device.name)
                    }
                    .foregroundStyle(theme.palette.accent.color)
                    .frame(height: Layout.deviceRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Abre la lista de dispositivos"))
            }
            if let notice = freshnessNotice {
                Text(notice)
                    .textStyle(.freshnessLabel)
                    .foregroundStyle(theme.palette.tertiaryText.color)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .frame(height: Layout.deviceRowHeight)
    }

    private var freshnessNotice: LocalizedStringKey? {
        switch freshness {
        case .live: return nil
        case .stale: return "SIN ACTUALIZAR"
        case .quotaLimited: return "SPOTIFY PIDE ESPERAR"
        }
    }
}

/// SF Symbol for a Spotify Connect device type.
///
/// The mockups draw devices as outlines (`Dispositivos.dc.html`). Recent iOS versions draw
/// some of these symbols (`laptopcomputer`, `tv`, `iphone`, `ipad`…) with a translucent
/// fill inside the screen by default; `.monochrome` keeps them as plain outlines. There are
/// no separate outline-only symbols for a computer or a TV.
enum DeviceSymbol {
    static func image(for type: String) -> Image {
        image(named: name(for: type))
    }

    static func image(named name: String) -> Image {
        Image(systemName: name).symbolRenderingMode(.monochrome)
    }

    static func name(for type: String) -> String {
        switch type.lowercased() {
        case "computer": return "laptopcomputer"
        case "smartphone": return "iphone"
        case "tablet": return "ipad"
        case "speaker", "avr", "stb", "audiodongle", "castaudio": return "hifispeaker"
        case "tv", "castvideo": return "tv"
        case "gameconsole": return "gamecontroller"
        case "automobile": return "car"
        case "smartwatch": return "applewatch"
        default: return "speaker.wave.2"
        }
    }
}

// MARK: - Progress

/// Elapsed time · bar · duration (or time left, from Ajustes › Reproductor). Tapping the time
/// on the right switches between the duration and the time left, like Apple Music; it never
/// moves the playback position.
///
/// Seeking (owner's request, 2026-11-18): where Spotify allows it (`onSeek` set), a finger on
/// the bar moves the playback. The whole 44 pt band around the bar takes the finger; while it
/// moves, the bar grows to 8 pt and the elapsed time follows it, and the seek is sent once,
/// on release. Where Spotify forbids seeking (`actions.disallows.seeking`, a restricted
/// device) `onSeek` is `nil` and the bar stays informative, with no hint that it moves, as
/// Spotify's guidelines ask for restricted actions (docs/06).
struct ProgressRow: View {
    /// The item that plays (`NowPlaying.transitionKey`). A drag that started on another item
    /// sends nothing: the bar now measures a different track.
    var itemKey = ""
    var progressMs: Int
    var durationMs: Int
    var isPlaying: Bool
    var fetchedAt: Date
    var showsRemainingTime = false
    var onToggleTime: (() -> Void)?
    /// Moves the playback to a position in ms. `nil`: informative bar.
    var onSeek: ((Int) -> Void)?

    /// Where the finger is while it drags on the bar; `nil` otherwise.
    @State private var scrubMs: Int?
    /// The item the current drag started on.
    @State private var scrubItemKey: String?
    /// Goes back to `false` by itself also when the system cancels the gesture, when
    /// `onEnded` is not called.
    @GestureState private var isScrubbing = false
    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Player

    var body: some View {
        // Redraws a few times per second only while playing; frozen when paused.
        TimelineView(.animation(minimumInterval: 0.25, paused: !isPlaying)) { context in
            let position = PlaybackProgress.interpolatedMs(
                progressMs: progressMs, durationMs: durationMs, isPlaying: isPlaying,
                fetchedAt: fetchedAt, now: context.date)
            content(positionMs: scrubMs ?? position)
        }
        .frame(height: Layout.progressRowHeight)
        .onChange(of: isScrubbing) { scrubbing in
            // A cancelled drag (an alert, a call) sends nothing.
            if !scrubbing {
                scrubMs = nil
                scrubItemKey = nil
            }
        }
        // The track changed under the finger: drop the preview of the old one.
        .onChange(of: itemKey) { _ in scrubMs = nil }
    }

    private var canSeek: Bool { onSeek != nil && durationMs > 0 }

    private func content(positionMs: Int) -> some View {
        let elapsed = PlaybackProgress.formatted(ms: positionMs)
        let total = PlaybackProgress.formatted(ms: durationMs)
        let trailing = showsRemainingTime
            ? PlaybackProgress.remainingFormatted(positionMs: positionMs, durationMs: durationMs)
            : total
        return HStack(spacing: Layout.progressRowGap) {
            // Both times reserve the width of their longest possible text, so the bar keeps
            // its length when the time on the right is toggled and when a long episode
            // crosses the one-hour mark (`1:00:00` → `59:59`).
            timeSlot(elapsed, widest: total, alignment: .leading)
                // While dragging, the time the release will jump to stands out.
                .foregroundStyle(scrubMs == nil ? theme.palette.tertiaryText.color
                                                : theme.palette.text.color)
            bar(positionMs: positionMs)
            timeSlot(trailing,
                     widest: PlaybackProgress.remainingFormatted(positionMs: 0,
                                                                 durationMs: durationMs),
                     alignment: .trailing)
                // The 12 pt text is a small target: the tappable area grows to about 44 pt
                // without changing the layout.
                .contentShape(Rectangle().inset(by: -Layout.progressTimeTapOutset))
                .onTapGesture { onToggleTime?() }
        }
        .textStyle(.playbackTime)
        .foregroundStyle(theme.palette.tertiaryText.color)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progreso"))
        .accessibilityValue(Text("\(elapsed) de \(total)"))
        .accessibilityActions {
            // Two literals, not a ternary: a ternary would make them plain `String`s, which
            // skip the String Catalog.
            if let onToggleTime {
                if showsRemainingTime {
                    Button("Mostrar duración", action: onToggleTime)
                } else {
                    Button("Mostrar tiempo restante", action: onToggleTime)
                }
            }
        }
        .modifier(SeekAdjustable(positionMs: positionMs, onSeek: canSeek ? onSeek : nil))
    }

    private func bar(positionMs: Int) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.progressTrack)
                Capsule()
                    .fill(theme.palette.text.color)
                    .frame(width: proxy.size.width
                            * PlaybackProgress.fraction(positionMs: positionMs,
                                                        durationMs: durationMs))
            }
            .frame(height: scrubMs == nil ? Layout.progressBarHeight
                                          : Layout.progressBarScrubbingHeight)
            .frame(maxHeight: .infinity)
            .animation(Motion.progressScrub, value: scrubMs == nil)
            .contentShape(VerticalOutsetRectangle(outset: Layout.progressBarTouchOutset))
            .gesture(canSeek ? scrubGesture(width: proxy.size.width) : nil)
        }
        .frame(height: Layout.progressRowHeight)
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($isScrubbing) { _, scrubbing, _ in scrubbing = true }
            .onChanged { drag in
                if scrubItemKey == nil { scrubItemKey = itemKey }
                guard scrubItemKey == itemKey else { return }
                scrubMs = PlaybackProgress.positionMs(atX: drag.location.x, width: width,
                                                      durationMs: durationMs)
            }
            .onEnded { drag in
                defer {
                    scrubMs = nil
                    scrubItemKey = nil
                }
                guard (scrubItemKey ?? itemKey) == itemKey else { return }
                let target = PlaybackProgress.positionMs(atX: drag.location.x, width: width,
                                                         durationMs: durationMs)
                // The command moves the position on screen at once (optimistic), so the bar
                // does not jump back between the release and Spotify's answer.
                onSeek?(target)
            }
    }

    /// A time label as wide as `widest` (hidden). The font is monospaced, so the text with
    /// the most characters is the widest one.
    private func timeSlot(_ text: String, widest: String,
                          alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            Text(verbatim: widest).hidden()
            Text(verbatim: text)
        }
        .frame(minWidth: Layout.progressTimeWidth, alignment: alignment)
    }
}

/// VoiceOver: swiping up or down on the progress moves it 15 s, the same step as the
/// podcast buttons. Only where seeking is allowed.
private struct SeekAdjustable: ViewModifier {
    var positionMs: Int
    var onSeek: ((Int) -> Void)?

    func body(content: Content) -> some View {
        if let onSeek {
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onSeek(positionMs + PlayerControlsModel.seekStepMs)
                case .decrement: onSeek(positionMs - PlayerControlsModel.seekStepMs)
                @unknown default: break
                }
            }
        } else {
            content
        }
    }
}

/// A rectangle taller than its view: lets a thin bar take the finger from the whole row
/// around it without changing the layout.
private struct VerticalOutsetRectangle: Shape {
    var outset: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 0, dy: -outset))
    }
}

// MARK: - Controls

/// One centered row (owner's request, 2026-11-17): the theme's optional controls split in
/// two (`PlayerControlLayout`) around previous · play/pause · next, with the same gap between
/// every button. The two sides take the same flexible width, so play/pause stays in the exact
/// center whatever the number of optional controls.
///
/// - Controls that `actions.disallows` forbids, or all of them on a restricted device, are
///   shown disabled (`ControlAvailability`).
/// - For podcast episodes the center group has −15 s and +15 s instead of previous and next,
///   as Spotify's design guidelines ask ("Podcasts need to have the option to seek 15 seconds
///   forward or backwards").
/// - Agregar a una playlist sits at the left end of the row (owner's request, 2026-11-18).
///   Like Cola, it is not a theme control: saved themes list their controls explicitly and
///   would never show it. On narrow screens every gap shrinks so it fits
///   (`PlayerControlLayout.gap(forWidth:)`).
/// - The volume bar opens sideways out of the speaker (owner's request, 2026-11-18, mockup
///   `VolumenLateral.html`): the row moves left until previous reaches the left edge, the
///   controls that would be pushed out (or covered) fade, and the bar unrolls from the
///   speaker to the end of the row. On closing it rolls back into the speaker
///   (`PlayerControlLayout.volumeExpansion`).
struct PlayerControls: View {
    var playback: PlaybackState?
    var actions: PlayerActions
    /// Optional controls in the theme's order (`reproductor.controles`).
    var controls: [Theme.PlayerControl]
    var lyricsActive = false
    /// A track or episode that a playlist can take (not ads nor local files).
    var canAddToPlaylist = false
    /// Observed here because the bar opens inside this row.
    @ObservedObject var volume: VolumeController

    private typealias Layout = Metrics.Player

    var body: some View {
        GeometryReader { proxy in
            let layout = PlayerControlLayout(controls: controls)
            let gap = layout.gap(forWidth: proxy.size.width)
            let expansion = layout.volumeExpansion(forWidth: proxy.size.width, gap: gap)
            ZStack(alignment: .topLeading) {
                row(layout: layout, gap: gap, expansion: expansion)
                volumeBar(expansion)
            }
            .offset(x: isVolumeOpen ? -expansion.shift : 0)
            .animation(isVolumeOpen ? VolumePanelMotion.entry : VolumePanelMotion.exit,
                       value: isVolumeOpen)
        }
        .frame(height: Layout.controlsHeight)
    }

    private var isVolumeOpen: Bool { volume.isPanelVisible }

    /// The bar, at the speaker's right edge. Its content keeps its full width and a frame
    /// that grows from zero reveals it, so it unrolls out of the speaker instead of
    /// squeezing.
    private func volumeBar(_ expansion: VolumeExpansion) -> some View {
        HStack(spacing: 0) {
            if expansion.usesRowSpeaker {
                Color.clear
                    .frame(width: Layout.sideButtonSize)
            } else {
                // The theme's volume button is on the left (it fades out with that group)
                // or not in the theme at all: a speaker comes in with the bar.
                volumeButton
                    .fadedOut(!isVolumeOpen)
            }
            VolumePanelView(volume: volume)
                .frame(width: expansion.barAreaWidth, alignment: .leading)
                .opacity(isVolumeOpen ? 1 : 0)
                .animation(isVolumeOpen ? VolumePanelMotion.fadeIn : VolumePanelMotion.fadeOut,
                           value: isVolumeOpen)
                .frame(width: isVolumeOpen ? expansion.barAreaWidth : 0, alignment: .leading)
                .clipped()
        }
        .frame(height: Layout.controlsHeight)
        .offset(x: expansion.speakerX)
    }

    private var volumeButton: some View {
        // Always enabled: on a device without volume control the bar explains why.
        ToggleIconButton(systemName: "speaker.wave.2", isOn: isVolumeOpen, label: "Volumen",
                         action: actions.volume)
    }

    private func row(layout: PlayerControlLayout, gap: CGFloat,
                     expansion: VolumeExpansion) -> some View {
        let availability = ControlAvailability(playback: playback)
        return HStack(spacing: gap) {
            HStack(spacing: 0) {
                ToggleIconButton(systemName: "plus.circle", isOn: false,
                                 label: "Agregar a una playlist", isEnabled: canAddToPlaylist,
                                 action: actions.addToPlaylist)
                    .accessibilityHint(Text("Elegí una de tus playlists"))
                Spacer(minLength: layout.leading.isEmpty ? 0 : gap)
                HStack(spacing: gap) {
                    ForEach(layout.leading, id: \.self) { control in
                        optionalButton(control, availability: availability)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .fadedOut(isVolumeOpen)

            if isEpisode {
                SkipButton(systemName: "gobackward.15", label: "Retroceder 15 segundos",
                           iconSize: Metrics.SeekButton.iconSize,
                           isEnabled: availability.seek, action: actions.skipBackward)
            } else {
                SkipButton(systemName: "backward.end.fill", label: "Anterior",
                           isEnabled: availability.previous, action: actions.previous)
            }
            PlayPauseButton(isPlaying: playback?.isPlaying == true,
                            isEnabled: availability.playPause, action: actions.playPause)
            if isEpisode {
                SkipButton(systemName: "goforward.15", label: "Adelantar 15 segundos",
                           iconSize: Metrics.SeekButton.iconSize,
                           isEnabled: availability.seek, action: actions.skipForward)
            } else {
                SkipButton(systemName: "forward.end.fill", label: "Siguiente",
                           isEnabled: availability.next, action: actions.next)
            }

            HStack(spacing: gap) {
                ForEach(Array(layout.trailing.enumerated()), id: \.element) { index, control in
                    // Controls after the speaker would sit under the bar.
                    optionalButton(control, availability: availability)
                        .fadedOut(isVolumeOpen && index > expansion.keptTrailingCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Layout.controlsHeight)
    }

    private var isEpisode: Bool {
        if case .episode = playback?.item { return true }
        return false
    }

    @ViewBuilder
    private func optionalButton(_ control: Theme.PlayerControl,
                                availability: ControlAvailability) -> some View {
        switch control {
        case .shuffle:
            ToggleIconButton(systemName: "shuffle", isOn: playback?.shuffleState == true,
                             label: "Aleatorio", isEnabled: availability.shuffle,
                             action: actions.shuffle)
        case .repeatMode:
            ToggleIconButton(systemName: playback?.repeatState == .track ? "repeat.1" : "repeat",
                             isOn: (playback?.repeatState ?? .off) != .off,
                             label: repeatLabel, isEnabled: availability.repeatMode,
                             action: actions.repeatMode)
        case .lyrics:
            ToggleIconButton(systemName: "quote.bubble", isOn: lyricsActive,
                             label: "Letras", action: actions.lyrics)
        case .volume:
            volumeButton
        }
    }

    private var repeatLabel: LocalizedStringKey {
        switch playback?.repeatState ?? .off {
        case .off: return "Repetir: desactivado"
        case .context: return "Repetir: todo"
        case .track: return "Repetir: este tema"
        }
    }
}

private extension View {
    /// Fades a control out while the volume bar takes its place, and back in when it closes.
    /// Hidden, it takes no touches and VoiceOver skips it.
    func fadedOut(_ hidden: Bool) -> some View {
        opacity(hidden ? 0 : 1)
            .animation(hidden ? VolumePanelMotion.fadeOut : VolumePanelMotion.fadeIn, value: hidden)
            .allowsHitTesting(!hidden)
            .accessibilityHidden(hidden)
    }
}

/// Round icon button. Active: accent on accent at 16 % (like Letras in the mockup).
struct ToggleIconButton: View {
    var systemName: String
    var isOn: Bool
    var label: LocalizedStringKey
    var isEnabled = true
    var size: CGFloat = Metrics.Player.sideButtonSize
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Metrics.Player.sideIconSize - 2, weight: .semibold))
                .foregroundStyle(isOn ? theme.palette.accent.color : theme.palette.tertiaryText.color)
                .frame(width: size, height: size)
                .background(Circle().fill(isOn
                    ? theme.palette.accent.color.opacity(Palette.activeToggleOpacity)
                    : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Palette.disabledControlOpacity)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct SkipButton: View {
    var systemName: String
    var label: LocalizedStringKey
    var iconSize: CGFloat = Metrics.Player.skipIconSize
    var isEnabled = true
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: iconSize, weight: .regular))
                .foregroundStyle(theme.palette.text.color)
                .frame(width: Metrics.Player.skipButtonSize, height: Metrics.Player.skipButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Palette.disabledControlOpacity)
        .accessibilityLabel(Text(label))
    }
}

struct PlayPauseButton: View {
    var isPlaying: Bool
    var isEnabled = true
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: Metrics.Player.playIconSize, weight: .bold))
                .foregroundStyle(Palette.playButtonIcon)
                .frame(width: Metrics.Player.playButtonSize, height: Metrics.Player.playButtonSize)
                .background(Circle().fill(theme.palette.text.color))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Palette.disabledControlOpacity)
        .accessibilityLabel(isPlaying ? Text("Pausar") : Text("Reproducir"))
    }
}
