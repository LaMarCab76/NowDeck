# Diseño · mockups de Nowdeck

Estos archivos son las **fuentes** de los mockups hechos en el lienzo de diseño de Claude. Son
HTML con estilos en línea y **no se abren solos** en un navegador, porque dependen del runtime
del lienzo (`support.js`, que no está incluido). Sirven como referencia de valores exactos:
colores, tamaños, márgenes, radios, textos y estados.

| Archivo | Pantalla |
|---|---|
| `Main.dc.html` | Reproducción. Incluye el modo letras, el panel de volumen y el aviso, según su estado |
| `Letras.dc.html` / `LetrasEstrofa.dc.html` | Modo letras por palabra y por estrofa |
| `SinLetra.dc.html` | Aviso "No encontramos la letra" |
| `Volumen.dc.html` | Panel de volumen visible (reemplazado por `VolumenLateral.html`) |
| `VolumenLateral.html` | Barra de volumen que se abre hacia el costado desde el parlante, interactiva. Hecho a mano el 2026-11-18 y aprobado por el dueño; se ve en un navegador sin `support.js` |
| `Biblioteca.dc.html` | Biblioteca y Buscar, con filtros y mini reproductor |
| `Detalle.dc.html` | Detalle de una playlist o un álbum: propia, álbum y playlist de otra persona |
| `Dispositivos.dc.html` | Hoja de dispositivos y ayuda |
| `cola-integrada.html` | Cola integrada al reproductor, con transición a la carátula grande. Interactivo, se abre en el navegador |
| `Cola.html` | Referencia histórica de la hoja de Cola |
| `Ajustes.dc.html` / `AjustesReproductor.dc.html` | Ajustes: Apariencia y Reproductor |
| `TemaImportar.dc.html` | Importar tema |
| `SinReproduccion.dc.html` | Nada sonando |
| `Onboarding1-3.dc.html` | Primer inicio, en vertical |
| `canvas.json` | Disposición del lienzo y tamaño de cada pantalla |

Notas:
- Las carátulas, los nombres de temas, playlists y artistas, y la letra de ejemplo son
  **inventados**, de relleno.
- "LOGO SPOTIFY" es un **lugar reservado**: va el asset oficial de Spotify.
- Las fuentes Space Grotesk e IBM Plex Mono son una aproximación del mockup. En iOS se usa la
  fuente del sistema (ver `docs/02-diseno.md`).
- Los valores marcados como *tweaks* en el bloque `data-props` (por ejemplo `fondo`, `accent` y
  `anchoLetras`) son variantes de diseño, y en la app se traducen a ajustes del usuario.
