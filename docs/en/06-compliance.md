# 06 · Spotify compliance

> English translation of [`docs/06-cumplimiento.md`](../06-cumplimiento.md). The Spanish version is the source of truth; if they differ, it wins.

Sources:
- Design & Branding Guidelines: https://developer.spotify.com/documentation/design
- Developer Policy: https://developer.spotify.com/policy/
- Developer Terms: https://developer.spotify.com/developer-terms-of-use/

Breaking these rules can lead Spotify to revoke API access.

## Checklist by screen

- [ ] **Attribution**: every screen with Spotify content (Player, lyrics mode, Library, mini
  player, Queue) shows the **official Spotify logo**.
  - Full logo: 70 px digital minimum. Icon alone: 21 px minimum.
  - Exclusion zone equal to half the icon's height.
  - On dark backgrounds, white logo. Green only on black or white.
  - The asset is downloaded from Spotify's site (*Design Resources*) and goes in
    `Resources/Assets.xcassets`. **Don't draw it by hand.**
- [ ] **Link back**: the logo (and the playlist or album name) opens the content in Spotify.
  - If the Spotify app is installed, use the universal link `open.spotify.com/...`. If not,
    send the user to the App Store.
  - There must be a visible "OPEN SPOTIFY" (*ABRIR SPOTIFY*) text somewhere in the app. It's
    in Library and in Nothing playing (*Nada sonando*).
- [ ] **Artwork**: Spotify's artwork is used as is, with a 4 pt radius. **No cropping, no
  blurring, no text, controls or logos overlaid on it.**
- [ ] **Metadata**: names unmodified.
  - If they're truncated, there has to be a way to see them in full (marquee or tap).
  - Leave room for at least 25 characters for a playlist or album, 18 for an artist and 23 for
    a song.
- [ ] **Controls**: disable or hide whatever `actions.disallows` forbids. The guidelines:
  "Play controls must either have a disabled state to indicate that they are restricted or
  they should not be displayed at all". Nowdeck disables them (see `docs/en/03`, "`actions`").
- [ ] **Progress**: where Spotify doesn't allow seeking, informational, with no hint that it
  can be scrubbed. The guideline's sentence ("Make clear that the track progress bar is for
  information only - there should be no indication that the user can seek") is in the section
  *Handling Spotify Free restricted actions in your companion app* (re-read on 2026-11-18): it
  covers restricted actions, and doesn't forbid seeking where Spotify allows it.
- [ ] **Podcasts**: show the episode title and the podcast name. ±15 s skips for episodes:
  **applies** (verified on 2026-11-17 in *Design & Branding Guidelines* → "Playing views").
  The section starts with "If you choose to show play controls in your app, the following
  requirements need to be followed" and asks that "Podcasts need to have the option to seek
  15 seconds forward or backwards" (also for audiobook samples). Nowdeck shows controls, so
  for episodes −15 s and +15 s replace Previous and Next (`PUT /me/player/seek`). The same
  section *recommends* not offering more controls than play/pause: it's a recommendation, not
  a rule, and Nowdeck's design sets it aside on purpose.
- [ ] **Player background**: take the color from the artwork. If that's not possible, use a
  dark color.
- [ ] **Content rows**: at most **20 items** per row, and each row ends with a link to the
  Spotify app.
- [ ] **Explicit**: mark songs with `explicit: true`.
- [ ] **Nowdeck name and logo**:
  - No "Spotify" and nothing that starts with "Spot" or sounds similar.
  - "for Spotify" is allowed as a tagline.
  - The app icon can't look like Spotify's: no green circle and no waves.

## Policy (what you can't do)

- **Imitate or replace a core Spotify experience** without permission: don't copy screens from
  Spotify or from the Car Thing. Nowdeck's design is its own and has to stay that way.
- **Control Spotify by voice**.
- **Suggest endorsement, affiliation or co-branding** by Spotify. The first launch already
  includes the "independent project, not affiliated" notice.
- Use Spotify content to train AI models, or analyze it to produce metrics.
- Commercial or business use, such as music in a store.

## Gray areas (document in the README)

- **Each user's own Client ID**: Spotify neither forbids nor endorses it in writing. It's the
  only practical way to distribute an open app with the 5-user limit.
- **Lyrics from LRCLIB**: the policy forbids products integrated with another service's
  content. That's why the feature is explained and can be turned off in Settings. It starts
  on, per the owner's decision of 2026-11-18 (see "Gray areas" in the review below).

- **Playlist folders (experimental, optional)**: owner's decision of 2026-11-17. The Web
  API doesn't provide folders; with the option on, Nowdeck reads the *rootlist* from Spotify's
  internal playlist service (`spclient.wg.spotify.com`), which isn't documented or approved
  for third-party apps and conflicts with the Developer Terms. That's why:
  - it's **off by default** and offered with the risks explained (optional setup step and
    Settings → Player);
  - it only sends the user's Web API token: it does **not** imitate the Spotify client (no
    `client-token` and no web player token);
  - if the service rejects the request, the library shows the flat list with a notice.
  Nobody has tested it with a real account yet; most likely Spotify will reject that token.

- **Artist photo as background**: owner's decision of 2026-11-17, to resemble Spotify's TV
  app. The *Get Artist* reference says "Spotify visual content must be kept in its original
  form, e.g. you can not crop album artwork, overlay images on album artwork…". The photo is
  shown cropped to fill the screen and, since 2026-11-18, on its own and darkened by a
  configurable black layer ("Dim" (*Oscurecer*)), so this conflicts with the letter of that
  sentence. The design guide's rules
  ("Artwork must be kept in its original form… This includes applying overlays and blurring")
  are under "For album and podcast artwork" and don't mention artist photos. The owner
  considers it acceptable because it's personal use, with no distribution. To limit the risk:
  - the **artwork** stays intact (not cropped or covered); the photo goes only in the
    background;
  - it's an option in Settings → Appearance → PLAYER BACKGROUND (*FONDO DEL REPRODUCTOR*),
    not on by default (the default background is still "From the artwork" (*Según la
    carátula*)), and with another option it isn't requested;
  - the "Blur" (*Desenfoque*) and "Dim" sliders blur and darken it further (the guide names
    *blurring* and *overlays* among the things not to do with artwork; here, again, it's the
    artist photo, not the artwork);
  - the content is still attributed (Spotify icon and link back in the top row; in the
    Settings preview, the icon appears in the same place while the photo is shown and opens
    the artist of that photo).
  The Canvas (looping video) isn't in the Web API and isn't fetched.
- **Swiping between songs** (2026-11-17): while dragging, the current song's artwork and the
  next or previous one's move whole, side by side; an edge may be off screen for a moment, as
  in any carousel. They're never cropped to fit, never overlap, and nothing is drawn on top.
  When the item isn't known, the empty square with an icon isn't artwork.
- **"Car Thing-like" controls** (owner's request of 2026-11-17): only the idea of a centered
  row with more space between the buttons was taken. The buttons, colors and sizes are still
  Nowdeck's: the Car Thing screen wasn't copied.

## App Store (if it's ever published)

- Apple may ask for proof that you're allowed to show the artwork. In the store screenshots,
  use your own generic artwork.
- **Privacy policy**: Nowdeck doesn't collect data. Tokens stay on the device and it only
  talks to Spotify and LRCLIB.

## Milestone 8 review (2026-11-17)

Point-by-point review on the `hito/08-terminaciones` branch (milestones 1 to 7 integrated).
✅ complies · ⚠️ pending for the owner · ❌ doesn't comply, with the reason.

### Attribution

- ✅ **Official logo (2026-11-17)**: the owner brought the files from *Design Resources* (2024
  kit). `SpotifyIcon` (white icon) goes next to the source in the Player and in lyrics mode;
  `SpotifyLogo` (full white logo) in Library. The official SVGs were only re-saved with the
  white fill written on each path, because the asset catalog doesn't read `<style>` blocks.
  24 pt icon (minimum 21) with 12 clear (half the height). What follows in this point is the
  previous state.
- ⚠️ **Official logo**: the slot is in the Player (108×30 in a 44 zone, on the left of the
  top row), lyrics mode (top right) and Library (tab row, which also covers the mini player).
  The `SpotifyLogo` asset is **empty on purpose**: the owner still needs to add the official
  white file from *Design Resources*. Meanwhile, the Player and Library show the empty slot
  (it can be tapped) and lyrics mode a dotted box with the text "SPOTIFY LOGO" (*LOGO
  SPOTIFY*). The logo is never drawn or imitated.
- ✅ **Size and exclusion zone**: 108 pt wide (minimum 70) and 15 pt clear between the logo
  and "From the playlist" (*Desde la playlist*) (half of 30). The mockup had 10; 15 is used
  per the guide.
- ⚠️ **Logo color**: the code doesn't tint it; it depends on the file that's added being the
  white version, because all backgrounds are dark.

### Link back

- ✅ The logo opens the content in Spotify (the context or the song; in Library, Spotify's
  home). The playlist or album name does too ("Playing from …" (*Reproduciendo desde …*) in
  the Player, the name in lyrics mode, and "Open in Spotify" (*Abrir en Spotify*) in each
  card's menu).
- ✅ Universal link `open.spotify.com` with `universalLinksOnly`; if Spotify isn't installed,
  its App Store page opens (`SpotifyLink`). Only `https://open.spotify.com` URLs are opened.
- ✅ Visible text "OPEN SPOTIFY ↗" (*ABRIR SPOTIFY ↗*) in Library and in Nothing playing
  (*Nada sonando*), plus the "See more in Spotify" (*Ver más en Spotify*) card at the end of
  each row.
- ✅ Queue (2026-11-17): full logo in the header (link to the playing song), up to 20 songs,
  explicit mark, full names on long press and "OPEN SPOTIFY ↗" at the end of the list.
- ✅ Add to a playlist (2026-11-18): full logo in the header (link to the song), explicit
  mark, title and artists with marquee, and "OPEN SPOTIFY ↗" at the end.
- ⚠️ Add to a playlist shows **all** editable playlists, without cutting at 20: it was
  interpreted as not a content row but a destination picker (same criterion as the song list
  in the detail view).

### Artwork

- ✅ Shown as is (`.fit`, not cropped), with a 4 pt radius, with no text, controls or logos
  on top, in the Player, lyrics mode, mini player, cards, Queue and Add to a playlist.
- ✅ Fixed in this milestone: while a card was starting, the whole card was dimmed, artwork
  included. Now only the text is dimmed.
- ⚠️ **Temporary overlays**: the volume panel (520×64, centered at the top, as in
  `Volumen.dc.html`) and the notices (pill centered at the top) sit for a few seconds over the
  top-right corner of the artwork. It's the mockups' design and doesn't cover anything
  permanently, but the guide says "no controls overlaid on it". Options: leave it as is, or
  center the panel and notices over the text column instead of the screen. Not changed.

### Metadata

- ✅ Names unmodified: every name that comes from Spotify is shown with
  `Text(verbatim:)` (neither translated nor interpreted as Markdown).
- ✅ **Readable truncated names** (new in this milestone): the **marquee** was chosen, which
  both this guide and `docs/en/02` offer. A phone on the desk is read at a glance and almost
  all texts that can be cut off are already buttons (the source opens Spotify, the device
  opens the sheet), so "tap to see in full" conflicted with those actions.
  - They scroll, only if they don't fit: title (two lines; if they're not enough, one line
    that scrolls), artist, the source name and "Playing on …" (*Reproduciendo en …*) in the
    Player; source name, title, artist and device in lyrics mode; title · artist and
    "Playing on …" (*Suena en …*) in the mini player. 3 s pause at the start, 30 pt/s, faded
    right edge. With *Reduce Motion* it makes a single pass each time the text changes.
  - Library cards don't scroll: tapping them plays, and long-pressing them shows the full
    name (context menu preview).
  - VoiceOver always reads the full text.
- ✅ **25 characters for the playlist or album in the Player**: since 2026-11-18 the source
  goes on two lines ("Playing from" (*Reproduciendo desde*) on top and the name below, see
  `docs/en/02`), and with the row at full width the name has visible room for more than 25
  characters. If it doesn't fit, it scrolls.
- ⚠️ **25 characters in Library cards**: the name goes on one 150 pt line at 16 pt semibold
  (like the mockup), where about 17 characters fit. The full name is seen by long-pressing
  the card. If the rule has to be met to the letter, the proposal is to allow two lines for
  the name (+22 pt of height per row; it fits in 414 pt).
- ✅ 18 artist characters and 23 song characters: the artist has one 22 pt line in a column
  of ~512 pt (896) or ~388 pt (736), and the title two 40 pt lines: they fit with room to
  spare at both sizes. In lyrics mode and the mini player too.

### Playlist or album detail (added on 2026-11-17)

- ✅ **Attribution and link back**: the logo and "OPEN IN SPOTIFY ↗" (*ABRIR EN SPOTIFY ↗*)
  in the top row open the playlist or album in Spotify; on someone else's playlist, "View in
  Spotify" (*Ver en Spotify*) too. Long-pressing a song offers "Open in Spotify" (*Abrir en
  Spotify*) with the song's page.
- ✅ **Artwork**: 150×150, `.fit`, radius 4, nothing on top; "Play" (*Reproducir*) goes
  below.
- ✅ **Explicit**: the list marks songs with `explicit: true` with an "E".
- ✅ **Readable truncated names**: the name and subtitle in the left column use the marquee;
  in the list, long-pressing a song shows the full title and artists. VoiceOver reads
  everything.
- ⚠️ **25 characters for the playlist or album name**: the 170 pt column at 18 pt bold leaves
  about 17 visible characters. Same case as the cards: it can be read in full with the
  marquee, but there's no *visible* room for 25. Moving it to two lines doesn't fit in the
  block's 252 pt together with "Play".
- ✅ **23 song characters and 18 artist characters** in the list: the title has about 510 pt
  at 896 and about 350 at 736.
- ⚠️ **Maximum of 20 items per row**: it was interpreted as not applying to the song list,
  which isn't a content row but the content of a playlist or album. It's loaded in full, 50
  at a time. Proposed to the owner on 2026-11-17, awaiting confirmation. The alternative is
  to cut at 20 and end with "See all in Spotify" (*Ver todo en Spotify*).

### Controls

- ✅ Whatever `actions.disallows` forbids is shown **disabled** (dimmed and with no action),
  and everything is disabled on a device with `is_restricted`. See `docs/en/03`,
  "`actions`": the owner still needs to confirm with a real response that `disallows` arrives.
- ✅ Seeking from the bar and from the lyrics (owner's request, 2026-11-18): only when
  `actions.disallows` doesn't forbid `seeking` and the device doesn't have `is_restricted`,
  same as −15 s and +15 s. Web API commands already require Premium, and the guideline's rule
  about "information only" progress is in the section on Spotify Free restricted actions.
  Where seeking isn't allowed, the bar stays as before: no knob or dragging, VoiceOver reads
  it as "Progress, 1:25 of 3:47" (*Progreso, 1:25 de 3:47*) with no adjust action, and the
  lyrics don't take the finger. Tapping the time on the right only toggles between the
  duration and the time left (owner's decision of 2026-11-18): it doesn't seek forward or
  back.

### Podcasts

- ✅ Episodes: episode title and podcast name (in place of the artist).
- ✅ −15 s and +15 s instead of Previous and Next.

### Player background

- ✅ Color taken from the artwork and softened; with no artwork (or if Settings chooses
  Black or Dark gray), the theme's background, which is dark.

### Content rows

- ✅ At most 20 items per row (`LibraryModel.rowLimit`), and each row ends with the
  "See more in Spotify" (*Ver más en Spotify*) card.

### Explicit

- ✅ "E" mark in the Player and in the mini player. Fixed in this milestone: it was missing
  in lyrics mode (bottom row).
- ✅ Library cards (playlists, albums, podcasts, audiobooks) don't have the `explicit` mark
  in the API, so it doesn't apply. Search results don't have a screen yet.

### Nowdeck name and logo

- ✅ Visible name "Nowdeck" (`CFBundleDisplayName`), with no "Spotify" or anything similar.
- ⚠️ **App icon**: `AppIcon` doesn't have an image yet. When it's made: no green circle and
  no waves.

### Policy

- ✅ No voice control, analytics, or backend; Spotify content isn't stored for metrics or
  used to train anything.
- ✅ "Independent open source project, not affiliated with Spotify" notice on the Welcome
  screen and in the README.
- ✅ Original design: it doesn't copy screens from Spotify or from the Car Thing.

### Gray areas

- ✅ Documented in the README (own Client ID, lyrics from LRCLIB).
- ✅ **Lyrics on by default**: this guide and `docs/en/04` asked for the lyrics feature to
  start **off**, but `docs/en/05` defines that the default theme includes `"letras"` in
  `reproductor.controles`, so the lyrics button appears on a fresh install and in the four
  preset themes. The owner decided on 2026-11-18 to leave it that way: lyrics start on and can
  be turned off in Settings → Player → "Show lyrics" (*Mostrar letras*). The README and the
  Settings note explain where they come from.

### Other related items pending for the owner

- ⚠️ `play: true` when transferring playback (`docs/en/03`, "Devices"): it stays as is until
  the owner decides.
- ⚠️ The alternative document type `public.json` for opening themes: unchanged, pending.
- ⚠️ GitHub username in the LRCLIB User-Agent (`<usuario>` in `LRCLIBClient.projectURL`).
