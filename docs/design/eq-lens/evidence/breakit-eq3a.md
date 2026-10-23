# EQ3a break-it — adversarial pass

Target: `feat/s10-8-eq` @ `1c5c3b8` (EQ3a: the EQ’s editing logic, view model, `eqStateV2` persistence,
the v1 migration, slots, Edge 5 and the output toast). Branch with the red tests:
`test/s10-8-eq3a-break-it` @ `5b91e14` (no product code changed).

How each finding is proven:

- **Kit:** red swift-testing tests in `Tests/EQEditKitTests/EQBreakItEQ3aTests.swift` (BRK-01..03).
- **View model:** the app target can’t be imported by a test target, so `.breakit-scratch/vmharness/`
  (uncommitted, in this worktree) compiles the REAL `EQViewModel.swift`, `+Persistence`, `+Stroke` and
  the kit, copied verbatim by `run.sh`, against a stub `AudioViewModel`, a verbatim copy of
  `ShellToastSlot`, and temporary `UserDefaults` suites that record every write. Scenario ids (A1, B1,
  …) are the harness’s `BROKEN` / `HOLDS` lines; its log is `.breakit-scratch/harness-run.log`.
- **Code reading:** only for the toast-view items (marked).
- **Data rule:** never touched the app’s domain or Application Support. Only `breakit.eq3a.*` temp
  suites were used, and their plists were removed.

**No BLOCKER and no MAJOR.** The migration of real users’ data is correct (see “What held up”). Every
finding is MINOR, and several are LATENT: in EQ3a nothing can create a pin (pin / unpin is EQ4) and the
migration writes none, so every output plays `shared`, the slot never changes, and the output toast
can’t fire yet. Those become live with EQ4. One of them, finding 5 (C1), would then be MAJOR.

## Findings

| # | Severity | Claim attacked | Repro / test | Expected | Actual |
|---|---|---|---|---|---|
| 1 | MINOR (live) | Stroke: “Esc restores the snapshot”; persistence: “written at stroke end” | Harness **A1, A2**. Drag on the graph; press ↑ while the mouse is still down (the first sample focuses the graph, so ↑ reaches `nudge`); drag on; press Esc; relaunch. | The nudge is either kept or refused. After Esc, the relaunch restores what plays (Warm). | The next drag sample silently undoes the nudge (band 20: 3.94 → 2.94). `nudge` persisted the mid-stroke curve, and `cancelStroke` restores `before` without persisting. The relaunch plays **“Warm · edited”** (the mid-stroke curve), not Warm. |
| 2 | MINOR (live; same root cause as 1) | Stroke API, and the “Edited” label | Harness **S0**. Choose Warm; mouse-down and drag; with Full Keyboard Access, Tab to the picker and choose Vocal; one more drag sample; release. | One of two outcomes: the choice ends the drag and Vocal plays, or the label still names the curve that plays. | The label reads **“Vocal · edited”**, but band 3 plays Warm’s +7.88 dB (Vocal’s is 0). The stroke re-applies its mouse-down (Warm) curve under the new preset ref, and `endStroke` persists it. |
| 3 | MINOR (likely during this sprint) | Migration “runs once”; “`eqLiveStateV1` kept for a downgrade” | Harness **B1**. v1 `Warm`; launch v2 (migrates); downgrade, and the v1 build chooses Vocal (writes `eqLiveStateV1`); launch v2 again. | Vocal, the last EQ the user chose. | **Warm.** Any EQ chosen or edited in the older build is silently discarded on re-upgrade, because `eqStateV2` exists. The reverse also holds: the downgraded build plays the pre-upgrade EQ, never the latest v2 one. The founder alternating `main` (v1) and `feat/s10-8-eq` (v2) builds hits this. |
| 4 | MINOR (live) | Edge 5: “`outputDidChange` ends a drag first” | Harness **D1**. Drag; the output changes mid-drag (Bluetooth connect, FOLLOW mode); keep dragging. | The drag continues when the slot doesn’t change. In EQ3a that is always the case: everything plays `shared`. | The stroke ends. Every later sample is ignored until mouse-up (band 14 stays 0, expected +6), so the graph “freezes” mid-gesture. |
| 5 | MINOR (latent; MAJOR once EQ4 adds pins) | Slots plus Save: “edits write to the current output’s slot” | Harness **C1**. Speakers on edited Warm (shared), AirPods pinned to Vocal. Open “Save as Custom…”; AirPods connect while the modal sheet is up; type a name; Save. | “My Warm” = the edited Warm the user was looking at. | “My Warm” = **Vocal’s points**, and the AirPods slot is rewritten to `.mine("My Warm")`. The edited Warm stays unsaved. `save(as:)` reads `current` at Save time, not at sheet-open time. |
| 6 | MINOR (latent) | Toast: “none at launch” | Harness **E2**. Speakers (Warm), then every output gone (`nil`), then pinned AirPods (Vocal). | A toast, “AirPods Pro · Vocal”: the sound changed. | No toast. `hadOutput = output != nil` treats “no output right now” as launch. |
| 7 | MINOR (latent; code reading) | ui-plan §4.4: “with the window closed … simply no toast” | `outputDidChange` always calls `outputToast.show`. `ShellToastHost` renders a non-nil `toast` and announces it in `.onAppear`. Switch outputs with the window closed, then reopen it from the menu bar within 3 s. | Nothing shows. | The stale toast appears and VoiceOver announces it. |
| 8 | MINOR (latent; code reading) | One shell toast at a time | `ContentView` adds `QueueToast` and `EQOutputToast` as two `.overlay(alignment: .bottom)` siblings, both padded `Spacing.medium` from the bottom. Add to the queue, then switch output within 3 s. | The capsules are queued or stacked. | Two glass capsules overlap at the same spot, and both texts are unreadable. |
| 9 | MINOR (corrupt data; latent) | `EQStore` lenient decode | **BRK-01**. One pin’s `key` loses its `uid`. | The intact AirPods pin survives. | Every pin is dropped: `try?` covers the whole `[String: PinnedSlot]` map. The next write (any edit) makes the loss permanent. |
| 10 | MINOR (corrupt data; latent until `setOn`, EQ3) | `EQState` lenient decode (“keeping the user’s sound where it can”) | **BRK-02**. An Off, edited Warm slot whose stored curve is damaged (short `base`). | It stays Off: decision 25 makes “Intensity 0 + EQ Off” the bit-perfect path. | `.flat`, which is **ON**. A damaged curve silently turns the EQ on. A missing `isOn` key likewise discards the slot’s curve. |
| 11 | MINOR (robustness; not reachable in-app today) | `EQState(choosing:myPresets:)`: “`nil` for a My Preset that no longer exists” | **BRK-03** (exit test). `EQState(choosing: .mine("Short"), myPresets: ["Short": [1, 2, 3]])` | `nil`. The kit elsewhere tolerates wrong-count presets: `isEdited` never matches them, and the migration skips them. | **SIGTRAP** in `EQCurve.init(base:tone:)`’s precondition. Only `loadMyPresets`’ filter keeps the app safe, so EQ4’s My Presets code must never bypass it. |
| 12 | MINOR (UX) | Names: Unicode, empty, whitespace, a preset named like a built-in | Harness **N1, N2**. Save a My Preset as “Warm”. Save as `"\n"`. | Either distinguishable from the built-in, or refused. | `.mine("Warm")` reads exactly “Warm” in the picker’s line, the Settings row and the toast (next to the built-in Warm). A newline-only name is accepted (`trimmingCharacters(in: .whitespaces)`, pre-existing from v1). Empty and space-only names are correctly refused. |

### Suggested fixes (the builder’s call; nothing here is applied)

- **1 + 2 (one root cause): a discrete edit doesn’t own the slot while a stroke does.**
  - Have `choose`, `nudge` and `save` call `endStroke()` first, or ignore them while `stroke != nil`.
  - Make `cancelStroke` persist whenever anything was persisted since `beginStroke`.
- **3: carry v1 edits across the round trip.**
  - Store the migrated `eqLiveStateV1` bytes, or their hash, inside `eqStateV2`.
  - At load, re-migrate the shared slot when `eqLiveStateV1` no longer matches.
  - Optionally, mirror the shared slot back into `eqLiveStateV1` on each persist (`presetRaw` = the id
    for an unedited built-in, else nil; `bandGains` = points), so a downgrade hears the latest EQ.
- **4:** end the stroke only when the slot id changes: `store.slotID(for: key) != store.slotID(for: output)`.
- **5:** snapshot the state and its slot id when the Save sheet opens and save that snapshot, or dismiss
  the sheet in `outputDidChange` when the slot changes.
- **6:** replace `hadOutput` with a one-way `hasSeenOutput` flag.
- **7:** don’t raise the toast while no window is up, or dismiss it when the shell (re)appears.
- **8:** one shell toast host that queues, or stack the two capsules.
- **9:** decode pins one entry at a time, dropping only the unreadable entry.
- **10:** decode `isOn` and the preset ref independently of the curve, so a bad curve falls back to the
  reference (or Flat) but keeps On/Off.
- **11:** in `init(choosing:)`, return nil for `points.count != EQBands.count` or a non-finite value.
- **12:** reserve the built-in display names for My Presets, or suffix them. Trim `.whitespacesAndNewlines`.

### Observations (not filed as bugs)

- **The model-UID fallback writes into the other unit’s pin** (harness L).
  - Repro: AirPods #2 plays AirPods #1’s pin; choosing Studio there changes #1’s pin to Studio.
  - This is the F5 design (“a second unit of the pinned model plays that pin”), but EQ4 should confirm
    that edits on unit 2 are meant to rewrite unit 1’s memory.
  - It also covers a USB DAC moved to another port, which is the main reason for the fallback.
- **“First name alphabetically” (migration rule 2) is code-point order.** With `apple` and `Zed`,
  `Zed` wins (probe). The real claim, the same resolution every time, holds. Don’t “fix” it with a
  locale-aware compare: that would make the result depend on the locale.
- **An Off → Off output switch toasts.** “AirPods Pro · Off” shows when only the preset under Off
  differs, so nothing audible changed. This matches ui-plan §4.4 (“if the state differs”).
- **A click on the graph is an edit.** `DragGesture(minimumDistance: 0)` turns the first sample into a
  stroke, so clicking only to focus the graph for the arrow keys changes 5 bands. v1 behaved the same
  way, so this isn’t a regression, but EQ3 may want a click-to-focus that doesn’t draw.

## What held up

- **Migration (v1 → v2), checked against v1’s own writer at `d3abd8e`.**
  - Every v1 edit path (drag, keyboard nudge, VoiceOver) went through `commitCustomBandEdits`, which
    sets `selectedPreset = nil`. So `presetRaw != nil` ⇒ unedited, and rule 1 is sound.
  - v1’s `EQPreset.gains` and today’s `EQBuiltInPreset.points` use identical formulas at identical ISO
    centres, so the reference plays exactly what v1 played.
  - v1’s per-output map was indeed never written.
  - Probed malformed inputs, all handled correctly:
    - **Flat:** 30 or 32 gains, a `NaN` token or string, `1e39`, gains as strings, `presetRaw` as a
      number, an array root, `{}`.
    - **Clamped to ±12:** `1e30`, matching v1’s restore.
    - **Ignored:** extra keys.
    - **Rules 2–3:** an unknown, lowercase or empty `presetRaw`, and a null `presetRaw` (an edit).
    - The EQ is always on.
  - The migration writes `eqStateV2` exactly once at load (G0) and never again (G1). `eqLiveStateV1`
    is left in place (B0).
  - Corrupt v2 plays Flat and stays on disk; nothing writes it without a user action (H0, H1, G4).
- **Canonical form.** A built-in back within 0.05 dB with Tone 0 becomes the reference, and a re-voice
  reaches unedited slots, shared and pinned, but not edited ones. A `.mine` reference left dangling
  at load becomes an edited Flat with its curve kept: the kit tests plus `loadStore`’s re-point.
- **Slots.**
  - Exact UID first; a model UID only when exactly one pin has it; otherwise shared.
  - Unpinnable outputs (`CADefaultDeviceAggregate-…`, an empty UID) always play shared.
  - Rapid output switching mid-drag: the stroke lands only in the slot it began on, is persisted at
    the switch, and the new output’s pin is untouched (R0–R2).
  - A pinned UID that goes away and comes back gets its pin again (E1, R).
- **Stroke.** `setPoint` lands within 1e-5 under any Tone. There is no compounding. Esc restores the
  snapshot exactly (I0), and Esc with no drag passes on (I1).
- **Persistence cadence.**
  - 60 drag samples write nothing (G2); stroke end writes once (G3).
  - An output change with no drag writes nothing (G4).
  - Each aggregate is one key, so writes are atomic.
  - Save writes My Presets before the store, so a crash in between can’t leave a dangling reference.
- **Edge 5.**
  - **Re-reads:** rate, buffer and rename re-reads don’t fire (UID-only `isOutputChange`; `refreshDevices`
    re-selecting the same UID doesn’t either).
  - **Launch:** no toast at launch (E0), and a launch with no output plays shared with no toast.
  - **Copy:** the toast reads “AirPods Pro · Vocal” (E1).
  - **Wiring:** the hook is wired in `AdaptiveSound.init`, before `initializeEngine` (run from
    `ContentView.onAppear`) first sets `selectedDevice`. The first output therefore reaches the view
    model, and with the window closed too.
- **Swift 6 and `@Observable`.**
  - No `didSet` self-assign: `selectedDevice.didSet` only announces, and `ShellToastSlot` has no `didSet`.
  - Everything is `@MainActor`, and the kit types are `Sendable` values.
  - The toast never writes state, so there is no toast/edit write race.

## Re-run

- `swift test --filter EQBreakItEQ3aTests`: 3 red (BRK-01..03).
- `.breakit-scratch/vmharness/run.sh` re-copies the current kit and view-model sources, then builds and
  runs the scenarios. Today it prints 7 `BROKEN` lines (A1, A2, B1, C1, D1, E2, S0) and exits 1. It
  removes its temporary plists.
- Full `swift test` on `test/s10-8-eq3a-break-it`: **exit code 1**. 496 tests in 78 suites ran, and only
  the 3 BRK tests are red (4 issues). Log: `.breakit-scratch/swift-test.log`.
