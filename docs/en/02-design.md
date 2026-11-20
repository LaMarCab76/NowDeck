# 02 · Design

> English translation of [`docs/02-diseno.md`](../02-diseno.md). The Spanish version is the source of truth; if they differ, it wins.

The source of truth is the mockups in `design/mockups/*.dc.html`: the exact values are in the
`style="…"` attributes of each file. This document summarizes them. Measurements are in
**points (pt)** on the reference canvas of **896×414** (landscape) or **414×896** (first launch).

## Tokens

### Colors (default theme "Black and green" (*Negro y verde*))

| Token | Value | Use |
|---|---|---|
| `fondo` | `#000000` | General background |
| `fondoReproductor` | artwork color, softened (example `#34465A`) | Player and mini player |
| `superficie` | `#161616` | Sheets (Devices, Import theme) |
| `superficieSutil` | white at 7–10% | Pill buttons, rows, tab container |
| `texto` | `#F2EEE8` | Main text, play button |
| `textoSecundario` | `#D5DCE4` | Artist in the player |
| `textoTerciario` | `#A9B4C0` | Times, secondary icons |
| `textoCuerpo` | `#C9C4BC` | Paragraphs and card subtitles |
| `etiqueta` | `#A39D95` | Uppercase labels (monospaced) |
| `letraPendiente` | `#8E99A6` | Words yet to be sung and the next verse |
| `acento` | `#2FD566` | Highlight, active device, toggles, primary button |
| `textoSobreAcento` | `#00170A` | Text on buttons with an accent background |
| `advertencia` | `#FFB23E` | Warning icon in theme import |
| `bordeChip` | white at 35% | Unselected filters |

The green is similar to Spotify's **on purpose, but not the same**. Spotify reserves its green
(`#1DB954`) for its own brand.

Contrast ratios verified on `#34465A`, the example player background:

| Text | Contrast |
|---|---|
| `texto` | 8.4:1 |
| `textoSecundario` | 7.0:1 |
| `textoTerciario` | 4.6:1 |
| `acento` | 5.0:1 |
| `letraPendiente` | 3.3:1 (only for text of 22 pt or larger) |

### Typography

The mockups use Space Grotesk (titles) and IBM Plex Mono (labels and times) as an
approximation. On iOS, use **the system font**, as Spotify's guidelines require:

| Use | iOS | Size / weight |
|---|---|---|
| Song title | `.system` | 40 pt bold (2 lines max.) |
| Artist | `.system` | 22 pt regular |
| Screen titles | `.system` | 34 pt bold (Settings), 24 pt bold (sheets) |
| Library/Search tabs | `.system` | 17 pt bold |
| Body | `.system` | 15–16 pt |
| Uppercase labels | `.system(design: .monospaced)` | 12 pt, tracking +0.08em |
| Playback times | `.system(design: .monospaced)` | 12 pt |
| Current verse | `.system` | 30 pt bold, line height 38 |
| Next verse | `.system` | 22 pt semibold, line height 30 |

Support Dynamic Type wherever it doesn't break the player's fixed layout. In Settings and in
first launch, yes.

### Shapes and motion

- Artwork: **4 pt** corner radius (Spotify guideline). Never crop it, cover it, or overlay
  anything on it.
- Pill buttons: radius equal to half the height. Cards and rows: 12–16 pt. Sheets: 20 pt at
  the top.
- Touch targets of at least **44 pt**.
- Icons: 2 pt stroke, line style. Use equivalent SF Symbols where they exist.
- **Song and lyric line changes** (owner's request, 2026-11-17; not in the mockups): artwork
  crossfades (0.45 s); title and artist move up 10 pt and fade out (0.35 s); the current verse
  moves up 18 pt while the next one comes in (0.35 s); normal view ⇄ lyrics mode with a fade
  (0.3 s). With *Reduce Motion*, only the fades remain.

## Player (`Main.dc.html`)

- **Margins**: 24 top, 48 on the sides, 20 bottom. Vertical spacing between blocks: 20.
- **Top block** (height 256):
  - **Artwork** of 256×256 on the left, 32 away from the text column.
  - **Top row of the column**:
    - Spotify icon (24, in a 44 zone; it is a link to Spotify) 12 from the source
      (owner's decision of 2026-11-17: the icon instead of the full 108×30 logo);
    - "From the playlist **Name**" (*Desde la playlist **Nombre***) in 13 pt, truncated with
      "…";
    - on the right, the **Library** pill (44 tall) and the **Settings** button (44).
  - **Title and artist** (see typography). Truncated text must be viewable in full: marquee
    or tap to expand.
  - **"Playing on Name"** (*Reproduciendo en Nombre*) in accent, 15 pt. Tapping it opens
    Devices.
- **Bottom block**, full width:
  - **Progress**: current time · bar 4 tall (track white at 18%, fill `texto`) · duration.
    No knob. With "Show time left" (*Mostrar tiempo
    restante*) (Settings › Player, off by default) the right side shows how much is left,
    `−2:23`, with the typographic minus sign (U+2212). Tapping that time toggles between
    duration and remaining (touch area of about 44 pt); it never changes the position.
  - **Seeking** (owner's request, 2026-11-18): putting a finger on the bar and moving it
    changes the position. The whole 44 strip around the bar takes the finger (the 16 of the
    row + 14 above and below), between the two times. While dragging, the bar grows to 8 tall
    and the left time shows, in `texto`, where it will jump to; the request is sent once, on
    release (a tap without dragging also jumps there). With VoiceOver, swiping up or down moves
    15 s. If `actions.disallows` forbids `seeking`, or on a device with `is_restricted`, the
    bar stays **informational**: it doesn't take the finger or give any hint that it can move
    (see `docs/en/06`).
  - **Controls** (height 64), in three groups:
    - left, in 200 of width: Shuffle and Repeat (48);
    - center, 20 apart: Previous (56), Play/Pause (64, `texto` circle with a dark icon) and
      Next (56);
    - right, in 200 of width: Lyrics (48; only if enabled in Settings; active = accent on
      accent at 16%) and Volume (48).
- Disable or hide the controls the API marks as not allowed (`actions.disallows`).

### Redesign of 2026-11-17 (owner's request)

Changes the above in these points (not in the mockups):

- **Full-width top row** (44), above the artwork: the Spotify icon and the source in the
  top-left corner; **Queue** and **Library** on the right (Queue first; see "Queue"). With the
  full width, the source has visible room for more than 25 characters.
  - **Source on two lines** (owner's request, 2026-11-18): "Playing from" (*Reproduciendo
    desde*) in 12/16 medium (secondary text) on top and, below, the name in 15/20 bold, the
    same sizes as in lyrics mode. Without a name, the type is shown: "A playlist" (*Una
    playlist*) (while it loads), "Spotify playlist" (*Playlist de Spotify*) (the API doesn't
    provide it: radios, mixes and editorial playlists), "An album" (*Un álbum*), "An artist"
    (*Un artista*), "A podcast" (*Un podcast*) or "Liked Songs" (*Tus me gusta*). The mockup
    has "From the playlist **Name**" on one line; this decision prevails.
  - Since 2026-11-18 (owner's request) nothing in this row has a pill: the source sits 12
    from the icon, which stays outside the button to respect its clear space. Queue and
    Library are icon and text (15 semibold) with no background, 24 apart; the touch zone is
    still 44 tall.
  - Top margin 12 (it was 24 in the mockup and 16 before 2026-11-18) and 14 between the row
    and the artwork (it was 4), so about 18 remain between the source text and the artwork.
- **Artwork of 210** (it was 256, and 216 before 2026-11-18) and artwork block height 210.
  Lyrics mode takes up the row and the block together (268). Vertical count:
  12 + 44 + 14 + 210 + 20 + 94 + 20 = 414.
- **Settings** is no longer in the player: it opens from the Library header (icon to the left
  of the Spotify logo, 20 apart).
- **Controls in a single centered row**, with 36 between all buttons. The theme's optional
  controls are split between the two sides as before (`PlayerControlLayout`), and both sides
  take the same flexible width, so Play/Pause always stays at the exact center. With all
  seven buttons the row measures 584 (it fits in the 640 of the 8 Plus).
- **Add to a playlist** (*Agregar a una playlist*) (2026-11-18, at the owner's request): a
  round 48 button with `plus.circle` at the **far left** of the controls row, styled like the
  optional controls (20 icon in `textoTerciario`). Disabled for ads and local files. It is not
  a theme control, just like Queue. Since the left side has to fit in the half left by the
  center (`2 × left + center + 4 gaps ≤ width`), the spacing between buttons shrinks when
  there isn't enough room (`PlayerControlLayout.gap(forWidth:)`): 36 on the 11 Pro Max (800
  of usable width) and **22 on the 8 Plus** (640), never less than 12.
- **Swipe to change songs**, like a carousel:
  - The drag can start anywhere in the strip of the artwork and the title, from edge to edge
    of the screen. It only counts if it starts more horizontal than vertical (decided at 8).
    The progress bar, the controls and the source row are excluded, with their own gestures.
  - Dragging left brings the next item and dragging right the previous one. The artwork, the
    title and the device follow the finger, and going back past the start shows the other
    one.
  - From the corresponding side, the other item's "page" comes in, one screen away: from the
    right, the next item in the queue (`GET /me/player/queue`), from the left, the previous
    one (the one the app saw playing before; the Web API doesn't provide it). The device row
    moves with its page (if it stayed still, the artwork would pass underneath it); the
    source row and everything below stay still.
  - If the item isn't known yet, the page shows an empty square with the next or previous
    icon and "Next" (*Siguiente*) or "Previous" (*Anterior*).
  - On release after 96 (or with a quick swipe), the new page finishes coming in (0.25 s),
    the phone vibrates (medium impact) and Next or Previous is sent. When Spotify reports the
    new item, the pages return to their place without animation. If it doesn't report another
    item within 2.5 s (for example, a "previous" that only restarted the song), it goes back.
  - If Spotify doesn't allow that skip, the content resists (a third of the travel, up to 40)
    and returns on release.
  - It also changes items for episodes (the episode buttons are still ±15 s).
  - In **lyrics mode** the strip is the bottom row (small artwork, title, artist and device),
    never the lyrics. That row moves the same way and the other item's row comes in.
- **"Artist photo" (*Foto del artista*) background** (Spotify TV app style): fourth option of
  PLAYER BACKGROUND (*FONDO DEL REPRODUCTOR*) (`fondoReproductor: "artista"`). It uses the
  largest photo from `GET /artists/{id}` of the first artist, full screen (`fill`).
  - Since 2026-11-18 (owner's request) the photo stands alone and fills the screen (cropped,
    see `docs/en/06-compliance.md`): no fade toward the artwork and no artwork color at the
    bottom.
  - When the artist changes, the previous photo stays until the new one is ready and they
    switch with the 0.8 s fade. The artwork color is only seen when there's no photo at all:
    at startup, before the first one, or if the artist has no photo.
  - On top, a black layer darkens it a bit (**Dim** (*Oscurecer*), `oscurecerFondo`, 60% by
    default). 100% is black at 80%: the photo never disappears completely.
  - Slow zoom from 1 to 1.06 over 30 s, back and forth (no zoom with *Reduce Motion*), and a
    0.8 s fade when the artist changes.
  - With this option, the **Blur** (*Desenfoque*) and **Dim** sliders appear (0 to 100%, in
    steps of 5; the theme's `desenfoqueFondo` and `oscurecerFondo`). By default, 40% blur and
    60% dim (owner's request, 2026-11-18). 100% blur is a radius of 30. They're saved on
    release. See "Settings" for the preview.
  - Spotify provides a single photo per artist (in three sizes), so it doesn't rotate between
    photos.
  - See `docs/en/06-compliance.md`, "Gray areas".

### Lyrics mode

Replaces the top block:

- **Top row** (44): the Spotify icon and, 12 away, "Playing from" (*Reproduciendo desde*) in
  12 pt on top and the name (or the type, as in the normal view) in 15 pt bold below, on the
  left. The mockup had the logo on the right; the owner moved it next to the source on
  2026-11-17, same as in the normal view.
- **Lyrics**, centered in the remaining space:
  - current verse and next verse, at the width of "Lyrics width" (*Ancho de las letras*)
    (50%, **66.7%** or 100% of the usable width);
  - no forced line breaks, balanced `text-wrap` and 12 of spacing.
  - **Word by word**: what's already sung in `texto` and what's pending in `letraPendiente`.
  - **Full verse**: the whole current verse in `texto`. That's what line sync shows, and also
    word sync when "Lyrics style" (*Estilo de las letras*) is set to Verse.
  - **Browse and jump** (owner's request, 2026-11-18), only where Spotify allows seeking (like
    the progress bar):
    - Dragging up or down over the lyrics browses the verses: every 44 of drag shows the next
      one (up, as when scrolling a list) or the previous one, whole in `texto`, with the
      following one below. Above it, in accent and 13 monospaced, "▶ 2:07": when it starts.
      Verses cross-fade (not the usual rise, which would look backwards when going back) with
      a selection haptic.
    - Tapping a verse (the big one or the one below, browsing or not) moves the playback to
      where it starts, minus the "Lyrics timing" (*Sincronía de las letras*), and the lyrics
      follow the playback again.
    - After 4 s without touches, the lyrics go back to what's playing on their own.
    - With VoiceOver, the current verse has the action "Play from here" (*Reproducir desde
      acá*).
- **Bottom row** (56): 56 artwork (radius 4), title in 18 bold, artist in 15 and, on the
  right, the device in accent.
- Library and Settings are not shown.

### Volume bar

Owner's request (2026-11-18), approved on the mock `design/mockups/VolumenLateral.html`. It
replaces the floating pill of `Volumen.dc.html`, which stays as a historical reference.

- **Opens sideways, from the Volume button**: the whole controls row moves left until Previous
  (or −15 s) sits on the left edge, and the bar unrolls from the speaker's right edge to the
  end of the row. When it closes, the bar rolls back into the speaker and the row returns to
  its place.
- While it's open, Add to a playlist, the left group and the right-group controls after the
  speaker (they would sit under the bar) fade out. Previous, Play/Pause, Next and the
  right-group controls before the speaker (Lyrics, with the default order) stay visible and
  tappable.
- The open speaker shows as active (accent on accent at 16%); tapping it again closes the bar.
- If the theme has no Volume in the right group (it's on the left or missing) and the bar
  opens (for example, because the volume changed from another device), a speaker of its own
  comes in with the bar, after the right group.
- **No background**: no panel, no shadow, no − and + buttons. The bar sits right on the player
  background, which no longer shrinks: you can swipe between songs with the bar open.
- Content: 12 of breathing room · bar 8 tall (track white at 14%, fill in accent) · 12 · value
  in monospaced 14 (30 wide, right-aligned). With the default controls, the room for bar and
  value is 384 on the 11 Pro Max and 280 on the 8 Plus.
- **Drag** (owner's request, 2026-11-17): the whole 44 row around the bar takes the finger;
  tapping or dragging sets the level instantly. While dragging, at most one change is sent
  every 250 ms, plus the final value on release. With VoiceOver, each swipe on the bar changes
  the volume by 5%.
- **Opening**: the row moves and the bar unrolls in 0.30 s, with curve `(0.2, 0.8, 0.2, 1)`.
  What leaves fades out in 0.12 s; the bar's content appears in 0.2 s, 0.06 s later.
- **Closing**: after 3 s without interaction (never with the finger on the bar), or when
  tapping the speaker, in 0.22 s ease-in. The controls come back in 0.2 s.
- **Opens** when tapping Volume or when polling detects a different volume.
- If the device doesn't support changing the volume (`supports_volume: false`), the bar's place
  reads "This device doesn't allow changing the volume" (*Este dispositivo no permite cambiar
  el volumen*, up to two lines).

### Notice (toast)

- Pill 48 tall, centered 20 from the top edge, with a `texto` background and dark text in
  15 semibold, plus an icon.
- `accessibilityLabel` announced as a status. Lasts 3 s.

### Background from the artwork

1. Downscale the artwork to ~32×32 and compute the **most frequent** color, discarding
   near-blacks and near-whites. Don't use the average of the whole image.
2. Convert it to HSL or OKLCH, clamp **saturation to 25–35%** and set **lightness to
   25–30%**.
3. If `textoTerciario` falls below 4.5:1, darken one more step.
4. ~0.5 s transition between songs. Cache the result by album ID.
5. If there's no artwork, use `fondo`.

## Library (`Biblioteca.dc.html`)

- **Margins**: 28 top, 48 on the sides, 10 bottom. Blocks are distributed with
  `space-between`.
- **Row 1**:
  - segmented control with **Library** and **Search** (44 container, radius 22, white at
    8%, padding of 4 and shifted −4 so the active tab lines up with the filters; 36 tab,
    radius 18, active with a `texto` background and black text);
  - Spotify logo on the right.
- **Row 2** (only in Library):
  - filters Playlists, Albums, Podcasts and Audiobooks (*Playlists, Álbumes, Podcasts y
    Audiolibros*) (36 tall, radius 18, 1.5 border; the active one, `texto` fill);
  - "OPEN SPOTIFY ↗" (*ABRIR SPOTIFY ↗*) in monospaced on the right.
- **Cards**: 150×150 artwork (radius 4), name in 16 semibold and subtitle in 13, with 20
  between cards. The row scrolls horizontally and reaches the right edge of the screen.
  Tapping a playlist or an album opens its detail. Long-pressing the card offers "Play"
  (*Reproducir*) directly. Podcasts and audiobooks open in Spotify.
- **Playlist folders** (experimental option): when a folder is opened, the row shows its
  contents and "‹ Back" (*‹ Volver*) replaces the filters. Closing a playlist's detail goes
  back to the folder it was opened from. The first folder search after launch shows
  "Looking for folders…". If it fails, a notice appears once and the ungrouped playlists
  load. Later loads during the same launch skip both notices.
- **Search**: 56 field (radius 28, white at 10%) with the placeholder "Songs, artists, albums,
  podcasts or audiobooks" (*Temas, artistas, álbumes, podcasts o audiolibros*) and a help
  line.
- **Mini player** (56, radius 14, background from the artwork): Add to a playlist
  (`plus.circle` of 20 in `texto`, 44 zone; since 2026-11-18, at the far left), 40 artwork,
  title and artist, "Playing on **Device**" (*Suena en **Dispositivo***) in accent (opens
  Devices) and Pause (44).

## Playlist or album detail (`Detalle.dc.html`)

Opens when tapping a playlist or album card. It keeps the Library margins and the mini
player; the filter row and the cards are replaced by the detail.

- **Row 1** (44): "‹ Library" (*‹ Biblioteca*) on the left (36 pill, radius 18, white at 8%,
  17 bold, padding 10/16, shifted −4 like the tabs). Next to it, **Shuffle** (44, with
  the same style and state as the player's control). On the right, "OPEN IN SPOTIFY ↗"
  (*ABRIR EN SPOTIFY ↗*) in monospaced (opens the playlist or the album) and the logo, with 20
  between them.
- **Central block** (252), in two columns with 32 between them:
  - **Left** (170): 150×150 artwork (radius 4), name in 18 bold (line height 22, one line
    with a marquee if it doesn't fit) 10 from the artwork, subtitle in 13 `textoCuerpo`
    ("By <owner> · N songs" (*De <dueño> · N temas*) or "<artists> · <year>") and, at the
    bottom, **Play** (*Reproducir*): 150×44, radius 22, `acento` background, `textoSobreAcento`
    16 bold text with a 16 play icon.
  - **Right**: "48 SONGS · 2 H 51 MIN" (*48 TEMAS · 2 H 51 MIN*) in monospaced 12 `etiqueta`
    (+0.08em, height 22; the duration appears once all songs are loaded) and the list with
    vertical scrolling. Rows of 50 with a top line of white at 10%: number (monospaced 12
    `textoTerciario`, 22 wide, right-aligned), 14 of spacing, title 16 semibold (line height
    21) with the "E" mark (15) if explicit, artists in 13 `textoCuerpo` and duration in
    monospaced 12. Unavailable songs are at 40%. At the bottom, a 36 fade toward the
    background. They load 50 at a time on reaching the end.
  - **Someone else's playlist**: instead of the list, a lock (28, `etiqueta`), "Spotify
    doesn't show this playlist's songs" (*Spotify no muestra los temas de esta playlist*)
    (20 bold, line height 26), a help line (15/22) and "View in Spotify ↗" (*Ver en Spotify
    ↗*) (44 outlined button, border white at 35%), all within a maximum width of 440 and
    vertically centered.
- Tapping an available song starts playback at its position in the collection and keeps
  the detail open. Long-pressing a song shows the full name and "Open in Spotify"
  (*Abrir en Spotify*) when a link is available.

## Devices (`Dispositivos.dc.html`)

- 640×398 sheet over a black background, with surface `#161616`, radius 20 at the top and a
  40×5 grabber.
- **Header**: 52 circle in accent with the device icon, "CURRENT DEVICE" (*DISPOSITIVO
  ACTUAL*) in accent, the name in 22 bold and Close (44).
- "CHOOSE A DEVICE" (*ELEGÍ UN DISPOSITIVO*), and below it rows of 60 with separators of
  white at 10%: icon (26), name (18 medium) and type (14).
- **"Don't see your device?"** (*¿No ves tu dispositivo?*) (text button with an icon) opens a
  view inside the sheet with:
  1. Open Spotify on that device.
  2. Use the same Spotify account as this app.
  3. If it's a speaker or a TV, wake it up first.

  Plus "Refresh list" (*Actualizar lista*) (primary) and "Back to the list" (*Volver a la
  lista*).

## Add to a playlist (2026-11-18, no mockup)

At the owner's request. It opens from the player's button and from the mini player's, and
follows the Queue design:

- The same 640×398 sheet (grabber, surface, radius 20 at the top, 40 gradient at the end).
- **Header**: Queue's, with "ADD TO A PLAYLIST" (*AGREGAR A UNA PLAYLIST*) in accent instead
  of "PLAYING" (*SONANDO*). The song is **fixed** on opening: if the music moves on while the
  user chooses, the one that was playing when the button was tapped is added.
- "YOUR PLAYLISTS" (*TUS PLAYLISTS*) and rows of 56: 40 artwork (uncropped, radius 4), name
  in 16 semibold, "Collaborative · N songs" (*Colaborativa · N temas*) in 13 `textoCuerpo`,
  and on the right the status in a 44 zone: `plus.circle` (`textoTerciario`), loading
  indicator, `checkmark.circle.fill` in accent (added) or `exclamationmark.circle` in
  `advertencia` (failed; tapping retries). The whole row is the button and it **adds
  immediately**, without confirmation. Long names scroll (marquee) so they can be read in
  full before tapping. Long-pressing the row offers "Open in Spotify" (*Abrir en Spotify*)
  with that playlist's page (the link back from docs/en/06-compliance.md).
- The song total goes up by one when adding. If a read of the list overlaps with the request,
  that total is hidden until the next read instead of guessing it.
- **Search field** (2026-11-18, at the owner's request): between the header and the list, a
  small version of Search's field: 40 capsule (white at 10 %), 18 magnifying glass, 16 text and
  the placeholder "Search your playlists" (*Buscar en tus playlists*) in `etiqueta`; with
  text, an ✕ clears it. It filters by name ignoring case and accents. No matches: "No playlist
  matches that name." (*Ninguna playlist se llama así.*). Scrolling the list dismisses the
  keyboard (in landscape it covers almost the whole sheet).
- **Already in, first** (2026-11-18, at the owner's request): "ALREADY IN" (*YA ESTÁ EN*) with
  the playlists that already have the song (check in accent; tapping them doesn't add another
  copy), and below it "OTHER PLAYLISTS" (*OTRAS PLAYLISTS*). If it's in none, a single "YOUR
  PLAYLISTS" group. The first time, every playlist is read: until that finishes, a spinner with
  "Looking for the song in your playlists… N of M" (*Buscando el tema en tus playlists… N de
  M*) replaces the list, so rows don't move under the finger. What's added with the sheet open
  stays in place; it moves up to "ALREADY IN" the next time. If some playlist couldn't be read,
  a note above the list says so, and that playlist isn't marked "already in" from old data.
  On pull to refresh, the list stays on screen with its previous order; a tap meanwhile waits
  for the read and doesn't add if the song was already there.
- Only **your own and collaborative** playlists appear (`owner.id` = user or
  `collaborative: true`), in Spotify's order within each group. At the end: "Only your own and collaborative
  playlists appear. To remove songs, use Spotify." (*Solo aparecen tus playlists y las
  colaborativas. Para quitar temas, usá Spotify.*) and "OPEN SPOTIFY ↗" (*ABRIR SPOTIFY ↗*).
- What was added stays marked while the app is open and isn't added again with another tap
  (avoids accidental duplicates). It **can't be removed** from the app (see
  docs/en/03-spotify-api.md).
- **Permission needed** (*Falta un permiso*): with sessions from before 2026-11-18, instead
  of the list you see a lock, "Permission needed", the explanation and "Allow" (*Dar
  permiso*) (accent capsule), which opens the Spotify login again without leaving the
  player.
- **No editable playlists**: list icon, "You have no playlists you can edit" (*No tenés
  playlists para editar*) and how to create one. **Error**: the Devices notice line and
  "Retry" (*Reintentar*). If a read fails with the list already on screen, the list stays
  and "Retry" appears next to the notice; an add that fails is retried by tapping its row.
  When signing back in with "Allow", only the **same Spotify account** is accepted, and only
  if Spotify grants both permissions.

## Queue (`Cola.html`)

- The same sheet as Devices: 640×398 over a black background, surface `#161616`, radius 20
  at the top, 40×5 grabber (dragging it down closes it).
- **Header** (height 56): 56 artwork, "PLAYING" (*SONANDO*) in accent (12 mono, +0.08em), the
  title in 20 bold and the artists in 14 `textoCuerpo` (with the explicit mark in front, as
  in the player); on the right, the Spotify logo (link to the song)
  and Close (44). Long titles and artists scroll (marquee).
- "UP NEXT" (*A CONTINUACIÓN*) (12 mono, `etiqueta`) and rows of 56 with separators of white
  at 10%: number (12 mono), 40 artwork (uncropped, radius 4), title 16 semibold with the
  explicit mark, artists 13 `textoCuerpo` and duration (12 mono). Up to **20** songs.
- **Tapping a song** (since 2026-11-18, owner's request; not in the mockup) opens the system
  alert "Play this song?" (*¿Reproducir este tema?*), with "“Title” by Artists starts
  playing now." (*«Título» de Artistas empieza a sonar ahora.*) and the buttons "Play"
  (*Reproducir*) and "Cancel" (*Cancelar*). While pressed, the row dims to 70%. While it
  starts, a spinner replaces the duration and the other rows don't respond; if it fails,
  the notice line shows above the list ("No active device. Choose one to listen on."
  (*No hay un dispositivo activo. Elegí uno para escuchar.*), "Couldn't play it. Try
  again." (*No pudimos reproducirlo. Probá de nuevo.*), etc.). The sheet stays open and
  updates on its own when the song starts. Episodes and local files are not buttons.
- Long-pressing a song shows the full name and "Open in Spotify" (*Abrir en Spotify*), as in
  the detail. At the bottom, a 40 gradient toward the surface.
- At the end of the list: "To remove or reorder songs, use Spotify." (*Para quitar o
  reordenar temas, usá Spotify.*) (14, `textoCuerpo`) and "OPEN SPOTIFY ↗" (*ABRIR SPOTIFY
  ↗*).
- **Empty queue**: list icon, "The queue is empty" (*No hay nada en la cola*) (20 bold) and
  "When this song ends, Spotify decides what's next. You can pick something from the
  Library." (*Cuando termine este tema, Spotify decide qué sigue. Podés elegir algo desde la
  Biblioteca.*) (15, maximum width 440).
- **Error**: the Devices notice line and "Retry" (*Reintentar*) (48 accent capsule).
- It's read on opening, when another song starts with the sheet open (also if the same song
  starts again, for example because it was in the queue twice in a row) and when pulling the
  list down (also with an empty queue). It has no polling of its own: it uses the player's,
  which keeps running while the sheet is open.
- **Button**: "Queue" (*Cola*) in the top row, to the left of Library and with the same style
  (44 tall, icon and text 15 semibold; no pill since 2026-11-18). It's always there, except
  in lyrics mode: its top row keeps the Spotify icon and the source, but doesn't have Queue
  or Library.
- Differences from the mockup (owner's decision, 2026-11-17):
  - The mockup puts the button in the right group of controls. Since the redesign, the
    controls go in a single centered row with 36 between buttons, and one more doesn't fit on
    the iPhone 8 Plus (that side would need 216 and has 160), so it moved to the top row.
  - It is not a theme control (`reproductor.controles`): themes saved before it existed list
    their controls and would never show it.
  - The icon is the SF Symbols `list.bullet` symbol (three bulleted lines); the mockup draws
    lines with a play triangle.

## Settings (`Ajustes.dc.html`)

- **Left column** (200): Back, "Settings" (*Ajustes*) in 34 bold and vertical tabs Appearance
  and Player (*Apariencia* and *Reproductor*) (44 tall, radius 12; the active one with a
  background of white at 12%).
- **Appearance**:
  - **THEME** (*TEMA*): 40 chips with a sample of the accent on the theme's background.
  - **ACCENT COLOR** (*COLOR DE RESALTADO*): 6 circles of 32 in 44 zones; the selected one
    has a `texto` ring. Colors: Green `#2FD566`, Amber `#FFB23E`, Sky blue `#7CC4FF`, Coral
    `#FF7A7A`, Lavender `#C9A2FF`, White `#F2EEE8` (*Verde, Ámbar, Celeste, Coral, Lavanda,
    Blanco*).
  - **PLAYER BACKGROUND** (*FONDO DEL REPRODUCTOR*): segmented with Black, Dark gray, **From
    the artwork** (default) and Artist photo (*Negro, Gris oscuro, Según la carátula, Foto del
    artista*). With Artist photo, **Blur** and **Dim** (*Desenfoque* and *Oscurecer*) appear,
    with a single note below.
  - **Background preview** (owner's request, 2026-11-18): when touching one of those two
    sliders, the rest of Settings (left column, sections, note and the other slider) fades
    out in 0.25 s and behind it the player background appears with the sample photo and the
    values being chosen, live. Only the slider being moved remains. On release, Settings
    comes back with the same animation and the value is saved.
    - Sample photo: the one of the **last artist that played** (a song chosen while paused
      doesn't count until it plays). First, the photo of that artist that the player showed
      with Settings open; if there isn't one, that artist's photo is fetched
      (`GET /artists/{id}`). The fetch first checks the last song listened to on Spotify
      (`GET /me/player/recently-played`): it's used if the app hasn't heard anything yet in
      this session or if it names that same artist; since the history may lag behind, if it
      names a different one it's ignored. It's recomputed when the photo or the playback
      changes (pause, resume, stop). With none at all, the theme's background color is shown.
    - It's fetched when the sliders appear (unless there's already a suitable photo) and
      canceled when Settings closes. A photo that was found is suitable as long as it's of
      the last artist listened to. If there's no photo (an error, a wait due to `429`, or it
      stopped being suitable), it's fetched again when the sliders reappear, when touching
      one, or if the last artist listened to changes while dragging (also if it goes back to
      a previous one); if a fetch was already in progress, the new one starts when that one
      finishes. A poll that doesn't change the artist doesn't repeat the request.
    - While a photo is shown (and only then), the Spotify icon stays at the top left, in the
      same place as in the player, and opens that photo's artist in Spotify
      (`docs/en/06-compliance.md`).
    - What fades out doesn't receive touches either: with one finger on a slider, another
      finger can't start moving the other one.
  - **Export theme** (*Exportar tema*) and **Import theme** (*Importar tema*): 48 outlined
    buttons.
- **Player**:
  - **Show lyrics** (*Mostrar letras*) toggle (56×32 track, 26 knob, on in accent);
  - **Lyrics width** (*Ancho de las letras*): Half, **2/3** or Full (*Mitad*, *2/3* or
    *Completo*);
  - **Lyrics style** (*Estilo de las letras*): **By word** or Verse (*Por palabra* or
    *Estrofa*; the same segmented control as the width; added by the owner on 2026-11-18, not
    in the mockup);
  - note about LRCLIB.

## Import theme (`TemaImportar.dc.html`)

- 800×398 sheet. Header with "Import theme" (*Importar tema*), the file name in monospaced
  and Close.
- **Left**: the JSON in monospaced 12/17 on `#0A0A0A` with a `#2A2A2A` border, with
  scrolling.
- **Right** (280):
  - "Valid theme" (*Tema válido*) status (accent) or the error;
  - preview with the theme's colors;
  - warnings with a yellow icon, for example about low contrast (which is corrected when
    applying);
  - Apply theme (*Aplicar tema*) (primary) and Cancel (*Cancelar*).

## Nothing playing (`SinReproduccion.dc.html`)

- 290 dotted frame in place of the artwork, "Nothing playing" (*Nada sonando*) in 40 bold and
  a help line.
- Buttons "Choose device" (*Elegir dispositivo*) (primary, 56) and "OPEN SPOTIFY ↗" (*ABRIR
  SPOTIFY ↗*).

## First launch (`Onboarding1–3.dc.html`, portrait)

1. **Welcome**:
   - provisional logo (landscape rectangle with a square in accent) + "Nowdeck";
   - illustration of a "deck";
   - title "Your iPhone, now a desk controller." (*Tu iPhone, ahora control de escritorio.*);
   - "YOU'LL NEED" (*VAS A NECESITAR*) list (Spotify Premium, a browser, 5 minutes);
   - "Get started" (*Empezar*);
   - notice that it isn't affiliated with Spotify.
2. **Create the app**: "STEP 1 OF 2" (*PASO 1 DE 2*); 5 numbered steps; the box with
   `nowdeck://callback` and Copy (*Copiar*); "Open the dashboard" (*Abrir el panel*)
   (outlined) and "I already have a Client ID" (*Ya tengo mi Client ID*) (primary).
3. **Client ID**:
   - 56 monospaced field with Paste (*Pegar*); help: "It's 32 letters and numbers. It's
     stored only on this iPhone, in the Keychain" (*Son 32 letras y números. Se guarda solo
     en este iPhone, en el Llavero*);
   - list of permissions in plain words;
   - "Connect to Spotify" (*Conectar con Spotify*).

Steps added after connecting (2026-11-17, no mockup; same style as the previous ones):

4. **Playlist folders** (*Carpetas de playlists*) (first time only): explains that the Web
   API doesn't provide folders, offers the experimental mode with its risks and has
   "Continue without folders" (*Seguir sin carpetas*) (primary) and "Turn on folders
   (experimental)" (*Activar carpetas (experimental)*) (outlined). It can be changed in
   Settings → Player.
5. **All set!** (*¡Listo!*): the ring and the checkmark draw themselves, the text moves up
   and at 1.8 s the player comes in with a fade while the screen rotates to landscape.

The whole setup stays **locked in portrait**: rotating the phone doesn't rotate it.

## Adapting to the iPhone 8 Plus (736×414)

- Compute the artwork with `GeometryReader`: `min(available height of the top block, width × 0.3)`.
- Shrink the side control groups from 200 to ~160.
- The Import theme sheet goes down to ~680 wide, and the right column to 240.
- In Library, the card row already scrolls: no need to change it.
- In the playlist or album detail, the left column doesn't change and the song list gets
  narrower (about 440 wide).
