# Sprint EQ — break-it pass on the IMPLEMENTED EQ engine

*2026-10-10. Base `feat/s10-8-eq` @ 12ea184; break-it branch `test/s10-8-eq-engine-break-it` @ 31dea8e.
Machine: Apple Silicon (this worktree's Mac), optimised measurements at `-O2`.*

**Method.** I attacked the merged code, not the plan, in two ways:
- **Red tests.** I added four failing tests to the C++ gate in `Tests/EqEngineBreakItTests.inc`.
  They run inside `make gate`, `make sanitize` and `make tsan`.
- **Measurements.** These are not gated:
  - the harness is `Tests/EqEngineBreakItMeasure.cpp` with `Tests/EqEngineBreakItMeasurements.inc`;
  - `research/eq-engine-break-it/build-measure.sh -O2` builds it and `research/eq-engine-break-it/measure [name]` runs it;
  - the full run is committed as `research/eq-engine-break-it/out-measurements.txt`.

Every transition figure has the same basis:
- it uses the real `Realizer::applyEq`, with the production τ rule and its bookkeeping;
- it runs through the real `EQModule` with quadrature probes, so the envelopes are exact;
- it is measured against the designer's analytic read-back of every endpoint.

**Product code was not changed.**

## Findings

| # | Severity | Claim attacked | Repro / test | Expected vs measured |
|---|---|---|---|---|
| 1 | **BLOCKER** (for the EQ4 listening check; known EQ2 item, not an EQ1b regression) | "Read-back: 0.000 dB from what plays, at every Intensity" | `measure app-safety-clamp-gap`. Code: `AudioEngineBridge+EQControl.swift:27` still sends `EQSafetyClamp.clamped(points)` through `publishEQBandGains`, while `EQViewModel.played` designs the *unclamped* points | Expected: the graph equals what plays. Measured in the app as merged: any curve whose signed sum is above 12 dB is scaled by 12/sum before it is played, but the graph draws it unscaled.<br>• Warm: drawn +10.11 dB, played +0.75 dB (9.36 dB gap @ 489 Hz).<br>• Presence: 8.00 vs 2.70.<br>• Vocal: 6.01 vs 1.58.<br>• Tone Bass+Air +12: 11.45 dB gap.<br>5 of the 6 built-ins are 3.2–9.4 dB off. The 0.000 dB figure holds only below the C-ABI. EQ2 must land before anyone judges the EQ by ear. |
| 2 | **MAJOR** | Guards: "NaN rejected; a bad input recovers in 1 block (module) / 2 (kernel)" | **`BreakIt_InfInput_KernelRecovers`** (red). Code: `LimiterModule.h:379` (`targetGrDb` → −Inf), `:405` (release −Inf + Inf) | Expected: finite output within 2 blocks.<br>Measured: one +Inf input sample on an identity-EQ path (P2 with the EQ off; or leaving P0 after an Inf was primed into the limiter ring) sends the limiter's true-peak detector to Inf. The gain envelope goes to −Inf dB, and the release then computes −Inf+Inf = **NaN for good**. Every later sample is NaN from about 43 ms on, until a re-allocation.<br>The non-identity EQ "survives" only by accident: its cascade turns Inf into NaN, and the limiter's `std::max` drops NaN. A corrupt 32-bit float file is enough to trigger it. |
| 3 | **MAJOR** (pre-existing in `LufsMeter`, reached on P2/P3) | Same guard claim, one stage later | **`BreakIt_NonFiniteInput_NormaliserKeepsAdapting`** (red); `measure normaliser-poison`. Code: `LufsMeter.h` K-weighting state; `blockLoudness` (`:337`) reads NaN energy as silence | Expected: the normaliser keeps adapting.<br>Measured: one NaN *or* +Inf sample puts NaN into the K-weighting biquad state. After that:<br>• short-term loudness reads −200 LUFS ("silence") forever;<br>• nothing is gated in again;<br>• the makeup **freezes** (−2.40 → −2.40 dB over 3 s, and 0.537 → 0.537 over 6 s) until the AU re-allocates.<br>The output stays finite, so `EQ_NaNInput_Recovers` can't see it. The EQ zeroes its own states, but the poisoned block still reaches the normaliser. |
| 4 | **MAJOR** (product-level; founder decision) | "Intensity-0 boundary step 0.054 dB after the normaliser has adapted" (amendment 2: "no level step") | `measure intensity-zero-swing`. Code: `DSPKernel.cpp:211` | The 0.054 dB reproduces, but it is a **per-sample** step. Seen as level over time, r 0.3 → 0 swings the whole adapted makeup:<br>• loud tone: **+9.99 dB** (10→90 % within 45–115 ms; 8.8 dB in the worst 50 ms);<br>• quiet tone: **−14.57 dB** (35–110 ms; 10.2 dB in 50 ms).<br>The fade `min(1, r/0.1)` follows *r*, and *r* ramps at 32 ms. So "Reimagine off" (0 %) still moves the level by up to ~15 dB in about 0.1 s from the default 20 %. A per-sample gate can't tell this apart from a step. |
| 5 | **MAJOR** (UX) | Amendment 1: "τ 160 ms only for jagged curves (adjacent bells fighting at ±30 dB)" | **`BreakIt_TauRule_SinglePointIsNotJagged`** (red); `measure tau-classes`, `drag-latency`, `jagged-false-positives`. Code: `EQTargets.h:25, 41` | Expected: simple gestures glide at 10 ms.<br>Measured: **one point at ±12 dB solves to ±17.8 dB**, so a single point at about ±10.5 dB or more lands in the 160 ms class. Examples:<br>• a key step +11 → +12 @ 1 kHz takes **371 ms** to reach 90 %, against 25 ms for +9 → +10;<br>• Warm with 125 Hz pulled to −12 takes 356 ms;<br>• a drag to the top trails the pointer by about τ.<br>At ≥ 1 kHz the slow class buys nothing: forced to 10 ms, those single points stay ≤ +0.53 dB local (+0.01 dB for the key step). |
| 6 | MINOR (violates the realistic gate's own bounds) | `EQ_Transitions_Realistic`: "everyday changes local ≤ +0.75, peak ≤ +0.5 dB" | **`BreakIt_Transitions_LowBandGestures`** (red) | Expected: ≤ +0.75 local / ≤ +0.5 peak.<br>Measured, at the rule's τ (10 ms), Off → one bass point:<br>• +6/+8 dB at 20–63 Hz: local **+1.60 … +2.92 dB** (above +1 dB for 26–84 ms);<br>• +8 dB at 20 Hz: **peak +2.78 dB** (above the curve's own maximum).<br>These are Compare release, the On toggle and choosing a My Preset. The reverse direction is clean.<br>Root cause, shared with #5: τ keys on the curve's max solved gain. It should follow each band's own time constant (∝ 1/f_c). A 40 Hz bell rings for ~20 ms, but τ is 10 ms; a 1 kHz bell is clean at 10 ms but is sent to 160. |
| 7 | MINOR | "adv_pair_S2 local +4.74 dB @ 2205 Hz but peak 0.00 — is local audible?" | `measure local-swells` | The excursion:<br>• sits at **2.2 kHz** (presence band), 12.2 dB below the curve's max, so it is not low in level;<br>• stays above +1 dB for **330 ms** and above +3 dB for **211 ms**, peaking 105 ms after the switch;<br>• has neighbours at 1.7/2.9/3.4 kHz of +2–3 dB for 150–250 ms.<br>The 160 ms ramp makes it *longer*. It is likely audible as a presence "bloom". The adversarial pair is My-Preset-only. The "peak" metric can't see a swell below the curve max.<br>v3_worst_tau40's +1.44 dB @ 38 Hz lasts 103 ms, 2.6 dB below the curve max (its own bass hump): low audibility. |
| 8 | MINOR | "Transitions realistic ≤ +0.3 dB" — the calm class (τ 10/40) | `measure calm-pair-search` | Expected: the calm class is swell-free.<br>Measured: 400 random calm pairs (Tone settings, edited presets, point pairs; both endpoints ≤ 15 dB solved) reach a worst local of **+1.83 dB**. A hill-climbed rough calm pair reaches **+4.43 dB @ 33 Hz** (above +3 dB for 16 ms, 14 dB below the curve max). The peak stays ≤ +0.19 dB. |
| 9 | MINOR (decision 29 not yet built) | P0 ↔ P1 switching "no glitch, no level step" | `measure p0-switch` | On the gate's −9 LUFS loud master at Intensity 0:<br>• EQ Off (or a Compare held past 2 s) plays limited for 2.2 s, and then P0 lifts the limiter's gain reduction in 5 ms: **+0.74 LU** (P1 −9.08 vs source −8.34 LUFS; sample peak −2.99 → source).<br>• With decision 29's −0.1 dBTP ceiling (EQ2) the step is +0.26 LU.<br>• The 5 ms equal-gain fade between the 3 ms-apart streams dips **−3.3 dB for ~1 ms** on broadband noise (a comb).<br>`Kernel_PathSwitch_NoGlitch` uses a sine below the ceiling, so it sees neither. |
| 10 | MINOR (EQ1c not yet wired) | Predictor "≤ 0.112 dB" | `measure predictor-adversarial` | The gate's realistic programmes *with bass cuts*, which the gate never tests, hold at ≤ 0.137 dB. Adversarial programmes do not:<br>• a sustained 31.6 Hz sine with −12 dB at 31.6 Hz: **+3.12 dB** error;<br>• the same tone on jagged curves: 2.4–8.2 dB. The 400 ms block resolves 2.5 Hz, but the 1/24-octave bands are under 1 Hz wide there;<br>• DC 0.3 + 12 Hz rumble, Warm: +0.72 dB;<br>• 44.1 k with a 21.5 kHz tone, Air/+12 @ 20 k: +1.05/+1.14 dB (the last band's centre against the bell's fall to Nyquist). |
| 11 | MINOR | "CPU 2.19 % settled, 2.39 % gliding at 192 kHz × 8" | `measure cpu` | Reproduced: 2.19–2.24 % settled, 2.30–2.35 % gliding.<br>But the designer, Realizer and module accept up to **768 kHz**: 4.4–4.7 % at 384 k × 8 and **8.7–9.4 % at 768 k × 8**, over the 5 % budget (×1.4–1.8 on M1 Pro).<br>Stereo costs almost as much as 8 ch (1.9 vs 2.2 % at 192 k): the work buffer always strides 4 pairs. |

## Suggested fixes (recommended option first; for the fix round, not done here)

1. **#1.** Land EQ2's cut-over before the EQ4 listening check:
   - delete `EQSafetyClamp`;
   - send `points` through `publishEQ`.

   Until then, nobody should judge the EQ by ear on this branch.
2. **#2 and #3, one guard each, at the stage that owns the state.**
   - Limiter:
     - treat a non-finite detector value as "clamp hard", with a finite target;
     - reset `envFastDb_` / `envSlowDb_` when they stop being finite.
   - LufsMeter: reset the K-weighting state of a hop whose energy is non-finite.
   - Alternative: one input scrub at `DSPKernel::process` entry for the processed paths and the P0 prime (P0's own output stays untouched). It is cheaper, but it hides the next stage that grows state.
3. **#4.** This is a founder decision.
   - **(A, recommended)** Glide the normaliser's contribution in *time* (about 1–2 s), not in *r*, so that 20 % → 0 % fades the level instead of jumping 10–15 dB.
   - (B) Keep it, and say in the UI that 0 % plays the track at its own level.

   Either way, the path-switch gate should measure level in 50 ms windows, not per sample.
4. **#5 and #6.** Key the glide on each band's own time constant, e.g. τ_m = clamp(k / f_m, 10, 160) ms with k chosen by measurement. Key "jagged" on adjacent solved-gain opposition (sign flips or differences), not on max |gain|.
   - Add low single-band gestures (20–63 Hz, ±6/±8, both directions) to `EQ_Transitions_Realistic`.
   - Add a drag-latency bound for single points.
5. **#9.** Decision 29's −0.1 dBTP P1 ceiling (EQ2) cuts the step to 0.26 LU. Add a loud-master case to `Kernel_PathSwitch_NoGlitch`.

## What held up

- **Read-back at the C-ABI.**
  - `EQ_ReadbackEqualsEngine`: the RT (k, m1) equal the design bit for bit, and the kernel matches the read-back to 0.0000 dB.
  - `EQ_ResponseIndependentOfIntensity`: 0.0000 dB at r = 0 / 0.2 / 0.5 / 1.
- **RT numerics** (`measure rt-vs-readback`). The settled module matches the read-back:
  - ≤ 0.00003 dB at 192 and 768 kHz, at 20–40 Hz (g ≈ 8e-5) and at 20 kHz, on Warm, alternating and +12 @ 20 k;
  - ≤ 0.0011 dB at 44.1 kHz up to 21.5 kHz.
- **Designer accuracy.** Presets 0.082–0.084, hard 0.322–0.323, Rämö 0.437–0.445 dB.
  - This holds at every rate the designer accepts: 44.0, 44.1, 192, 352.8, 384, 705.6 and 768 kHz.
  - 8 fresh Rämö seeds: ≤ 0.447 dB.
  - A 30 000-design hill-climb finds 0.476 dB, within the 0.6 gate and the literature's < 1 dB. The "hard ≤ 0.32" figure is specific to that set.
- **The τ rule's "from" is the published target, not the module's state.**
  - I attacked jagged → calm → calm, Δ = 10–250 ms, over 4 jagged × 3 calm hops.
  - It is benign: at most +1.10 dB local, for ≤ 10 ms.
- **Re-allocation.**
  - VerifyAUGraph: stereo@48 → 6 ch@44.1 → stereo@48, worst 0.000 dB, drift 0.000 dB.
  - Storm: 18–21 k intents (jagged/preset/random EQ, On/Off, Intensity 0/0.05/0.2/1, crossfeed) and 38 re-allocations across 44.1/48/96 kHz × 256/512/1024 frames, over 40 k render blocks. Result: **0 RT allocations, 0 non-finite samples**, peak 0.873.
  - Under TSan the storm reports no race (`out-storm-tsan.txt`).
- **The Intensity-0 per-sample step.** 0.054 dB, reproduced.
- **The P0 fade.** No skipped or repeated audio; the only artefact is the ~1 ms comb dip (#9).
- **Rates below 44 kHz.** The designer rejects them, and the Realizer then publishes the identity.
- **NaN on non-identity EQ paths.** The output recovers (but see #2 and #3).
- **The predictor** on silence-heavy (95 %), left-only and mono-in-stereo programmes: ≤ 0.011 dB.
- **The existing gates.** 169 pre-existing C++ tests pass under the plain, ASan+UBSan and TSan builds, and ASan, UBSan and TSan report nothing.

## Limits of this pass

- **No listening.** Audibility calls (#6, #7) rest on level, duration and band.
- **The RT-allocation check counts `operator new` only** (the existing guard). On macOS 26 I could not count C-level `malloc` from Accelerate or libc++:
  - `malloc_logger` is read-only and writing it faults;
  - zone hooks are bypassed by the fast path;
  - main-executable interposing doesn't reach shared-cache callers.
  A code read of the RT path found no allocating call.
- **No Swift test for #1.** The bridge needs a live AU; the measurement mirrors `EQSafetyClamp.clamped` exactly.

## Exit codes (final run on 31dea8e)

- `make gate`: **2**. The null test is 169 passed, 4 failed (exactly the four new red tests), and the `&&` chain stops there.
- `swift run VerifyAUGraph`, run separately: **0**.
- `swift run VerifyLibraryStore`, run separately: **0**.
- `make sanitize`: **2** (169/4, the same four; no ASan or UBSan report).
- `make tsan`: **2** (169/4, the same four; no ThreadSanitizer report).
- The TSan build of the measurement storm: **0**, with no report.
- clang-tidy on `Tests/DSPKernelNullTest.cpp` and `Tests/EqEngineBreakItMeasure.cpp`: **0**. The pre-commit hook also passed.

Without the four red tests, the base suite is 169/169 in every build.
