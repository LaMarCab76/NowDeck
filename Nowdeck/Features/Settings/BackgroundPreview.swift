import Combine
import SwiftUI

/// The background preview of Ajustes → Apariencia (owner's request, 2026-11-18): while the
/// finger is on the "Desenfoque" or "Oscurecer" slider, the rest of Ajustes fades out and
/// the artist's photo shows behind, with the values being chosen. When the finger lifts,
/// Ajustes comes back.
///
/// The sample photo is the artist of what is playing. When nothing plays (or an episode
/// plays), it is the newest photo the player showed while Ajustes was open, or else the
/// artist of the last track heard on Spotify (`GET /me/player/recently-played`), and if that
/// is not available (sessions without the `user-read-recently-played` scope answer `403`)
/// the last track the app saw playing.
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
    /// The page of the artist in `image`, for the Spotify icon shown with it (docs/06: the
    /// link goes to the content shown). `nil` opens Spotify's home page.
    @Published private(set) var artistURL: URL?

    /// A photo and the artist it belongs to.
    struct Sample {
        var image: UIImage
        var artistID: String
        /// Found through the last track the app saw, not Spotify's history.
        var isLocal = false

        var artistURL: URL? { SpotifyURI("spotify:artist:\(artistID)")?.webURL }
    }

    private weak var player: PlayerModel?
    private let api: SpotifyAPI?
    private let artworkLoader: ArtworkLoader?
    /// The photo found without the player's help (nothing playing, or an episode).
    private var fallbackSample: Sample?
    private var playerSample: Sample?
    /// Every photo the player showed during this visit, by artist. When playback stops, the
    /// one of the last artist heard is the sample: it is newer than anything the history
    /// lookup can find. A photo of a track picked while paused is kept too, but not used
    /// unless that track then played.
    private var playerSamples: [String: Sample] = [:]

    /// The player's photo of the last artist heard, if it showed one during this visit.
    private var retainedSample: Sample? {
        player?.lastHeardArtistID.flatMap { playerSamples[$0] }
    }
    private var fallbackTask: Task<Void, Never>?
    private var subscription: AnyCancellable?

    /// `player` is `nil` in previews: then the preview shows the background color only.
    init(player: PlayerModel?) {
        self.player = player
        api = player?.api
        artworkLoader = player?.artworkLoader
        // With "Foto del artista" on, the player already loads the photo of what plays.
        // `artistImageArtistID` is set before each photo is published, so it matches `image`.
        subscription = player?.$artistImage.sink { [weak self, weak player] image in
            let artistID = player?.artistImageArtistID
            var sample: Sample?
            if let image, let artistID { sample = Sample(image: image, artistID: artistID) }
            self?.playerSample = sample
            if let sample { self?.playerSamples[sample.artistID] = sample }
            self?.updateImage()
        }
    }

    // MARK: Sliders

    func begin(_ control: Control, blur: Int, dim: Int) {
        // A lookup that found nothing (an error, a `429`) tries again with each new touch.
        prepare()
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
    /// finger touches one, also while something plays (its artist may have no photo, or
    /// playback may stop before the finger arrives). Once a photo is found it is not looked
    /// up again while Ajustes is open; a lookup that found none is tried again when the
    /// sliders appear again (another tab and back) or on the next touch of a slider, so a
    /// temporary failure (a `429` cooldown) does not last the whole visit. Not needed once the
    /// player showed a photo: that one wins for the rest of the visit.
    func prepare() {
        guard fallbackTask == nil, fallbackSample == nil, retainedSample == nil,
              let api, let artworkLoader else { return }
        fallbackTask = Task { [weak self, weak player] in
            let sample = await Self.samplePhoto(api: api, loader: artworkLoader,
                                                seenArtistID: { await player?.lastHeardArtistID })
            guard let self else { return }
            // Also when cancelled, so a later `prepare()` can start again.
            self.fallbackTask = nil
            guard !Task.isCancelled, let sample else { return }
            // Another track played while the photo loaded: this one is no longer the last
            // the app saw. Dropped, so the next `prepare()` looks up the new one.
            if sample.isLocal, sample.artistID != player?.lastHeardArtistID { return }
            self.fallbackSample = sample
            self.updateImage()
        }
    }

    /// A lookup for the sample photo is running.
    var isLookingUp: Bool { fallbackTask != nil }

    /// Ajustes closed: stop looking, so no request of ours shares the player's rate limit
    /// for nothing.
    func cancel() {
        fallbackTask?.cancel()
    }

    /// What plays wins: its photo replaces the sample as soon as the player has it, and stays
    /// when playback stops.
    private func updateImage() {
        let sample = playerSample ?? retainedSample ?? fallbackSample
        image = sample?.image
        artistURL = sample?.artistURL
    }

    /// The photo of the last track heard on Spotify, or of `seenArtistID` when Spotify can't
    /// say (`403` without the scope, empty history, an error). `seenArtistID` is read only
    /// then, so it is the newest track the app saw. `nil` when there is no photo.
    static func samplePhoto(api: SpotifyAPI, loader: ArtworkLoader,
                            seenArtistID: () async -> String?) async -> Sample? {
        var artistID = try? await api.recentlyPlayedTracks(limit: 1)
            .lazy.compactMap { NowPlaying(item: $0)?.artistID }.first
        guard !Task.isCancelled else { return nil }
        let isLocal = artistID == nil
        if isLocal { artistID = await seenArtistID() }
        guard let artistID,
              let images = try? await api.artistImages(id: artistID),
              !Task.isCancelled, let url = NowPlaying.bestImage(images),
              let image = try? await loader.loadImage(url)
        else { return nil }
        return Sample(image: image, artistID: artistID, isLocal: isLocal)
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
            // Hidden controls take no touches: a second finger can't start the other slider
            // while the preview shows.
            .allowsHitTesting(!isHidden)
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
