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
   **[VERIFICAR]** Según fuentes de terceros, desde mediados de 2026 el refresh token vence a
   los **6 meses** de la autorización original, aunque se refresque.

Todo se guarda en el **Llavero** (`kSecClassGenericPassword`, accesible después del primer
desbloqueo).

### Scopes

| Scope | Para qué |
|---|---|
| `user-read-playback-state` | Estado del reproductor y dispositivos de Connect |
| `user-modify-playback-state` | Play, pausa, saltar, volumen, aleatorio, repetir, transferir |
| `user-read-currently-playing` | Lo que suena ahora |
| `playlist-read-private` | Playlists privadas del usuario |
| `playlist-read-collaborative` | Playlists colaborativas en el listado |
| `user-library-read` | Álbumes guardados (y, **[VERIFICAR]**, podcasts y audiolibros) |
| `user-read-playback-position` | Posición en episodios de podcast |

Pedir solo estos. En el primer inicio se explican en palabras simples.

## Endpoints por funcionalidad

Base: `https://api.spotify.com/v1`. Cabecera: `Authorization: Bearer <token>`.

| Función | Endpoint | Notas |
|---|---|---|
| Estado del reproductor | `GET /me/player?additional_types=episode` | `204` = nada suena → "Nada sonando". Trae `device`, `progress_ms`, `is_playing`, `item`, `shuffle_state`, `repeat_state`, `context` y `actions.disallows` |
| Dispositivos | `GET /me/player/devices` | Solo los activos o despiertos. `supports_volume` por dispositivo |
| Transferir | `PUT /me/player` con body `{"device_ids":["<id>"],"play":true}` | |
| Play / reanudar | `PUT /me/player/play` con body opcional `context_uri` o `uris` y `device_id` opcional | Para reproducir una tarjeta de la Biblioteca |
| Pausa | `PUT /me/player/pause` | |
| Siguiente / anterior | `POST /me/player/next` · `POST /me/player/previous` | |
| Volumen | `PUT /me/player/volume?volume_percent=0..100` | Agrupar los toques: mandar uno solo ~250 ms después del último |
| Aleatorio | `PUT /me/player/shuffle?state=true\|false` | |
| Repetir | `PUT /me/player/repeat?state=off\|context\|track` | |
| Origen ("Desde la playlist…") | `context.type` y `context.uri` del estado; nombre con `GET /playlists/{id}?fields=name` o `GET /albums/{id}` | **[VERIFICAR]** que `GET /playlists/{id}` siga disponible en Development Mode para playlists ajenas. Si no, mostrar solo el tipo |
| Playlists | `GET /me/playlists?limit=…` | Disponible |
| Álbumes guardados | `GET /me/albums` | **[VERIFICAR]** tras los cambios de la biblioteca de feb-2026 |
| Podcasts guardados | `GET /me/shows` | **[VERIFICAR]** |
| Audiolibros guardados | `GET /me/audiobooks` | **[VERIFICAR]** disponibilidad y mercados (no en todos los países). Si no aplica, ocultar el filtro |
| Buscar | `GET /search?q=…&type=track,album,playlist,show,audiobook&limit=10` | Desde feb-2026, en Development Mode el **límite máximo es 10** (por defecto 5). Paginar con `offset` |

Los comandos de reproducción requieren **Premium**. Si devuelven `403` con el motivo
`PREMIUM_REQUIRED`, mostrar un mensaje claro.

## Polling y estado local

La Web API no tiene notificaciones push del estado, así que hay que consultarlo.

- **Reproduciendo, app en primer plano**: `GET /me/player` cada **3 s**. Entre consultas, el
  progreso se **interpola** localmente con `Date()` y `progress_ms`.
- **Pausado o nada sonando**: cada **10 s**.
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

## Modelos

`Codable` con `snake_case` (`keyDecodingStrategy = .convertFromSnakeCase`). Campos opcionales
donde la API puede omitirlos: `item` es `nil` durante los anuncios y con contenido local, y
`device.volume_percent` puede faltar. Los episodios de podcast usan `show` en lugar de `album` y
`artists`.
