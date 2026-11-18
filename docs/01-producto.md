# 01 · Producto

## Qué es

Nowdeck es un control de escritorio para Spotify que corre en un iPhone, pensado para dejarlo
apoyado en horizontal, enchufado y con la pantalla siempre encendida. Se ve de un vistazo qué
suena, y permite controlarlo y elegir en qué dispositivo suena. **No reproduce audio**: todo pasa
por la Spotify Web API sobre los dispositivos de Spotify Connect de la cuenta del usuario
(computadora, parlantes, teles, otros teléfonos).

- **Requisitos del usuario**: Spotify **Premium** (los comandos de reproducción de la API lo
  exigen) y una **app de desarrollador propia** en el panel de Spotify.
- **Modelo de distribución**: open source. Cada usuario crea su app en
  developer.spotify.com, copia el **Client ID** y lo pega en Nowdeck la primera vez.
  - Motivo: desde 2026, una app en *Development Mode* admite hasta 5 usuarios, y el
    *Extended Quota Mode* solo se otorga a empresas con 250.000 usuarios activos mensuales.
  - Con un Client ID por usuario, cada uno tiene su propia cuota.
- **Nombre**: "Nowdeck". En la App Store o en el README puede llevar "para Spotify" como
  bajada, nunca "Spotify" en el nombre.

## Orientación

| Pantalla | Orientación |
|---|---|
| Primer inicio (3 pasos) | Vertical, 414×896 de referencia |
| Todo lo demás | Horizontal, 896×414 de referencia (adaptar a 736×414) |

Bloquear la orientación por pantalla: `supportedInterfaceOrientations` desde el AppDelegate más
`UIWindowScene.requestGeometryUpdate(.iOS(interfaceOrientations:))`, disponible desde iOS 16.

Mientras la app está en primer plano, **la pantalla no se apaga**
(`UIApplication.shared.isIdleTimerDisabled = true`).

## Pantallas

1. **Primer inicio**
   1. **Bienvenida**: qué es, qué hace falta y el aviso de que no está afiliada a Spotify.
   2. **Crear la app**: los 5 pasos del panel de Spotify y el Redirect URI `nowdeck://callback`
      con botón Copiar.
   3. **Client ID**: campo para pegarlo, los permisos que se van a pedir y "Conectar con Spotify".
2. **Reproducción**: la pantalla principal.
   - Arriba: carátula a la izquierda y, a la derecha, logo de Spotify + "Reproduciendo desde / X",
     Biblioteca, Ajustes, título, artista y "Reproduciendo en <dispositivo>".
   - Abajo, a todo el ancho: barra de progreso (informativa, sin arrastre) y controles.
   - Fondo: un color suave tomado de la carátula.
3. **Modo letras**, dentro de Reproducción, activado con el botón de letras.
   - Fila superior: "Reproduciendo desde / Nombre" en dos líneas a la izquierda y el logo a la
     derecha.
   - Centro: estrofa actual y estrofa siguiente, al ancho configurado (por defecto 2/3).
   - Fila inferior: carátula chica, título, artista y dispositivo.
   - Biblioteca y Ajustes se ocultan mientras está activo.
4. **Barra de volumen**: se abre hacia el costado desde el botón de volumen, dentro de la fila
   de controles, que se corre para dejarle lugar. Se abre al tocar el botón o cuando cambia el
   volumen (también si cambia desde otro dispositivo). Se cierra a los 3 s.
5. **Aviso "No encontramos la letra de este tema"**: aparece arriba 3 s y el reproductor vuelve
   a la vista normal.
6. **Biblioteca**
   - Pestañas Biblioteca y Buscar.
   - Filtros Playlists, Álbumes, Podcasts y Audiolibros.
   - Fila horizontal de tarjetas. Tocar una playlist o un álbum abre su **detalle**; los
     podcasts y audiolibros se abren en Spotify.
   - **Detalle de playlist o álbum**: carátula, nombre, dueño o artistas, el botón
     **Reproducir** (arranca desde el principio) y la lista de temas. Los temas no se tocan
     para reproducir. En las playlists de otras personas Spotify no devuelve los temas: se
     avisa y se puede reproducir igual o verla en Spotify.
   - Mini reproductor abajo, con fondo del color de la carátula y "Suena en <dispositivo>".
7. **Buscar**: campo de búsqueda; al tocar un resultado, suena en el dispositivo activo. La
   pantalla de resultados todavía no está diseñada (ver pendientes).
8. **Dispositivos**
   - Hoja inferior con el dispositivo actual destacado y la lista del resto.
   - Botón "¿No ves tu dispositivo?", que abre una ayuda de 3 pasos y "Actualizar lista".
9. **Cola** (agregada el 2026-11-17, a pedido del dueño)
   - Píldora Cola en la fila superior del reproductor, a la izquierda de Biblioteca.
   - Hoja inferior con lo que suena ahora y hasta 20 temas de "A continuación".
   - **Solo lectura**: la Web API no deja quitar, reordenar ni saltar a un tema de la cola. Los
     temas no se tocan; mantenerlos apretados muestra el nombre completo y "Abrir en Spotify".
     La lista termina con "Para quitar o reordenar temas, usá Spotify." y "ABRIR SPOTIFY".
10. **Agregar a una playlist** (agregada el 2026-11-18, a pedido del dueño)
   - Botón en el extremo izquierdo de los controles del reproductor y del mini reproductor de
     la Biblioteca.
   - Hoja con las playlists que el usuario puede editar (propias y colaborativas); tocar una
     agrega el tema o episodio que suena. Lo agregado queda marcado. Quitar se hace en Spotify.
   - Buscador por nombre arriba de la lista, y primero las playlists que ya tienen el tema
     ("YA ESTÁ EN", con el check), después el resto (agregado el 2026-11-18).
   - Pide un permiso nuevo (editar playlists): las sesiones anteriores lo dan desde la misma
     hoja con "Dar permiso".
11. **Ajustes**
   - **Apariencia**:
     - tema (Negro y verde, Ámbar, Azul noche, Personalizado);
     - color de resaltado (6 opciones);
     - fondo del reproductor (Negro, Gris oscuro o Según la carátula; por defecto, Según la
       carátula);
     - Exportar e Importar tema.
   - **Reproductor**: interruptor "Mostrar tiempo restante" (en vez de la duración, a la
     derecha de la barra; apagado por defecto), interruptor "Mostrar letras", "Ancho de las
     letras" (Mitad, 2/3 o Completo; por defecto 2/3) y "Estilo de las letras" (Por palabra o
     Estrofa; por defecto Por palabra).
12. **Importar tema**: hoja con el JSON, el resultado de la validación, advertencias, vista
    previa y los botones Aplicar y Cancelar.
13. **Nada sonando**: estado vacío con "Elegir dispositivo" y "ABRIR SPOTIFY".

## Flujos clave

- **Primer arranque**: Bienvenida → Crear la app → Client ID → login de Spotify
  (`ASWebAuthenticationSession`) → Reproducción, o Nada sonando si no hay reproducción activa.
- **Token vencido o revocado** (`invalid_grant` al refrescar): volver a la pantalla de Client ID
  con el ID precargado y un mensaje claro.
- **Cambiar de dispositivo**: tocar "Reproduciendo en …" → hoja de Dispositivos → tocar un
  dispositivo → transferir la reproducción → cerrar la hoja.
- **Letras**: tocar el botón de letras.
  - Si hay letra con sincronía por palabra y el estilo es "Por palabra", se usa ese modo.
  - Con el estilo "Estrofa", se muestra la estrofa completa aunque haya sincronía por palabra.
  - Si hay sincronía por línea, se muestra la estrofa completa.
  - Si no hay letra o es solo texto plano, aparece el aviso y el reproductor vuelve a la vista
    normal.
- **Reproducir desde la Biblioteca**: tocar una playlist o un álbum → detalle con sus temas →
  Reproducir → suena en el dispositivo activo y se vuelve a Reproducción. Si no hay
  dispositivo activo, se abre Dispositivos. Mantener apretada una tarjeta sigue ofreciendo
  "Reproducir" sin pasar por el detalle.
- **Tema**: en Ajustes → Exportar, se abre la hoja de compartir con un `.nowdeck.json`.
  Importar se puede hacer desde Archivos, AirDrop o pegando el texto → hoja de importación →
  Aplicar.

## Fuera de alcance (por ahora)

- Reproducir audio en el iPhone (receptor de Spotify Connect, librespot).
- Control por voz: la política de Spotify lo prohíbe.
- Editar la cola (quitar, reordenar o saltar a un tema): la Web API no lo permite. Agregar a
  la cola (`POST /me/player/queue`) sí existe, pero todavía no tiene diseño.
- Accesos rápidos (presets).
- Pantalla de resultados de búsqueda, pendiente de diseño.
- Protección contra *burn-in* de OLED (atenuar brillo, desplazar píxeles): se habló como opción
  futura, sin decidir.
- Variante "Pastel claro" del fondo, que requeriría invertir los colores del texto.

## Decisiones pendientes del dueño

- ✅ Licencia del repositorio: MIT (decidido el 2026-11-18, archivo `LICENSE`).
- Usuario u organización de GitHub y Bundle ID definitivo (sugerido
  `com.lamarcab76.nowdeck`).
- Si los temas se editan color por color dentro de la app o alcanza con presets e importación.
