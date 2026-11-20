import SwiftUI

// Detail of a playlist or an album (`Detalle.dc.html`), shown inside the library in place of
// the filters and the row of cards. The library keeps its margins and its mini player; the
// first row changes to "‹ Biblioteca", shuffle, "ABRIR EN SPOTIFY ↗" and the logo.
//
// Tapping a playable song starts it within the collection. A long press shows its full
// name and "Abrir en Spotify".

// MARK: - Header

/// Row 1 of the detail screen.
struct CollectionDetailHeader: View {
    /// The playlist's or album's page: both the link and the logo open it in Spotify.
    var pageURL: URL?
    var shuffleIsOn: Bool
    var canToggleShuffle: Bool
    var onToggleShuffle: () -> Void
    var onBack: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        HStack(spacing: Layout.rowGap) {
            Button(action: onBack) {
                HStack(spacing: Layout.backIconGap) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: Layout.backIconSize - 2, weight: .bold))
                        .accessibilityHidden(true)
                    Text("Biblioteca")
                        .textStyle(.libraryTab)
                        .lineLimit(1)
                }
                .foregroundStyle(theme.palette.text.color)
                .padding(.leading, Layout.backLeadingPadding)
                .padding(.trailing, Layout.backTrailingPadding)
                .frame(height: Layout.backHeight)
                .background(Capsule().fill(Palette.libraryTabTrack))
                // The 36 pt pill sits in a 44 pt tap area.
                .frame(height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Lined up with the artwork below, like the tabs with the filters.
            .padding(.leading, Layout.tabTrackOffset)
            .accessibilityLabel(Text("Volver a la biblioteca"))

            ToggleIconButton(systemName: "shuffle", isOn: shuffleIsOn, label: "Aleatorio",
                             isEnabled: canToggleShuffle, size: Metrics.minTouchTarget,
                             action: onToggleShuffle)

            Spacer(minLength: 0)

            HStack(spacing: Layout.detailHeaderGap) {
                OpenSpotifyLink(title: "ABRIR EN SPOTIFY", url: pageURL)
                SpotifyLogoLink(url: pageURL)
            }
        }
        .frame(height: Layout.rowHeight)
    }
}

// MARK: - Body

/// Artwork, name and "Reproducir" on the left; the track list on the right.
struct CollectionDetailView: View {
    @ObservedObject var model: CollectionDetailModel
    var canStartPlayback: Bool
    var onPlay: () -> Void
    var onPlayTrack: (CollectionTrack) -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        HStack(alignment: .top, spacing: Layout.detailColumnGap) {
            info
            tracks
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.detailHeight, alignment: .top)
        .task(id: model.entry.uri) { await model.loadIfNeeded() }
    }

    // MARK: Left column

    private var info: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Same artwork as the cards: fitted, 4 pt radius, nothing over it.
            CardArtwork(url: model.entry.artworkURL, side: Layout.cardSize)

            // Names longer than the column scroll (docs/06: cut names must be readable).
            MarqueeText(verbatim: model.entry.name)
                .textStyle(.detailName)
                .foregroundStyle(theme.palette.text.color)
                .padding(.top, Layout.detailNameTopGap)
            MarqueeText(verbatim: model.entry.detailSubtitle ?? model.entry.subtitle)
                .textStyle(.cardSubtitle)
                .foregroundStyle(theme.palette.bodyText.color)

            Spacer(minLength: Spacing.xs)

            playButton
        }
        .frame(width: Layout.detailInfoWidth, alignment: .leading)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: Layout.detailPlayIconGap) {
                Image(systemName: "play.fill")
                    .font(.system(size: Layout.detailPlayIconSize - 2, weight: .bold))
                    .accessibilityHidden(true)
                Text("Reproducir")
                    .textStyle(.detailPlay)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.palette.textOnAccent.color)
            .frame(width: Layout.detailPlayWidth, height: Layout.detailPlayHeight)
            .background(Capsule().fill(theme.palette.accent.color))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canStartPlayback)
        .opacity(canStartPlayback ? 1 : 0.6)
        .accessibilityHint(Text("Reproduce en el dispositivo activo"))
    }

    // MARK: Right column

    @ViewBuilder
    private var tracks: some View {
        switch model.state {
        case .loading:
            placeholders
        case .loaded where model.tracks.isEmpty:
            RowMessage(text: "Todavía no tiene temas.")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded:
            trackList
        case .restricted:
            RestrictedTracksView(pageURL: model.entry.pageURL)
        case .failed(let failure):
            RowMessage(text: message(for: failure),
                       onRetry: { Task { await model.load() } })
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            listLabel(model.listLabel)
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(model.tracks) { track in
                        TrackRow(track: track, canStartPlayback: canStartPlayback) {
                            onPlayTrack(track)
                        }
                            .onAppear {
                                if track.id == model.tracks.last?.id {
                                    Task { await model.loadMore() }
                                }
                            }
                    }
                    footer
                }
                // The last row can scroll out from under the fade.
                .padding(.bottom, Layout.trackListFadeHeight)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [theme.palette.background.color.opacity(0),
                                        theme.palette.background.color],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.trackListFadeHeight)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView()
                .tint(theme.palette.text.color)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.trackRowHeight)
        } else if model.loadMoreFailed {
            Button("Reintentar") { Task { await model.loadMore() } }
                .buttonStyle(.plain)
                .textStyle(.libraryFilter)
                .foregroundStyle(theme.palette.text.color)
                .frame(maxWidth: .infinity)
                .frame(height: Layout.trackRowHeight)
                .contentShape(Rectangle())
        }
    }

    private func listLabel(_ text: String) -> some View {
        Text(verbatim: text)
            .textStyle(.trackListLabel)
            .foregroundStyle(theme.palette.label.color)
            .lineLimit(1)
            .frame(height: Layout.trackListLabelHeight, alignment: .top)
    }

    private var placeholders: some View {
        VStack(alignment: .leading, spacing: 0) {
            listLabel(" ")
            ForEach(0..<Layout.trackPlaceholderCount, id: \.self) { index in
                HStack(spacing: Layout.trackRowGap) {
                    Color.clear.frame(width: Layout.trackNumberWidth)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        RoundedRectangle(cornerRadius: Radius.artwork)
                            .fill(Palette.subtleSurface)
                            .frame(width: index.isMultiple(of: 2) ? 180 : 140, height: 12)
                        RoundedRectangle(cornerRadius: Radius.artwork)
                            .fill(Palette.subtleSurface)
                            .frame(width: 100, height: 10)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: Layout.trackRowHeight)
                .overlay(alignment: .top) { TrackSeparator() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cargando"))
    }

    private func message(for failure: LibraryModel.LoadFailure) -> LocalizedStringKey {
        switch failure {
        case .forbidden:
            return "Spotify no deja ver estos temas con esta cuenta."
        case .rateLimited:
            return "Spotify pidió esperar un momento. Probá de nuevo en un rato."
        case .failed:
            return "No pudimos cargar los temas. Revisá la conexión y probá de nuevo."
        }
    }
}

// MARK: - Track row

/// A 50 pt row: number, title (with the explicit mark), artists and duration.
struct TrackRow: View {
    var track: CollectionTrack
    var canStartPlayback: Bool
    var onPlay: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        Group {
            if track.playbackPosition != nil {
                Button(action: onPlay) { row }
                    .buttonStyle(.plain)
                    .disabled(!canStartPlayback)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(Text("Reproduce en el dispositivo activo"))
            } else {
                row
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
            }
        }
        .modifier(TrackMenu(track: track))
    }

    private var row: some View {
        HStack(spacing: Layout.trackRowGap) {
            Text(verbatim: "\(track.number)")
                .textStyle(.trackRowNumber)
                .foregroundStyle(theme.palette.tertiaryText.color)
                .lineLimit(1)
                .frame(width: Layout.trackNumberWidth, alignment: .trailing)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Layout.trackTitleGap) {
                    Text(verbatim: track.title)
                        .textStyle(.trackRowTitle)
                        .foregroundStyle(theme.palette.text.color)
                    if track.isExplicit {
                        // Spotify asks to mark explicit content (docs/06).
                        Image(systemName: "e.square.fill")
                            .font(.system(size: Layout.trackExplicitSize))
                            .foregroundStyle(theme.palette.bodyText.color)
                    }
                }
                if !track.subtitle.isEmpty {
                    Text(verbatim: track.subtitle)
                        .textStyle(.cardSubtitle)
                        .foregroundStyle(theme.palette.bodyText.color)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let duration = track.durationMs {
                Text(verbatim: PlaybackProgress.formatted(ms: duration))
                    .textStyle(.trackRowNumber)
                    .foregroundStyle(theme.palette.tertiaryText.color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: Layout.trackRowHeight)
        .overlay(alignment: .top) { TrackSeparator() }
        .opacity(track.isAvailable ? 1 : Layout.trackUnavailableOpacity)
        .contentShape(Rectangle())
    }

    private var accessibilityLabel: Text {
        var label = Text(verbatim: "\(track.number). \(track.title)")
        if track.isExplicit {
            label = label + Text(verbatim: ", ") + Text("Explícito")
        }
        if !track.subtitle.isEmpty {
            label = label + Text(verbatim: ", \(track.subtitle)")
        }
        if let duration = track.durationMs {
            label = label + Text(verbatim: ", \(PlaybackProgress.formatted(ms: duration))")
        }
        if !track.isAvailable {
            label = label + Text(verbatim: ", ") + Text("No disponible")
        }
        return label
    }
}

/// Long press on a track to read the full title and artists. Tracks with a Spotify page
/// also offer a link to open it. The Cola sheet uses it for its rows too.
struct TrackMenu: ViewModifier {
    var track: CollectionTrack

    @EnvironmentObject private var theme: ThemeStore
    @State private var isShowingPreview = false

    func body(content: Content) -> some View {
        if let url = track.pageURL {
            content
                .accessibilityAction(named: Text("Abrir en Spotify")) { SpotifyLink.open(url) }
                .contextMenu {
                    Button {
                        SpotifyLink.open(url)
                    } label: {
                        Label("Abrir en Spotify", systemImage: "arrow.up.right")
                    }
                } preview: {
                    preview
                }
        } else {
            content
                .onLongPressGesture { isShowingPreview = true }
                .popover(isPresented: $isShowingPreview) { preview }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(verbatim: track.title)
                .textStyle(.trackRowTitle)
                .foregroundStyle(theme.palette.text.color)
            if !track.subtitle.isEmpty {
                Text(verbatim: track.subtitle)
                    .textStyle(.cardSubtitle)
                    .foregroundStyle(theme.palette.bodyText.color)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 300, alignment: .leading)
        .padding(Spacing.m)
        .background(theme.palette.surface.color)
        .environmentObject(theme)
    }
}

private struct TrackSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.trackSeparator)
            .frame(height: Metrics.Library.trackSeparatorWidth)
    }
}

// MARK: - Playlists of other people

/// Spotify lists the tracks only of playlists the user owns or collaborates on (`403`
/// otherwise). The screen says so, and the playlist can still be played or opened.
struct RestrictedTracksView: View {
    var pageURL: URL?

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.restrictedGap) {
            Image(systemName: "lock")
                .font(.system(size: Layout.restrictedIconSize - 4, weight: .regular))
                .foregroundStyle(theme.palette.label.color)
                .frame(width: Layout.restrictedIconSize, height: Layout.restrictedIconSize)
                .accessibilityHidden(true)
            Text("Spotify no muestra los temas de esta playlist")
                .textStyle(.restrictedTitle)
                .foregroundStyle(theme.palette.text.color)
                .fixedSize(horizontal: false, vertical: true)
            Text("Solo deja ver los temas de las playlists que creaste o en las que colaborás. Podés reproducirla igual, o verla en Spotify.")
                .textStyle(.searchHelp)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                SpotifyLink.open(pageURL)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("Ver en Spotify")
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: Layout.openSpotifyIconSize - 2, weight: .bold))
                        .accessibilityHidden(true)
                }
                .textStyle(.libraryFilter)
                .foregroundStyle(theme.palette.text.color)
                .padding(.horizontal, Layout.outlineButtonPadding)
                .frame(height: Layout.outlineButtonHeight)
                .overlay(Capsule().strokeBorder(Palette.chipBorder,
                                                lineWidth: Layout.filterBorderWidth))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isLink)
            .padding(.top, Spacing.xxs)
        }
        .frame(maxWidth: Layout.restrictedMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
