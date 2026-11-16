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
- Ante `429`: respetar `Retry-After` con hasta un 30 % de *jitter*.
- **Caché** en disco por `item.id` de Spotify, incluidas las respuestas negativas (por ejemplo
  durante 7 días), para no volver a consultar temas sin letra.

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

## Avisos para el usuario y el README

- La nota de Ajustes ya dice que las letras vienen de una base comunitaria, no de Spotify, y que
  pueden faltar o tener errores.
- **Derechos**: las letras de LRCLIB las cargan usuarios; los derechos son de las editoriales.
  Por eso la función está apagada por defecto y aclarada en el README.
- La política de Spotify prohíbe productos "integrados con contenido de otro servicio". Mostrar
  letras de un tercero junto a la reproducción es una zona gris sin un precedente claro. Está
  anotado en `docs/06-cumplimiento.md`.
