# Nowdeck

**Un control de escritorio para Spotify que corre en tu iPhone.**

Lo dejás apoyado en horizontal, enchufado y con la pantalla prendida, y de un vistazo ves qué
suena, lo controlás y elegís en qué dispositivo suena.

> Nowdeck es un proyecto open source independiente. No está afiliado a Spotify ni cuenta con su
> aval.

## Qué hace

- Muestra lo que suena: carátula, tema, artista, de qué playlist o álbum viene y en qué
  dispositivo, con el fondo tomado del color de la carátula.
- Controla la reproducción: play y pausa, anterior y siguiente (o −15 s y +15 s en los
  podcasts), aleatorio, repetir y volumen.
- Pasa la música de un dispositivo a otro (computadora, parlantes, teles, otros teléfonos).
- Recorre tu biblioteca (playlists, álbumes, podcasts y audiolibros) y reproduce desde ahí.
- Muestra letras sincronizadas, por palabra o por estrofa, tomadas de
  [LRCLIB](https://lrclib.net).
- Se puede personalizar con temas que se exportan e importan como archivos `.nowdeck.json`.

Nowdeck **no reproduce audio**: controla tus dispositivos de Spotify Connect mediante la
Spotify Web API. La música suena en otro lado: en la compu, el parlante o el teléfono donde
tengas Spotify abierto.

## Requisitos

- iPhone con **iOS 16 o posterior**. El más viejo en el que tiene que andar es el iPhone 8 Plus.
- Una cuenta de **Spotify Premium**: la Web API solo acepta comandos de reproducción de
  cuentas Premium, y la cuenta que crea la app de desarrollador también tiene que serlo.
- Una **app de desarrollador propia** en el panel de Spotify (se explica abajo). La app queda en
  *Development Mode*, que admite **hasta 5 usuarios** cargados a mano. Lo normal es que cada
  persona cree la suya y se cargue como único usuario.
- Para compilar: una Mac con **Xcode 27.2** (la versión con la que se compiló y se probó en el
  simulador; versiones anteriores que compilen para iOS 16 deberían andar) y
  [XcodeGen](https://github.com/yonaskolb/XcodeGen).

## Crear tu app en Spotify

Nowdeck te guía la primera vez que lo abrís, pero estos son los pasos:

1. Entrá a [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard) con tu
   cuenta Premium y aceptá los términos de desarrollador si te los pide.
2. Tocá **Create app**. En nombre y descripción poné lo que quieras (sin usar "Spotify" en el
   nombre).
3. En **Redirect URIs** pegá, tal cual:

   ```
   nowdeck://callback
   ```

4. Donde pregunta qué API vas a usar, marcá **Web API** y guardá.
5. Abrí **Settings** y copiá el **Client ID**. El *Client secret* no hace falta: Nowdeck usa
   Authorization Code con PKCE, que no lo necesita.
6. Si otra persona va a usar tu app, agregala en **User Management** con el mail de su cuenta
   de Spotify (hasta 5). Si sos solo vos, no hace falta.

En Nowdeck pegá el Client ID, tocá **Conectar con Spotify** e iniciá sesión. Nowdeck pide
solo estos permisos:

| Permiso | Para qué |
|---|---|
| `user-read-playback-state` | Ver qué suena y en qué dispositivos |
| `user-modify-playback-state` | Play, pausa, saltar, volumen, aleatorio, repetir y cambiar de dispositivo |
| `user-read-currently-playing` | Ver el tema actual |
| `playlist-read-private` | Listar tus playlists privadas |
| `playlist-read-collaborative` | Listar tus playlists colaborativas |
| `user-library-read` | Listar tus álbumes, podcasts y audiolibros guardados |
| `user-read-playback-position` | Saber por dónde vas en un episodio de podcast |

Si después de conectar aparece "Spotify no deja usar tu app", revisá que tu cuenta esté en
**User Management** y que la cuenta dueña de la app tenga Premium.

## Compilar

```bash
brew install xcodegen                                   # si no lo tenés
cp Config/Local.xcconfig.example Config/Local.xcconfig  # y completalo (ver abajo)
xcodegen generate                                       # genera Nowdeck.xcodeproj
open Nowdeck.xcodeproj
```

El proyecto de Xcode se genera desde `project.yml` y no se versiona.

`Config/Local.xcconfig` no se sube al repositorio. Ahí van tus datos de firma:

```
DEVELOPMENT_TEAM = ABCDE12345            // tu Team ID de Apple
NOWDECK_BUNDLE_ID = com.tunombre.nowdeck // opcional: tu propio Bundle ID
```

Para correr en tu iPhone necesitás un Team ID (alcanza con una cuenta gratuita de Apple
Developer) y, si la cuenta es gratuita, un Bundle ID propio. Para el simulador alcanza con
`xcodegen generate` y elegir un iPhone.

Tests (no se conectan ni a Spotify ni a LRCLIB: todo pasa por respuestas de prueba):

```bash
xcodebuild -scheme Nowdeck -destination 'platform=iOS Simulator,name=<simulador>' test
```

## Zonas grises y límites

Cosas que Nowdeck no puede hacer, o que conviene saber, por cómo funciona la Spotify Web API
en 2026 y por las reglas de Spotify:

- **Cada usuario usa su propio Client ID.** Desde 2026 una app en *Development Mode* admite
  hasta 5 usuarios, y el modo ampliado (*Extended Quota Mode*) solo se otorga a empresas con
  250.000 usuarios activos por mes. Spotify no prohíbe ni avala por escrito que cada usuario
  cree su app; es la única forma práctica de distribuir una app abierta.
- **Cuota limitada.** Cada app de desarrollador tiene una cuota de pedidos. Si se pasa, Spotify
  responde "esperá" y Nowdeck consulta con menos frecuencia durante un rato (aparece "SPOTIFY
  PIDE ESPERAR").
- **Sin avisos instantáneos.** La API no avisa los cambios: Nowdeck consulta el estado cada 3 s
  mientras suena (10 s en pausa), así que un cambio hecho en otro dispositivo puede tardar unos
  segundos en verse.
- **Premium vencido.** Si se vence el Premium de la cuenta dueña de la app, la app deja de
  funcionar para todos sus usuarios.
- **Volver a conectar cada 6 meses.** El acceso que da Spotify dura 6 meses desde que
  conectás; después Nowdeck te pide conectar de nuevo.
- **Lo que la API no ofrece**: cola de reproducción, playlists editoriales y algorítmicas de
  Spotify (se muestra solo "Desde una playlist"), y reproducir podcasts o audiolibros desde la
  biblioteca (esas tarjetas abren Spotify). La búsqueda en *Development Mode* devuelve como
  mucho 10 resultados por tipo; la pantalla de resultados todavía no está hecha.
- **Dispositivos que no aparecen.** La lista de Spotify Connect muestra en la práctica solo los
  dispositivos con Spotify abierto o despierto. Algunos modelos no admiten control remoto y se
  ven atenuados.
- **Letras de una base comunitaria.** Spotify no ofrece letras en su API. Nowdeck las toma de
  [LRCLIB](https://lrclib.net), una base abierta que cargan sus usuarios: pueden faltar o tener
  errores, y los derechos de las letras son de sus autores y editoriales. Además, la política
  de Spotify prohíbe integrar contenido de otro servicio con el suyo, y mostrar letras de un
  tercero junto a la reproducción no tiene un precedente claro. Por eso las letras se pueden
  apagar en **Ajustes → Reproductor → Mostrar letras**, y la pantalla de Ajustes explica de
  dónde salen. Nowdeck nunca usa el acceso interno de Spotify a sus letras.
- **No es un reproductor.** No hace sonar nada en el iPhone; para eso está la app de Spotify.

## Privacidad

- **Sin servidor propio y sin analytics.** Nowdeck solo habla con Spotify (para controlar la
  reproducción) y con LRCLIB (para las letras, y solo si están activadas). A LRCLIB le manda
  el título, el artista, el álbum y la duración del tema.
- **Tus credenciales quedan en el iPhone**, en el Llavero: el Client ID y los tokens de acceso.
  No hay Client Secret. Nada de eso se guarda en otro lado ni se manda a otro servicio.
- Los temas importados son solo datos: colores y opciones. Nunca se ejecutan ni cargan nada de
  internet.

## Documentación

| Documento | Contenido |
|---|---|
| [`docs/01-producto.md`](docs/01-producto.md) | Alcance, pantallas y flujos |
| [`docs/02-diseno.md`](docs/02-diseno.md) | Tokens y medidas |
| [`docs/03-spotify-api.md`](docs/03-spotify-api.md) | Autenticación, endpoints y errores |
| [`docs/04-letras.md`](docs/04-letras.md) | Letras con LRCLIB |
| [`docs/05-temas.md`](docs/05-temas.md) | Formato de temas |
| [`docs/06-cumplimiento.md`](docs/06-cumplimiento.md) | Reglas de Spotify y revisión |
| [`docs/07-plan.md`](docs/07-plan.md) | Plan de hitos |

## Créditos

- [LRCLIB](https://lrclib.net): base de datos abierta y comunitaria de letras sincronizadas, de
  donde salen todas las letras que muestra Nowdeck. Gracias a su autor y a quienes cargan
  letras.
- [Yams](https://github.com/jpsim/Yams) (licencia MIT): lectura del formato Lyricsfile (YAML)
  de LRCLIB. Es la única dependencia del proyecto.
- Spotify y su logo son marcas de Spotify AB. Nowdeck usa la Spotify Web API y no está
  afiliado a Spotify.

## Contribuir

El código está en `https://github.com/<usuario>/Nowdeck`. Los issues y pull requests son
bienvenidos.

## Licencia

Pendiente: la elige el dueño del proyecto y va a quedar en el archivo `LICENSE`.
