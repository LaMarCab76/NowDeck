# 04 · Letras (LRCLIB)

Spotify **no** ofrece letras en su Web API. Las librerías que las sacan de Spotify usan un
endpoint interno con la cookie de sesión del usuario: **no usarlas**, porque violan los términos
y exponen credenciales.

La fuente es **LRCLIB** (`https://lrclib.net`), una base comunitaria y abierta. Documentación:
`https://lrclib.net/docs.txt`.

## Activación

- La opción vive en Ajustes → Reproductor → "Mostrar letras". Si está apagada, el botón de
  letras no aparece en el reproductor.
- Al tocar el botón se busca la letra del tema actual. Si cambia el tema con el modo activo, se
  busca la nueva.

## Pedido

```
GET https://lrclib.net/api/get
  ?track_name=<título>
  &artist_name=<primer artista>
  &album_name=<álbum>
  &duration=<segundos, entero>
User-Agent: Nowdeck/<versión> (https://github.com/<usuario>/Nowdeck)
```

- La duración tiene que coincidir con **±2 s**, y conviene incluir el álbum para afinar.
- **User-Agent identificado** (nombre, versión y URL o mail): sube el límite de ~45 a ~90
  pedidos por minuto por IP. LRCLIB también ofrece registrar la app (`Lrclib-App-Id`); eso
  queda para más adelante.
- Ante `429` (y `503`): respetar `Retry-After` con hasta un 30 % de *jitter*.
- **Caché** en disco por `item.id` de Spotify, incluidas las respuestas negativas (por ejemplo
  durante 7 días), para no volver a consultar temas sin letra.

### Verificado en la documentación de LRCLIB (2026-11-17)

Fuentes: `https://lrclib.net/docs.txt`, `https://lrclib.net/llms.txt` y la especificación del
Lyricsfile (`github.com/tranxuanthang/lyricsfile`, `SPECIFICATION.md`, borrador 1.0, enlazada
desde LRCLIB como "Lyricsfile format").

- `GET /api/get` sigue igual: `track_name` y `artist_name` obligatorios; `album_name` y
  `duration` opcionales pero recomendados. La duración tiene que estar entre **1 y 3600 s**
  (fuera de ese rango es un `400 ValidationError`), así que la app no la manda si queda afuera.
  Sin coincidencia responde `404 TrackNotFound`.
- Campos del registro: `id`, `name` (alias viejo de `trackName`), `trackName`, `artistName`,
  `albumName`, `duration` (segundos, puede tener decimales: `233.0`), `instrumental`,
  `hasWordSync`, `plainLyrics`, `syncedLyrics` y `lyricsfile` (YAML; la documentación dice que
  todo registro trae uno). Los registros publicados solo con `plainLyrics` o `syncedLyrics`
  nunca tienen `hasWordSync`.
- **User-Agent**: obligatorio identificarse con nombre, versión y página del proyecto o un mail
  (si no se puede tocar el header, valen `X-User-Agent` o `Lrclib-Client`). Límites
  aproximados: ~45 pedidos/min por IP sin identificar, ~90 identificado, ~180 con
  `Lrclib-App-Id` (registro opcional en `lrclib.net/developers`; el ID no es secreto). Nowdeck
  manda `Nowdeck/<versión> (https://github.com/<usuario>/Nowdeck)`: el `<usuario>` queda como
  marcador hasta que el dueño elija el usuario u organización de GitHub
  (`LRCLIBClient.projectURL`).
- **429**: trae `Retry-After` en segundos; hay que esperarlo con un *jitter* chico (la doc
  sugiere hasta 30 %) o LRCLIB puede banear temporalmente. **503 `ServerOverloaded`** también
  trae `Retry-After` (normalmente 1 s). Los rechazos del borde de la red pueden no ser JSON:
  mirar el código de estado y el header, no el cuerpo.
- **LRC real de LRCLIB**: las estrofas casi nunca se separan con líneas en blanco sino con una
  línea con tiempo y sin texto (`[00:49.72] `), y la letra suele terminar con una así. El parser
  trata las dos formas como corte de estrofa; la línea vacía con tiempo además marca el fin de
  la estrofa (durante el instrumental se muestra la siguiente, toda en `letraPendiente`).
- **Lyricsfile** (borrador 1.0, puede cambiar): `version` (tiene que ser exactamente `"1.0"`;
  la especificación pide no tratar otra versión como 1.0, así que la app vuelve al LRC),
  `metadata` (`title`, `artist`, `album`, `duration_ms`, `offset_ms`, `language`,
  `instrumental`), `lines[]` con `text`, `start_ms`, `end_ms` opcional y `words[]` opcional
  (`text` con el espacio incluido, `start_ms`, `end_ms` opcional) y `plain`. Todo en
  milisegundos enteros. **`offset_ms` se ignora**: la especificación dice que su significado no
  está definido. En los Lyricsfile reales con palabras no aparecen líneas vacías ni pausas
  (`end_ms` de una línea = `start_ms` de la siguiente), así que se agrupa de a 2 líneas.
- **Estrofas de más de 2 líneas**: se cortan de a pares. A 30 pt con interlineado de 38, el
  espacio del modo letras (156 pt en 896×414) entra 3 líneas de la estrofa actual y una de la
  siguiente; una estrofa de 4 versos no entra. Si aun así no entra, el texto se achica (hasta
  60 %) en lugar de cortarse.

## Qué modo usar

| Respuesta | Modo |
|---|---|
| `hasWordSync == true` | **Por palabra**: leer `lyricsfile` (YAML) → `lines[].words` con tiempos |
| `syncedLyrics` no nulo | **Estrofa completa**, usando los tiempos por línea del LRC para saber en qué estrofa vamos |
| Solo `plainLyrics`, `instrumental == true` o 404 | **Sin letra**: aviso "No encontramos la letra de este tema" durante 3 s y vuelta a la vista normal |

### Parser LRC (`syncedLyrics`)

- Cada línea tiene la forma `[mm:ss.xx] texto`. Puede haber varias marcas de tiempo en una
  misma línea (estribillos repetidos) y metadatos del tipo `[ar:…]` o `[offset:+/-ms]`, que hay
  que aplicar.
- **Estrofas**: se separan con líneas vacías del LRC.
  - Si no hay líneas vacías, agrupar por pausas de más de 4 s entre líneas o, como último
    recurso, cada 2 líneas.
  - Estrofa actual = la que contiene la última línea con tiempo menor o igual a la posición
    actual. Siguiente = la que viene después.

### Lyricsfile (`hasWordSync`)

- Es YAML: parsearlo con **Yams**. Las palabras están en `lines[].words`, con su tiempo.
  Antes de escribir el parser, revisá la especificación del formato en el repositorio de LRCLIB
  y no supongas los nombres de los campos.
- **Resaltado**: las palabras con tiempo menor o igual a la posición van en `texto`; el resto,
  en `letraPendiente`.
- Las estrofas se agrupan igual que en el LRC.

## Sincronización con la reproducción

- Posición = `progress_ms` del último polling + el tiempo transcurrido, mientras `is_playing`
  sea verdadero. Actualizar la vista a ~10 fps en modo palabra y ~2 fps en modo estrofa.
- Si el polling detecta un salto de más de 1,5 s frente a lo interpolado (alguien adelantó el
  tema), resincronizar.
- **Sincronía de las letras** (Ajustes → Reproductor, 2026-11-17): un desfase de −3 a +3 s en
  pasos de 0,1 s que se suma a la posición interpolada antes de elegir la estrofa. Positivo
  las muestra antes (para cuando la posición de Spotify llega tarde o el audio va por
  Bluetooth). Se guarda en `UserDefaults`, no en el tema: depende del equipo y de la red.

## Avisos para el usuario y el README

- La nota de Ajustes ya dice que las letras vienen de una base comunitaria, no de Spotify, y que
  pueden faltar o tener errores.
- **Derechos**: las letras de LRCLIB las cargan usuarios; los derechos son de las editoriales.
  Por eso la función está aclarada en el README y se puede apagar en Ajustes. Arranca
  **prendida**: el dueño lo decidió el 2026-11-18 (ver `docs/06-cumplimiento.md`).
- La política de Spotify prohíbe productos "integrados con contenido de otro servicio". Mostrar
  letras de un tercero junto a la reproducción es una zona gris sin un precedente claro. Está
  anotado en `docs/06-cumplimiento.md`.
