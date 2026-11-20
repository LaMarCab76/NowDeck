# Design · Nowdeck mockups

> English translation of [`design/README.md`](README.md). The Spanish version is the source of truth; if they differ, it wins.

These files are the **sources** of the mockups made on Claude's design canvas. They are HTML
with inline styles and **don't open on their own** in a browser, because they depend on the
canvas runtime (`support.js`, which isn't included). They serve as a reference for exact
values: colors, sizes, margins, radii, text and states.

| File | Screen |
|---|---|
| `Main.dc.html` | Playback. Includes lyrics mode, the volume panel and the toast, depending on its state |
| `Letras.dc.html` / `LetrasEstrofa.dc.html` | Lyrics mode word by word and by verse |
| `SinLetra.dc.html` | "No lyrics found" notice (*No encontramos la letra*) |
| `Volumen.dc.html` | Volume panel visible (replaced by `VolumenLateral.html`) |
| `VolumenLateral.html` | Volume bar that opens sideways from the speaker, interactive. Made by hand on 2026-11-18 and approved by the owner; it can be viewed in a browser without `support.js` |
| `Biblioteca.dc.html` | Library and Search, with filters and mini player |
| `Detalle.dc.html` | Detail of a playlist or an album: your own, an album, and someone else's playlist |
| `Dispositivos.dc.html` | Devices sheet and help |
| `cola-integrada.html` | Queue inside the player, with a toggle back to the large cover. Interactive in a browser |
| `Cola.html` | Historical reference for the queue sheet |
| `Ajustes.dc.html` / `AjustesReproductor.dc.html` | Settings: Appearance and Player |
| `TemaImportar.dc.html` | Import theme |
| `SinReproduccion.dc.html` | Nothing playing (*Nada sonando*) |
| `Onboarding1-3.dc.html` | First launch, in portrait |
| `canvas.json` | Canvas layout and the size of each screen |

Notes:
- The artwork, the names of songs, playlists and artists, and the sample lyrics are
  **made up**, placeholder content.
- "LOGO SPOTIFY" is a **placeholder**: the official Spotify asset goes there.
- The Space Grotesk and IBM Plex Mono fonts are an approximation in the mockup. iOS uses the
  system font (see `docs/en/02-design.md`).
- The values marked as *tweaks* in the `data-props` block (for example `fondo`, `accent` and
  `anchoLetras`) are design variants, and in the app they become user settings.
