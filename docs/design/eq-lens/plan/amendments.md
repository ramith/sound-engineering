# Sprint EQ — amendments after the verify pass (binding)

*2026-10-10. The build plan is three files, read in this order:*

1. *this file — it WINS wherever the others differ;*
2. *[engine-plan.md](engine-plan.md) — the DSP lane (the author's v2, after the three-reviewer panel);*
3. *[ui-plan.md](ui-plan.md) — the UI lane (the designer's v2).*

*Evidence lives in [../evidence/](../evidence/): the literature and players surveys, plus the three
reviews and their verify passes. The reference prototype is in
[research/eq-geq-poc/](../../../../research/eq-geq-poc/README.md).*

*Every item below comes from a verify-pass finding (architect A1–A6, F17, F18, N1, N2; breaker 2.1–2.3;
SOTA point 2) or from founder decision 29. The review loop is closed: one revision, one verify
(decision 18). These amendments are not re-reviewed as text. Each one carries a gate, and the build's
break-it pass checks the gates.*

## Founder decision 29 — loud masters in the EQ-only path

With Intensity 0 and the EQ on, the path is EQ → limiter, with no normaliser.

- **The problem.** On loud masters with a big boost, the −1 dBTP limiter worked hard. On a synthetic
  −9 LUFS master it held more than 1 dB of gain reduction for up to 74 % of the time, and EQ On played
  up to 2.75 dB quieter than Off (SOTA verify, measured).
- **Decision: the ceiling in that path is −0.1 dBTP.** That is no higher than the bit-perfect Off of the
  same masters already sends (up to +0.8 dBTP).
  - Heavy limiting (> 3 dB) falls from 26 % to 7 % of the time.
  - On/Off mismatch falls to p90 0.57 dB (max 2.07 dB).
  - A held Compare plays the original within 0.22 dB.
- **Bluetooth outputs keep −1 dBTP.** The wireless link re-encodes the signal, and lossy encoders need
  the margin (EBU R128's −1 dBTP rationale). The device's transport type comes with the DEV-UID PR.
- **Every other path keeps −1 dBTP.**
- **Gate:** `Limiter_EqOnlyCeiling` — −0.1 dBTP on wired/built-in, −1 dBTP on Bluetooth; output never
  above the ceiling.
- **Later, not R1:** a per-curve peak scan of the track that caps the gain where the limiter would exceed
  2 dB (SOTA verify).

## Engine lane (DSP)

1. **Transition ramp time keyed on jaggedness** (breaker 2.1; re-opens part of M1).
   - Choose the τ class from the endpoints, not from the size of the change: if max |solved gain| of
     either endpoint exceeds 15 dB, use τ = 160 ms; otherwise use v2's 10 / 40 ms rule.
   - Measured: the two adversarial pairs go from +4.51 / +2.42 dB to ≤ +1.0 dB.
   - Pin both pairs (`research/eq-geq-poc/fixtures/v3_worst_tau40.npy`, `v3_worst_tau10.npy`) in
     `EQ_Transitions_Adversarial`, with a bound of ≤ +1.0 dB (time-domain peak).
   - v2's "≤ +1.49 dB" claim is withdrawn.
2. **No level step at the Intensity-0 boundary** (breaker 2.3). This bug predates the sprint: +13.4 / −15.5 dB
   was measured at today's boundary.
   - Fade the normaliser's contribution continuously as r → 0 (e.g., makeup·min(1, r/0.1)), so P1 and P3
     meet at r = 0 with no step.
   - **Gate:** `Path_Switch_AfterNormaliserAdapted` — ≥ 10 s of a loud programme first, then a level step
     ≤ 0.5 dB.
3. **Track loudness analysis (EQ1c), fully specified** (architect N2 + breaker 2.2):
   - **One owner:** a Swift `TrackLoudnessAnalyzer` actor in the bridge layer.
     - It decodes with `AVAudioFile` and feeds the C++ profiler.
     - At most 2 jobs (current + next), latest-wins per track token, cancelled on a skip or track change.
   - **Prefix first:** profile the first ~20–30 s at once, then refine to the whole track with a slow glide.
   - **Skipping work:**
     - no analysis in Pure Mode;
     - a cache keyed by file identity (library id, or URL + size + mtime).
   - **Failure:** fall back to the causal running estimator (not the pink prior). Log once; never retry in a
     loop.
   - **Gapless:**
     - Switch the profile at the AUDIBLE seam: the `.dataPlayedBack` / `bumpTransitionCount` site
       (`AudioEngineBridge+Gapless.swift:191`) and `playFile`.
     - Never switch at next-track scheduling (`setNextTrack`).
     - The level step at a gapless seam must be ≤ 0.2 dB. If two tracks' gains differ by more, the gapless
       group shares one gain.
   - **Cost bound:**
     - A `Profiler_Timing` gate on the worst supported format (192 kHz × 8 ch) with a stated budget.
     - Memory and Realizer cost bounded by duration, with decimation above a cap.
   - **C-ABI ownership:** `publishTrackLoudnessProfile` / `setCurrentTrack` are called from the analyzer
     and the bridge only, never from `EQViewModel`.
   - **Port rule:** the block FFT uses NO window. Hann errs −0.36 dB on a tonal track (breaker verify).
   - **Gates:**
     - profile-late;
     - gapless-seam step ≤ 0.2 dB;
     - analysis-fails fallback;
     - `Profiler_Timing`.
4. **Loudness refresh after edits** (A6): a ~150 ms idle debounce inside the Realizer. The contract has
   no stroke-end signal.
5. **Gate table additions:**
   - F17: a direct `RtSwappableResource` test;
   - the ultrasonic gate applies to named curves only (breaker m2: an adversarial command exceeds its
     1.5 dB bound at +2.07 dB).
6. **Logging** (F18): the per-publish C++ `[QW1]` lines (`Realizer.mm:163`, `AUAudioUnit.mm:414`) become
   debug-level or rate-limited in EQ1b.
7. **Off copy** (A4): drop engine-plan §8's "playing the original". The UI plan's copy stands: "Equalizer
   off · the song plays without it, at matched loudness".

## UI lane

8. **Unedited built-ins are stored as a reference** (architect N1).
   - In `eqStateV2`, an unedited built-in is stored as `.builtIn(id)` with NO `base`, meaning "this
     preset's current points".
   - It is written in that form whenever tone == 0 and base ≈ the preset's points; migration rule 1 emits
     the same form. Edited states keep an explicit `base`.
   - **Kit tests (EQ3a):**
     - re-voicing a built-in updates unedited slots, shared and pinned, and leaves edited ones alone;
     - a dangling `.mine(name)` at load decodes to edited-flat with its curve kept.
9. **Loudness fallback wording** (A5): the UI plan's "curve fallback for ~10 s" is replaced by the
   behaviour in item 3. The UI shows nothing for it; the level simply settles.

## Added by the EQ3a break-it pass (2026-10-10)

EQ3a's own fix round fixed the drag, downgrade and data-robustness findings. **EQ4 inherits these
items, which only go live once pins exist:**

10. **C1:** Save while the output switches must save the curve that was showing when Save was pressed,
    into the slot it came from. It becomes MAJOR once pins exist.
11. **Toasts:**
    - E2: a switch after a gap with no output must STILL show the toast (it was missing);
    - a toast raised while the window is closed must not appear or be spoken on reopen;
    - the queue toast and the EQ output toast must not overlap (one shell toast slot, or stacked).
12. **Preset names:**
    - N1: a My Preset may not be named like a built-in, compared case-insensitively;
    - N2: names that are empty or whitespace/newline-only are rejected.
13. **Pins on the same model:** confirm with the founder that a second unit of a pinned model sharing the
    first unit's pin is the intended behaviour (the model-UID fallback).

## Added by the engine break-it (2026-10-10; tests in 31dea8e on `test/s10-8-eq-engine-break-it`)

The fix round runs after EQ2. EQ2 itself closes finding 1 (the app still clamps, so presets play 3–9 dB
under the graph), and it must land before the listening check.

14. **Non-finite input** (findings 2, 3):
    - one +Inf sample must not leave the limiter in a permanent NaN state;
    - one NaN or Inf sample must not freeze the normaliser's K-weighting state.
    Sanitise at the kernel input and make both states recover. Red tests:
    `BreakIt_InfInput_KernelRecovers`, `BreakIt_NonFiniteInput_NormaliserKeepsAdapting`.
15. **Per-band glide** (findings 5–8): each band follows its own time constant, from its own change and its
    own jaggedness, instead of one τ from the curve's largest solved gain.
    - A single ±12 point must settle in ≤ ~30 ms (today it takes 371 ms).
    - Low-band gestures must not swell above the curve's own maximum.
    - Bound the local swell's DURATION as well as its peak: adv_pair_S2 stayed above +3 dB for 211 ms.
    Red tests: `BreakIt_TauRule_SinglePointIsNotJagged`, `BreakIt_Transitions_LowBandGestures`.
16. **Decision 33:** crossing Intensity 0 glides the level over ~2 s. Gate it on the level's slew rate, not on
    a per-sample step.
17. **The P0 switch** (finding 9): bring the +0.74 LU level step entering bit-perfect down to ≤ 0.3 LU on a loud
    master (decision 29's ceiling helps), and make the 5 ms fade equal-power, with no −3.3 dB dip.
18. **Rates above 192 kHz** (finding 11): either cap the design rate (e.g., hold identity or resample above
    384 kHz) or state a separate CPU budget; 768 kHz costs ~9 %.
19. **The predictor on pathological programmes** (finding 10: sustained pure tones, DC rumble, near-Nyquist tones):
    document the limits, and clamp |ΔL| to a sane bound so a mis-prediction never moves the level by more
    than ~3 dB.

## Recorded deviations from the UI plan (the screen's fix round, 2026-10-10)

- **`highlightedRegion` lives on `EQViewModel`**, not as `EQTabView` state (ui-plan §3.1): the Tone card and
  the graph sit in different subtrees, and one observed property links them without plumbing.
- **The +12 dB ceiling ghost is a dashed ring and tether** at the asked level, not a dashed requested curve
  (ui-plan §4.3): the designer holds points at ±12, so no honest curve exists for a level the EQ can't play.
- **`EQAudibleState.engineNotReady`** is a fifth state (ui-plan §4 has four): with no engine nothing plays,
  and the strip says so, while the graph still draws the EQ as it will play once the engine runs.

## Lanes and ownership (A1–A3)

| Lane | PRs (order) | Notes |
|---|---|---|
| DSP | **EQ0** (contract + kit value types + stub) and **DEV-UID** (device UID + model UID + transport type) on day 1 → **EQ1a** (pure designer) → **EQ1b** (real-time engine, kernel order, re-allocation, launch publish incl. intensity + the two Now Playing Intensity strings, logging) → **EQ1c** (track loudness analysis; its Realizer part lands AFTER EQ1b, since both edit `Realizer.{h,mm}` and the C-ABI header) → **EQ2** (bridge cut-over, `EQSafetyClamp` deleted, decision-29 ceiling) | EQ0 and DEV-UID belong to the DSP lane (A1) |
| UI | **EQ3a** (kit logic + view model + persistence + `EQPlotMap`) → **EQ3** (V1b screen, needs EQ1a's designer) ∥ **EQ3t** (Tone card) → **EQ4** (My Presets, the pin, the re-voice — last) | EQ3a alone owns the view model and persistence |

The founder's listening check (EQ4) follows the break-it pass on the merged branch.
