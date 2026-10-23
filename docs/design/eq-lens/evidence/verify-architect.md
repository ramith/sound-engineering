# Sprint EQ: architect verify pass (the one re-check)

*2026-10-10. I read `dsp/dsp-plan-v2.md`, `ui/ui-plan-v2.md` and plan §B 25–28 on `feat/s10-8-eq` @ c15f183.
Code claims were re-checked read-only in the main checkout; nothing was built or edited.*

## 1. Findings F1–F19 and §3/§6/§7/§9

| # | Status | Evidence / what remains |
|---|---|---|
| F1 Intensity | **CLOSED** | Decision 25. DSP §5 has the P0–P3 paths, so the early return (`DSPKernel.cpp:158-164`) now requires `eqIdentity`. Gate `EQ_ResponseIndependentOfIntensity` (r ∈ {0, 0.2, 0.5, 1}). Launch publish (§5.4). The Now Playing strings come from UI v2 §1. *Owner conflict: see A3.* |
| F2 One contract | **CLOSED** | Both plans use `base` / `tone` / `points` and extend the existing `AudioPlaybackEngine` (DSP §8, UI §0/§3.1). |
| F3 Re-allocation | **CLOSED** | `reinitializeKernel` runs on the Realizer queue. It re-solves at the new fs, re-derives crossfeed (`Realizer.mm:319-322`), snaps on first adopt and holds on an fs mismatch (DSP §6). Gates include `Realizer_ReinitDuringDrain` (tsan) and the `VerifyAUGraph` 2→6→2 case. |
| F4 Recall | **CLOSED** | Edge 5 in `AdaptiveSound.init`, fired on a UID change, works with the window closed (UI §1, §4.4). The launch order holds: `selectedDevice` is set before `isEngineReady` and `onEngineReady` (`AudioViewModel+Lifecycle.swift:46-62`), so the slot is resolved before the first real publish. |
| F5 UID | **CLOSED** | DEV-UID; UID key, and ModelUID only when it is unique (UI §1). *Ownership: see A1.* |
| F6 Safety | **CLOSED** | C-ABI validation; script and `.gitignore` removed in EQ2. The guarantee is restated as "loudness ±0.11 dB, peaks bounded by the −1 dBTP limiter". `EQ_Limiter_HoldsAfterCut` and `Safety_EQToggle_AfterNormaliserAdapted` are added. |
| F7 Migration | **PARTIAL** | The three v1 rules are adopted verbatim (UI §3.4). But an unedited built-in is then *stored as a frozen `base`*, so EQ4's re-voice brings the bug back. See **N1**. |
| F8 One aggregate | **CLOSED** | `eqStateV2 = {version, shared, pinned}`, written atomically; `eqCustomPresetsV1` unchanged (UI §3.4). |
| F9 Read-back boundary | **CLOSED** | Owner-local designer; `played` lazy and memoised; `Designer_TwoThreads` and `Designer_Timing` (DSP §8/§9, UI §3.2). |
| F10 Compare ≡ Off | **CLOSED** | Decisions 26 + 28: Off is a true bypass, the engine takes `isOn` only, and Compare is `isOn && !isComparing`. *Copy conflict: see A4.* |
| F11 Undo | **CLOSED** | Decision 27: "Bring back edits" on the restore-message pattern, plus a WCAG 2.2.1 alternative path (UI §4.5). |
| F12 Stroke | **CLOSED** | Stroke-start API (`begin` / `update` / `end` / `cancel`); Esc uses the snapshot (UI §3.3). |
| F13 Presets in the kit | **CLOSED** | `EQBuiltInPreset` with stable ids; "Low Volume" is a display name only (UI §1). |
| F14 PR ownership | **PARTIAL** | The VM is EQ3a-only and the shading belongs to EQ3, both closed. But EQ0, DEV-UID, the Realizer and the launch publish are claimed twice or not at all. See A1–A3. |
| F15 `PendingSlot<T>` | **CLOSED** | In EQ1b (DSP §1). |
| F16 One coefficient function | **CLOSED** | `svfBell` and `svfDamping`, header-only, shared by the designer, the read-back and RT (DSP §1). |
| F17 `RtSwappableResource` | **PARTIAL** | "Keep, with one direct test" is in the disposition, but the §9 gate table does not list the test. Add the row. |
| F18 Log flood | **PARTIAL** | The VM logs at stroke end (UI). The per-publish C++ `[QW1]` lines (`Realizer.mm:163`, `AUAudioUnit.mm:414`) are not addressed. EQ1b should rate-limit them or log them at debug level. |
| F19 FYI | **CLOSED** | Both plans carry the founder FYI. |
| §3 RT from smoothed dB | **CLOSED: I accept the rejection** | S2 is measured on every metric. Frozen peak: S1 +6.62 vs S2 +0.00 dB. Time-domain peak at τ 40 ms: S1 +5.4…+6.6 vs S2 ≤ +1.49 dB. Zipper and sidebands are the same (DSP §3.1). S2 restores "RT runs finished coefficients". Bit-exact read-back becomes trivial, since (k, m1) are passed, not recomputed. The extra per-sample divide is costed (2.67 % at 192 k × 8). |
| §6 Safety framing | **CLOSED** | Superseded by decision 26. The limiter stays the bound on every path, P1 included (DSP §5.1). |
| §7 Seams | **CLOSED** | `outputGainDb` is its own field, (k, m1) are per section, and the m0/m2 mix comes later (DSP §1). |
| §9 the-fool | **CLOSED** | Unpinned outputs use `shared`, and any edit turns the EQ on (UI §1, §4.1). |

## 2. Contract alignment: one contract, with these exact mismatches

**These agree:**
- the names (`base`, `tone`, `points`);
- `EQPlayed` = {static `frequencies` (256), `responseDb[256]`, `centreDb[31]`, `sampleRate`}. DSP §8 lists it; UI uses `centreDb` for the "plays +3.8" value and has no Headroom readout;
- `publishEQ(points:isOn:)` and `eqSampleRate()`;
- the VM API and `isOn && !isComparing`;
- the engine rules: On = (k, m1) with −ΔL; Off = identity;
- the track profile flowing playback → Realizer only. It is engine-internal, and the UI never sees it.

**Mismatches to fix (text edits; no design change):**

- **A1. EQ0 and DEV-UID have two claimants and no named owner.**
  - UI v2 §7 lists both as "UI scope" rows; DSP v2 §10 lists them as "day 1" with no lane.
  - Per the coordinator, the **DSP lane owns EQ0 and DEV-UID**, so UI v2 §7 should mark them "consumed".
  - Move `EQPlotMap` out of EQ0 into **EQ3a**, so the DSP agent doesn't move UI drawing code.
  - EQ0 also carries the `Models/EQPreset.swift` → kit move (UI §2) and the `MockAudioEngine` and
    `SheetEngine` updates. DSP v2 §10 should list these.
- **A2. EQ1c is missing from the UI plan.** UI v2 §7's DSP lane reads "EQ1a → EQ1b → EQ2", but the
  real lane is **EQ1a → EQ1b ∥ EQ1c → EQ2**, and EQ4 waits on EQ2, so on EQ1c too. Separately, EQ1b
  and EQ1c both edit `Realizer.{h,mm}` and the C-ABI header, so they can't run fully in parallel:
  - EQ1c's parallel part is the pure `TrackLoudnessProfiler`, the analysis job and their tests;
  - the Realizer predictor and the track hooks land **after EQ1b merges**.

  State this in DSP §10.
- **A3. Launch publish has two owners.** DSP v2 §10 puts "launch publish" in **EQ1b**; UI v2 §1 (F1 row)
  says it is **EQ2's** job. Pick EQ1b (it lands with the chain reorder it protects) and fix the UI row.
  DSP §10's EQ1b scope should also list the two `InspectorColumn` Intensity strings that UI v2 says EQ1b
  carries.
- **A4. Off copy.**
  - DSP v2 §8 says Off "can again say 'playing the original'". UI v2 §4.1 deliberately rejects that copy
    ("Original" belongs to Pure Mode) and uses "Equalizer off · the song plays without it, at matched
    loudness".
  - The UI owns copy, so delete the DSP §8 line.
- **A5. Loudness fallback description.**
  - UI v2 §1 (Breaker M2 row) still says "a curve-estimate fallback for the first ~10 s". That is v1
    SOTA wording, which DSP v2 rejected (S-pre).
  - The DSP v2 rule is: pink prior until the load-time profile lands (≈ 1 s), then a 500 ms glide.
  - Fix the UI row. No UI depends on it.
- **A6. "Refreshed in full at stroke end" has no signal.**
  - DSP §4.2 decimates the gain during a drag and refreshes it "at stroke end". But the contract (§8)
    gives the engine only `points` + `isOn`, so the Realizer cannot know a stroke ended.
  - Resolve it **inside the Realizer**: a full recompute when no EQ publish has arrived for about
    150 ms (a debounce on the queue).
  - Keep the contract unchanged, and say so in §4.2.

## 3. New issues (BLOCKER / MAJOR only)

**N1: MAJOR. The `eqStateV2` storage freezes built-in voicings.**
- **The problem.** Every slot stores `curve.base`. EQ3a's migration (rule 1) writes an unedited Warm as
  `{.builtIn(.warm), base = Warm's points at that time}`.
  - EQ3a lands **before** EQ4's re-voice. Any machine that launches an EQ3a build migrates at once, the
    founder's real defaults included, ahead of the EQ4 listening check.
  - After EQ4, `isEdited` compares that frozen base with the new Warm, so the user sees **"Warm · Edited"
    playing the old voicing**. That is exactly F7 again, and it recurs on every future re-tune.
- **Fix.**
  - Encode an unedited built-in as a reference only: `base` omitted, meaning "this preset's current
    points". Write it that way whenever tone == 0 and base ≈ the preset's points at save time.
    Migration rule 1 emits the same form.
  - Edited states keep their explicit `base`.
- **Kit tests (EQ3a):**
  - re-voicing a built-in updates unedited slots (shared and pinned) and leaves edited ones alone;
  - a dangling `.mine(name)` at load (`eqStateV2` and `eqCustomPresetsV1` are two keys written
    non-atomically) decodes to edited-flat with its curve kept.

**N2: MAJOR. The load-time loudness pre-analysis (EQ1c) is under-specified where it can cause rework.**
DSP §4.2 says "the playback layer decodes the file a second time on a utility-QoS thread". In Enhanced mode
that layer is Swift `AVAudioFile` (`AudioEngineBridge+Playback.swift:138`, `+GaplessRoll.swift:151-154`).
EQ1c must state:
1. **One owner.**
   - A single app-side `TrackLoudnessAnalyzer` actor (Swift, bridge layer) decodes with `AVAudioFile` and
     feeds the C++ profiler through `asLoudnessProfiler*`.
   - At most **2 jobs** (current + next).
   - Latest-wins per track token, **cancelled** on a track change or skip.
2. **Skips.**
   - No analysis in **Pure Mode**, where the EQ never plays.
   - A finished profile is **cached** by file identity (URL + size + mtime, or the library id), so
     repeat, previous and re-queue don't decode again.
3. **Failure.** On a decode error or an unreadable file: keep the pink prior for that track, log it once,
   and never retry in a loop.
4. **Seam timing.**
   - `setCurrentTrack(token)` is called at the **audible** seam, `bumpTransitionCount`
     (`AudioEngineBridge+Gapless.swift:191`, the `.dataPlayedBack` site), and at `playFile`.
   - Never at next-track *scheduling* (`setNextTrack`, `:52`), or track A's tail plays with B's gain.
5. **Cost bound.**
   - The ~1 s estimate is for 44.1/48 kHz stereo. A 400 ms FFT per block at 192 kHz × 8 channels is
     roughly 10–20× that, so the prior (≤ 3.4 dB off) could play for many seconds and then glide mid-song.
   - Add a `Profiler_Timing` gate on the worst supported format with a stated budget.
   - Bound memory and Realizer cost by duration: the profile is ~37 MB for a 60-minute track ×2, and
     ΔL costs ~10× per solve.
   - Decimate blocks above a duration cap.
6. **Ownership of the C-ABI.** `publishTrackLoudnessProfile` and `setCurrentTrack` are called from the
   analyzer and the bridge only, never from `EQViewModel`. That keeps the UI contract at `publishEQ`
   + `eqSampleRate`.

**Checked, nothing BLOCKER or MAJOR:**
- **The four-path kernel and the limiter fix** (`LimiterModule.h:139-161`: the look-ahead ring is real,
  and P0 bypasses it). The approach (prime the ring, a 5 ms crossfade, 2 s hysteresis, the gate) is sound.
  The crossfade combs for 5 ms and the primed ring isn't detected, but both only reproduce the source
  P0 was already playing.
- **Edge 5:** the launch order is correct (§1 F4). The UID diff ignores the rate-only `selectedDevice`
  reassignment.
- **The rest of the migration:** the rules, decode limits and downgrade key are fine apart from N1.

## Verdict: **OPEN ITEMS**

- **N1** (MAJOR): unedited built-ins stored as a frozen `base`.
- **N2** (MAJOR): the pre-analysis owner, cancellation, Pure skip, cache, failure path, seam timing and
  cost bound.
- **A1–A6:** text mismatches between the two plans (owners, lane, launch publish, Off copy, fallback
  wording, the stroke-end signal).
- **F17 / F18 partials:** the `RtSwappableResource` gate row, and the C++ per-publish logging.

**Summary**
1. 15 of my 19 findings are CLOSED. F7, F14, F17 and F18 are PARTIAL, and none is OPEN in substance.
2. I accept the DSP author's rejection of my §3: finished (k, m1) on one one-pole (S2) beats the dB path
   on measured swell (+1.49 vs +6.6 dB) and keeps the read-back trivially bit-exact.
3. The two plans now share one contract. Six text mismatches remain, mainly EQ0/DEV-UID ownership, the
   EQ1c lane, the launch-publish owner and the stroke-end signal.
4. **N1:** store an unedited built-in as a reference only, or EQ4's re-voice marks every unedited user
   "Edited".
5. **N2:** EQ1c needs one analyzer owner, cancellation, a Pure skip, a cache, a failure path, the
   audible-seam hook and a hi-res cost gate.
