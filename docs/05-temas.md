# 05 · Temas (JSON)

Un tema define los colores de la app y algunas opciones del reproductor. Se exporta y se importa
como archivo **`.nowdeck.json`**. Esquema: `schemas/nowdeck.tema.v1.schema.json`. Ejemplos en
`themes/`.

## Formato v1

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

| Campo | Valores | Por defecto |
|---|---|---|
| `formato` | `"nowdeck.tema/1"` (obligatorio) | — |
| `nombre` | texto de 1 a 40 caracteres (obligatorio) | — |
| `colores.*` | `#RRGGBB` | los del tema "Negro y verde" |
| `fondoReproductor` | `solido` (usa `colores.fondo`) · `caratula` | `caratula` |
| `reproductor.caratula` | `izquierda` · `derecha` | `izquierda` |
| `reproductor.controles` | subconjunto ordenado de `aleatorio`, `repetir`, `letras`, `volumen` | los cuatro |
| `letras.ancho` | `mitad` · `dos-tercios` · `completo` | `dos-tercios` |

Correspondencia con Ajustes → Apariencia → Fondo del reproductor:

| Opción en Ajustes | En el JSON |
|---|---|
| Negro | `fondoReproductor: "solido"` con `fondo: #000000` |
| Gris oscuro | `fondoReproductor: "solido"` con `fondo: #121212` |
| Según la carátula | `fondoReproductor: "caratula"` |

`reproductor.caratula: "derecha"` está en el formato, pero **no tiene diseño todavía**. Por
ahora, ignorarlo con una advertencia en la importación.

## Modelo en Swift

- `struct Tema: Codable, Equatable` con todos los campos opcionales salvo `formato` y `nombre`.
  Al aplicar, se mezcla con el tema por defecto.
- Las **claves desconocidas se ignoran** (compatibilidad hacia adelante) y se informan como
  advertencia.
- El tema activo se guarda como JSON en `Application Support/` y se publica con un
  `ObservableObject` (`ThemeStore`) inyectado en el entorno.

## Validación al importar

1. **Tamaño** máximo de 16 KB: si se pasa, se rechaza.
2. **JSON** válido y `formato` igual a `nowdeck.tema/1`.
   - Si el formato es de una versión mayor: "Este tema es de una versión más nueva de
     Nowdeck".
   - Si falta o es otro: "No es un tema de Nowdeck".
3. **Colores**: cada uno tiene que cumplir `^#[0-9A-Fa-f]{6}$`. Un color inválido es un error.
4. **Contraste** (WCAG 2.x), que genera advertencias y no errores:
   - `texto` sobre `fondo` y sobre `superficie`: 4,5:1 o más.
   - `textoSecundario` sobre `fondo`: 4,5:1 o más.
   - `textoSobreAcento` sobre `acento`: 4,5:1 o más.
   - `acento` sobre `fondo`: 3:1 o más.

   Si alguno no cumple, mostrar la advertencia con el valor (por ejemplo "4,3:1"). **Al
   aplicar**, aclarar u oscurecer ese color en pasos chicos hasta cumplir, y avisar.
5. **Vista previa** con los colores del tema y los botones Aplicar y Cancelar.

## Exportar

- Con `ShareLink`, exportar el tema activo como `<nombre-en-slug>.nowdeck.json`, en UTF-8, con
  formato legible y claves ordenadas.

## Importar

- **Tipo de archivo**: declarar un `UTType` exportado `com.<tu-usuario>.nowdeck.theme`, que
  conforme a `public.json`, con la extensión `nowdeck.json`. Así Archivos y AirDrop ofrecen
  abrir con Nowdeck.
- **Entradas posibles**:
  - abrir el archivo desde fuera de la app (`onOpenURL`);
  - `.fileImporter` desde Ajustes;
  - pegar el texto JSON desde el portapapeles.

## Seguridad

Un tema es **solo datos**: no se interpreta como código, no carga URLs ni imágenes y no puede
cambiar nada fuera de los colores y las opciones listadas. Leer el archivo con
`startAccessingSecurityScopedResource` y cerrar el acceso siempre.
