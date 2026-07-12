# Stage 4 — GUI / SwiftUI review (view layer)

**Theme:** architectural elegance · reuse · best practices (+ accessibility, the GUI-specific correctness lens)
**Scope:** the VIEW layer only — all of `Sources/AdaptiveSound/UI/**` (EQ, Library, Loudness, Monitoring, NowPlaying, Playlist, Settings, Shell, Spectrum, Tabs) plus the top-level view files `AdaptiveSound.swift` (scene), `ContentView.swift`, `TabContentView.swift`, `MenuBarView.swift`, `DesignSystem.swift`, `Color+Brand.swift`, `FormatBadgeView.swift`. **Excluded** (other stages): all view-models (`AudioViewModel*`, `LibraryModel*`, `LibraryBrowseModel*`, `EQViewModel*`, `UI/Monitoring/MonitoringViewModel.swift` — Stage 3), `AudioEngineBridge*` (Stage 3), `LibraryStore` (Stage 5), SQL (Stage 6).
**Method:** two independent SME lenses — `swiftui-pro` (modern SwiftUI idiom / correctness / performance) + `accessibility-tester` (VoiceOver / keyboard / Dynamic Type / contrast / HIG) — then a `the-fool` adversarial pass that read the actual source to confirm/refute each finding (and independently recomputed the WCAG contrast math), then main-agent reconciliation. No build was run by the reviewers.

---

## Executive summary

The view layer is in **good SwiftUI health**: modern APIs used consistently (value-based `.animation(_, value:)` with Reduce-Motion gating, two-parameter `onChange`, `foregroundStyle`/`clipShape(.rect(...))`, `onGeometryChange` over `GeometryReader`), a thorough `DesignSystem` token system, and the two macOS-specific crash traps (`Table` + `@Environment(Observable)`, `List(selection:)` gesture races) **correctly and knowingly avoided** where they were addressed. `ArtworkThumbnailStore`, `SongsTable`, `SongsView`'s debounce, and the shell primitives are exemplary — do not touch them.

The adversarial pass **reshaped the severity distribution sharply**:

- It **upgraded** the one plausibly-real user-facing bug — **SW1**, the bare-`Space` menu shortcut that steals the space key from the Library filter text fields — from MEDIUM to **HIGH** (pending a 30-second runtime confirm), because it fires in a music player's steady state (a track is selected while you browse).
- It **downgraded the entire SwiftUI "performance" tier to LOW** — SW3/SW4/SW6/SW7 are all real redundancies but trivial in impact (≤8 static rows, one-shot I/O, in-memory filters, a 30-bar × 20 Hz gradient), and it corrected SW6's "debounce like SongsView" advice as a category error (in-memory `.filter` ≠ async store query; the fix is **de-duplication**, not debouncing).
- It **confirmed the accessibility tier intact**: one **HIGH** (the EQ curve is a mouse-only drawing surface — the app's signature feature is unreachable by VoiceOver and keyboard-only users, verified by grepping the whole EQ folder for any adjustable/focusable/keyboard path and finding none) and five solid **MEDIUM**s, including the contrast finding whose ratio it recomputed independently at **2.52:1** (AA needs 4.5:1).

**The strongest signal is convergence:** both lenses independently flagged the **Album-detail / facet track rows** — `swiftui-pro` for the double-click race (SW2), `accessibility-tester` for missing rotor verbs + no Return-to-play (A-M4). Those older screens simply never received the accessible, gesture-reliable treatment their newer siblings (`SongsTable`, `FacetTrackListView`) already prove out. That's the highest-value, lowest-risk cluster in this stage.

Nothing in this stage touches the DSP kernel or the golden-master path — even the EQ-accessibility fix only adds input routes that write the same already-clamped `bandGains`.

### Verdict table

| # | Finding | SME call | the-fool verdict | **Final** | Action |
|---|---------|----------|------------------|-----------|--------|
| SW1 | Bare-`Space` menu shortcut steals space from Library filter `TextField`s | MED (HIGH if confirmed) | **UPGRADE → HIGH** (fires in steady state; app's own comments prove menu key-eq wins) | **HIGH** | Fix now (30s runtime confirm first) |
| A-H1 | EQ 31-band curve editable only by drag — no VoiceOver/keyboard path | HIGH | CONFIRMED (no adjustable/focusable/keyboard path anywhere in EQ) | **HIGH** | Fix — founder call on approach |
| SW2 | `AlbumDetailView` + `FacetTrackListView` use `List(selection:)` + `.onTapGesture(count:2)` — drop-click race | MED | CONFIRMED (applies the ratified pattern, doesn't reverse it) | **MED** | Fix now (with A-M4) |
| A-M4 | Same album rows: verbs only in `.contextMenu` (rotor can't reach) + no `.onKeyPress(.return)` | MED | CONFIRMED (asymmetry vs `FacetTrackListView` real, admitted in-code) | **MED** | Fix now (with SW2) |
| A-M3 | Queue now-playing/selected is color-only + VO reads noisy file path | MED | CONFIRMED (bg-opacity only; `relativePath` in composed label) | **MED** | Fix now |
| A-M5 | Peak-meter clip/"hot" state color-only + absent from `accessibilityValue` | MED | CONFIRMED (`isHot ? .red`; value omits clip flag) | **MED** | Fix now |
| A-M6 | Accent `#29B6A4` as white-on-accent button text = **2.52:1** (< AA 4.5:1) | MED | CONFIRMED (independent recompute = 2.52:1) | **MED** | Fix now (single-source) |
| A-M2 | `DesignSystem.Font` rungs are fixed `.system(size:)` → OS text-size setting is a no-op; own `.dynamicTypeSize` clamps are dead | MED | CONFIRMED (softened: macOS Dynamic Type adoption weaker than iOS) | **MED** | Fix soon (single-source + call-site migration) |
| SW5 | `TrackInfoCard` uses banned `String(format:)` + `ByteCountFormatter` inconsistency | MED | CONFIRMED (house-rule ban; `SongsTable:431` is the established form) | **MED→LOW** | Fix now (polish) |
| SW3 | `MonitorChannelRowView` `GeometryReader` only to split 50/50 | MED | DOWNGRADE → LOW (≤8 static rows; safe `.frame(maxWidth:.infinity)` swap) | **LOW** | Polish |
| SW4 | `TrackInfoCard` `Task.detached` vs repo's `@concurrent nonisolated … -> sending` | MED | DOWNGRADE → LOW (already `!Task.isCancelled`-guarded; one-shot I/O) | **LOW** | Polish |
| SW6 | Filtered collections recomputed 3–4× per render, undebounced | MED | DOWNGRADE → LOW; **fix = de-dup, NOT debounce** (in-memory ≠ async query) | **LOW** | Polish |
| SW7 | `SpectrumAnalyzerView` rebuilds constant per-bar gradient every ~20 Hz frame | MED | DOWNGRADE → LOW (~30 bars × 20 Hz trivial; cache `[LinearGradient]`) | **LOW** | Polish |
| L7 | Inconsistent `⌘[` back shortcut (`FacetTrackListView` has it, `AlbumDetailView` doesn't) | LOW | CONFIRMED | **LOW** | Polish (with SW2/A-M4) |
| L8 | Small hit targets (size-14 transport glyphs, clear-filter ✕) | LOW | plausible | **LOW** | Optional |
| L9 | `.accessibilityElement(children: .combine)` wraps operable pickers | LOW | CONFIRMED, correctly scoped (only `threeRow` extreme-DT fallback) | **LOW** | Optional |
| L10 | `labelTertiary` `white.opacity(0.48)` borderline AA on card surface | LOW | plausible | **LOW** | Verify with contrast checker |
| SW-LOW | idiom cluster: `replacing` over `replacingOccurrences`; stray `Array(enumerated())`; `SongsHeader.filterField` dupes `LibraryFilterField`; `togglePlayPause()` verb | LOW | mostly confirmed; **2 cautions** (see below) | **LOW** | Polish |

**Two "do not blindly fix" cautions from the-fool:**
- The per-row `.popover(isPresented: Binding(get:set:))` at `AlbumDetailView.swift:110` / `FacetTrackListView.swift:180` / `PlaylistView.swift:181` is **deliberate** — a `ForEach` with a shared `.popover(item:)` presents on *every* row when the item is set; the derived per-row binding is the correct anchor. **Not a finding.** Do not "unify" to `.popover(item:)`.
- Dropping `Array(...)` from `NowPlayingWidget.swift:160` must be checked against `ForEach`'s `RandomAccessCollection` requirement — the codebase documents this exact reliability caveat at `PlaylistView.swift:139-144`, and `PlaylistView.swift:145` keeps `Array(...)` *correctly* for `.onMove`. Verify before touching.

---

## Fix now — one focused PR (the convergent cluster + cheap single-source wins)

### SW1 — bare-`Space` menu shortcut steals the space key from Library filters (HIGH)
`AdaptiveSound.swift:85` binds `.keyboardShortcut(.space, modifiers: [])` to Play/Pause in a `CommandMenu`, gated only by `.disabled(selectedTrackIndex == nil)` (`:86`). The filter fields are plain `TextField`s with no space guard (`SongsHeader.swift:50`, `LibraryFilterField.swift:18`). A modifier-less menu key-equivalent is matched in AppKit's `performKeyEquivalent:` **before** the field editor inserts the character — so bare space toggles playback instead of typing a space, breaking multi-word filtering ("pink floyd"). The `.disabled` guard does not save it: browsing with a track selected is the steady state of a music player. The app's own code already knows menu key-equivalents win (`AdaptiveSound.swift:76-77`; the queue's `.onKeyPress(.space)` at `PlaylistView.swift:252` is the workaround that proves it).

**Fix:** gate the shortcut on first-responder focus, or scope it so it does not fire while a text field is focused (keep Space-to-play via the footer button / queue `onKeyPress`). **First: a ~30-second `make run` confirmation** — this rests on established AppKit behavior, not a runtime repro. **Effort S.**

### SW2 + A-M4 + L7 — Album-detail & facet track rows: fix the double-click race AND finish the accessibility (MEDIUM) — the convergent cluster
Both lenses landed on the same rows.
- **SW2 (idiom):** `AlbumDetailView.swift:95-98` and `FacetTrackListView.swift:120-165` drive double-click-to-play with `List(selection:)` + `.onTapGesture(count:2)` — the documented drop-click race the grids already moved away from.
- **A-M4 (a11y):** `AlbumDetailView.swift:101` exposes only a default (unnamed) Play action; Play Next / Add to Queue / Info live **only** in `.contextMenu` (`:102-108`, invisible to the VoiceOver actions rotor), and there is **no** `.onKeyPress(.return)` anywhere in the file → keyboard-only users cannot play. `FacetTrackListView` already has named `.accessibilityAction`s (`:168-171`) + `.onKeyPress(.return)` (`:127,144`); `AlbumDetailView` is the laggard, and its own comments admit it (`:99-101`).
- **L7:** `FacetTrackListView.swift:54` binds `⌘[` back; `AlbumDetailView.swift:34-49` back bar has no shortcut.

**Fix (one coherent pass over the two detail screens):** bring `AlbumDetailView`'s track rows up to the `FacetTrackListView` bar — named rotor `.accessibilityAction`s for every verb + `.onKeyPress(.return)` to play the selection + `⌘[` back. For the mouse double-click, converge both files on one reliable path: either `Table(primaryAction:)` (as `SongsTable` proves) or Button-per-row (as `AlbumGridView`/`FacetListRoot.swift:94` prove) — either resolves the race; neither reverses the ratified pattern. **Effort M.**

### A-M3 — Queue now-playing / selected state is color-only and unlabeled for VoiceOver (MEDIUM)
`PlaylistItemRow.swift:44-50`: now-playing vs selected is distinguished only by `listRowBackground` opacity (0.25 vs 0.12) — color-only; neither state is exposed to VO. The row has `.accessibilityAddTraits(.isButton)` (`PlaylistView.swift:167`) but no `.accessibilityLabel` override, so VO composes a label that includes `file.relativePath` (`:28`) — reading a noisy monospaced file path.

**Fix:** give the row an explicit `.accessibilityLabel` (mirror `TrackRow.accessibilityLabel`, exclude the path), append state via `.accessibilityValue(isNowPlaying ? "Now playing" : "")` / `.accessibilityAddTraits(isSelected ? .isSelected : [])`, and add a non-color now-playing cue (a small ▶/speaker glyph in the number column). **Effort S.**

### A-M5 — Peak-meter clip/"hot" state is color-only and missing from the VoiceOver value (MEDIUM)
`LoudnessMetersView.swift:73-75` `isHot = peakDb >= -1`; `:87` fill = `isHot ? Color.red : Color.asAccent` (color-only, no "CLIP" text/shape); `accessibilityValue` (`:95-97`) reports dBFS/"silent" with no clip flag. This is the most safety-relevant state on the meter and it's invisible to colorblind + VoiceOver users.

**Fix:** add a "CLIP" text or `exclamationmark.triangle` badge when `isHot`, and append `" — over"` / `" — clipping"` to the `accessibilityValue`. **Effort S.**

### A-M6 — Accent-teal fails WCAG AA as button text (MEDIUM) — single-source fix
`DesignSystem.swift:32` accent `#29B6A4`, `onAccent = .white` (`:36`). the-fool's independent recompute: relative luminance of `#29B6A4` = 0.366 → contrast vs white = **2.52:1**, well below the 4.5:1 text minimum, and appearance-independent (fails dark mode too). Confirmed white-on-accent on the prominent Play buttons: `AlbumDetailView.swift:78-79` and `FacetTrackListView.swift:93-94` (`.buttonStyle(.borderedProminent).tint(DesignSystem.Color.accent)`).

**Fix:** for text-bearing accent fills use the already-defined darker `accentDeep #148979` (verify it clears AA; may need a touch darker) — a single-source change in `DesignSystem`, no need to abandon the brand teal for non-text (glyph/track) uses. Fold **L10** (`labelTertiary` `white.opacity(0.48)` on the card surface, `DesignSystem.swift:57-58`) into the same contrast-checker pass. **Effort S.**

### SW5 — banned `String(format:)` + formatter inconsistency (LOW, polish)
`TrackInfoCard.swift:227` uses `String(format: "%.1f kHz", …)` (banned by the repo's `swift.md`); `:197-199` uses `ByteCountFormatter` where `SongsTable.swift:431` uses the established `fileSize.formatted(.byteCount(style: .file))`.
**Fix:** `"\(kHz.formatted(.number.precision(.fractionLength(1)))) kHz"` and `.formatted(.byteCount(...))`. **Effort S.**

---

## Fix soon — one systemic accessibility win

### A-M2 — App text does not scale with the macOS text-size setting (MEDIUM)
Every `DesignSystem.Font` rung (`DesignSystem.swift:69-79`) is `Font.system(size:)` with no `relativeTo:`/text-style, so it ignores Accessibility → Display → Text size. This makes the deliberate clamps at `SongsTable.swift:57` (`.dynamicTypeSize(.small ... .xxLarge)`) and `NowPlayingBar.swift:39` **dead code** — the app signals scaling intent that never fires. Many controls also bypass the tokens with raw `.system(size:)` (`PlaylistItemRow`, `NowPlayingWidget`, `NowPlayingInfoView`, `LoudnessMetersView`, `MasterGainSliderView`).

**Fix:** redefine the `DesignSystem.Font` rungs with `.system(size:relativeTo:)` (or map to text styles) so they scale within the existing clamps, and migrate the ad-hoc `.system(size:)` call sites onto the tokens. Single source of truth + a bounded call-site sweep. *(Real-world impact softened — macOS Dynamic Type adoption is weaker than iOS — but the accommodation is real in Sonoma+, and the codebase's own clamps show it was meant to work.)* **Effort M.**

---

## Fix — needs a design decision (founder call)

### A-H1 — The EQ curve is mouse-only: the signature feature is unreachable by VoiceOver & keyboard (HIGH)
`FrequencyResponseCanvas.swift:49-57` edits the 31-band curve **only** via `DragGesture`; the a11y wrapper (`:63-71`) is a single read-only element whose hint literally says "Click or drag to adjust" — an instruction a VoiceOver user physically cannot follow. the-fool verified by grep across `Sources/AdaptiveSound/UI/EQ/`: **no** `Slider`, `Stepper`, `accessibilityAdjustableAction`, `focusable`, or `onKeyPress` exists; the only `bandGains` writes are the drag and `EQViewModel.swift:109` (clamp). `EQControlsSection` offers only Interpolation/Preset pickers + Save — none shapes an individual band. So per-band EQ editing is impossible for both VoiceOver **and** keyboard-only users.

**Options (need a decision on approach):**
1. **Adjustable representation** — make the canvas (or a hidden sibling) expose the focused band via `accessibilityAdjustableAction` (increment/decrement, announcing "1 kHz, +3 dB"). Keeps the visual canvas; smallest surface.
2. **Accessible per-band control list** — a collapsible list of per-band `Slider`/`Stepper` rows with `.accessibilityValue` in dB (also helps low-vision + motor users; larger UI addition).
3. **Interim (do regardless):** stop advertising "Click or drag to adjust" to VoiceOver while no VO-reachable adjust action exists — a truthful hint until (1)/(2) lands.

View-layer only — writes the same already-clamped `bandGains`, does **not** touch the DSP kernel/golden-master. *Founder sign-off on approach before implementing.* **Effort M–L depending on option.**

---

## Deferred / optional — polish cluster (with the-fool's severity corrections)

- **SW3 (LOW):** `MonitorChannelRowView.swift:83-107` — swap the 50/50 `GeometryReader` for `.frame(maxWidth: .infinity)` on the two `SpectrumMiniView`s. Safe simplification; not a perf win (≤8 static rows). *(The `FooterScrubber` `GeometryReader` in `NowPlayingBar.swift:243` is legitimate — needs track width for drag math — leave it.)*
- **SW4 (LOW):** `TrackInfoCard.swift:155` — migrate `Task.detached(...).value` to the repo's `@concurrent nonisolated static … -> sending` pattern (`ArtworkThumbnailStore.swift:59-60`) for cancellation linkage + consistency. Already stale-write-guarded (`:160`), so no user-facing harm today.
- **SW6 (LOW):** de-duplicate the filtered collection to one `let` per body pass — `AlbumGridView.swift:59/74/82`, `ArtistsView.swift:23/27` (compounded), `FacetListRoot.swift:77`. **Do not debounce** — these are in-memory `.filter`s, not async store queries (that's why `SongsView` debounces and these should not).
- **SW7 (LOW):** cache the per-bar gradients (`[LinearGradient]` keyed on `bars.count`) instead of rebuilding in the `ForEach` body every ~20 Hz — `SpectrumAnalyzerView.swift:25`.
- **SW-LOW idiom nits:** `replacing(...)` over `replacingOccurrences(...)` (`NowPlayingBar.swift:393`, `NowPlayingWidget.swift:231`); drop the gratuitous `Array(tracks.enumerated())` at `AlbumDetailView.swift:96` (no `.onMove`); consolidate `SongsHeader.filterField` (`:46-82`) onto the reusable `LibraryFilterField` so the search-pill styling can't drift; a single `togglePlayPause()` verb to collapse the ~5 duplicated `if isPlaying {…}` sites (`AdaptiveSound.swift:79-83`, `PlaylistView.swift:207/213/247/254` — note: touches the VM, so pair with a Stage-3 follow-up or do view-side only). Respect the two cautions above.
- **L8 (LOW):** consider ≥28pt `contentShape` frames on the size-14 transport toggles (`PlaylistView.swift:78-114`) and clear-filter ✕ (`LibraryFilterField.swift:28-34`, `SongsHeader.swift:60-66`) for motor targeting.
- **L9 (LOW):** verify (or drop) the `.accessibilityElement(children: .combine)` around the operable pickers at `EQControlsSection.swift:63,71` — only the rare `threeRow` extreme-Dynamic-Type fallback; the normal paths use `LabeledContent` and are fine.

---

## What is genuinely GOOD — do not "fix"
- **`SongsAccessibility.swift` + `SongsTable.swift`** — the reference implementation: a single stable row element whose label/value compose from the *track model* (hiding columns never changes the spoken identity), Play as the default action + named Play Next / Add to Queue / Info rotor actions, every data cell `.accessibilityHidden`, `⌘F` focus, Return-to-play, and a live `AccessibilityNotification.Announcement` on sort changes. It also correctly navigates the `Table` + `@Environment(Observable)` crash (env-free cells, model as a plain `let`, native `TableColumnCustomization` `@AppStorage`, correct two-parameter `onChange`). This is the bar the laggard screens should meet.
- **`ArtworkThumbnailStore.swift`** — exemplary modern concurrency: `@concurrent nonisolated static … async -> sending CGImage?` to cross isolation race-free, `NSImage` pinned to `@MainActor`, batched `warm(keys:)`, `NSCache` pressure eviction, synchronous cache peek to avoid placeholder flashes.
- **`SongsView.swift:26`** — textbook `.task(id: model.searchQuery)` debounce (`Task.sleep`, `Task.isCancelled`, model epoch guard), hosted on the stable parent so header churn can't tear it down.
- **`ErrorBanner` + `QueueToast`** — non-modal failures/confirmations spoken via `AccessibilityNotification.Announcement` on a persistent host so they re-fire reliably; decorative icons `.accessibilityHidden`; both honor Reduce Motion.
- **Transport sliders + scrubber** — `MasterGainSliderView` and `NowPlayingInfoView` expose real dB/percent values; `NowPlayingBar`'s footer scrubber has a proper `accessibilityAdjustableAction` for seek plus interrupted-device state in its value.
- **Shell primitives** (`AppShell`, `Screen`, `VisualizerSurface`, `WindowMinSize`) — clean layering, `onGeometryChange` over `GeometryReader`, every non-obvious layout decision justified in-code; Reduce Motion respected consistently via `@Environment(\.accessibilityReduceMotion)`; system Materials auto-adapt to Reduce Transparency.

---

## Recommended plan
1. **PR A (fix now):** SW1 (Space-shortcut — confirm with `make run` first) + the convergent **SW2 + A-M4 + L7** cluster (Album/facet rows: reliable double-click + rotor verbs + Return-to-play + `⌘[`) + A-M3 (queue state a11y) + A-M5 (clip a11y) + A-M6/L10 (single-source contrast) + SW5 (formatter polish). One coherent "finish the accessible-interaction pattern + fix the input bugs" PR. Gate: `swift build` (Swift 6) + `swift test` + `swiftlint --strict`.
2. **PR B (soon):** A-M2 (Dynamic Type — `DesignSystem.Font` `relativeTo:` + call-site sweep).
3. **Founder call (design decision):** A-H1 (accessible EQ editing — pick option 1/2/3; do the interim hint fix regardless).
4. **Optional polish:** SW3 / SW4 / SW6 (de-dup, not debounce) / SW7 + the SW-LOW idiom nits + L8 / L9 — batchable as a low-risk cleanup PR, respecting the two "do not blindly fix" cautions.

**PAUSE — boundary.** Per cadence, no fixes applied yet. Awaiting go-ahead on the plan (and the A-H1 approach decision) before implementing.
