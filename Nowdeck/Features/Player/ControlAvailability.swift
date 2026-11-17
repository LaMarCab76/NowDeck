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
}
