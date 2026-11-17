# 07 · Plan de hitos

Cada hito termina con el build sin errores, los tests en verde y una demo corta en el simulador.
Trabajá en una rama por hito y frená al final de cada uno para que el dueño revise.

## Hito 0 · Proyecto base

- `project.yml` de XcodeGen:
  - target `Nowdeck` con iOS 16.0 y target `NowdeckTests`;
  - Bundle ID configurable (por defecto `com.lamarcab76.nowdeck`);
  - URL scheme `nowdeck`;
  - `UTType` exportado para `.nowdeck.json`.
- Estructura de carpetas de `AGENTS.md`, `.gitignore` (incluido `*.xcodeproj`), `README.md`
  inicial y `LICENSE` vacío para que el dueño elija.
- `DesignSystem`: colores (desde `ThemeStore` con el tema por defecto), tipografías, espaciados
  y radios.
- Orientación por pantalla y `isIdleTimerDisabled` en primer plano.

**Listo cuando**: `xcodegen generate` y el build funcionan, y la app muestra una pantalla vacía
en horizontal con el fondo negro.

## Hito 1 · Primer inicio y autenticación

- Las tres pantallas verticales, con Copiar y Pegar funcionando y validación de formato del
  Client ID (32 caracteres alfanuméricos).
- PKCE + `ASWebAuthenticationSession` + intercambio y refresh de tokens, guardados en el
  Llavero.
- Manejo de `invalid_grant` y de usuario fuera de la lista permitida (`403`).

**Tests**: generación de PKCE, armado de la URL de autorización, validación de `state`, refresh
concurrente (un solo pedido) y Llavero con un *mock*.

**Listo cuando**: un usuario real completa el flujo y la app guarda los tokens.

## Hito 2 · Reproductor en modo lectura

- Cliente `SpotifyAPI` (async, con manejo de 401, 429 y 5xx), modelos Codable y polling
  adaptativo.
- Pantalla de Reproducción con datos reales: carátula, título, artista, origen,
  "Reproduciendo en" y progreso interpolado.
- Fondo según la carátula (`ArtworkColor`) y la pantalla "Nada sonando".

**Tests**: decodificación de respuestas reales guardadas, interpolación del progreso y
extracción de color con imágenes de prueba.

## Hito 3 · Controles

- Play/pausa, anterior, siguiente, aleatorio y repetir, con actualización optimista y
  reconsulta.
- Respetar `actions.disallows`.
- Panel de volumen flotante con sus animaciones, agrupado de toques y detección de cambios
  externos.

## Hito 4 · Dispositivos

- Hoja con la lista, transferencia de la reproducción, vista de ayuda y "Actualizar lista".
- Accesos desde Reproducción, modo letras y mini reproductor.

## Hito 5 · Biblioteca y Buscar

- Pestañas, filtros y filas de tarjetas (playlists primero; álbumes, podcasts y audiolibros
  según lo que confirme el **[VERIFICAR]** de la API).
- Mini reproductor con el color de la carátula. Tocar una tarjeta la reproduce.
- Buscar con el límite de 10 resultados. La pantalla de resultados no está diseñada: proponé
  una que siga el lenguaje visual existente y **mostrala antes de implementarla**.

## Hito 6 · Letras

- Cliente LRCLIB con User-Agent y caché.
- Parsers de LRC y de Lyricsfile (Yams).
- Modo letras: por palabra o por estrofa, ancho configurable y aviso de "sin letra".

**Tests**: parser LRC (varias marcas, offset, estrofas), parser Lyricsfile con un ejemplo real
de la documentación y cálculo de estrofa actual y siguiente.

## Hito 7 · Ajustes y temas

- Ajustes → Apariencia y Reproductor, con todas sus opciones guardadas.
- `ThemeStore`, temas preestablecidos (los de `themes/`), Exportar con `ShareLink` e Importar
  desde archivo, `onOpenURL` o portapapeles, con la hoja de validación.

**Tests**: validación contra todos los casos de `docs/05-temas.md`, cálculo de contraste y
corrección automática.

## Hito 8 · Terminaciones

- Adaptación a 736×414 (8 Plus).
- VoiceOver: etiquetas en todos los botones de ícono, y anuncios del aviso y del panel de
  volumen.
- Revisar la checklist de `docs/06-cumplimiento.md` punto por punto.
- README completo:
  - cómo crear la app en Spotify;
  - requisitos;
  - zonas grises;
  - créditos a LRCLIB.
