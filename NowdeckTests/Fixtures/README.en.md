# Fixtures

> English translation of [`NowdeckTests/Fixtures/README.md`](README.md). The Spanish version is the source of truth; if they differ, it wins.

Sample responses for the decoding tests. They contain no tokens or data from real
accounts.

| File | Source |
|---|---|
| `playback-state-reference.json` | Sample response from *Get Playback State* (`GET /me/player`), copied as is from developer.spotify.com on 2026-11-17 |
| `episode-reference.json` | Sample response from *Get Episode* (`GET /episodes/{id}`), copied as is from developer.spotify.com on 2026-11-17. The tests put it in as the `item` of a playback state, because the `GET /me/player` reference has no episode example |
| `playback-state-playing.json` | Built by hand with the shape of the reference and realistic values: a playlist as context, a valid `repeat_state`, and `actions.disallows` (the shape documented in `docs/en/03-spotify-api.md`) |
| `devices-reference.json` | Sample response from *Get Available Devices* (`GET /me/player/devices`), copied from developer.spotify.com on 2026-11-17 (same values, indented) |
| `playlists-reference.json` | Sample from *Get Current User's Playlists* (`GET /me/playlists`), copied from developer.spotify.com on 2026-11-17 (only the HTML highlighting was removed) |
| `saved-albums-reference.json` | Sample from *Get User's Saved Albums* (`GET /me/albums`), same source and date |
| `saved-shows-reference.json` | Sample from *Get User's Saved Shows* (`GET /me/shows`), same source and date |
| `saved-audiobooks-reference.json` | Sample from *Get User's Saved Audiobooks* (`GET /me/audiobooks`), same source and date |
| `queue-playing.json` | Built by hand with the shape of *Get the User's Queue* (`GET /me/player/queue`, checked on 2026-11-17): `currently_playing` and `queue` with a song, an episode, a local file, and a type the app doesn't know |
| `search-reference.json` | Sample from *Search for Item* (`GET /search`), same source and date |
