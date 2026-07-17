# Handoff: Adaptive Sound — Now Playing, variant 7a "Liquid Glass" (RELEASE)

> **⚠ Repo-specific: read `INTEGRATION.md` first.** It maps this design onto the actual `ramith/sound-engineering` architecture (AppShell/ChromeBar/NowPlayingBar, DesignSystem tokens, existing SpectrumColorPalette) and gives the safe 6-PR plan. The Swift file here is a visual reference, NOT a drop-in — the repo already has a governed UI layer.

## What this is
Final released design of the **Now Playing** screen, to be implemented in the existing Swift/macOS codebase (Sources/AdaptiveSound) using **VS Code + Claude Code**.

**Layout is identical to variant 5a** (already specified in `design_handoff_5a/README.md`, reproduced as the base spec below via `NowPlayingView.swift` + `now-playing-base.html`). **7a changes only the material language** — it adopts macOS Liquid Glass. Implement the 5a layout, then apply the Liquid Glass layer described here.

Open `Player Layout Variants.dc.html` in a browser and find the card labeled **7a** (turn 7; see **8a** in turn 8 for the final production polish — 8a IS the release target: 7a + polish).

## Recommended Claude Code process
1. Drop this folder into the repo (e.g. `docs/design/now-playing-7a/`).
2. In VS Code, ask Claude Code: *"Implement the Now Playing screen per docs/design/now-playing-7a/README.md. Use NowPlayingView.swift as the starting point, apply the Liquid Glass material layer, and wire PlayerModel to our audio engine."*
3. Review in small steps: layout first (5a base), then materials (glass layer), then engine wiring (FFT spectrum, EBU R128 loudness, device/tab state).
4. Keep the HTML files open side-by-side as the visual source of truth.

## Base spec (layout, unchanged from 5a)
- `NowPlayingView.swift` — reference SwiftUI implementation: toolbar, hero (28px/800 title, badges, transport pill, scrubber), 400px analyzer, queue + fixed-width inspector as flow siblings, DS tokens incl. Teal→Lime spectrum mapping (`#1F9D8B #36C1AB #4FD2C0 #7FE3A8 #A8EC84 #C8F06A`, per-bar vertical darken 18%).
- `now-playing-base.html` — standalone browser-openable reference of the base layout.

## Liquid Glass adoption layer (what 7a/8a adds)

### 1. Ambient content glow (the light the glass refracts)
Window base `#0e1013`, radius 22. Three large blurred radial glows behind all content:
- top-left: teal `rgba(41,182,164,.28)`, ~720×560, blur 30
- bottom-right: lime `rgba(200,240,106,.12)`, ~760×600, blur 34
- mid-right: blue `rgba(79,178,214,.10)`, ~420×380, blur 28
In SwiftUI: `Circle().fill(RadialGradient(...)).blur(radius:)` in a background ZStack. In production, these can instead sample the (future) album-art color.

### 2. Glass recipe (apply to toolbar, transport pill, analyzer, inspector, filter pill, badges)
- Fill: dark translucent (`rgba(38,41,46,.5)` toolbar · `rgba(16,18,21,.42)` analyzer · `rgba(30,33,38,.5)` inspector · `rgba(255,255,255,.07-.09)` small controls)
- Backdrop: blur 20–28 **+ saturation boost 1.4–1.6** (`backdrop-filter: blur(26px) saturate(1.5)`). SwiftUI: `.background(.ultraThinMaterial)` approximates; for exact match use an `NSVisualEffectView` + saturation layer, or the OS glass-effect API where available.
- Specular top rim: `inset 0 1px 0 rgba(255,255,255,.14-.2)`
- Hairline: `inset 0 0 0 1px rgba(255,255,255,.04-.06)`
- Bottom light bleed: `inset 0 -12..-16px 24..32px -18..-24px rgba(255,255,255,.10-.14)`
- Drop shadow: `0 10..18px 30..44px -12..-14px rgba(0,0,0,.6-.65)`

### 3. Geometry
- **Floating toolbar**: detached capsule, margin 14/16, height 52, radius 26 (contains traffic lights, app mark, device pill, tab capsule).
- Concentric radii: window 22 → inspector 22 → analyzer 20 → toolbar capsule 26 → pills = height/2 → queue rows 12 → badges 10-11.
- Alignment grid: floating panels inset **16px** from window edges; text gutter **26px** left; inspector top aligns with queue header.

### 4. Component deltas vs base
- **Device pill**: add live sample rate readout ("44.1 kHz", 10.5px mono, 45% white) + hover state. Active tab: teal gradient `rgba(79,210,192,.95)→rgba(31,168,147,.95)` + inner top highlight + teal glow; inactive tabs get hover (bg white 7%, text 90%).
- **Scrubber/sliders**: 5px tracks with `inset 0 1px 2px rgba(0,0,0,.4)` (carved look); teal fill emits glow `0 0 8-10px rgba(63,208,186,.4-.5)`; 14px knobs with bottom inner shade.
- **Play button**: adds `inset 0 1.5px 0 rgba(255,255,255,.45)` top highlight + `inset 0 -6px 12px -8px rgba(0,0,0,.4)` bottom shade.
- **Analyzer**: dB gridlines (4 hairlines, white 4-6%), "0 dB" label top-right, **peak-hold caps** (2px, bar color at 50%, 4px above each bar), freq scale 20 Hz–20 kHz.
- **Hero title**: teal text-shadow halo `0 2px 16px rgba(41,182,164,.25)`.
- **ENHANCED badge**: pulsing 5px dot (1.6s opacity 1→.4), fixed 22px height; all badges capsule-height-consistent.
- **Dividers**: gradient-fade hairlines (`linear-gradient(90deg, transparent, rgba(255,255,255,.1-.12), transparent)`), not solid.
- **Disabled crossfeed**: whole block at 55% opacity, grey gradient knob, caption "Connect headphones to enable."
- **Queue rows**: radius 12, full file-path tooltip (`.help()`), active row = teal 16% fill + ring + animated 3-bar equalizer replacing the index.

### 5. Motion & states
- Spectrum + row equalizer animate only while playing; pause → freeze + dim (opacity .4).
- Hovers: transport buttons (white 10%), rows (white 5%), pills (white ~10-12%).
- Respect Reduce Transparency (fall back to opaque fills) and Reduce Motion (no pulse/eq animation).

## Files
- `Player Layout Variants.dc.html` + `support.js` — full exploration canvas; implement **8a** (= 7a + production polish).
- `NowPlayingView.swift` — base layout implementation to start from (apply the glass layer above).
- `now-playing-base.html` — standalone base-layout reference.
