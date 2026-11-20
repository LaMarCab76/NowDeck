import SwiftUI

/// Agregar a una playlist (owner's request, 2026-11-18): the item that was playing when the
/// sheet opened, and the user's editable playlists. Tapping a playlist adds the item right
/// away; the row then shows a check.
///
/// A search field filters the playlists by name, and the ones that already hold the item
/// come first, under "YA ESTÁ EN" (owner's request, 2026-11-18).
///
/// Same 640×398 sheet as Dispositivos and Cola (handle, header with the Spotify logo and
/// Cerrar, list with a bottom fade, footer with "ABRIR SPOTIFY").
struct AddToPlaylistSheetView: View {
    @ObservedObject var model: AddToPlaylistModel
    /// The item and cover captured when the sheet opened: the sheet keeps adding that item
    /// even if the music moves on.
    var item: NowPlaying
    var artwork: UIImage?
    var dismiss: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    @State private var dragOffset: CGFloat = 0
    @State private var query = ""

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
            AddToPlaylistHeader(item: item, artwork: artwork, dismiss: dismiss)
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
        if model.needsPermission {
            PermissionPanel(model: model)
        } else if let playlists = model.playlists {
            VStack(alignment: .leading, spacing: 0) {
                if let problem = model.problem {
                    HStack(alignment: .center, spacing: Spacing.m) {
                        ProblemLine(problem: problem)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // A failed read of the list: the rows on screen are the last ones
                        // that loaded. Failed adds are retried from their row instead.
                        if model.canRetryList {
                            Button("Reintentar") {
                                Task { await model.prepare(force: true) }
                            }
                            .buttonStyle(DevicesRefreshButtonStyle())
                        }
                    }
                    .padding(.bottom, Spacing.xs)
                }
                if playlists.isEmpty {
                    emptyList
                } else if model.isMembershipReady {
                    list(playlists)
                } else {
                    checkingPanel
                }
            }
        } else if let problem = model.problem {
            // The first read failed: explain and offer to try again.
            VStack(alignment: .leading, spacing: Layout.emptyGap) {
                ProblemLine(problem: problem)
                Button("Reintentar") {
                    Task { await model.prepare(force: true) }
                }
                .buttonStyle(DevicesRefreshButtonStyle())
            }
            .padding(.top, Spacing.xs)
        } else {
            ProgressView()
                .tint(theme.palette.tertiaryText.color)
                .frame(maxWidth: .infinity, minHeight: Layout.rowHeight)
                .accessibilityLabel(Text("Cargando tus playlists"))
        }
    }

    private func list(_ playlists: [EditablePlaylist]) -> some View {
        let sections = PlaylistSections(playlists: playlists, containing: model.containingIDs,
                                        query: query)
        return VStack(alignment: .leading, spacing: 0) {
            PlaylistSearchField(text: $query)
                .padding(.bottom, Metrics.AddToPlaylist.searchBottomGap)

            if model.membershipIncomplete {
                NoteLine(text: "No se pudieron revisar todas tus playlists: puede que el tema también esté en otras.")
                    .padding(.bottom, Spacing.xs)
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if sections.isEmpty {
                        noMatches
                    }
                    if !sections.alreadyIn.isEmpty {
                        sectionLabel("YA ESTÁ EN")
                        rows(sections.alreadyIn)
                    }
                    if !sections.others.isEmpty {
                        if sections.alreadyIn.isEmpty {
                            sectionLabel("TUS PLAYLISTS")
                        } else {
                            sectionLabel("OTRAS PLAYLISTS")
                                .padding(.top, Metrics.AddToPlaylist.sectionTopGap)
                        }
                        rows(sections.others)
                    }
                    Footer()
                }
                // The footer can scroll out from under the fade.
                .padding(.bottom, Layout.fadeHeight)
            }
            // In landscape the keyboard covers most of the sheet: scrolling puts it away.
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await model.prepare(force: true) }
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [theme.palette.surface.color.opacity(0),
                                        theme.palette.surface.color],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: Layout.fadeHeight)
                    .allowsHitTesting(false)
            }
        }
    }

    private func rows(_ playlists: [EditablePlaylist]) -> some View {
        ForEach(playlists) { playlist in
            PlaylistRow(playlist: playlist, state: model.state(of: playlist)) {
                Task { await model.add(to: playlist) }
            }
        }
    }

    private func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .textStyle(.devicesLabel)
            .foregroundStyle(theme.palette.label.color)
            .lineLimit(1)
            .frame(height: Layout.labelHeight, alignment: .top)
            .accessibilityAddTraits(.isHeader)
    }

    /// The search matched nothing.
    private var noMatches: some View {
        Text("Ninguna playlist se llama así.")
            .textStyle(.devicesMessage)
            .foregroundStyle(theme.palette.bodyText.color)
            .frame(maxWidth: .infinity, minHeight: Layout.rowHeight, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
    }

    /// The first time, every playlist is read to know where the item already is. The list
    /// waits for it: rows that moved while the user reaches for one would add the item to
    /// the wrong playlist.
    private var checkingPanel: some View {
        VStack(alignment: .leading, spacing: Layout.emptyGap) {
            ProgressView()
                .tint(theme.palette.tertiaryText.color)
            if let progress = model.membershipProgress {
                Text("Buscando el tema en tus playlists… \(progress.done) de \(progress.total)")
                    .textStyle(.devicesMessage)
                    .foregroundStyle(theme.palette.bodyText.color)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, minHeight: Layout.rowHeight, alignment: .leading)
        .padding(.top, Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Buscando el tema en tus playlists"))
    }

    /// No editable playlist, inside a scroll view so pull to refresh still works after
    /// creating one in Spotify.
    private var emptyList: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                MessagePanel(symbol: "music.note.list",
                             title: "No tenés playlists para editar",
                             message: "Creá una en Spotify y deslizá hacia abajo para que aparezca acá.")
                    .frame(width: proxy.size.width, alignment: .leading)
                    .frame(minHeight: proxy.size.height)
            }
            .refreshable { await model.prepare(force: true) }
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

/// Cover, "AGREGAR A UNA PLAYLIST", title and artists; the Spotify logo and Cerrar on the
/// right. The same layout as Cola's header.
private struct AddToPlaylistHeader: View {
    var item: NowPlaying
    var artwork: UIImage?
    var dismiss: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        HStack(spacing: Layout.headerGap) {
            HStack(spacing: Layout.headerGap) {
                ArtworkView(image: artwork, side: Layout.headerArtworkSize)
                VStack(alignment: .leading, spacing: 0) {
                    Text("AGREGAR A UNA PLAYLIST")
                        .textStyle(.devicesLabel)
                        .foregroundStyle(theme.palette.accent.color)
                        .lineLimit(1)
                    // Long names scroll instead of staying cut (docs/06, "Metadatos").
                    MarqueeText(verbatim: item.title)
                        .textStyle(.queueCurrentTitle)
                    if !item.subtitle.isEmpty || item.isExplicit {
                        HStack(spacing: Layout.titleGap) {
                            if item.isExplicit {
                                // Spotify asks to mark explicit content (docs/06).
                                Image(systemName: "e.square.fill")
                                    .font(.system(size: Layout.explicitSize))
                                    .foregroundStyle(theme.palette.bodyText.color)
                                    .accessibilityLabel(Text("Explícito"))
                            }
                            MarqueeText(verbatim: item.subtitle)
                                .textStyle(.queueCurrentSubtitle)
                                .foregroundStyle(theme.palette.bodyText.color)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            // Attribution on every screen with Spotify content (docs/06).
            SpotifyLogoLink(url: item.itemURL ?? SpotifyLink.home)

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

// MARK: - Search

/// A smaller version of Buscar's field: magnifying glass, text and, while there is text, a
/// button that clears it.
private struct PlaylistSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.AddToPlaylist

    var body: some View {
        HStack(spacing: Layout.searchFieldIconGap) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Layout.searchFieldIconSize - 3, weight: .bold))
                .foregroundStyle(theme.palette.bodyText.color)
                .frame(width: Layout.searchFieldIconSize, height: Layout.searchFieldIconSize)
                .accessibilityHidden(true)

            // `String()`: an empty, non-localized title (a literal would add an empty key
            // to the String Catalog).
            TextField(String(), text: $text)
                .textStyle(.playlistSearchInput)
                .foregroundStyle(theme.palette.text.color)
                .tint(theme.palette.accent.color)
                .focused($isFocused)
                .submitLabel(.done)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel(Text("Buscar una playlist"))
                // Drawn by hand, as in Buscar: iOS 16 does not color a TextField prompt.
                .background(alignment: .leading) {
                    if text.isEmpty {
                        Text("Buscar en tus playlists")
                            .textStyle(.playlistSearchInput)
                            .foregroundStyle(theme.palette.label.color)
                            .lineLimit(1)
                            .accessibilityHidden(true)
                    }
                }

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: Layout.searchFieldIconSize, weight: .regular))
                        .foregroundStyle(theme.palette.tertiaryText.color)
                        .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Borrar búsqueda"))
            }
        }
        .padding(.leading, Layout.searchFieldPadding)
        .padding(.trailing, text.isEmpty ? Layout.searchFieldPadding : 0)
        .frame(height: Layout.searchFieldHeight)
        .background(Capsule().fill(Palette.searchField))
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}

// MARK: - Rows

/// A 56 pt row: cover, name, "Colaborativa · N temas", and the state on the right (+,
/// spinner, check or warning). The whole row is the button.
private struct PlaylistRow: View {
    var playlist: EditablePlaylist
    var state: AddToPlaylistModel.RowState
    var action: () -> Void

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        Button(action: action) {
            HStack(spacing: Layout.rowGap) {
                // Fitted, never cropped, with the 4 pt radius (docs/06, "Carátulas").
                CardArtwork(url: playlist.imageURL, side: Layout.rowArtworkSize)

                VStack(alignment: .leading, spacing: 0) {
                    // Long names scroll instead of staying cut (docs/06, "Metadatos"): a tap
                    // adds right away, so the full name must be readable first.
                    MarqueeText(verbatim: playlist.name)
                        .textStyle(.trackRowTitle)
                        .foregroundStyle(theme.palette.text.color)
                    if let details {
                        Text(details)
                            .textStyle(.cardSubtitle)
                            .foregroundStyle(theme.palette.bodyText.color)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                stateIcon
                    .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
            }
            .frame(height: Layout.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`: that would dim an added row. The model ignores taps on rows that
        // are being added or were added.
        .overlay(alignment: .top) { Separator() }
        // The tap adds, so the link back to the playlist (docs/06) is a long press, as on
        // the detail's tracks.
        .contextMenu {
            if let url = playlist.pageURL {
                Button {
                    SpotifyLink.open(url)
                } label: {
                    Label("Abrir en Spotify", systemImage: "arrow.up.right")
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(state == .added ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(state == .idle || state == .failed
                           ? Text("Agrega el tema a esta playlist") : Text(verbatim: ""))
        .accessibilityAction(named: Text("Abrir en Spotify")) {
            if let url = playlist.pageURL { SpotifyLink.open(url) }
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch state {
        case .idle:
            Image(systemName: "plus.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.palette.tertiaryText.color)
        case .adding:
            ProgressView()
                .tint(theme.palette.tertiaryText.color)
        case .added:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.palette.accent.color)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.palette.warning.color)
        }
    }

    /// "Colaborativa · 12 temas", either part alone, or nothing.
    private var details: String? {
        var parts: [String] = []
        if playlist.isCollaborative {
            parts.append(String(localized: "Colaborativa"))
        }
        if let count = playlist.itemCount {
            parts.append(count == 1 ? String(localized: "1 tema")
                                    : String(localized: "\(count) temas"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var accessibilityLabel: Text {
        var label = Text(verbatim: playlist.name)
        if let details {
            label = label + Text(verbatim: ", \(details)")
        }
        switch state {
        case .idle: break
        case .adding: label = label + Text(verbatim: ", ") + Text("Agregando")
        case .added: label = label + Text(verbatim: ", ") + Text("Agregado")
        case .failed: label = label + Text(verbatim: ", ") + Text("No se pudo agregar")
        }
        return label
    }
}

/// End of the list: why some playlists are missing, and the link to Spotify.
private struct Footer: View {
    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        HStack(spacing: Layout.footerGap) {
            Text("Solo aparecen tus playlists y las colaborativas. Para quitar temas, usá Spotify.")
                .textStyle(.queueFooter)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            OpenSpotifyLink()
        }
        .padding(.top, Layout.footerTopPadding)
        .padding(.bottom, Layout.footerBottomPadding)
        .overlay(alignment: .top) { Separator() }
    }
}

private struct Separator: View {
    var body: some View {
        Rectangle()
            .fill(Palette.trackSeparator)
            .frame(height: Metrics.Queue.separatorWidth)
            .accessibilityHidden(true)
    }
}

// MARK: - Permission, empty and problems

/// Sessions from before 2026-11-18 lack the playlist-editing scopes: explain, and log in
/// again to grant them.
private struct PermissionPanel: View {
    @ObservedObject var model: AddToPlaylistModel

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.emptyGap) {
            MessagePanel(symbol: "lock.open",
                         title: "Falta un permiso",
                         message: "Para agregar temas a tus playlists, Spotify tiene que darle permiso a Nowdeck. Se abre Spotify un momento y volvés acá.",
                         fillsHeight: false)
            if case .permission = model.problem, let problem = model.problem {
                ProblemLine(problem: problem)
            }
            Button {
                Task { await model.requestPermission() }
            } label: {
                if model.isRequestingPermission {
                    ProgressView().tint(theme.palette.text.color)
                } else {
                    Text("Dar permiso")
                }
            }
            .buttonStyle(DevicesRefreshButtonStyle())
            .disabled(model.isRequestingPermission)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.bottom, Layout.emptyBottomPadding)
    }
}

/// Icon, title and explanation, in the style of Cola's empty queue.
private struct MessagePanel: View {
    var symbol: String
    var title: LocalizedStringKey
    var message: LocalizedStringKey
    var fillsHeight = true

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Queue

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.emptyGap) {
            Image(systemName: symbol)
                .font(.system(size: Layout.emptyIconSize - 6, weight: .medium))
                .foregroundStyle(theme.palette.label.color)
                .frame(width: Layout.emptyIconSize, height: Layout.emptyIconSize,
                       alignment: .leading)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(.queueEmptyTitle)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .textStyle(.queueEmptyBody)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: Layout.emptyMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .leading)
        .padding(.bottom, fillsHeight ? Layout.emptyBottomPadding : 0)
    }
}

/// A warning that does not stop the list, with the same look as `ProblemLine`.
private struct NoteLine: View {
    var text: LocalizedStringKey

    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(theme.palette.warning.color)
                .accessibilityHidden(true)
            Text(text)
                .foregroundStyle(theme.palette.bodyText.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .textStyle(.devicesMessage)
        .accessibilityElement(children: .combine)
    }
}

/// The last problem, with the warning icon (like Dispositivos and Cola).
private struct ProblemLine: View {
    var problem: AddToPlaylistProblem

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
