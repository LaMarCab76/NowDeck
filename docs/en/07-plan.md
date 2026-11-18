# 07 · Milestone plan

> English translation of [`docs/07-plan.md`](../07-plan.md). The Spanish version is the source of truth; if they differ, it wins.

Each milestone ends with an error-free build, green tests, and a short demo in the simulator.
Work on one branch per milestone and stop at the end of each one so the owner can review.

## Milestone 0 · Base project

- XcodeGen `project.yml`:
  - `Nowdeck` target with iOS 16.0 and `NowdeckTests` target;
  - configurable Bundle ID (`com.lamarcab76.nowdeck` by default);
  - `nowdeck` URL scheme;
  - exported `UTType` for `.nowdeck.json`.
- Folder structure from `AGENTS.md`, `.gitignore` (including `*.xcodeproj`), initial
  `README.md`, and an empty `LICENSE` for the owner to choose.
- `DesignSystem`: colors (from `ThemeStore` with the default theme), typography, spacing,
  and radii.
- Per-screen orientation and `isIdleTimerDisabled` in the foreground.

**Done when**: `xcodegen generate` and the build work, and the app shows an empty screen
in landscape with a black background.

## Milestone 1 · First launch and authentication

- The three portrait screens, with Copy and Paste working and format validation of the
  Client ID (32 alphanumeric characters).
- PKCE + `ASWebAuthenticationSession` + token exchange and refresh, stored in the
  Keychain.
- Handling of `invalid_grant` and of a user outside the allowlist (`403`).

**Tests**: PKCE generation, building the authorization URL, `state` validation, concurrent
refresh (a single request), and Keychain with a *mock*.

**Done when**: a real user completes the flow and the app stores the tokens.

## Milestone 2 · Read-only player

- `SpotifyAPI` client (async, with handling of 401, 429, and 5xx), Codable models, and adaptive
  polling.
- Player screen with real data: artwork, title, artist, source,
  "Playing on" (*Reproduciendo en*), and interpolated progress.
- Background from the artwork (`ArtworkColor`) and the "Nothing playing" (*Nada sonando*) screen.

**Tests**: decoding of saved real responses, progress interpolation, and
color extraction with test images.

## Milestone 3 · Controls

- Play/pause, previous, next, shuffle, and repeat, with optimistic updates and a
  follow-up fetch.
- Respect `actions.disallows`.
- Floating volume panel with its animations, tap coalescing, and detection of external
  changes.

## Milestone 4 · Devices

- Sheet with the list, playback transfer, help view, and "Refresh list" (*Actualizar lista*).
- Entry points from the Player, lyrics mode, and the mini player.

## Milestone 5 · Library and Search

- Tabs, filters, and rows of cards (playlists first; albums, podcasts, and audiobooks
  depending on what the API **[VERIFY]** confirms).
- Mini player with the artwork color. Tapping a card plays it.
- Search with the 10-result limit. The results screen isn't designed: propose
  one that follows the existing visual language and **show it before implementing it**.

## Milestone 6 · Lyrics

- LRCLIB client with User-Agent and cache.
- LRC and Lyricsfile (Yams) parsers.
- Lyrics mode: word by word or by verse, configurable width, and "no lyrics" notice.

**Tests**: LRC parser (multiple timestamps, offset, verses), Lyricsfile parser with a real example
from the documentation, and calculation of the current and next verse.

## Milestone 7 · Settings and themes

- Settings → Appearance and Player, with all their options saved.
- `ThemeStore`, preset themes (the ones in `themes/`), Export with `ShareLink`, and Import
  from a file, `onOpenURL`, or the clipboard, with the validation sheet.

**Tests**: validation against all the cases in `docs/en/05-themes.md`, contrast calculation, and
automatic correction.

## Milestone 8 · Finishing touches

- Adaptation to 736×414 (8 Plus).
- VoiceOver: labels on every icon button, and announcements for the notice and the volume
  panel.
- Go through the `docs/en/06-compliance.md` checklist item by item.
- Complete README:
  - how to create the app in Spotify;
  - requirements;
  - gray areas;
  - credits to LRCLIB.
