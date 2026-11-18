# 02 · Diseño

La fuente de verdad son los mockups de `design/mockups/*.dc.html`: los valores exactos están en
los `style="…"` de cada archivo. Este documento los resume. Las medidas están en **puntos (pt)**
sobre el lienzo de referencia de **896×414** (horizontal) o **414×896** (primer inicio).

## Tokens

### Colores (tema por defecto "Negro y verde")

| Token | Valor | Uso |
|---|---|---|
| `fondo` | `#000000` | Fondo general |
| `fondoReproductor` | color de la carátula, suavizado (ejemplo `#34465A`) | Reproducción y mini reproductor |
| `superficie` | `#161616` | Hojas (Dispositivos, Importar tema) |
| `superficieSutil` | blanco al 7–10 % | Botones píldora, filas, contenedor de pestañas |
| `texto` | `#F2EEE8` | Texto principal, botón de play |
| `textoSecundario` | `#D5DCE4` | Artista en el reproductor |
| `textoTerciario` | `#A9B4C0` | Tiempos, íconos secundarios |
| `textoCuerpo` | `#C9C4BC` | Párrafos y subtítulos de tarjetas |
| `etiqueta` | `#A39D95` | Etiquetas en mayúsculas (monoespaciada) |
| `letraPendiente` | `#8E99A6` | Palabras por cantar y estrofa siguiente |
| `acento` | `#2FD566` | Resaltado, dispositivo activo, interruptores, botón principal |
| `textoSobreAcento` | `#00170A` | Texto sobre botones con fondo de acento |
| `advertencia` | `#FFB23E` | Ícono de advertencia en la importación de temas |
| `bordeChip` | blanco al 35 % | Filtros sin seleccionar |

El verde es parecido al de Spotify **a propósito pero no igual**. Spotify reserva su verde
(`#1DB954`) para su propia marca.

Contrastes verificados sobre `#34465A`, el fondo de ejemplo del reproductor:

| Texto | Contraste |
|---|---|
| `texto` | 8,4:1 |
| `textoSecundario` | 7,0:1 |
| `textoTerciario` | 4,6:1 |
| `acento` | 5,0:1 |
| `letraPendiente` | 3,3:1 (solo en texto de 22 pt o más) |

### Tipografía

Los mockups usan Space Grotesk (títulos) e IBM Plex Mono (etiquetas y tiempos) como
aproximación. En iOS hay que usar **la fuente del sistema**, como piden las guidelines de Spotify:

| Uso | iOS | Tamaño / peso |
|---|---|---|
| Título del tema | `.system` | 40 pt bold (2 líneas máx.) |
| Artista | `.system` | 22 pt regular |
| Títulos de pantalla | `.system` | 34 pt bold (Ajustes), 24 pt bold (hojas) |
| Pestañas Biblioteca/Buscar | `.system` | 17 pt bold |
| Cuerpo | `.system` | 15–16 pt |
| Etiquetas en mayúsculas | `.system(design: .monospaced)` | 12 pt, tracking +0.08em |
| Tiempos de reproducción | `.system(design: .monospaced)` | 12 pt |
| Estrofa actual | `.system` | 30 pt bold, interlineado 38 |
| Estrofa siguiente | `.system` | 22 pt semibold, interlineado 30 |

Soportar Dynamic Type donde no rompa el layout fijo del reproductor. En Ajustes y en el primer
inicio, sí.

### Formas y movimiento

- Carátulas: radio **4 pt** (guideline de Spotify). Nunca recortar, tapar ni superponer nada.
- Botones píldora: radio igual a la mitad del alto. Tarjetas y filas: 12–16 pt. Hojas: 20 pt
  arriba.
- Zonas táctiles de **44 pt** como mínimo.
- Íconos: trazo 2 pt, estilo lineal. Usar SF Symbols equivalentes cuando existan.
- **Cambios de tema y de letra** (pedido del dueño, 2026-11-17; no están en los mockups):
  carátula con fundido cruzado (0,45 s); título y artista suben 10 pt y se desvanecen
  (0,35 s); la estrofa actual sube 18 pt mientras entra la siguiente (0,35 s); vista normal ⇄
  modo letras con fundido (0,3 s). Con *Reducir movimiento* quedan solo los fundidos.

## Reproducción (`Main.dc.html`)

- **Márgenes**: 24 arriba, 48 a los costados, 20 abajo. Separación vertical entre bloques: 20.
- **Bloque superior** (alto 256):
  - **Carátula** de 256×256 a la izquierda, a 32 de la columna de texto.
  - **Fila superior de la columna**:
    - ícono de Spotify (24, en una zona de 44; es un enlace a Spotify) a 12 del origen
      (decisión del dueño del 2026-11-17: el ícono en lugar del logo completo de 108×30);
    - "Desde la playlist **Nombre**" en 13 pt, que se corta con "…";
    - a la derecha, la píldora **Biblioteca** (44 de alto) y el botón **Ajustes** (44).
  - **Título y artista** (ver tipografía). El texto truncado tiene que poder verse completo:
    marquesina o toque para expandir.
  - **"Reproduciendo en Nombre"** en acento, 15 pt. Al tocarlo se abre Dispositivos.
- **Bloque inferior**, a todo el ancho:
  - **Progreso**: tiempo actual · barra de 4 de alto (pista blanca al 18 %, relleno `texto`) ·
    duración. Es **informativa**: sin perilla y sin arrastre.
  - **Controles** (alto 64), en tres grupos:
    - izquierda, en 200 de ancho: Aleatorio y Repetir (48);
    - centro, separados 20: Anterior (56), Play/Pausa (64, círculo `texto` con ícono oscuro)
      y Siguiente (56);
    - derecha, en 200 de ancho: Letras (48; solo si está activado en Ajustes; activo =
      acento sobre acento al 16 %) y Volumen (48).
- Deshabilitar u ocultar los controles que la API marque como no permitidos (`actions.disallows`).

### Rediseño del 2026-11-17 (pedido del dueño)

Cambia lo anterior en estos puntos (no está en los mockups):

- **Fila superior a todo el ancho** (44), arriba de la carátula: el ícono de Spotify y el
  origen en la esquina superior izquierda; **Cola** y **Biblioteca** a la derecha (Cola
  primero; ver "Cola"). Con todo el ancho, el origen tiene lugar visible para más de 25
  caracteres.
  - Desde el 2026-11-18 (pedido del dueño) nada de esta fila lleva píldora: el origen va en
    dos líneas, "Desde la playlist" en 12 medium `textoSecundario` arriba y el nombre en 15
    bold `texto` abajo (igual que en el modo letras), a 12 del ícono, que queda afuera del
    botón para respetar su espacio libre. Cola y Biblioteca son ícono y texto (15 semibold)
    sin fondo, separados 24; la zona de toque sigue siendo de 44 de alto.
  - Margen de arriba 12 (era 24 en el mockup y 16 antes del 2026-11-18) y 14 entre la fila y
    la carátula (era 4), así que entre el texto del origen y la carátula quedan unos 18.
- **Carátula de 210** (era 256, y 216 antes del 2026-11-18) y alto del bloque de la carátula
  210. El modo letras ocupa la fila y el bloque juntos (268). Cuenta vertical:
  12 + 44 + 14 + 210 + 20 + 94 + 20 = 414.
- **Ajustes** ya no está en el reproductor: se abre desde la cabecera de Biblioteca (ícono a
  la izquierda del logo de Spotify, con 20 de separación).
- **Controles en una sola fila centrada**, con 36 entre todos los botones. Los opcionales
  del tema se reparten a los dos lados igual que antes (`PlayerControlLayout`), y los dos lados
  ocupan el mismo ancho flexible, así que Play/Pausa queda siempre en el centro exacto. Con los
  siete botones la fila mide 584 (entra en los 640 del 8 Plus).
- **Deslizar para pasar de tema**, como un carrusel:
  - El arrastre puede empezar en cualquier punto de la franja de la carátula y el título, de
    borde a borde de la pantalla. Solo cuenta si arranca más horizontal que vertical (se
    decide a los 8). La barra de progreso, los controles y la fila del origen quedan fuera,
    con sus propios gestos.
  - Arrastrar a la izquierda trae el siguiente y a la derecha el anterior. La carátula, el
    título y el dispositivo siguen al dedo, y volver más allá del inicio muestra el otro.
  - Del costado correspondiente entra la "página" del otro ítem, una pantalla más allá: desde la derecha el
    siguiente de la cola (`GET /me/player/queue`), desde la izquierda el anterior (el que la
    app vio sonar antes; la Web API no lo da). La fila del dispositivo se mueve con su página
    (si quedara quieta, la carátula pasaría por debajo); la fila del origen y todo lo de abajo
    quedan quietos.
  - Si el ítem no se conoce todavía, la página muestra un cuadrado vacío con el ícono de
    siguiente o anterior y "Siguiente" o "Anterior".
  - Al soltar después de 96 (o con un deslizamiento rápido), la página nueva termina de entrar
    (0,25 s), el teléfono vibra (impacto medio) y se manda Siguiente o Anterior. Cuando Spotify
    informa el ítem nuevo, las páginas vuelven a su lugar sin animación. Si en 2,5 s no
    informa otro ítem (por ejemplo, "anterior" que solo reinició el tema), vuelve atrás.
  - Si Spotify no permite ese salto, el contenido se resiste (un tercio del recorrido, hasta
    40) y al soltar vuelve.
  - También en episodios pasa de ítem (los botones de episodios siguen siendo ±15 s).
  - En **modo letras** la franja es la fila de abajo (carátula chica, título, artista y
    dispositivo), nunca las letras. Esa fila se mueve igual y entra la del otro ítem.
- **Fondo "Foto del artista"** (estilo app de TV de Spotify): cuarta opción de FONDO DEL
  REPRODUCTOR (`fondoReproductor: "artista"`). Usa la foto más grande de `GET /artists/{id}`
  del primer artista, a pantalla completa (`fill`).
  - Desde el 2026-11-18 (pedido del dueño) la foto va sola y entera: sin fundido hacia la
    carátula ni el color de la carátula abajo. El color de la carátula solo se ve mientras la
    foto carga o si el artista no tiene foto.
  - Encima, una capa negra la oscurece un poco (**Oscurecer**, `oscurecerFondo`, 30 % por
    defecto). El 100 % es negro al 80 %: la foto nunca desaparece del todo.
  - Zoom lento de 1 a 1,06 en 30 s, ida y vuelta (sin zoom con *Reducir movimiento*), y
    fundido de 0,8 s al cambiar de artista.
  - Con esta opción aparecen los deslizadores **Desenfoque** y **Oscurecer** (0 a 100 %, de
    a 5; `desenfoqueFondo` y `oscurecerFondo` del tema). El 100 % de desenfoque es un radio de
    30. Se guardan al soltar. Ver "Ajustes" para la vista previa.
  - Spotify da una sola foto por artista (en tres tamaños), así que no rota entre fotos.
  - Ver `docs/06`, "Zonas grises".

### Modo letras

Reemplaza el bloque superior:

- **Fila superior** (44): el ícono de Spotify y, a 12, "Desde la playlist" en 12 pt arriba y
  el nombre en 15 pt bold abajo, a la izquierda. El mockup tenía el logo a la derecha; el
  dueño lo pasó junto al origen el 2026-11-17, igual que en la vista normal.
- **Letras**, centradas en el espacio que queda:
  - estrofa actual y estrofa siguiente, al ancho de "Ancho de las letras" (50 %, **66,7 %** o
    100 % del ancho útil);
  - sin cortes de línea forzados, `text-wrap` equilibrado y separación de 12.
  - **Por palabra**: lo ya cantado en `texto` y lo pendiente en `letraPendiente`.
  - **Estrofa completa**: toda la estrofa actual en `texto`.
- **Fila inferior** (56): carátula de 56 (radio 4), título en 18 bold, artista en 15 y, a la
  derecha, el dispositivo en acento.
- Biblioteca y Ajustes no se muestran.

### Panel de volumen

- Píldora de 520×64, centrada, con radio 32 y fondo `rgba(8,10,14,0.94)` con sombra.
- **Posición** (pedido del dueño, 2026-11-18; el mockup la ponía a 16 del borde superior):
  a 16 del borde **inferior**. Mientras está abierta, el resto del reproductor se achica hacia
  arriba (escala 0,78, anclado arriba al centro) para dejarle lugar: en 414 de alto quedan 92
  abajo, los 64 + 16 del panel y 12 de aire. El fondo y los avisos no se achican. Al cerrarse,
  el reproductor vuelve a su tamaño con la misma animación. Mientras está abierta no se puede
  deslizar entre temas.
- Contenido: [−] (48) · ícono de parlante · barra de 8 de alto (relleno en acento) · valor en
  monoespaciada de 14 · [+] (48). Cada toque cambia el volumen 5 %.
- **Arrastre** (pedido del dueño, 2026-11-17): toda la fila de 44 alrededor de la barra toma
  el dedo; tocar o arrastrar fija el nivel al instante. Mientras se arrastra se manda como
  máximo un cambio cada 250 ms, y el valor final al soltar.
- **Entrada**: sube desde `y = +112` (debajo de la pantalla) hasta 0 en 0,30 s, con curva
  `(0.2, 0.8, 0.2, 1)`; el reproductor se achica con la misma curva.
- **Salida**: a los 3 s sin interacción, en 0,22 s ease-in.
- **Se muestra** al tocar Volumen, al tocar − o +, o cuando el polling detecta otro volumen.
- Si el dispositivo no soporta cambiar el volumen (`supports_volume: false`), el panel lo
  indica y deshabilita − y +.

### Aviso (toast)

- Píldora de 48 de alto, centrada a 20 del borde superior, con fondo `texto` y texto oscuro en
  15 semibold, más un ícono.
- `accessibilityLabel` anunciado como estado. Dura 3 s.

### Fondo según la carátula

1. Reducir la carátula a ~32×32 y calcular el color **más frecuente**, descartando los casi
   negros y casi blancos. No usar el promedio de toda la imagen.
2. Pasarlo a HSL u OKLCH, limitar la **saturación a 25–35 %** y fijar la **luminosidad en
   25–30 %**.
3. Si `textoTerciario` queda por debajo de 4,5:1, oscurecer un paso más.
4. Transición de ~0,5 s entre temas. Cachear el resultado por ID de álbum.
5. Si no hay carátula, usar `fondo`.

## Biblioteca (`Biblioteca.dc.html`)

- **Márgenes**: 28 arriba, 48 a los costados, 10 abajo. Los bloques se distribuyen con
  `space-between`.
- **Fila 1**:
  - control segmentado con **Biblioteca** y **Buscar** (contenedor de 44, radio 22, blanco al
    8 %, relleno de 4 y corrido −4 para que la pestaña activa se alinee con los filtros;
    pestaña de 36, radio 18, activa con fondo `texto` y texto negro);
  - logo de Spotify a la derecha.
- **Fila 2** (solo en Biblioteca):
  - filtros Playlists, Álbumes, Podcasts y Audiolibros (36 de alto, radio 18, borde de 1,5;
    el activo, relleno `texto`);
  - "ABRIR SPOTIFY ↗" en monoespaciada a la derecha.
- **Tarjetas**: carátula de 150×150 (radio 4), nombre en 16 semibold y subtítulo en 13, con 20
  entre tarjetas. La fila se desliza en horizontal y llega hasta el borde derecho de la
  pantalla. Tocar una playlist o un álbum abre su detalle. Mantener la tarjeta apretada
  ofrece "Reproducir" directamente. Los podcasts y audiolibros se abren en Spotify.
- **Carpetas de playlists** (opción experimental): al abrir una carpeta, la fila muestra
  su contenido y "‹ Volver" reemplaza los filtros. Al cerrar el detalle de una playlist
  se vuelve a la carpeta desde la que se abrió.
- **Buscar**: campo de 56 (radio 28, blanco al 10 %) con el placeholder "Temas, artistas,
  álbumes, podcasts o audiolibros" y una línea de ayuda.
- **Mini reproductor** (56, radio 14, fondo según la carátula): carátula de 40, título y
  artista, "Suena en **Dispositivo**" en acento (abre Dispositivos) y Pausa (44).

## Detalle de playlist o álbum (`Detalle.dc.html`)

Se abre al tocar una tarjeta de playlist o álbum. Mantiene los márgenes de la Biblioteca y el
mini reproductor; la fila de filtros y las tarjetas se reemplazan por el detalle.

- **Fila 1** (44): "‹ Biblioteca" a la izquierda (píldora de 36, radio 18, blanco al 8 %,
  17 bold, relleno 10/16, corrida −4 como las pestañas). A la derecha, "ABRIR EN SPOTIFY ↗"
  en monoespaciada (abre la playlist o el álbum) y el logo, con 20 entre los dos.
- **Bloque central** (252), en dos columnas con 32 entre ellas:
  - **Izquierda** (170): carátula de 150×150 (radio 4), nombre en 18 bold (interlineado 22,
    una línea con marquesina si no entra) a 10 de la carátula, subtítulo en 13 `textoCuerpo`
    ("De <dueño> · N temas" o "<artistas> · <año>") y, abajo, **Reproducir**: 150×44, radio
    22, fondo `acento`, texto `textoSobreAcento` 16 bold con ícono de play de 16.
  - **Derecha**: "48 TEMAS · 2 H 51 MIN" en monoespaciada 12 `etiqueta` (+0.08em, alto 22;
    la duración aparece cuando están todos los temas cargados) y la lista con scroll vertical.
    Filas de 50 con línea superior blanca al 10 %: número (monoespaciada 12 `textoTerciario`,
    22 de ancho, alineado a la derecha), 14 de separación, título 16 semibold (interlineado 21)
    con la marca "E" (15) si es explícito, artistas en 13 `textoCuerpo` y duración en
    monoespaciada 12. Los temas no disponibles van al 40 %. Abajo, un desvanecido de 36 hacia
    el fondo. Se cargan de a 50 al llegar al final.
  - **Playlist de otra persona**: en lugar de la lista, candado (28, `etiqueta`), "Spotify no
    muestra los temas de esta playlist" (20 bold, interlineado 26), una línea de ayuda (15/22)
    y "Ver en Spotify ↗" (botón contorneado de 44, borde blanco al 35 %), todo en un ancho
    máximo de 440 y centrado en vertical.
- Mantener apretado un tema muestra el nombre completo y "Abrir en Spotify".

## Dispositivos (`Dispositivos.dc.html`)

- Hoja de 640×398 sobre fondo negro, con superficie `#161616`, radio 20 arriba y manija de
  40×5.
- **Cabecera**: círculo de 52 en acento con el ícono del dispositivo, "DISPOSITIVO ACTUAL" en
  acento, el nombre en 22 bold y Cerrar (44).
- "ELEGÍ UN DISPOSITIVO", y debajo filas de 60 con separadores blancos al 10 %: ícono (26),
  nombre (18 medium) y tipo (14).
- **"¿No ves tu dispositivo?"** (botón de texto con ícono) abre una vista dentro de la hoja con:
  1. Abrí Spotify en ese dispositivo.
  2. Usá la misma cuenta de Spotify que esta app.
  3. Si es un parlante o una tele, despertalo primero.

  Más "Actualizar lista" (principal) y "Volver a la lista".

## Cola (`Cola.html`)

- La misma hoja que Dispositivos: 640×398 sobre fondo negro, superficie `#161616`, radio 20
  arriba, manija de 40×5 (arrastrarla hacia abajo la cierra).
- **Cabecera** (alto 56): carátula de 56, "SONANDO" en acento (12 mono, +0,08em), el título en
  20 bold y los artistas en 14 `textoCuerpo` (con la marca de explícito delante, como en el
  reproductor); a la derecha, el logo de Spotify (enlace al tema)
  y Cerrar (44). Título y artistas largos se desplazan (marquesina).
- "A CONTINUACIÓN" (12 mono, `etiqueta`) y filas de 56 con separadores blancos al 10 %:
  número (12 mono), carátula de 40 (sin recortar, radio 4), título 16 semibold con la marca
  de explícito, artistas 13 `textoCuerpo` y duración (12 mono). Hasta **20** temas.
- Las filas **no son botones**: mantenerlas apretadas muestra el nombre completo y "Abrir en
  Spotify", como en el detalle. Abajo, un degradado de 40 hacia la superficie.
- Al final de la lista: "Para quitar o reordenar temas, usá Spotify." (14, `textoCuerpo`) y
  "ABRIR SPOTIFY ↗".
- **Cola vacía**: ícono de lista, "No hay nada en la cola" (20 bold) y "Cuando termine este
  tema, Spotify decide qué sigue. Podés elegir algo desde la Biblioteca." (15, ancho máximo
  440).
- **Error**: la línea de aviso de Dispositivos y "Reintentar" (cápsula de acento de 48).
- Se lee al abrir, cuando empieza otro tema con la hoja abierta (también si el mismo tema
  vuelve a empezar, por ejemplo porque estaba dos veces seguidas en la cola) y al deslizar
  hacia abajo la lista (también con la cola vacía). No hace polling propio: usa el del
  reproductor, que sigue andando mientras la hoja está abierta.
- **Botón**: "Cola" en la fila superior, a la izquierda de Biblioteca y con su mismo estilo
  (44 de alto, ícono y texto 15 semibold; sin píldora desde el 2026-11-18). Siempre está, salvo en
  modo letras: su fila superior conserva el ícono de Spotify y el origen, pero no lleva Cola
  ni Biblioteca.
- Diferencias con el mockup (decisión del dueño, 2026-11-17):
  - El mockup pone el botón en el grupo derecho de controles. Desde el rediseño los
    controles van en una sola fila centrada con 36 entre botones, y uno más no entra en el
    iPhone 8 Plus (ese lado necesitaría 216 y tiene 160), así que pasó a la fila superior.
  - No es un control del tema (`reproductor.controles`): los temas guardados antes de que
    existiera listan sus controles y nunca lo mostrarían.
  - El ícono es el símbolo `list.bullet` de SF Symbols (tres renglones con viñetas); el
    mockup dibuja renglones con un triángulo de reproducción.

## Ajustes (`Ajustes.dc.html`)

- **Columna izquierda** (200): Volver, "Ajustes" en 34 bold y pestañas verticales Apariencia y
  Reproductor (44 de alto, radio 12; la activa con fondo blanco al 12 %).
- **Apariencia**:
  - **TEMA**: chips de 40 con una muestra del acento sobre el fondo del tema.
  - **COLOR DE RESALTADO**: 6 círculos de 32 en zonas de 44; el seleccionado lleva un anillo
    `texto`. Colores: Verde `#2FD566`, Ámbar `#FFB23E`, Celeste `#7CC4FF`, Coral `#FF7A7A`,
    Lavanda `#C9A2FF`, Blanco `#F2EEE8`.
  - **FONDO DEL REPRODUCTOR**: segmentado con Negro, Gris oscuro, **Según la carátula** (por
    defecto) y Foto del artista. Con Foto del artista aparecen **Desenfoque** y **Oscurecer**,
    con una sola nota debajo.
  - **Vista previa del fondo** (pedido del dueño, 2026-11-18): al tocar uno de esos dos
    deslizadores, el resto de Ajustes (columna izquierda, secciones, nota y el otro
    deslizador) se desvanece en 0,25 s y detrás aparece el fondo del reproductor con la foto
    de ejemplo y los valores que se están eligiendo, en vivo. Solo queda el deslizador que se
    está moviendo. Al soltar, Ajustes vuelve con la misma animación y el valor se guarda.
    - Foto de ejemplo: la del artista de lo que suena. Si no suena nada (o suena un episodio),
      la última foto que mostró el reproductor con Ajustes abierto; si no hubo, la del último
      tema escuchado en Spotify (`GET /me/player/recently-played`); si eso no está disponible
      (sesiones sin el permiso nuevo), la del último tema que la app vio sonar (aunque después
      haya parado o haya sonado un episodio). Sin ninguna, se ve el color de fondo del tema.
    - Se busca al aparecer los deslizadores, una vez por apertura de Ajustes, y se cancela al
      cerrar Ajustes.
    - Mientras se ve la foto, el ícono de Spotify (con enlace a Spotify) queda arriba a la
      izquierda, en el mismo lugar que en el reproductor (`docs/06`).
    - Lo que se desvanece tampoco recibe toques: con un dedo en un deslizador, otro dedo no
      puede empezar a mover el otro.
  - **Exportar tema** e **Importar tema**: botones contorneados de 48.
- **Reproductor**:
  - interruptor **Mostrar letras** (pista de 56×32, perilla de 26, encendido en acento);
  - **Ancho de las letras**: Mitad, **2/3** o Completo;
  - nota sobre LRCLIB.

## Importar tema (`TemaImportar.dc.html`)

- Hoja de 800×398. Cabecera con "Importar tema", el nombre del archivo en monoespaciada y
  Cerrar.
- **Izquierda**: el JSON en monoespaciada de 12/17 sobre `#0A0A0A` con borde `#2A2A2A`, con
  scroll.
- **Derecha** (280):
  - estado "Tema válido" (acento) o el error;
  - vista previa con los colores del tema;
  - advertencias con ícono amarillo, por ejemplo de contraste bajo (que se corrige al aplicar);
  - Aplicar tema (principal) y Cancelar.

## Nada sonando (`SinReproduccion.dc.html`)

- Marco punteado de 290 en lugar de la carátula, "Nada sonando" en 40 bold y una línea de
  ayuda.
- Botones "Elegir dispositivo" (principal, 56) y "ABRIR SPOTIFY ↗".

## Primer inicio (`Onboarding1–3.dc.html`, vertical)

1. **Bienvenida**:
   - logo provisorio (rectángulo apaisado con un cuadrado en acento) + "Nowdeck";
   - ilustración de un "deck";
   - título "Tu iPhone, ahora control de escritorio.";
   - lista "VAS A NECESITAR" (Spotify Premium, un navegador, 5 minutos);
   - "Empezar";
   - aviso de que no está afiliada a Spotify.
2. **Crear la app**: "PASO 1 DE 2"; 5 pasos numerados; la caja con `nowdeck://callback` y
   Copiar; "Abrir el panel" (contorno) y "Ya tengo mi Client ID" (principal).
3. **Client ID**:
   - campo monoespaciado de 56 con Pegar; ayuda: "Son 32 letras y números. Se guarda solo en
     este iPhone, en el Llavero";
   - lista de permisos en palabras simples;
   - "Conectar con Spotify".

Pasos agregados después de conectar (2026-11-17, sin mockup; mismo estilo que los anteriores):

4. **Carpetas de playlists** (solo la primera vez): explica que la Web API no da las carpetas,
   ofrece el modo experimental con sus riesgos y tiene "Seguir sin carpetas" (principal) y
   "Activar carpetas (experimental)" (contorno). Se puede cambiar en Ajustes → Reproductor.
5. **¡Listo!**: el anillo y el tilde se dibujan, el texto sube y a los 1,8 s entra el
   reproductor con un fundido mientras la pantalla rota a horizontal.

Toda la configuración queda **fija en vertical**: girar el teléfono no la rota.

## Adaptación al iPhone 8 Plus (736×414)

- Calcular la carátula con `GeometryReader`: `min(alto disponible del bloque superior, ancho × 0,3)`.
- Achicar los grupos laterales de controles de 200 a ~160.
- La hoja de Importar tema baja a ~680 de ancho, y la columna derecha a 240.
- En Biblioteca, la fila de tarjetas ya se desliza: no hace falta cambiarla.
- En el detalle de playlist o álbum, la columna izquierda no cambia y la lista de temas se
  angosta (unos 440 de ancho).
