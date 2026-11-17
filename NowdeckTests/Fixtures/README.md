# Fixtures

Respuestas de ejemplo para los tests de decodificación. No hay tokens ni datos de cuentas
reales.

| Archivo | Origen |
|---|---|
| `playback-state-reference.json` | Ejemplo de respuesta de *Get Playback State* (`GET /me/player`), copiado tal cual de developer.spotify.com el 2026-11-17 |
| `episode-reference.json` | Ejemplo de respuesta de *Get Episode* (`GET /episodes/{id}`), copiado tal cual de developer.spotify.com el 2026-11-17. Los tests lo meten como `item` de un estado de reproducción, porque la referencia de `GET /me/player` no trae ejemplo de episodio |
| `playback-state-playing.json` | Armado a mano con la forma de la referencia y valores realistas: playlist como contexto, `repeat_state` válido y `actions.disallows` (la forma que documenta `docs/03-spotify-api.md`) |
| `devices-reference.json` | Ejemplo de respuesta de *Get Available Devices* (`GET /me/player/devices`), copiado de developer.spotify.com el 2026-11-17 (mismos valores, con sangría) |
| `playlists-reference.json` | Ejemplo de *Get Current User's Playlists* (`GET /me/playlists`), copiado de developer.spotify.com el 2026-11-17 (solo se quitó el resaltado HTML) |
| `saved-albums-reference.json` | Ejemplo de *Get User's Saved Albums* (`GET /me/albums`), mismo origen y fecha |
| `saved-shows-reference.json` | Ejemplo de *Get User's Saved Shows* (`GET /me/shows`), mismo origen y fecha |
| `saved-audiobooks-reference.json` | Ejemplo de *Get User's Saved Audiobooks* (`GET /me/audiobooks`), mismo origen y fecha |
| `queue-playing.json` | Armado a mano con la forma de *Get the User's Queue* (`GET /me/player/queue`, consultado el 2026-11-17): `currently_playing` y `queue` con un tema, un episodio, un archivo local y un tipo que la app no conoce |
| `search-reference.json` | Ejemplo de *Search for Item* (`GET /search`), mismo origen y fecha |
