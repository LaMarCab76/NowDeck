# 03 · Spotify Web API

> La API cambió varias veces entre noviembre de 2024 y julio de 2026. Todo lo marcado
> **[VERIFICAR]** hay que confirmarlo en developer.spotify.com antes de implementarlo. Si un
> endpoint no está disponible en *Development Mode*, avisá y proponé una alternativa. No lo
> reemplaces en silencio.

## Contexto de cuotas (estado a noviembre de 2026)

- Las apps nuevas arrancan en **Development Mode**: el dueño necesita Spotify **Premium**, hay
  **hasta 5 usuarios** en la lista permitida, y la cuota se cuenta **por cuenta de
  desarrollador**. Al pasarse, la API responde `429` con el motivo `QUOTA_EXCEEDED`.
- Por eso cada usuario de Nowdeck usa **su propio Client ID**, se carga a sí mismo como único
  usuario y tiene su propia cuota.
- Los usuarios que no están en la lista permitida pueden loguearse, pero reciben `403` en las
  llamadas. Mostrá un mensaje que lo explique, porque es el error más probable si alguien
  configuró mal su app.
- **Verificado (2026-11-17, "Quota modes" y guía de migración de feb-2026)**: "API requests
  with an access token associated to that user and app will receive a 403 status code
  error". Si el Premium del dueño vence, "the app will stop working". Los cambios de feb-2026
  rigen para todas las apps en Development Mode (las nuevas desde el 11-feb-2026, las
  existentes desde el 9-mar-2026). La cuota agrupa endpoints en *buckets* sin números
  publicados.

## Autenticación: Authorization Code con PKCE

Sin Client Secret. Redirect URI: **`nowdeck://callback`**, registrado como URL scheme en
`Info.plist` y en el panel de la app del usuario. Spotify recomienda HTTPS o Universal Links,
pero sigue aceptando esquemas propios.

1. Generar un `code_verifier` aleatorio de 43 a 128 caracteres
   (`[A-Za-z0-9-._~]`, usando `SecRandomCopyBytes`) y el
   `code_challenge = BASE64URL(SHA256(verifier))`, sin relleno.
2. Abrir `ASWebAuthenticationSession` con:
   ```
   GET https://accounts.spotify.com/authorize
     ?client_id=<CLIENT_ID>
     &response_type=code
     &redirect_uri=nowdeck://callback
     &code_challenge_method=S256
     &code_challenge=<challenge>
     &state=<aleatorio>
     &scope=<scopes separados por espacio>
   ```
   Usar `prefersEphemeralWebBrowserSession = false`, para aprovechar la sesión de Spotify del
   navegador.
3. Validar `state`. Intercambiar el código:
   ```
   POST https://accounts.spotify.com/api/token
   Content-Type: application/x-www-form-urlencoded
   grant_type=authorization_code&code=<code>&redirect_uri=nowdeck://callback
   &client_id=<CLIENT_ID>&code_verifier=<verifier>
   ```
4. **Refresh**: `grant_type=refresh_token&refresh_token=<rt>&client_id=<CLIENT_ID>`. Si la
   respuesta trae un `refresh_token` nuevo, **reemplazar el guardado**. Refrescar unos 60 s
   antes de que venza el `access_token`. Un solo refresh a la vez (actor), aunque haya varias
   llamadas esperando.
5. Ante `invalid_grant`: borrar los tokens y volver a la pantalla de Client ID con un mensaje.
   **Verificado (nov-2026, "Refreshing tokens")**: los refresh tokens de apps del panel duran
   **6 meses** desde la autorización original; refrescar no los extiende. A los 6 meses el
   usuario vuelve a conectar.
6. **Comprobar el acceso** después del login con `GET /me/player` (scope
   `user-read-playback-state`, que ya pedimos). Un `403` ahí significa que la cuenta no está
   en *Users Management* de la app. No se usa `GET /me` porque su referencia lista scopes
   que no pedimos (`user-read-private`, `user-read-email`). Spotify no documenta el cuerpo de
   ese `403`.

Todo se guarda en el **Llavero** (`kSecClassGenericPassword`, accesible después del primer
desbloqueo). Lo guardado en el Llavero sobrevive a desinstalar la app, y se deja así: al
reinstalar, la app arranca con la sesión anterior. Si Spotify la rechaza en la primera
renovación, se borra y se vuelve a la configuración:

- `invalid_grant` (venció o se revocó el refresh token): se borran los tokens y se vuelve al
  paso del Client ID con el ID cargado.
- `invalid_client` (por ejemplo, la app se borró en el panel): se borran los tokens y el
  Client ID, y se vuelve al paso del Client ID con el campo vacío.

### Scopes

| Scope | Para qué |
|---|---|
| `user-read-playback-state` | Estado del reproductor y dispositivos de Connect |
| `user-modify-playback-state` | Play, pausa, saltar, volumen, aleatorio, repetir, transferir |
| `user-read-currently-playing` | Lo que suena ahora |
| `playlist-read-private` | Playlists privadas del usuario |
| `playlist-read-collaborative` | Playlists colaborativas en el listado |
| `user-library-read` | Álbumes, podcasts y audiolibros guardados. **Verificado (2026-11-17)**: es el único scope que listan `GET /me/albums`, `GET /me/shows` y `GET /me/audiobooks` |
| `user-read-playback-position` | Posición en episodios de podcast |

Pedir solo estos. En el primer inicio se explican en palabras simples.

## Endpoints por funcionalidad

Base: `https://api.spotify.com/v1`. Cabecera: `Authorization: Bearer <token>`.

| Función | Endpoint | Notas |
|---|---|---|
| Estado del reproductor | `GET /me/player?additional_types=episode` | `204` = nada suena → "Nada sonando". Trae `device`, `progress_ms`, `is_playing`, `item`, `shuffle_state`, `repeat_state`, `context`, `currently_playing_type` y `actions`. **Verificado (2026-11-17)**: sigue disponible, scope `user-read-playback-state`, respuestas 200/204/401/403/429. `additional_types` "might be deprecated in the future". Ver la nota sobre `actions` más abajo |
| Dispositivos | `GET /me/player/devices` | Solo los activos o despiertos. `supports_volume` por dispositivo |
| Transferir | `PUT /me/player` con body `{"device_ids":["<id>"],"play":true}` | |
| Play / reanudar | `PUT /me/player/play` con body opcional `context_uri` o `uris` y `device_id` opcional | Para reproducir una tarjeta de la Biblioteca. **Verificado (2026-11-17)**: scope `user-modify-playback-state`, solo Premium. Sin `device_id` apunta al dispositivo activo. "Valid contexts are albums, artists & playlists": podcasts y audiolibros **no** están documentados como `context_uri`, así que esas tarjetas abren el contenido en Spotify. La referencia lista 204/401/403/429; sin dispositivo activo la API responde `404` (se trata como "No active device") |
| Pausa | `PUT /me/player/pause` | |
| Siguiente / anterior | `POST /me/player/next` · `POST /me/player/previous` | |
| Volumen | `PUT /me/player/volume?volume_percent=0..100` | Agrupar los toques: mandar uno solo ~250 ms después del último |
| Aleatorio | `PUT /me/player/shuffle?state=true\|false` | |
| Repetir | `PUT /me/player/repeat?state=off\|context\|track` | |
| Origen ("Desde la playlist…") | `context.type` y `context.uri` del estado. Playlist: `GET /playlists/{id}?fields=name`. Álbum, artista y podcast: el nombre sale del propio `item` cuando su URI coincide con la del contexto, sin pedido extra | **Verificado (2026-11-17)**: `GET /playlists/{id}` figura en "Endpoints still available" del changelog de feb-2026. Para playlists ajenas devuelve solo metadatos (sin `items`), y `name` está entre ellos. Soporta `fields`. La referencia no lista scope. Si responde `403`/`404` (por ejemplo, playlists editoriales o algorítmicas de Spotify, que desde nov-2024 no están disponibles para apps nuevas; esto último no se volvió a verificar), se muestra solo el tipo ("Desde una playlist") y no se vuelve a pedir. `GET /albums/{id}` sigue disponible, pero no hace falta |
| Playlists | `GET /me/playlists?limit=…&offset=…` | **Verificado (2026-11-17)**: scope `playlist-read-private`; `limit` 1–50 (por defecto 20), `offset` hasta 100.000. La cantidad de temas pasó de `tracks.total` a `items.total` (`tracks` figura como *deprecated*); el modelo lee `items` y, si falta, `tracks` |
| Álbumes guardados | `GET /me/albums` | Lectura listada en "Endpoints still available" (feb-2026, consultado 2026-11-17). Lo que se quitó son las escrituras (`PUT`/`DELETE`, reemplazadas por `/me/library`) y los `contains`. **Verificado (2026-11-17)**: scope `user-library-read`; `limit` 1–50 (por defecto 20), `offset`; ítems `{added_at, album}`; `market` opcional (con token de usuario manda el país de la cuenta). La referencia todavía muestra `label`, `popularity` y `available_markets` como *deprecated*; el changelog de feb-2026 los da por quitados y no se decodifican |
| Podcasts guardados | `GET /me/shows` | Lectura disponible, igual que la anterior. `show.publisher` y `available_markets` se quitaron. **Verificado (2026-11-17)**: scope `user-library-read`; `limit` 1–50, `offset`; ítems `{added_at, show}` con `total_episodes`. Como no hay `publisher`, la tarjeta dice "Podcast · N episodios" |
| Audiolibros guardados | `GET /me/audiobooks` | Lectura disponible, igual que la anterior. **Verificado (2026-11-17)**: scope `user-library-read`; `limit` 1–50, `offset`; los ítems vienen **sin** envoltorio (`authors`, `narrators`, `total_chapters`). "Audiobooks are only available within the US, UK, Canada, Ireland, New Zealand and Australia markets" (referencias de *Get an Audiobook* y *Search*). Como `GET /me` ya no trae `country`, el filtro Audiolibros se muestra solo si este pedido devuelve al menos un audiolibro |
| Buscar | `GET /search?q=…&type=track,album,playlist,show,audiobook&limit=10` | Desde feb-2026, en Development Mode el **límite máximo es 10** (por defecto 5). Paginar con `offset`. **Verificado (2026-11-17)**: `type` admite `album`, `artist`, `playlist`, `track`, `show`, `episode` y `audiobook`; `limit` 0–10, `offset` 0–1000; la referencia no lista scope. El `+` de la consulta se manda como `%2B` (si no, llega como espacio). La pantalla de resultados sigue pendiente de diseño: el pedido y su modelo están hechos, la UI no lo llama todavía |

Los comandos de reproducción requieren **Premium**. **Verificado (2026-11-17)**: Spotify ya no
documenta el motivo `PREMIUM_REQUIRED`. El cuerpo de error documentado es
`{"error": {"status", "message", "reason"?}}` y el único `reason` listado es `QUOTA_EXCEEDED`.
Por eso un `403` se trata siempre igual (fuera de la lista permitida, Premium vencido del dueño
o del usuario) y se muestra con un mensaje con instrucciones.

### `actions` **[VERIFICAR en el hito 3 con una respuesta real]**

La referencia actual de *Get Playback State* (consultada el 2026-11-17) lista los diez booleanos
(`interrupting_playback`, `pausing`, `resuming`, `seeking`, `skipping_next`, `skipping_prev`,
`toggling_repeat_context`, `toggling_shuffle`, `toggling_repeat_track`,
`transferring_playback`) **directamente** dentro de `actions`, sin `disallows`, y no dice si
`true` significa permitido o prohibido. Las respuestas reales que se conocían traen
`"actions": {"disallows": {"resuming": true}}`, donde `true` significa prohibido.

El modelo (`PlaybackActions`) interpreta solo la forma con `disallows`. Si llegan los booleanos
sueltos, los guarda sin usarlos, para no deshabilitar controles con un significado que no está
documentado. El hito 3 tiene que mirar una respuesta real y decidir.

### Campos quitados en Development Mode (changelog de feb-2026)

- Track: `available_markets`, `linked_from`, `popularity`. `external_ids` se quitó y volvió en
  marzo de 2026.
- Album: `album_group`, `available_markets`, `label`, `popularity`.
- Artist: `followers`, `popularity`.
- Show: `available_markets`, `publisher`.
- `GET /me`: `country`, `email`, `explicit_content`, `followers`, `product`.

Los modelos no decodifican ninguno de estos campos.

## Polling y estado local

La Web API no tiene notificaciones push del estado, así que hay que consultarlo.

- **Reproduciendo, app en primer plano**: `GET /me/player` cada **3 s**. Entre consultas, el
  progreso se **interpola** localmente con `Date()` y `progress_ms`. Se toma la hora local
  en que llegó la respuesta, no el campo `timestamp`: según la referencia, ese campo marca
  cuándo *cambió* el estado y viene con el reloj de Spotify.
- **Pausado o nada sonando**: cada **10 s**.
- **Después de `QUOTA_EXCEEDED`**: durante 15 minutos, cada 10 s reproduciendo y cada 30 s
  pausado (`PollingPolicy`).
- **Después de un error de red o `5xx`**: espera exponencial de 3, 6, 12… hasta 60 s.
- **Después de un `403`**: cada 30 s, para que la app se recupere sola si el dueño corrige la
  lista de usuarios.
- **App en segundo plano**: detener el polling.
- **Después de un comando**: actualizar la UI en forma **optimista** y volver a consultar a los
  ~600 ms para confirmar.
- **Cambio de tema** (`item.id` distinto): recalcular el color de fondo y buscar la letra si el
  modo letras está activo.
- **Cambio de volumen** frente al último conocido, y no causado por la app: mostrar el panel de
  volumen.

## Errores

| Código | Acción |
|---|---|
| `401` | Refrescar el token y reintentar **una** vez |
| `403` | Usuario fuera de la lista permitida o sin Premium: mensaje con instrucciones |
| `404` "No active device" | Abrir Dispositivos o mostrar "Nada sonando" |
| `429` | Respetar `Retry-After` (más un poco de *jitter*). Si el motivo es `QUOTA_EXCEEDED`, bajar la frecuencia del polling y avisar en forma discreta |
| `5xx` o sin red | Reintento con espera exponencial; mantener el último estado visible y marcarlo como desactualizado |

**Verificado (2026-11-17, "Rate limits" y "API calls")**:

- El límite se calcula en una ventana móvil de 30 s.
- `Retry-After` viene en **segundos**.
- La cuota de Development Mode "has a different enforcement mechanism than rate limits" y
  responde `429` con `"reason": "QUOTA_EXCEEDED"`.

Cómo lo maneja `SpotifyAPI`:

- Ante un `429`, recuerda hasta cuándo esperar y, mientras tanto, falla sin salir a la red.
- Ante un `5xx`, reintenta solo los `GET`, dos veces, a los 0,5 s y a los 1,5 s más
  *jitter*.
- Los comandos no se reintentan solos: repetir "siguiente" podría saltar dos temas.

## Modelos

`Codable` con `snake_case` (`keyDecodingStrategy = .convertFromSnakeCase`). Campos opcionales
donde la API puede omitirlos: `item` es `nil` durante los anuncios y con contenido local, y
`device.volume_percent` puede faltar. Los episodios de podcast usan `show` en lugar de `album` y
`artists`.
