# 01 · Product

> English translation of [`docs/01-producto.md`](../01-producto.md). The Spanish version is the source of truth; if they differ, it wins.

## What it is

Nowdeck is a desk controller for Spotify that runs on an iPhone, meant to be left standing in
landscape, plugged in, with the screen always on. You can see at a glance what's playing, control
it, and choose which device it plays on. **It does not play audio**: everything goes through the
Spotify Web API to the Spotify Connect devices on the user's account (computer, speakers, TVs,
other phones).

- **User requirements**: Spotify **Premium** (the API's playback commands require it) and their
  **own developer app** in the Spotify dashboard.
- **Distribution model**: open source. Each user creates their app at
  developer.spotify.com, copies the **Client ID**, and pastes it into Nowdeck the first time.
  - Reason: since 2026, an app in *Development Mode* allows up to 5 users, and
    *Extended Quota Mode* is only granted to companies with 250,000 monthly active users.
  - With one Client ID per user, each one gets their own quota.
- **Name**: "Nowdeck". On the App Store or in the README it may carry "for Spotify" as a
  subtitle, never "Spotify" in the name.

## Orientation

| Screen | Orientation |
|---|---|
| First launch (3 steps) | Portrait, 414×896 reference |
| Everything else | Landscape, 896×414 reference (adapt to 736×414) |

Lock the orientation per screen: `supportedInterfaceOrientations` from the AppDelegate plus
`UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))`, available since iOS 16.

While the app is in the foreground, **the screen does not turn off**
(`UIApplication.shared.isIdleTimerDisabled = true`).

## Screens

1. **First launch**
   1. **Welcome**: what it is, what you need, and the notice that it isn't affiliated with Spotify.
   2. **Create the app**: the 5 steps in the Spotify dashboard and the Redirect URI
      `nowdeck://callback` with a "Copy" (*Copiar*) button.
   3. **Client ID**: a field to paste it, the permissions that will be requested, and
      "Connect to Spotify" (*Conectar con Spotify*).
2. **Player**: the main screen.
   - Top: artwork on the left and, on the right, the Spotify logo + "Playing from / X"
     (*Reproduciendo desde*), Library, Settings, title, artist, and "Playing on <device>"
     (*Reproduciendo en %@*).
   - Bottom, full width: progress bar (informational, no dragging) and controls.
   - Background: a soft color taken from the artwork.
3. **Lyrics mode**, inside the Player, turned on with the lyrics button.
   - Top row: "Playing from / Name" on two lines on the left and the logo on the
     right.
   - Center: current verse and next verse, at the configured width (2/3 by default).
   - Bottom row: small artwork, title, artist, and device.
   - Library and Settings are hidden while it's active.
4. **Volume bar**: it opens sideways from the volume button, inside the controls row, which
   moves to make room for it. It opens when the button is tapped or when the volume changes
   (also if it changes from another device). It closes after 3 s.
5. **"No lyrics found for this song" notice** (*No encontramos la letra de este tema*): it
   appears at the top for 3 s and the player goes back to the normal view.
6. **Library**
   - Library and Search tabs.
   - Playlists, Albums (*Álbumes*), Podcasts, and Audiobooks (*Audiolibros*) filters.
   - Horizontal row of cards. Tapping a playlist or an album opens its **detail**; podcasts
     and audiobooks open in Spotify.
   - **Playlist or album detail**: artwork, name, owner or artists, the **Play** (*Reproducir*)
     button (starts from the beginning), and the list of songs. Songs can't be tapped to
     play. For other people's playlists Spotify doesn't return the songs: the user is told,
     and can still play it or view it in Spotify.
   - Mini player at the bottom, with a background in the artwork's color and "Playing on
     <device>" (*Suena en*).
7. **Search**: search field; tapping a result plays it on the active device. The
   results screen isn't designed yet (see pending items).
8. **Devices**
   - Bottom sheet with the current device highlighted and the list of the rest.
   - "Don't see your device?" (*¿No ves tu dispositivo?*) button, which opens a 3-step help
     and "Refresh list" (*Actualizar lista*).
9. **Queue** (added on 2026-11-17, at the owner's request)
   - Queue pill in the player's top row, to the left of Library.
   - Bottom sheet with what's playing now and up to 20 songs under "UP NEXT" (*A CONTINUACIÓN*).
   - **Read-only**: the Web API doesn't allow removing, reordering, or skipping to a song in
     the queue. Songs can't be tapped; long-pressing them shows the full name and "Open in
     Spotify" (*Abrir en Spotify*). The list ends with "To remove or reorder songs, use
     Spotify." (*Para quitar o reordenar temas, usá Spotify.*) and "OPEN SPOTIFY" (*ABRIR
     SPOTIFY*).
10. **Add to a playlist** (added on 2026-11-18, at the owner's request)
   - Button at the far left of the player's controls and of the Library's mini
     player.
   - Sheet with the playlists the user can edit (their own and collaborative ones); tapping one
     adds the song or episode that's playing. What was added stays marked. Removing is done in
     Spotify.
   - It asks for a new permission (editing playlists): earlier sessions grant it from the same
     sheet with "Allow" (*Dar permiso*).
11. **Settings**
   - **Appearance**:
     - theme (Black and green, Amber, Night blue, Custom);
     - accent color (6 options);
     - player background (Black, Dark gray, or From the artwork; by default, From the
       artwork);
     - Export theme and Import theme.
   - **Player**: "Show time left" (*Mostrar tiempo restante*) switch (instead of the duration,
     to the right of the bar; off by default), "Show lyrics" (*Mostrar letras*) switch,
     "Lyrics width" (*Ancho de las letras*) (Half, 2/3, or Full; 2/3 by default), and
     "Lyrics style" (*Estilo de las letras*) (By word or Verse; By word by default).
12. **Import theme**: sheet with the JSON, the validation result, warnings, a
    preview, and the Apply and Cancel buttons.
13. **Nothing playing** (*Nada sonando*): empty state with "Choose device" (*Elegir
    dispositivo*) and "OPEN SPOTIFY" (*ABRIR SPOTIFY*).

## Key flows

- **First launch**: Welcome → Create the app → Client ID → Spotify login
  (`ASWebAuthenticationSession`) → Player, or Nothing playing if there's no active playback.
- **Expired or revoked token** (`invalid_grant` when refreshing): go back to the Client ID
  screen with the ID prefilled and a clear message.
- **Switch devices**: tap "Playing on …" → Devices sheet → tap a
  device → transfer playback → close the sheet.
- **Lyrics**: tap the lyrics button.
  - If there are lyrics with word-by-word sync and the style is "By word", that mode is used.
  - With the "Verse" style, the whole verse is shown even when there's word-by-word sync.
  - If there's line sync, the whole verse is shown.
  - If there are no lyrics or only plain text, the notice appears and the player goes back to the
    normal view.
- **Play from the Library**: tap a playlist or an album → detail with its songs →
  Play → it plays on the active device and you go back to the Player. If there's no
  active device, Devices opens. Long-pressing a card still offers
  "Play" without going through the detail.
- **Theme**: in Settings → Export, the share sheet opens with a `.nowdeck.json`.
  Importing can be done from Files, AirDrop, or by pasting the text → import sheet →
  Apply.

## Out of scope (for now)

- Playing audio on the iPhone (Spotify Connect receiver, librespot).
- Voice control: Spotify's policy forbids it.
- Editing the queue (removing, reordering, or skipping to a song): the Web API doesn't allow it.
  Adding to the queue (`POST /me/player/queue`) does exist, but it has no design yet.
- Quick access shortcuts (presets).
- Search results screen, pending design.
- OLED *burn-in* protection (dimming brightness, shifting pixels): discussed as a future
  option, undecided.
- "Light pastel" background variant, which would require inverting the text colors.

## Decisions pending from the owner

- ✅ Repository license: MIT (decided on 2026-11-18, `LICENSE` file).
- GitHub user or organization and final Bundle ID (suggested
  `com.lamarcab76.nowdeck`).
- Whether themes are edited color by color inside the app or presets and importing are enough.
