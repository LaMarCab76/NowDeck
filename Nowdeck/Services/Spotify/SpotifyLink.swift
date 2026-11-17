import UIKit

/// Links back to Spotify (docs/06-cumplimiento.md, "Enlace de vuelta").
///
/// `open.spotify.com` links are universal links: with `universalLinksOnly` iOS opens them
/// only if the Spotify app is installed, and reports failure otherwise. In that case we send
/// the user to Spotify's App Store page, as the compliance checklist asks. This needs no
/// `LSApplicationQueriesSchemes` entry.
@MainActor
enum SpotifyLink {
    static let home = URL(string: "https://open.spotify.com")!
    /// Spotify on the App Store.
    static let appStore = URL(string: "https://apps.apple.com/app/id324684580")!

    static func open(_ url: URL?) {
        let target = sanitized(url)
        UIApplication.shared.open(target, options: [.universalLinksOnly: true]) { opened in
            if !opened {
                UIApplication.shared.open(appStore)
            }
        }
    }

    /// Only `https://open.spotify.com/...` is opened. URLs come from API answers; anything
    /// else falls back to Spotify's home page.
    static func sanitized(_ url: URL?) -> URL {
        guard let url, url.scheme == "https", url.host == "open.spotify.com" else { return home }
        return url
    }
}
