import SwiftUI

/// Cola (Cola.html): what plays now and what comes next, in the same 640×398 sheet as
/// Dispositivos.
///
/// Read-only on purpose: the Web API cannot remove, reorder or jump to a queued item
/// (docs/03, "Cola"). Rows are not buttons, so they do not suggest that a tap plays them;
/// a long press shows the full name and "Abrir en Spotify", like in the playlist detail.
/// The list ends with "ABRIR SPOTIFY", as the guidelines ask for content rows (docs/06).
struct QueueSheetView: View {
    @ObservedObject var model: QueueModel
    /// The player's current item and cover, for the header.
    var nowPlaying: NowPlaying?
    var artwork: UIImage?
    var dismiss: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @State private var dragOffset: CGFloat = 0

    private typealias Sheet = Metrics.Devices
    private typealias Layout = Metrics.Queue

    var body: some View {
        GeometryReader { proxy in
            // Same size rules as Dispositivos: 640 wide, and on the iPhone 8 Plus (736)
            // still 640 with the minimum 48 pt margins.
            let width = min(Sheet.sheetWidth, proxy.size.width - 2 * Sheet.minSideMargin)

            sheet
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .padding(.top, Sheet.sheetTop)
                .offset(y: dragOffset)
                .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
        .background(theme.palette.background.color.ignoresSafeArea())
        .foregroundStyle(theme.palette.text.color)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: Sheet.sheetGap) {
            handle
            QueueHeader(nowPlaying: nowPlaying, artwork: artwork, dismiss: dismiss)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.top, Sheet.sheetTopPadding)
        .padding(.horizontal, Sheet.sheetHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            UnevenTopRoundedRectangle(radius: Radius.sheet)
                .fill(theme.palette.surface.color)
        )
        .clipShape(UnevenTopRoundedRectangle(radius: Radius.sheet))
    }

    @ViewBuilder
    private var content: some View {
        if let entries = model.entries {
            VStack(alignment: .leading, spacing: 0) {
                if let problem = model.problem {
                    QueueProblemLine(problem: problem)
                        .padding(.bottom, Spacing.xs)
                }
                if entries.isEmpty {
                    emptyQueue
                } else {
                    list(entries)
                }
            }
        } else if let problem = model.problem {
            // The first read failed: explain and offer to try again.
            VStack(alignment: .leading, spacing: Layout.emptyGap) {
                QueueProblemLine(problem: problem)
                Button("Reintentar") {
                    Task { await model.reload() }
                }
                .buttonStyle(DevicesRefreshButtonStyle())
            }
            .padding(.top, Spacing.xs)
        } else {
            ProgressView()
                .tint(theme.palette.tertiaryText.color)
                .frame(maxWidth: .infinity, minHeight: Layout.rowHeight)
                .accessibilityLabel(Text("Cargando la cola"))
        }
    }

    private func list(_ entries: [QueueEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A CONTINUACIÓN")
                .textStyle(.devicesLabel)
                .foregroundStyle(theme.palette.label.color)
                .lineLimit(1)
                .frame(height: Layout.labelHeight, alignment: .top)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        QueueRow(entry: entry)
                    }
                    QueueFooter()
                }
                // The footer can scroll out from under the fade.
                .padding(.bottom, Layout.fadeHeight)
            }
            .refreshable { await model.reload() }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [theme.palette.surface.color.opacity(0),
                                        theme.palette.surface.color],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.fadeHeight)
                    .allowsHitTesting(false)
            }
        }
    }

    /// "No hay nada en la cola", inside a scroll view so that pull to refresh still works:
    /// the queue is not polled, and something added from another Spotify app would
    /// otherwise only show up after closing and opening the sheet.
    private var emptyQueue: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                QueueEmptyView()
                    // At least the visible height, so the message stays centered.
                    .frame(width: proxy.size.width, alignment: .leading)
                    .frame(minHeight: proxy.size.height)
            }
            .refreshable { await model.reload() }
        }
    }

    /// The 40×5 handle. Dragging it down closes the sheet, like in Dispositivos.
    private var handle: some View {
        Capsule()
            .fill(Palette.sheetHandle)
            .frame(width: Sheet.handleSize.width, height: Sheet.handleSize.height)
            .frame(maxWidth: .infinity, minHeight: Sheet.handleSize.height)
            .contentShape(Rectangle().inset(by: -12))
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = max(0, $0.translation.height) }
                    .onEnded { value in
                        if value.translation.height > Sheet.dismissDragDistance {
                            dismiss()
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        }
                    }
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Header

/// Cover, "SONANDO", title and artists; the Spotify logo and Cerrar on the right.
private struct QueueHeader: View {
    var nowPlaying: NowPlaying?
    var artwork: UIImage?
    var dismiss: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        HStack(spacing: Layout.headerGap) {
            HStack(spacing: Layout.headerGap) {
                ArtworkView(image: artwork, side: Layout.headerArtworkSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text("SONANDO")
                        .textStyle(.devicesLabel)
                        .foregroundStyle(theme.palette.accent.color)
                        .lineLimit(1)
                    if let nowPlaying {
                        // Long names scroll instead of staying cut (docs/06, "Metadatos").
                        MarqueeText(verbatim: nowPlaying.title)
                            .textStyle(.queueCurrentTitle)
                        if !nowPlaying.subtitle.isEmpty || nowPlaying.isExplicit {
                            // The mark goes before the artists, as in the player (TitleBlock).
                            HStack(spacing: Layout.titleGap) {
                                if nowPlaying.isExplicit {
                                    // Spotify asks to mark explicit content (docs/06).
                                    Image(systemName: "e.square.fill")
                                        .font(.system(size: Layout.explicitSize))
                                        .foregroundStyle(theme.palette.bodyText.color)
                                        .accessibilityLabel(Text("Explícito"))
                                }
                                MarqueeText(verbatim: nowPlaying.subtitle)
                                    .textStyle(.queueCurrentSubtitle)
                                    .foregroundStyle(theme.palette.bodyText.color)
                            }
                        }
                    } else {
                        Text("Nada sonando")
                            .textStyle(.queueCurrentTitle)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            // Attribution on every screen with Spotify content (docs/06).
            SpotifyLogoLink(url: nowPlaying?.itemURL ?? SpotifyLink.home)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: Metrics.Devices.closeIconSize, weight: .bold))
                    .foregroundStyle(theme.palette.text.color)
                    .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                    .background(Circle().fill(Palette.closeButtonFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Cerrar"))
        }
        .frame(height: Layout.headerArtworkSize)
    }
}

// MARK: - Rows

/// A 56 pt row: number, cover, title (with the explicit mark), artists and duration.
private struct QueueRow: View {
    var entry: QueueEntry

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    private var track: CollectionTrack { entry.track }

    var body: some View {
        HStack(spacing: Layout.rowGap) {
            Text(verbatim: "\(track.number)")
                .textStyle(.trackRowNumber)
                .foregroundStyle(theme.palette.tertiaryText.color)
                .lineLimit(1)
                .frame(width: Layout.numberWidth, alignment: .trailing)

            // Fitted, never cropped, with the 4 pt radius (docs/06, "Carátulas").
            CardArtwork(url: entry.artworkURL, side: Layout.rowArtworkSize)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Layout.titleGap) {
                    Text(verbatim: track.title)
                        .textStyle(.trackRowTitle)
                        .foregroundStyle(theme.palette.text.color)
                    if track.isExplicit {
                        // Spotify asks to mark explicit content (docs/06).
                        Image(systemName: "e.square.fill")
                            .font(.system(size: Layout.explicitSize))
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

            if let duration = track.durationMs, duration > 0 {
                Text(verbatim: PlaybackProgress.formatted(ms: duration))
                    .textStyle(.trackRowNumber)
                    .foregroundStyle(theme.palette.tertiaryText.color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: Layout.rowHeight)
        .overlay(alignment: .top) { QueueSeparator() }
        .opacity(track.isAvailable ? 1 : Metrics.Library.trackUnavailableOpacity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        // Truncated names can be read in full with a long press (docs/06, "Metadatos").
        .modifier(TrackMenu(track: track))
    }

    private var accessibilityLabel: Text {
        var label = Text(verbatim: "\(track.number). \(track.title)")
        if track.isExplicit {
            label = label + Text(verbatim: ", ") + Text("Explícito")
        }
        if !track.subtitle.isEmpty {
            label = label + Text(verbatim: ", \(track.subtitle)")
        }
        if let duration = track.durationMs, duration > 0 {
            label = label + Text(verbatim: ", \(PlaybackProgress.formatted(ms: duration))")
        }
        return label
    }
}

/// End of the list: why it cannot be edited here, and the link to Spotify.
private struct QueueFooter: View {
    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        HStack(spacing: Layout.footerGap) {
            Text("Para quitar o reordenar temas, usá Spotify.")
                .textStyle(.queueFooter)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            OpenSpotifyLink()
        }
        .padding(.top, Layout.footerTopPadding)
        .padding(.bottom, Layout.footerBottomPadding)
        .overlay(alignment: .top) { QueueSeparator() }
    }
}

private struct QueueSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.trackSeparator)
            .frame(height: Metrics.Queue.separatorWidth)
            .accessibilityHidden(true)
    }
}

// MARK: - Empty and problems

/// "No hay nada en la cola", in the style of the detail's restricted playlist message.
private struct QueueEmptyView: View {
    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.emptyGap) {
            Image(systemName: "list.bullet")
                .font(.system(size: Layout.emptyIconSize - 6, weight: .medium))
                .foregroundStyle(theme.palette.label.color)
                .frame(width: Layout.emptyIconSize, height: Layout.emptyIconSize,
                       alignment: .leading)
                .accessibilityHidden(true)
            Text("No hay nada en la cola")
                .textStyle(.queueEmptyTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Cuando termine este tema, Spotify decide qué sigue. Podés elegir algo desde la Biblioteca.")
                .textStyle(.queueEmptyBody)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: Layout.emptyMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.bottom, Layout.emptyBottomPadding)
    }
}

/// The last problem, with the warning icon (like Dispositivos).
private struct QueueProblemLine: View {
    var problem: QueueProblem

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(theme.palette.warning.color)
                .accessibilityHidden(true)
            Text(problem.message)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textStyle(.devicesMessage)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}
