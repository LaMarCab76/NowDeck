# 06 · Cumplimiento con Spotify

Fuentes:
- Design & Branding Guidelines: https://developer.spotify.com/documentation/design
- Developer Policy: https://developer.spotify.com/policy/
- Developer Terms: https://developer.spotify.com/developer-terms-of-use/

Romper estas reglas puede hacer que Spotify revoque el acceso a la API.

## Checklist por pantalla

- [ ] **Atribución**: toda pantalla con contenido de Spotify (Reproducción, modo letras,
  Biblioteca, mini reproductor) muestra el **logo oficial de Spotify**.
  - Logo completo: 70 px de mínimo digital. Ícono solo: 21 px de mínimo.
  - Zona de exclusión igual a la mitad del alto del ícono.
  - Sobre fondos oscuros, logo blanco. El verde, solo sobre negro o blanco.
  - El asset se descarga del sitio de Spotify (*Design Resources*) y va en
    `Resources/Assets.xcassets`. **No dibujarlo a mano.**
- [ ] **Enlace de vuelta**: el logo (y el nombre de la playlist o el álbum) abre el contenido en
  Spotify.
  - Si la app de Spotify está instalada, usar el enlace universal `open.spotify.com/...`. Si no,
    mandar a la App Store.
  - Debe existir un texto visible "ABRIR SPOTIFY" en algún lugar de la app. Está en Biblioteca y
    en Nada sonando.
- [ ] **Carátulas**: se usa la de Spotify tal cual, con radio de 4 pt. **Sin recortar, sin
  difuminar, sin superponerle texto, controles ni logos.**
- [ ] **Metadatos**: nombres sin modificar.
  - Si se truncan, tiene que haber forma de verlos completos (marquesina o toque).
  - Hay que dejar lugar para al menos 25 caracteres en playlist o álbum, 18 en artista y 23 en
    tema.
- [ ] **Controles**: deshabilitar u ocultar lo que `actions.disallows` prohíba. Las guidelines:
  "Play controls must either have a disabled state to indicate that they are restricted or
  they should not be displayed at all". Nowdeck los deshabilita (ver `docs/03`, "`actions`").
- [ ] **Progreso**: informativo, sin ningún indicio de que se pueda adelantar.
- [ ] **Podcasts**: mostrar el título del episodio y el nombre del podcast. Saltos de ±15 s para
  episodios: **aplica** (verificado el 2026-11-17 en *Design & Branding Guidelines* → "Playing
  views"). La sección empieza con "If you choose to show play controls in your app, the
  following requirements need to be followed" y pide "Podcasts need to have the option to seek
  15 seconds forward or backwards" (también para muestras de audiolibros). Nowdeck muestra
  controles, así que en los episodios −15 s y +15 s reemplazan a Anterior y Siguiente
  (`PUT /me/player/seek`). La misma sección *recomienda* no ofrecer más controles que
  play/pausa: es una recomendación, no una regla, y el diseño de Nowdeck la deja de lado a
  propósito.
- [ ] **Fondo del reproductor**: tomar el color de la carátula. Si no se puede, usar un color
  oscuro.
- [ ] **Filas de contenido**: como máximo **20 ítems** por fila, y cada fila termina con un
  enlace a la app de Spotify.
- [ ] **Explícito**: marcar los temas con `explicit: true`.
- [ ] **Nombre y logo de Nowdeck**:
  - Sin "Spotify" y sin nada que empiece con "Spot" o suene parecido.
  - "para Spotify" está permitido como bajada.
  - El ícono de la app no puede parecerse al de Spotify: nada de círculo verde ni de ondas.

## Política (lo que no se puede hacer)

- **Imitar o reemplazar una experiencia central de Spotify** sin permiso: no copiar pantallas de
  Spotify ni del Car Thing. El diseño de Nowdeck es propio y así tiene que quedar.
- **Controlar Spotify por voz**.
- **Sugerir aval, vínculo o co-branding** de Spotify. El primer inicio ya incluye el aviso
  "proyecto independiente, no afiliado".
- Usar contenido de Spotify para entrenar modelos de IA, o analizarlo para hacer métricas.
- Uso comercial o en negocios, como música en un local.

## Zonas grises (documentar en el README)

- **Client ID propio por usuario**: Spotify no lo prohíbe ni lo avala por escrito. Es la única
  forma práctica de distribuir una app abierta con el límite de 5 usuarios.
- **Letras de LRCLIB**: la política prohíbe productos integrados con contenido de otro servicio.
  Por eso la función está apagada por defecto y explicada.

- **Carpetas de playlists (experimental, opcional)**: decisión del dueño del 2026-11-17. La Web
  API no da las carpetas; con la opción activa, Nowdeck lee el *rootlist* del servicio interno
  de playlists de Spotify (`spclient.wg.spotify.com`), que no está documentado ni aprobado
  para apps de terceros y choca con los Developer Terms. Por eso:
  - está **apagada por defecto** y se ofrece con los riesgos explicados (paso opcional de la
    configuración y Ajustes → Reproductor);
  - solo manda el token de la Web API del usuario: **no** imita al cliente de Spotify (nada de
    `client-token` ni token del reproductor web);
  - si el servicio rechaza el pedido, la biblioteca muestra la lista plana con un aviso.
  Nadie lo probó todavía con una cuenta real; lo más probable es que Spotify rechace ese token.

- **Foto del artista de fondo**: decisión del dueño del 2026-11-17, para parecerse a la app de
  TV de Spotify. La referencia de *Get Artist* dice "Spotify visual content must be kept in its
  original form, e.g. you can not crop album artwork, overlay images on album artwork…". La
  foto se muestra recortada para llenar la pantalla, más tenue y desvanecida hacia el color de
  fondo, así que esto choca con la letra de esa frase. Las reglas de la guía de diseño
  ("Artwork must be kept in its original form… This includes applying overlays and blurring")
  están bajo "For album and podcast artwork" y no nombran las fotos de artistas. El dueño lo
  considera aceptable porque es uso personal, sin distribución. Para limitar el riesgo:
  - la **carátula** sigue intacta (sin recortar ni tapar); la foto va solo en el fondo;
  - se puede apagar en Ajustes → Apariencia → "Foto del artista" (y entonces no se pide);
  - el contenido sigue atribuido (ícono de Spotify y enlace de vuelta en la fila superior).
  El Canvas (video en loop) no está en la Web API y no se trae.
- **Controles "parecidos al Car Thing"** (pedido del dueño del 2026-11-17): se tomó solo la
  idea de una fila centrada con más aire entre los botones. Los botones, colores y medidas
  siguen siendo los de Nowdeck: no se copió la pantalla del Car Thing.

## App Store (si algún día se publica)

- Apple puede pedir pruebas de que podés mostrar las carátulas. En las capturas de la tienda,
  usar carátulas genéricas propias.
- **Política de privacidad**: Nowdeck no recolecta datos. Los tokens quedan en el dispositivo y
  solo se habla con Spotify y con LRCLIB.

## Revisión del Hito 8 (2026-11-17)

Repaso punto por punto sobre la rama `hito/08-terminaciones` (hitos 1 a 7 integrados).
✅ cumple · ⚠️ pendiente del dueño · ❌ no cumple, con el motivo.

### Atribución

- ✅ **Logo oficial (2026-11-17)**: el dueño trajo los archivos de *Design Resources* (kit
  2024). `SpotifyIcon` (ícono blanco) va junto al origen en Reproducción y en el modo letras;
  `SpotifyLogo` (logo completo blanco) en Biblioteca. Los SVG oficiales solo se volvieron a
  guardar con el relleno blanco escrito en cada trazo, porque el catálogo de assets no lee los
  bloques `<style>`. Ícono de 24 pt (mínimo 21) con 12 libres (la mitad del alto). Lo que
  sigue de este punto es el estado anterior.
- ⚠️ **Logo oficial**: el lugar está en Reproducción (108×30 en una zona de 44, a la izquierda
  de la fila superior), modo letras (arriba a la derecha) y Biblioteca (fila de pestañas, que
  también cubre el mini reproductor). El asset `SpotifyLogo` está **vacío a propósito**: falta
  que el dueño agregue el archivo oficial blanco de *Design Resources*. Mientras tanto,
  Reproducción y Biblioteca muestran el hueco vacío (se puede tocar) y el modo letras un
  recuadro punteado con el texto "LOGO SPOTIFY". Nunca se dibuja ni se imita el logo.
- ✅ **Tamaño y zona de exclusión**: 108 pt de ancho (mínimo 70) y 15 pt libres entre el logo y
  "Desde la playlist" (la mitad de 30). El mockup tenía 10; se usa 15 por la guía.
- ⚠️ **Color del logo**: el código no lo tiñe; depende de que el archivo que se agregue sea la
  versión blanca, porque todos los fondos son oscuros.

### Enlace de vuelta

- ✅ El logo abre el contenido en Spotify (el contexto o el tema; en Biblioteca, la portada de
  Spotify). El nombre de la playlist o el álbum también ("Desde la playlist …" en Reproducción,
  el nombre en el modo letras, y "Abrir en Spotify" en el menú de cada tarjeta).
- ✅ Enlace universal `open.spotify.com` con `universalLinksOnly`; si Spotify no está
  instalado, se abre su página en la App Store (`SpotifyLink`). Solo se abren URLs de
  `https://open.spotify.com`.
- ✅ Texto visible "ABRIR SPOTIFY ↗" en Biblioteca y en Nada sonando, además de la tarjeta "Ver
  más en Spotify" al final de cada fila.

### Carátulas

- ✅ Se muestran tal cual (`.fit`, sin recortar), con radio de 4 pt, sin texto, controles ni
  logos encima, en Reproducción, modo letras, mini reproductor y tarjetas.
- ✅ Corregido en este hito: mientras arranca una tarjeta se atenuaba la tarjeta entera,
  carátula incluida. Ahora se atenúan solo los textos.
- ⚠️ **Superposiciones pasajeras**: el panel de volumen (520×64, centrado arriba, como en
  `Volumen.dc.html`) y los avisos (píldora centrada arriba) quedan unos segundos sobre la
  esquina superior derecha de la carátula. Es el diseño de los mockups y no tapa nada de forma
  permanente, pero la guía dice "sin superponerle controles". Opciones: dejarlo así, o centrar
  el panel y los avisos sobre la columna de texto en lugar de la pantalla. No se cambió.

### Metadatos

- ✅ Nombres sin modificar: todo nombre que viene de Spotify se muestra con
  `Text(verbatim:)` (ni traducido ni interpretado como Markdown).
- ✅ **Nombres truncados legibles** (nuevo en este hito): se eligió la **marquesina**, que
  ofrecen tanto esta guía como `docs/02`. Un teléfono en el escritorio se lee de un vistazo y
  casi todos los textos que se pueden cortar ya son botones (el origen abre Spotify, el
  dispositivo abre la hoja), así que "tocar para ver completo" chocaba con esas acciones.
  - Se desplazan, solo si no entran: título (dos líneas; si no alcanzan, una línea que se
    desplaza), artista, "Desde la playlist …" y "Reproduciendo en …" en Reproducción; nombre
    del origen, título, artista y dispositivo en el modo letras; título · artista y "Suena en
    …" en el mini reproductor. Pausa de 3 s al inicio, 30 pt/s, borde derecho desvanecido. Con
    *Reducir movimiento* hace una sola pasada cada vez que cambia el texto.
  - Las tarjetas de Biblioteca no se desplazan: tocarlas reproduce, y mantenerlas apretadas
    muestra el nombre completo (vista previa del menú contextual).
  - VoiceOver siempre lee el texto completo.
- ⚠️ **25 caracteres para la playlist o el álbum en Reproducción**: la fila superior deja poco
  lugar a "Desde la playlist **Nombre**" (unos 13 caracteres del nombre en 896 pt y casi nada en
  736 pt). Con la marquesina el nombre se puede leer entero, pero no hay lugar *visible* para
  25 caracteres. Pendiente de la decisión de diseño del dueño.
- ⚠️ **25 caracteres en las tarjetas de Biblioteca**: el nombre va en una línea de 150 pt a
  16 pt semibold (como el mockup), donde entran unos 17 caracteres. El nombre completo se ve
  manteniendo apretada la tarjeta. Si hace falta cumplir la regla al pie de la letra, la
  propuesta es permitir dos líneas en el nombre (+22 pt de alto por fila; entra en 414 pt).
- ✅ 18 caracteres de artista y 23 de tema: el artista tiene una línea de 22 pt en una columna
  de ~512 pt (896) o ~388 pt (736), y el título dos líneas de 40 pt: entran de sobra en los dos
  tamaños. En el modo letras y el mini reproductor también.

### Detalle de playlist o álbum (agregado el 2026-11-17)

- ✅ **Atribución y enlace de vuelta**: el logo y "ABRIR EN SPOTIFY ↗" de la fila superior
  abren la playlist o el álbum en Spotify; en una playlist de otra persona también "Ver en
  Spotify". Mantener apretado un tema ofrece "Abrir en Spotify" con la página del tema.
- ✅ **Carátula**: 150×150, `.fit`, radio 4, sin nada encima; "Reproducir" va debajo.
- ✅ **Explícito**: la lista marca con "E" los temas con `explicit: true`.
- ✅ **Nombres truncados legibles**: el nombre y el subtítulo de la columna izquierda usan la
  marquesina; en la lista, mantener apretado un tema muestra el título y los artistas
  completos. VoiceOver lee todo.
- ⚠️ **25 caracteres para el nombre de la playlist o el álbum**: la columna de 170 pt a 18 pt
  bold deja unos 17 caracteres visibles. Mismo caso que las tarjetas: se lee entero con la
  marquesina, pero no hay lugar *visible* para 25. Pasarlo a dos líneas no entra en los 252
  pt del bloque junto con "Reproducir".
- ✅ **23 caracteres de tema y 18 de artista** en la lista: el título tiene unos 510 pt en
  896 y unos 350 en 736.
- ⚠️ **Máximo de 20 ítems por fila**: se interpretó que no se aplica a la lista de temas, que
  no es una fila de contenido sino el contenido de una playlist o un álbum. Se carga completa,
  de a 50. Propuesto al dueño el 2026-11-17, falta su confirmación. La alternativa es cortar
  en 20 y terminar con "Ver todo en Spotify".

### Controles

- ✅ Lo que `actions.disallows` prohíbe se muestra **deshabilitado** (atenuado y sin acción), y
  todo queda deshabilitado en un dispositivo con `is_restricted`. Ver `docs/03`, "`actions`":
  sigue pendiente del dueño confirmar con una respuesta real que llega `disallows`.
- ✅ Progreso informativo: barra sin perilla ni arrastre, y VoiceOver la lee como "Progreso,
  1:25 de 3:47" sin acción de ajuste.

### Podcasts

- ✅ Episodios: título del episodio y nombre del podcast (en el lugar del artista).
- ✅ −15 s y +15 s en lugar de Anterior y Siguiente.

### Fondo del reproductor

- ✅ Color tomado de la carátula y suavizado; sin carátula (o si Ajustes elige Negro o Gris
  oscuro), el fondo del tema, que es oscuro.

### Filas de contenido

- ✅ Como máximo 20 ítems por fila (`LibraryModel.rowLimit`), y cada fila termina con la
  tarjeta "Ver más en Spotify".

### Explícito

- ✅ Marca "E" en Reproducción y en el mini reproductor. Corregido en este hito: faltaba en el
  modo letras (fila inferior).
- ✅ Las tarjetas de Biblioteca (playlists, álbumes, podcasts, audiolibros) no traen la marca
  `explicit` en la API, así que no aplica. Los resultados de búsqueda todavía no tienen
  pantalla.

### Nombre y logo de Nowdeck

- ✅ Nombre visible "Nowdeck" (`CFBundleDisplayName`), sin "Spotify" ni nada parecido.
- ⚠️ **Ícono de la app**: `AppIcon` todavía no tiene imagen. Cuando se haga: nada de círculo
  verde ni ondas.

### Política

- ✅ No hay control por voz, analytics, ni backend; el contenido de Spotify no se guarda para
  métricas ni se usa para entrenar nada.
- ✅ Aviso "proyecto open source independiente, no afiliado a Spotify" en la Bienvenida y en
  el README.
- ✅ Diseño propio: no copia pantallas de Spotify ni del Car Thing.

### Zonas grises

- ✅ Documentadas en el README (Client ID propio, letras de LRCLIB).
- ⚠️ **Letras apagadas por defecto**: esta guía y `docs/04` piden que la función de letras
  arranque **apagada**, pero `docs/05` define que el tema por defecto incluye `"letras"` en
  `reproductor.controles`, y "Mostrar letras" se guarda en el tema (decisión de la
  integración). Hoy el botón de letras aparece en una instalación nueva y en los cuatro
  temas preestablecidos. No se cambió porque toca el formato de los temas y los archivos de
  `themes/`. Propuesta: sacar `"letras"` de los controles por defecto y de los temas de
  ejemplo, y que "Mostrar letras" lo agregue al activarse.

### Otros pendientes del dueño relacionados

- ⚠️ `play: true` al transferir la reproducción (`docs/03`, "Dispositivos"): se mantiene como
  está hasta que el dueño decida.
- ⚠️ El tipo de documento alternativo `public.json` para abrir temas: sin cambios, pendiente.
- ⚠️ Usuario de GitHub en el User-Agent de LRCLIB (`<usuario>` en `LRCLIBClient.projectURL`).
