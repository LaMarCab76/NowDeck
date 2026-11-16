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
- [ ] **Controles**: deshabilitar u ocultar lo que `actions.disallows` prohíba.
- [ ] **Progreso**: informativo, sin ningún indicio de que se pueda adelantar.
- [ ] **Podcasts**: mostrar el título del episodio y el nombre del podcast. Las guidelines piden
  saltos de ±15 s para episodios **[VERIFICAR si aplica a esta app]**.
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

## App Store (si algún día se publica)

- Apple puede pedir pruebas de que podés mostrar las carátulas. En las capturas de la tienda,
  usar carátulas genéricas propias.
- **Política de privacidad**: Nowdeck no recolecta datos. Los tokens quedan en el dispositivo y
  solo se habla con Spotify y con LRCLIB.
