import SwiftUI

/// The scrollable center of the player's queue mode (cola-integrada.html).
///
/// The Web API cannot remove, reorder or jump to a queued item (docs/03, "Cola"). Tapping a
/// track asks "¿Reproducir este tema?" and, on "Reproducir", plays it now
/// (`SpotifyAPI.playFromQueue`). A long press shows the full name and "Abrir en Spotify",
/// like in the playlist detail. The list ends with "ABRIR SPOTIFY", as the guidelines ask
/// for content rows (docs/06).
struct QueueView: View {
    @ObservedObject var player: PlayerModel
    @ObservedObject var controls: PlayerControlsModel
    @ObservedObject var model: QueueModel
    @EnvironmentObject private var theme: ThemeStore
    @State private var pendingEntry: QueueEntry?

    private typealias Layout = Metrics.Queue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("A CONTINUACIÓN")
                .textStyle(.devicesLabel)
                .foregroundStyle(theme.palette.secondaryText.color)
                .lineLimit(1)
                .frame(height: Layout.queueLabelHeight)
                .accessibilityAddTraits(.isHeader)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(theme.palette.text.color)
        .alert("¿Reproducir este tema?", isPresented: isConfirming, presenting: pendingEntry) { entry in
            Button("Reproducir") { play(entry) }
            Button("Cancelar", role: .cancel) {}
        } message: { entry in
            Text(confirmationMessage(for: entry.track))
        }
        .task { await model.reload() }
        .onChange(of: player.itemStarts) { _ in
            // Consecutive plays of the same track consume an entry too.
            Task { await model.trackDidChange() }
        }
    }

    private var isConfirming: Binding<Bool> {
        Binding(get: { pendingEntry != nil },
                set: { if !$0 { pendingEntry = nil } })
    }

    /// "«Título» de Artistas empieza a sonar ahora." Episodes are never tapped, so there is
    /// always a title; the artists may be missing.
    private func confirmationMessage(for track: CollectionTrack) -> String {
        if track.subtitle.isEmpty {
            return String(localized: "«\(track.title)» empieza a sonar ahora.")
        }
        return String(localized: "«\(track.title)» de \(track.subtitle) empieza a sonar ahora.")
    }

    private func play(_ entry: QueueEntry) {
        Task { await controls.playQueuedTrack(entry, in: model) }
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
                    Task { await model.reload(clearingPlaybackProblem: true) }
                }
                .buttonStyle(DevicesRefreshButtonStyle())
            }
            .padding(.top, Spacing.xs)
        } else {
            ProgressView()
                .tint(theme.palette.tertiaryText.color)
                .frame(maxWidth: .infinity, minHeight: Layout.queueRowHeight)
                .accessibilityLabel(Text("Cargando la cola"))
        }
    }

    private func list(_ entries: [QueueEntry]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(entries) { entry in
                    QueueRow(entry: entry, isStarting: model.startingID == entry.id) {
                        pendingEntry = entry
                    }
                    .disabled(controls.isSendingCommand)
                }
                QueueFooter()
            }
        }
        .refreshable { await model.reload(clearingPlaybackProblem: true) }
    }

    /// "No hay nada en la cola", inside a scroll view so that pull to refresh still works:
    /// the queue is not polled, and something added from another Spotify app would
    /// otherwise only show up after closing and reopening Queue.
    private var emptyQueue: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                QueueEmptyView()
                    // At least the visible height, so the message stays centered.
                    .frame(width: proxy.size.width, alignment: .leading)
                    .frame(minHeight: proxy.size.height)
            }
            .refreshable { await model.reload(clearingPlaybackProblem: true) }
        }
    }
}

// MARK: - Rows

/// A 48 pt row: number, cover, title (with the explicit mark), artists and duration. A
/// playable row is a button that asks to play it (`onTap`); local files and episodes are
/// not.
private struct QueueRow: View {
    var entry: QueueEntry
    /// Its track is starting: a spinner takes the duration's place.
    var isStarting = false
    var onTap: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    private var track: CollectionTrack { entry.track }

    var body: some View {
        if entry.playURI != nil {
            Button(action: onTap) { row }
                .buttonStyle(QueueRowButtonStyle())
                .accessibilityHint(Text("Pregunta antes de reproducirlo"))
        } else {
            row
        }
    }

    private var row: some View {
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

            if isStarting {
                ProgressView()
                    .tint(theme.palette.tertiaryText.color)
                    .accessibilityHidden(true)
            } else if let duration = track.durationMs, duration > 0 {
                Text(verbatim: PlaybackProgress.formatted(ms: duration))
                    .textStyle(.trackRowNumber)
                    .foregroundStyle(theme.palette.tertiaryText.color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: Layout.queueRowHeight)
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

/// Pressed rows dim a little, like the library cards; no other change of look.
private struct QueueRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
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
