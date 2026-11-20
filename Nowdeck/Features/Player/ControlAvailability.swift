import Foundation

/// Which player controls can be used right now, from `actions` and the device.
///
/// Spotify's design guidelines: "Play controls must either have a disabled state to indicate
/// that they are restricted or they should not be displayed at all". Nowdeck disables them
/// (the layout stays the same).
///
/// - Only `actions.disallows` is interpreted (`true` = not allowed, missing = allowed). The
///   flat booleans that the current reference lists have no documented meaning, so they never
///   disable anything (docs/03-spotify-api.md, "`actions`").
/// - A device with `is_restricted` "will not accept Web API commands": everything is disabled.
struct ControlAvailability: Equatable {
    var playPause = false
    var previous = false
    var next = false
    var shuffle = false
    var repeatMode = false
    /// The ±15 s buttons of podcast episodes.
    var seek = false

    /// Nothing enabled (no playback, restricted device).
    static let none = ControlAvailability()

    init() {}

    init(playback: PlaybackState?) {
        guard let playback, playback.device?.isRestricted != true else { return }
        let actions = playback.actions
        playPause = !actions.isDisallowed(playback.isPlaying ? .pausing : .resuming)
        previous = !actions.isDisallowed(.skippingPrev)
        next = !actions.isDisallowed(.skippingNext)
        shuffle = !actions.isDisallowed(.togglingShuffle)
        repeatMode = Self.nextRepeatMode(after: playback.repeatState, actions: actions) != nil
        seek = !actions.isDisallowed(.seeking)
    }

    /// The mode the repeat button switches to: off → context → track → off, skipping the
    /// modes that `actions` forbids. `nil` when no other mode is allowed.
    ///
    /// Spotify has two flags: `toggling_repeat_context` (turning context repeat on or off) and
    /// `toggling_repeat_track` (turning track repeat on or off).
    static func nextRepeatMode(after current: RepeatMode, actions: PlaybackActions) -> RepeatMode? {
        let cycle: [RepeatMode] = [.off, .context, .track]
        let start = cycle.firstIndex(of: current) ?? 0
        for step in 1..<cycle.count {
            let candidate = cycle[(start + step) % cycle.count]
            if canSwitch(from: current, to: candidate, actions: actions) { return candidate }
        }
        return nil
    }

    private static func canSwitch(from current: RepeatMode, to target: RepeatMode,
                                  actions: PlaybackActions) -> Bool {
        switch target {
        case .context:
            return !actions.isDisallowed(.togglingRepeatContext)
        case .track:
            return !actions.isDisallowed(.togglingRepeatTrack)
        case .off:
            return !actions.isDisallowed(current == .track ? .togglingRepeatTrack
                                                           : .togglingRepeatContext)
        }
    }
}

/// How the theme's optional controls (`reproductor.controles`) are placed around the center
/// group (previous · play/pause · next).
///
/// The theme gives an ordered list; it is read left to right across the bar. The first half
/// (rounded up) goes to the left group and the rest to the right group. With the default
/// order that gives the mockup's layout: Aleatorio · Repetir on the left, Letras · Volumen on
/// the right. Without lyrics (the default when "Mostrar letras" is off) Volumen stays alone on
/// the right.
struct PlayerControlLayout: Equatable {
    var leading: [Theme.PlayerControl]
    var trailing: [Theme.PlayerControl]

    init(controls: [Theme.PlayerControl]) {
        // A theme could repeat a control: show it once, where it first appears.
        var seen = Set<Theme.PlayerControl>()
        let unique = controls.filter { seen.insert($0).inserted }
        let leadingCount = (unique.count + 1) / 2
        leading = Array(unique.prefix(leadingCount))
        trailing = Array(unique.dropFirst(leadingCount))
    }

    /// The gap between buttons for a row `width` wide, with Agregar a una playlist at the
    /// left end of the left group (owner's request, 2026-11-18).
    ///
    /// Play/pause stays in the exact center, so both groups take the same width and the left
    /// one, which also holds the add button, decides: `2 × left + center + 4 gaps ≤ width`.
    /// The design's 36 pt where it fits (the 800 pt of the 11 Pro Max); less on narrower
    /// screens: with the default controls the 640 pt of the iPhone 8 Plus give 22 pt. Never
    /// below `minimumGap`.
    func gap(forWidth width: CGFloat,
             preferred: CGFloat = Metrics.Player.controlsGap,
             minimumGap: CGFloat = Metrics.Player.controlsMinimumGap,
             buttonSize: CGFloat = Metrics.Player.sideButtonSize,
             centerWidth: CGFloat = Metrics.Player.centerGroupWidth) -> CGFloat {
        let leftButtons = CGFloat(leading.count + 1)
        let leftGaps = CGFloat(leading.count)
        // 2 × (leftButtons × size + leftGaps × gap) + center + 4 × gap ≤ width
        let room = width - centerWidth - 2 * leftButtons * buttonSize
        let fitting = (room / (2 * leftGaps + 4)).rounded(.down)
        return max(minimumGap, min(preferred, fitting))
    }

    /// Where the volume bar opens in a row `width` wide with `gap` between buttons
    /// (owner's request, 2026-11-18; mockup `VolumenLateral.html`).
    ///
    /// The row is the HStack of `PlayerControls`: the left frame and the right frame take
    /// `side` each, and four gaps separate them from previous · play/pause · next. While the
    /// bar is open the whole row moves left until previous sits on the left edge, and the
    /// bar fills the room from the speaker's right edge to the end of the row.
    func volumeExpansion(forWidth width: CGFloat, gap: CGFloat,
                         buttonSize: CGFloat = Metrics.Player.sideButtonSize,
                         centerWidth: CGFloat = Metrics.Player.centerGroupWidth) -> VolumeExpansion {
        let side = (width - centerWidth - 4 * gap) / 2
        let shift = side + gap
        let trailingStart = side + centerWidth + 4 * gap
        // Volume on the left (or not in the theme): a speaker of its own comes in with the
        // bar, after the right group.
        let volumeIndex = trailing.firstIndex(of: .volume)
        let slot = volumeIndex ?? trailing.count
        let speakerX = trailingStart + CGFloat(slot) * (buttonSize + gap)
        let barArea = width - (speakerX - shift) - buttonSize
        return VolumeExpansion(shift: shift, speakerX: speakerX, barAreaWidth: max(0, barArea),
                               usesRowSpeaker: volumeIndex != nil, keptTrailingCount: slot)
    }
}

/// The volume bar inside the controls row (`PlayerControlLayout.volumeExpansion`).
struct VolumeExpansion: Equatable {
    /// How far the row moves left while the bar is open.
    var shift: CGFloat
    /// The speaker's x in the closed row. The bar opens from its right edge, and closes
    /// back into it.
    var speakerX: CGFloat
    /// From the speaker's right edge to the end of the row, once the row has moved.
    var barAreaWidth: CGFloat
    /// The theme's volume button is in the right group, so the bar comes out of it. When
    /// `false`, a speaker comes in with the bar at `speakerX`.
    var usesRowSpeaker: Bool
    /// Right-group controls before the speaker. They stay; the ones after it would sit
    /// under the bar, so they fade out with the left group.
    var keptTrailingCount: Int
}
