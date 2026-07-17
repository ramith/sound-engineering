# S10.7 — Liquid Glass UI polish (design)

> Status lives in [sprint-plan.md §Status](sprint-plan.md#status), not here. This doc carries the
> sprint's scope, architecture, chunk plan, decisions, and QA plan.
> **Design sources of truth:** [docs/design/now-playing-7a/](../design/now-playing-7a/README.md) —
> `README.md` (glass recipe), `INTEGRATION.md` (repo mapping + the 6-PR skeleton this plan grew
> from), `Player Layout Variants.dc.html` **card 8a** (release target = 7a glass + production
> polish), `now-playing-base.html` (base layout), `NowPlayingView.swift` (visual reference — NOT a
> drop-in; the repo has a governed UI layer).

## 1. Goal

Adopt the founder-approved **8a "Liquid Glass"** design on the **Now Playing tab + the global
shell** (chrome bar, footer transport) with a **HIG-correct layer policy**: system Liquid Glass
only where macOS provides it (we never imitate system chrome), and the app's own "glass-look"
surfaces built as token-governed content-layer styling — no hand-painted `rgba` in views, no
appearance hacks, no accessibility regressions. Other tabs pick up the same tokens as a
fast-follow sprint; nothing here may fork a second styling system.

Founder directives binding on this sprint: architecture must be **clean, no hacks**, grounded in
current Apple guidance (researched online 2026-07-17, §3.0); **the-fool** red-teams the design
and every chunk for hack-smells; **qa-expert + the-fool** evolve the test rig for visual work (§7).

## 2. Scope — locked founder decisions

| # | Decision (LOCKED) | Consequence |
|---|---|---|
| **D1** | Scope = **Now Playing + global shell** | EQ/Library/Monitoring/Settings only inherit tokens later (fast-follow); their layouts don't change in S10.7. |
| **D2** | Inspector = **trailing 260pt glass column** (8a) | `NowPlayingTabView` leaves the 50/50 `containerRelativeFrame` split → queue-flex + fixed-260 inspector (§5). |
| **D3** | **Transport stays in the footer** (`NowPlayingBar`, L3) | 8a's in-hero transport pill + scrubber are NOT implemented; the footer gets the glass-look restyle instead. |
| **D4** | **Chrome stays a band**, not 8a's floating detached capsule | Preserves the L2 window-drag setup + the "fixed top-left" invariant; the band keeps the window surface, its CONTROLS restyle via tokens. |

Non-goals (this sprint): album-art-sampled glow colors (D8 fast-follow); 8a's queue filter field
(D7); any change to `ShellMetrics`/`Footer` metrics or window minimums; any playback-engine work;
**an overlay-bar shell** (making content scroll UNDER a true-glass footer is the one place real
refraction would earn its keep — Apple's showcase pattern — but it reverses the L1 decision that
moved AppShell from `safeAreaInset` to explicit frames precisely because content rendered behind
chrome, and glass over a 20 Hz animating backdrop has no published perf evidence. Revisit post-R1
as its own design if wanted.)

## 3. Materials architecture

### 3.0 Research grounding (online pass, 2026-07-17)

Two research sweeps ground this section: a native-API inventory and an adoption-pitfalls survey
of Apple docs/HIG, WWDC25/26 sessions, and named-author engineering write-ups. Load-bearing
findings, cited where they change our design:

1. **Apple's adoption order is "recompile → subtract → add":** system components pick up the new
   look automatically; the first *active* step is REMOVING custom backgrounds that fight system
   glass, and custom `glassEffect` comes last, "sparingly"
   ([Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass),
   [Landmarks sample](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)).
2. **Glass is the controls/navigation layer floating above content — never the content layer, and
   never glass-on-glass**
   ([HIG · Materials](https://developer.apple.com/design/human-interface-guidelines/materials);
   [Donny Wals](https://www.donnywals.com/designing-custom-ui-with-liquid-glass-on-ios-26/)).
   Content-layer *structure* should use standard effects (fills, blur, vibrancy) — not Liquid
   Glass (HIG, same page).
3. **"Ghost glass":** glass needs rich, varied content *beneath* it; over a flat or app-owned
   static backdrop it renders as an inert gray platter — a named anti-pattern
   ([STRV / Apple developer-event guidance](https://www.strv.com/blog/how-to-apply-liquid-glass-to-your-app),
   [Blake Crosley](https://blakecrosley.com/blog/liquid-glass-swiftui-patterns)).
4. **Glass over continuously animating content** forces real-time backdrop resampling (each glass
   surface is a `CABackdropLayer` rendering ~3 offscreen textures); guidance is to keep animation
   out of glass contexts; no published macOS measurements exist for glass over a ~20 Hz canvas
   ([Apple · Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views),
   [JuniperPhoton adoption postmortem](https://juniperphoton.substack.com/p/adopting-liquid-glass-experiences)).
5. **Accessibility:** native glass/system materials adapt to Reduce Transparency / Increase
   Contrast / Reduce Motion automatically; anything hand-built gets **nothing** automatically and
   must react to those environment flags itself. macOS couples Increase Contrast → forces Reduce
   Transparency on
   ([Apple](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass),
   [Six Colors](https://sixcolors.com/post/2025/11/soaping-up-liquid-glass-less-transparency-more-contrast/)).
   Tint/accent tokens need light/dark **and increased-contrast** variants (Apple, same doc).
6. **The cautionary tale is Apple's own Music app** (white glass transport washing out on white
   playlists); the positive proof is **Longplay for Mac** — glass confined to navigation/floating
   controls, legibility intact
   ([Mac Observer](https://www.macobserver.com/news/apple-music-on-macos-tahoe-is-a-mess-and-users-have-had-enough/),
   [MacStories roundup](https://www.macstories.net/stories/wading-back-into-the-liquid-glass-pool-the-macstories-os-26-app-roundup-continued/)).
7. WWDC26 reworked glass foundations (light diffusion, contrast) and added a user transparency
   slider — benefits accrue **only** to system-material users; hand-rolled imitations of system
   chrome silently ignore user preference
   ([MacRumors](https://www.macrumors.com/2026/06/08/apple-announces-liquid-glass-improvements/)).

*(§3.0 API-name footnotes — exact shipping signatures for `glassEffect`/`GlassEffectContainer`/
concentric-corner APIs — finalized from the API-inventory sweep; see §3.5.)*

### 3.1 The layer policy (the core idea)

The 8a design was authored in CSS, where "glass" is one thing. On macOS 26 it decomposes into
three different implementation regimes, and picking the right regime per surface is exactly what
"clean, no hacks" means here:

- **Regime A — system Liquid Glass, owned by the system.** Menus (device picker dropdown,
  context menus), popovers, sheets, tooltips, and the native segmented control's own macOS 26
  look. We take these for free, and we **subtract interference** (no custom fills/skins fighting
  them). We do NOT hand-apply `glassEffect` anywhere this sprint — every candidate surface fails
  the HIG placement test below.
- **Regime B — app "glass-look" panels: token-governed content-layer styling.** The analyzer
  lens, inspector column, device pill, badges, and both shell bands are **flow-layout structure**
  in this app: `AppShell` stacks bands and panes; *nothing ever renders beneath these surfaces
  except the app's own static glow field* (§3.3). Backdrop-sampling machinery (`glassEffect` OR
  `Material`) over a self-owned static backdrop is ghost glass (§3.0-3) plus cost plus manual
  accessibility branching — for pixels identical to a translucent **fill**. So Regime B is:
  dynamic translucent fills + edge decoration (specular top rim, hairline, bottom light bleed,
  shadow) composed by ONE modifier from `DesignSystem.Glass` tokens. Deterministic in both
  appearances, zero backdrop layers, and *we* own the Reduce-Transparency/Increase-Contrast
  fallbacks in one place. ("Edges matter more than surfaces" is the documented craft insight for
  exactly this kind of panel — [Klarity](https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos).)
  *Considered alternative:* HIG does sanction standard `Material`s for content-layer structure —
  a material substrate under the same decoration would auto-track system translucency settings at
  the cost of determinism and an extra backdrop pass. Because the role modifier hides the choice,
  swapping fills → material later touches ZERO call sites; we start with fills (simpler,
  deterministic, nothing variable to blur) and let the founder's PR-2/3 by-eye + the SME panel
  overturn it if the look reads flat. The 8a CSS `saturate(1.5)` backdrop boost is dropped
  outright — SwiftUI has no public backdrop-filter API (§3.5), and approximating it would be
  exactly the kind of hack this sprint bans.
- **Regime C — plain content styling.** Ambient glows, queue-row tints, title halo,
  gradient-fade dividers, meter fills: ordinary fills/gradients from tokens. Queue **rows** stay
  opacity-tinted fills (`rowNowPlaying`/`rowSelected`) — per-row surfaces are both a HIG
  violation and the canonical perf trap (§3.0-2/-4).

**The placement test (mechanical, fool-checkable):** *does variable content render beneath this
surface at runtime?* No → Regime B/C (fills). Yes → it must be system glass — and if we can't use
system glass there, we don't build the surface. Today NOTHING in the app answers "yes" (stacked
bands, flow panels) — which is why this sprint ships zero hand-applied `glassEffect` and zero
`Material` usage, and why the one future "yes" candidate (an overlay footer with the queue
scrolling beneath) is explicitly parked in §2 as a post-R1 design.

This is not a rejection of Liquid Glass — it's the HIG's own assignment of our surfaces to the
content layer, using the content layer's sanctioned tools (§3.0-2), while every system-owned
surface (menus/sheets/controls) renders true glass untouched.

### 3.2 `DesignSystem.Glass` — the only place glass-look is defined

PR 1 adds a `Glass` namespace to `DesignSystem.swift` (same governance as `Footer`/`QueueRow`):

- **Surface roles, not ad-hoc values:** a `.glassPanel(_ role:)` ViewModifier with roles
  `panel` (inspector, radius 22), `lens` (analyzer, radius 20), `control` (pills, radius h/2),
  `badge` (radius 10–11). A view says *what it is*, never *how glass looks*. The modifier owns
  fill + rim + hairline + bleed + shadow composition and the accessibility fallbacks.
- **Token'd decoration:** rim/hairline/bleed/shadow values + the three ambient-glow colors from
  the 8a spec as `DesignSystem.Glass.*` constants; every fill via the existing
  `DesignSystem.Color.dynamic(light:dark:)` — 8a's values are the dark side; light appearance is
  a first-class variant (white-based fills + dark hairlines), tuned in the founder's `make run`.
- **Increased-contrast variants** for accent/tint tokens (§3.0-5): the dynamic provider already
  resolves per-appearance; it extends to the high-contrast appearance names so Increase Contrast
  gets stronger hairlines/borders without view-level branching.
- **Typography:** `DesignSystem.Font.heroTitle` (Dynamic-Type-mapped large-title style, heavy
  weight — the 8a 28/800 hero) added beside the existing rungs.
- **Radii concentricity:** the 8a concentric map (window 22 → panel 22 → lens 20 → pills h/2 →
  rows 12 → badges 10–11) recorded as `Glass.Radius` tokens; if the shipping concentric-corner
  API (§3.5) fits our fixed-band shell, roles adopt it instead of constants — decided in PR 1
  review, not per call site.
- **Accessibility inside the modifier, not call sites:** Reduce Transparency (which macOS also
  forces on under Increase Contrast) swaps translucent fills → opaque `Color.panel`-family
  tokens. Reduce Motion is consumed by the two animated accents (§3.4), which are the only
  motion this sprint adds.

**Enforcement (rig, §7 R1):** a static tripwire bans `Material`/`.ultraThinMaterial`,
`glassEffect`, `NSVisualEffectView`, and `Color(red:` literals in `Sources/AdaptiveSound/UI/**`
outside the DesignSystem/Glass files — the token layer is load-bearing, so it gets a tripwire
like every other invariant in this repo. (The ban on `glassEffect` is deliberate: per §3.1 any
future use must arrive together with an under-content surface, i.e. through a design review that
also updates this doc and the tripwire — not ad hoc.)

### 3.3 Ambient glow field (content layer)

A `GlowField` background ZStack behind `NowPlayingTabView` content: three blurred radial
gradients (teal top-left ~720×560 / lime bottom-right ~760×600 / blue mid-right ~420×380, blurs
28–34) over the window base. Static brand colors this sprint (D8). Dark appearance per spec;
light appearance gets deliberately subtler variants. This is what the Regime-B translucent fills
visibly sit over — it's what makes them read as glass — so it lands (PR 2) before the panels
(PR 3+). Pure decoration → `accessibilityHidden(true)`, no motion, and under Reduce Transparency
it flattens to the plain window color (translucency semantics, owned by the same token layer).

### 3.4 Motion & state rules

- ENHANCED badge pulsing dot (1.6s opacity 1→0.4) and the active-queue-row 3-bar equalizer
  animate **only while playing** and **only when Reduce Motion is off** — same gating the
  spectrum already uses (`SpectrumAnalyzerView` dims to 0.4 on pause; keep that).
- No animated panel properties (no fill/shadow animation — documented fallback-stack smell);
  transitions stay the existing `.easeInOut(0.2)` tab-level ones.
- Hovers per 8a (rows white 5%, pills 10–12%) via tokens.

### 3.5 Native-API footnotes (SDK-verified inventory, macOS 26.5 SDK, 2026-07-17)

The API research pass pulled Apple's doc JSON and cross-verified every signature against the
installed `MacOSX26.5.sdk` swiftinterfaces — these are SHIPPING names (several beta-era spellings
died; do not copy blog code unchecked). Recorded so any future Regime-A adoption starts verified:

- `glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape())`
  (default shape = Capsule). **No `isEnabled:` parameter ships** — conditional disabling is
  `Glass.identity`. `Glass`: `.regular` (adaptive), `.clear` (no adaptive legibility; Apple's own
  pattern adds a ~35% dark dimming layer), `.identity`, `.tint(_:)` (adaptive/brightness-mapped —
  **cannot force a literal brand color**), `.interactive()` (pointer-reactive on macOS 26).
- `GlassEffectContainer(spacing:)` — batches N glass backdrops into one sampling pass (each
  standalone glass = a `CABackdropLayer` ≈ 3 offscreen textures); `glassEffectID(_:in:)`,
  `glassEffectUnion(id:namespace:)`, `glassEffectTransition(_:)`.
- Buttons: `.buttonStyle(.glass)`, `.glassProminent`, `.glass(_ glass:)`; AppKit
  `NSButton.BezelStyle.glass`. Apple: prefer these over custom glass effects on buttons.
- `scrollEdgeEffectStyle(.hard/.soft/.automatic, for:)` + `scrollEdgeEffectHidden`; **`safeAreaBar
  (edge:alignment:spacing:content:)`** registers a CUSTOM bar into the scroll-edge system — the
  sanctioned hook if the §2 overlay-footer exploration ever happens post-R1.
- `backgroundExtensionEffect()` (hero content extending under sidebar/inspector; "apply with
  discretion… performance"); relevant to a future album-art hero, not this sprint.
- Toolbars: system glass automatic on the macOS window toolbar; `ToolbarSpacer(.fixed/.flexible)`
  splits shared-glass groups; `sharedBackgroundVisibility(_:)` per item. (Our chrome is an
  app-owned band per D4, so none of this applies until/unless the shell ever migrates.)
- Concentric corners: **`.containerConcentric` never shipped** — the shipping API is
  `ConcentricRectangle` / `Edge.Corner.Style.concentric(minimum:)` / `.rect(corners:isUniform:)`,
  resolved against a `containerShape`. PR 1 review decides tokens-vs-concentric for our inset
  panels (they don't hug the window container, so fixed tokens are the likely fit).
- Accessibility (native glass): Reduce Transparency → frostier; Increase Contrast →
  black/white + border (and macOS force-enables RT under IC); Reduce Motion → damped effects —
  automatic for the MATERIAL, while app-triggered animations and custom overlays remain ours.
  macOS 26.1 added a user Clear/Tinted glass preference; macOS 27 (beta) adds a transparency
  slider — system materials track these, app-owned fills legitimately don't (content design).
- `Material` (e.g. `.ultraThinMaterial`) blurs **in-app** content only; HIG sanctions standard
  materials for content-layer structure. There is **no public backdrop-filter API** in SwiftUI
  (the 8a CSS `saturate(1.5)` boost is not reproducible and is dropped from the recipe).
- `NSGlassEffectView`/`NSGlassEffectContainerView` exist for AppKit (regular/clear only;
  `effectIsInteractive` is macOS 27); `NSVisualEffectView` = the standard-materials system
  (behind-window blending), NOT Liquid Glass — remains banned in `UI/**` (§3.2).

## 4. What already matches (don't rebuild)

`SpectrumColorPalette` (exact Teal→Lime + 0.82 vertical darken), spectrum pause-dim + Reduce
Motion handling, real FFT source (`AudioViewModel.spectrumBars` ~20 Hz), `AppShell` band
architecture, WCAG-audited dynamic label palette, `FormatBadgeView`, loudness meters, queue row
tint tokens, the 5-tab set. The sprint restyles; it does not re-derive any of these.

## 5. Target Now Playing layout (the one structural change — PR 5)

Current: `NowPlayingTabView` = 50/50 split (`LeftPanelView` scroll: spectrum → master gain →
info/meters/intensity/crossfeed | `RightPanelView`: queue).

Target (8a, transport-less per D3):

```
ZStack {
  GlowField (Regime C, PR 2)
  VStack(spacing: 0)                      // inside AppShell's bounded content region
  ├─ HeroBand                             // title/artist/badges left … analyzer lens right
  │    ├─ VStack: heroTitle (28/800 + teal halo), artist, badge row
  │    │          [FormatBadge · ENHANCED(pulsing dot) · sample-rate]
  │    └─ SpectrumAnalyzerView in .glassPanel(.lens)  — 400×122 w/ dB grid,
  │         0 dB label, 20 Hz–20 kHz scale, peak-hold caps        (D6)
  └─ HStack(spacing: 0)
       ├─ Queue (flex)                    // PlaylistView, unchanged internals
       └─ InspectorColumn (fixed 260, .glassPanel(.panel))         (D2)
            master gain · Reimagine intensity · loudness meters · crossfeed
            (moved from LeftPanelView/NowPlayingInfoView; scrolls if short window)
}
```

Notes: the lens is a Regime-B fill **behind** the bars — never anything sampling over them
(§3.0-4). Window min 880×640 holds — the queue *gains* width (~590 vs today's 440 at minimum);
the inspector top aligns with the queue header (8a alignment grid: 16pt panel insets, 26pt text
gutter). Sliders adopt the 8a carved look (5pt inset track, 14pt knob, teal glow fill) via ONE
shared slider primitive — extracted from the existing custom `FooterScrubber` drag logic rather
than a second hand-rolled slider (one control, two consumers). Crossfeed keeps its existing
disabled semantics (55% block opacity + caption — already implemented). `LeftPanelView` /
`RightPanelView` dissolve into `HeroBand` + `InspectorColumn`; the double-click-spectrum →
Monitoring affordance moves onto the lens.

## 6. Chunk plan (6 PRs, each independently shippable + gated)

| PR | Deliverable | Key files | Acceptance (beyond the standard gate) |
|---|---|---|---|
| **1. Glass tokens** | `DesignSystem.Glass` roles/tokens + `.glassPanel(_:)` modifier (fills + edge decoration; RT/IC fallbacks inside) + `heroTitle` font + glow colors + radii; **zero call sites** | `DesignSystem.swift` (+ `DesignSystemGlass.swift` peer file) | No visual change (`make run` before/after identical); token-scope tripwire lands in the same PR (§7 R1) |
| **2. Ambient glow** | `GlowField` behind Now Playing content; dark + subtler light variants; RT → flat window color | `NowPlayingTabView` (+ small `GlowField.swift`) | Founder eyeball both appearances; Reduce Transparency flattens |
| **3. Analyzer lens** | Lens panel (Regime B) around the spectrum: dB gridlines (4 hairlines), 0 dB label, 20 Hz–20 kHz scale, **peak-hold caps** (2px, bar color @50%, 4px above bar, ~600 ms hold then decay) | `SpectrumAnalyzerView.swift` + `PeakHoldTracker` (pure, unit-tested) + small overlay views | Caps freeze on pause + honor Reduce Motion; `PeakHoldTracker` swift-testing cases green; heights still sourced from `spectrumBars` |
| **4. Hero** | `HeroBand`: heroTitle + halo, artist line, badge row (`FormatBadgeView` capsule variant, ENHANCED pulsing dot, fixed 22pt badge height) | `NowPlayingInfoView.swift` → `HeroBand` (widget card retires here) | Pulse gated on `isPlaying && !reduceMotion`; badges identical height; long-title truncation |
| **5. Inspector column** | The §5 restructure: queue-flex + fixed-260 inspector; carved-slider primitive shared w/ footer scrubber; meters restyle | `NowPlayingTabView`, new `InspectorColumn.swift`, `MasterGainSliderView`, `NowPlayingInfoView` split, `LoudnessMetersView` | Keyboard/VO traversal order sane; 880pt window: no truncated readouts (the S9 LUFS-clip lesson); inspector scrolls on short windows |
| **6. Chrome + footer restyle** | Band surfaces stay window/panel colors (no fake glass slabs); device pill restyled via tokens (+ sample-rate readout, D5); tab selector per D9; footer regions restyled via tokens; subtract-interference audit (nothing fights system menus/popovers) | `ChromeBar.swift`, `NowPlayingBar.swift` | `ShellMetrics`/`Footer` metrics byte-identical; window-drag on chrome still works (L2); media-key/transport behavior untouched |

Order: 1→2→3→4→5→6. PRs 2–4 are restyles inside the current split (they do NOT wait for the
restructure); PR 5 is the only layout change; PR 6 touches shared shell last, once the token
layer has been proven on lower-risk surfaces. Every PR: the standard loop — SME review
(swiftui-pro + macos-design), `scripts/strict-gate.sh` green, founder `make run` matrix (§7 R6).

## 7. Test-rig evolution (qa-expert + the-fool own this — seeded, not final)

The rig today (strict-gate: format/lint/semgrep/periphery/migrator+drop-path greps/build/test/
C++ gates; VerifyLibraryStore; `make run` = the only visual check) verifies none of what this
sprint changes. Proposed additions for the QA panel to accept/reject/replace:

- **R1 — token-scope tripwire (static, in strict-gate):** ban `Material`/`.ultraThinMaterial`,
  `glassEffect`, `NSVisualEffectView`, and `Color(red:` literals in `UI/**` outside
  DesignSystem/Glass files (§3.2). Same pattern as the migrator-posture/drop-path greps.
- **R2 — pure-logic extraction + unit tests:** `PeakHoldTracker` (hold/decay math), the
  RT-fallback resolution (given the flag, the modifier resolves opaque), the pulse-gating
  predicate — plain swift-testing cases (no UI harness needed).
- **R3 — snapshot testing (evaluate, don't assume):** pointfree `swift-snapshot-testing` over
  `NSHostingView` offscreen renders for HeroBand/InspectorColumn/lens. Because Regime B is plain
  fills (no Materials), offscreen renders are **deterministic** — the classic
  materials-don't-render-off-window objection doesn't apply. Open question for the panel:
  cross-macOS-build brittleness vs value in a founder-eyeballs-every-PR loop.
- **R4 — contrast re-audit against composites:** the label palette was WCAG-audited against
  SOLID surfaces; Regime B makes the effective backdrop = fill ⊕ glow ⊕ window. Because all
  three are app-owned tokens, worst-case composite colors are computable — re-verify AA for
  label/labelSecondary on the lightest composite in both appearances (+ Increase Contrast
  forced-RT state). VoiceOver traversal after the PR-5 restructure.
- **R5 — performance sanity:** a documented manual Instruments pass (or a cheap FPS probe) on
  the Now Playing tab while playing, dark mode, after PR 3 and PR 5. Regime B removed the
  backdrop-sampling cost by construction, so the budget (no sustained dropped frames at 120 Hz)
  should hold trivially — verify, don't assume.
- **R6 — founder visual matrix as a committed checklist:** per-PR: {dark, light} ×
  {Reduce Transparency on/off} × {Reduce Motion on/off} spot-grid (8 cells, ~4 that matter per
  PR) so "looks right" is a repeatable pass, not vibes.

## 8. Risks

| Risk | Mitigation |
|---|---|
| 8a look drifts from what fills-without-materials can express (founder judges it "not glassy enough") | The glow field is what sells the effect (§3.3 lands early); PR 2+3 give the founder the earliest possible by-eye check; escalation path is a REAL under-content surface (§2 overlay-footer, post-R1), never fake backdrop stacks |
| Legibility on translucent fills (light mode especially) | Labels stay the explicit WCAG palette; R4 composite re-audit; Increase Contrast (forces RT on macOS) verified per PR |
| PR-5 restructure regresses keyboard/VO or the S9 truncation fixes | PR-5 acceptance explicitly re-runs those checks; swiftui-pro review on the restructure |
| Chrome/footer restyle disturbs L2 window-drag or `.clipped()` shadows at band seams | D4 keeps band structure; shadows kept inside the content region via spacing tokens; PR-6 last |
| System-glass drift (macOS updates re-tune menus/controls while our token surfaces stay fixed) | Regime split is explicit: system surfaces are never skinned, so they track the OS; token surfaces are app content design (like album-art UI), legitimately stable |
| Scope creep into other tabs ("just one more surface") | D1: tokens only; any non-Now-Playing layout change is out of sprint |

## 9. Open decisions for the founder (recommendations first)

| # | Question | Recommendation |
|---|---|---|
| **D5** | Device pill sample-rate readout ("44.1 kHz", live)? | **Yes** — audiophile-signal, data already flows through the signal-path readout; small (PR 6). |
| **D6** | Analyzer placement: 8a hero-right lens (400×122) vs today's full-width 50pt strip under the hero? | **Adopt 8a hero-right** — it's the design's centerpiece and the lens treatment reads best as a framed panel (PR 5 layout; PR 3 styling works either way). |
| **D7** | 8a's queue filter field? | **Defer** — the queue is a working set, not a library; Library surfaces already have filter fields. Revisit post-R1 if queues run long. |
| **D8** | Glow colors: static brand teal/lime/blue vs album-art-sampled? | **Static now**, art-sampled as a fast-follow (needs dominant-color extraction + caching design of its own). |
| **D9** | Tab selector: keep the native segmented control vs build 8a's custom tab capsule (teal-gradient active pill)? | **Keep native** — free macOS 26 styling + full a11y/keyboard behavior tracks the OS; a custom capsule is bespoke-control debt for a brand accent. Revisit only if the founder judges the native look breaks the design. |

## 10. Definition of done

All six PRs merged with green gates; founder visual matrix passed per PR; qa-expert + the-fool
break-it round on the finished tab (focus: appearance switching mid-play, Reduce-* toggles at
runtime, window at min size, empty queue/no-track, long titles/many badges, tab-switch churn
while playing); rig additions from §7 landed or explicitly rejected in this doc; sprint-plan
§Status updated; retro captured.
