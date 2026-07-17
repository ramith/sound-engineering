# S10.7 — Liquid Glass release UX (design)

> Status lives in [sprint-plan.md §Status](sprint-plan.md#status), not here. This doc carries the
> sprint's scope, architecture, chunk plan, decisions, and QA plan.
> **Design sources of truth:** [docs/design/now-playing-7a/](../design/now-playing-7a/README.md) —
> `README.md` (glass recipe), `INTEGRATION.md` (repo mapping + the 6-PR skeleton this plan grew
> from), `Player Layout Variants.dc.html` **card 8a** (release target = 7a glass + production
> polish), `now-playing-base.html` (base layout), `NowPlayingView.swift` (visual reference — NOT a
> drop-in; the repo has a governed UI layer).
> **Review provenance:** researched online 2026-07-17 (Apple docs/HIG/WWDC25-26 + an SDK-verified
> API inventory against MacOSX26.5); SME panel: swiftui-pro + macos-design + qa-expert (rig);
> final gate: architect-reviewer (**APPROVED WITH AMENDMENTS** — all landed) + the-fool
> (**PASS WITH AMENDMENTS** — all landed; its §4 "could not break" list covers the fills-vs-glass
> thesis, the placement test in-sprint, D10's WCAG direction, and the R0/R3/R5 rig calls).
> Findings are folded in below, not appended.

## 1. Goal

Ship the founder-approved **8a "Liquid Glass"** design on the **Now Playing tab + the global
shell** (chrome bar, footer transport) as **the release UX**. Founder 2026-07-17: the current UI
is elementary and **not releasable** — this is a design-from-scratch sprint for the product's
face, not a polish pass, and **R1 now gates on it** (plus the S10.8 tab sweep). Longer term the
**entire GUI redesigns around Liquid Glass**: the `DesignSystem.Glass` token layer built in PR 1
is the permanent foundation of that system, so it is designed for the whole app, not just the
five surfaces this sprint touches.

The implementation posture is a **HIG-correct layer policy**: system Liquid Glass only where
macOS provides it (we never imitate system chrome), the app's own "glass-look" surfaces built as
token-governed content-layer styling — no hand-painted `rgba` in views, no appearance hacks, no
accessibility regressions.

Founder directives binding on this sprint: architecture must be **clean, no hacks**, grounded in
current Apple guidance (§3.0); **the-fool** red-teams the design and every chunk for hack-smells;
**qa-expert + the-fool** evolve the test rig for visual work (§7).

## 2. Scope — locked founder decisions

| # | Decision (LOCKED) | Consequence |
|---|---|---|
| **D1** | Scope = **Now Playing + global shell** | Library/EQ/Monitoring/Settings keep their layouts; they adopt the proven tokens in **S10.8** (surfaces/controls/type only — per-tab layout redesigns are post-R1 waves of the full Liquid-Glass redesign). |
| **D2** | Inspector = **trailing 260pt glass column** (8a) | `NowPlayingTabView` leaves the 50/50 `containerRelativeFrame` split → queue-flex + fixed-260 inspector (§5). |
| **D3** | **Transport stays in the footer** (`NowPlayingBar`, L3) | 8a's in-hero transport pill + scrubber are NOT implemented; the footer's CONTROLS restyle via tokens (its band surface — `panel`, per AppShell — is unchanged). The hero is recomposed for its transport-less reality (§5). |
| **D4** | **Chrome stays a band**, not 8a's floating detached capsule | Preserves the L2 window-drag setup + the "fixed top-left" invariant; the band keeps a quiet window surface + its existing solid hairline (NO glass slab, NO added elevation); its CONTROLS restyle via tokens. |
| **D11** | **R1 gates on S10.7 + S10.8** | "Nothing elementary ships." S10.8 = token sweep across the remaining tabs after this sprint proves the tokens. |

Non-goals (this sprint): any change to `ShellMetrics`/`Footer` metrics or window minimums; any
playback-engine work;
**an overlay-bar shell** (making content scroll UNDER a true-glass footer is the one place real
refraction would earn its keep — Apple's showcase pattern, sanctioned hook = `safeAreaBar`
(§3.5) — but it reverses the L1 decision that moved AppShell from `safeAreaInset` to explicit
frames precisely because content rendered behind chrome, and glass over a 20 Hz animating
backdrop has no published perf evidence. Revisit post-R1 as its own design if wanted.)

**Known deltas vs the 8a mock (founder: accept up front, by-eye at PR 2/3 confirms):** the top of
the window is a quiet band, not a floating glass capsule (D4); the hero is title + badges, not a
transport cockpit (D3); and without a backdrop-saturation API (§3.5) the panels run slightly less
vivid than the browser mock unless the accent-chroma compensation knob (§3.2) is adopted.
Expected fidelity ≈ 85% — the visual thesis (glow field, lens, inspector, teal light) survives
intact.

## 3. Materials architecture

### 3.0 Research grounding (online pass, 2026-07-17)

Two research sweeps ground this section: a native-API inventory (SDK-verified, §3.5) and an
adoption-pitfalls survey of Apple docs/HIG, WWDC25/26 sessions, and named-author engineering
write-ups. Load-bearing findings, cited where they change our design:

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

### 3.1 The layer policy (the core idea)

The 8a design was authored in CSS, where "glass" is one thing. On macOS 26 it decomposes into
three different implementation regimes, and picking the right regime per surface is exactly what
"clean, no hacks" means here:

- **Regime A — system Liquid Glass, owned by the system.** Menus (device picker dropdown,
  context menus), popovers, sheets, tooltips, and the native segmented control's own macOS 26
  look. We take these for free, and we **subtract interference** (no custom fills/skins fighting
  them). We do NOT hand-apply `glassEffect` anywhere this sprint — every candidate surface fails
  the placement test below.
- **Regime B — app "glass-look" panels: token-governed content-layer styling.** The analyzer
  lens, inspector column, device pill, and badges are **flow-layout structure**: *nothing ever
  renders beneath these surfaces except the app's own static glow field* (§3.3).
  Backdrop-sampling machinery (`glassEffect` OR `Material`) over a self-owned static backdrop is
  ghost glass (§3.0-3) plus cost plus manual accessibility branching — for pixels identical to a
  translucent **fill**. So Regime B is: dynamic translucent fills + edge decoration (specular top
  rim, hairline, bottom light bleed, shadow) composed by ONE modifier from `DesignSystem.Glass`
  tokens. Deterministic in both appearances, zero backdrop layers, and *we* own the
  Reduce-Transparency/Increase-Contrast fallbacks in one place. ("Edges matter more than
  surfaces" — [Klarity](https://www.klaritydisk.com/blog/building-liquid-glass-ui-macos).)
  The SHELL BANDS are **not** Regime B: per D4 they keep quiet window/panel surfaces + solid
  hairlines; only the controls sitting on them restyle.
  *Considered alternative:* HIG does sanction standard `Material`s for content-layer structure —
  a material substrate under the same decoration would auto-track system translucency settings at
  the cost of determinism and an extra backdrop pass. Because the role modifier hides the choice,
  swapping fills → material later touches ZERO call sites; we start with fills (simpler,
  deterministic, nothing variable to blur) and let the founder's PR-2/3 by-eye + panel judgment
  overturn it if the look reads flat. The 8a CSS `saturate(1.5)` backdrop boost is dropped
  outright — SwiftUI has no public backdrop-filter API (§3.5), and approximating it would be
  exactly the kind of hack this sprint bans. The sanctioned vividness knob is §3.2's
  accent-chroma compensation.
- **Regime C — plain content styling.** Ambient glows, queue-row tints, title halo,
  gradient-fade hairlines (content-internal separators ONLY — band seams keep the full-width
  solid `Hairline`), meter fills: ordinary fills/gradients from tokens. Queue **rows** stay
  opacity-tinted fills (`rowNowPlaying`/`rowSelected`) — per-row surfaces are both a HIG
  violation and the canonical perf trap (§3.0-2/-4).

**The placement test (mechanical, fool-checkable):** *does variable content render beneath this
surface at runtime?* No → Regime B/C (fills). Yes → system glass or system Material — and if
neither fits, we don't build the surface. **"Variable" is defined** (so the test survives the
app's growth): *spatially structured content that a backdrop blur would visibly transform —
scrolling text, imagery, independent motion — beneath the surface.* A smooth low-frequency
field — static or per-track-tinted — blurs to itself and stays "no"; app-orchestrated DISCRETE
restyles (e.g. D8's track-change glow recolor) therefore stay Regime B: alpha compositing
still expresses them, no backdrop resampling involved. D8 is pre-bound accordingly:
art-sampled glow colors must clamp chroma/alpha into token-defined ranges, so the R4 audit
keeps enumerating bounded worst cases, never concrete albums.

**Applying the test to the codebase today (dry-run inventory — corrected by the fool gate, then
re-verified by grep 2026-07-17):** the bands and Now Playing panels all answer "no" — which is
why this sprint ships zero hand-applied `glassEffect` and zero NEW backdrop-sampling surfaces.
Pre-existing sites, dispositioned one by one:
- **Four surfaces answer "yes" and migrate to `.glassPanel(.overlay)` in PR 1a** (zero pixel
  change, now token-routed): the floating error banner
  ([ErrorBanner.swift](../../Sources/AdaptiveSound/UI/Shell/ErrorBanner.swift)), the queue toast
  ([QueueToast.swift](../../Sources/AdaptiveSound/UI/Shell/QueueToast.swift)), the EQ recall
  banner ([EQTabView.swift](../../Sources/AdaptiveSound/UI/Tabs/EQTabView.swift)) — and the
  selection pill at `PlaylistDetailView.swift:290` (`.background(.bar, in: Capsule())`), which
  floats over variable list content and passes the test like the other three.
- **Two Library `.background(.bar)` band sites** (`LibrarySidebar.swift:78,364`) are out of D1
  scope → house TEMP suppression until S10.8.
- **Named-color call sites rule 3 catches:** `ChromeBar.swift:52` `Color.white` → the existing
  `onAccent` token (migrates in PR 1b — same pixel, white IS onAccent); `LoudnessMetersView.
  swift:87/98` `Color.red` (clipping/hot state) → a NEW `statusError`/meter-hot token minted in
  PR 1a (a genuine token-system gap: `statusWarning` is orange); `NowPlayingBar.swift:303`
  shadow literal → TEMP until PR 6 restyles the footer. `Color.clear` is explicitly ALLOWED by
  rule 3 (transparent is absence-of-paint, not a painted color).
- (`SpectrumColorPalette.swift` computes interpolated `Color(red:)` — a token SOURCE, excluded
  as a definition file.)

### 3.2 `DesignSystem.Glass` — the only place glass-look is defined

The `Glass` namespace lives in `DesignSystemGlass.swift` (a peer of `DesignSystem.swift`, same
governance as `Footer`/`QueueRow`). Because the entire GUI eventually redesigns around these
tokens, the ROLE CHARTER below is named for the whole app — but **declarations land staged,
each with its first consumer** (`.overlay` in PR 1a, glow colors PR 2, `.lens` PR 3,
`heroTitle`/`.badge` PR 4, `.panel`+slider tokens PR 5, `.control` PR 6): the hostile Periphery
gate flags consumer-less tokens, and the repo already recorded this lesson at `SongsList`
("only the tokens THIS slice consumes"). **S10.8 may ADD roles** (e.g. `field`, `tableHeader`)
through the same doc-update process — surfaces are never shoehorned into wrong roles to avoid
re-opening this doc:

- **Surface roles, not ad-hoc values:** a `.glassPanel(_ role:)` ViewModifier with roles
  `panel` (inspector + future side panels, radius 22), `lens` (analyzer + future visualizer
  frames, radius 20), `control` (pills, radius h/2), `badge` (radius 10–11), and `overlay`
  (the ONE Material-backed role — transient floating surfaces with variable content genuinely
  beneath, §3.1: banner/toast/recall/selection-pill). **`.overlay` is specified tightly so the
  PR-1a migration is pixel-identical:** Material + a call-site SHAPE parameter (capsule for
  toast/recall/pill, rounded rect for the banner) + each site's existing hairline — **no added
  decoration strata, and RT/IC deliberately left to the Material's NATIVE adaptation** (these
  are the only surfaces where the system, not our resolver, owns the fallback). A view says
  *what it is*, never *how glass looks*. The modifier owns fill + rim + hairline + bleed + shadow
  composition and the accessibility fallbacks. Edge decoration composes as distinct strata —
  top-edge-only 1px specular highlight (never a full-perimeter stroke), a separate full 1px
  hairline, a wide soft bottom-only inner bleed, and a soft deep drop shadow (large radius, low
  alpha — never tight/dark). That layering, not the fill, is what separates Mac glass from a
  web card.
- **`DesignTokenKit` (R0, §7 — the testability spine):** the app is an `executableTarget`, so
  tests cannot import it (the constraint that already produced `PlaybackQueueKit` and
  `LibraryBrowseKit`). PR 1a puts the sprint's pure visual core in a small library target.
  **Admission charter:** the Kit holds design-token DATA (light/dark RGBA pairs, radii,
  decoration constants, slot widths — plain structs) **and their pure resolvers over
  appearance, accessibility flags, and time** (`resolveSurface(role:appearance:
  reduceTransparency:increasedContrast:)`; `PeakHoldTracker` — the resolver of motion-design
  tokens over fed time; the animation-gate predicate); NOTHING that imports SwiftUI/AppKit
  (enforced by a strict-gate purity guard, §7 R1). Escape hatch: a second visualizer state
  machine triggers extraction to its own target (the `PlaybackQueueKit` precedent), not Kit
  growth. **Single-source invariant (D10-critical):** every color the R4 audit composites
  over — INCLUDING the legacy `window`/`card`/`panel`/`hairline`/label palette that D10
  re-bases — is defined once as Kit data; `DesignSystem.Color.*` keeps its API but re-exports
  Kit values; no RGBA value may exist in both places, else the "permanent audit" audits a
  hand-mirror. (The semgrep definition-file carve-out means REVIEW, not the rule, owns the
  "no new literals in the definition files" seam.)
- **Token'd decoration:** rim/hairline/bleed/shadow values + the three ambient-glow colors from
  the 8a spec as `DesignSystem.Glass.*` constants; every fill via the existing
  `DesignSystem.Color.dynamic(light:dark:)`.
- **The dark base (D10):** 8a is tuned against window `#0e1013`; the shipping dark window is
  `#1E1E1E` — twice as light. Every glow alpha, panel fill, and rim value assumes the deep base.
  D10 (§9) decides re-basing the dark surface stack (window → ≈`#0e1013`–`#121418`, card/panel
  re-checked) **app-wide** in PR 2 — one base per app is non-negotiable, and S10.8 inherits it.
  The R4 contrast audit runs against whichever base D10 picks.
- **Light appearance — mandated translation grammar (never invert):**
  1. Specular top rim STAYS white but visibly brighter than the fill (~.5–.6) — a highlight,
     never a gray stroke.
  2. The 1px hairline FLIPS to dark (black .08–.12).
  3. Bottom light-bleed is DROPPED in light (depth in light mode comes from shadow, not
     emission).
  4. Shadows lighter and tighter (~half the dark opacity, slightly smaller radius).
  5. Glows at ~1/3 alpha with larger blur radius-equivalents — ambience, not smears.
  6. Teal title halo + slider glow are DARK-ONLY (≤.10 or off in light); carved-track inner
     shadows .4 → ~.15.
  The founder tunes VALUES in `make run`; this grammar is not up for per-PR reinterpretation.
- **Accent-chroma compensation (sanctioned vividness knob):** the dropped `saturate(1.5)` boost
  made 8a's glows read *more vivid through* panels than beside them. The token-level, hack-free
  equivalent: ~4–6% accent chroma mixed into the panel fill tokens (or a very-low-alpha accent
  wash as a decoration stratum inside `.glassPanel`). Named here so PR 3 doesn't rediscover it
  ad hoc; founder by-eye decides whether it's needed.
- **Increased-contrast variants (mechanism verified):** the dynamic provider's
  `bestMatch(from: [.aqua, .darkAqua])` extends with the two
  `NSAppearanceNameAccessibilityHighContrast*` names; optional `lightHC:`/`darkHC:` parameters
  default to the base values so existing call sites compile unchanged. STRUCTURAL
  increase-contrast responses (thicker hairline, added border — Apple's own IC treatment adds
  borders) live in the `.glassPanel` modifier reading `@Environment(\.colorSchemeContrast)`,
  not in color tokens. Because macOS forces Reduce Transparency on under IC, the IC variants
  always composite over the opaque RT-fallback fills.
- **Typography:** `DesignSystem.Font.heroTitle` = `.largeTitle` + `.heavy` (Dynamic-Type-mapped;
  macOS default ~26pt vs the mock's 28px — accepted; a fixed `.system(size: 28)` would break
  Dynamic Type and is banned). Badge/axis type floors: informational badge text ≥ 10pt;
  sub-10px sizes only for a11y-hidden decorative axis labels.
- **Radii:** fixed tokens (panel 22 / lens 20 / rows 12 / badges 10–11, all `.continuous`,
  pills h/2). The concentric-corner API is skipped deliberately: these panels are inset
  mid-content and never meet a window corner (bands are full-bleed), so container-relative
  radii buy nothing (§3.5).
- **Accessibility inside the modifier, not call sites:** Reduce Transparency swaps translucent
  fills → opaque `Color.panel`-family tokens. Reduce Motion is consumed by the animated accents
  (§3.4), which are the only motion this sprint adds. Opaquing fills is the RT path ONLY — it is
  never the fix for a contrast failure (that's a token-value fix; see §7 R4).

**Enforcement (rig, §7 R1):** four semgrep tripwires over ALL of `Sources/AdaptiveSound`
(ad-hoc materials incl. `.background(.bar)`, frozen Liquid Glass APIs, hand-painted color
literals, per-view appearance branching), excepting ONLY the four governed definition files
(`DesignSystem.swift`, `DesignSystemGlass.swift`, `Color+Brand.swift`,
`SpectrumColorPalette.swift`) — never call sites. The §3.1 migrations/dispositions land BEFORE
the rules (PR 1a code, PR 1b governance) so the rules are green from day one. **Rule-2
governance (durable — the fool's N3 pre-mortem):** the rule's failure message routes to the
`DesignSystemGlass.swift` header (which outlives any sprint doc), and rule 2 is NEVER
suppressed — adopting real glass means EDITING THE RULE ITSELF in the same PR as the design
review that sanctions the under-content surface. Suppression = hack; rule edit + design review
= policy evolution.

### 3.3 Ambient glow field (content layer)

A `GlowField` background behind `NowPlayingTabView` content: three radial gradients (teal
top-left ~720×560 / lime bottom-right ~760×600 / blue mid-right ~420×380) over the D10 window
base. **Construction (no `.blur` at all):** each glow is an `Ellipse` filled with a 3-stop eased
`RadialGradient` (peak → ~35% of peak @ ~0.55 → clear @ 1) — a gradient already IS a smooth
falloff; authoring the falloff in the stops is visually equivalent to blurring a hard shape and
costs zero filter passes under a 20 Hz-invalidating subtree. Mounted via `.background { }` on the
tab content (not a layout-participating sibling — a ~760pt glow would inflate the tab's ideal
size), `.allowsHitTesting(false)` + `accessibilityHidden(true)`. Brand colors land first (PR 2);
**per D8 (founder 2026-07-17: IN scope), PR 7 then makes the glow colors album-art-sampled** —
dominant colors extracted from the current artwork (`NowPlayingController.currentArtwork`),
**clamped into token-defined chroma/alpha ranges** (the §3.1 pre-binding: R4 keeps auditing
bounded worst cases; a pathological cover can never blow the contrast budget), cached per
track (the `ArtworkThumbnailStore` pattern), falling back to the brand colors for missing art,
recoloring on track change as a DISCRETE restyle (crossfade gated on Reduce Motion — never a
continuous animation). Dark per spec; light per the §3.2 grammar (~1/3 alpha). Under Reduce
Transparency the field flattens to the plain window color. PR-2 eyeball checklist: gradient
banding on wide-gamut displays; `AppShell`'s `.clipped()` hard-cutting glows at the band seams
(mostly hidden under the hairlines — verify).

**Tertiary-text placement rule (PR-2 audit finding, 2026-07-17):** the R4 audit's first run
against the glow tokens failed `labelTertiary` on the teal core at spec alpha (3.98:1 dark) —
and the 8a mock itself never puts small text there (its top-left core hosts only the HERO,
large text at the 3:1 threshold). Rather than dilute the 8a alphas or waive the audit, the
constraint is encoded: **labelTertiary small text never sits inside the teal core** (post-PR-5
all tertiary lives in the inspector, right side); the audit models tertiary at lime/blue cores
at max alpha + everything else at the mid-stop attenuation, and models pairwise glow overlaps
at mid-stop (the three cores are geometrically disjoint — only faded tails overlap). Review
owns the placement rule; R4-GLOW-01/02/04 own the math.

### 3.4 Motion & state rules

- ENHANCED badge pulsing dot (1.6s cycle, opacity 1→0.4) and the active-queue-row 3-bar
  equalizer animate **only while playing** and **only when Reduce Motion is off** — same gating
  the spectrum already uses (dims to 0.4 on pause; keep that).
- **Pulse implementation (mandated pattern):** a conditional `phaseAnimator([1.0, 0.4])` with
  `.easeInOut(duration: 0.8)` per phase, mounted only while `isPlaying && !reduceMotion` — the
  `if` swap removes it → deterministic stop at full opacity, no zombie animation, immune to
  `@Observable` invalidation restarts. The `.animation(.repeatForever)`+`onAppear` idiom is
  BANNED (keeps animating after gating flips; freezes mid-phase) — PR-4 review checks for it.
- **3-bar row equalizer:** derive the three bars from the real `spectrumBars` low/mid/high bands
  (the data is already on the main thread 20×/s) rather than a fake sine loop — the difference
  between an instrument and a GIF. Reduce Motion / paused → static bars.
- **Micro-transitions (all Reduce-Motion-gated):** hero title/artist crossfade on track change
  (`.contentTransition(.opacity)`); ENHANCED badge appear/disappear crossfade when the path
  flips Pure↔Enhanced (never a pop); device-pill sample-rate `numericText` transition (D5);
  visible accent focus rings on panels (verified in PR-5's traversal check).
- No animated panel properties (no fill/shadow animation); transitions stay the existing
  `.easeInOut(0.2)` tab-level ones. Hovers per 8a (rows white 5%, pills 10–12%) via tokens; the
  lens gets a hover state (slight rim brighten + pointer + existing `.help`) for its
  double-click→Monitoring affordance. **A11y (replaces the earlier "acceptable because the tab
  picker exists" position — the fool rejected investing in a sighted-only affordance):** the
  20 Hz CANVAS stays `accessibilityHidden` (correct — it would spam VO), but the lens FRAME is
  exposed as one static labeled element ("Spectrum analyzer") carrying
  `.accessibilityAction(named: "Open Monitoring")` and keyboard activation — one element, no
  churn, the affordance reaches everyone.

### 3.5 Native-API footnotes (SDK-verified inventory, macOS 26.5 SDK, 2026-07-17)

The API research pass pulled Apple's doc JSON and cross-verified every signature against the
installed `MacOSX26.5.sdk` swiftinterfaces — these are SHIPPING names (several beta-era spellings
died; do not copy blog code unchecked). The swiftui-pro panel re-verified the list against the
SDK independently: no corrections. Recorded so any future Regime-A adoption starts verified:

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
  resolved against a `containerShape`. Skipped for our inset panels (§3.2 Radii).
- Accessibility (native glass): Reduce Transparency → frostier; Increase Contrast →
  black/white + border (and macOS force-enables RT under IC); Reduce Motion → damped effects —
  automatic for the MATERIAL, while app-triggered animations and custom overlays remain ours.
  macOS 26.1 added a user Clear/Tinted glass preference; macOS 27 (beta) adds a transparency
  slider — system materials track these, app-owned fills legitimately don't (content design).
- `Material` (e.g. `.ultraThinMaterial`) blurs **in-app** content only; HIG sanctions standard
  materials for content-layer structure. There is **no public backdrop-filter API** in SwiftUI
  (the 8a CSS `saturate(1.5)` boost is not reproducible; §3.2 names the sanctioned substitute).
- `NSGlassEffectView`/`NSGlassEffectContainerView` exist for AppKit (regular/clear only;
  `effectIsInteractive` is macOS 27); `NSVisualEffectView` = the standard-materials system
  (behind-window blending), NOT Liquid Glass — banned in `UI/**` (§3.2).

## 4. What already matches (don't rebuild)

`SpectrumColorPalette` (exact Teal→Lime + 0.82 vertical darken), spectrum pause-dim + Reduce
Motion handling, real FFT source (`AudioViewModel.spectrumBars` ~20 Hz), `AppShell` band
architecture, WCAG-audited dynamic label palette, `FormatBadgeView`, loudness meters, queue row
tint tokens, the 5-tab set, and the three §3.1-allowlisted Material overlays. The sprint
restyles; it does not re-derive any of these.

## 5. Target Now Playing layout (the one structural change — PR 5)

Current: `NowPlayingTabView` = 50/50 split (`LeftPanelView` scroll: spectrum → master gain →
info/meters/intensity/crossfeed | `RightPanelView`: queue).

Target (8a, transport-less per D3):

```
NowPlayingTabView                          // inside AppShell's bounded content region
 .background { GlowField() }               // Regime C, PR 2 — not a layout sibling
 VStack(spacing: 0)
 ├─ HeroBand                               // hugs intrinsic height; ≈154pt at DEFAULT type size
 │                                         // (DERIVED: Glass.lensHeight=122 token + padding —
 │                                         // 154 never appears in code; grows under Dynamic Type)
 │    ├─ VStack: heroTitle (28/800-equiv + dark-only teal halo), artist,
 │    │          badge row  [signal-path badge set · format · sample-rate]
 │    │          — the block CENTERED VERTICALLY against the lens (no lower-left void)
 │    └─ SpectrumAnalyzerView in .glassPanel(.lens)                    (D6)
 │         flex width min 400 → max ~560, height 122; dB grid, 0 dB label,
 │         20 Hz–20 kHz scale, peak-hold caps; beyond max-width, whitespace
 │         is legitimate hero negative space
 └─ HStack(spacing: 0)
      ├─ Queue (flex)                      // PlaylistView + 8a filter field (D7) + OWN scroll
      └─ InspectorColumn (fixed 260)                                    (D2)
           .glassPanel(.panel) on the COLUMN CONTAINER, its content in an
           inner ScrollView (rim/hairline must not scroll away)
           master gain · Reimagine intensity · decoder/bit-depth detail ·
           loudness meters · crossfeed
```

**Scrolling architecture (mandated):** NO outer ScrollView — an unbounded height proposal would
materialize every queue row (virtualization dead) and break `scrollTo`/jump-to-now-playing. The
HeroBand hugs intrinsic height; the queue keeps its internal `ScrollView`+`LazyVStack`; the
inspector scrolls its own content INSIDE the panel chrome. At the 880×640 minimum the content
region is 516pt → hero ~154 (default type) leaves ~362: the inspector (~400pt+ of content) is
EXPECTED to scroll near minimum height — that's the design, not a defect. PR-5 acceptance tests
880×640 exactly, **at default AND at the largest supported Dynamic Type size** — the §7.1
layout-arithmetic test derives hero height at both and asserts the queue keeps a minimum
visible-row count at 880×640 (the hero scales by design; the assertion is that scaling never
starves the queue).

**Geometry rules:** pad-inside-then-frame for the inspector (`.padding` before
`.frame(width: 260)` widens the column to 292 and silently steals queue width — the S9
lesson mutates with explicit frames: the symptom flips from clipping to theft). "Inspector top
aligns with queue header" is implemented as a shared top-padding token on both panes, never
cross-sibling alignment guides. The queue pane's current `.padding(16)` + `Color.asCard` fill +
leading hairline (NowPlayingTabView:17–24) do NOT carry over — the queue sits directly on the
glow field (rows carry their own tints); the inspector panel + hairline tokens replace the old
pane treatment.

**Hero badge row — signal-path state mapping (required before the widget retires):**
`NowPlayingWidget`/`SignalPathBadge` today surface Pure/Enhanced, the "(Pure unavailable)"
fallback, interrupted/device-disconnected, decoder (Apple/FFmpeg), bit depth, intensity %, and
crossfeed. The hero badge row maps ALL states: `PURE` badge (accent-less, monochrome) when
bit-perfect; `ENHANCED` + pulsing dot when the DSP path is active; `PURE UNAVAILABLE →
ENHANCED` fallback keeps the warning affordance (statusWarning tint); interrupted state shows
the footer's interrupted treatment at hero scale. Decoder + bit-depth move to a small
`InspectorColumn` detail line (the audiophile home for them); the footer's condensed signal slot
is untouched. Badge heights via `@ScaledMetric(relativeTo: .subheadline)` (fixed 22pt clips
under Dynamic Type); the hero band hugs intrinsic height — no `.dynamicTypeSize` clamp unless
the badge ROW alone needs one.

**Empty / first-launch state (designed, not endured):** placeholder title ("Nothing playing")
in `labelSecondary`, NO halo; badge row HIDDEN (not grayed) until a track loads; the lens ships
its frame + dB grid + axis labels with flat bars, dimmed — the instrument-at-rest is the
audiophile empty state; geometry identical to the loaded state so nothing reflows on first play
(mirror the footer's existing behavior). The existing empty-queue view restyles onto the glow
field in the same PR.

**Queue filter field (D7 — founder 2026-07-17: IN scope, PR 5):** the 8a filter field sits in
the queue header, **view-local** (filters the visible list; never mutates the queue or
playback), case/diacritic-insensitive on title+artist, Escape clears + returns focus to the
queue, adopts `TransportSpaceSuppressing` (typing a space must never toggle playback — the
S10.2 pattern), and does not steal the queue's `.defaultFocus`. Empty-result state: "No
matches" + the clear affordance. Jump-to-now-playing ignores an active filter (clears it
first) rather than silently failing.

**Focus & traversal (stated decision):** structural order hero → queue → inspector gives the VO
reading order; this REVERSES today's controls-before-queue tab order, and the queue's
`.defaultFocus` keeps first focus. Accepted — the queue is the tab's primary object. PR-5
re-verifies `.defaultFocus` resolution in the new hierarchy + visible focus treatment on all
inspector controls.

**Carved sliders — one primitive, two commit policies:** extract `CarvedSliderTrack` (visuals:
5pt inset track, 14pt knob, dark-only teal glow; drag → fraction stream + edit-phase callback,
shaped like `Slider(value:onEditingChanged:)`). Two thin consumers choose policy: the footer
scrubber stays DEFERRED-commit (local fraction, seek on release, tooltip/time labels stay in
`FooterScrubber`'s composition); gain/intensity are LIVE-commit (audible while dragging, step
0.01). **A11y parity is acceptance, not aspiration:** focusable with visible focus treatment,
←/→ ± step when focused, `.accessibilityAdjustableAction` + spoken `accessibilityValue` on all
three consumers — a keyboard user who can Tab to the gain slider but cannot change it is a PR
failure. (Native `Slider` restyling on macOS cannot produce the carved look — `.tint` only —
so the custom track is justified, and this parity clause is the price.)

`LeftPanelView`/`RightPanelView` dissolve into `HeroBand` + `InspectorColumn`; the
double-click-spectrum → Monitoring affordance moves onto the lens (hover per §3.4).

## 6. Chunk plan (6 PRs, each independently shippable + gated)

| PR | Deliverable | Key files | Acceptance (beyond the standard gate) |
|---|---|---|---|
| **1a. Kit + overlay role (product)** | **R0 `DesignTokenKit`** (token data + pure RT/IC resolver + `Tests/DesignTokenKitTests`: RES/TOK/ContrastAudit(existing surfaces)/SlotFit); single-source invariant (legacy palette values move into Kit; `DesignSystem.Color` re-exports); `.glassPanel(.overlay)` ONLY (per the staged-declaration rule §3.2) + the four §3.1 overlay migrations + the new `statusError` token + HC-variant provider extension | `Package.swift`, `Sources/DesignTokenKit/`, `Tests/DesignTokenKitTests/`, `DesignSystem.swift`, `DesignSystemGlass.swift` | **Zero visual change** — matrix A,B in a SINGLE app run + three forced-visible overlay cells (device unplug → error banner; add-to-queue from Library → toast; EQ device switch → recall banner) in A, B **and C**; plus a one-off same-machine before/after `screencapture` + ImageMagick `compare` diff pasted in the PR (pixel-identity as evidence, not trust — NOT a snapshot suite) |
| **1b. Governance (rig)** | The four R1 semgrep rules (exact regexes pinned in the PR; `.background(.bar` prefix match; `Color.clear` allowance) + Kit-purity guard + Dynamic-Type-clamp guard + 3 TEMP suppressions (2 × LibrarySidebar `.bar` → S10.8; NowPlayingBar shadow → PR 6) + `ChromeBar` `Color.white`→`onAccent` + matrix template | `.semgrep.yml`, `scripts/strict-gate.sh`, `ChromeBar.swift`, `docs/sprints/s10-7-visual-matrix.md` | Gate GREEN with a re-run dry-run count pinned in the PR body; zero visual change (onAccent IS white) |
| **2. Ambient glow + base re-tune (D10)** | `GlowField` (stop-authored gradients, no blur); dark-base re-tune app-wide per D10; light variants per §3.2 grammar | `NowPlayingTabView` (+ `GlowField.swift`), `DesignSystem.Color` | Founder eyeball both appearances **against the 8a mock**; RT flattens; band-seam clipping + banding checked; R4 composite audit re-run against the new base |
| **3. Analyzer lens (size-agnostic)** | Lens fill via `.glassPanel(.lens)` + **peak-hold caps**: pure `PeakHoldTracker` (hold ~600ms → decay), fed from the existing 20 Hz `tickSpectrum()` in `AudioViewModel`, published as `peakCaps` beside `spectrumBars`, drawn by ONE overlay view (not 88 extra diffed siblings) | `SpectrumAnalyzerView.swift`, `AudioViewModel+SpectrumTimer.swift`, `PeakHoldTracker.swift` + tests | Caps freeze on pause + no implicit animation under Reduce Motion; tracker cases green (R2); heights still sourced from `spectrumBars`; NO grid/scale yet (they need the D6 frame — PR 5) |
| **4. Hero** | `HeroBand`: heroTitle + dark-only halo, artist, full signal-path badge mapping (§5), pulsing dot via conditional `phaseAnimator`, `@ScaledMetric` badge heights, empty/first-launch state, title/badge micro-transitions | `NowPlayingInfoView.swift` → `HeroBand.swift` (widget card retires; decoder/bits relocation stubbed for PR 5) | All four signal-path states render (Pure/Enhanced/fallback/interrupted); pulse stops deterministically when gating flips; long-title truncation + `.help`; empty state per §5 |
| **5. Inspector column + lens placement (D6) + queue filter (D7)** | The §5 restructure: hero-right lens (400→560 flex ×122) + dB grid/0 dB/axis scale; queue-flex + fixed-260 inspector w/ own scroll; the §5 queue filter field; `CarvedSliderTrack` + gain/intensity consumers; decoder/bits detail line; meters restyle | `NowPlayingTabView`, `HeroBand`, `InspectorColumn.swift`, `PlaylistView.swift` (filter), `MasterGainSliderView`, `LoudnessMetersView`, `CarvedSliderTrack.swift` | 880×640 exact (default + max type): no truncation, queue virtualization intact (`scrollTo` works), inspector scrolls inside chrome; keyboard operability per §5 (arrows adjust, focus visible, VO adjustable); filter: space-suppression + Escape + jump-clears-filter verified; traversal decision verified |
| **7. Art-sampled glows (D8)** | Dominant-color extraction from current artwork → clamped into token chroma/alpha ranges (§3.3) → per-track glow recolor w/ RM-gated crossfade; per-track cache; brand-color fallback | `GlowField.swift`, small `ArtworkGlowSampler` (+ cache), `DesignTokenKit` clamp-range tokens | R4 re-runs against the CLAMP BOUNDS (not concrete albums) and stays green; matrix A,B,H + track-change transition cell; RM: recolor is a cut, not a crossfade; missing-art fallback cell |
| **6. Chrome + footer restyle** | Band SURFACES unchanged (`AppShell` byte-untouched: chrome keeps `window`, footer keeps its existing `panel` + hairlines — no slab, no elevation); device pill restyled via tokens + sample-rate readout w/ `numericText` (D5); tab selector per D9 (native); footer CONTROLS restyle w/ the non-text contrast rules (incl. retiring the `NowPlayingBar:303` shadow literal → token); `FooterScrubber` adopts `CarvedSliderTrack` HERE (not PR 5); subtract-interference audit | `ChromeBar.swift`, `NowPlayingBar.swift` | `ShellMetrics`/`Footer` metrics byte-identical; window-drag intact (L2); media-keys/transport regression-checked (scrubber re-plumb happens in the PR whose acceptance watches the footer); non-text 3:1 contrast (track/knob/meters/toggle) both appearances; matrix H required |
| — **S10.8 (own sprint):** Library/EQ/Monitoring/Settings token sweep on the proven tokens — surfaces/controls/type only. R1 gates on it (D11). | | | |

Order: 1a→1b→2→3→4→5→6→7, **strictly incremental (founder directive):** each PR is a
founder-verifiable milestone — build green → SME review (swiftui-pro + macos-design) →
strict-gate → **founder runs it, screenshots the PR's matrix cells, feeds them back for
vs-mock review → sign-off → merge**. PRs 2–4 are restyles inside the current split (they do
NOT wait for the restructure); PR 5 is the only layout change; PR 6 touches shared shell last,
once the token layer has been proven on lower-risk surfaces.

## 7. Test-rig evolution (qa-expert + the-fool — DECIDED)

The rig today (strict-gate: format/lint/semgrep/periphery/migrator+drop-path greps/build/test/
C++ gates; VerifyLibraryStore; `make run` = the only visual check) verifies none of what this
sprint changes. Panel verdicts (qa-expert, dry-run against the tree; the-fool's counters in
§7.4), with the structural prerequisite first. The founder's testing mode for this sprint:
**manual, incremental — the founder screenshots the required matrix cells at every milestone
and feeds them back for vs-mock review before sign-off** (the run-and-screenshot loop).

**R0 — `DesignTokenKit` extraction (NEW; prerequisite for R2/R4; lands in PR 1).** See §3.2.
Token DATA + the pure RT/IC resolver + (later) `PeakHoldTracker` and the animation-gate
predicate live in a library target with `Tests/DesignTokenKitTests` — headless, deterministic,
in `swift test` → strict-gate → CI forever. Zero visual change.

**R1 — token-scope tripwires: ACCEPT, revised + hardened (PR 1; semgrep, house style).**
Four `pattern-regex` rules over `Sources/AdaptiveSound`, excluding only the four definition
files (§3.2):
1. `ui-no-adhoc-material` — bans `.*Material`, `Material.`, `NSVisualEffectView`,
   `.background(.bar)`; message routes to `.glassPanel(_:)`.
2. `no-liquid-glass-api` — freezes `glassEffect*`, `GlassEffectContainer`,
   `NSGlassEffectView*`, `buttonStyle(.glass…)` — NO exceptions, incl. DesignSystem (any
   future use re-opens this doc).
3. `ui-no-color-literal` — bans `Color/NSColor(red:|white:|hue:|srgbRed:…)`, `#colorLiteral`,
   named/string colors outside the definition files.
4. `ui-no-appearance-branching` — bans `\.colorScheme` reads, `.preferredColorScheme(`,
   `NSApp.appearance =` (appearance is owned by the dynamic token layer — S9-T).
Dry-run inventory: see §3.1 (CORRECTED by the fool gate, grep-verified): 4 overlay migrations +
2 Library TEMP suppressions + per-site named-color dispositions (`onAccent` migration, new
`statusError` token, footer-shadow TEMP) + an explicit `Color.clear` allowance; the `.bar`
pattern is a PREFIX match (`\.background\(\s*\.bar\b` — the fourth site is
`.background(.bar, in: Capsule())`). PR 1b pins the exact final regexes and a re-run dry-run
count in its PR body. `docs/`/`research/` already semgrep-ignored (the 8a reference file's
`glassEffect` stays out of scope); no `#Preview` blocks exist, so no carve-out. Accepted
posture: these are drift nets, not security boundaries (same as the migrator grep) — evasion
routes exist (§7.4-1); review owns that seam.
Plus TWO strict-gate bash guards (presence assertions, migrator-grep idiom): (1) fixed-band
Dynamic-Type-clamp guard — `NowPlayingBar.swift` must keep `.dynamicTypeSize(` (a fixed 64pt
band overflows at accessibility sizes); ChromeBar joins the list in PR 6; (2) Kit-purity guard —
fail on `import SwiftUI|AppKit` under `Sources/DesignTokenKit/` (the Kit's zero-UI-imports
property IS its testability contract).

**R2 — pure-logic unit tests: ACCEPT (requires R0). House style: `@Suite` + ID'd `@Test`s,
derived expectations, never magic numbers.**
- `PeakHoldTracker` — time-FED (`update(bars:elapsed:)`, never wall-clock; the S10.6
  monotonic-while-playing lesson), config `(hold: 0.6s, decayPerSecond: r)`:
  PH-01 cap ≥ live bar (rising re-latches) · PH-02 holds latched value for exactly `hold`
  fed-seconds · PH-03 then decays linearly (derived from config) · PH-04 floors at
  max(live, 0) · PH-05 higher bar re-latches + restarts hold · PH-06 no feed → no decay
  (pause is structural) · PH-07 `reset()` on track change · PH-08 band-count reconfigure ·
  PH-09 hostile input (negative elapsed clamps; NaN/∞/out-of-range bars clamp).
- RT/IC resolver — RES-01 all roles × both appearances: RT off → translucent role token; RT
  on → alpha 1.0 opaque token · RES-02 IC=true implies the opaque result EVEN IF the RT flag
  is false (never depend on the OS coupling) · RES-03 IC hairline/border strength ≥ default
  (derived comparison) · RES-04 GlowField under RT resolves to the flat window token.
- Animation gate — PG-01..04: the 2×2 `(isPlaying, reduceMotion)` truth table; animate only
  `(true, false)`; pause-dim (1.0/0.4) derived from the same predicate.
- Token invariants — TOK-01 radii chain monotonic (window ≥ panel ≥ lens ≥ rows ≥ badges) ·
  TOK-02 translucent fill alphas ∈ (0,1) · TOK-03 every dynamic token has both appearance
  values.

**R3 — snapshot testing: REJECT for S10.7; adopt-later ONLY behind entry criteria.** The
Regime-B fills are deterministic, but: (1) the views read `@Environment(AudioViewModel.self)`
inside the non-importable executable target — a snapshot test cannot even construct them
without a UI-library extraction this sprint doesn't budget; (2) the panels are TEXT-heavy and
font rasterization drifts across machines/OS-runner images (CI = GitHub-hosted `macos-26`,
image bumps on GitHub's cadence → "regenerate and rubber-stamp" rot); (3) in-sprint it only
re-verifies what the founder's screenshot loop just verified; (4) new external dependency
(per-dependency justification bar). Entry criteria to revisit post-R1: fast-follow sprints
restyle surfaces the founder no longer eyeballs per-PR, AND the check is scoped to TEXT-FREE
decoration (`.glassPanel` over a fixed gray rect from Kit data — deterministic in fact), AND
references are recorded on the CI runner image. Re-evaluation is BOUND to S10.8's definition
of done (a trigger event, not an unanchored "later"). (Known-good recipe recorded for that
day: window-free `NSHostingView` + `layoutSubtreeIfNeeded` + `cacheDisplay` into a fixed-size
1x bitmap, explicit `NSAppearance(named:)` per appearance.)

**R4 — contrast audit: ACCEPT, upgraded to a PERMANENT unit test**
(`DesignTokenKitTests/ContrastAuditTests`; lands PR 1, extends PR 2/3/5/6). ~40 lines of pure
Swift: sRGB alpha-over compositing + WCAG relative luminance; thresholds derived (≥4.5:1 text
AA, ≥3:1 non-text per WCAG 1.4.11). Backdrop set per surface = worst-case ENUMERATION: window
alone; window ⊕ each glow at token max alpha; window ⊕ each PAIRWISE glow overlap (overlaps
composite lighter); then ⊕ the surface fill (blur falloff modeled conservatively as
max-alpha). Required pairs, each × {light, dark} × {default, IC-resolved}: (1) glow composite
directly × `label` (hero title sits straight on the glow — most exposed); (2) `lens` ×
`label`/`labelSecondary` (0 dB + axis text); (3) `panel` × `label`/`labelSecondary`/
`labelTertiary`; (4) `control` × `label` + the device-pill readout (PR 6); (5) `badge` fills ×
their text; (6) `rowNowPlaying`/`rowSelected` ⊕ **glow-field composite** × `label` (post-§5 the queue rows
sit on the glow field, not a panel — fool correction); (7) IC state: RT-opaque surfaces × all
labels + hairline-vs-surface ≥3:1 non-text; (8) **legacy pairs (D10's automated net —
architect):** `window`/`card`/`panel` × `label`/`labelSecondary`/`labelTertiary` — so the
app-wide re-base is proven non-regressive on the UNTOUCHED tabs by math, not by S10.8's
promise; (9) **the lens-label exposure (fool):** the lens's "0 dB"/axis labels sit over the
BARS, whose palette tops out at near-white lime `#C8F06A` at the right edge — the palette's
max-luminance stop joins the lens-label backdrop set; if any pair fails, the fix is a design
fix (relocate the label above the bar field or a token scrim), never an audit waiver. Scope
guard: audits the surfaces this sprint touches — it does not retro-gate shipped choices (found
in passing: `onAccent` white-on-teal computes ≈2.5:1 today — pre-existing, flagged to the
founder separately, not a gate). VoiceOver traversal is NOT R4 — it's manual (R6/PR 5).

**R5 — performance: REVISE — a documented manual Instruments recipe as matrix rows; REJECT
an in-app FPS probe and xctrace automation** (no public frame-drop API; a homegrown probe
measures main-thread congestion, not render throughput — false confidence; headless xctrace
parsing rots). When: after PR 3 (caps over the 20 Hz spectrum — the real risk), after PR 5
(restructure), and at the sprint-end break-it. Recipe (verbatim in the matrix template):
`make run` → play 96 kHz → Now Playing, dark → Instruments Core Animation FPS / Metal System
Trace → 60 s steady + 30 s resize/tab-flip while playing. Budget: zero SUSTAINED dropped
frames at the display's refresh; GPU frame time p95 < ~50% budget; one-frame blips on tab
switch acceptable. The observed number is recorded in the PR's matrix block.

**R6 — founder visual matrix: ACCEPT, concretized + bound to the screenshot loop.** The
TEMPLATE is committed once as `docs/sprints/s10-7-visual-matrix.md` (PR 1); each PR's FILLED
matrix is pasted into the PR description with the founder's screenshots attached — **the
founder screenshots each required cell at every milestone and feeds them back; the vs-mock
review of those screenshots happens before founder sign-off; merge requires the filled block
+ sign-off.** States: A dark/default · B light/default · C dark/RT · D light/RT · E dark/IC ·
F light/IC · G dark/RM-while-playing · H live-toggle (appearance AND RT flipped mid-playback
on the visible tab — catches cached-resolution bugs no static check can see). **A and B are
captured in a SINGLE app run without relaunch** (makes every PR an implicit H — a baked
`static let` color caught at capture time, not at PR 5). Required cells: PR 1a → A,B (NO
visual change) + the three forced-visible overlay cells in A,B,C (§6); PR 2 → A,B,C,D,H vs
the 8a mock; PR 3 → A,B,C,G + Instruments row; PR 4 → A,B,E,G + long-title cell; PR 5 →
A,B,C,E,**H** + 880×640-min cell (default + max type size) + inspector-scroll cell + the
written VO/keyboard traversal script + Instruments row; PR 6 → A,B,E,**H** + window-drag cell
+ system-surfaces cell (device menu + a context menu render true glass over our bands).
Sprint end: the full A–H grid + the §10 break-it list. (Template documents the Settings
toggles incl. IC force-enabling RT.) **Deferred-cell ledger (fool, §7.4-5):** a skipped cell
is recorded IN the committed matrix file with the house TEMP grammar (reason + expiry =
sprint end) — tracked debt, never a silent drop; the end-of-sprint full grid is the
enforcement backstop.

### 7.1 Additions beyond the seeds

- **SlotFitTests (headless, Kit):** widest legitimate readout strings vs slot tokens
  (`"88:88"` vs `Footer.timeLabelWidth`; `"-88.8 LUFS"`; `"176.4 kHz"` pill readout;
  `"+12.0 dB"` gain) measured via `NSFont.preferredFont(forTextStyle:)` — honestly documented
  as a gross-misfit net (the SwiftUI↔NSFont metric seam), catching exactly the S9
  LUFS-truncation class. Plus a PR-5 layout-arithmetic test: inspector 260 + insets + queue
  minimum ≤ 880 (turns §5's width prose into an asserted derivation), AND the vertical twin
  (fool): hero height derived from `Glass.lensHeight` + type-scaled title/badge metrics at
  default AND max supported Dynamic Type size, asserting the queue keeps a minimum visible-row
  count at 880×640.
- **Dead code on dissolution (LeftPanelView/RightPanelView/NowPlayingWidget):** already
  covered — Periphery runs in strict-gate on the hostile config; the PRs must delete, not
  orphan. No new rig.
- **Launch smoke:** consciously not automated beyond `make run`'s existing pgrep assertion;
  a GUI launch in hosted CI is a flake generator.
- **VO/keyboard traversal (PR 5): explicitly manual** — a written expected-traversal script
  in the matrix template (hero → lens → queue → inspector: gain → intensity → meters →
  crossfeed; footer reachable; Monitoring affordance's stated a11y position §3.4). No
  XCUITest (SwiftPM, no xcodeproj; osascript needs TCC and rots). Automation theater is
  worse than an honest manual step.

### 7.2 Per-PR acceptance flow

Every PR: `make strict-gate` locally + identical hosted CI — which after PR 1 includes the
four R1 rules (also in fast `make lint`), the clamp guard, and all Kit tests via `swift test`.
No new Makefile targets or CI steps — nothing to forget to run. On top, per PR:

| PR | Automated (new, in-gate) | Founder-manual (screenshots → review → sign-off in PR body) |
|---|---|---|
| 1a | RES/TOK/ContrastAudit/fit tests; single-source invariant | A,B single-run — no visual change + 3 forced-visible overlay cells (A,B,C) + pixel-diff |
| 1b | R1 rules green (dry-run count pinned); purity + clamp guards | A,B — no visual change |
| 2 | R4 glow⊕window composites (incl. pairwise overlaps) | A,B,C,D,H vs mock |
| 3 | PH-01..09; PG-01..04; R4 lens pairs | A,B,C,G + Instruments |
| 4 | R4 hero/badge pairs; badge/truncation fit cases | A,B,E,G + long-title |
| 5 | Layout-arithmetic; inspector fit tests | A,B,C,E + min-window + scroll + VO script + Instruments |
| 6 | Pill fit test; clamp guard extends to ChromeBar; metrics byte-identical | A,B,E + window-drag + system-surfaces |

End of sprint: full A–H on the finished tab; qa+fool break-it round (§10); rig retro (which
rules fired / false-positived; TEMP suppressions re-dated or resolved).

**Explicitly founder-owned forever (never claimed by automation):** whether it looks right
(all matrix cells, via the screenshot loop), perceived glassiness of Regime-B fills (the §8
escalation trigger), Instruments numbers, VO/keyboard feel, Pure-mode/audio unaffectedness by
ear.

### 7.3 CI note

CI is GitHub-hosted `macos-26` (strict-ci.yml). Runner-image cadence is GitHub's — a
standing argument against pixel-reference checks (R3) and for token-math checks (R4).

### 7.4 Standing attack brief for the-fool (the rig's own weakest points)

1. Regex tripwires have escape routes (helper returning `some ShapeStyle`, laundered `let s:
   Material`, asset-catalog colors, future Apple material tokens) — drift net + review is the
   accepted posture; enumerate holes so review knows them. **The most probable evasion is
   LEGAL-token recomposition** (fool): a fake-glass surface built from
   `DesignSystem.Color.panel.opacity(…)` + `.blur()` + `.shadow()` uses zero banned tokens —
   only review catches "you rebuilt `.glassPanel` by hand."
2. The R4 composite model is a model (pairwise max-alpha, no blur falloff shape, no triple
   overlap, sRGB-vs-P3) — probe whether matrix cells C–F would catch what the math misses.
3. Resolver-to-modifier wiring is untested headlessly — a `.glassPanel` that ignores the env
   flags passes every unit test; matrix cells C/D/E/H are the only net — is a subtly-still-
   translucent RT fallback actually SEEN?
4. Fit tests ride the font-metric seam — the safety margin can mask a real 1–2 pt clip.
5. The heaviest risks have only manual nets, and manual nets are skippable (branch protection
   can't parse a pasted matrix; post-sprint, no pixel net exists at all — pressure-test the R3
   entry criteria).

## 8. Risks

| Risk | Mitigation |
|---|---|
| 8a look drifts from what fills can express (founder judges it "not glassy enough") | D10 deep base + glow field land FIRST (PR 2 = earliest by-eye vs the mock); §3.2 accent-chroma knob is the sanctioned vividness lever; escalation is a REAL under-content surface (§2 overlay-footer, post-R1), never fake backdrop stacks. **Stopping rule (fool N1 — bounds the tuning loop):** PR-2 by-eye gets TWO tuning rounds; then the founder makes a binary call — accept the fills look, or pre-commit the post-R1 real-glass escalation — and token values FREEZE for the rest of the sprint except where R4 fails |
| D10 interim state: PR 2 re-bases every tab's dark window while Library/EQ/Monitoring/Settings keep `#1E1E1E`-era tints until S10.8 (fool N2: "the app looks worse overall mid-sprint") | The honest interim story, stated up front: dark-mode text contrast on untouched tabs mathematically IMPROVES (white-on-darker; R4's legacy pairs prove it), cohesion intentionally degrades until S10.8, and R1 blocks on S10.8 (D11) so the interim never ships. PR 2 includes a 30-min base-compat micro-pass re-checking the four tabs' dark `card`/`panel`/`hairline` against the new base. S10.8 scope stays OUT of S10.7 reviews — pulling it forward mid-sprint is the recorded failure mode |
| Legibility on translucent fills (light mode especially) | §3.2 light grammar mandated; R4 composite audit incl. non-text 3:1; IC forced-RT state verified per PR |
| PR-5 restructure regresses keyboard/VO, queue virtualization, or the S9 truncation fixes | §5 mandates the scrolling architecture + keyboard-parity acceptance; 880×640-exact check; swiftui-pro review on the restructure |
| Custom slider primitive loses native-Slider a11y | §5 parity clause IS the acceptance; deferred/live commit split keeps scrubber semantics intact |
| Chrome/footer restyle disturbs L2 window-drag or `.clipped()` shadows at band seams | D4 keeps band structure quiet; shadows inside content region via tokens; scrubber re-plumb moved to PR 6 where footer acceptance lives |
| Base re-tune (D10) shifts every tab mid-sprint | Deliberate: one base per app; S10.8 sweeps the tabs onto it; R4 re-runs against the new base in PR 2 |
| D8 sampling: a pathological cover (near-black art, neon art, low-chroma art) produces ugly or illegible glows | Clamp-range tokens bound chroma/alpha/luminance (§3.3) — R4 audits the BOUNDS, so contrast can't break by construction; aesthetics verified by the founder's PR-7 screenshot cells incl. a worst-case-album set; brand-color fallback for missing/failed extraction |
| Scope creep into other tabs ("just one more surface") | D1: layouts untouched; S10.8 owns the sweep; any layout redesign is a post-R1 wave |

## 9. Decisions — RESOLVED (founder, 2026-07-17)

| # | Question | Decision |
|---|---|---|
| **D5** | Device pill sample-rate readout? | **YES** (per recommendation) — PR 6, `numericText` transition. |
| **D6** | Analyzer placement? | **8a hero-right lens** (per recommendation) — flex 400→~560 ×122; grid/scale follow the frame in PR 5. |
| **D7** | 8a's queue filter field? | **IN SCOPE** (founder overrode the defer recommendation) — PR 5, view-local, spec in §5. |
| **D8** | Glow colors? | **Album-art-sampled IN SCOPE** (founder overrode the defer recommendation) — brand colors PR 2, sampling PR 7 with clamp-range tokens (§3.3); the §3.1 pre-binding + R4 clamp audit were designed for exactly this. |
| **D9** | Tab selector? | **Native segmented control** (per recommendation, both SMEs firm) — revisit only if the PR-6 screenshots reject the neutral look. |
| **D10** | Dark-base re-tune app-wide? | **YES** (per recommendation) — PR 2, with the interim story + base-compat micro-pass (§8) and the R4 legacy-pair audit as the net. |
| **D11** | R1 gate | **S10.7 + S10.8** (locked earlier — "nothing elementary ships"). |

## 10. Definition of done

All six PRs merged with green gates; founder visual matrix passed per PR via the screenshot
loop (PR 2/3 include the vs-mock check); qa-expert + the-fool break-it round on the finished
tab (focus: appearance
switching mid-play, Reduce-*/IC toggles at runtime, window at min size 880×640, empty queue /
no-track / first-launch, long titles/many badges under Dynamic Type, signal-path state flips
Pure↔Enhanced↔fallback↔interrupted mid-play, tab-switch churn while playing, queue
virtualization + jump-to-now-playing after the restructure); rig additions from §7 landed or
explicitly rejected in this doc; sprint-plan §Status updated; S10.8 sweep sprint defined from
the proven tokens; retro captured.
