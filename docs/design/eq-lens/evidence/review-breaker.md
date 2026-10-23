# Sprint EQ: DSP plan, adversarial review (Reviewer 1, "the Breaker")

*2026-10-09. Under test: `eq-plan/dsp/dsp-plan-check.md`. The UI plan was read for the contract and state
model only. Code was read on `feat/s10-8-eq` @ f563437 in the main checkout; nothing in the repo was
built or edited.*

*Method. I built my own prototype from the papers and first principles:*
- *the 31-band ACGE-style design, the transitions, loudness and Tone in Python (`bkgeq.py`, `a*.py`);*
- *the time-domain real-time ramp, numerics, the real `vDSP_biquad`, denormals and NaN in C++ (`rt_sim.cpp`,
  `zipper_nopre.cpp`, `fzprobe.cpp`);*
- *two runtime repros of today's kernel, compiled from a read-only copy of `Sources/AudioDSP` in `repro_src/`.*

*I did not run or import any author script. After reproducing, I read the author's `geq.py`, `acge_ref.cpp`
and `results/` only to explain differences (§4). Everything re-runs with `sh run_all.sh` in this folder;
the outputs are in `out_*.txt`.*

*Labels: **[M]** measured here; **[C]** cited (source in §7); **[O]** opinion or judgement. All dB figures are
[M] unless marked. Machine: Apple M4 Pro.*

## 1. Verdict: SOUND WITH FIXES (one BLOCKER to settle before EQ1 is coded)

The engine core holds. My independent reproduction of these matches the author to two decimals [M]:
- one bilinear bell per band with an iterative weighted least-squares (WLS) interaction solve;
- a double-precision TPT SVF;
- automatic headroom.

The plan as written is still not safe to build. Four reasons:

1. **BLOCKER.** The **Reimagine intensity blend** sits *after* the EQ and *before* the loudness stage and the
   limiter. At any intensity strictly between 0 and 100%:
   - the played curve is not the drawn curve;
   - the output exceeds the source by up to **+3.0 dB**;
   - "Off with a flat curve is bit-exact" is false.

   The read-back API has no intensity input, and every gate test runs at intensity 1.0. Decisions 22 and 23
   are broken in a user-reachable state.
2. **MAJOR.** The shared dB-domain ramp, the plan's main real-time design choice, overshoots **+5.5 dB** on
   an adversarial pair of curves, not the claimed 0.8–1.2 dB.
   - Smoothing *finished* per-band SVF coefficients overshoots **+0.12 dB** on the same pair (+1.48 dB at its
     own adversarial worst).
   - So the "+21 dB" argument for computing coefficients on the RT thread is inverted. It holds only for
     direct-form coefficients.
3. **MAJOR.** Compare/Off level matching by curve-only predicted loudness is off by up to **±3.9 dB** (Warm)
   and **+7.3 dB** (a sub boost on EDM), not ±1.2 dB.
4. **MAJOR.** The latent "EQ goes flat after an AU re-allocation" bug is **confirmed at runtime**.
   - It fires on more paths than the plan lists.
   - The plan's fix does not specify how the new module seeds itself after re-initialisation.

## 2. Findings

| # | Sev | Claim attacked | What I found | Repro | Proposed fix |
|---|---|---|---|---|---|
| B1 | **BLOCKER** | "What is drawn is what plays"; "nothing is ever louder than the source"; "Off with a flat curve is bit-exact" (§5, §7) | The blend `cos(rπ/2)·dry + sin(rπ/2)·EQ` runs before loudness and the limiter. At r = 0.2 / 0.5 / 0.8: up to **+2.0 / +3.0 / +2.0 dB above source** for "+12 @ 1 k"; shape error vs the drawn curve **10.9 / 8.4 / 5.0 dB** (Warm 8.7 / 6.6 / 3.9; alternating 22 / 19 / 14). A flat Off plays **+2.0 / +3.0 dB**. Through today's real kernel copy, a +12 band plays **+6.85 dB at r = 0.2** and **+12.31 dB at r = 0.8** | `python3 a5_headroom.py` (section D); `./repro_blend` | Founder decision, recommended option first: **(a)** take the dry tap *after* the EQ, so the EQ sits outside the Reimagine blend. The "0 % = bit-perfect" help text becomes "Reimagine off"; Pure Mode stays the bit-perfect path. (b) Make the read-back and the headroom blend-aware (`|c + s·P·H|`, preamp solved so that ≤ 0 dB) and draw that curve. Either way, add gate tests at r ∈ {0.2, 0.5} |
| M1 | **MAJOR** | Shared dB ramp: "+0.004 realistic, +0.8–1.2 pathological"; gate ≤ 1.5 dB; "interpolating finished coefficients overshoots +21 dB", hence the RT computes coefficients (§3, §8) | Adversarial pair of ±12 zig-zags: **+5.58 dB** (frozen model), **+5.52 / +5.40 dB** in the time domain (sine at 968 / 959 Hz). Curve ↔ flat (Off or Compare toggles): **+2.15 dB**. The **SVF (k, m1) one-pole on finished coefficients** gives **+0.12 / +0.24 dB** on the same pair, **+1.48 dB** at its own adversarial worst, and **−0.00 dB** on alt+ → alt− (where direct-form interpolation gives **+21.41 dB**, reproduced). Realistic cases (42 preset pairs, 150 smooth pairs, drags), frozen model: **0.000 dB**. **In the time domain, the 42 preset pairs reach +0.194 dB** (plan ramp) and +0.209 dB (SVF smoother), at Warm → Flat, 480 Hz; both endpoints settle ≤ 0 dB. The author's "+0.004 realistic" is a frozen-model figure, so the gate's "realistic ≤ +0.05 dB sampled during the ramp" fails | `python3 a4_transition.py`, `a4b_reachable.py`, `a4c_svf_adv.py`; `./rt_sim` (Attack 4); `./presets_td`; `./td_check` | Ship the **finished-coefficient SVF smoother**: the Realizer computes per-band (k, m1) targets off-RT; the RT one-pole smooths them per sample (one divide per band). This restores "RT runs finished coefficients" without the overshoot. Pin `worst_pair.npy` in `EQ_Headroom_Transitions`. Optional: a path-aware transition preamp (a 9-point off-RT path check predicts 5.56 dB against the true 5.58) |
| M2 | **MAJOR** | Compare/Off level match "±1.2 dB depending on the music" (§4.4) | Error (true − predicted) by long-term spectrum: Warm **−3.92 … +3.87**; Presence −1.70 … +2.81; Clarity −2.59 … +1.55; sub boost +12 @ 40–63 Hz **+7.26** (EDM 808); Air +12 **−6.13** (orchestral). Compare Warm ↔ Presence, real A−B: **−4.72 … +5.56 dB**. Spectra are constructed models [O]; the K-weighting is BS.1770 [C] | `python3 a7_loudness.py` | Move the "use the track's own long-term spectrum (the existing pre-DSP analyzer)" follow-up **into EQ2**. Until it exists, don't claim "level-fair". Gate the residual on a spectrum family, not on pink only |
| M3 | **MAJOR** (pre-existing) | §2.5: "after AU re-allocation the EQ plays flat; nothing republishes" | **Confirmed by code and at runtime**: +12.00 dB → **+0.00 dB** after `initialize()`, then back once any other intent republishes. Trigger paths in §3.3. In the new design, the module's re-init seeding and fs mismatch are unspecified; gains run at the wrong fs err by **1.41 dB** (44.1 ↔ 48 k) and **2.89 dB** (96 → 44.1 k) | `./repro_realloc`; `python3 a6_tone.py` (S9b) | Keep the plan's Realizer `setSampleRate` fix. Also: (i) `EQModule::initialize` **snaps** its ramp to the snapshot's `filterGainDb` (not identity); (ii) while `designSampleRate ≠ fs`, hold the last good coefficients or play flat at the preamp, then re-solve; (iii) test at the Realizer + kernel level and in `VerifyAUGraph` (stereo → 6 ch → stereo keeps the EQ) |
| m1 | MINOR | "≤ 0.31 dB at the centres on the hardest commands"; "a third pass gains < 0.02 dB" | Adversarial command: centre **0.864 dB** (48 k) and **0.829** (44.1 k); 61-point **2.18 dB**. **5 passes give 0.413, 8 give 0.338.** Bandwidth c = 0.33 gives 0.504; c = 0.46 gives 1.345. Still inside the literature's < 1 dB [C] | `python3 a1_accuracy.py`, `a1b_longsearch.py` | Use 6–8 passes (cost ≈ 2× of a ~0.1 ms solve [O]). Add `worst_cmd_long.npy` to `EQ_ACGE_Hard` |
| m2 | MINOR | "No special case near Nyquist"; "the shape pokes ≤ 0.3 dB above +12" | Above band 31 (20.2–20.7 kHz) the response is unfitted: **13.62 dB at 44.1 k** for a −12/+12 edge pair (audible-band peak 12.20), and alternating 12.96 against 12.00. This sets the preamp, which drops **1.4 dB** for no audible reason, while the graph (20 Hz–20 kHz) can't show why. At 96 / 192 k, "all +12" boosts **+4.7 / +5.1 dB at 25 kHz**. Nyquist is exactly 0 dB | `python3 a2_nyquist.py`, `a2b_hazard.py` | Decide whether the headroom scan stops at 20 kHz (with the limiter catching the rest) or at Nyquist. If at Nyquist, draw or explain it. Optionally add a fit point near min(0.95·Nyquist, 22 kHz) |
| m3 | MINOR | Peak scan "under-estimates by ≤ 0.009 dB"; gate `NoFrequencyAboveSource` ≤ +0.01 dB | **0.0125 dB** under-estimate on 300 adversarial commands, so the gate as specified would flake | `python3 a5b_peakscan.py` | Add a +0.02 dB margin to the preamp; gate at +0.03 |
| m4 | MINOR | "Every gain ≤ headroom, so nothing is ever louder than the source" | Magnitude ≤ 0 dB still lets **peaks rise**. Worst-case peak gain (L1 norm of h): Warm **+4.8**, bass cut **+8.0**, alternating **+16.4 dB**. A constructed ±0.99 signal goes −0.09 → **+1.54 dBFS** sample peak. A synthetic brickwalled master through a bass cut goes −0.10 → **+3.85 dBFS** sample peak, with true peak +0.27 dB. The limiter is downstream and catches this (`DSPKernel.cpp:256-272`). Separately, the normaliser (`LoudnessModule.cpp:258-271`) restores the level over minutes (≤ +12 dB) | `python3 a5_headroom.py` (A–C) | Restate it as "no *frequency* above the source, at the EQ stage". Add a gate test that −1 dBTP holds after a cut-only EQ on a clipped signal |
| m5 | MINOR | WLS refinement "rebuilds B from the previous gains"; the NaN guard "checks states once per block" | Dividing by a previous gain of 0 makes a **flat command produce NaN** (the solver fails). The author's code guards at 1e-3 [read], but the plan text doesn't. A **NaN target gives NaN coefficients**, and the state-only guard leaves **5120 / 5120 outputs NaN** | `python3 a2b_hazard.py`; `./rt_sim` (Attack 3c) | Put the \|g\| < 1e-3 guard in the spec. `asEqDesign` rejects non-finite or out-of-range targets (±12) and non-finite results. The RT checks gains and coefficients with `isfinite`, not just states |
| m6 | MINOR | "Float DF: 28 dB SNR at 192 k vs 199 dB for the double SVF; don't port to `vDSP_biquad`" | The **real `vDSP_biquad` (float)** measures **41.9 / 36.1 dB** (Warm / alternating, 48 k) and **25.3 / 16.1 dB** (192 k), worse than the author's DF-I model. But **`vDSP_biquadD`** gets 184–204 dB and double DF-I/TDF-II 186–216 dB. Precision argues against *float*, not against direct form. The −0.868 dB float-coefficient shift (20 Hz, 192 k) reproduces | `./rt_sim` (Attacks 3a, 3b) | Keep the double SVF, but justify it by modulation behaviour (M1), not precision |
| m7 | MINOR | "FPCR.FZ also covers double [O, verify]"; gate a silence-tail timing test | **Verified**: FZ flushes double subnormals. A timing test **cannot fail** on Apple Silicon: 0.136 s with 57 subnormal states vs 0.135 s flushed | `./fzprobe`; `./rt_sim` (Attack 3d) | Replace it with deterministic checks: FZ is set on the render thread, and states are exactly 0 after N s of silence |
| m8 | MINOR | The ENGINE ↔ UI contract (§7 vs the UI plan §3, §5, §8) | (i) **`points` means opposite things**: the DSP plan's `points` is the ±12 list sent to the engine; the UI plan's `points` is the ±24 pre-Tone list, and it sends `effective`. (ii) DSP Compare is A/B against a reference curve, while UI Q3 is "hear the original"; with a flat reference, Compare ≡ Off. (iii) The UI draws Off as "flat at 0, playing the original", but the engine plays flat at L(curve): **−5.3 dB** (Warm), **−11.2 dB** (+12 @ 1 k) | `dsp-plan-check.md:309-325`; `ui-plan-check.md:157,165,310-313,388-392` | One glossary (`base` / `points`). The engine clamps to ±12 itself. Decide which Compare is meant. Show "Off · level-matched −X dB" |
| m9 | MINOR | "A dragged point lands **exactly** where dragged" | It holds to 1e-6 dB, but in float32 `(e − T) + T ≠ e` in **32,083 of 100,000** random cases (worst 9.5e-7 dB) | `python3 a6_tone.py` (S1) | `EQEditKit` tests use a tolerance |
| m10 | MINOR (pre-existing) | — | At launch the UI shows **20 %** intensity (`AudioViewModel.swift:104`, `didSet` only on change), while the kernel plays **100 %** (`TargetState.h:114`). The first touch jumps. This feeds B1 | code read | Publish the intensity at engine-ready, as the EQ does |

## 3. Details that matter for the fixes

### 3.1 B1: why this is a blocker and not a footnote

- `DSPKernel.cpp:179-189` takes the bit-exact in-place chain **only** when the intensity is settled at exactly
  1. Every other value goes through `:191-249`:
  - the dry signal is copied **before** the EQ;
  - the wet signal is EQ → Clarity → BRIR → Crossfeed;
  - they are blended equal-power (`:225-244`), and only then do loudness and the limiter run (`:249`).
- The slider is in the Now Playing inspector (`InspectorColumn.swift:116-120`). Any position other than
  0 % or 100 % makes the EQ:
  - **weaker** (a +12 band plays +1.9 dB of range at 20 %);
  - **comb-coloured** (dry plus minimum-phase wet);
  - **louder than the source** (equal-power on correlated signals).
- None of the plan's guarantees or gate tests sees this. `makeIdentityState()` pins intensity to 1.0
  (`Tests/TestSupport.h:370`).
- The project's own invariant is "Reimagine intensity 0 must be MD5-identical to the source". Option (a)
  therefore changes a locked decision. That is why the founder must choose, and it must happen before EQ1 [O].

### 3.2 M1: the convexity argument fails for large opposing gains

- The plan says a shared α keeps the *parameters* convex combinations of the targets. That is true, but the
  net dB response is **not** linear in the band gains. At ±30 dB filter gains, the bell shape changes
  enough that a midpoint set of gains peaks **5.6 dB** above both endpoints (at s ≈ 0.5, 967 Hz).
- The author's "pathological" set was 300 *random* zig-zag pairs (`results/07_ramp_stress.txt`: worst
  +1.22). A hill-climb finds the tail.
- Smoothing the SVF's (k, m1) works because the bell is `1 + m1·BP(k)`. That is affine in m1, so a
  midpoint never invents a large bell. On the same pair it reaches +0.12 dB.
- Costs of switching, both measured with the preamp fixed [M]:
  - the 100 Hz step artefact is **−52 vs −56 dBFS**;
  - the drag staircase is **−78.5 vs −78.8 dBFS**.
- Users rarely build zig-zags [O]. They can, though: My Presets, Compare and Undo all switch between
  arbitrary curves. The limiter only stops clipping; it does not remove the swell.

### 3.3 M3: exact chain (code read; the runtime repro is `out_repro_realloc.txt`)

1. Re-allocation calls `_kernel->initialize(...)` (`AUAudioUnit.mm:169`).
   - That creates a fresh `EQModule` (`DSPKernel.cpp:53`), whose identity vDSP setup is published at
     `EQModule.cpp:33-35`.
   - `EQModule::process` uses only the adopted setup plus `params.masterGainLinear` (`EQModule.cpp:118, 151`).
     It never reads `params.biquads`.
2. Coefficients reach the module only through `DSPKernel::publishTargetState` (`DSPKernel.cpp:97-100`).
   That runs only from `Realizer::publishCanonical` (`Realizer.mm:371`), and only when a new intent is set.
3. The Swift side re-sends the EQ only on user actions and `onEngineReady` (`EQViewModel.swift:73`). That
   hook fires only from `initializeEngine` (`AudioViewModel+Lifecycle.swift:62`).
4. Re-allocation happens on:
   - every stereo ↔ multichannel file change. `reconfigureGraph` → `pause` / reconnect / `start`
     (`AudioEngineBridge+Reconfigure.swift:184-187`; its own comment at `:182-183` says it "re-allocates
     both AUs").
   - an output-device rate or channel-count change. The engine restarts at
     `AudioEngineBridge+ConfigChange.swift:86`, after AVAudioEngine "stops, uninitializes itself" [C].
5. Neither path re-dispatches the EQ.
6. Today the Enhanced graph runs at a fixed 48 kHz (`AudioEngineBridge+Lifecycle.swift:46`, resampler).
   - So in production the trigger is the *re-allocation* itself, not a rate change.
   - The 88.2–192 kHz analysis matters for Phase 2 (the process tap), not for today's path [O].

### 3.4 What the six-rate accuracy really is (my reproduction, worst over 44.1–192 k)

| Curve | Centre (mine / author) | 61-pt (mine / author) | Filter gains | cond(WB) |
|---|---|---|---|---|
| Presence / Clarity / Warm | 0.084 / 0.032 / 0.045 ‖ 0.08 / 0.03 / 0.05 | 0.37 / 0.19 / 0.21 ‖ same | ≤ ±5.6 dB | 7.9 |
| Loudness / Vocal / Studio | 0.019 / 0.033 / 0.013 ‖ 0.02 / 0.03 / 0.01 | 0.08 / 0.12 / 0.06 ‖ same | ≤ ±2.9 dB | 7.9 |
| Alternating ±12 | 0.298 ‖ 0.30 | 1.37 ‖ 1.37 | −33.6 … +33.6 | 9.0 |
| −12/+12 edge pair at bands 30/31 | 0.239 | 1.22 | −26.5 … +22.2 | 7.9 |
| Random rough U±12 (my seeds) | 0.332 ‖ 0.31 | n/a | — | — |
| **Adversarial (hill-climb)** | **0.864** (3 passes), **0.338** (8 passes) | **2.18** / 1.65 | −32.7 … +32.3 | 8.6 |

## 4. Diff against the author's numbers (read after reproducing)

- **Presets and alternating ±12:** identical to two decimals. The author's bell, bandwidth and solver match
  mine; their divide-by-gain guard is in the code (`geq.py:141-142`, `acge_ref.cpp:26`) but not in the plan.
- **Ramp overshoot:** the author's 1.22 dB came from 300 random pairs. Adversarial search gives 5.58 dB.
  The +21.41 dB direct-form interpolation and the +5 dB separate-32 ms-preamp result both reproduce.
- **Precision:**
  - The author's float DF-I is 55.9 / 47.3 / 27.7 / 28.7 dB (48 k / 192 k). Mine is 51.9 / 41.2 / 21.2 / 14.0,
    and the real `vDSP_biquad` gives 41.9 / 36.1 / 25.3 / 16.1. The differences come from the input signal
    and the coefficient sets; the conclusion is the same and stronger.
  - My double SVF is the reference, so I can't confirm "199 dB" separately. Double DF and TDF-II agree with
    it to 186–216 dB.
- **Zipper:** −56 / −79 dBFS (mine, preamp fixed) against −60 / −89 (author). The metric details differ,
  and the order of magnitude is the same. With the preamp included, the probe's own 12 dB level change
  dominates (−19 dBFS), so the author's metric must exclude it.
- **Loudness:** the author's ±1.2 dB spans two smooth slopes (pink and −4.5 dB/oct). Real program spectra are
  not smooth slopes.

## 5. What I could not break

- **WLS conditioning:** cond(WB) ≤ 9.0, and about 81 for the normal equations, on every curve including the
  adversarial ones. Filter gains stay bounded at ±33.6 dB, and 3 to 12 passes converge [M].
- **Bell identities:**
  - A cut is the exact inverse of a boost (algebraic).
  - The TPT SVF equals the bilinear bell to **3.5e-13 dB** [M].
  - The response at Nyquist is exactly 0 dB [M].
- **In-band near Nyquist:** at 44.1 and 48 kHz, every top-band centre error is ≤ 0.24 dB on my curves.
  No shelf or Orfanidis bell is needed for the audible band [M].
- **Double precision:** the SVF in double reaches ≥ 186 dB SNR even with ±34 dB sections at 192 k [M].
- **Stability:**
  - 60 s of white noise with **5,510 random target switches** (hold 32–1024 samples) stays finite and
    bounded (+3.0 dB peak; +1.5 dB for the SVF smoother).
  - A 32-sample alt+ ↔ alt− chatter stays bounded (−4.9 dB) [M].
- **Realistic transitions:** preset pairs, smooth curves, drags and Tone moves never exceed the source in the
  frozen model (0.000 dB). The time-domain transient adds ≤ +0.21 dB for about 10 ms, which is inaudible [O]
  but matters for the gate threshold [M].
- **Tone layer:**
  - The weights telescope to exactly 1 in float32.
  - A flat Tone lift plays at the source level within −0.30 … 0 dB.
  - Preset reset, Save-bakes and the "removable layer" all behave as specified [M]. The hidden ±24 base makes
    a slider look dead on clamped points (S2), but that follows from the stated rules [O].
- **Chain order:** the limiter (−1 dBTP, 8× true-peak detector) is the last stage after the EQ in every
  branch (`DSPKernel.cpp:186-187, 249, 268-272`), so transient overshoots cannot clip.
- **Denormals:** FPCR.FZ flushes double on AArch64 [M].

## 6. Gate tests: what is missing (each defect above → a test that would catch it)

Most of the proposed §8 suite would pass on a build that still has B1, M1, M2 and M3. Add these:

1. `EQ_IntensityBlend_Honest` (B1): through the kernel at r ∈ {0.2, 0.5}. Assert that the played response
   equals the read-back (whichever option is chosen) within 0.3 dB, and that no frequency is above the
   source by more than 0.03 dB.
2. `EQ_Headroom_Transitions_Adversarial` (M1): the pinned pair in `worst_pair.npy` plus the curve ↔ flat
   pair, in the time domain. Use a sine sweep around the predicted frequency. Bound: ≤ +1.5 dB (finished-SVF
   smoother: measured 0.24). Set the "realistic" bound at **+0.3 dB** in the time domain (measured 0.194,
   Warm → Flat), not +0.05 dB.
3. `EQ_ACGE_Hard` (m1) adds the pinned `worst_cmd_long.npy` command: centre ≤ 0.5 dB with 8 passes
   (measured 0.338).
4. `EQ_Reallocate_KeepsCurve` (M3): Realizer publish, then `kernel.initialize(same fs)` with no republish.
   The played response must still match within 0.1 dB.
5. `EQ_Reallocate_NewRate`: re-initialise at 44.1 k with gains designed at 48 k. Use **Air +12**; alternating
   and a +12 bell at band 26 also work, but a mid single band is nearly fs-invariant and would pass vacuously.
   The test asserts a re-solve or hold. A `VerifyAUGraph` case must show that stereo → 6 ch → stereo keeps
   the EQ.
6. `EQ_Design_Rejects_NonFinite` and `EQ_Design_FlatFinite` (m5): flat, one band exactly 0, NaN and ±24
   targets. Assert that the design returns false or clamps, and that the RT keeps the last good set.
7. `EQ_Headroom_NoFrequencyAboveSource` gets a +0.02 dB preamp margin and a 0.03 dB threshold (m3). Add a
   20–22.05 kHz row at 44.1 k (m2).
8. `EQ_Limiter_HoldsAfterCut` (m4): a clipped synthetic master through a cut-only curve, then the full
   chain. Assert true peak ≤ −1 dBTP + 0.1 dB.
9. `EQ_PresetLoudness_SpectrumFamily` (M2): assert the residual on ≥ 5 spectra, or on the LTAS-based
   predictor once EQ2 has it.
10. Replace `EQ_SilenceTail_NoDenormalSlowdown` (m7) with assertions that FZ is set and states are exactly 0.
11. `EQEditKit` "lands exactly" tests use `abs(Δ) ≤ 1e-5` (m9). A contract test asserts that the engine clamps
    targets to ±12 (m8).

## 7. Literature: what I could actually open (all via WebSearch summaries; no full PDF was retrievable)

- **Välimäki & Liski, "Accurate Cascade Graphic Equalizer", IEEE SPL 24(2):176–180, 2017.** I confirmed the
  bibliographic record (dblp, Aalto). The body was not opened, so the bandwidth constants are unverified.
  https://aaltodoc.aalto.fi/handle/123456789/33567
- **Liski & Välimäki, "The Quest for the Best Graphic Equalizer", DAFx-17, pp. 95–102.** Abstract only. It
  covers one SOS per band, error < 1 dB, the bandwidth definition, the interaction estimate and the
  iteration study [C]. https://dafx.de/paper-archive/details/Ycir51R86FWcfPNqrjV2kQ
- **Rämö, Liski & Välimäki, Appl. Sci. 10(4):1222, 2020.** Abstract only: iterative WLS, worst-case error
  **0.81 dB** third-octave and 1.26 dB Bark [C]. https://www.mdpi.com/2076-3417/10/4/1222
- **`acge3.m`** (third-party MATLAB, KPrawda/Two_stage_filter), seen as a search excerpt. It uses a uniform
  17 dB first-pass leakage level, 61 points with linearly interpolated midpoints, and one re-solve from the
  solved gains. That matches the plan's procedure [C].
  https://github.com/KPrawda/Two_stage_filter/blob/main/acge3.m
- **Cytomic `SvfLinearTrapOptimised2.pdf`.** Not opened. The bell formulas are verified numerically instead
  (3.5e-13 dB). https://docs.rs/simper-filter
- **Apple `vDSP_biquad` docs.** They state single precision, DF-I state of 2M + 2, and a setup built from
  double coefficients; the internal precision is undocumented, hence measured here.
  https://developer.apple.com/documentation/accelerate/vdsp_biquad.md
- **Apple `AVAudioEngineConfigurationChange`.** On an I/O channel-count or sample-rate change "the audio
  engine stops, uninitializes itself" [C].
  https://developer.apple.com/tutorials/data/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange.md
- **BS.1770 K-weighting coefficients:** the standard 48 kHz biquads [C]. **Orfanidis 1997:** not
  re-verified (I did not implement the prescribed-Nyquist bell).

## 8. Files (all in this folder)

- **Prototype:** `bkgeq.py`, with the presets transcribed read-only from `EQPreset.swift`.
- **Attacks:** `a1_accuracy.py`, `a1b_longsearch.py`, `a2_nyquist.py`, `a2b_hazard.py`, `a4_transition.py`,
  `a4b_reachable.py`, `a4c_svf_adv.py`, `a5_headroom.py`, `a5b_peakscan.py`, `a6_tone.py`, `a7_loudness.py`.
- **Time domain:** `rt_sim.cpp` (structures, the plan's ramp, the SVF smoother, real vDSP, NaN, FZ),
  `presets_td.cpp`, `td_check.cpp`, `zipper_nopre.cpp`, `fzprobe.cpp`.
- **Inputs:** `gains.txt` (solved gain sets written once by the Python prototype; a static input to the C++),
  `worst_pair.npy`, `worst_cmd_*.npy` (deterministic seeds).
- **Kernel repros:** `repro_realloc.mm` and `repro_blend.mm`, built from the read-only copy `repro_src/AudioDSP`.
- **Outputs:** `out_*.txt`. To re-run everything: `sh run_all.sh`.
