# AdaptiveSound — Brand Asset Kit

The **Flux / "Flag"** mark: an eighth note whose flag has become the adaptive
waveform. The note anchors it as *music*; the flowing wave says the sound
*adapts* — the core promise of the engine (continuous, content-aware
re-rendering steered by the Reimagine dial).

> **These SVGs are the source of truth.** PNGs in `png/` are generated from
> them. Re-export PNGs from the SVGs if you change anything.

---

## Files

### `svg/` — vector source (use these in code wherever possible)
| File | Use |
|---|---|
| `mark.svg` | Primary icon, full Sunset gradient, transparent bg |
| `mark-ink.svg` | Single-color mark, `#211510` — for light backgrounds, print, 1-color contexts |
| `mark-white.svg` | Single-color white mark — for dark backgrounds / photos |
| `lockup.svg` | Horizontal lockup: mark + `AdaptiveSound` wordmark (gradient mark, ink text) |
| `lockup-ink.svg` | Lockup, all ink |
| `lockup-white.svg` | Lockup, all white |
| `favicon.svg` | Square gradient mark, transparent — modern SVG favicon |
| `app-icon.svg` | 1024² rounded-tile app icon (mark on dark `#140C0A`) |

### `png/` — rasterized (generated from the SVGs)
| File | Use |
|---|---|
| `favicon-16/32/48.png` | Legacy favicons |
| `apple-touch-icon-180.png` | iOS home-screen icon |
| `app-icon-512/1024.png` | macOS / store app icon |
| `mark-512.png` | Gradient mark, transparent |
| `mark-white-512.png` | White mark, transparent |

> The **wordmark is live text** (font: Space Grotesk). Render it from the font in
> code rather than baking it into PNGs, so it stays crisp at any size. The lockup
> SVGs reference `'Space Grotesk'` — make sure the font is loaded where they render.

---

## Color

| Token | Hex | OKLCH | Role |
|---|---|---|---|
| `--as-pink` | `#F80791` | `oklch(0.64 0.26 356)` | Gradient start (note head) |
| `--as-orange` | `#FF6405` | `oklch(0.70 0.21 42)` | Gradient mid |
| `--as-gold` | `#FDC025` | `oklch(0.84 0.165 84)` | Gradient end (wave tip) |
| `--as-dark` | `#140C0A` | `oklch(0.165 0.014 40)` | Tile / dark surface |
| `--as-ink` | `#211510` | `oklch(0.21 0.022 45)` | Text / single-color mark |
| `--as-paper` | `#FEFBF8` | `oklch(0.99 0.006 70)` | Light surface |

### The Sunset gradient
A diagonal sweep, bottom-left → top-right (pink → orange → gold).

**CSS (surfaces / wordmark):**
```css
background: linear-gradient(40deg, #F80791 0%, #FF6405 50%, #FDC025 100%);
/* gradient text: set the above as background, then */
-webkit-background-clip: text; background-clip: text; color: transparent;
```

**SVG (matches the mark exactly — userSpaceOnUse over the 160×120 art):**
```xml
<linearGradient id="g" gradientUnits="userSpaceOnUse" x1="20" y1="95" x2="148" y2="18">
  <stop offset="0%"   stop-color="#F80791"/>
  <stop offset="50%"  stop-color="#FF6405"/>
  <stop offset="100%" stop-color="#FDC025"/>
</linearGradient>
```

---

## Typography

- **Wordmark + UI:** **Space Grotesk** (Google Fonts), weights 400 / 500 / 600 / 700.
- **Wordmark lockup:** `Adaptive` in **500**, `Sound` in **700**, set solid (no space
  between the two words), letter-spacing **-0.025em**.
- **Mono / labels (optional):** Space Mono, for technical captions and code-like UI.

```html
<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&family=Space+Mono:wght@400;700&display=swap" rel="stylesheet">
```

---

## Usage

- **Clearspace:** keep margin ≥ the height of the note head on all sides.
- **Minimum size:** mark ≥ 20px; lockup ≥ 120px wide.
- **Backgrounds:** gradient mark on dark `#140C0A` or paper `#FEFBF8`. On photos or
  busy color, use `mark-white.svg` / `mark-ink.svg`.
- **Don't:** recolor the gradient, stretch/skew, add shadows or outlines, rotate the
  mark, or separate the note from its wave.

### Wiring favicons / app icon (HTML)
```html
<link rel="icon" type="image/svg+xml" href="/brand/svg/favicon.svg">
<link rel="icon" type="image/png" sizes="32x32" href="/brand/png/favicon-32.png">
<link rel="apple-touch-icon" sizes="180x180" href="/brand/png/apple-touch-icon-180.png">
```

---

## Geometry (if you need to redraw the mark)

Art space `viewBox="0 0 160 120"`, strokes `stroke-width="11"`, round caps & joins.
```
note head : <ellipse cx="40" cy="86" rx="15" ry="10.5" transform="rotate(-22 40 86)"/>
stem      : M 52.5 84 L 54 30
wave flag : M 54 30 C 68 28 72 50 86 50 C 100 50 100 22 114 22 C 128 22 132 46 146 46
```
