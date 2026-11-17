import Foundation

/// A Spotify URI such as `spotify:playlist:37i9dQZF1DXcBWIGoYBM5M`.
struct SpotifyURI: Equatable, Sendable {
    /// `playlist`, `album`, `artist`, `show`, `track`, `episode`…
    let kind: String
    let id: String

    init?(_ string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        // `spotify:<kind>:<id>`. Other shapes (`spotify:user:<id>:collection`, local files)
        // are not resources with a public page.
        guard parts.count == 3, parts[0] == "spotify", !parts[1].isEmpty, !parts[2].isEmpty,
              parts[2].allSatisfy({ $0.isLetter || $0.isNumber })
        else { return nil }
        kind = String(parts[1])
        id = String(parts[2])
    }

    /// The `open.spotify.com` page, which opens the Spotify app when it is installed.
    var webURL: URL? {
        URL(string: "https://open.spotify.com/\(kind)/\(id)")
    }
}
