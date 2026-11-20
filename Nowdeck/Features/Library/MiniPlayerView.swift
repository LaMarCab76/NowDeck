import SwiftUI

/// The mini player at the bottom of the library (`Biblioteca.dc.html`): Agregar a una
/// playlist at the left end (owner's request, 2026-11-18), artwork, title and artist (back to
/// the player), "Suena en **Dispositivo**" (devices) and play/pause.
///
/// Its background is the artwork color, softened like the player's
/// (`ArtworkColor.playerBackground`). The design asks for it unconditionally, so it does
/// not follow Ajustes → "Fondo del reproductor": with a black player background the mini
/// player would disappear against the black library.
struct MiniPlayerView: View {
    var item: NowPlaying?
    var artwork: UIImage?
    var artworkColor: RGBColor?
    var device: SpotifyDevice?
    var isPlaying: Bool
    var onOpenPlayer: () -> Void
    var onShowDevices: () -> Void
    var onPlayPause: () -> Void
    var onAddToPlaylist: () -> Void = {}

    @EnvironmentObject private var theme: ThemeStore
    private typealias Layout = Metrics.Library

    var body: some View {
        HStack(spacing: Layout.miniGap) {
            if let item {
                addToPlaylistButton(isEnabled: item.playlistURI != nil)
            }

            Button(action: onOpenPlayer) {
                HStack(spacing: Layout.miniArtworkGap) {
                    artworkView
                    titles
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Vuelve al reproductor"))

            deviceButton

            if item != nil {
                playPauseButton
            }
        }
        .padding(.leading, Layout.miniLeadingPadding)
        .padding(.trailing, Layout.miniTrailingPadding)
        .frame(height: Layout.miniHeight)
        .background(
            RoundedRectangle(cornerRadius: Layout.miniRadius, style: .continuous)
                .fill(background)
                .animation(.easeInOut(duration: 0.5), value: background)
        )
    }

    private var background: Color {
        guard let artworkColor else { return Palette.miniPlayerFallback }
        return ArtworkColor.playerBackground(from: artworkColor,
                                             readableWith: theme.palette.tertiaryText).color
    }

    @ViewBuilder
    private var artworkView: some View {
        if item != nil {
            ArtworkView(image: artwork, side: Layout.miniArtworkSize)
        } else {
            RoundedRectangle(cornerRadius: Radius.artwork, style: .continuous)
                .strokeBorder(Palette.emptyArtworkBorder,
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: Layout.miniArtworkSize, height: Layout.miniArtworkSize)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var titles: some View {
        if let item {
            // One line that scrolls when it does not fit (docs/06, "Metadatos").
            MarqueeText(titleLine(item), id: "\(item.title)|\(item.subtitle)",
                        accessibilityText: titleLabel(item))
        } else {
            Text("Nada sonando")
                .textStyle(.miniTitle)
                .foregroundStyle(theme.palette.text.color)
                .lineLimit(1)
        }
    }

    /// Title, explicit mark and artist, as one text so they scroll together.
    private func titleLine(_ item: NowPlaying) -> Text {
        // Two spaces at these sizes give about the 8 pt gap of the mockup.
        let gap = Text(verbatim: "  ")
        var line = Text(verbatim: item.title)
            .font(TextStyle.miniTitle.fixedFont)
            .foregroundColor(theme.palette.text.color)
        if item.isExplicit {
            line = line + gap + Text(Image(systemName: "e.square.fill"))
                .font(.system(size: 13))
                .foregroundColor(theme.palette.bodyText.color)
        }
        if !item.subtitle.isEmpty {
            line = line + gap + Text(verbatim: item.subtitle)
                .font(TextStyle.miniSubtitle.fixedFont)
                .foregroundColor(theme.palette.bodyText.color)
        }
        return line
    }

    private func titleLabel(_ item: NowPlaying) -> Text {
        var label = Text(verbatim: item.title)
        if item.isExplicit {
            label = label + Text(verbatim: ", ") + Text("Explícito")
        }
        if !item.subtitle.isEmpty {
            label = label + Text(verbatim: ", ") + Text(verbatim: item.subtitle)
        }
        return label
    }

    private var deviceButton: some View {
        Button(action: onShowDevices) {
            HStack(spacing: Layout.miniDeviceIconGap) {
                DeviceSymbol.image(for: device?.type ?? "")
                    .font(.system(size: Layout.miniDeviceIconSize - 3, weight: .medium))
                    .frame(width: Layout.miniDeviceIconSize, height: Layout.miniDeviceIconSize)
                    .accessibilityHidden(true)
                deviceText
                    .lineLimit(1)
            }
            .foregroundStyle(theme.palette.accent.color)
            .padding(.horizontal, Layout.miniDevicePadding)
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityHint(Text("Abre la lista de dispositivos"))
    }

    private var deviceText: Text {
        guard let name = device?.name, !name.isEmpty else {
            return Text("Elegir dispositivo").font(TextStyle.miniDeviceName.fixedFont)
        }
        return Text("Suena en").font(TextStyle.miniDevicePrefix.fixedFont)
            + Text(verbatim: " ")
            + Text(verbatim: name).font(TextStyle.miniDeviceName.fixedFont)
    }

    /// Same icon as the player's button. Disabled for ads and local files.
    private func addToPlaylistButton(isEnabled: Bool) -> some View {
        Button(action: onAddToPlaylist) {
            Image(systemName: "plus.circle")
                .font(.system(size: Layout.miniAddIconSize, weight: .semibold))
                .foregroundStyle(theme.palette.text.color)
                .frame(width: Metrics.minTouchTarget, height: Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : Palette.disabledControlOpacity)
        .accessibilityLabel(Text("Agregar a una playlist"))
        .accessibilityHint(Text("Elegí una de tus playlists"))
    }

    private var playPauseButton: some View {
        Button(action: onPlayPause) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: Layout.miniPlayIconSize, weight: .bold))
                .foregroundStyle(Palette.playButtonIcon)
                .frame(width: Layout.miniPlayButtonSize, height: Layout.miniPlayButtonSize)
                .background(Circle().fill(theme.palette.text.color))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPlaying ? Text("Pausar") : Text("Reproducir"))
    }
}
