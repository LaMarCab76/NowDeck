# Nowdeck

**A desk controller for Spotify that runs on your iPhone.**

Leave it propped up in landscape, plugged in with the screen on, and at a glance you can see
what's playing, control it, and choose which device it plays on.

> Nowdeck is an independent open source project. It is not affiliated with or endorsed by
> Spotify.

> The app's interface is currently in **Spanish** (Rioplatense). The texts live in a String
> Catalog, so other languages can be added later.

## What it does

- Shows what's playing: artwork, track, artist, the playlist or album it comes from and the
  device it's playing on, with a background color taken from the artwork.
- Controls playback: play and pause, previous and next (or −15 s and +15 s for podcasts),
  shuffle, repeat and volume.
- Moves the music from one device to another (computers, speakers, TVs, other phones).
- Browses your library (playlists, albums, podcasts and audiobooks) and plays from there.
- Shows synced lyrics, word by word or line by line, from [LRCLIB](https://lrclib.net).
- Can be customized with themes that are exported and imported as `.nowdeck.json` files.

Nowdeck **does not play audio**: it controls your Spotify Connect devices through the
Spotify Web API. The music plays somewhere else: on the computer, speaker or phone where you
have Spotify open.

## Requirements

- An iPhone running **iOS 16 or later**. The oldest supported device is the iPhone 8 Plus.
- A **Spotify Premium** account: the Web API only accepts playback commands from Premium
  accounts, and the account that creates the developer app must be Premium too.
- **Your own developer app** in the Spotify dashboard (explained below). The app stays in
  *Development Mode*, which allows **up to 5 users** added by hand. The usual setup is for
  each person to create their own app and add themselves as its only user.
- To build: a Mac with **Xcode 27.2** (the version it was built and tested with in the
  simulator; earlier versions that can build for iOS 16 should work) and
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) (tested with 2.46.0).

## Create your Spotify app

Nowdeck walks you through this the first time you open it, but these are the steps:

1. Go to [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) with your
   Premium account and accept the developer terms if asked.
2. Tap **Create app**. Use any name and description you like (without "Spotify" in the name).
3. Under **Redirect URIs**, paste exactly:

   ```
   nowdeck://callback
   ```

4. Where it asks which API you'll use, check **Web API** and save.
5. Open **Settings** and copy the **Client ID**. You don't need the *Client secret*: Nowdeck
   uses Authorization Code with PKCE, which doesn't require it.
6. If someone else is going to use your app, add them under **User Management** with the
   email of their Spotify account (up to 5). If it's only you, there's nothing to do.

In Nowdeck, paste the Client ID, tap **Conectar con Spotify** (*Connect with Spotify*) and
sign in. Nowdeck only asks for these scopes:

| Scope | What for |
|---|---|
| `user-read-playback-state` | See what's playing and on which devices |
| `user-modify-playback-state` | Play, pause, skip, volume, shuffle, repeat and switching devices |
| `user-read-currently-playing` | See the current track |
| `playlist-read-private` | List your private playlists |
| `playlist-read-collaborative` | List your collaborative playlists |
| `user-library-read` | List your saved albums, podcasts and audiobooks |
| `user-read-playback-position` | Know where you are in a podcast episode |

If after connecting you see "Spotify no deja usar tu app" (*Spotify won't let you use your
app*), check that your account is listed under **User Management** and that the account that
owns the app has Premium.

## Build

```bash
brew install xcodegen                                   # if you don't have it
cp Config/Local.xcconfig.example Config/Local.xcconfig  # and fill it in (see below)
xcodegen generate                                       # generates Nowdeck.xcodeproj
open Nowdeck.xcodeproj
```

The Xcode project is generated from `project.yml` and is not checked in.

`Config/Local.xcconfig` is not committed to the repository. Your signing details go there:

```
DEVELOPMENT_TEAM = ABCDE12345              // your Apple Team ID
NOWDECK_BUNDLE_ID = com.yourname.nowdeck   // optional: your own Bundle ID
```

To run on your iPhone you need a Team ID (a free Apple Developer account is enough) and, if
the account is free, your own Bundle ID. For the simulator, `xcodegen generate` and picking an
iPhone is enough.

Tests (they never connect to Spotify or LRCLIB: everything goes through stubbed responses):

```bash
xcodebuild -scheme Nowdeck -destination 'platform=iOS Simulator,name=<simulator>' test
```

## Gray areas and limitations

Things Nowdeck can't do, or that are worth knowing, because of how the Spotify Web API works
in 2026 and because of Spotify's rules:

- **Each user uses their own Client ID.** Since 2026, an app in *Development Mode* allows up
  to 5 users, and *Extended Quota Mode* is only granted to companies with 250,000 monthly
  active users. Spotify neither forbids nor endorses in writing that each user creates their
  own app; it's the only practical way to distribute an open app.
- **Limited quota.** Each developer app has a request quota. If it's exceeded, Spotify replies
  "wait" and Nowdeck polls less often for a while ("SPOTIFY PIDE ESPERAR" — *Spotify asks to
  wait* — is shown).
- **No push updates.** The API doesn't notify changes: Nowdeck checks the state every 3 s
  while playing (10 s when paused), so a change made on another device may take a few seconds
  to show up.
- **Expired Premium.** If the Premium subscription of the account that owns the app expires,
  the app stops working for all of its users.
- **Reconnect every 6 months.** The access Spotify grants lasts 6 months from when you
  connect; after that Nowdeck asks you to connect again.
- **What the API doesn't offer**: the playback queue, Spotify's editorial and algorithmic
  playlists (only "Desde una playlist" — *From a playlist* — is shown), and playing podcasts or
  audiobooks from the library (those cards open Spotify). Search in *Development Mode* returns
  at most 10 results per type; the results screen isn't built yet.
- **Devices that don't show up.** In practice, the Spotify Connect list only shows devices
  that have Spotify open or awake. Some models don't support remote control and appear
  dimmed.
- **Lyrics from a community database.** Spotify doesn't offer lyrics in its API. Nowdeck gets
  them from [LRCLIB](https://lrclib.net), an open database filled in by its users: lyrics may
  be missing or contain mistakes, and their rights belong to their authors and publishers.
  Also, Spotify's policy forbids integrating content from another service with its own, and
  showing third-party lyrics next to playback has no clear precedent. That's why lyrics can be
  turned off in **Ajustes → Reproductor → Mostrar letras** (*Settings → Player → Show
  lyrics*), and the Settings screen explains where they come from. Nowdeck never uses
  Spotify's internal access to its lyrics.
- **It's not a player.** It doesn't play anything on the iPhone; that's what the Spotify app is
  for.

## Privacy

- **No server of its own and no analytics.** Nowdeck only talks to Spotify (to control
  playback) and to LRCLIB (for lyrics, and only if they're turned on). It sends LRCLIB the
  track's title, artist, album and duration.
- **Your credentials stay on the iPhone**, in the Keychain: the Client ID and the access
  tokens. There is no Client Secret. None of it is stored anywhere else or sent to any other
  service.
- Imported themes are data only: colors and options. They never run or load anything from the
  internet.

## Documentation

The project documentation is written in Spanish.

| Document | Contents |
|---|---|
| [`docs/01-producto.md`](docs/01-producto.md) | Scope, screens and flows |
| [`docs/02-diseno.md`](docs/02-diseno.md) | Design tokens and measurements |
| [`docs/03-spotify-api.md`](docs/03-spotify-api.md) | Authentication, endpoints and errors |
| [`docs/04-letras.md`](docs/04-letras.md) | Lyrics with LRCLIB |
| [`docs/05-temas.md`](docs/05-temas.md) | Theme format |
| [`docs/06-cumplimiento.md`](docs/06-cumplimiento.md) | Spotify's rules and compliance review |
| [`docs/07-plan.md`](docs/07-plan.md) | Milestone plan |

## Credits

- [LRCLIB](https://lrclib.net): an open, community-driven database of synced lyrics, the
  source of every lyric Nowdeck shows. Thanks to its author and to everyone who contributes
  lyrics.
- [Yams](https://github.com/jpsim/Yams) (MIT license): reads LRCLIB's Lyricsfile format
  (YAML). It's the project's only dependency.
- Spotify and its logo are trademarks of Spotify AB. Nowdeck uses the Spotify Web API and is
  not affiliated with Spotify.

## Contributing

The code lives at [github.com/LaMarCab76/NowDeck](https://github.com/LaMarCab76/NowDeck).
Issues and pull requests are welcome.

## License

Pending: the project owner will choose it, and it will be added to the `LICENSE` file.
