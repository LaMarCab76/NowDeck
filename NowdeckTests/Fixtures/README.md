# Fixtures

Respuestas de ejemplo para los tests de decodificación. No hay tokens ni datos de cuentas
reales.

| Archivo | Origen |
|---|---|
| `playback-state-reference.json` | Ejemplo de respuesta de *Get Playback State* (`GET /me/player`), copiado tal cual de developer.spotify.com el 2026-11-17 |
| `episode-reference.json` | Ejemplo de respuesta de *Get Episode* (`GET /episodes/{id}`), copiado tal cual de developer.spotify.com el 2026-11-17. Los tests lo meten como `item` de un estado de reproducción, porque la referencia de `GET /me/player` no trae ejemplo de episodio |
| `playback-state-playing.json` | Armado a mano con la forma de la referencia y valores realistas: playlist como contexto, `repeat_state` válido y `actions.disallows` (la forma que documenta `docs/03-spotify-api.md`) |
| `devices-reference.json` | Ejemplo de respuesta de *Get Available Devices* (`GET /me/player/devices`), copiado de developer.spotify.com el 2026-11-17 (mismos valores, con sangría) |
