import Combine
import SwiftUI

/// The background preview of Ajustes → Apariencia (owner's request, 2026-11-18): while the
/// finger is on the "Desenfoque" or "Oscurecer" slider, the rest of Ajustes fades out and
/// the artist's photo shows behind, with the values being chosen. When the finger lifts,
/// Ajustes comes back.
///
/// The sample photo is the artist of what is playing. When nothing plays (or an episode
/// plays), it is the artist of the last track heard on Spotify (`GET
/// /me/player/recently-played`), and if that is not available (sessions without the
/// `user-read-recently-played` scope answer `403`) the last track the app saw playing.
@MainActor
final class BackgroundPreviewModel: ObservableObject {
    enum Control: Equatable {
        case blur
        case dim
    }

    /// The slider under the finger; `nil` when no preview shows.
    @Published private(set) var editing: Control?
    /// The values being chosen, shown live by the preview.
    @Published private(set) var blur = 0
    @Published private(set) var dim = Theme.defaultBackgroundDim
    /// The sample photo, once known.
    @Published private(set) var image: UIImage?

    private weak var player: PlayerModel?
    private let api: SpotifyAPI?
    private let artworkLoader: ArtworkLoader?
    /// The photo found without the player's help (nothing playing, or an episode).
    private var fallbackImage: UIImage?
    private var playerImage: UIImage?
    private var fallbackTask: Task<Void, Never>?
    private var subscription: AnyCancellable?

    /// `player` is `nil` in previews: then the preview shows the background color only.
    init(player: PlayerModel?) {
        self.player = player
        api = player?.api
        artworkLoader = player?.artworkLoader
        // With "Foto del artista" on, the player already loads the photo of what plays.
        subscription = player?.$artistImage.sink { [weak self] image in
            self?.playerImage = image
            self?.updateImage()
        }
    }

    // MARK: Sliders

    func begin(_ control: Control, blur: Int, dim: Int) {
        self.blur = blur
        self.dim = dim
        editing = control
    }

    func update(_ control: Control, to value: Int) {
        switch control {
        case .blur: blur = value
        case .dim: dim = value
        }
    }

    func end() {
        editing = nil
    }

    // MARK: Sample photo

    /// Looks for a sample photo when the sliders appear, so it is usually ready before the
    /// finger touches one. Asks Spotify at most once per opening of Ajustes.
    func prepare() {
        guard fallbackTask == nil, let api, let artworkLoader else { return }
        let seenArtistID = player?.previousTrack?.item.artistID
        fallbackTask = Task { [weak self] in
            guard let image = await Self.samplePhoto(api: api, loader: artworkLoader,
                                                     seenArtistID: seenArtistID),
                  !Task.isCancelled else { return }
            self?.fallbackImage = image
            self?.updateImage()
        }
    }

    /// What plays wins: its photo replaces the sample as soon as the player has it.
    private func updateImage() {
        image = playerImage ?? fallbackImage
    }

    /// The photo of the last track heard on Spotify, or of `seenArtistID` when Spotify can't
    /// say (`403` without the scope, empty history, an error). `nil` when there is none.
    static func samplePhoto(api: SpotifyAPI, loader: ArtworkLoader,
                            seenArtistID: String?) async -> UIImage? {
        let recentArtistID = try? await api.recentlyPlayedTracks(limit: 1)
            .lazy.compactMap { NowPlaying(item: $0)?.artistID }.first
        guard let artistID = recentArtistID ?? seenArtistID,
              let images = try? await api.artistImages(id: artistID),
              let url = NowPlaying.bestImage(images)
        else { return nil }
        return try? await loader.loadImage(url)
    }
}

// MARK: - Environment

private struct BackgroundPreviewKey: EnvironmentKey {
    static let defaultValue: BackgroundPreviewModel? = nil
}

private struct BackgroundPreviewEditingKey: EnvironmentKey {
    static let defaultValue: BackgroundPreviewModel.Control? = nil
}

extension EnvironmentValues {
    /// Set by `SettingsView`. Optional, so the settings views also work without it
    /// (previews): then the sliders just don't preview.
    var backgroundPreview: BackgroundPreviewModel? {
        get { self[BackgroundPreviewKey.self] }
        set { self[BackgroundPreviewKey.self] = newValue }
    }

    /// The slider being previewed, as a plain value so views fade without observing the model.
    var backgroundPreviewEditing: BackgroundPreviewModel.Control? {
        get { self[BackgroundPreviewEditingKey.self] }
        set { self[BackgroundPreviewEditingKey.self] = newValue }
    }
}

/// Fades a part of Ajustes out while the background preview shows. `keeps` is the slider
/// that stays visible (the one under the finger).
private struct BackgroundPreviewFade: ViewModifier {
    var keeps: BackgroundPreviewModel.Control?
    @Environment(\.backgroundPreviewEditing) private var editing

    func body(content: Content) -> some View {
        let isHidden = editing != nil && editing != keeps
        content
            .opacity(isHidden ? 0 : 1)
            .animation(Motion.backgroundPreview, value: isHidden)
    }
}

extension View {
    /// Hides this part of Ajustes while the finger is on a background slider, except the
    /// slider named by `keeps`.
    func fadesDuringBackgroundPreview(keeps: BackgroundPreviewModel.Control? = nil) -> some View {
        modifier(BackgroundPreviewFade(keeps: keeps))
    }
}

extension Motion {
    /// Ajustes fading out and back around the background preview.
    static let backgroundPreview = Animation.easeInOut(duration: 0.25)
}
