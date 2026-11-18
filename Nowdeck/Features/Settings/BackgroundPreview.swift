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

        var artistURL: URL? { SpotifyURI("spotify:artist:\(artistID)")?.webURL }
    }

    private weak var player: PlayerModel?
    private let api: SpotifyAPI?
    private let artworkLoader: ArtworkLoader?
    /// The photo found without the player's help: Spotify's history, or the last track the
    /// app saw.
    private var fallbackSample: Sample?
    /// The player's photos during this visit, by artist. Only two are kept: the one on
    /// screen and the one of the last artist heard (they are the same while a track plays).
    private var playerSamples: [String: Sample] = [:]
    private var fallbackTask: Task<Void, Never>?
    /// The last heard artist when the latest lookup started. Automatic lookups (a playback
    /// change during a drag) only start for a different one, so polls that change nothing
    /// never send a request.
    private var lookupArtistID: String?
    /// The last heard artist at the previous player change, to notice when it changes (also
    /// back to an artist an earlier lookup already tried).
    private var observedHeardArtistID: String?
    private var subscription: AnyCancellable?

    /// `player` is `nil` in previews: then the preview shows the background color only.
    init(player: PlayerModel?) {
        self.player = player
        api = player?.api
        artworkLoader = player?.artworkLoader
        observedHeardArtistID = player?.lastHeardArtistID
        // With "Foto del artista" on, the player already loads the photo of what plays. A
        // new photo and a playback change (pause, resume, stop) both can change the choice.
        // `@Published` sends before the value is stored, and `PlayerModel` updates the last
        // heard artist after `playback`, so the choice is made on the next main-queue turn,
        // when the player is consistent again.
        if let player {
            subscription = player.$artistImage.map { _ in () }
                .merge(with: player.$playback.map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.playerDidChange() }
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
    /// finger touches one. Only when there is no sample yet: a lookup that found none is
    /// tried again when the sliders appear again (another tab and back) or on the next touch
    /// of a slider, so a temporary failure (a `429` cooldown) does not last the whole visit.
    func prepare() {
        guard fallbackTask == nil, selectedSample == nil,
              let api, let artworkLoader else { return }
        lookupArtistID = player?.lastHeardArtistID
        fallbackTask = Task { [weak self, weak player] in
            let lookup = await Self.samplePhoto(api: api, loader: artworkLoader,
                                                seenArtistID: { await player?.lastHeardArtistID })
            guard let self else { return }
            // Also when cancelled, so a later `prepare()` can start again.
            self.fallbackTask = nil
            guard !Task.isCancelled else { return }
            // The artist this lookup really accounted for, even if it found no photo.
            self.lookupArtistID = lookup.heardArtistID
            // A result for an artist that is no longer the last heard would only replace a
            // photo that may still serve.
            if let sample = lookup.sample, self.serves(sample) {
                self.fallbackSample = sample
                self.updateImage()
            }
            // Another artist started while this lookup ran and still has no photo.
            self.lookUpIfArtistChanged()
        }
    }

    /// During a drag, a lookup for a new last heard artist that has no photo yet. Nothing for
    /// the artist the latest lookup was already for: that one gets another try on the next
    /// touch or when the sliders appear again.
    private func lookUpIfArtistChanged() {
        guard editing != nil, selectedSample == nil,
              player?.lastHeardArtistID != lookupArtistID else { return }
        prepare()
    }

    /// A lookup for the sample photo is running.
    var isLookingUp: Bool { fallbackTask != nil }

    /// Ajustes closed: stop looking, so no request of ours shares the player's rate limit
    /// for nothing.
    func cancel() {
        fallbackTask?.cancel()
    }

    private func playerDidChange() {
        guard let player else { return }
        if let image = player.artistImage, let artistID = player.artistImageArtistID {
            playerSamples[artistID] = Sample(image: image, artistID: artistID)
        }
        let kept = Set([player.artistImageArtistID, player.lastHeardArtistID].compactMap { $0 })
        playerSamples = playerSamples.filter { kept.contains($0.key) }
        updateImage()
        // Another artist started under the finger and its photo is not here yet: look for one
        // now instead of waiting for the next touch. If a lookup is running, its end checks
        // again. Polls that keep the same artist do nothing.
        let heard = player.lastHeardArtistID
        guard heard != observedHeardArtistID else { return }
        observedHeardArtistID = heard
        if editing != nil, selectedSample == nil { prepare() }
    }

    /// The sample, for the last artist heard (a track picked while paused was not heard):
    /// 1. the player's photo of that artist, the newest thing the app knows;
    /// 2. else the lookup's photo (Spotify's history, or the last track the app saw), if it
    ///    still serves.
    private var selectedSample: Sample? {
        let lastHeard = player?.lastHeardArtistID
        if let lastHeard, let sample = playerSamples[lastHeard] { return sample }
        guard let fallbackSample, serves(fallbackSample) else { return nil }
        return fallbackSample
    }

    /// A lookup's photo serves while it is of the last artist heard, or while the app has not
    /// heard anything yet (then Spotify's history is all there is). The last heard artist
    /// never goes back to `nil`, so once something plays only that artist's photo serves.
    private func serves(_ sample: Sample) -> Bool {
        guard let lastHeard = player?.lastHeardArtistID else { return true }
        return sample.artistID == lastHeard
    }

    /// Publishes only real changes, so the preview does not redraw on every poll.
    private func updateImage() {
        let sample = selectedSample
        if image !== sample?.image { image = sample?.image }
        if artistURL != sample?.artistURL { artistURL = sample?.artistURL }
    }

    /// What a lookup found, and the last heard artist it accounted for.
    struct Lookup {
        var sample: Sample?
        var heardArtistID: String?
    }

    /// The photo of the last track heard on Spotify, or of `seenArtistID` when Spotify can't
    /// say (`403` without the scope, empty history, an error), its artist has no photo, or
    /// it is not the artist the app heard last (Spotify's history may lag behind). Every
    /// photo found is of the last artist heard, or of history while the app heard nothing.
    static func samplePhoto(api: SpotifyAPI, loader: ArtworkLoader,
                            seenArtistID: () async -> String?) async -> Lookup {
        let heardAtStart = await seenArtistID()
        let recentArtistID = try? await api.recentlyPlayedTracks(limit: 1)
            .lazy.compactMap { NowPlaying(item: $0)?.artistID }.first
        var triedArtistID: String?
        if let recentArtistID, heardAtStart == nil || recentArtistID == heardAtStart {
            triedArtistID = recentArtistID
            if let sample = await photo(of: recentArtistID, api: api, loader: loader) {
                return Lookup(sample: sample, heardArtistID: heardAtStart)
            }
        }
        // Skipped only if that artist's photo was just asked for and there was none.
        let localArtistID = await seenArtistID()
        guard !Task.isCancelled, let localArtistID, localArtistID != triedArtistID else {
            return Lookup(sample: nil, heardArtistID: localArtistID)
        }
        let sample = await photo(of: localArtistID, api: api, loader: loader)
        return Lookup(sample: sample, heardArtistID: localArtistID)
    }

    /// The widest photo of an artist (`GET /artists/{id}`), loaded. `nil` if there is none,
    /// on any error, or once cancelled.
    private static func photo(of artistID: String, api: SpotifyAPI,
                              loader: ArtworkLoader) async -> Sample? {
        guard !Task.isCancelled,
              let images = try? await api.artistImages(id: artistID),
              !Task.isCancelled, let url = NowPlaying.bestImage(images),
              let image = try? await loader.loadImage(url)
        else { return nil }
        return Sample(image: image, artistID: artistID)
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
