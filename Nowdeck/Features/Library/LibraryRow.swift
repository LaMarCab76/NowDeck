import SwiftUI

// MARK: - Filters

/// Playlists, Álbumes, Podcasts (and Audiolibros when available), plus "ABRIR SPOTIFY ↗".
struct LibraryFilterBar: View {
    var filters: [LibraryFilter]
    var selected: LibraryFilter
    var onSelect: (LibraryFilter) -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        HStack(spacing: Layout.rowGap) {
            HStack(spacing: Layout.filterGap) {
                ForEach(filters) { filter in
                    chip(filter)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Filtrar biblioteca"))

            Spacer(minLength: 0)
            OpenSpotifyLink()
        }
        .frame(height: Layout.rowHeight)
    }

    private func chip(_ filter: LibraryFilter) -> some View {
        let isSelected = filter == selected
        return Button { onSelect(filter) } label: {
            Text(filter.title)
                .textStyle(.libraryFilter)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Palette.playButtonIcon : theme.palette.text.color)
                .padding(.horizontal, Layout.filterHorizontalPadding)
                .frame(height: Layout.filterHeight)
                .background(Capsule().fill(isSelected ? theme.palette.text.color : .clear))
                .overlay(Capsule().strokeBorder(isSelected ? theme.palette.text.color
                                                           : Palette.chipBorder,
                                                lineWidth: Layout.filterBorderWidth))
                // 36 pt chips inside a 44 pt row: the tap area takes the whole row height.
                .frame(height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Inside a playlist folder (experimental): "‹ Volver" and the folder's name, in place of
/// the filters.
struct FolderBackBar: View {
    var folderName: String
    var onBack: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        HStack(spacing: Layout.rowGap) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .accessibilityHidden(true)
                    Text("Volver")
                        .textStyle(.libraryFilter)
                }
                .foregroundStyle(theme.palette.text.color)
                .padding(.horizontal, Layout.filterHorizontalPadding)
                .frame(height: Layout.filterHeight)
                .overlay(Capsule().strokeBorder(Palette.chipBorder,
                                                lineWidth: Layout.filterBorderWidth))
                .frame(height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.palette.tertiaryText.color)
                    .accessibilityHidden(true)
                // Names are shown verbatim and scroll when they don't fit.
                MarqueeText(verbatim: folderName)
                    .textStyle(.libraryFilter)
                    .foregroundStyle(theme.palette.text.color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
            OpenSpotifyLink()
        }
        .frame(height: Layout.rowHeight)
    }
}

/// "ABRIR SPOTIFY ↗": the visible link the compliance checklist asks for. The detail screen
/// uses it as "ABRIR EN SPOTIFY ↗", with the playlist's or album's page.
struct OpenSpotifyLink: View {
    var title: LocalizedStringKey = "ABRIR SPOTIFY"
    var url: URL? = SpotifyLink.home

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        Button {
            SpotifyLink.open(url)
        } label: {
            HStack(spacing: Layout.openSpotifyIconGap) {
                Text(title)
                    .textStyle(.openSpotifyLink)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: Layout.openSpotifyIconSize - 2, weight: .bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.palette.text.color)
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityAddTraits(.isLink)
    }
}

// MARK: - Row

/// The horizontal row of cards for the selected filter, with its loading, empty and error
/// states. Ends with a card that opens Spotify (guidelines: every content row ends with a
/// link to the Spotify app).
struct LibraryRow: View {
    var state: LibraryModel.RowState
    var startingURI: String?
    /// The right margin the row slides under, added back at the end of the content so the
    /// last card can scroll fully into view.
    var trailingMargin: CGFloat
    /// Tapping a card opens a folder, a playlist or album detail, or Spotify.
    var onOpen: (LibraryEntry) -> Void
    /// "Reproducir" in a card's menu: plays it without opening it.
    var onPlay: (LibraryEntry) -> Void
    var onRetry: () -> Void

    private typealias Layout = Metrics.Library

    var body: some View {
        Group {
            switch state {
            case .idle, .loading:
                placeholders
            case .loaded(let items) where items.isEmpty:
                HStack(alignment: .top, spacing: Layout.cardGap) {
                    MoreInSpotifyCard()
                    RowMessage(text: "No hay nada guardado acá todavía.")
                }
            case .loaded(let items):
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: Layout.cardGap) {
                        ForEach(items) { item in
                            LibraryCard(item: item, isStarting: item.uri == startingURI,
                                        onOpen: { onOpen(item) },
                                        onPlay: { onPlay(item) })
                        }
                        MoreInSpotifyCard()
                    }
                    .padding(.trailing, trailingMargin)
                }
            case .failed(let failure):
                RowMessage(text: message(for: failure), onRetry: onRetry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Layout.rowHeightWithText, alignment: .top)
    }

    private var placeholders: some View {
        HStack(spacing: Layout.cardGap) {
            ForEach(0..<Layout.placeholderCount, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous)
                    .fill(Palette.subtleSurface)
                    .frame(width: Layout.cardSize, height: Layout.cardSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cargando"))
    }

    private func message(for failure: LibraryModel.LoadFailure) -> LocalizedStringKey {
        switch failure {
        case .forbidden:
            return "Spotify no deja leer tu biblioteca con esta cuenta. Revisá que siga en Users Management, en el panel de Spotify."
        case .rateLimited:
            return "Spotify pidió esperar un momento. Probá de nuevo en un rato."
        case .failed:
            return "No pudimos cargar tu biblioteca. Revisá la conexión y probá de nuevo."
        }
    }
}

/// A message in the row area (also the detail screen's track list), with an optional
/// "Reintentar".
struct RowMessage: View {
    var text: LocalizedStringKey
    var onRetry: (() -> Void)?

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(text)
                .textStyle(.searchHelp)
                .foregroundStyle(theme.palette.bodyText.color)
                .frame(maxWidth: Metrics.Library.searchHelpMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry {
                Button("Reintentar", action: onRetry)
                    .buttonStyle(RetryButtonStyle())
            }
        }
        .padding(.top, Spacing.s)
    }
}

/// Outlined capsule, like the filters.
private struct RetryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.libraryFilter)
            .padding(.horizontal, Metrics.Library.filterHorizontalPadding)
            .frame(height: Metrics.minTouchTarget)
            .overlay(Capsule().strokeBorder(Palette.chipBorder,
                                            lineWidth: Metrics.Library.filterBorderWidth))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - Cards

/// A 150 pt card: artwork (fitted, never cropped nor covered), name and subtitle.
///
/// Tapping a folder opens its contents. Playlists and albums open their detail screen,
/// while podcasts and audiobooks open in Spotify. A long press on a Spotify item shows
/// its full name and the available actions (docs/06).
struct LibraryCard: View {
    var item: LibraryEntry
    var isStarting: Bool
    var onOpen: () -> Void
    var onPlay: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Layout.cardTextGap) {
                if case .folder = item.kind {
                    FolderTile(side: Layout.cardSize)
                } else {
                    CardArtwork(url: item.artworkURL, side: Layout.cardSize)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: item.name)
                        .textStyle(.cardTitle)
                        .foregroundStyle(theme.palette.text.color)
                    Text(verbatim: item.subtitle)
                        .textStyle(.cardSubtitle)
                        .foregroundStyle(theme.palette.bodyText.color)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                // While playback starts, the texts dim. The artwork stays as Spotify sends
                // it: nothing drawn over it, no fading (docs/06, "Carátulas").
                .opacity(isStarting ? 0.5 : 1)
            }
            .frame(width: Layout.cardSize, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(item.name), \(item.subtitle)"))
        .accessibilityHint(hint)
        .modifier(CardMenu(item: item, onPlay: onPlay, theme: theme))
    }

    private var hint: Text {
        if case .folder = item.kind { return Text("Abre la carpeta") }
        return item.playsInPlace ? Text("Muestra los temas")
                                 : Text("Abre en Spotify")
    }
}

/// The long-press menu of a card (folders have none: they have no page in Spotify).
private struct CardMenu: ViewModifier {
    var item: LibraryEntry
    var onPlay: () -> Void
    var theme: ThemeStore

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .folder = item.kind {
            content
        } else {
            menu(content)
        }
    }

    private func menu(_ content: Content) -> some View {
        content
        // The Spotify link is reachable from the VoiceOver rotor too.
        .accessibilityAction(named: Text("Abrir en Spotify")) { SpotifyLink.open(item.pageURL) }
        .contextMenu {
            if item.playsInPlace {
                Button(action: onPlay) {
                    Label("Reproducir", systemImage: "play.fill")
                }
            }
            Button {
                SpotifyLink.open(item.pageURL)
            } label: {
                Label("Abrir en Spotify", systemImage: "arrow.up.right")
            }
        } preview: {
            CardPreview(item: item)
                .environmentObject(theme)
        }
    }
}

/// A folder card's square: a filled tile with a folder symbol, like "Ver más en Spotify".
private struct FolderTile: View {
    var side: CGFloat
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        RoundedRectangle(cornerRadius: Metrics.Library.moreCardRadius, style: .continuous)
            .fill(Palette.subtleSurface)
            .overlay(
                Image(systemName: "folder")
                    .font(.system(size: Metrics.Library.moreCardIconSize, weight: .semibold))
                    .foregroundStyle(theme.palette.text.color)
            )
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// The long-press preview: the artwork larger and the full name.
private struct CardPreview: View {
    var item: LibraryEntry
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            CardArtwork(url: item.artworkURL, side: 220)
            Text(verbatim: item.name)
                .textStyle(.cardTitle)
                .foregroundStyle(theme.palette.text.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: item.subtitle)
                .textStyle(.cardSubtitle)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 220, alignment: .leading)
        .padding(Spacing.m)
        .background(theme.palette.surface.color)
    }
}

/// Artwork loaded from Spotify's CDN, fitted in a square with the 4 pt radius. While it
/// loads (or if it fails) the square is a neutral surface.
struct CardArtwork: View {
    var url: URL?
    var side: CGFloat

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Palette.subtleSurface
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Last card of every row: opens Spotify. Not in the mockup; required by Spotify's
/// guidelines for content rows (docs/06-cumplimiento.md).
struct MoreInSpotifyCard: View {
    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        Button {
            SpotifyLink.open(SpotifyLink.home)
        } label: {
            VStack(alignment: .leading, spacing: Layout.cardTextGap) {
                RoundedRectangle(cornerRadius: Layout.moreCardRadius, style: .continuous)
                    .strokeBorder(Palette.chipBorder, lineWidth: Layout.filterBorderWidth)
                    .overlay(
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: Layout.moreCardIconSize, weight: .semibold))
                            .foregroundStyle(theme.palette.text.color)
                    )
                    .frame(width: Layout.cardSize, height: Layout.cardSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ver más en Spotify")
                        .textStyle(.cardTitle)
                        .foregroundStyle(theme.palette.text.color)
                    Text("Abre la app de Spotify")
                        .textStyle(.cardSubtitle)
                        .foregroundStyle(theme.palette.bodyText.color)
                }
                .lineLimit(1)
            }
            .frame(width: Layout.cardSize, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Ver más en Spotify"))
        .accessibilityAddTraits(.isLink)
    }
}
