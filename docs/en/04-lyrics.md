# 04 · Lyrics (LRCLIB)

> English translation of [`docs/04-letras.md`](../04-letras.md). The Spanish version is the source of truth; if they differ, it wins.

Spotify does **not** offer lyrics in its Web API. The libraries that pull them from Spotify use an
internal endpoint with the user's session cookie: **do not use them**, because they violate the
terms and expose credentials.

The source is **LRCLIB** (`https://lrclib.net`), an open, community database. Documentation:
`https://lrclib.net/docs.txt`.

## Turning it on

- The option lives in Settings → Player → "Show lyrics" (*Mostrar letras*). If it's off, the
  lyrics button doesn't appear in the player.
- Tapping the button looks up the lyrics for the current song. If the song changes while the
  mode is on, the new one is looked up.

## Request

```
GET https://lrclib.net/api/get
  ?track_name=<title>
  &artist_name=<first artist>
  &album_name=<album>
  &duration=<seconds, integer>
User-Agent: Nowdeck/<version> (https://github.com/<usuario>/Nowdeck)
```

- The duration has to match within **±2 s**, and it's worth including the album to narrow it down.
- **Identified User-Agent** (name, version, and URL or email): raises the limit from ~45 to ~90
  requests per minute per IP. LRCLIB also offers registering the app (`Lrclib-App-Id`); that's
  left for later.
- On `429` (and `503`): honor `Retry-After` with up to 30% *jitter*.
- On-disk **cache** keyed by Spotify's `item.id`, including negative responses (for example
  for 7 days), so songs without lyrics aren't queried again.

### Verified against the LRCLIB documentation (2026-11-17)

Sources: `https://lrclib.net/docs.txt`, `https://lrclib.net/llms.txt`, and the Lyricsfile
specification (`github.com/tranxuanthang/lyricsfile`, `SPECIFICATION.md`, draft 1.0, linked
from LRCLIB as "Lyricsfile format").

- `GET /api/get` is unchanged: `track_name` and `artist_name` are required; `album_name` and
  `duration` are optional but recommended. The duration has to be between **1 and 3600 s**
  (outside that range it's a `400 ValidationError`), so the app doesn't send it if it falls outside.
  With no match it responds `404 TrackNotFound`.
- Record fields: `id`, `name` (old alias of `trackName`), `trackName`, `artistName`,
  `albumName`, `duration` (seconds, may have decimals: `233.0`), `instrumental`,
  `hasWordSync`, `plainLyrics`, `syncedLyrics`, and `lyricsfile` (YAML; the documentation says
  every record has one). Records published with only `plainLyrics` or `syncedLyrics`
  never have `hasWordSync`.
- **User-Agent**: identifying yourself with name, version, and project page or an email is
  required (if the header can't be set, `X-User-Agent` or `Lrclib-Client` work). Approximate
  limits: ~45 requests/min per IP unidentified, ~90 identified, ~180 with
  `Lrclib-App-Id` (optional registration at `lrclib.net/developers`; the ID isn't secret). Nowdeck
  sends `Nowdeck/<version> (https://github.com/<usuario>/Nowdeck)`: the `<usuario>` stays as a
  placeholder until the owner chooses the GitHub user or organization
  (`LRCLIBClient.projectURL`).
- **429**: comes with `Retry-After` in seconds; you have to wait it out with a small *jitter* (the
  docs suggest up to 30%) or LRCLIB may ban you temporarily. **503 `ServerOverloaded`** also
  comes with `Retry-After` (usually 1 s). Rejections from the network edge may not be JSON:
  look at the status code and the header, not the body.
- **Real LRC from LRCLIB**: verses are almost never separated by blank lines but by a
  line with a timestamp and no text (`[00:49.72] `), and the lyrics usually end with one of those.
  The parser treats both forms as a verse break; the empty timestamped line also marks the end of
  the verse (during the instrumental the next one is shown, all in `letraPendiente`).
- **Lyricsfile** (draft 1.0, may change): `version` (must be exactly `"1.0"`;
  the specification says not to treat any other version as 1.0, so the app falls back to LRC),
  `metadata` (`title`, `artist`, `album`, `duration_ms`, `offset_ms`, `language`,
  `instrumental`), `lines[]` with `text`, `start_ms`, optional `end_ms`, and optional `words[]`
  (`text` with the space included, `start_ms`, optional `end_ms`), and `plain`. Everything in
  integer milliseconds. **`offset_ms` is ignored**: the specification says its meaning is not
  defined. In real Lyricsfiles with words there are no empty lines or pauses
  (a line's `end_ms` = the next line's `start_ms`), so lines are grouped in pairs.
- **Verses longer than 2 lines**: they're split into pairs. At 30 pt with 38 line height, the
  lyrics mode area (156 pt on 896×414) fits 3 lines of the current verse and one of the
  next; a 4-line verse doesn't fit. If it still doesn't fit, the text shrinks (down to
  60%) instead of being cut off.

## Which mode to use

| Response | Mode |
|---|---|
| `hasWordSync == true` | **Word by word**: read `lyricsfile` (YAML) → `lines[].words` with timestamps |
| `syncedLyrics` not null | **Whole verse**, using the LRC's per-line timestamps to know which verse we're on |
| Only `plainLyrics`, `instrumental == true`, or 404 | **No lyrics**: "No lyrics found for this song" (*No encontramos la letra de este tema*) notice for 3 s and back to the normal view |

### LRC parser (`syncedLyrics`)

- Each line has the form `[mm:ss.xx] text`. There can be several timestamps on the
  same line (repeated choruses) and metadata like `[ar:…]` or `[offset:+/-ms]`, which
  must be applied.
- **Verses**: they're separated by empty lines in the LRC.
  - If there are no empty lines, group by pauses of more than 4 s between lines or, as a last
    resort, every 2 lines.
  - Current verse = the one containing the last line with a timestamp less than or equal to the
    current position. Next = the one that comes after.

### Lyricsfile (`hasWordSync`)

- It's YAML: parse it with **Yams**. The words are in `lines[].words`, with their timestamps.
  Before writing the parser, check the format specification in the LRCLIB repository
  and don't assume the field names.
- **Highlighting**: words with a timestamp less than or equal to the position go in `texto`; the
  rest, in `letraPendiente`.
- Verses are grouped the same way as in the LRC.

## Syncing with playback

- Position = `progress_ms` from the last poll + the elapsed time, while `is_playing`
  is true. Update the view at ~10 fps in word mode and ~2 fps in verse mode.
- If polling detects a jump of more than 1.5 s compared to the interpolated position (someone
  skipped ahead in the song), resync.
- **Lyrics timing** (*Sincronía de las letras*) (Settings → Player, 2026-11-17): an offset of
  −3 to +3 s in 0.1 s steps that's added to the interpolated position before choosing the verse.
  Positive shows them earlier (for when Spotify's position arrives late or the audio goes over
  Bluetooth). It's stored in `UserDefaults`, not in the theme: it depends on the device and the
  network.

## Notices for the user and the README

- The note in Settings already says that the lyrics come from a community database, not from
  Spotify, and that they may be missing or contain mistakes.
- **Rights**: LRCLIB lyrics are uploaded by users; the rights belong to the publishers.
  That's why the feature is explained in the README and can be turned off in Settings. It starts
  **on**: the owner decided this on 2026-11-18 (see `docs/en/06-compliance.md`).
- Spotify's policy forbids products "integrated with content from another service". Showing
  third-party lyrics alongside playback is a gray area without a clear precedent. It's
  noted in `docs/en/06-compliance.md`.
