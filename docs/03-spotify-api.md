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
| `user-read-recently-played` | Último tema escuchado, para la foto de ejemplo de la vista previa del fondo en Ajustes (desde 2026-11-18). Las sesiones anteriores no lo tienen hasta volver a conectar: mientras tanto `GET /me/player/recently-played` responde `403` y se usa lo que la app vio sonar |

Pedir solo estos. En el primer inicio se explican en palabras simples.

## Endpoints por funcionalidad

Base: `https://api.spotify.com/v1`. Cabecera: `Authorization: Bearer <token>`.

| Función | Endpoint | Notas |
|---|---|---|
| Estado del reproductor | `GET /me/player?additional_types=episode` | `204` = nada suena → "Nada sonando". Trae `device`, `progress_ms`, `is_playing`, `item`, `shuffle_state`, `repeat_state`, `context`, `currently_playing_type` y `actions`. **Verificado (2026-11-17)**: sigue disponible, scope `user-read-playback-state`, respuestas 200/204/401/403/429. `additional_types` "might be deprecated in the future". Ver la nota sobre `actions` más abajo |
| Dispositivos | `GET /me/player/devices` | **Verificado (2026-11-17)**: sigue disponible (figura en "Endpoints still available" de feb-2026; los changelogs de may-2026 y jul-2026 no lo tocan), scope `user-read-playback-state`, respuestas 200/401/403/429. Ver "Dispositivos" más abajo |
| Transferir | `PUT /me/player` con body `{"device_ids":["<id>"],"play":true}` | **Verificado (2026-11-17)**: sigue disponible (mismas fuentes), scope `user-modify-playback-state`, solo Premium, respuestas 204/401/403/429. Ver "Dispositivos" más abajo |
| Play / reanudar | `PUT /me/player/play` con body opcional `context_uri` o `uris` y `device_id` opcional | Para reproducir una tarjeta de la Biblioteca. **Verificado (2026-11-17)**: scope `user-modify-playback-state`, solo Premium. Sin `device_id` apunta al dispositivo activo. "Valid contexts are albums, artists & playlists": podcasts y audiolibros **no** están documentados como `context_uri`, así que esas tarjetas abren el contenido en Spotify. La referencia lista 204/401/403/429; sin dispositivo activo la API responde `404` (se trata como "No active device") |
| Pausa | `PUT /me/player/pause` | |
| Siguiente / anterior | `POST /me/player/next` · `POST /me/player/previous` | |
| Volumen | `PUT /me/player/volume?volume_percent=0..100` | Agrupar los toques: mandar uno solo ~250 ms después del último |
| Aleatorio | `PUT /me/player/shuffle?state=true\|false` | |
| Repetir | `PUT /me/player/repeat?state=off\|context\|track` | |
| Cola | `GET /me/player/queue` | **Verificado (2026-11-17)**: figura en "Endpoints still available" → Player del changelog de feb-2026 ("Retrieves the current playback queue"); los de may-2026 y jul-2026 no lo tocan; sin nota de deprecación. Scopes `user-read-currently-playing` y `user-read-playback-state` (ya pedidos). Respuestas 200/401/403/429. Trae `currently_playing` ("Can be `null`") y `queue` ("The tracks or episodes in the queue. Can be empty"), con temas o episodios; mezcla lo agregado a mano y lo que sigue del contexto sin distinguirlos. La referencia no indica un máximo de ítems; la app muestra hasta 20 (docs/06). No hay endpoints para quitar, reordenar ni saltar a un ítem: la hoja es de solo lectura. `POST /me/player/queue?uri=…` (agregar, `user-modify-playback-state`, solo Premium, 204/401/403/429) también sigue disponible, pero la app todavía no lo usa |
| Saltar ±15 s (episodios) | `PUT /me/player/seek?position_ms=…` | "Must be a positive number". Pasarse de la duración "will cause the player to start playing the next song": la app lo limita a la duración |
| Origen ("Desde la playlist…") | `context.type` y `context.uri` del estado. Playlist: `GET /playlists/{id}?fields=name`. Álbum, artista y podcast: el nombre sale del propio `item` cuando su URI coincide con la del contexto, sin pedido extra | **Verificado (2026-11-17)**: `GET /playlists/{id}` figura en "Endpoints still available" del changelog de feb-2026. Para playlists ajenas devuelve solo metadatos (sin `items`), y `name` está entre ellos. Soporta `fields`. La referencia no lista scope. Si responde `403`/`404` (por ejemplo, playlists editoriales o algorítmicas de Spotify, que desde nov-2024 no están disponibles para apps nuevas; esto último no se volvió a verificar), se muestra solo el tipo ("Desde una playlist") y no se vuelve a pedir. `GET /albums/{id}` sigue disponible, pero no hace falta |
| Siguiente en la cola (deslizar desde el borde) | `GET /me/player/queue` | **Verificado (2026-11-17)**: en "Endpoints still available" (Player) del changelog de feb-2026; scopes `user-read-currently-playing` y `user-read-playback-state`, que ya se piden. Se lee una vez por cada ítem nuevo y otra vez al empezar a deslizar si la última lectura tiene más de 15 s. Solo se usa el primer ítem. Si falla, la tarjeta queda genérica y el deslizamiento funciona igual. El ítem anterior no sale de la API: es el que la app vio sonar antes (hasta 20) |
| Foto del artista (fondo del reproductor) | `GET /artists/{id}` | **Verificado (2026-11-17)**: figura en "Endpoints still available" (Metadata) del changelog de feb-2026, que a los artistas solo les quitó `followers` y `popularity`; `images` sigue ("Images of the artist in various sizes, widest first"). La referencia no lista scope. Se pide una vez por artista mientras la app está abierta (`404`/`403`: no se vuelve a pedir; otros errores: se reintenta al minuto). Solo se pide con el fondo "Foto del artista". La referencia avisa: "Spotify visual content must be kept in its original form, e.g. you can not crop…" (ver `docs/06`, "Zonas grises") |
| Último tema escuchado (vista previa del fondo en Ajustes) | `GET /me/player/recently-played?limit=1` | **Verificado (2026-11-18)**: en "Endpoints still available" (Player) del changelog de feb-2026; la guía de migración de Development Mode no lo restringe. Scope `user-read-recently-played`; `limit` 1–50 (por defecto 20); ítems `{track, played_at, context}`; "Currently doesn't support podcast episodes"; respuestas 200/401/403/429. Se pide cuando aparecen los deslizadores Desenfoque y Oscurecer (fondo "Foto del artista"), una vez por apertura de Ajustes (si no se encontró foto, otra vez al tocar un deslizador), también si algo suena (por si su artista no tiene foto o la reproducción para), y se cancela al cerrar Ajustes. Como cualquier lectura, puede reintentarse ante errores del servidor y respeta la espera de un `429`. Le sigue `GET /artists/{id}` del artista de ese tema. No se revisaron los changelogs de marzo, mayo y julio de 2026 para este endpoint |
| Playlists | `GET /me/playlists?limit=…&offset=…` | **Verificado (2026-11-17)**: scope `playlist-read-private`; `limit` 1–50 (por defecto 20), `offset` hasta 100.000. La cantidad de temas pasó de `tracks.total` a `items.total` (`tracks` figura como *deprecated*); el modelo lee `items` y, si falta, `tracks` |
| Álbumes guardados | `GET /me/albums` | Lectura listada en "Endpoints still available" (feb-2026, consultado 2026-11-17). Lo que se quitó son las escrituras (`PUT`/`DELETE`, reemplazadas por `/me/library`) y los `contains`. **Verificado (2026-11-17)**: scope `user-library-read`; `limit` 1–50 (por defecto 20), `offset`; ítems `{added_at, album}`; `market` opcional (con token de usuario manda el país de la cuenta). La referencia todavía muestra `label`, `popularity` y `available_markets` como *deprecated*; el changelog de feb-2026 los da por quitados y no se decodifican |
| Temas de un álbum (detalle) | `GET /albums/{id}/tracks?limit=50&offset=…` | **Verificado (2026-11-17)**: en "Endpoints still available" (Metadata) del changelog de feb-2026; `limit` 1–50 (por defecto 20), `offset`. Los temas simplificados traen `artists`, `duration_ms`, `explicit`, `is_local`, `restrictions` e `is_playable`; este último es "Part of the response when Track Relinking is applied", o sea solo con `market`. La app **no** manda `market`: la referencia solo documenta códigos de país (no `from_token`) y dice que el país de la cuenta "will take priority over this parameter". Un tema se atenúa si es local, si `is_playable` es `false` o si trae `restrictions` |
| Temas de una playlist (detalle) | `GET /playlists/{id}/items?limit=50&offset=…&additional_types=track,episode` | **Verificado (2026-11-17)**: agregado en feb-2026; `GET /playlists/{id}/tracks` se **quitó**. Scope `playlist-read-private`; `limit` 1–50. "This endpoint is only accessible for playlists owned by the current user or playlists the user is a collaborator of. A 403 Forbidden status code will be returned if the user is neither the owner nor a collaborator": la app lo muestra como "Spotify no muestra los temas de esta playlist" y deja reproducirla igual. Cada ítem es `{added_at, added_by, is_local, item}`; `track` sigue con lo mismo pero "Deprecated: Use `item` instead" (la app lee los dos). No se usa `fields`: los nombres cambiaron en feb-2026 y un filtro con el nombre viejo devolvería ítems vacíos |
| Podcasts guardados | `GET /me/shows` | Lectura disponible, igual que la anterior. `show.publisher` y `available_markets` se quitaron. **Verificado (2026-11-17)**: scope `user-library-read`; `limit` 1–50, `offset`; ítems `{added_at, show}` con `total_episodes`. Como no hay `publisher`, la tarjeta dice "Podcast · N episodios" |
| Audiolibros guardados | `GET /me/audiobooks` | Lectura disponible, igual que la anterior. **Verificado (2026-11-17)**: scope `user-library-read`; `limit` 1–50, `offset`; los ítems vienen **sin** envoltorio (`authors`, `narrators`, `total_chapters`). "Audiobooks are only available within the US, UK, Canada, Ireland, New Zealand and Australia markets" (referencias de *Get an Audiobook* y *Search*). Como `GET /me` ya no trae `country`, el filtro Audiolibros se muestra solo si este pedido devuelve al menos un audiolibro |
| Buscar | `GET /search?q=…&type=track,album,playlist,show,audiobook&limit=10` | Desde feb-2026, en Development Mode el **límite máximo es 10** (por defecto 5). Paginar con `offset`. **Verificado (2026-11-17)**: `type` admite `album`, `artist`, `playlist`, `track`, `show`, `episode` y `audiobook`; `limit` 0–10, `offset` 0–1000; la referencia no lista scope. El `+` de la consulta se manda como `%2B` (si no, llega como espacio). La pantalla de resultados sigue pendiente de diseño: el pedido y su modelo están hechos, la UI no lo llama todavía |

**Verificado (2026-11-17), comandos de reproducción** (play, pausa, siguiente, anterior,
volumen, aleatorio, repetir y seek): siguen en la lista "Endpoints still available" → Player del
changelog de feb-2026, sin nota de deprecación; scope `user-modify-playback-state`; respuestas
documentadas 204, 401, 403 y 429 (solo la 204 tiene descripción); `device_id` opcional en todos
("If not supplied, the user's currently active device is the target"), y la app no lo manda.
Cada página dice "The order of execution is not guaranteed when you use this API with other
Player API endpoints": por eso la app manda los comandos de a uno, en el orden en que se tocaron.

Los comandos de reproducción requieren **Premium**. **Verificado (2026-11-17)**: Spotify ya no
documenta el motivo `PREMIUM_REQUIRED`. El cuerpo de error documentado es
`{"error": {"status", "message", "reason"?}}` y el único `reason` listado es `QUOTA_EXCEEDED`.
Por eso un `403` se trata siempre igual (fuera de la lista permitida, Premium vencido del dueño
o del usuario) y se muestra con un mensaje con instrucciones.

### Dispositivos (hito 4)

Verificado en developer.spotify.com el 2026-11-17 (referencias de *Get Available Devices* y
*Transfer Playback*, y changelogs de feb-2026, may-2026 y jul-2026):

- `GET /me/player/devices` devuelve `{"devices": [...]}`. Cada dispositivo trae `id` (puede ser
  `null`; "any cached `device_id` should periodically be cleared out and refetched"),
  `is_active`, `is_private_session`, `is_restricted`, `name`, `type`, `volume_percent` (puede
  ser `null`) y `supports_volume`. La referencia no lista más campos.
- `type` solo se documenta con ejemplos ("computer", "smartphone", "speaker"), sin lista
  cerrada, y las mayúsculas varían. La app compara sin distinguir mayúsculas y usa un nombre
  genérico ("Dispositivo") para los tipos que no conoce.
- `is_restricted: true`: "no Web API commands will be accepted by this device". La hoja lo
  muestra atenuado, con "No admite control remoto", y no se puede tocar. Un dispositivo sin
  `id` se trata igual, porque no se lo puede nombrar en la transferencia.
- La referencia solo dice que "some device models are not supported and will not be listed".
  No documenta que la lista se limite a los dispositivos activos o despiertos: eso es lo que
  se ve en la práctica y lo que explica la ayuda de la hoja.
- `PUT /me/player`: `device_ids` es obligatorio y acepta **un solo** ID ("Supplying more than
  one will return `400 Bad Request`"). `play: true` "ensure playback happens on new device";
  `false` o ausente "keep the current playback state". La app manda `play: true`, como decía
  este documento, para que "Elegir dispositivo" desde "Nada sonando" también arranque la
  música. "The order of execution is not guaranteed when you use this API with other Player
  API endpoints": por eso, después de transferir, la app vuelve a consultar
  `GET /me/player` a los ~600 ms en lugar de suponer el resultado.
- La referencia no documenta un `404` para la transferencia. Si llega (por ejemplo, el
  dispositivo se durmió después de cargar la lista), la hoja avisa y vuelve a pedir la lista.
- Errores de la hoja: `403` con un mensaje genérico (Premium o *Users Management*, como el resto
  de la app); `429` respetado por el cliente (no sale a la red hasta que pase `Retry-After`);
  sin red o `5xx`, aviso y la lista anterior queda en pantalla. La transferencia, como todo
  comando, no se reintenta sola.

### `actions` (revisado en el hito 3, 2026-11-17)

Lo que dice la referencia actual de *Get Playback State*
(`/reference/get-information-about-the-users-current-playback`):

- `actions`: "Allows to update the user interface based on which playback actions are
  available within the current context".
- Lista los diez booleanos (`interrupting_playback`, `pausing`, `resuming`, `seeking`,
  `skipping_next`, `skipping_prev`, `toggling_repeat_context`, `toggling_shuffle`,
  `toggling_repeat_track`, `transferring_playback`) **directamente** dentro de `actions`, cada uno
  como "Optional field", **sin `disallows`**.
- **No dice** si `true` significa permitido o prohibido. El ejemplo trae los diez en `false`, que
  no lo aclara. Los changelogs de feb, mar, may y jul de 2026 no mencionan ningún cambio en
  `actions`.
- No se pudo mirar una respuesta real: no hay una cuenta conectada en este entorno.

Decisión (la conservadora):

- Se interpreta **solo** la forma con `disallows` (`"actions": {"disallows": {"resuming": true}}`):
  `true` = **prohibido**, y lo que falta = permitido. Es la forma de las respuestas reales
  conocidas. Antes de este cambio, la referencia nombraba ese objeto `DisallowsObject` y listaba
  los mismos booleanos sin el envoltorio (esto último sale de memoria, no se pudo volver a
  verificar). Todo indica que la referencia muestra el contenido de `disallows`.
- Los booleanos sueltos se guardan (`PlaybackActions.flatFlags`) pero **no deshabilitan nada**:
  si `true` quisiera decir "disponible", leerlos como prohibición dejaría la app sin controles.
  Si llega una acción prohibida que no se deshabilitó, Spotify responde con un error, la app
  deshace el cambio optimista y muestra el aviso genérico.
- Un dispositivo con `is_restricted: true` ("no Web API commands will be accepted by this
  device") deshabilita todos los controles.
- **Pendiente del dueño**: mirar una respuesta real de `GET /me/player` (por ejemplo durante una
  publicidad o con un tema que no deja volver atrás) para confirmar que llega `disallows`.

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
- **Otra pantalla tapa el reproductor**: con la Biblioteca (mini reproductor; Ajustes se abre
  desde ahí) o la Cola (cabecera) abiertas, el polling sigue; con Dispositivos, se detiene
  hasta volver.
- **Después de un comando**: actualizar la UI en forma **optimista** y volver a consultar a los
  ~600 ms para confirmar. Mientras el comando viaja, el polling se frena (una respuesta leída
  antes del comando pisaría el cambio optimista). Si falla, se deshace el cambio y se vuelve a
  consultar enseguida.
- **Volumen**: después de cambiarlo desde la app, las consultas pueden traer el valor viejo un
  rato. Se ignoran durante 3 s después del pedido (o hasta que llegue el valor pedido).
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
