import SwiftUI

/// The player (`Main.dc.html`): artwork and text on top, progress and controls below.
struct PlayerView: View {
    @ObservedObject var model: PlayerModel
    @ObservedObject var lyrics: LyricsModeController
    var actions: PlayerActions
    var showsLyricsButton: Bool
    /// Full screen width, to adapt to the iPhone 8 Plus (736 pt).
    var screenWidth: CGFloat

    private typealias Layout = Metrics.Player

    var body: some View {
        VStack(spacing: Spacing.Player.blockGap) {
            topBlock
            Spacer(minLength: 0)
            bottomBlock
        }
    }

    // MARK: Top block

    private var artworkSide: CGFloat {
        min(Layout.artworkSize, (screenWidth * Layout.artworkWidthFraction).rounded(.down))
    }

    @EnvironmentObject private var theme: ThemeStore

    /// The normal top block, or lyrics mode in its place (docs/02, "Modo letras").
    @ViewBuilder
    private var topBlock: some View {
        if lyrics.showsLyricsMode, let item = model.nowPlaying, let playback = model.playback {
            LyricsModeView(
                content: LyricsModeContent(item: item, origin: model.origin,
                                           deviceName: playback.device?.name),
                lyrics: lyrics.lyrics,
                playback: playback.lyricsPlayback(fetchedAt: model.fetchedAt),
                width: theme.lyricsWidth,
                artwork: model.artwork.map(Image.init(uiImage:)),
                onOpenSource: { [origin = model.origin] in
                    if let url = origin?.url { SpotifyLink.open(url) }
                },
                onOpenSpotify: { [url = model.origin?.url ?? item.itemURL] in
                    if let url { SpotifyLink.open(url) }
                },
                onShowDevices: actions.devices
            )
            .frame(height: Layout.topBlockHeight)
        } else {
            normalTopBlock
        }
    }

    private var normalTopBlock: some View {
        HStack(alignment: .top, spacing: Layout.artworkGap) {
            ArtworkView(image: model.artwork, side: artworkSide)
            VStack(alignment: .leading, spacing: 0) {
                PlayerTopRow(origin: model.origin, logoURL: model.nowPlaying?.itemURL,
                             actions: actions)
                Spacer(minLength: 0)
                if let item = model.nowPlaying {
                    TitleBlock(item: item)
                }
                Spacer(minLength: 0)
                DeviceRow(device: model.playback?.device, freshness: model.freshness,
                          action: actions.devices)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: Layout.topBlockHeight, alignment: .top)
    }

    // MARK: Bottom block

    private var bottomBlock: some View {
        VStack(spacing: Layout.bottomBlockGap) {
            if let item = model.nowPlaying, let playback = model.playback {
                ProgressRow(progressMs: playback.progressMs ?? 0, durationMs: item.durationMs,
                            isPlaying: playback.isPlaying, fetchedAt: model.fetchedAt)
            }
            PlayerControls(playback: model.playback, actions: actions,
                           showsLyricsButton: showsLyricsButton,
                           lyricsActive: lyrics.isButtonActive,
                           sideGroupWidth: screenWidth < Layout.narrowScreenWidth
                               ? Layout.narrowSideGroupWidth : Layout.sideGroupWidth)
        }
    }
}

// MARK: - Artwork

/// The cover as Spotify sends it: fitted (never cropped), with the 4 pt radius of the
/// guidelines, and nothing on top of it (docs/06-cumplimiento.md).
struct ArtworkView: View {
    var image: UIImage?
    var side: CGFloat

    var body: some View {
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
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
        .accessibilityHidden(true)
    }
}

// MARK: - Top row

/// Spotify logo, "Desde la playlist …", Biblioteca and Ajustes.
struct PlayerTopRow: View {
    var origin: PlaybackOrigin?
    var logoURL: URL?
    var actions: PlayerActions
    var showsLibraryAndSettings = true

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Player

    var body: some View {
        HStack(spacing: Layout.topRowGap) {
            HStack(spacing: Layout.logoClearSpace) {
                SpotifyLogoLink(url: origin?.url ?? logoURL)
                if let origin {
                    Button {
                        SpotifyLink.open(origin.url)
                    } label: {
                        OriginText(origin: origin)
                            .frame(height: Metrics.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsLibraryAndSettings {
                HStack(spacing: Layout.topButtonsGap) {
                    Button(action: actions.library) {
                        HStack(spacing: Layout.libraryPillIconGap) {
                            Image(systemName: "books.vertical")
                                .font(.system(size: Layout.libraryIconSize - 3, weight: .medium))
                                .frame(width: Layout.libraryIconSize, height: Layout.libraryIconSize)
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

                    Button(action: actions.settings) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: Layout.settingsIconSize - 3, weight: .medium))
                            .foregroundStyle(theme.palette.tertiaryText.color)
                            .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Ajustes"))
                }
            }
        }
        .frame(height: Layout.topRowHeight)
    }
}

/// The official Spotify logo, linking back to Spotify.
///
/// The image set `SpotifyLogo` ships **empty** on purpose: the owner adds the official white
/// logo from Spotify's Design Resources. It must never be drawn or approximated
/// (docs/06-cumplimiento.md). Until then the 108×30 slot is empty but still tappable.
struct SpotifyLogoLink: View {
    var url: URL?

    var body: some View {
        Button {
            SpotifyLink.open(url)
        } label: {
            Image("SpotifyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.Player.logoSize.width, height: Metrics.Player.logoSize.height,
                       alignment: .leading)
                .frame(height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Abrir en Spotify"))
    }
}

/// "Desde la playlist **Nombre**", or only the type while the name is unknown.
struct OriginText: View {
    var origin: PlaybackOrigin

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        text
            .lineLimit(1)
            .truncationMode(.tail)
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
            Text(verbatim: item.title)
                .textStyle(.trackTitle)
                .foregroundStyle(theme.palette.text.color)
                .lineLimit(Metrics.Player.titleLineLimit)
                .fixedSize(horizontal: false, vertical: true)

            if !item.subtitle.isEmpty || item.isExplicit {
                HStack(spacing: 8) {
                    if item.isExplicit {
                        // Spotify asks to mark explicit content (docs/06). Not in the mockup.
                        Image(systemName: "e.square.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.palette.secondaryText.color)
                            .accessibilityLabel(Text("Explícito"))
                    }
                    Text(verbatim: item.subtitle)
                        .textStyle(.artist)
                        .foregroundStyle(theme.palette.secondaryText.color)
                        .lineLimit(1)
                        .truncationMode(.tail)
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
                        Image(systemName: DeviceSymbol.name(for: device.type))
                            .font(.system(size: Layout.deviceIconSize - 3, weight: .medium))
                            .frame(width: Layout.deviceIconSize, height: Layout.deviceIconSize)
                        (Text("Reproduciendo en").font(TextStyle.devicePrefix.fixedFont)
                            + Text(verbatim: " ")
                            + Text(verbatim: device.name).font(TextStyle.deviceName.fixedFont))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .foregroundStyle(theme.palette.accent.color)
                    .frame(height: Layout.deviceRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
enum DeviceSymbol {
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

/// The three control groups. In milestone 2 the buttons show the current state but do
/// nothing; milestone 3 wires them and applies `actions.disallows`.
struct PlayerControls: View {
    var playback: PlaybackState?
    var actions: PlayerActions
    var showsLyricsButton: Bool
    var lyricsActive = false
    var sideGroupWidth: CGFloat

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Player

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: Layout.sideButtonGap) {
                ToggleIconButton(systemName: "shuffle", isOn: playback?.shuffleState == true,
                                 label: "Aleatorio", action: actions.shuffle)
                ToggleIconButton(systemName: playback?.repeatState == .track ? "repeat.1" : "repeat",
                                 isOn: (playback?.repeatState ?? .off) != .off,
                                 label: "Repetir", action: actions.repeatMode)
            }
            .frame(width: sideGroupWidth, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: Layout.centerGap) {
                SkipButton(systemName: "backward.end.fill", label: "Anterior",
                           action: actions.previous)
                PlayPauseButton(isPlaying: playback?.isPlaying == true, action: actions.playPause)
                SkipButton(systemName: "forward.end.fill", label: "Siguiente", action: actions.next)
            }

            Spacer(minLength: 0)

            HStack(spacing: Layout.sideButtonGap) {
                if showsLyricsButton {
                    ToggleIconButton(systemName: "quote.bubble", isOn: lyricsActive,
                                     label: "Letras", action: actions.lyrics)
                }
                ToggleIconButton(systemName: "speaker.wave.2", isOn: false, label: "Volumen",
                                 action: actions.volume)
            }
            .frame(width: sideGroupWidth, alignment: .trailing)
        }
        .frame(height: Layout.controlsHeight)
    }
}

/// 48 pt round icon button. Active: accent on accent at 16 % (like Letras in the mockup).
struct ToggleIconButton: View {
    var systemName: String
    var isOn: Bool
    var label: LocalizedStringKey
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
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct SkipButton: View {
    var systemName: String
    var label: LocalizedStringKey
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: Metrics.Player.skipIconSize, weight: .regular))
                .foregroundStyle(theme.palette.text.color)
                .frame(width: Metrics.Player.skipButtonSize, height: Metrics.Player.skipButtonSize)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

struct PlayPauseButton: View {
    var isPlaying: Bool
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
        .accessibilityLabel(isPlaying ? Text("Pausar") : Text("Reproducir"))
    }
}
