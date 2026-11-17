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
                artwork: model.artwork.map(Image.init(uiImage:)),
                onOpenSource: { [origin = model.origin] in
                    if let url = origin?.url { SpotifyLink.open(url) }
                },
                onOpenSpotify: { [url = model.origin?.url ?? item.itemURL] in
                    if let url { SpotifyLink.open(url) }
                },
                onShowDevices: actions.devices
            )
            .frame(height: Layout.upperAreaHeight)
            .transition(.opacity)
        } else {
            normalTopBlock
                .transition(.opacity)
        }
    }

    /// The origin row across the whole width, so "Desde la playlist …" always sits in the
    /// top-left corner, and below it the artwork with the title, artist and device.
    private var normalTopBlock: some View {
        VStack(spacing: Layout.topRowBottomGap) {
            PlayerTopRow(origin: model.origin, logoURL: model.nowPlaying?.itemURL,
                         actions: actions)
            HStack(alignment: .top, spacing: Layout.artworkGap) {
                ArtworkView(image: model.artwork, side: artworkSide)
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    ZStack(alignment: .leading) {
                        if let item = model.nowPlaying {
                            // A new track: the old title rises away and the new one comes in.
                            TitleBlock(item: item)
                                .id(item.transitionKey)
                                .transition(Motion.rise(Motion.trackRise, reduceMotion: reduceMotion))
                        }
                    }
                    .animation(Motion.trackChange, value: model.nowPlaying?.transitionKey)
                    Spacer(minLength: 0)
                    DeviceRow(device: model.playback?.device, freshness: model.freshness,
                              action: actions.devices)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: Layout.topBlockHeight, alignment: .top)
        }
        .frame(height: Layout.upperAreaHeight, alignment: .top)
    }

    // MARK: Bottom block

    /// The theme's optional controls in its order. `showsLyricsButton` comes from the same
    /// theme list; it is applied again here so callers can still turn the button off.
    private var optionalControls: [Theme.PlayerControl] {
        theme.playerControls.filter { $0 != .lyrics || showsLyricsButton }
    }

    private var bottomBlock: some View {
        VStack(spacing: Layout.bottomBlockGap) {
            if let item = model.nowPlaying, let playback = model.playback {
                ProgressRow(progressMs: playback.progressMs ?? 0, durationMs: item.durationMs,
                            isPlaying: playback.isPlaying, fetchedAt: model.fetchedAt)
            }
            PlayerControls(playback: model.playback, actions: actions,
                           controls: optionalControls,
                           lyricsActive: lyrics.isButtonActive)
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
                }
            }
            .id(image.map(ObjectIdentifier.init))
            .transition(.opacity)
        }
        .animation(Motion.artworkCrossfade, value: image.map(ObjectIdentifier.init))
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Top row

/// Spotify icon and "Desde la playlist …" at the left, Biblioteca at the right. Ajustes is
/// reached from the library (owner's request, 2026-11-17), so it is not always on screen.
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

            if showsLibrary {
                Button(action: actions.library) {
                    HStack(spacing: Layout.libraryPillIconGap) {
                        Image(systemName: "books.vertical")
                            .font(.system(size: Layout.libraryIconSize - 3, weight: .medium))
                            .frame(width: Layout.libraryIconSize, height: Layout.libraryIconSize)
                            .accessibilityHidden(true)
                        Text("Biblioteca")
                            .textStyle(.libraryPill)
                    }
                    .foregroundStyle(theme.palette.text.color)
                    .padding(.leading, Layout.libraryPillLeadingPadding)
                    .padding(.trailing, Layout.libraryPillTrailingPadding)
                    .frame(height: Metrics.minTouchTarget)
                    .background(Capsule().fill(Palette.subtleSurface))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: Layout.topRowHeight)
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

/// "Desde la playlist **Nombre**", or only the type while the name is unknown.
struct OriginText: View {
    var origin: PlaybackOrigin

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        // Long names scroll instead of staying cut (docs/06, "Metadatos").
        MarqueeText(text, id: "\(origin.kind)|\(origin.name ?? "")")
    }

    private var text: Text {
        let prefix = Text(prefixKey)
            .font(TextStyle.originPrefix.fixedFont)
            .foregroundColor(theme.palette.secondaryText.color)
        guard let name = origin.name, !name.isEmpty else { return prefix }
        // Names are shown verbatim: never localized nor parsed as Markdown.
        return prefix
            + Text(verbatim: " ")
            + Text(verbatim: name)
                .font(TextStyle.originName.fixedFont)
                .foregroundColor(theme.palette.text.color)
    }

    private var prefixKey: LocalizedStringKey {
        let named = !(origin.name ?? "").isEmpty
        switch origin.kind {
        case .playlist: return named ? "Desde la playlist" : "Desde una playlist"
        case .album: return named ? "Desde el álbum" : "Desde un álbum"
        case .artist: return named ? "Desde el artista" : "Desde un artista"
        case .show: return named ? "Desde el podcast" : "Desde un podcast"
        case .likedSongs: return "Desde Tus me gusta"
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

/// Elapsed time · bar · duration. Informative only: no knob, no dragging (docs/06).
struct ProgressRow: View {
    var progressMs: Int
    var durationMs: Int
    var isPlaying: Bool
    var fetchedAt: Date

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Player

    var body: some View {
        // Redraws a few times per second only while playing; frozen when paused.
        TimelineView(.animation(minimumInterval: 0.25, paused: !isPlaying)) { context in
            let position = PlaybackProgress.interpolatedMs(
                progressMs: progressMs, durationMs: durationMs, isPlaying: isPlaying,
                fetchedAt: fetchedAt, now: context.date)
            content(positionMs: position)
        }
        .frame(height: Layout.progressRowHeight)
    }

    private func content(positionMs: Int) -> some View {
        let elapsed = PlaybackProgress.formatted(ms: positionMs)
        let total = PlaybackProgress.formatted(ms: durationMs)
        return HStack(spacing: Layout.progressRowGap) {
            Text(verbatim: elapsed)
                .frame(minWidth: Layout.progressTimeWidth, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.progressTrack)
                    Capsule()
                        .fill(theme.palette.text.color)
                        .frame(width: proxy.size.width
                                * PlaybackProgress.fraction(positionMs: positionMs,
                                                            durationMs: durationMs))
                }
            }
            .frame(height: Layout.progressBarHeight)
            Text(verbatim: total)
                .frame(minWidth: Layout.progressTimeWidth, alignment: .trailing)
        }
        .textStyle(.playbackTime)
        .foregroundStyle(theme.palette.tertiaryText.color)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Progreso"))
        .accessibilityValue(Text("\(elapsed) de \(total)"))
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
struct PlayerControls: View {
    var playback: PlaybackState?
    var actions: PlayerActions
    /// Optional controls in the theme's order (`reproductor.controles`).
    var controls: [Theme.PlayerControl]
    var lyricsActive = false

    private typealias Layout = Metrics.Player

    var body: some View {
        let layout = PlayerControlLayout(controls: controls)
        let availability = ControlAvailability(playback: playback)
        HStack(spacing: Layout.controlsGap) {
            HStack(spacing: Layout.controlsGap) {
                ForEach(layout.leading, id: \.self) { control in
                    optionalButton(control, availability: availability)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)

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

            HStack(spacing: Layout.controlsGap) {
                ForEach(layout.trailing, id: \.self) { control in
                    optionalButton(control, availability: availability)
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
            // Always enabled: on a device without volume control the panel explains why.
            ToggleIconButton(systemName: "speaker.wave.2", isOn: false, label: "Volumen",
                             action: actions.volume)
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

/// 48 pt round icon button. Active: accent on accent at 16 % (like Letras in the mockup).
struct ToggleIconButton: View {
    var systemName: String
    var isOn: Bool
    var label: LocalizedStringKey
    var isEnabled = true
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Metrics.Player.sideIconSize - 2, weight: .semibold))
                .foregroundStyle(isOn ? theme.palette.accent.color : theme.palette.tertiaryText.color)
                .frame(width: Metrics.Player.sideButtonSize, height: Metrics.Player.sideButtonSize)
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
