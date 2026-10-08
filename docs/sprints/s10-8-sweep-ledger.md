# S10.8 part 2 — glass sweep ledger

Per-sprint record for [s10-8-glass-sweep-plan.md](s10-8-glass-sweep-plan.md): each sprint's
plan check, PR record, filled acceptance matrix, founder findings with their triage tag, and the
mini-retro that adjusts the next sprint (plan §D). The plan carries the *why*; this carries the
evidence.

## Sprint A — foundation

### Plan check (2026-10-06)

Started by a swiftui-pro agent (stopped by the coordinator at the founder's request once its
probes had answered the open questions) and completed by the coordinator from the agent's
scratchpad evidence plus a code read. Corrections to the plan's Sprint A:

1. **A4 is proven feasible as designed.** A throwaway debug renderer rendered the *real*
   `ContentView` (Now Playing and Library › Songs) from fixture models, offscreen, in dark,
   light and dark + Increase Contrast, before the single-instance guard and without opening the
   library store. It produced the first-ever light render of Now Playing. No fallback needed.
2. **A1 visual change is negligible.** The probe's before/after crops (analyzer lens, hero
   chips, filter pill, Songs rows) show only the halos disappearing. Badges (chips, pills, the
   device pill) get **no** drop shadow — they never had a designed one; what looked like their
   shadow was the text halo.
3. **A2 needs two tokens, not one.** Moving teal text to the existing `accentText` would
   brighten approved dark text (#29B6A4 → #6FE0D0). So: `accentFill` (tints, fills, glyph fill
   layers) and `accentForeground` (text, glyphs), each with **dark = today's #29B6A4** and only
   the light value changed. Inventory: 8 `.tint` sites (6 of them the `.borderedProminent`
   buttons), 13 teal-text sites, 2 two-layer glyphs; ~14 decorative strokes and fills keep
   `accent`. The primary pill reuses the shipped teal gloss + `onAccent` text (already audited
   as R4-TAB-01) — dark text on the deeper teal would fail AA in light.
4. **A3 is smaller than planned.** The queue already scrolls its cursor into view; only Songs,
   playlist detail and the sidebar need scroll-into-view. The focus ring uses `accentText`'s
   values (≥ 3:1 against every row fill, both appearances).
5. **Order:** all four PRs are independent → built **in parallel** (founder request), each in
   its own worktree, merged by the coordinator, then one `make strict-gate` on the merge.

### PR record

Built in parallel by four swiftui-pro agents, each in its own worktree; replayed onto
`sprint/s10-8-a-foundation` by the coordinator (one palette conflict — both sides' new tokens
kept). Combined: `swift build` + 224 tests + format + lint + semgrep green before the full gate.

| PR | Commits | Scope | Tests |
|---|---|---|---|
| A1 | `d73b40c` | Card shadow cast by the background fill shape only; `SurfaceRole.castsShadow` (panel, lens true; badge, overlay false). No GlassDecor value changed | RES-06 |
| A3 | `295f693` `a46f1f8` `dffd1a8` | `focusRing` token (= `accentText` values); `keyboardCursorRing` on Songs, queue, playlist detail and the rail; scroll-into-view on Songs, playlist detail and the rail (the queue already had it) | R4-FOCUS-01, R4-FOCUS-02 (queue rows over the dark glow) |
| A2 | `4ce0d9a` `fd2dd24` `d01ed17` `4b2e4f5` | `accentFill` / `accentForeground` (dark = today's teal); text, glyph and switch-tint sites migrated; `PillButtonStyle` (shipped teal gloss + dark text) replaces the 6 `.borderedProminent` buttons; semgrep `ui-no-bordered-prominent`, `ui-no-accent-as-text` | R4-TINT-01…03 |
| A4 | `bed2bb4` `e60eae5` `2f1dd91` | Debug picture-sheet renderer (`-ASRenderSheets`, fake audio engine, fixture models, isolated settings suite) + `make sheets`: 5 tabs × 6 appearances × 2 sizes = 60 sheets | renderer smoke run (60/60, live app untouched — checked with `lsof`) |

### Deviations from the plan (accepted by the coordinator, with evidence)

1. **No app-wide root tint (A2).** An offscreen render showed an inherited `.tint` recolours
   every plain and bordered button in dark (white text → teal text on a teal wash) and turns
   default-action buttons white-on-teal (~2.5:1) — a dark-look change the founder rule forbids
   and the exact failure A2 removes. The menu-bar menu is native; a tint does nothing there.
   *Corrected in the review round:* A2 had instead tinted the one untinted switch ("Keep
   playback on this device") teal — but that switch drew in the system accent (blue), so it was
   itself a dark-look change. Reverted; Sprint F restyles Settings.
2. **Increase Contrast sheets use a private AppKit selector (A4).** `NSAppearance(named:)`
   silently maps the high-contrast names to plain appearances; only the private
   `_darkAquaAppearanceWithAccessibility:` renders true Increase Contrast. Debug-only, never in
   the release binary, checked at runtime and failing loudly rather than faking.
3. **EQ persistence takes an injected settings store (A4)**, defaulting to the app's standard
   store with unchanged keys — so the renderer cannot write the founder's EQ settings.

### Found by the first picture sheets (to triage at the founder check)

- Now Playing, light, 880×640: the "Filter queue" placeholder is cut off; the Crossfeed switch
  is barely visible (light — Sprint B).
- Songs, light + Increase Contrast, 880×640: the count subtitle wraps onto three lines; row
  highlights touch the card's right edge.
- The teal Play pill is ~6pt taller than the system Shuffle button beside it (Shuffle is
  restyled in Sprint E).
- The keyboard ring shows as soon as the rail and the queue auto-focus, and after a mouse click.

### Gate and reviews

- **Strict gate, first run:** failed before any code check — swiftlint crashed (SIGILL) walking
  the agents' worktrees under `.claude/worktrees/` (full repo copies with their own `.build/`).
  Fixed at the root: `.claude/` excluded in `.swiftlint.yml` and `.swiftformat` (`3f30e7e`),
  merged worktrees removed. **Second run: exit 0.**
- **code-reviewer:** no blocker; MAJOR = the Settings switch tint above; MINORs = ring and keys
  could act on different rows, the ring showed on auto-focus and clicks, semgrep gaps (the
  Monitoring "BEFORE" tag reads `accent` through a variable — deferred to Sprint G), badge
  shadows also dropped under Reduce Transparency / Increase Contrast (judged from the sheets).
- **swiftui-pro:** no blocker; MAJOR = the ring should mean *keyboard* focus (macOS convention);
  MAJOR = the pill taller than its neighbours (primary actions stand out by fill, not height);
  MINORs = capsule focus shape, drop-target outlines and one play disc still on bare `accent`,
  a stale doc, the debug seed's anchor.

### Review fix round (swiftui-pro, 10 commits `816906c`…`1612820`; 236 tests)

| # | Fix |
|---|---|
| prep | `PlaylistItemList` moved to its own file (PlaylistView.swift 488 → 216 lines) |
| 1 | `KeyboardFocusVisibility`: one app-wide input-mode tracker; the ring draws only after Tab / arrow / Home / End / Page keys (or always with Full Keyboard Access), never on open or after a click; ⌘-arrows (track skip) don't count |
| 2 | `ListKeyboardCursor` in LibraryBrowseKit (11 tests): ring, arrows, Return and Delete resolve one row; a first arrow press selects the ring row; Return / Delete act only on a selected or ringed row; lists with no cursor-able row aren't focus stops |
| 3 | Settings switch untinted again (above) |
| 4 | Pill height from `controlSize`: 24pt regular (measured = system bordered), 30pt large; capsule focus shape |
| 5–6 | Drop-target outlines and the Recently Played disc on `accentFill`; R4-TINT-04 (dark-on-teal glyph ≥ 3:1) |
| 7–9 | Doc fix; debug seed sets the anchor; `ui-no-bordered-prominent` widened to `.glassProminent` and the style initialisers |

**Behaviour changes to put in front of the founder:** with the keyboard ring on the queue's
playing row, Delete removes the playing track (the "one row" rule); every pill is now 24pt
(was 30).

**Plan amendment:** §H's Sprint G check "Space works pills and switches" is reworded — Space is
the app-wide play / pause key by design (it is matched before a focused button); Return
activates a focused pill.

### Break-it pass (qa-expert + the-fool, read-only, 2026-10-07)

**Decisive fact:** Full Keyboard Access is **on** on the founder's Mac (`AppleKeyboardUIMode` = 2,
verified). With it, the review round's "ring only for keyboard" and "Delete acts on the ring row"
combined into a data-loss bug: one ⌫ in the queue (which auto-focuses) removed the playing track,
and in playlist detail removed entry 1 — on main, Delete required a selection.

**R1 blockers → fix round 2:**

| # | Finding (reviewer) | Fix |
|---|---|---|
| 1 | ⌫ removes an unselected row — the playing track, or a user playlist's first entry; repeated ⌫ at the queue's end reaches the playing row (both) | Delete requires a real selection; an unanchored ⌫ only claims the row; after deleting the last row the cursor moves to the new last row |
| 2 | Full Keyboard Access forced the ring on permanently (the-fool) | FKA no longer forces the ring; Tab / arrows still switch to keyboard mode |
| 3 | First ↓ in the queue appears to do nothing (stays on the playing row) (the-fool) | Steps from the playing row |
| 4 | Monitoring "BEFORE" tag is teal text at 2.5:1 in light — reached `Text` through a parameter, so semgrep missed it (QA) | `accentForeground` |
| 5 | Songs: ⌘-click to deselect, then Return plays the deselected row (QA) | Anchored only while it is selected |
| 6 | Sheets lie: Increase Contrast without Reduce Transparency (impossible on macOS), stale PNGs never cleared, display-profile PNGs, a 0-sheet run exits 0 (both) | IC implies RT; per-commit output dir; sRGB; usage error |

**Triaged to later sprints (not Sprint A blockers):**

- **Sprint D (R1 blocker there):** the Songs count subtitle wraps onto three lines at the
  880×640 minimum window, in dark too — pre-existing, pixel-identical before Sprint A.
- **Sprint E:** the queue cursor is a *position*, not a track — drag-reorder or a removal above it
  moves the cursor onto a different track (pre-existing); Songs keeps one merged anchor while E1's
  ⇧-arrow needs the anchor and the moving row separate (extend `ListKeyboardCursor`, don't fork).
- **Sprint F (R1 blocker there):** "Keep playback on this device" is system blue on an app-drawn
  card; the Monitoring AFTER tag (app blue, 3.7:1 in light) and the BEFORE swatch.
- **Sprint G:** Space on a focused button or switch under Full Keyboard Access toggles playback
  (the menu's Space key is matched first — pre-existing); the ring stays drawn when the window is
  inactive.
- **Rule hardening (next sprint that touches `.semgrep.yml`):** the accent-as-text rule misses
  `foregroundColor`, `Color.accentColor`, values passed through a variable, and multi-line calls;
  flip it to an allow-list (bare `accent` only inside `stroke` / `strokeBorder` / `fill` /
  `background`). With no root tint, every system control in Sprints D–G needs its own tint —
  added to the plan's §F rules.

**Renderer blind spots — matrix cells pre-marked "live-only":** system controls draw in the
inactive-window state (switch tints and segmented selections can't be judged from sheets);
Materials (banners, toasts); real album art (and so the art-sampled glow); the titlebar strip;
large text; window sizes other than 1000×720 and 880×640; any screen not yet in the fixture
(Albums, Artists, Genres, detail pages, playlists — fixture routes are part of Sprints D and E).

**Tried to break, held:** A1's dark look (shadow pixels match the probe; the lens changes by at
most 4 levels — only the halos); both teal tokens' dark values equal today's teal; Sprint A's
teal text measures 6.0–8.6:1 in light; the keyboard monitor ignores ⌘-shortcuts, modifiers,
typing, Space, Return and Esc; all 6 pill swaps kept their disabled bindings, labels and
shortcuts; the renderer can't be reached by `make run` and never touches the founder's store,
settings or audio; the rail stands down during drill-downs and renames.

**Founder check additions (≈ 90 seconds), because nothing in Sprint A's original check exercised
what Sprint A changed:** open an album and look at Play; open a playlist and look at Play beside
the other buttons; launch, and without clicking press ↓ once in the queue (it moves); press ⌫
before selecting anything (nothing happens).

### Founder check (2026-10-07, dark + a light glance)

| Step | Founder found | Outcome |
|---|---|---|
| Now Playing look | Unchanged in dark | ✅ accepted |
| Light mode | "OK for an undesigned state" | ✅ accepted — designed in Sprint B |
| Album page Play | First click did nothing; on retry it played (log: `playNow: 2 track(s)`) | ✅ works — the first click most likely only activated the window |
| No Shuffle beside Play on the album page | — | Not a bug: the coordinator's check script was wrong (album pages have Play + More; Shuffle is on artist / genre pages) |
| "‹ Library" from an album returns to the top of the grid, not where the founder was | — | **New R1 Must → Sprint D** (the Albums grid keeps its scroll position) |
| Playlist page "looks different" | — | Expected: playlist pages get their glass card in Sprint D and header in Sprint E |
| Queue: click a song, Backspace → not removed | **R1 blocker** | **Fixed** (`e6310dd`, `ebbdb59`) — confirmed by the founder |

**The Backspace bug — root cause.** `.onKeyPress(.delete)` never fires on macOS: Backspace arrives
as U+007F while `KeyEquivalent.delete` is U+0008. The handler had been dead in both the queue and
playlist detail since before Sprint A; Sprint A's check exposed it. Both lists now use
`.onDeleteCommand` (⌫, ⌦ and Edit ▸ Delete), keeping the Sprint A rule (only a selected row is
removed); semgrep `swift-no-keypress-delete` keeps it out. Verified on the running app with real
mouse and key events (queue: `removeTrack:` logged; playlist detail: entry removed; Songs and
the rail: ↓ moves).

**How it was found without more founder time.** The coordinator drove the real app with macOS
accessibility automation and a direct-binary launch that captures the `[UX]` log. One trap,
recorded so it is not repeated: System Events `click at` performs an element's *accessibility
action*, not a mouse click — it produced a false "the device menu holds focus" diagnosis until
the fix agent switched to real mouse and key events.

**Side effect, disclosed to the founder:** testing a playlist row replaced the founder's queue
(by design); the agent restored it as it was at launch, deleted only throwaway test tracks, and
a few test songs played briefly.

### Mini-retro — Sprint A

1. **Parallel worktrees paid off; merging cost little.** Four PRs built at once; one palette
   conflict. But the worktrees crashed swiftlint until `.claude/` was excluded — any future
   parallel sprint starts with that exclusion in place (done).
2. **Break-it found what review missed — twice.** Reviews passed a Delete rule that, with Full
   Keyboard Access on (the founder's real setup), deleted the playing track; the founder check
   then found a Delete handler that had never worked. **Change for Sprint B on:** every
   keyboard / focus change is tested live with Full Keyboard Access on, using the automation
   harness, before the founder sees it.
3. **The check script must exercise what the sprint changed.** The original one did not (the
   devil's advocate caught it); the founder's 10 minutes found a pre-existing bug. Keep writing
   checks from the sprint's diff, not from the plan's wording.
4. **Picture sheets earned their keep** (60 → 70 sheets, ring and empty variants) but cannot
   show live interaction, real art, or system-control tint — those stay founder-only.
5. **Next sprint's plan check** reads this retro, adds the live FKA keyboard pass to Sprint B's
   loop, and starts Sprint B with the light options render (B1).

**Late founder finding (same check):** in Songs, multi-select by keyboard (Shift + ↑/↓, ⌘A,
type-to-find) doesn't exist; Shift + click and ⌘ + click work, and right-click → Add to Queue /
Play Next adds the selection. **Founder decision: keep the keyboard set in Sprint E** (E1), built
once for Songs and every detail page. Also noted: the selected-row tint is very faint (≈ 1.2:1
in dark), which makes a multi-selection hard to see — a Sprint B light-design item that also
covers dark.

## Sprint B — light mode

### Plan check and B1 (2026-10-07, ui-designer)

The plan check corrected Sprint B before work started (the full note and the B1 prototype stayed
in the session scratchpad): selection visibility needs a companion text rule; the headphones
hint is an R1 blocker in BOTH appearances; R4-SPEC-01's idle dim cannot pass in either mode
(audit the playing state, exempt the dim and caps as decorative); the shared teal fill must be
fixed with the knob; a light glow needs a pastel clamp for art-sampled colour and must keep
`InspectorCardGlow` dark-only; "Filter queue" clipping at 880×640 is dark too (→ D2); the
renderer was non-deterministic on Songs. It split B2 into **B2a** (shared fixes, started at once)
and **B2b** (the chosen backdrop). B1 rendered three backdrops: A no glow, B pale glow, C tinted
base.

Commit hashes in B2a / B2b / B3 below are the agents' worktree hashes; the sprint branch carries
the same commits replayed by cherry-pick (same subjects).

### B2a — the shared light fixes (2026-10-07)

Built by a swiftui-pro agent in its own worktree while the founder picks the backdrop (B1),
from the designer's plan check (the values) and B1 prototype (the evidence). Everything here
is the same for options A, B and C; the window, the background glow, `InspectorCardGlow`,
`SampledGlow` and RES-04 are B2b's.

| Commit | Scope | Tests |
|---|---|---|
| `43a146d` | The Songs column-header flake: root cause and fix (below) | SongColumnConfigTests |
| `16260d1` | Sheets render at a fixed 2x in Display P3 → sRGB, not the main screen's | debug only |
| `6080bb0` | CARD-SEP-01: light card 86%, lens 80%; light shadow 11% r8 y3 + a 1pt contact shadow | CARD-SEP-01/02 |
| `b9e190e` | Analyzer ramp → Kit `SpectrumRamp` light/dark pair; light caps 85% | R4-SPEC-01/02 |
| `af63182` | Light knob ring (black 45%); `meterFillTrail` (light = `accentDeep`) for sliders, meters, scrubber | R4-SLIDER-01…04 |
| `8cd9b80` | Light `rowSelected` = `accentDeep` 24%; the selected-row text rule, one home | R4-SEL-01…03, TOK-04 |
| `af52039` | Headphones block, light: `GlassSwitchStyle` (F2 reuses it), `disabledDim` | sheets |

**Measured on the light sheets** (1000×720, the composited pixels — not token math):

| Pair | Before | After |
|---|---|---|
| Card vs window (NP inspector, Songs, rail) | 1.055 (#F3F3F3) | 1.093 (#F7F7F7); RT/IC 1.151 |
| Lens vs window | 1.055 | 1.074 |
| Analyzer bar tops / bottoms (playing) | 1.35–3.09 / 1.62–4.11 | 3.53–4.74 / 4.12–6.11 |
| Analyzer peak caps | 1.22–1.88 | 3.42–4.31 |
| Fill value end vs card / groove body | 1.73 / 1.22 | 4.01 / 3.19 |
| Footer fill end vs window / groove | 1.64 / 1.31 | 3.67 / 2.93 (pinned, R4-SLIDER-03) |
| Knob edge vs card | 1.11 (white knob) | ring 3.96 |
| Selection vs card | 1.10 | 1.33 |
| Selected row: title / secondary / tertiary | 15.20 / 5.85 / 4.53 | 12.79 / 5.49 / 5.49 (promoted) |
| Rail's active label on the selection | 7.40 | 6.15 |
| Headphones hint / heading | 1.95 / 2.14 | 4.69 / 6.05 (RT/IC hint 4.73) |

Dark: every B2a commit above leaves the 35 dark sheets (dark, darkIC, darkRT, both sizes, ring,
ring-rail, empty) pixel-identical — all four channels compared.

**Decorative exemptions** (R4-SPEC-01, recorded in the test; the bar field is hidden from
accessibility): the paused 40% dim (light ramp 1.53–1.74:1, even black only 2.81:1; dark
1.86–3.19:1) and the peak caps (dark keeps 50%: 2.24:1 at the darkest stop).

**Known issues, pinned with `withKnownIssue` (they flip when fixed):** R4-SLIDER-03 — the fill on
the footer groove over the light window, 2.94:1 (the time text beside it carries the position),
→ B3 (**resolved** there, 3.15:1). R4-SEL-03 — dark tertiary on a selected row, 4.46:1
(pre-existing) → **resolved**: the founder chose "fix both" (2026-10-07), so dark tertiary on a selected row promotes to secondary like
light (the test now asserts AA outright; the dark selection tint itself is unchanged).

**Deviations (accepted by the agent, with evidence):**

1. **The renderer flake was a real app bug.** `SongColumnConfig` is `RawRepresentable` and
   `Equatable` with no `==`, so Swift's witness was the standard library's RawRepresentable `==`,
   comparing JSON whose key order varies from one encode to the next: `isCustomized` flipped at
   random (7 of 16 base Library renders; the live app too). Fixed by a canonical (sorted-key)
   string; the type moved into LibraryBrowseKit for a headless test. A hand-written `==` was
   dropped: SwiftFormat's `redundantEquatable` deletes it as "synthesized-equivalent".
2. **A second sheet non-determinism.** The renderer took density and colour profile from the
   main screen; with a 1x external display as main it wrote 1000×720 sheets mid-sprint. Fixed
   (≤ 2 levels on ~250 px against the old Retina output). Dark proofs after that compare against
   the base plus only this and the column fix (deterministic: 70/70 twice). What it cannot pin:
   text and AppKit controls rasterize for the offscreen window's screen — the main one (a 1x
   main screen changes every glyph, even in the 2x bitmap; in clamshell mode there is no Retina
   screen to borrow). The renderer now prints a WARNING then; diff only sheets rendered with the
   same main-screen scale. Residual, rare: the native "Filter Songs" placeholder moved 1px in 2 of
   ~23 full renders (one at a display change), and in 0 of 22 focused reruns.
3. **Caps keep a view opacity** (`.spectrumCapOpacity()`): baking the alpha into the gradient's
   colours moved the dark caps by up to 4 levels (~1,400 px). The B1 prototype's "dark 27/27
   identical" was likely the same diff-tool trap the agent hit first: PIL's `getbbox()` on an
   RGBA difference reads the alpha channel only.
4. **The light groove stays 10%** (the prototype's 12% lowers fill-vs-groove: card 3.21 → 3.06,
   footer 2.94 → 2.81). The knob gets the ring only, per scope (no prototype knob shadow).
5. **The switch hairline sits on the switch's own frame**, which is the native 54×24 track; the
   prototype's 1pt horizontal inset is gone. The dark "ticks" at its ends in zoomed crops are
   antialiasing that any 1pt capsule stroke shows.

**Found, routed:**

- B3: the white format-badge chips nearly vanish on the denser light card (1.07:1, was 1.11 —
  text-led, not an AA miss); the paused footer scrubber (`accent` 50%) on the light window.
  **Both resolved in B3.**
- Wherever Reimagine is restyled: its Intensity block dims whole to 50% under Pure, so the
  "Pure (bypassed)" status reads ~2:1 in both appearances — the headphones-hint class.
- `DesignSystemGlass.swift` is at 496 of its 500 lines → **resolved at the merge**: B2a + B2b
  together reached 507, so the control visuals moved to `DesignSystemGlassControls.swift`.
- Tooling: in agent worktrees (under `.claude/worktrees/`), `.swiftformat`'s `--exclude .claude`
  matches the worktree's own path, so SwiftFormat — the hook and `make strict-gate` — silently
  skips every file there. B2a ran it with the same rules minus that exclusion: clean.
- Live-only (sheets draw system switches as an inactive window): the Crossfeed switch on, off
  and disabled in an active window, both appearances.

**The dark half — its own commit (DARK-AFFECTING; the founder chose "fix both", 2026-10-07).** It moves
`disabledDim` from the whole headphones block to its control row, so in dark too only the control
dims: hint 2.19 → 4.81:1, heading 2.49 → 5.84:1 (darkIC/RT 4.87 / 5.98). The control row stays
pixel-identical (label 4.57:1, the shipped switch). Only the 8 Now Playing dark sheets change,
and only in the heading and hint rows; light is untouched (35/35).

### B2b — the light window backdrop (2026-10-07)

The founder picked **B · Pale glow** live in the app (`Debug ▸ Light Background`) on 2026-10-07;
A (no glow) and C (tinted base) and the switch are deleted — light ships the pale glow.

### B3 — the final light polish (2026-10-07)

Three light-only fixes from the B2a findings, approved by the founder under the freeze rule. Token
math (the R4 tests) first, then the rendered sheet pixels.

| Fix | Commit | Before → after |
|---|---|---|
| Format chips: a 1pt light edge (`controlEdgeLight`, black 20%, now shared with the switch) inside the chip, clipped to it, both states; one `lightEdge` modifier now draws the knob ring, the switch edge and the chip edge | `c3b2e8d` | White chip on the card 1.08 → 1.49 (rendered 1.07 → 1.51), RT/IC card 1.02 → 1.57 (1.02 → 1.58), window 1.17 → 1.37 (1.16 → 1.39); teal playing chip on its row 1.10 → 1.76 rendered. Text unchanged, AA (6.20; teal 5.16–6.72). R4-CHIP-03 |
| Footer groove on the light window: `carvedTrackOnWindow` 7% (the card groove's grey) | `d7d0fc1` | Playing fill end vs groove 2.94 → 3.15 (rendered 2.89 → 3.09); vs window 3.68, unchanged; the groove itself 1.25 → 1.17 against the window. R4-SLIDER-03 now asserts 3:1 outright (pin removed) |
| Paused fill: `scrubberPausedFill`, light = `accentText` 70%, a greyed teal | `685d1f3` | Vs groove 1.34 → 3.41 (rendered 1.32 → 3.33); vs window 1.68 → 3.98 (1.65 → 3.90). It reads dimmer than playing by chroma, not lightness. R4-SLIDER-05 |

The hero's "FLAC · 48 kHz" chip already had an edge: its `.badge` glass hairline measures 1.42 on
the window (rendered 1.43). R4-CHIP-03 now holds it to the same floor; it is unchanged.

**Proof.** All 70 sheets rendered at `7f01921` and at the tip, compared on all four channels. Dark:
35/35 identical, and also identical paused (a throwaway `isPlaying = false` render of Now Playing
and Library, not committed). Light: 35/35 differ, and only in the chip columns and the footer
groove.

**Found, not fixed:**

- Dark paused scrubber: 2.39:1 against its groove, 3.40 against the window. It shipped that way,
  and dark is out of scope.
- R4-SLIDER-01 puts the knob ring over the surface. The ring is actually drawn over the white
  knob, so on the light window it is 2.87:1, under 3:1. That is the footer's hover thumb. On the
  card it is 3.10.
- Reimagine's "Pure (bypassed)" dim, as routed in B2a.

### Merge, gate and the founder's picks (2026-10-07)

- **Merge.** B2a and B2b cherry-picked onto `sprint/s10-8-b-light` with no conflicts. One merge
  fix: `DesignSystemGlass.swift` reached 507 lines (each agent alone was under 500) → the carved
  slider and glass switch moved verbatim to `DesignSystemGlassControls.swift`, sanctioned by
  `ui-no-appearance-branching` (now path-anchored).
- **Gate.** The agents' own strict-gate runs failed at clang-tidy: agent worktrees do not check
  out the `third_party/libebur128` submodule (an artifact, not the code). From here on agents run
  `swift build && swift test` + lint, and ONE `make strict-gate` runs on the merged branch in the
  main repo — exit 0 after each merge.
- **Swift warnings are now build-breaking in debug** (founder request, mid-sprint): the footer's
  `Text + Text` (deprecated in macOS 26) had sat on main since S10.8 PR-G because only C++
  warnings were fatal. `Package.swift` gives every target `treatAllWarnings(as: .error)` in debug
  (release stays permissive, like AudioDSP); the three existing warnings were fixed first
  (`Text` interpolation, `-disable-bridging-pch`, a never-mutated `var`). Proven by planting a
  deprecation and an unused `var`: both fail debug; release still builds.
- **Founder picks (decisions 16, 17).** Backdrop **B** chosen live with a temporary
  `Debug ▸ Light Background` switch, then A, C and the switch deleted (light sheets identical to
  the B sheets, dark identical). Dark text: **fix both** — the headphones hint and the selected
  row's tertiary text (R4-SEL-03 now asserts AA outright).

### Mini-retro — Sprint B

1. **The founder felt a never-ending loop, and was right.** Sprint A had 10 feature commits and
   22 fix commits; every review stage found more, much of it numbers no eye can see. Sprint B's
   tail ran lean (one agent per fix set, the gate, a 2-minute founder look, no separate break-it
   for colour-only changes) and closed fast. **Change:** the founder chooses the routine for
   C–G before Sprint C starts (lighter routine recommended: break-it only for keyboard, focus or
   data-changing work, and once at the end).
2. **Live beats pictures for a taste decision.** The backdrop was picked in the running app via a
   temporary DEBUG switch, then the losers deleted in one commit. Reuse that for any visual
   either/or.
3. **Parallel agents again merged cleanly, but their checks don't add up.** Each kept a file
   under budget, together they broke it; their gate runs were invalid (no submodule). Gate only
   the merged branch; expect a merge-level fix.
4. **Waiting was the real cost.** Picture renders went from ~1.5 to ~40 minutes while the Mac sat
   idle (App Nap-style throttling, not confirmed), and every merge re-ran the 10-minute gate.
   **Change:** keep the Mac awake for renders (or give the renderer a no-throttle activity);
   batch merges so one gate covers several.
5. **Honest labels.** An agent labelled a change "founder decision" before the founder had
   decided; caught and relabelled. Agents never record a decision the founder hasn't made.

## Sprint C — album artists, and the test library

### C1 — the isolated test library (2026-10-07)

Built by one agent in its own worktree, alongside C2.

- **One `AppDataLocation`** decides where the app persists: the store (tracks, albums, playlists,
  queue, history, watched folders), the artwork cache, the single-instance lock, and the settings
  (every `@AppStorage` through `.defaultAppStorage`, and the view models' defaults). Nothing else
  names Application Support or the standard defaults — semgrep `persist-one-location`. The user's
  own location is unchanged: `Application Support/AdaptiveSound/` and the app's standard defaults.
- **`-ASTestLibrary [<folder>]`** (debug only) swaps in `Application Support/AdaptiveSound Test
  Library/`, the `AdaptiveSound.TestLibrary` defaults suite and its own lock, under its own bundle id
  (`com.adaptivesound.app.test-library`, because AppKit files window state by bundle id). It refuses
  to run inside the real bundle. Release builds carry no trace of it.
- **`make stress-library`** writes 10,043 small tagged tracks (857 albums, 345 artists, art and no
  art, long / CJK / RTL / emoji names, compilations with and without the flag, same-title albums in
  different folders, 6- and 8-channel files) to `~/Music/AdaptiveSound Stress Library` in ~7 s
  (~117 MB). **`make run-test-library`** runs the debug app on it; **`make reset-test-library`**
  wipes only the test store.
- **Isolation proof:** four launches beside the founder's running app; the real store files, the
  artwork folder and `defaults export com.adaptivesound.app` were identical before and after.
- **Found by its first stress scan** (fed to C2): FLAC album artists never read; same-title albums
  merging across folders; one artist spelled two ways making two artist rows.

### C2 design check (2026-10-07)

- **Compilation tag.** AVFoundation reads `itsk/cpil`, `id3/TCMP` and `vorb/COMPILATION`; FFmpeg
  reads its `compilation` key (Vorbis, mp4 `cpil` and ID3 `TCMP` all land there). One parser
  (`1`/`true`/`yes`); stored per song. Checked on generated m4a, mp3 and flac files.
- **Grouping** — one pure `AlbumGrouping`, used by the store and the harness. With an album-artist
  tag: title + tag + year, any folder (as today). Without: title + year + **album folder** (the
  file's folder; a `CD 1` / `Disc 2` subfolder folds into its parent, so a 2-disc set stays one).
- **Artist** (no tag): "Various Artists" if any song has the compilation flag or the songs have two
  or more artists (decision 12); else their one shared artist; else Unknown Artist (sentinel).
- **Where it runs.** Each tag write regroups the albums sharing the song's old and new title, so
  every commit is consistent. After every scan or reconcile, `MetadataScanner` regroups the whole
  library (writing only songs whose album changed: the affected albums), sweeps orphan albums,
  then artwork. `removeRoot` does the same in its transaction.
- **Schema v7, appended.** `tracks` + `album_title`, `album_artist_tag`, `compilation`, filled from
  today's album rows; `schema_info.derived_version`; `albums` + `folder_key` ('' = tagged) with the
  unique key widened to (title, artist, year, folder_key). Widening a table UNIQUE needs SQLite's
  table rebuild, the data-preserving, append-only form `makeMigrator` documents: `albums` is
  derived, its ids are copied, foreign keys are off during the migration, nothing is dropped.
- **Version bump.** `derivedDataVersion = 1`: on open, a lower stored value resets
  `metadata_scanned` on every song in one write; at launch the app runs the metadata pass when
  songs are pending ("Reading tags…"). Kept: playlists and entries (never touched), song ids (rows
  updated in place), play count, loved, rating, last played, frecency (no write names them).
- **One missing-artist string:** `unknownArtistName`, also the sentinel row's name; a semgrep
  rule bans the literal anywhere else.
- **Stop check: none hit.** Decision 12 is the rule above; no user data is written; S8's M1 key
  stays total (two untagged same-title albums in ONE folder still collapse) — amended, not broken.

### C2 build record (2026-10-07)

- **Folded in from C1's stress scan.** (1) FFmpeg normalises Vorbis `ALBUMARTIST` to `album_artist`,
  which the FFmpeg path never read, so every tagged FLAC album was credited "Unknown Artist" — fixed
  (generic keys lead the chains; ALB-02 reads the album artist from the real `fixture.flac`).
  (2) Same-title albums merging across folders: ALB-05. (3) Spelling variants: the credit compares
  artist names NFC-normalised and case-folded, so "Zoë" (NFC / NFD) and "zoë" on one album are one
  artist, not "Various Artists" (ALB-01).
- **Finding, not fixed (artist-row identity is S8's):** NFC/NFD and case variants of one artist name
  are still separate artist rows (C1 saw 2 for "Zoë Ångström", 3 for "Neon Harbor"), so the Artists
  list shows them twice and a tagged album-artist spelled two ways is two albums.
- **Beyond the plan's letter:** the end-of-pass regroup is whole-library but writes only the songs
  whose album changed; the artwork sweep now runs after every clean pass (it used to skip passes
  with nothing pending); the harness builds its migrators from `LibraryStore.makeMigrator` (one
  registration list, capped by version) instead of a hand-kept copy.

### C2 review and break-it, round 1 (2026-10-08, code-reviewer + qa-expert, read-only)

Both found the UPGRADE itself byte-safe (a v6 store with playlists, plays, loved, ratings and
frecency, migrated and re-read: user data identical; kill -9 at six points, then resume: identical).
What was not safe was everything around it. Verdict: **not safe for the founder's real library.**

- **Open path (pre-existing, made likely by v7):** any migration failure on a healthy store, or a
  store from a NEWER build, was quarantined and rebuilt EMPTY. A v7 library opened by main's v6
  build came up with no playlists or plays. → the store-open safety round below.
- **The re-read:** a file offline at first launch was marked read and never re-read (3,796 FLAC
  album artists lost for good in the repro); a tag write regrouped every song sharing its title
  (2,000 songs, one title: 118 s; 10k extrapolated past an hour).
- **Grouping:** disc and bonus folders split ("Disc 1 of 2", "[CD 1]", "Bonus/" …, a regression from
  v6); compilations split by year; mixed tagging made twin tiles; stray spaces and NFC/NFD split
  albums; "feat." made Various Artists; ghost zero-song albums mid-pass.
→ the C2 fix round below (A3, B1–B4, C1–C8).

### C2 store-open safety round (2026-10-08)

One agent, in parallel with the fix round. `LibraryStore+Open.swift`, `StoreBackup.swift`.

- **Look first, read-only:** an existing file is checked on a plain connection before anything
  writes to it (a WAL pool writes on open).
- **Quarantine only real corruption** (`SQLITE_CORRUPT`, `SQLITE_NOTADB`, a failed `integrity_check`).
- **Refuse, untouched:** a newer-schema store, or a migration / open failure on an intact file, leaves
  the store nil and the file byte-identical, with a plain message ("This library was last opened by a
  newer version of AdaptiveSound… Nothing was changed").
- **Back up before every migration of an existing store:** `library.pre-v<N>-<stamp>.sqlite3` via GRDB
  `backup(to:)`, written under `.partial` and renamed; the newest two kept; a failed backup refuses.
- **Checks:** OPEN-01…05; SCHEMA-6 and the foreign-schema check now assert refusal (an intentional
  rule change). 11 mutations, all caught. The S8.1 and S10.3 designs carry the annotation.

### C2 fix round (2026-10-08)

Inputs: an independent code review and a break-it pass with real experiments (A3, B1–B4, C1–C8).
**v7 was amended in place, not a v8:** no real library has run it. A TEST library built on the
earlier v7 must be reset (`make reset-test-library`): GRDB never re-runs an applied step.

- **A3** v7 runs with foreign keys off and without GRDB's whole-database check, then checks only the
  references into `albums` (`Schema.checkReferences`) — a stale `tracks.artwork_key` no longer fails
  the upgrade. GRDB's switch is sticky: from v7 on, every step checks its own references.
- **B1** a file that is not there stays pending; only a present-but-unparseable file is marked.
- **B2** a pass's writes do no album work; the end-of-pass regroup is the authority, and
  `schema_info.regroup_owed` (set per write, cleared by the regroup) makes a pass cut off at quit
  regroup at the next launch. A single write regroups its own neighbourhood (old/new title in its
  album folder). `--bi-perf 2000 10 same`: first scan + pass 50.1 s → 2.1 s, re-read 100.9 s → 1.1 s
  (10,000 songs: 13.3 s / 5.8 s; distinct titles unchanged, 2.1 s / 1.1 s).
- **B3** a gone row writes nothing (no `track_genres` FK error); a reconcile's pass reads only its
  root's pending songs; the launch resume never overwrites a running `scanTask`; `removeLibraryFolder`
  lets a running pass skip the removed rows.
- **B4** a single write deletes the album it vacates; the Albums grid hides 0-song albums
  (`FacetListVisibility`, as Artists and Genres).
- **C1** identity is (title, tag) or (title, album folder); the album shows its songs' most common
  non-zero year (a tie → the latest). v6 rows that differed only by year merge in v7, ids kept.
- **C2** disc folders ("Disc 1 of 2", "CD1 - Live", "Disc One", "[CD 1]", "Disc #1", "CD 01" …) and
  "Bonus" / "Bonus Tracks" / "Extras" fold into the album folder; look-alikes don't.
- **C3** untagged songs adopt the one tag their same-title folder-mates agree on.
- **C4** one missing rule, `AlbumGrouping.presentArtist`: empty, whitespace or a literal "Unknown
  Artist" artist or album artist is no artist.
- **C5** `TrackMetadata.init` trims + NFC-normalises the album title, album-artist tag and artist.
- **C6** "X feat./ft./featuring Y" counts as X for shared vs "Various Artists"; rows keep full names.
- **C7** mp3 `TXXX:TCMP` / `TXXX:compilation`, Vorbis `ITUNESCOMPILATION`, and `vorb/ALBUMARTIST`
  on the AVFoundation path; `.opus`/`.oga` go FFmpeg-first. New fixtures `compilation.{mp3,ogg,opus}`.
- **C8** the album cover is its first song with art in (disc, track) order, derived at the regroup.
- **Also:** the search index takes a song's album text from `tracks.album_title`, so a pass that
  defers the album still indexes it at the song's own write.

**Checks.** New ALB-06…16 (A3, B1–B4, C1–C6); C7 extends ALB-02's real-file table; C8 replaces AA.
Rules that intentionally changed in existing checks: **ALB-01** (NFC and NFD spellings are now one
artist row: 3 → 2), **ALB-04** (a literal "Unknown Artist" tag is no artist, not a link to the
sentinel row), **AA** (M5 "the first applied cover wins" → the deterministic cover), **T / DC1 / DC2
/ F8** (the pass write leaves the album to the end-of-pass regroup), and the schema golden. Each new
rule was mutation-checked: broken once, its check failed (21 mutations, all caught). One guard has no
proof of its own: the AVFoundation-path Vorbis keys only matter when FFmpeg is absent, so breaking
the opus routing alone is masked by them (breaking both is caught).

**Deferred.** (1) Case variants of one artist are still separate artist rows, so a tagged album
whose album artist is spelled two ways by case is two albums (S8's artist identity). (2) "Straße" vs
"STRASSE" reads as two artists for the credit (`lowercased()` does not fold ß). (3) No fixture for the
dedicated mp3 `TCMP` frame (the ffmpeg CLI cannot write it). (4) The app-side `scanTask` guard and
`removeLibraryFolder` behaviour have no automated proof (the app is an executable target, which no
test target can import).

### C2 re-break, round 2 (2026-10-08, qa-expert, at `25ef2c5`)

Every round-1 finding re-checked with its original repro and **held**: this build refuses a newer
store untouched; the backup opens with the user data (WAL writes included); offline at the re-read →
all 10,043 stay pending, and after remount the result equals a fresh scan (0 rows differ); 2,000
songs on one title in 1.16 s (was 118 s); every disc / bonus folder folds; compilations and year-less
bonus tracks stay one; removing a root mid-pass is clean; "feat." credits the artist; covers are
deterministic; a stray dangling FK no longer fails v7. Kill -9 at seven points (backup and migration
included) then resume: identical. Live test app: 10k library consistent 13.6 s after launch.
It found two new MAJORs, both from the fix round itself:
- **"Year out of identity" merged distinct tagged albums**: Weezer's Blue (1994) and Green (2001),
  Thriller and its 2008 edition; and an untagged album absorbed a tagged one in its folder.
- **A store migrated by the pre-fix v7 was accepted, then every pass failed.** Dev and test stores
  only — the founder's real store was confirmed at v6 by an immutable read-only look (no lock; file
  byte-identical before and after).
→ the final round below. Decision: **no third break-it round** (decision 18): the final round
re-ran the break-it harness itself, and the founder checks the result on the test library.

### C2 final fix round (2026-10-08)

The re-break confirmed the first fix round holds; it found two MAJORs and three small items.

- **The year tells two albums apart (MAJOR).** Taking the year out of identity merged distinct tagged
  albums: Weezer's self-titled Blue (1994) and Green (2001) became one six-song album with duplicate
  track numbers, and Thriller merged with its 2008 edition. The year is now a SPLIT, only where a
  group holds two albums (`AlbumGrouping+Years.swift`, `albums.edition_year`, 0 unless split):
  - a tagged group spanning album folders whose dominant years differ splits per folder year;
    agreeing or year-less folders stay together;
  - an untagged folder holding two primary artists in two years splits per year (Queen's 1981 and
    ABBA's 1992 "Greatest Hits" in one flat folder);
  - a compilation (the flag, or a "Various Artists" tag) never splits; a year-less song or folder
    joins its group's most common year;
  - adoption (C3) needs agreeing years, or a year-less untagged song ("Gardens": an untagged 1962
    album beside a tagged 2023 one is two albums again, as is ABBA beside a tagged Queen "Hits").
  A single write now regroups every song sharing its old or new title, the smallest complete scope
  now that a split weighs all of a tagged album's folders. v7 copies every v6 row with its year as
  `edition_year` (ids kept; no merge). Re-read cost unchanged: `--bi-perf 2000 10 same` 2.1 s first
  scan + pass / 1.17 s re-read; the 10,043-song stress store upgrades and re-reads in 6.0 s, with no
  album holding a duplicate (disc, track).
- **A store an unfinished test build migrated to v7 is refused (MAJOR).** v7 was amended in place
  twice; a dev/test store migrated by an earlier amendment recorded v7 as applied, so GRDB never
  re-ran it, and every pass then failed (`no such column: regroup_owed`, an `ON CONFLICT` matching no
  key). The open path now checks the v7 shape (`Schema.v7ShapeProblem`: the columns v7 adds, and the
  album key) and refuses a mismatch (`StoreOpenRefusal.unfinishedTestVersion`), the file untouched.
  The founder's real store is at v6 and migrates normally.
- **Look-alike folders.** A disc folder is now just a disc marker with a small number (below 100),
  optionally " of N", then a " - subtitle" or a bracketed note. "CD 100 Hits", "CD 1 Hits" and
  "CD 100" are albums of their own; "CD1 - Live" and "Disc 1 (Remastered)" still fold.
- **A refusal is byte-identical even with a hot WAL.** The open path's look-first connection turns
  off checkpoint-on-close (`SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE`, through a small C target,
  `StoreSQLiteShim` — Swift doesn't import the variadic `sqlite3_db_config`), so refusing a library
  whose WAL still holds a crash's writes leaves its main file and WAL as they were.
- **Stale backups.** A backup a crash left half-written (`.partial` + journal) is cleared at the next
  backup.

**Checks.** New ALB-17 (the year splits two albums, and a single retag that makes the years agree
merges them in that write) and OPEN-06 (both earlier v7 shapes refused, with a hot WAL, while this
build's v7 passes). Extended: SCHEMA-6 (the newer build's id only in the WAL, refused byte-identical),
OPEN-02 (stale `.partial` cleared), ALB-12 (look-alikes). Intentionally changed: **ALB-11** (a tagged
album across folders of different years now splits; its "stays one" case is now folders whose years
agree or are missing) and **ALB-06** (year-apart v6 rows stay two, ids kept, instead of merging); the
schema golden. 13 mutations of the new rules, each caught. VerifyLibraryStore 148/148.

**Re-break harness re-run.** Every `--bi-edge` scenario (rounds 1–3, `biScenarios3` included) groups
as specified; real FLACs from `mkweezer.sh` give Weezer 1994 ×3 and 2001 ×3 (tracks 1–3 each) and two
Peter Gabriel albums; the break-it's old v7 store is refused, byte-identical.

**Deferred** (out of scope for this round, as agreed): disagreeing album-artist tags ("Band" vs "The
Band") still make twin tiles; "&" / "and" / "with" guest forms and "ß" vs "SS" still read as two
artists for the credit; a root that stays offline re-runs a short "Reading tags…" pass at each
launch; backups taken in the same second can prune out of order.

### Merge and gate (2026-10-08)

C1, C2, the store-open safety round and three C2 fix rounds were cherry-picked onto
`sprint/s10-8-c-artists` (two conflicts: the launch path in `LibraryModel+Scan.swift`, where the
test-library scan stands in for the launch re-read, and the check registry in VerifyLibraryStore's
`main.swift`). One merge-level fix: Periphery's hostile config flagged four leftovers of the first
fix round (a key struct read only through `Hashable`, an import, a helper) — the agents had not run
Periphery. `make strict-gate`: exit 0 on the final tip; VerifyLibraryStore 148/148.

### Founder check and the real-library upgrade (2026-10-08)

The real library must not meet this build before it is on main: main's v6 build would quarantine a
v7 store (the old open path), and this build refuses only from now on. So: check on the test
library, merge, then the founder's own app upgrades the real library, with the automatic
`library.pre-v7-*` backup plus a manual copy taken first.

**Done.** The founder checked on the test library (and asked for the Genres grid — decision 19) and
merged PR #70. With both apps quit, a full copy of the library folder was taken and verified (90
files, md5-identical); `make run` on main then upgraded the real library: the automatic
`library.pre-v7-*` backup was written, v7 applied, the re-read finished (0 songs pending). Compared on
a scratch copy against the pre-upgrade snapshot: 379 songs, 4 playlists / 23 entries (same songs,
same order) and every user column (plays, rating, loved, last played, frecency) **identical**; albums
139 → 138; albums credited "Unknown Artist" **139 → 0**. 26 songs have no artist tag at all and
still read "Unknown Artist" — correct. Scratch copies deleted.

### Mini-retro — Sprint C

1. **Store work earned the full review + break-it, and the founder's data is why.** The upgrade was
   byte-safe from the first build, yet round 1 found that a failed or newer store was wiped from
   view — a pre-existing open-path rule that v7 made likely. Keep review + break-it for any store,
   migration or audio-path work (decision 18 already says so).
2. **A fix round can cause the next round's MAJORs.** "Year out of identity" fixed compilations and
   merged Weezer's two albums. A product-visible rule change needs its counter-examples written
   down before it is coded (here: same title + artist, different years).
3. **Don't delete an agent's worktree until the sprint closes.** The C2 builder could not be resumed
   for its own fix round (its worktree was gone); a fresh agent relearned the code.
4. **Agents must run Periphery** (`make periphery`): the gate's hostile dead-code check caught four
   leftovers after a merge. Briefs now name it.
5. **The test library paid off on day one.** Its first scan found the FLAC album-artist bug behind
   the founder's "Unknown Artist", and every break-it repro ran on it — never on the real library.

## Behaviour pull-forward — keyboard, scroll restore, playlist moves (decisions 18, 20)

### Plan check and split (2026-10-08, coordinator)

The lighter routine (decision 18), three agents in parallel worktrees off `18a3430`, split by file
so they cannot collide:

| Piece | Scope | Owns |
|---|---|---|
| **E1** | the selection kit (cursor, anchor, ⇧-extend, ⌘A, type-to-select, Home/End, Page Up/Down, Esc) — no column or sort knowledge (COL-01) — wired into Songs with no visual change; the Songs count line no longer wraps at 880×640 (D6, second half) | `ListKeyboardCursor`, the Songs files |
| **Grid keys + D6** | a 2-D `GridKeyboardCursor` for Albums / Artists (Genres stays a list until Sprint D); the A3 ring on tiles; back from a detail page restores the scroll position and the cursor (D6) — and, if wiring twice would duplicate, the browse-grid STRUCTURE moves forward from D5 (no restyle) | the grid / facet views, `LibraryRoute` |
| **E4 moves** | Move Up / Down / to Top for playlist entries (context menu + shortcuts), through the store API drag-reorder already uses | the playlist files |

Agents do not drive the real UI (the founder may be using the Mac); the live Full Keyboard Access
pass (Sprint A retro rule) runs once, coordinated with the founder, at break-it time.

### Build record (2026-10-08)

- **E1** — `ListSelection` (LibraryBrowseKit): cursor, anchor, ⇧-extend, ⌘A (the filtered rows),
  Home / End, Page Up / Down, type-to-select, Esc; no column or sort knowledge (semgrep
  `selection-kit-no-columns`). Wired into Songs with no visual change; the Songs count line drops its
  duration where it would wrap (880×640). SEL-01…08 defined in the plan (§E).
- **Grid keys + D6** — `GridKeyboardCursor`; the browse STRUCTURE moved forward from D5 with no
  restyle (`BrowseGridRoot`, `BrowseGrid`, `BrowseTile`, `BrowseKeyboard`, `BrowseNavigator`, the
  Genres `FacetList` on ScrollView + LazyVStack); back from a page restores the place (`BrowsePlace`)
  and the Filter (`browseFilter`); a sidebar jump starts fresh.
- **E4** — `ListMove` (Move to Top / Up / Down / to Bottom: ⌥⌘↑ / ⌥⌘↓, ⌥⇧⌘↑ / ⌥⇧⌘↓, context menu,
  VoiceOver). Saving goes through a per-playlist latest-wins `CoalescingWriter` (LibraryBrowseKit)
  and `ListOrder` (the store's merge rule) so a reload never publishes over an unsaved order; quit
  flushes it.
- **Merge** — one shared `TypeSelectBuffer` (both agents had written one) and one `KeyPress.isShortcut`
  rule ("⌘ / ⌥ / ⌃ held = a shortcut, not a step or typing") for Songs, the grids and the rail.

### Code review (2026-10-08, code-reviewer, read-only) → one fix round

**BLOCKER:** a single pending-order slot let a playlist switch mid-burst silently drop the first
playlist's newest order. **MAJOR:** a stale reload could publish the old order and the next save
made the revert permanent; ⌥⌘↑/↓ went to the sidebar (it took modifier arrows) and switched
playlists. **MINOR:** quit could lose the last order; the failure alert was not tied to its playlist;
the grid type-select prefix never reset; Genres' keys sat on an NSTableView-backed `List`; deleting
the open playlist wiped the browse state; Songs rows could each be a Tab stop. All fixed by the three
builders in parallel (each in its own worktree), with tests (the writer: 7, mutation-checked).

### Live keyboard pass (2026-10-08, the coordinator, real CGEvent input on the test library)

The plan's founder script (A Songs, B grids, C playlists), driven with real key and mouse events
on the 10,043-song test library, verified through the accessibility tree, the app's `[UX]` log and
the TEST library's database. **Found a BLOCKER no test could:** End in Songs froze the app (100% CPU
for minutes) — `scrollTo(id)` made the lazy stack build every row up to the last (~20,000), and each
row's eager context menu scanned all songs. Fixed (`FixedRowReveal`: scroll by arithmetic on the fixed
row height; an O(1) menu decision, targets resolved in the actions; shared per-pass row values) and
guarded by `make songs-perf` (offscreen, 20,000 songs; every key < 100 ms — measured 27–42 ms, ≤ 82
rows built; End was 15.1 s / 19,986 rows). Re-run live after the fix: **A1–A9, B1–B5, C1–C5 all pass**
(⌥⌘↓ stays in the playlist; switching playlists mid-burst keeps both orders; ⌘Q right after a move
keeps it; back from a page restores the place even at the end of 862 albums).

Harness lessons (tools in the session scratchpad: `kp`, `mc`, `ax`): a flagged key event leaves the
modifier "held" in the HID source state — every event must set its flags explicitly, or later clicks
arrive as ⌘-clicks; CGEvent letters don't type into fields (use System Events `keystroke`); re-read a
row's frame before clicking (the list scrolls the cursor into view); no Screen Recording, so verify
through the AX tree, the log and the database. Noted, not fixed: the inline new-playlist name field
does not take focus (click it first); sidebar rows are each a Tab stop (pre-existing); switching tabs
clears the Songs selection; a filtered grid's count reads "N albums" (Sprint D's header).

### Mini-retro — behaviour pull-forward

1. **Run the slow, real checks BEFORE review, not after.** The review found data and focus bugs; the
   live pass found a freeze no test could. Three passes where two would do: next sprint, the agents
   run `make songs-perf`-style perf checks and the coordinator runs the live keyboard pass on the
   merged branch before the code review.
2. **Stress data is the point.** The End-key freeze only exists at 10k rows — the founder's 379-song
   library would never show it. Keep the 10k test library in every keyboard / list check.
3. **Parallel agents duplicate shared helpers** (two `TypeSelectBuffer`s, two modifier rules). The
   plan check should name the shared pieces and their owner up front.
4. **A cherry-pick skips the pre-commit hook** — a merge-resolution commit failed the gate's lint.
   Run swiftlint on the resolved files before committing a resolution.
5. **The founder stopped the agents to ask whether they were useful** — a fair check. Report each
   agent's measurable result (here: End 15.1 s → 0.04 s) rather than activity.
