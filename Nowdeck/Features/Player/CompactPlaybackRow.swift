import SwiftUI

/// The fixed row below the lyrics or playback queue. Only this row follows a track swipe.
struct CompactPlaybackRow: View {
    let title: String
    let artist: String
    let isExplicit: Bool
    let artwork: Image?
    let deviceName: String?
    let deviceType: String?
    let onShowDevices: () -> Void
    let swipe: TrackSwipePhase
    let pageWidth: CGFloat
    let upNext: TrackPreview?
    let previousTrack: TrackPreview?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var theme: ThemeStore

    /// Changes with the track, for the footer's animations.
    private var trackKey: String { title + "|" + artist }

    var body: some View {
        ZStack(alignment: .leading) {
            currentFooter
                .offset(x: swipe.offset(pageWidth: pageWidth))
            if let edge = swipe.edge {
                previewFooter(edge: edge)
                    .offset(x: swipe.previewOffset(pageWidth: pageWidth))
            }
        }
        .frame(height: Metrics.Lyrics.footerHeight)
        .trackSwipeBand()
    }

    /// While a swiped-in item settles, the row swaps to it without animation (see
    /// `PlayerView.animatesTrackChange`).
    private var animatesTrackChange: Bool { !swipe.isLanding }

    private var currentFooter: some View {
        HStack(spacing: Metrics.Lyrics.footerSpacing) {
            ZStack {
                CompactPlaybackArtwork(image: artwork)
                    .id(trackKey)
                    .transition(.opacity)
            }
            .animation(animatesTrackChange ? Motion.artworkCrossfade : nil, value: trackKey)
            ZStack(alignment: .leading) {
                CompactPlaybackLabels(title: title, artist: artist, isExplicit: isExplicit)
                    .id(trackKey)
                    .transition(Motion.rise(Motion.trackRise, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(animatesTrackChange ? Motion.trackChange : nil, value: trackKey)
            deviceButton(action: onShowDevices)
        }
    }

    private func previewFooter(edge: TrackSwipe.Edge) -> some View {
        let preview: TrackPreview?
        switch swipe {
        case .landing(_, let frozen, _): preview = frozen
        default: preview = edge == .right ? upNext : previousTrack
        }
        return HStack(spacing: Metrics.Lyrics.footerSpacing) {
            CompactPlaybackArtwork(image: preview?.artwork.map(Image.init(uiImage:)))
            Group {
                if let item = preview?.item {
                    CompactPlaybackLabels(title: item.title, artist: item.subtitle,
                                      isExplicit: item.isExplicit)
                } else {
                    Text(edge == .right ? "Siguiente" : "Anterior")
                        .textStyle(.lyricsTrackTitle)
                        .foregroundColor(theme.palette.secondaryText.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            deviceButton(action: {})
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func deviceButton(action: @escaping () -> Void) -> some View {
        if let deviceName {
            CompactPlaybackDeviceButton(name: deviceName, type: deviceType ?? "", action: action)
        }
    }
}

/// 56 pt artwork with the Spotify radius of 4. Fitted, never cropped.
private struct CompactPlaybackArtwork: View {
    let image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Palette.subtleSurface
            }
        }
        .frame(width: Metrics.Lyrics.artworkSize, height: Metrics.Lyrics.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: Radius.artwork))
        .accessibilityHidden(true)
    }
}

private struct CompactPlaybackLabels: View {
    let title: String
    let artist: String
    let isExplicit: Bool
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.Lyrics.titleArtistSpacing) {
            HStack(spacing: Spacing.xs) {
                MarqueeText(verbatim: title)
                    .textStyle(.lyricsTrackTitle)
                    .foregroundColor(theme.palette.text.color)
                if isExplicit {
                    // Not in the mockup; Spotify asks to mark explicit content (docs/06).
                    Image(systemName: "e.square.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(theme.palette.secondaryText.color)
                        .accessibilityLabel(Text("Explícito"))
                }
            }
            MarqueeText(verbatim: artist)
                .textStyle(.lyricsArtist)
                .foregroundColor(theme.palette.secondaryText.color)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Device name in the accent color. Opens the devices sheet.
private struct CompactPlaybackDeviceButton: View {
    let name: String
    let type: String
    let action: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.Lyrics.deviceIconSpacing) {
                DeviceSymbol.image(for: type)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: Metrics.Lyrics.deviceIconSize, height: Metrics.Lyrics.deviceIconSize)
                    .accessibilityHidden(true)
                MarqueeText(verbatim: name)
                    .textStyle(.lyricsDevice)
            }
            .foregroundColor(theme.palette.accent.color)
            .frame(height: Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Reproduciendo en \(name)"))
        .accessibilityHint(Text("Abre la lista de dispositivos"))
    }
}
