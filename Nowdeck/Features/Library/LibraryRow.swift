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

/// "ABRIR SPOTIFY ↗": the visible link the compliance checklist asks for.
struct OpenSpotifyLink: View {
    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        Button {
            SpotifyLink.open(SpotifyLink.home)
        } label: {
            HStack(spacing: Layout.openSpotifyIconGap) {
                Text("ABRIR SPOTIFY")
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

/// A message in the row area, with an optional "Reintentar".
private struct RowMessage: View {
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
/// Names that don't fit are cut with "…"; a long press shows them whole, together with
/// "Abrir en Spotify" (docs/06: truncated metadata must be readable somehow, and the name
/// links back to Spotify).
struct LibraryCard: View {
    var item: LibraryEntry
    var isStarting: Bool
    var onPlay: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: Layout.cardTextGap) {
                CardArtwork(url: item.artworkURL, side: Layout.cardSize)
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
        .accessibilityHint(item.playsInPlace ? Text("Reproduce en el dispositivo activo")
                                             : Text("Abre en Spotify"))
        // The context menu's two actions, reachable from the VoiceOver rotor too.
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
