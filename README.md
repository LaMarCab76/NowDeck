# Nowdeck

Un control de escritorio para Spotify que corre en tu iPhone. Lo dejás apoyado en horizontal,
enchufado y con la pantalla prendida, y de un vistazo ves qué suena, lo controlás y elegís en qué
dispositivo suena.

Nowdeck **no reproduce audio**: controla tus dispositivos de Spotify Connect (computadora,
parlantes, teles, otros teléfonos) mediante la Spotify Web API.

> Nowdeck es un proyecto open source independiente. No está afiliado a Spotify ni cuenta con su
> aval.

**Estado:** en desarrollo, todavía no es usable. El plan está en
[`docs/07-plan.md`](docs/07-plan.md).

## Requisitos

- iPhone con iOS 16 o posterior (el más viejo que tiene que soportar es el iPhone 8 Plus).
- Una cuenta de **Spotify Premium**.
- Una **app de desarrollador propia** en [developer.spotify.com](https://developer.spotify.com/dashboard):
  Nowdeck te guía para crearla la primera vez y te pide su Client ID.

## Compilar

Hace falta Xcode y [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig   # poné tu DEVELOPMENT_TEAM
xcodegen generate
open Nowdeck.xcodeproj
```

El proyecto de Xcode se genera desde `project.yml` y no se versiona.

## Documentación

| Documento | Contenido |
|---|---|
| [`docs/01-producto.md`](docs/01-producto.md) | Alcance, pantallas y flujos |
| [`docs/02-diseno.md`](docs/02-diseno.md) | Tokens y medidas |
| [`docs/03-spotify-api.md`](docs/03-spotify-api.md) | Autenticación, endpoints y errores |
| [`docs/04-letras.md`](docs/04-letras.md) | Letras con LRCLIB |
| [`docs/05-temas.md`](docs/05-temas.md) | Formato de temas |
| [`docs/06-cumplimiento.md`](docs/06-cumplimiento.md) | Reglas de Spotify |
| [`docs/07-plan.md`](docs/07-plan.md) | Plan de hitos |

## Licencia

Pendiente de definir.
