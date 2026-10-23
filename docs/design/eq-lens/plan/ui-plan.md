# Sprint EQ: UI plan v2 (V1b). Replaces `ui-plan-check.md`

*ui-designer, 2026-10-10. This was a read-only check. Sources:*
- *Branch `feat/s10-8-eq` @ `c15f183`, read through git objects with no checkout.*
- *The founder decisions: 21–24 (V1b) and 25–28.*
- *The architect's review (APPROVED WITH AMENDMENTS), whose reconciled contract (§2) is **the
  contract** here.*
- *The UI-relevant findings of the breaker's and the SOTA review.*

*The visual reference is the uncommitted prototype in my worktree (`Debug/EQProto.swift`, modes
`v1b`, `v1bTone`, `v1bDrag`, `v1bCollapsed`).*

## 0. What changed since v1 (one paragraph)

The names follow the contract:
- **`base`**: the user's layer, ±24;
- **`tone`**: 5 values, ±12;
- **`points`**: clamp(base + Σ tone·w, ±12), the values **drawn and sent**.

The engine seam is the **existing** `AudioPlaybackEngine`, extended with no new protocol. The curve
that plays, `played`, is a pure, memoized function of (points, fs) computed by `EQDesigner`. So
there is **no stub curve and no "engine not ready" state**.

Per-output memory becomes **slots**, using the shipped composition-root edge pattern:
- the switch is wired at app level, keyed on the device UID with a model-UID fallback;
- it works from the menu bar with the window closed.

The rest of the changes:
- **Persistence and migration:** one atomic `eqStateV2` aggregate; migration keeps an unedited
  built-in unedited.
- **The drag:** stroke-start (not compounding), through a view-model stroke API.
- **Built-ins:** they move into the kit with stable ids, so the "Low Volume" rename needs no alias.
- **Tone:** EQ3 draws the Tone shading; EQ3t is the card only.
- **Founder decisions 25–28:**
  - the graph never depends on Intensity;
  - **no Headroom readout**, with Off as a true, level-matched bypass;
  - **"Bring back edits"** replaces ⌘Z;
  - **Compare is press-and-hold.**

## 1. Disposition of every UI-relevant review finding

**A** = accepted, **R** = rejected, **n/a** = not UI (owned by the DSP lane; listed for completeness).

| Source | Finding | Disp. | What changed here, or why |
|---|---|---|---|
| Arch F1 / Breaker B1 / m10 | The EQ sits inside the Intensity blend, so the graph lies below 100 % | A (decision 25) | The graph has **no Intensity input**, by contract. **Now Playing copy:** `InspectorColumn` `.help("0 % = bit-perfect bypass")` and the "Bypass" caption become false (the EQ still plays at 0 %). New text: help "0 % — Reimagine off (your EQ still plays)", caption "Off". Ships with the chain reorder in EQ1b; I supply the strings. Publishing Intensity at launch (m10) is EQ2's job. |
| Arch F2 / Breaker m8(i) | `points` means opposite things; two new engine protocols | A | The glossary is `base` / `tone` / `points` everywhere. v1's `EQEngineContract` is withdrawn: `AudioPlaybackEngine` gains `publishEQ(points:isOn:)` and `eqSampleRate()` (EQ0). |
| Arch F3, F15–F17; Breaker M1, M3, m1–m7; SOTA #1, #4–#6 | Re-allocation race, ramp, accuracy, precision, Nyquist, gates | n/a | DSP lane. Visible to the UI only as "the graph is true", which their gates guarantee. |
| Arch F4 | v1's `ContentView` recall still fails with the window closed, and fires on a rate change | A | **Withdrawn:** v1's `ContentView` `.onChange`. **Now:** the composition-root edge in `AdaptiveSound.init`, `audio.onOutputIdentityChanged = { [weak eq] in eq?.outputDidChange(to: $0) }`. It fires only on a UID change (DEV-UID adds the hook). The toast is view-level, in the shell overlay (§4.4). |
| Arch F5 | No device UID | A | Slots are keyed by `uid`. `modelUID` is the fallback only when exactly one stored slot has it. The name is stored for display. |
| Arch F6 | The clamp is ungated; the limiter is the real bound | A (copy) | The ceiling's copy no longer claims the clamp's role: "Held at +12 dB — the EQ's ceiling" (§4.3). |
| Arch F7 | Migration would mark an unedited Warm as "Edited" after the re-voice; restore clamps base to ±12 | A | §3.4: the architect's rules exactly. A v1 built-in loads the **re-voiced** points, unedited. Base decodes at ±24. Fixture test per rule. |
| Arch F8 | Two keys can diverge | A | One `eqStateV2 = {version, shared, pinned}`, written atomically. `eqCustomPresetsV1` is unchanged. `eqOutputPresetMapV1` is dropped (never written). |
| Arch F9 | `played` is not an engine method | A | v1's "engine not ready" state, the stub curve and the "re-render sheets on EQ2" step are **removed**. EQ3 depends on EQ1a (the real designer). |
| Arch F10 / Breaker m8(ii) | Compare ≡ Off; v1's Off copy "playing the original" was false | A (decisions 26 + 28) | Compare is a UI gesture: the engine gets `isOn && !isComparing`. New Off and Compare copy and looks in §4.1–4.2. |
| Breaker m8(iii) | "Show Off · level-matched −X dB" | **R** | Under decision 26 Off is a true bypass at matched loudness, so there is no number to show. |
| Arch F11 / Q2 | ⌘Z would be the app's first `UndoManager` | A (decision 27) | v1's founder Q1 (A) is withdrawn. Now: the "Bring back edits" message (§4.5), on the playlist's restore-message pattern. |
| Arch F12 | The shoulder compounds; views write VM arrays | A | v1 said "verbatim". Now: **stroke-start** in `points` space via `beginStroke` / `updateStroke` / `endStroke` / `cancelStroke`. Neighbours follow 0.75 / 0.25 of the way **from where they were at mouse-down**: same feel, deterministic. Esc uses the same snapshot. |
| Arch F13 | Preset ids double as display names | A | `EQBuiltInPreset` (kit) has stable raw ids: `.loudness` displays "Low Volume". No decode alias. |
| Arch F14 | EQ2 and EQ3a both own the VM; EQ3 and EQ3t both draw shading | A | The VM and persistence are **EQ3a only**. EQ3 draws the shading from `highlightedRegion: EQToneRegion?`. EQ3t is the card only. |
| Arch F18 | Per-publish logging floods | A | The VM logs at stroke end only (EQ3a). |
| Arch F19 | Saved My Presets will sound stronger | A | For the founder check only; no UI. |
| Arch §9 | What plays on unpinned outputs? Does a preset choice turn an Off EQ on? | A | Unpinned outputs share the `shared` slot. Any edit turns the EQ on: a drag, a nudge, a Tone move or a preset choice (§4.1). |
| Breaker M2 / SOTA #2 | The curve-on-pink level match is off by up to 3.4–7 dB | A (decision 26) | The engine uses the gated block-spectral predictor (with a curve-estimate fallback for the first ~10 s). The copy says **"matched loudness"**, never "exact". |
| Breaker S2 (§5) | The hidden ±24 base makes a Tone slider look dead on clamped points | A | A **"limited" readout:** a point readout ends "· limited"; the Tone readout adds "· 3 points held at +12"; VoiceOver says "limited" (§4.3). |
| Breaker m9 | float `(e − T) + T ≠ e` | A | Kit "lands exactly" tests use \|Δ\| ≤ 1e-5 (EQ3a). |
| SOTA #3 | Loudness-neutral output gain | A (decision 26) | The Headroom readout is removed everywhere (graph strip, VoiceOver value, sheets, audits). |
| SOTA #3 (sub-point) | Keep −max\|H\| as a "Headroom" figure the graph shows | **R** | Decision 26 removes it. It is a number the user can't act on, and it no longer describes the level they hear. |
| SOTA §6 | Drag-to-ear ≈ 11–21 ms; no rate limit needed | A | The view publishes every pointer sample. The Realizer coalesces latest-wins. No UI throttle. |
| SOTA §7 | At ≥ 88.2 kHz a 20 kHz boost reaches ~29 kHz | n/a | The graph is 20 Hz–20 kHz, matching the decision. Documented in the DSP gate. |

**v1 items kept unchanged** (none was challenged):
- On/Off is `GlassSwitchStyle`, not `CapsuleSwitch`.
- Cards are surface roles (no `GlassCard` type).
- Rename lives in the allow-listed `SaveCustomPresetView.swift`.
- The dark-only handle glow and the centre-zero groove live in `DesignSystemGlassControls.swift`.
- The analyzer silhouette starts at 40 Hz.
- The `R4-EQ-*` / `LAY-EQ-01` audits.
- The fold persists in `@AppStorage("eq.toneFolded.v1")` (the architect confirmed).
- `GlowField` is mounted locally until F1.

## 2. View structure (files)

**Budgets** (`swiftlint --strict`): files ≤ 500 lines, type bodies ≤ 250, functions ≤ 60, lines ≤ 120
characters, cyclomatic complexity ≤ 8. Every new file below is planned at ≤ 250 lines.

**Delete:**

| What | Where | When |
|---|---|---|
| `UI/EQ/EQControlsSection.swift`, `UI/EQ/EQInterpolationPickerView.swift`, `UI/EQ/EQPresetPickerView.swift` | — | EQ3 |
| `@AppStorage("eq.discreteSteps.v1")`, `logInterpolationModeChange` | — | EQ3 |
| `EQRecallBanner` and the device `.onChange` | `EQTabView` | EQ3a (replaced by the edge and the shell toast) |
| `Models/EQPreset.swift` | Moves to the kit as `EQBuiltInPreset` | EQ0 |
| `EQSafetyClamp.swift` | — | EQ2 |

**Change:**

| File | Change |
|---|---|
| `UI/Tabs/EQTabView.swift` | The V1b root: `HStack { EQRail; EQGraphCard }`, Library insets (22 / 22 / 18, gap 20), `GlowField(glows: .libraryGlows)` behind *(superseded by Sprint F1: one `appGlows` field is mounted once in `TabContentView` behind every tab but Now Playing; EQ no longer mounts its own)*. Owns `@State highlightedRegion: EQToneRegion?`. |
| `UI/EQ/FrequencyResponseCanvas*.swift` | Replaced by the `EQGraph*` files. `EQPlotMap` moves to the kit. |
| `UI/EQ/SaveCustomPresetView.swift` | A rename mode; the curve glyph of what will be saved. The path stays allow-listed. |
| `EQViewModel*.swift` | Reshaped to the contract (EQ3a only). Split: `EQViewModel.swift` (state, the single dispatch, memoized `played`), `+Stroke`, `+Presets` (choose, save, rename, delete, bring back), `+Outputs` (pin, unpin, `outputDidChange`, the toast state), `+Persistence` (`eqStateV2` + migration call). |
| `AdaptiveSound.swift` | Edge 5: `audio.onOutputIdentityChanged → eq.outputDidChange(to:)` |
| `ContentView.swift` | `.overlay(alignment: .bottom) { EQOutputToast() }`, beside `QueueToast` |
| `UI/Settings/PureModeSettingsSection.swift` | The "EQ Preset" row reads `eq.current`'s display ("Warm · edited" / "Off"); "Custom" no longer exists (EQ3a) |
| `UI/NowPlaying/InspectorColumn.swift` | The two Intensity strings (decision 25; with EQ1b) |
| `DesignSystemGlassControls.swift` | `CarvedTrack(origin:)` (EQ3t); `EQPointHandle` (the active point: the `iconFill` gradient, a white rim, the dark-only `sliderGlowDark`) (EQ3) |
| `Debug/SheetVariant.swift`, `SheetFixture*` | The EQ worlds (§6) |

**Add**, under `UI/EQ/` unless noted:

| File | PR | Contents |
|---|---|---|
| `EQRail.swift` | EQ3 | The left column: `EQEqualizerCard` (the title + On/Off switch row, then the presets list), then the Tone slot (EQ3t's card) |
| `EQPresetList.swift` | EQ3 | `NavSectionHeader` "Presets" and "My Presets" (+ = Save Current as Preset…); rows; ↑/↓ via `ListKeyboardCursor`; a context menu; `.onDeleteCommand` |
| `EQCurveGlyph.swift` | EQ3 | The mini curve of 31 points (rail rows, the Save sheet) |
| `EQGraphCard.swift` | EQ3 | `libraryDetailCard`: `EQGraphHeader` (the name + Edited / Off chip, the "Used on" pin, Compare, Reset, Save; reflows to two rows via `ViewThatFits`) over the lens graph and the Bring-back message |
| `EQGraph.swift` | EQ3 | The canvas host: the stroke gesture, keyboard, focus |
| `EQGraph+Drawing.swift` | EQ3 | Grid, regions, silhouette (from 40 Hz), **Tone shading** (`highlightedRegion`), ghost, ceiling, played curve, beads, Off / Compare dimming |
| `EQGraph+Overlay.swift` | EQ3 | The readout strip, the drag tag, `EQPointHandle` |
| `EQGraph+Accessibility.swift` | EQ3 | The 31 adjustable children (today's, moved), the container value |
| `EQCompareButton.swift` | EQ3 | Press-and-hold Compare (§4.2) |
| `EQBringBackMessage.swift` | EQ3 | The decision 27 message (§4.5) |
| `UI/Shell/EQOutputToast.swift` | EQ3a | The output-switch toast: `QueueToast`'s persistent-host recipe, tap opens the EQ tab |
| `UI/Controls/HeaderPillButton.swift` | EQ3 | A plain button in `headerPillChrome(_:)`, with the press opacity, hover wash and `controlFocusRing`. Consumers: Reset, the "Used on" pin, the Compare face. |
| `UI/EQ/EQToneCard.swift` | EQ3t | The header (fold chip, "TONE", Reset Tone), five rows, the one-line folded form; writes `highlightedRegion` |
| `Sources/EQEditKit/*` | EQ0 types; EQ3a logic | Per the contract: `EQBands`, `EQToneRegion`, `EQCurve`, `EQBuiltInPreset`, `EQPresetRef`, `EQState`, `EQOutputKey`, `EQStore`, `EQMigration`, `EQStroke`, `EQPlayed`, `EQPlotMap`, plus `EQState.offersBringBack(switchingTo:)` |

## 3. State model (the contract, plus the UI-only state)

### 3.1 Owners

- **`EQViewModel`**: `@MainActor @Observable`, built once in `AdaptiveSound.init`. Its API is the
  architect's §2: `store`, `current`, `played`, `isComparing`, `choose`, `setOn`, `reset`, the stroke
  API, `nudge`, `setTone`, `resetTone`, `save`, `rename`, `delete`, `pinCurrentOutput`,
  `unpinCurrentOutput`, `outputDidChange`.
- **Dispatch** happens at one point only:
  `engine.publishEQ(points: current.curve.points, isOn: current.isOn && !isComparing)`.
- **This plan adds three VM members:**

  | Member | Meaning |
  |---|---|
  | `bringBack: EQState?` + `bringBackEdits()` | The one-level restore point (§4.5) |
  | `outputToast: (message, token)?` | Raised by `outputDidChange` when the slot's state differs (§4.4) |
  | `beginCompare()` / `endCompare()` | Set `isComparing`. Release rules in §4.2. |

- **View state, never in the model:**

  | State | Owner |
  |---|---|
  | `highlightedRegion` | `EQTabView` |
  | `keyboardBand` and focus | `EQGraph` |
  | The fold | `@AppStorage` in `EQToneCard` |
  | The message's visibility timer | `EQBringBackMessage` |

### 3.2 Derived values, never stored

- `points`;
- `isEdited` (any |Δ| > 0.05 dB against the preset's points; Tone ≠ 0 counts);
- `played` (memoized on (points, fs); lazy, only while the graph is visible);
- `isLimited(band)`.

### 3.3 Actions

| Action | Effect |
|---|---|
| Choose a preset | base = preset points, tone = 0, **isOn = true** (any edit turns the EQ on). If `current.offersBringBack(switchingTo:)`, which means current is edited and the preset differs, then `bringBack = current`. |
| Stroke (drag) | `beginStroke(band)` snapshots; `updateStroke` applies `EQStroke` (the band at the pointer; neighbours ±1 / ±2 at 0.75 / 0.25 from the snapshot; the gap fill for fast sweeps); `endStroke` persists and logs once; `cancelStroke` (Esc) restores the snapshot. The first sample sets isOn = true and clears `bringBack`. |
| Keyboard ↑/↓ | `nudge(band, ±0.5)` (⇧ ±3): one band, persisted per press |
| Tone | `setTone` / `resetTone`. Choosing a preset resets Tone; Save bakes it in (`baked()`). |
| Reset (header) | `reset()`, the same as re-choosing the preset. It doesn't offer Bring back, since resetting is the user's explicit intent. |
| Save / rename / delete (My Presets) | `EQStore` fix-ups (pinned slots that point at a renamed or deleted preset) |
| Pin / unpin | Pin copies the current state into `pinned[uid]`. **Unpin copies the slot into `shared`, so there is no audible jump.** The pin's label reads the current output's name. |

### 3.4 Persistence and migration (EQ3a)

- **One aggregate**, `eqStateV2`, through the injected `defaults` (semgrep `persist-one-location`). It
  is written atomically on discrete actions and at stroke end, never per drag sample.
- **Migration** (`EQMigration.store(fromV1:customPresets:)`, the architect's rules):
  1. A v1 built-in is that preset's **current (re-voiced)** points, unedited.
  2. A v1 nil whose gains equal a saved preset becomes `.mine(name)`.
  3. Otherwise it becomes `.builtIn(.flat)`, edited, with base = the v1 gains.
  - In every case `isOn` = true.
  - Decode limits: base ±24, tone ±12, finite values, exact counts; anything invalid becomes flat.
  - `eqLiveStateV1` is kept for one release, for a downgrade.
- **The fold:** `@AppStorage("eq.toneFolded.v1")`, read through `.defaultAppStorage`, with no
  `store:` argument.

## 4. The states and their copy

### 4.1 Off (decision 26: a true bypass, matched loudness)

- **The rail switch** is Off.
- **The header** keeps the preset name, with an "Off" chip (`labelSecondary` on `badgeFill`) in
  place of "Edited".
- **The graph:**
  - the beads dim to `labelTertiary`;
  - **the played curve lies flat at 0 dB**, in `labelTertiary`;
  - Tone shading and the ceiling are hidden.
- **The strip reads: "Equalizer off · the song plays without it, at matched loudness".**
  - v1's "playing the original" is gone. "Original" belongs to Pure Mode, the bit-perfect path, and
    Off is the EQ stage only.
- **Compare** is disabled; there is nothing to compare.
- **Any edit turns the EQ on:** a drag, a nudge, a Tone move or a preset choice. The switch animates
  On (no easing under Reduce Motion), and VoiceOver announces "Equalizer on".

### 4.2 Compare (decision 28: press and hold)

**Its look while held:**
- **The pill** (the `EQCompareButton` face) takes the `.active` tone (teal edge + `controlActiveFill`);
  its label stays "Compare", so nothing shifts.
- **The graph:** the played curve lies flat at 0 (that is what plays). **The EQ'd curve is ghosted**
  (dashed `accentFill`) so you see what you're missing. The beads dim.
- **The strip reads "Without the EQ · matched loudness · release to return".**
- **On release,** everything returns at once.

**Input:**

| Input | Behaviour |
|---|---|
| **Mouse** | Press = `beginCompare`; release (anywhere) = `endCompare` |
| **Keyboard** | The pill is a Tab stop. **Hold Return** while it is focused: `.onKeyPress(.return, phases: [.down, .up])`; repeats are ignored; Space stays play / pause. A quick tap gives a short blip, which is the honest result of a hold gesture. |
| **VoiceOver** | The pill is a **toggle** (`.isToggle`, value "on" / "off"). Activating latches Compare on and announces "Comparing: hearing the song without the EQ, matched loudness". It releases on a second activation. |

**Always released when:**
- the window resigns key or the app deactivates;
- the tab changes;
- **Esc** is pressed;
- any edit starts;
- the output changes;
- VoiceOver focus leaves the pill.

Compare can never stick on. It is disabled while Off and in Pure Mode.

### 4.3 The +12 dB ceiling and "limited" (decision 23, revised by 26)

- **The amber dashed line** (`meterHot`) shows at +12 whenever any point sits at +12.
- **During a stroke past +12:**
  - the point pins at +12;
  - your pointer's position is **ghosted** (a dashed ring plus a dashed requested curve);
  - the strip reads **"Held at +12 dB — the EQ's ceiling"** (`meterHotText`);
  - VoiceOver hears this once per stroke.
- **A point that Tone pushes past ±12 is "limited":**
  - the readout reads "1 kHz · +12.0 dB · limited";
  - during a Tone drag the strip adds "· 3 points held at +12";
  - the VoiceOver value adds "limited". The slider never looks dead without a reason.
- **There is no Headroom readout anywhere** (decision 26).

### 4.4 The output switch (slots; decision 28's default)

- **What happens:** the edge fires on a UID change, and `outputDidChange` makes the matching slot
  current: the pinned slot, else `shared`.
- **Copy:** if the state differs from the one before, `outputToast` = "AirPods Pro · Late Night"
  (with " · edited" when so).
- **Where:** in the shell overlay (`EQOutputToast`), on every tab, for 3 s.
- **Interaction:** tapping opens the EQ tab. VoiceOver announces it, keyed on the token (as in
  `QueueToast`).
- **With the window closed,** the slot still switches, and there is simply no toast.

### 4.5 "Bring back edits" (decision 27)

**Where.** A capsule at the bottom-centre of the graph card, floating over the lens's lower edge.
- It uses `.glassPanel(.overlay(.ultraThin), in: Capsule())` + a hairline, the recipe of the
  playlist's "Restore previous queue" and `QueueToast`.
- It shows only on the EQ tab, the only place a preset switch happens.

**Copy.** "Edits to Warm set aside" + the button **"Bring back edits"** (`accentForeground`).

**How long.**
- **6 s**, the playlist restore-toast's duration, with a token-guarded cancel-and-respawn timer.
- The timer **pauses while the capsule is hovered or holds keyboard focus.**
- It is **re-armed** on each further preset switch.
  - Arrowing through presets to audition them keeps offering the *original* edits:
    `bringBack` is only replaced when the state being left is itself edited.

**What it restores.** The whole slot state from before the switch: the preset ref, base, tone and
isOn. Then `bringBack` = nil and the capsule hides.

**Cleared when:** the edits are brought back, a new edit is made (stroke, nudge, Tone), Save is used,
or the output changes. It is never persisted.

**Keyboard and VoiceOver.**
- **Show:** VoiceOver announces "Switched to Vocal. Edits to Warm can be brought back."
- **The button** is a Tab stop while visible (Return activates it).
- **No time limit for keyboard and VoiceOver users:** while `bringBack` exists, the **presets
  list's context menu** and a **VoiceOver custom action** on the list ("Bring back edits") offer the
  same restore after the capsule is gone (WCAG 2.2.1).

### 4.6 Pure Mode

- **The graph** looks as it does when Off.
- **The strip reads "Pure Mode is on — the EQ doesn't play. Switch to Enhanced to hear it."**, with an
  "Open Settings" link button (`selectedTab = .settings`).
- **Editing** stays allowed; it doesn't leave Pure Mode.
- **Compare** is disabled.

## 5. Keyboard, VoiceOver and layout (carried from v1; updated)

### 5.1 Tab order

1. The Equalizer switch.
2. The presets list (one stop).
3. My Presets "+".
4. Tone: the fold chip, Reset Tone, then the five sliders (or just the chips when folded).
5. The header: the "Used on" pin, Compare, Reset, Save.
6. The graph (one stop).
7. The Bring-back button, while visible.

`.defaultFocus` goes to the presets list, matching the Library rail.

### 5.2 The presets list

| Key | Action |
|---|---|
| ↑/↓ | Choose a preset; it plays at once. Bring back covers lost edits. |
| Return | Rename (My Presets) |
| ⌫ via `.onDeleteCommand` | Delete (My Presets), with a native confirmation |
| Esc | Bubbles |

The ring shows in keyboard mode only (`keyboardCursorRing`).

### 5.3 The graph

| Key | Action |
|---|---|
| ←/→ | Move the band cursor (handled at the ends) |
| Home / End | The first / last band |
| ↑/↓ | ±0.5 dB |
| ⇧↑/⇧↓ | ±3 dB |
| ⌫ via `.onDeleteCommand` | This band back to the preset's value |
| Esc | Cancels a stroke, or releases Compare; otherwise bubbles |

- **The cursor follows the click.** `beginStroke` sets `keyboardBand` and takes focus.
- **The ring** shows only while `graphFocused && showsKeyboardFocus`.
- **Space** stays play / pause.

### 5.4 VoiceOver

- **Graph:** a container "Equalizer graph", value "Warm, edited" (or "Off" / "Comparing" / "Pure
  Mode").
  - It has 31 adjustable children, stepping ±0.5: "1 kilohertz", "plus 4 decibels". A child adds
    "plays plus 3.8" only when |played − set| ≥ 0.2, and "limited" when clamped.
  - Custom action: "Reset band".
- **Tone sliders:** `CarvedSlider`, labelled "Presence tone, 2 to 6 kilohertz".
- **The fold chip:** value "collapsed" / "expanded".
- **The "Used on" pin:** a toggle.

### 5.5 The kit

| Piece | Use? |
|---|---|
| `ListKeyboardCursor` | Yes (presets) |
| `ListSelection` | No (single-select) |
| `GridKeyboardCursor`, `FillGridLayout`, `FixedRowReveal`, `FilterPill`, `CardFocus` | No |
| `TypeSelectBuffer` | Optional |

### 5.6 Layout

**The height budget** is the window − chrome 60 − footer 64 − insets 40: **556 pt at 1000×720, 476 pt
at 880×640.**

**The rail:**
- Width 234 (`sidebarIdeal`), shared with Library.
- Preset rows at **28 pt** via `NavRow(rowHeight:)` (default 38) with a `leading` builder for the
  curve glyph; Tone rows at **29 pt**.
- With 7 built-ins + 2 My Presets, both cards fit at 1000×720 (the prototype measured 553 of 556).
- **More presets, or 880×640 with Tone open:** the Equalizer card scrolls inside itself (the
  `huggingGlassPanel` rule, plus a bottom fade and the selected row scrolled into view), and Tone
  stays pinned and whole.
- **Folded** (the user's choice, remembered), 880×640 shows every built-in + 2 My Presets without
  scrolling.

**The graph:**
- It fills the card below the header. ±12 dB plus a 3 dB margin.
- The plot is ≈ 300 pt at 880×640.
- The band pitch is ≈ 26 pt (880) and ≈ 30 pt (1000). Each band's column is its hit area.

**Large text.** macOS 26 ignores Dynamic Type, so the layout holds by structure:
- the header uses `ViewThatFits` (one row → two);
- names use `lineLimit(1)` + middle truncation, with the full name in `.help`;
- Tone labels sit in a fixed 68 pt column.

## 6. R4 and the picture sheets

**Audits** (`Tests/DesignTokenKitTests/EQAuditTests.swift`, both appearances plus Increase Contrast):

| ID | Check |
|---|---|
| **R4-EQ-01** | The curve and beads (`accentFill`) ≥ 3:1 on the lens over the glow, the silhouette peak and the Tone-shading peak |
| **R4-EQ-02** | The 0 dB line, axis, neutral rings **and the Off / Compare dimmed curve and beads** (`labelTertiary`, full strength) ≥ 3:1 |
| **R4-EQ-03** | The ceiling line (`meterHot`) ≥ 3:1; its text (`meterHotText`) AA on the lens |
| **R4-EQ-04** | The drag tag (`label` on `panelFill` over the lens) AA; `EQPointHandle` ≥ 3:1 |
| **R4-FOCUS-03** | `focusRing` on the lens |
| **R4-CHIP** | The "Edited" / "Off" chips on the panel (extend the backdrop list if it lacks them) |

**LAY-EQ-01.** `EQLayout` metrics go in DesignTokenKit (the `NowPlayingLayout` precedent), and the
test checks the arithmetic:
- at 880×640 with Tone folded, everything fits without a scroll;
- at 1000×720 open, both cards fit;
- the plot is ≥ 280 pt.

**Sheets** (EQ only; dark and light at 1000×720 unless noted). States are seeded through a debug
environment value, like `SheetGridStates`:
- `eq-drag` (the readout, neighbours following);
- `eq-ceiling` (with "limited");
- `eq-ring`;
- `eq-ring-rail`;
- `eq-tone` (shading, with "· N points held");
- `eq-folded` at 880×640;
- `eq-many` at 880×640 (12 My Presets, a 40-character name);
- `eq-off`;
- `eq-compare` (held);
- `eq-pure`.

**Founder-only cells.** The Bring-back capsule and `EQOutputToast` are Materials (`.overlay`), which
the renderer can't draw.

## 7. PR split, sizes and lanes (the architect's §8)

| PR | UI scope | Size | Depends on |
|---|---|---|---|
| **EQ0** | Kit value types (incl. `EQBuiltInPreset` with stable ids, `EQPlotMap`); `AudioPlaybackEngine.publishEQ(points:isOn:)` and `eqSampleRate()`, plus `MockAudioEngine` and `SheetEngine`. **No VM change.** | S 0.5 | — |
| **DEV-UID** | `uid` / `modelUID` → `AudioDeviceModel`; the `onOutputIdentityChanged` hook | S 0.5 | — |
| **EQ3a** | Kit logic (`EQStroke`, the edited rule, `offersBringBack`, `EQStore` slots + resolution, `EQMigration`) + tests (migration fixtures, slot resolution, rename/delete fix-ups, stroke numbers, 1e-5 landing). The VM reshape (stroke API, single dispatch, memoized `played`, `bringBack`, compare begin/end, `outputToast`); `eqStateV2`; Edge 5 + `EQOutputToast`; the Settings "EQ Preset" consumer; stroke-end logging. Break-it (data and migration). | M 2 | EQ0, DEV-UID |
| **EQ3** | The V1b screen: `EQTabView`, `EQRail` + `EQPresetList`, `EQGraphCard` + header (`HeaderPillButton`, `EQCompareButton`), the `EQGraph*` rewrite drawing the real `played` (with Tone shading from `highlightedRegion`), the Off / Compare / Pure / ceiling / limited states, `EQBringBackMessage`; keyboard and VoiceOver; deleting the old controls; R4-EQ-01…04, R4-FOCUS-03, LAY-EQ-01, the sheets; the live keyboard pass | L 3 (at the top of L) | EQ3a, EQ1a |
| **EQ3t** | Card only: `EQToneCard`, `CarvedTrack(origin:)`, the fold (`@AppStorage`), the rows writing `highlightedRegion`; the `eq-tone` and `eq-folded` sheets | M 2 (could close at 1.5) | EQ3a (∥ EQ3) |
| **EQ4** | My Presets rename (the Save sheet's mode), Delete; the "Used on" pin UI + the context-menu "Use on <output>"; the re-voice (DSP, founder listening) | M 2 | EQ2, EQ3 |
| *EQ1b (DSP)* | Carries the two Now Playing Intensity strings (decision 25) | — | — |

**Lanes:**
- **UI:** EQ3a → (EQ3 ∥ EQ3t), then EQ4 last.
- **DSP:** EQ1a → EQ1b → EQ2.
- **From day 1:** EQ0 and DEV-UID.
- **UI total:** ≈ 7 points (EQ3a 2 + EQ3 3 + EQ3t 2) + EQ4 2.
- **Everything builds against EQ0's contract.** EQ3 needs only EQ1a's `EQDesigner` to draw truth, so
  there is no fake curve and no sheet re-render later.

## 8. Founder questions

None remain for the UI. Decisions 25–28 and the pinned-output default answered v1's three questions.

**For the founder check** (no answer needed):
- Saved My Presets will sound stronger. The old clamp had shrunk them.
