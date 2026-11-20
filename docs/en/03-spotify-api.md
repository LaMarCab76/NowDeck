# 03 · Spotify Web API

> English translation of [`docs/03-spotify-api.md`](../03-spotify-api.md). The Spanish version is the source of truth; if they differ, it wins.

> The API changed several times between November 2024 and July 2026. Everything marked
> **[VERIFY]** must be confirmed on developer.spotify.com before implementing it. If an
> endpoint isn't available in *Development Mode*, say so and propose an alternative. Don't
> replace it silently.

## Quota context (as of November 2026)

- New apps start in **Development Mode**: the owner needs Spotify **Premium**, there are
  **up to 5 users** on the allowlist, and the quota is counted **per developer account**. When
  it's exceeded, the API responds `429` with the reason `QUOTA_EXCEEDED`.
- That's why each Nowdeck user uses **their own Client ID**, adds themselves as the only
  user, and has their own quota.
- Users who aren't on the allowlist can sign in, but get `403` on calls. Show a message that
  explains it, because it's the most likely error if someone set up their app incorrectly.
- **Verified (2026-11-17, "Quota modes" and the Feb 2026 migration guide)**: "API requests
  with an access token associated to that user and app will receive a 403 status code
  error". If the owner's Premium expires, "the app will stop working". The Feb 2026 changes
  apply to all apps in Development Mode (new ones since Feb 11, 2026, existing ones since
  Mar 9, 2026). The quota groups endpoints into *buckets* with no published numbers.

## Authentication: Authorization Code with PKCE

No Client Secret. Redirect URI: **`nowdeck://callback`**, registered as a URL scheme in
`Info.plist` and in the user's app dashboard. Spotify recommends HTTPS or Universal Links,
but still accepts custom schemes.

1. Generate a random `code_verifier` of 43 to 128 characters
   (`[A-Za-z0-9-._~]`, using `SecRandomCopyBytes`) and the
   `code_challenge = BASE64URL(SHA256(verifier))`, without padding.
2. Open `ASWebAuthenticationSession` with:
   ```
   GET https://accounts.spotify.com/authorize
     ?client_id=<CLIENT_ID>
     &response_type=code
     &redirect_uri=nowdeck://callback
     &code_challenge_method=S256
     &code_challenge=<challenge>
     &state=<random>
     &scope=<space-separated scopes>
   ```
   Use `prefersEphemeralWebBrowserSession = false`, to take advantage of the browser's
   Spotify session.
3. Validate `state`. Exchange the code:
   ```
   POST https://accounts.spotify.com/api/token
   Content-Type: application/x-www-form-urlencoded
   grant_type=authorization_code&code=<code>&redirect_uri=nowdeck://callback
   &client_id=<CLIENT_ID>&code_verifier=<verifier>
   ```
4. **Refresh**: `grant_type=refresh_token&refresh_token=<rt>&client_id=<CLIENT_ID>`. If the
   response includes a new `refresh_token`, **replace the stored one**. Refresh about 60 s
   before the `access_token` expires. Only one refresh at a time (actor), even if several
   calls are waiting.
5. On `invalid_grant`: delete the tokens and go back to the Client ID screen with a message.
   **Verified (Nov 2026, "Refreshing tokens")**: refresh tokens for dashboard apps last
   **6 months** from the original authorization; refreshing doesn't extend them. After 6
   months the user connects again.
6. **Check access** after sign-in with `GET /me/player` (scope
   `user-read-playback-state`, which we already request). A `403` there means the account
   isn't in the app's *User Management*. `GET /me` isn't used because its reference lists
   scopes we don't request (`user-read-private`, `user-read-email`). Spotify doesn't document
   the body of that `403`.

Everything is stored in the **Keychain** (`kSecClassGenericPassword`, accessible after first
unlock). What's stored in the Keychain survives uninstalling the app, and it's left that way:
on reinstall, the app starts with the previous session. If Spotify rejects it on the first
refresh, it's deleted and the app goes back to setup:

- `invalid_grant` (the refresh token expired or was revoked): the tokens are deleted and the
  app goes back to the Client ID step with the ID filled in.
- `invalid_client` (for example, the app was deleted in the dashboard): the tokens and the
  Client ID are deleted, and the app goes back to the Client ID step with the field empty.

### Scopes

| Scope | What for |
|---|---|
| `user-read-playback-state` | Player state and Connect devices |
| `user-modify-playback-state` | Play, pause, skip, volume, shuffle, repeat, transfer |
| `user-read-currently-playing` | What's playing now |
| `playlist-read-private` | The user's private playlists |
| `playlist-read-collaborative` | Collaborative playlists in the list |
| `user-library-read` | Saved albums, podcasts and audiobooks. **Verified (2026-11-17)**: it's the only scope listed by `GET /me/albums`, `GET /me/shows` and `GET /me/audiobooks` |
| `user-read-playback-position` | Position in podcast episodes |
| `playlist-modify-public` · `playlist-modify-private` | Add the playing song to one of the user's own or collaborative playlists (since 2026-11-18). "Write access to a user's public/private playlists". Earlier sessions don't have them: the sheet detects this from the `scope` stored with the tokens (if no `scope` is stored, after a `403` when adding) and offers "Allow" (*Dar permiso*), which repeats the sign-in with the stored Client ID without leaving the player. The new tokens are stored only if `GET /me` returns the same user as the current session: a different account is rejected |
| `user-read-recently-played` | Last song played, for the sample photo in the background preview in Settings (since 2026-11-18). Earlier sessions don't have it until they connect again: in the meantime `GET /me/player/recently-played` responds `403` and the app uses what it saw playing |

Request only these. On first launch they're explained in plain words.

## Endpoints by feature

Base: `https://api.spotify.com/v1`. Header: `Authorization: Bearer <token>`.

| Feature | Endpoint | Notes |
|---|---|---|
| Player state | `GET /me/player?additional_types=episode` | `204` = nothing is playing → "Nothing playing" (*Nada sonando*). Returns `device`, `progress_ms`, `is_playing`, `item`, `shuffle_state`, `repeat_state`, `context`, `currently_playing_type` and `actions`. **Verified (2026-11-17)**: still available, scope `user-read-playback-state`, responses 200/204/401/403/429. `additional_types` "might be deprecated in the future". See the note about `actions` below |
| Devices | `GET /me/player/devices` | **Verified (2026-11-17)**: still available (it's in "Endpoints still available" from Feb 2026; the May 2026 and Jul 2026 changelogs don't touch it), scope `user-read-playback-state`, responses 200/401/403/429. See "Devices" below |
| Transfer | `PUT /me/player` with body `{"device_ids":["<id>"],"play":true}` | **Verified (2026-11-17)**: still available (same sources), scope `user-modify-playback-state`, Premium only, responses 204/401/403/429. See "Devices" below |
| Play / resume | `PUT /me/player/play` with optional body `context_uri` or `uris` and optional `device_id` | To play a Library card. **Verified (2026-11-17)**: scope `user-modify-playback-state`, Premium only. Without `device_id` it targets the active device. "Valid contexts are albums, artists & playlists": podcasts and audiobooks are **not** documented as `context_uri`, so those cards open the content in Spotify. The reference lists 204/401/403/429; with no active device the API responds `404` (treated as "No active device") |
| Pause | `PUT /me/player/pause` | |
| Next / previous | `POST /me/player/next` · `POST /me/player/previous` | |
| Volume | `PUT /me/player/volume?volume_percent=0..100` | Group the taps: send just one ~250 ms after the last one |
| Shuffle | `PUT /me/player/shuffle?state=true\|false` | |
| Repeat | `PUT /me/player/repeat?state=off\|context\|track` | |
| Queue | `GET /me/player/queue` | **Verified (2026-11-17)**: it's in "Endpoints still available" → Player in the Feb 2026 changelog ("Retrieves the current playback queue"); the May 2026 and Jul 2026 ones don't touch it; no deprecation note. Scopes `user-read-currently-playing` and `user-read-playback-state` (already requested). Responses 200/401/403/429. Returns `currently_playing` ("Can be `null`") and `queue` ("The tracks or episodes in the queue. Can be empty"), with songs or episodes; it mixes what was added by hand and what comes next from the context without telling them apart. The reference doesn't state a maximum number of items; the app shows up to 20 (docs/en/06). There are no endpoints to remove, reorder or skip to an item: the queue can't be edited from the app. `POST /me/player/queue?uri=…` (add, `user-modify-playback-state`, Premium only, 204/401/403/429) is also still available, but the app doesn't use it yet |
| Skip ±15 s (episodes), drag the bar, tap a verse | `PUT /me/player/seek?position_ms=…` | "Must be a positive number". Going past the duration "will cause the player to start playing the next song": the app clamps it to the duration |
| Source ("Playing from…" (*Reproduciendo desde…*)) | `context.type` and `context.uri` from the state. Playlist: `GET /playlists/{id}?fields=name`. Album, artist and podcast: the name comes from the `item` itself when its URI matches the context's, with no extra request | **Verified (2026-11-17)**: `GET /playlists/{id}` is in "Endpoints still available" in the Feb 2026 changelog. For other people's playlists it returns only metadata (no `items`), and `name` is among them. Supports `fields`. The reference lists no scope. If it responds `403`/`404` (for example, Spotify's editorial or algorithmic playlists, which since Nov 2024 aren't available to new apps; this last point hasn't been re-verified), "Spotify playlist" (*Playlist de Spotify*) is shown and it isn't requested again. Spotify radios arrive like this: `context.type` is `playlist` and the name request returns `404`. `GET /albums/{id}` is still available, but isn't needed |
| Play a song from the queue (tap it and confirm) | `PUT /me/player/play` | **Verified (2026-11-18)**: still in "Endpoints still available" (Player) in the Feb 2026 changelog, no deprecation note; scope `user-modify-playback-state`, Premium only, 204/401/403/429. Since there is no "skip to an item", the app does this: if the current context is an **album or a playlist** (the reference says `offset` is "Only available when context_uri corresponds to an album or playlist object"), it sends `{"context_uri": <context>, "offset": {"uri": <song>}}`, so the rest of the album or playlist follows. Without a context, or with another type (artist, Liked Songs), it sends `{"uris": [<song>]}`: only that song plays and the context is lost. **[VERIFY]** The reference doesn't say what happens if `offset.uri` isn't in the context (for example, a song added to the queue by hand): the app assumes it answers `400` or `404` and then retries with `uris`. If Spotify instead started the context from the beginning, this would need to change. A `404` on the second request means "no active device". Episodes and local files aren't played from the queue (`uris` is documented for songs only). Neither request is retried automatically |
| Next in the queue (swipe from the edge) | `GET /me/player/queue` | **Verified (2026-11-17)**: in "Endpoints still available" (Player) in the Feb 2026 changelog; scopes `user-read-currently-playing` and `user-read-playback-state`, which are already requested. It's read once per new item and again when a swipe starts if the last read is more than 15 s old. Only the first item is used. If it fails, the card stays generic and the swipe works anyway. The previous item doesn't come from the API: it's the one the app saw playing before (up to 20) |
| Artist photo (player background) | `GET /artists/{id}` | **Verified (2026-11-17)**: it's in "Endpoints still available" (Metadata) in the Feb 2026 changelog, which only removed `followers` and `popularity` from artists; `images` remains ("Images of the artist in various sizes, widest first"). The reference lists no scope. It's requested once per artist while the app is open (`404`/`403`: not requested again; other errors: retried after a minute). It's only requested with the "Artist photo" (*Foto del artista*) background. The reference warns: "Spotify visual content must be kept in its original form, e.g. you can not crop…" (see `docs/en/06`, "Gray areas") |
| Last song played (background preview in Settings) | `GET /me/player/recently-played?limit=1` | **Verified (2026-11-18)**: in "Endpoints still available" (Player) in the Feb 2026 changelog; the Development Mode migration guide doesn't restrict it. Scope `user-read-recently-played`; `limit` 1–50 (default 20); items `{track, played_at, context}`; "Currently doesn't support podcast episodes"; responses 200/401/403/429. It's requested when the Blur (*Desenfoque*) and Dim (*Oscurecer*) sliders appear ("Artist photo" background), once per opening of Settings, and canceled when Settings closes. If no photo was found, it's tried again when the sliders reappear (another Settings tab and back) or when one is touched. It isn't requested while there's a usable sample photo (the one of the last artist played); if it stops being usable because another artist with no photo yet is playing, it can be requested again in the same visit. Like any read, it can be retried on server errors and respects the wait of a `429`. It's followed by `GET /artists/{id}` for that song's artist, only if the app hasn't played anything yet in the session or if it's the same artist it played last (the history may lag behind); otherwise, the photo of the last artist the app saw playing is fetched. The March, May and July 2026 changelogs weren't checked for this endpoint |
| Add to a playlist | `POST /playlists/{id}/items` with body `{"uris":["spotify:track:…"]}` | **Verified (2026-11-18)**: `[ADDED]` in the Feb 2026 changelog, which marks `POST /playlists/{id}/tracks` as `[REMOVED]`; the Mar, May and Jul 2026 ones don't touch it. Scopes `playlist-modify-public` and `playlist-modify-private`. Accepts "track or episode URIs", up to 100 per request; without `position` they're added at the end. Responses 201 (with `snapshot_id`), 401, 403, 429. The app sends a single URI and **doesn't retry it** on `5xx` or with no network (it could duplicate it); the only resend is after a `401` with the refreshed token, which Spotify rejected before writing. The editable playlists come from `GET /me/playlists` (all pages, 50 at a time, up to 50 pages): the user's own (`owner.id` equal to the one from `GET /me`) or with `collaborative: true`. The list is reused for 5 minutes. **Where the song already is** (2026-11-18): no endpoint answers it, so each editable playlist is read with `GET /playlists/{id}/items` (50 at a time, up to 200 pages, 3 at once; empty ones aren't requested) and its URIs are kept with the `snapshot_id` from `GET /me/playlists` (verified on 2026-11-18: "The version identifier for the current playlist"). Afterwards only the ones whose `snapshot_id` changed are read again. When adding, the song is added to what's kept, but the `snapshot_id` returned by the `POST` isn't taken (it could include changes made elsewhere): the next read of the list reads that playlist again. The cache lives while the app is open. `fields` isn't used: its examples say `track` and the schema says `item`. `DELETE /playlists/{id}/items` exists, but it identifies items only by `uri` and doesn't document what happens with earlier copies of the same song: the app doesn't offer removing. The Development Mode guide mentions no restrictions for this endpoint; it still needs testing with a real account |
| Playlists | `GET /me/playlists?limit=…&offset=…` | **Verified (2026-11-17)**: scope `playlist-read-private`; `limit` 1–50 (default 20), `offset` up to 100,000. The song count moved from `tracks.total` to `items.total` (`tracks` is listed as *deprecated*); the model reads `items` and, if it's missing, `tracks` |
| Saved albums | `GET /me/albums` | Read listed in "Endpoints still available" (Feb 2026, checked 2026-11-17). What was removed are the writes (`PUT`/`DELETE`, replaced by `/me/library`) and the `contains` endpoints. **Verified (2026-11-17)**: scope `user-library-read`; `limit` 1–50 (default 20), `offset`; items `{added_at, album}`; optional `market` (with a user token it sends the account's country). The reference still shows `label`, `popularity` and `available_markets` as *deprecated*; the Feb 2026 changelog treats them as removed and they aren't decoded |
| Album songs (detail) | `GET /albums/{id}/tracks?limit=50&offset=…` | **Verified (2026-11-17)**: in "Endpoints still available" (Metadata) in the Feb 2026 changelog; `limit` 1–50 (default 20), `offset`. Simplified tracks include `artists`, `duration_ms`, `explicit`, `is_local`, `restrictions` and `is_playable`; the latter is "Part of the response when Track Relinking is applied", that is, only with `market`. The app does **not** send `market`: the reference only documents country codes (not `from_token`) and says the account's country "will take priority over this parameter". A song is dimmed if it's local, if `is_playable` is `false` or if it includes `restrictions` |
| Playlist songs (detail) | `GET /playlists/{id}/items?limit=50&offset=…&additional_types=track,episode` | **Verified (2026-11-17)**: added in Feb 2026; `GET /playlists/{id}/tracks` was **removed**. Scope `playlist-read-private`; `limit` 1–50. "This endpoint is only accessible for playlists owned by the current user or playlists the user is a collaborator of. A 403 Forbidden status code will be returned if the user is neither the owner nor a collaborator": the app shows it as "Spotify doesn't show this playlist's songs" (*Spotify no muestra los temas de esta playlist*) and still lets you play it. Each item is `{added_at, added_by, is_local, item}`; `track` still carries the same thing but "Deprecated: Use `item` instead" (the app reads both). `fields` isn't used: the names changed in Feb 2026 and a filter with the old name would return empty items |
| Saved podcasts | `GET /me/shows` | Read available, same as the previous one. `show.publisher` and `available_markets` were removed. **Verified (2026-11-17)**: scope `user-library-read`; `limit` 1–50, `offset`; items `{added_at, show}` with `total_episodes`. Since there's no `publisher`, the card says "Podcast · N episodes" (*Podcast · N episodios*) |
| Saved audiobooks | `GET /me/audiobooks` | Read available, same as the previous one. **Verified (2026-11-17)**: scope `user-library-read`; `limit` 1–50, `offset`; items come **without** a wrapper (`authors`, `narrators`, `total_chapters`). "Audiobooks are only available within the US, UK, Canada, Ireland, New Zealand and Australia markets" (*Get an Audiobook* and *Search* references). Since `GET /me` no longer returns `country`, the Audiobooks (*Audiolibros*) filter is shown only if this request returns at least one audiobook |
| Search | `GET /search?q=…&type=track,album,playlist,show,audiobook&limit=10` | Since Feb 2026, in Development Mode the **maximum limit is 10** (default 5). Paginate with `offset`. **Verified (2026-11-17)**: `type` accepts `album`, `artist`, `playlist`, `track`, `show`, `episode` and `audiobook`; `limit` 0–10, `offset` 0–1000; the reference lists no scope. The `+` in the query is sent as `%2B` (otherwise it arrives as a space). The results screen is still pending design: the request and its model are done, the UI doesn't call it yet |

**Verified (2026-11-17), playback commands** (play, pause, next, previous, volume, shuffle,
repeat and seek): they're still in the "Endpoints still available" → Player list in the Feb
2026 changelog, with no deprecation note; scope `user-modify-playback-state`; documented
responses 204, 401, 403 and 429 (only 204 has a description); `device_id` is optional on all
of them ("If not supplied, the user's currently active device is the target"), and the app
doesn't send it. Each page says "The order of execution is not guaranteed when you use this
API with other Player API endpoints": that's why the app sends commands one at a time, in the
order they were tapped.

Playback commands require **Premium**. **Verified (2026-11-17)**: Spotify no longer
documents the `PREMIUM_REQUIRED` reason. The documented error body is
`{"error": {"status", "message", "reason"?}}` and the only `reason` listed is `QUOTA_EXCEEDED`.
That's why a `403` is always handled the same way (not on the allowlist, the owner's or the
user's Premium expired) and shown with a message with instructions.

### Devices (milestone 4)

Verified on developer.spotify.com on 2026-11-17 (*Get Available Devices* and *Transfer
Playback* references, and the Feb 2026, May 2026 and Jul 2026 changelogs):

- `GET /me/player/devices` returns `{"devices": [...]}`. Each device has `id` (can be
  `null`; "any cached `device_id` should periodically be cleared out and refetched"),
  `is_active`, `is_private_session`, `is_restricted`, `name`, `type`, `volume_percent` (can
  be `null`) and `supports_volume`. The reference lists no other fields.
- `type` is only documented with examples ("computer", "smartphone", "speaker"), with no
  closed list, and the capitalization varies. The app compares case-insensitively and uses a
  generic name ("Device" (*Dispositivo*)) for types it doesn't know.
- `is_restricted: true`: "no Web API commands will be accepted by this device". The sheet
  shows it dimmed, with "No remote control" (*No admite control remoto*), and it can't be
  tapped. A device without an `id` is treated the same way, because it can't be named in the
  transfer.
- The reference only says that "some device models are not supported and will not be listed".
  It doesn't document that the list is limited to active or awake devices: that's what's seen
  in practice and what the sheet's help explains.
- `PUT /me/player`: `device_ids` is required and accepts **a single** ID ("Supplying more than
  one will return `400 Bad Request`"). `play: true` "ensure playback happens on new device";
  `false` or absent "keep the current playback state". The app sends `play: true`, as this
  document said, so that "Choose device" (*Elegir dispositivo*) from "Nothing playing"
  (*Nada sonando*) also starts the music. "The order of execution is not guaranteed when you
  use this API with other Player API endpoints": that's why, after transferring, the app
  queries `GET /me/player` again after ~600 ms instead of assuming the result.
- The reference doesn't document a `404` for the transfer. If one arrives (for example, the
  device went to sleep after the list loaded), the sheet shows a notice and requests the list
  again.
- Sheet errors: `403` with a generic message (Premium or *User Management*, like the rest of
  the app); `429` respected by the client (it doesn't go to the network until `Retry-After`
  has passed); with no network or `5xx`, a notice, and the previous list stays on screen. The
  transfer, like every command, isn't retried automatically on `5xx` or with no network (it's
  only resent once after a `401`, with the refreshed token; see "Errors").

### `actions` (reviewed in milestone 3, 2026-11-17)

What the current *Get Playback State* reference
(`/reference/get-information-about-the-users-current-playback`) says:

- `actions`: "Allows to update the user interface based on which playback actions are
  available within the current context".
- It lists the ten booleans (`interrupting_playback`, `pausing`, `resuming`, `seeking`,
  `skipping_next`, `skipping_prev`, `toggling_repeat_context`, `toggling_shuffle`,
  `toggling_repeat_track`, `transferring_playback`) **directly** inside `actions`, each one
  as an "Optional field", **without `disallows`**.
- It **doesn't say** whether `true` means allowed or forbidden. The example has all ten set to
  `false`, which doesn't clarify it. The Feb, Mar, May and Jul 2026 changelogs don't mention
  any change to `actions`.
- A real response couldn't be inspected: there's no connected account in this environment.

Decision (the conservative one):

- **Only** the form with `disallows` is interpreted
  (`"actions": {"disallows": {"resuming": true}}`): `true` = **forbidden**, and anything
  missing = allowed. It's the form of the known real responses. Before this change, the
  reference named that object `DisallowsObject` and listed the same booleans without the
  wrapper (this last point is from memory; it couldn't be re-verified). Everything suggests the
  reference shows the contents of `disallows`.
- The loose booleans are stored (`PlaybackActions.flatFlags`) but **don't disable anything**:
  if `true` meant "available", reading them as a prohibition would leave the app without
  controls. If a forbidden action that wasn't disabled is sent, Spotify responds with an
  error, the app reverts the optimistic change and shows the generic notice.
- A device with `is_restricted: true` ("no Web API commands will be accepted by this
  device") disables all controls.
- **Pending for the owner**: look at a real `GET /me/player` response (for example during an
  ad or with a song that doesn't allow going back) to confirm that `disallows` arrives.

### Fields removed in Development Mode (Feb 2026 changelog)

- Track: `available_markets`, `linked_from`, `popularity`. `external_ids` was removed and came
  back in March 2026.
- Album: `album_group`, `available_markets`, `label`, `popularity`.
- Artist: `followers`, `popularity`.
- Show: `available_markets`, `publisher`.
- `GET /me`: `country`, `email`, `explicit_content`, `followers`, `product`.

The models don't decode any of these fields.

## Polling and local state

The Web API has no push notifications for the state, so it has to be polled.

- **Playing, app in the foreground**: `GET /me/player` every **3 s**. Between polls, the
  progress is **interpolated** locally with `Date()` and `progress_ms`. The local time when
  the response arrived is used, not the `timestamp` field: according to the reference, that
  field marks when the state *changed* and uses Spotify's clock.
- **Paused or nothing playing**: every **10 s**.
- **After `QUOTA_EXCEEDED`**: for 15 minutes, every 10 s while playing and every 30 s while
  paused (`PollingPolicy`).
- **After a network error or `5xx`**: exponential backoff of 3, 6, 12… up to 60 s.
- **After a `403`**: every 30 s, so the app recovers on its own if the owner fixes the user
  list.
- **App in the background**: stop polling.
- **Another screen covers the player**: polling continues while Library is open so the mini
  player stays current. With Devices, it stops until the user comes back.
- **Queue**: opens inside the player and follows playback polling. The app reads the list
  on opening, on refresh, and when a song starts.
- **After a command**: update the UI **optimistically** and poll again after ~600 ms to
  confirm. While the command is in flight, polling is paused (a response read before the
  command would overwrite the optimistic change). If it fails, the change is reverted and the
  state is polled again right away.
- **Volume**: after changing it from the app, polls may return the old value for a while.
  They're ignored for 3 s after the request (or until the requested value arrives).
- **Song change** (different `item.id`): recompute the background color and fetch the lyrics
  if lyrics mode is on.
- **Volume change** compared to the last known value, and not caused by the app: show the
  volume panel.

## Errors

| Code | Action |
|---|---|
| `401` | Refresh the token and retry **once** |
| `403` | User not on the allowlist or without Premium: message with instructions |
| `404` "No active device" | Open Devices or show "Nothing playing" (*Nada sonando*) |
| `429` | Respect `Retry-After` (plus a bit of *jitter*). If the reason is `QUOTA_EXCEEDED`, lower the polling frequency and show a discreet notice |
| `5xx` or no network | Retry with exponential backoff; keep the last state visible and mark it as stale |

**Verified (2026-11-17, "Rate limits" and "API calls")**:

- The limit is calculated over a rolling 30 s window.
- `Retry-After` is in **seconds**.
- The Development Mode quota "has a different enforcement mechanism than rate limits" and
  responds `429` with `"reason": "QUOTA_EXCEEDED"`.

How `SpotifyAPI` handles it:

- On a `429`, it remembers until when to wait and, in the meantime, fails without going to
  the network.
- On a `5xx`, it retries only `GET`s, twice, after 0.5 s and after 1.5 s plus *jitter*.
- Commands (PUT/POST, including adding to a playlist) aren't retried automatically on a
  `5xx` or with no network: repeating "next" could skip two songs, and repeating an add could
  duplicate it. The only exception is the `401`: like any request, it's resent **once** with
  the refreshed token, because Spotify rejected it before executing it.

## Models

`Codable` with `snake_case` (`keyDecodingStrategy = .convertFromSnakeCase`). Optional fields
where the API may omit them: `item` is `nil` during ads and with local content, and
`device.volume_percent` may be missing. Podcast episodes use `show` instead of `album` and
`artists`.
