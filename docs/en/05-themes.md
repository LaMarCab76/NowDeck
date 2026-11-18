# 05 · Themes (JSON)

> English translation of [`docs/05-temas.md`](../05-temas.md). The Spanish version is the source of truth; if they differ, it wins.

A theme defines the app's colors and some player options. It's exported and imported
as a **`.nowdeck.json`** file. Schema: `schemas/nowdeck.tema.v1.schema.json`. Examples in
`themes/`.

## Format v1

```json
{
  "formato": "nowdeck.tema/1",
  "nombre": "Negro y verde",
  "colores": {
    "fondo": "#000000",
    "superficie": "#161616",
    "texto": "#F2EEE8",
    "textoSecundario": "#A9B4C0",
    "acento": "#2FD566",
    "textoSobreAcento": "#00170A"
  },
  "fondoReproductor": "caratula",
  "reproductor": {
    "caratula": "izquierda",
    "controles": ["aleatorio", "repetir", "letras", "volumen"]
  },
  "letras": {
    "ancho": "dos-tercios"
  }
}
```

| Field | Values | Default |
|---|---|---|
| `formato` | `"nowdeck.tema/1"` (required) | — |
| `nombre` | text of 1 to 40 characters (required) | — |
| `colores.*` | `#RRGGBB` | those of the "Black and green" (*Negro y verde*) theme |
| `fondoReproductor` | `solido` (uses `colores.fondo`) · `caratula` · `artista` (full-screen artist photo; while it loads, or if the artist has no photo, the artwork color) | `caratula` |
| `desenfoqueFondo` | integer from 0 (sharp) to 100; only used with `artista` | `40` |
| `oscurecerFondo` | integer from 0 (the photo as is) to 100; only used with `artista` | `60` |
| `reproductor.caratula` | `izquierda` · `derecha` | `izquierda` |
| `reproductor.controles` | ordered subset of `aleatorio`, `repetir`, `letras`, `volumen` | all four |
| `letras.ancho` | `mitad` · `dos-tercios` · `completo` | `dos-tercios` |

Mapping to Settings → Appearance → Player background (*Fondo del reproductor*):

| Option in Settings | In the JSON |
|---|---|
| Black (*Negro*) | `fondoReproductor: "solido"` with `fondo: #000000` |
| Dark gray (*Gris oscuro*) | `fondoReproductor: "solido"` with `fondo: #121212` |
| From the artwork (*Según la carátula*) | `fondoReproductor: "caratula"` |
| Artist photo (*Foto del artista*) | `fondoReproductor: "artista"`; its "Blur" (*Desenfoque*) and "Dim" (*Oscurecer*) sliders are `desenfoqueFondo` and `oscurecerFondo` |

On the iPhone 8 Plus the four options don't fit with their full names: there they're shown as
"Black" (*Negro*), "Gray" (*Gris*), "Artwork" (*Carátula*), and "Artist" (*Artista*).

`reproductor.caratula: "derecha"` is in the format, but **has no design yet**. For
now, ignore it with a warning on import.

## Swift model

- `struct Tema: Codable, Equatable` with all fields optional except `formato` and `nombre`.
  When applied, it's merged with the default theme.
- **Unknown keys are ignored** (forward compatibility) and reported as a
  warning.
- The active theme is stored as JSON in `Application Support/` and published through an
  `ObservableObject` (`ThemeStore`) injected into the environment.

## Validation on import

1. Maximum **size** of 16 KB: if it's larger, it's rejected.
2. Valid **JSON** and `formato` equal to `nowdeck.tema/1`.
   - If the format is from a higher version: "This theme is from a newer version of
     Nowdeck" (*Este tema es de una versión más nueva de Nowdeck*).
   - If it's missing or different: "This isn't a Nowdeck theme" (*No es un tema de Nowdeck*).
3. **Colors**: each one has to match `^#[0-9A-Fa-f]{6}$`. An invalid color is an error.
4. **Contrast** (WCAG 2.x), which produces warnings, not errors:
   - `texto` on `fondo` and on `superficie`: 4.5:1 or more.
   - `textoSecundario` on `fondo`: 4.5:1 or more.
   - `textoSobreAcento` on `acento`: 4.5:1 or more.
   - `acento` on `fondo`: 3:1 or more.

   If any of them fails, show the warning with the value (for example "4.3:1"). **When
   applying**, lighten or darken that color in small steps until it passes, and tell the user.
5. **Preview** with the theme's colors and the Apply and Cancel buttons.

## Export

- With `ShareLink`, export the active theme as `<slugified-name>.nowdeck.json`, in UTF-8,
  pretty-printed and with sorted keys.

## Import

- **File type**: declare an exported `UTType` `com.<your-username>.nowdeck.theme`, which
  conforms to `public.json`, with the extension `nowdeck.json`. That way Files and AirDrop offer
  to open it with Nowdeck.
- **Possible inputs**:
  - opening the file from outside the app (`onOpenURL`);
  - `.fileImporter` from Settings;
  - pasting the JSON text from the clipboard.

## Security

A theme is **data only**: it isn't interpreted as code, it doesn't load URLs or images, and it can't
change anything beyond the colors and the options listed. Read the file with
`startAccessingSecurityScopedResource` and always close access.
