# Nowdeck — instrucciones del proyecto para agentes de código

Nowdeck es una app iOS **open source** que convierte un iPhone apoyado en el escritorio en un
control de reproducción para Spotify: muestra lo que suena, controla la reproducción y el
volumen, pasa la música entre dispositivos de Spotify Connect, navega la biblioteca y muestra
letras sincronizadas. **No reproduce audio**: solo controla otros dispositivos mediante la
Spotify Web API.

Leé este archivo completo antes de cada tarea. El detalle está en `docs/`:

| Documento | Para qué |
|---|---|
| `docs/01-producto.md` | Alcance, pantallas, flujos y lo que queda fuera |
| `docs/02-diseno.md` | Tokens, medidas y comportamiento de cada pantalla |
| `docs/03-spotify-api.md` | Autenticación PKCE, permisos, endpoints, polling y errores |
| `docs/04-letras.md` | Integración con LRCLIB (línea y palabra por palabra) |
| `docs/05-temas.md` | Formato JSON de temas, validación, exportar e importar |
| `docs/06-cumplimiento.md` | Reglas de Spotify que la UI tiene que respetar |
| `docs/07-plan.md` | Hitos en orden, con criterios de aceptación |
| `design/` | Fuentes HTML de los mockups (referencia de valores exactos) |
| `schemas/`, `themes/` | Esquema JSON del tema y temas de ejemplo |

`docs/en/` tiene la traducción al inglés de estos documentos (y `design/README.en.md`,
`NowdeckTests/Fixtures/README.en.md`). **La versión en español es la fuente**: si cambiás un
documento, actualizá también su traducción en el mismo commit.

## Plataforma y stack

- **iOS 16.0 como mínimo** (tiene que correr en iPhone 8 Plus, que no pasa de iOS 16). Esto
  descarta el framework Observation (`@Observable`, iOS 17): usar `ObservableObject` /
  `@Published` / `@StateObject`.
- **SwiftUI** para toda la UI. UIKit solo donde SwiftUI no alcance (orientación por pantalla,
  `isIdleTimerDisabled`).
- Swift Concurrency (`async/await`, actores) para red y estado compartido.
- Dispositivos de referencia: **iPhone 11 Pro Max** (896×414 pt en horizontal) e
  **iPhone 8 Plus** (736×414 pt). El diseño está hecho para 896×414: tiene que adaptarse a
  736×414 sin recortar contenido.
- Proyecto generado con **XcodeGen** (`project.yml` versionado, `.xcodeproj` en `.gitignore`).
  Si `xcodegen` no está instalado, avisá y proponé `brew install xcodegen` en lugar de
  instalarlo por tu cuenta.
- Dependencias: **mínimas**. Única dependencia prevista: `Yams` (YAML, licencia MIT) para leer el
  `lyricsfile` de LRCLIB. Cualquier otra se consulta antes de agregarla.
- Sin backend propio. Sin analytics. Sin SDKs de terceros.

## Reglas de trabajo

1. **Seguí el plan de `docs/07-plan.md` hito por hito.** Al empezar un hito, resumí qué vas a
   hacer en pocas líneas; al terminarlo, decí cómo se verificó (tests, build, simulador) y qué
   quedó pendiente.
2. **La Spotify Web API cambió mucho en 2024–2026.** Antes de implementar un endpoint, verificá
   en la documentación oficial (developer.spotify.com) que siga disponible para apps en
   *Development Mode*. Los puntos marcados **[VERIFICAR]** en `docs/03-spotify-api.md` no están
   confirmados: confirmalos o avisá. No inventes endpoints, campos ni scopes.
3. **El diseño manda.** Los valores (colores, tamaños, espaciados, radios) salen de
   `docs/02-diseno.md` y de `design/mockups/*.dc.html`. Si algo no se puede hacer igual en
   SwiftUI, explicá la diferencia en vez de improvisar otra estética.
4. **Cumplimiento de Spotify primero** (`docs/06-cumplimiento.md`): atribución con el logo,
   carátula sin recortar ni tapar, enlace de vuelta a Spotify, nombre sin "Spotify". Si un
   pedido choca con esas reglas, decilo antes de implementarlo.
5. **Seguridad por defecto**:
   - Tokens y Client ID en el **Llavero** (Keychain), nunca en `UserDefaults` ni en logs.
   - Nada de Client Secret: el flujo es Authorization Code **con PKCE**.
   - Validar `state` en el callback de OAuth.
   - Los temas importados son **solo datos**: nunca se ejecutan ni cargan URLs.
   - No desactivar ATS ni la validación TLS.
6. **Tests**: lógica pura con tests unitarios (XCTest). Red con `URLProtocol` de prueba, sin
   pegarle a Spotify ni a LRCLIB en los tests.
7. **Git**: trabajá en una rama por hito (`hito/NN-nombre`), con commits chicos y mensajes
   descriptivos en inglés. **No hagas push ni abras PRs sin que te lo pida.**
8. **Idioma**: la UI está en español rioplatense (voseo, idioma fuente) y en inglés, en un
   *String Catalog* (`Localizable.xcstrings`; los nombres de tipo de archivo del Info.plist,
   en `InfoPlist.xcstrings`). Todo texto nuevo de la UI entra al catálogo **con su traducción
   al inglés** (estado `translated`). La app sigue el idioma del iPhone; cualquier otro idioma
   cae en inglés. Identificadores de código y comentarios en inglés.
9. El dueño del proyecto revisa el código generado: preferí código claro y explícito por sobre
   abstracciones ingeniosas. Explicá brevemente el porqué de las decisiones no obvias.

## Comandos útiles

```bash
xcodegen generate                         # regenera Nowdeck.xcodeproj desde project.yml
xcrun simctl list devices available       # simuladores disponibles
xcodebuild -scheme Nowdeck -destination 'platform=iOS Simulator,name=<simulador>' build
xcodebuild -scheme Nowdeck -destination 'platform=iOS Simulator,name=<simulador>' test
```

Para probar en horizontal usá un simulador de tamaño parecido al 11 Pro Max o al 8 Plus. Los
modelos exactos pueden no estar en los runtimes instalados: elegí el más cercano y decí cuál
usaste.

## Estructura de carpetas esperada

```
Nowdeck/
  App/            NowdeckApp.swift, AppState, orientación, idle timer
  Features/
    Onboarding/   Bienvenida, Crear la app, Client ID
    Player/       Reproductor, modo letras, panel de volumen, aviso
    Library/      Biblioteca (pestañas, filtros, filas), Buscar, mini reproductor
    Devices/      Hoja de dispositivos y ayuda
    Settings/     Ajustes (Apariencia, Reproductor), importar/exportar tema
    EmptyState/   Nada sonando
  Services/
    Auth/         PKCE, ASWebAuthenticationSession, refresh de tokens
    Spotify/      Cliente HTTP, modelos Codable, polling
    Lyrics/       Cliente LRCLIB, parser LRC, parser Lyricsfile
    Theme/        Modelo Codable del tema, validación, contraste
    Artwork/      Extracción del color de fondo desde la carátula
    Keychain/
  DesignSystem/   Colores, tipografía, espaciados, componentes reutilizables
  Resources/      Assets (incluido el logo oficial de Spotify), Localizable.xcstrings,
                  InfoPlist.xcstrings
NowdeckTests/
project.yml
```
