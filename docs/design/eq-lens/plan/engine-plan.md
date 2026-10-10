# Sprint EQ: DSP engine plan, v2 (replaces `dsp-plan-check.md`)

*2026-10-10. This is the revision after the three reviews (breaker, SOTA, architect), the literature and players
surveys, and founder decisions 25–28 (`feat/s10-8-eq` @ d6ab539).
- **Ground rules.** The repo was only read; nothing in it was built or compiled. Every new measurement is
  in `dsp/v2/` and re-runs with `sh run_all.sh` (about 6 min). The C++ simulators and benchmarks were
  compiled in the scratchpad. The machine is an Apple M4 Pro.
- **Labels.**
  - **[M]**: measured here; the result file in `v2/results/` is named.
  - **[R-B] / [R-S] / [R-A]**: a measurement or code read reported by the breaker, SOTA or architect review.
  - **[C]**: a published source (§13).
  - **[code]**: read in the repo, not run.
  - **[O]**: opinion.*

## 0. What changed since v1, in one screen

1. **The EQ is the first stage, ahead of the Intensity blend (decision 25).**
   - The dry tap is taken after the EQ, so the graph is honest at every Intensity.
   - Bit-perfect = Intensity 0 *and* the EQ identity-settled.
   - A new EQ-only path (EQ → limiter) serves Intensity 0 with the EQ On (§5).
2. **Loudness-neutral output gain (decision 26).** The −max|H| preamp, the peak scan, the Headroom readout
   and the "never above source" contract are all gone.
   - The gain is −ΔL, predicted from the track's own gated block spectra (1/24-oct): **≤ 0.112 dB** error on
     the 7-track corpus **[M s4b]**.
   - **This needs a load-time pre-analysis.** A causal running estimate misses the 0.1–0.2 dB target: 0.67 dB
     integrated and 2.7 dB over the first 10 s **[M s4]** (§4).
3. **Transitions: switched to the finished-coefficient SVF smoother ("S2") with an adaptive ramp time.** Per
   band, (k, m1) and the output gain share one one-pole.
   - The v1 shared dB ramp ("S1") raises the overall peak by up to **+6.6 dB** on adversarial pairs, even at
     τ = 40 ms.
   - S2 stays at or below **+1.49 dB** at τ = 40 ms, with the same zipper behaviour as S1 **[M s2c, s2f]** (§3).
4. **Solver: 5 refinement passes (6 solves).**
   - The hard patterns drop from 0.996 to **0.322 dB**, and a Rämö-style 1000-command set measures **0.44 dB**
     at 44.1–192 kHz **[M s1]**.
5. **Re-allocation: `Realizer::reinitializeKernel` runs on the Realizer queue.** It re-solves at the new
   rate, snaps the new module to the published state, re-derives crossfeed, and holds on an fs mismatch (§6).
6. **Guards.** NaN is rejected at the C-ABI, guarded in the solver and checked in the RT. The denormal test
   is now one that can fail **[M s7]** (§7).
7. **The contract is the architect's reconciled one**, amended by decisions 26 and 28:
   - `EQPlayed` loses headroom, peak and loudness;
   - the engine takes only `points` + `isOn`;
   - a track loudness profile flows from playback to the Realizer (§8).

## 1. Disposition of every finding

**Legend.** A = accepted; A* = accepted with a change; X = rejected; S = superseded by a founder decision;
UI = accepted, belongs to the UI lane.

| # | Finding | Disposition | What changed / why (evidence) |
|---|---|---|---|
| B-B1 | Intensity blend breaks "draws what plays" and adds +3 dB | S (dec. 25), A | EQ ahead of the blend (§5); `EQ_ResponseIndependentOfIntensity` at r ∈ {0, 0.2, 0.5, 1} |
| B-M1 | Shared dB ramp overshoots +5.6 dB; the SVF (k, m1) smoother only +0.12 | A | Measured both schemes on both metrics: S2 adopted plus adaptive τ (§3). Frozen peak swell: S1 +6.62 vs S2 +0.00; TD peak at τ 40: S1 +5.4…+6.6 vs S2 ≤ +1.49 **[M s2b, s2f]** |
| B-M2 | Curve-only level match off by up to ±3.9 / +7.3 dB | S (dec. 26), A | Gated block-spectral predictor: 0.112 dB max **[M s4b]**; the pink curve estimate is 3.44 dB **[M s4]** |
| B-M3 | Re-allocation plays flat; seeding unspecified | A | `reinitializeKernel`, snap on first adopt, fs-mismatch hold, `VerifyAUGraph` case (§6) |
| B-m1 | Adversarial command 0.86 dB; use 6–8 passes | A* | 5 passes: the hard set, including the 4 breaker commands, is at most 0.322. 8 passes is *not* better (0.345, non-monotone) **[M s1]** |
| B-m2 | Response above 20.2 kHz sets the preamp (13.62 dB at 44.1 k) | S (dec. 26) | Reproduced: 13.60 vs in-band 12.19 **[M s1b]**. With no preamp it costs no gain; documented as a property (§2.3) |
| B-m3 | The peak scan under-reads by 0.0125 dB; the gate would flake | S (dec. 26) | The scan leaves the product. Test helper tolerance is 0.02 dB |
| B-m4 | \|H\| ≤ 0 dB doesn't bound peaks | A | The guarantee now reads "loudness ±0.11 dB; peaks bounded by the −1 dBTP limiter". Limiter load measured (§4.4); `EQ_Limiter_HoldsAfterCut` |
| B-m5 | Divide-by-gain 0/0 → NaN; NaN targets | A | Guard in the spec (\|g\| < 1e-3 dB → ±1e-3 prototype); an unguarded rebuild is 1891/1891 non-finite; a NaN target crashes the solve **[M s7_guards]**. C-ABI rejects; RT checks coefficients |
| B-m6 | Precision argues against float, not direct form | A | The double SVF is now justified by transition behaviour (§3) and exact identity at m1 = 0, not by precision alone |
| B-m7 | The FZ timing test can't fail | A | Replaced: seeded-subnormal state test. 161 subnormal samples without FZ, 0 with **[M s7_fz]** |
| B-m8 | `points` means opposite things; Compare ≡ Off; Off copy | A | Architect contract (`base`/`points`); dec. 28 (Compare = hold Off); dec. 26 makes Off a true bypass, so "playing the original" is true again |
| B-m9 | float32 "lands exactly" fails at 1e-6 | A | Kit tests use \|Δ\| ≤ 1e-5 dB |
| B-m10 | Intensity not sent at launch | A | Publish every intent on engine-ready, and after re-init via the Realizer (§5.4) |
| B-tests 1–11 | Missing gate tests | A* | All folded into §9. #2's bounds re-derived from TD (realistic local ≤ 0.75 / peak ≤ 0.5; adversarial peak ≤ 2.0). #7 retired with the preamp, replaced by loudness and limiter tests |
| S-1 | Add a 3rd refinement pass | A* | 5 passes (see B-m1). Hard: 0.402 at 3 vs 0.322 at 5 **[M s1]** |
| S-2 | Gated block-spectral predictor (1/12 oct) | A* | 1/24 oct: 0.112 vs 0.180 max on 15 curves; jagged curves need it **[M s4b]** |
| S-3 | Loudness-neutral EQ gain | S (dec. 26) | §4 |
| S-4 | Rämö-style gate set | A | §2.2, §9 |
| S-5 | Evaluate \|H\|² in factored or complex form in C++ | A | A port rule: complex per-section product, never the expanded cos polynomial |
| S-6 | Analog-Nyquist bells for fc > 0.25 fs | A (later) | Not R1 (jagged 0.49 → 0.54 at 44.1 [R-S]); swappable via the single coefficient function |
| S-Q2 | Keep double SVF + the author's ramp; "sidebands are set by the ramp" | A* | Confirmed: SB equals the reference for realistic transitions in **both** schemes **[M s2c]**. But the ramp *path* decides swell, so S2 replaces the dB ramp |
| S-rej | FIR, matched, SGE3, neural, per-rate tables, ultrasonic guard points, float SVF, vDSP | A | Rejections stand; not re-measured |
| S-§3 | Meter resets per `playFile`, not per kernel lifetime | A | v1 §4.3 corrected. The integration window is per track (gapless continuation unchecked) |
| S-§8 | Corrections: "≤ 0.31 everywhere", "3rd pass < 0.02", "±1.2 dB", meter lifetime | A | All corrected here with new data |
| S-pre | "Full-track pre-analysis later; curve fallback for 10 s" | X (moved to R1) | The causal estimate misses the target: 0.67 dB integrated, 2.69 dB in the first 10 s; pre-analysis gives 0.112 **[M s4]**. Founder Q1 |
| S-hdr | "Keep −max\|H\| as a Headroom figure" | S (dec. 26) | The readout is gone |
| A-F1 | EQ inside the blend | S (dec. 25), A* | §5, adding the branch-latency fix the reviews missed: the limiter's 3 ms look-ahead [code] |
| A-F2 | One contract; extend `AudioPlaybackEngine` | A | §8 |
| A-F3 | Re-init race and stale crossfeed | A | §6 |
| A-F4, F5, F7, F8, F11–F14 | Recall edge, UIDs, migration, store, undo toast, stroke API, kit ownership, PR ownership | UI | Unchanged; UI lane (EQ3a, DEV-UID) |
| A-F6 | Trust boundary; delete the clamp script; safety gates | A* | Validation at the C-ABI. The `Safety_EQStep…` gate becomes `Safety_EQToggle_AfterNormaliserAdapted`: loudness step ≤ 0.2 dB, ≤ −1 dBTP |
| A-F9 | Owner-local designer; `played` pure and memoised | A | §8 |
| A-F10 | Compare collapses into Off; Off copy | S (dec. 26/28) | — |
| A-F15 | `PendingSlot<T>` extraction | A | In EQ1b |
| A-F16 | One shared coefficient function | A | `svfBell(gainDb, band) → (k, m1)` and `svfDamping(g, k) → a1..a3`, header-only, shared by the designer, read-back and RT |
| A-F17 | `RtSwappableResource` left untested | A | Keep it with one direct test (it is BRIR's IR-swap path) [O] |
| A-F18, F19 | Log flood; My Presets get stronger | A | Log at stroke end; founder FYI |
| A-§3 | "RT computes coefficients from smoothed dB" (approved) | X | Replaced by finished (k, m1) from the Realizer: dB-path swell is measured (§3) |
| A-§6 | "Steady-state ≤ 0 dB at every frequency" | S (dec. 26) | — |
| A-§7 | Seams: neutral names, S12 general mix, S14 output gain | A | `outputGainDb` stays its own field; (k, m1) per section; m0/m2 later |
| L-1 | Tuning done only at 44.1 k; tune per rate | A* | The interaction matrix is per rate and all six rates are gated. Hand-tuned tables rejected (no gain [R-S]) |
| L-2 | Band formula pluggable | A | Via F16 |
| L-3 | "< 1 dB" covers centres only | A | The graph draws dense \|H\|. Midpoints are logged |
| L-4 | Top-band physics | A | §2.3 table |
| L-5 | Headroom is not peak safety | A | The limiter stays the guarantee; load measured |
| L-6 | No vDSP ramping; prefer TDF-II | A / X | vDSP ramping: not used. TDF-II: rejected, because its edge was for unsmoothed jumps only [R-S, C Wishnick] |
| L-7 | Precision at high fs | A | Double SVF |
| L-8 | Compare to ≤ 0.1–0.2 dB | A | Met only with pre-analysis (§4.3) |
| L-9 | Clamp after summing macros | A | `points = clamp(base + Σ tone·w, ±12)` |
| L-10 | Licensing | A | Implemented from the equations; no third-party code |
| P-xfade | Equalizer APO 10 ms crossfade | X | Phase-cancellation dips to −47 dB mid-fade, 2× CPU [M v1] |
| P-rockbox | `volume += prescale` | S (dec. 26) | Not needed: the gain is loudness-neutral |

## 2. E1: the accurate graphic EQ (design unchanged, solver deepened)

### 2.1 Form

| Item | Choice |
|---|---|
| Centres | `f_m = 10^(1.3+0.1m)`, m = 0…30 (nominal ISO labels in the UI) |
| Band filter | Bilinear bell ≡ TPT SVF bell: `g_m = tan(ω_m/2)`, `A = 10^(G/40)`, `k = k0_m/A`, `m1 = k(A²−1)`, `k0_m = 2tan(0.2ω_m)/sin ω_m` (half-dB bandwidth 0.40·ω_m). A cut is the exact inverse of a boost |
| Solve | 61 points (centres + geometric midpoints, midpoint target = mean of neighbours); WLS with weights 1 / 0.5; first pass at a 17 dB prototype; **5 refinement passes** rebuilding B from the previous gains with the guard \|g\| < 1e-3 dB → ±1e-3. Normal equations + 31×31 Cholesky in double (cond ≈ 8–9 [M v1, R-B]) |
| Output | Finished per-band (k, m1) in double, from one shared header function (F16) |
| Cost | About 0.14 ms per design in C++ [O: SOTA's 75 µs for 3 solves + scan, plus 3 more solves at ~20 µs each, with no scan] |

### 2.2 Accuracy at the 31 centres, worst over 44.1/48/88.2/96/176.4/192 kHz [M s1]

| Set | Passes 2 | 3 | **5** | 8 |
|---|---|---|---|---|
| Presets / 100 Tone settings | 0.084 / 0.081 | 0.084 / 0.081 | **0.084 / 0.081** | 0.084 / 0.081 |
| 200 smooth (6-knot) curves | 0.155 | 0.156 | **0.157** | 0.157 |
| Rämö set: 500 binary {−12, 0, 12} + 500 integer | 0.503 | 0.464 | **0.440** | 0.440 |
| Hard: alternating, every-third (×6), cliffs (×16), singles, edge pair, ±all, 4 breaker commands | 0.996 | 0.402 | **0.322** | 0.345 |

The papers report 0.97 dB (ACGE3) and 0.81 dB (SGE3) worst over 10 k random settings [C Rämö 2020, via
R-S/literature]. Our 0.44 on 1000 Rämö-style commands is better, which agrees with the SOTA reviewer's
independent build [R-S].

### 2.3 Above 20 kHz: a documented property, not a defect [M s1b]

| Curve | 44.1 k: 21 / 22 kHz | 48 k: 22 kHz | 96 k: 25 / 30 kHz | 192 k: 25 / 30 / 40 kHz | Max above 20.2 kHz vs in-band peak (44.1 k) |
|---|---|---|---|---|---|
| +12 @ 20 kHz | +11.4 / +0.2 | +8.8 | +5.3 / +2.1 | +5.5 / +2.7 / +0.9 | 12.41 vs 12.12 |
| Edge −12/+12 (16k/20k) | +13.2 / +0.4 | +9.7 | +4.6 / +2.0 | +4.6 / +2.2 / +0.8 | **13.60 vs 12.19** |
| All +12 / Tone Air +12 | +10.1 / +0.2 | +7.4 | +4.7 / +1.7 | +5.1 / +2.4 / +0.8 | 11.81 vs 12.29 |

- Under decision 26 nothing derives a gain from the peak.
- The loudness predictor integrates to Nyquist, so the ultrasonic boost is accounted for.
- The limiter catches any true-peak effect.
- Gate: logged, plus a bound of in-band peak + 1.5 dB at 44.1 kHz.

## 3. Transitions: the conflict, measured on every metric

**The two schemes, both on a double TPT SVF, with the loudness-neutral output gain on the same one-pole:**
- **S1 (v1):** a shared dB one-pole on the 31 solved gains + the output gain; 32-sample control rate;
  coefficients interpolated linearly.
- **S2 (breaker):** per-band finished (k, m1) + the output gain (dB) on one one-pole per sample; a1..a3
  recomputed from k (one divide per band per sample).

**The metrics.** Both endpoints carry their own −ΔL gain, so "above source" no longer applies. The question is
whether the transition is louder than the louder endpoint.
- **Frozen path:** the response at intermediate parameter states.
  - *local* = max_f [net_s(f) − max(net_A(f), net_B(f))];
  - *peak* = max_f net_s − max(max net_A, max net_B);
  - *loud* = pink K-weighted loudness above the louder endpoint.
- **Time domain (TD):** 48 sine probes through `cpp/tdsim`.
  - local / peak: the post-switch envelope against the steady amplitudes;
  - SB: Wishnick sideband energy (85 ms Hann, ±1 ERB removed) [C];
  - Etr: error against an ideal analytic dB/phase crossfade.

### 3.1 Results

| Transition set | Frozen local / peak / loud: S1 | S2 | TD local / peak at τ 10 ms: S1 | S2 |
|---|---|---|---|---|
| 42 preset pairs (incl. Off) | 0.00 / 0.00 / 0.00 | 0.01 / 0.00 / 0.00 | +0.28 / +0.03 | +0.28 / +0.03 |
| Off ↔ hard patterns | 2.12 / 0.82 / **1.05** | 2.10 / 0.00 / 0.02 | — | — |
| Off → all +12 | 0.03 / 0.00 | 0.16 / 0.00 | +0.43 / +0.33 | +0.47 / +0.37 |
| Off ↔ alternating | — | — | +2.23 / 0.00 | +1.09 / 0.00 |
| 100 Rämö pairs | 4.44 / 1.88 / 0.18 | 4.17 / 0.13 / 0.00 | — | — |
| Breaker worst pair A→B | 5.42 / **4.96** | 0.30 / 0.00 | +5.41 / **+5.41** | +2.89 / +0.31 |
| S1's own adversarial | 7.50 / **6.62** | 0.71 / 0.00 | +6.94 / **+6.59** | +4.01 / +1.48 |
| S2's own adversarial | 3.44 / 1.52 | 6.25 / 0.00 | +12.9 / +3.30 | +12.6 / +3.27 |
| Realistic drag (Warm, 125 Hz → +12) | — | — | +0.08 / +0.01 | +0.08 / +0.01 |

Sources: [M s2b frozen, s2c TD, s2e drag]. Frozen loudness bump on the 3 named adversarial pairs: S1 up to **+2.98 dB**, S2 +0.00.

**Slowing the ramp separates the schemes** [M s2e, s2f]. On the 4 adversarial pairs at τ 40 ms, the TD peak is:
- S1: **+0.50 / +5.39 / +5.43 / +6.64 dB**. Its swell is in the path, so ramp time doesn't help.
- S2: +0.01 / +0.08 / +0.31 / **+1.49** dB.

**Sidebands and tracking** [M s2c]:
- **Realistic transitions** (Off → Warm, Warm → Presence, Presence → Off at 100 Hz / 1 kHz / 4 kHz): both
  schemes give the *same* SB, within 0.3 dB of SBref in 8 of 9 cases and +1.8 dB in one (Presence → Off at
  4 kHz, identical for S1 and S2). This confirms SOTA's "set by the ramp"; the structure adds nothing.
- **Tracking:** S2 is equal or better (Etr −70 vs −61 dB at Off → Warm 1 kHz).
- **Jagged transitions:** both exceed SBref by 5–10 dB. S2 is better on the breaker pair at 1 kHz
  (SB −46 vs −41; Etr −26 vs −12 dB); S1 is better on alternating → Off at 4 kHz (Etr −35 vs −27).

### 3.2 Decision

- **S2 with an adaptive τ.** τ = 10 ms when the largest per-band change in *solved* filter gain is ≤ 12 dB
  (every preset, Tone, drag and Off toggle of a normal curve). τ = 40 ms above that (jagged and adversarial
  jumps).
- **The loudness-neutral gain rides the same one-pole as (k, m1)** in every measurement above. A separate gain
  ramp is what overshot in v1: today's 32 ms `masterGainLinear` against a 10 ms filter ramp gave +5.4 to
  +6.9 dB [M v1 results/09].
- **Gain-only updates** (a new track profile) glide at τ = 500 ms on the output gain alone, which cannot
  swell.
- **Why S2:**
  - It never raises the overall peak or loudness of the frozen path beyond the louder endpoint (≤ +0.13 dB
    peak, ≤ +0.02 dB loudness, across every set).
  - Its residual is a structural transient that a slower τ removes.
  - It restores "the RT runs finished coefficients".
  - At its cost, the zipper and sidebands are equal to S1.
- **Local swells on jagged pairs remain** (S2's own adversarial: +7.0 dB at 25 Hz at τ 40, with peak +0.01).
  They sit at a low absolute level, and the limiter is downstream. Accepted [O].
- **Gate (TD):**
  - realistic set at τ 10: local ≤ **+0.75 dB**, peak ≤ **+0.5 dB** (measured 0.47 / 0.37);
  - pinned adversarial pairs at τ 40: peak ≤ **+2.0 dB** (1.49), local logged.
  - The v1 "≤ +0.05 dB" bound is retired: it was a frozen-model figure (B-M1).

## 4. The loudness-neutral output gain (decision 26)

### 4.1 Predictor (the SOTA design, re-implemented, at 1/24-octave)

- **Profile.** For each BS.1770 block (400 ms, 100 ms hop), store the K-weighted source power in 1/24-octave
  bins from 20 Hz to Nyquist, channel-summed with the BS.1770 channel weights.
  - That is about 264 floats per block, or about 2.5 MB for 4 minutes.
  - Use one 400 ms FFT per block. Summing 100 ms hop spectra is 4× cheaper but errs by 0.42 dB, because a
    100 ms hop cannot resolve 1/24 octave at 20 Hz **[M s4d]**.
- **Prediction for a curve.** ΔL = gated(Σ_b P_blk(b)\|H(f_b)\|²) − gated(Σ_b P_blk(b)), using the real
  two-stage BS.1770 gating. The output gain is −ΔL, which stays inside ±12 dB because all ±12 dB curves do.
- **Accuracy** on 7 tracks × 15 curves (presets, single ±12, Tone, all −12, alternating) **[M s4b]**:

  | Predictor | Max error | p90 |
  |---|---|---|
  | 1/24 octave (recommended) | **0.112 dB** | 0.036 |
  | 1/12 octave | 0.180 | 0.046 |
  | 1/6 octave | 1.27 | 0.37 |
  | Curve on pink (v1) | 3.44 | 2.51 |

### 4.2 Where it runs

- **`TrackLoudnessProfiler`** (pure C++, AudioDSP): PCM in, an immutable profile out.
- **Pre-analysis job.** At track load, and for the next queued track (gapless prefetch), the playback layer
  decodes the file a second time on a utility-QoS thread and builds the profile.
  - Estimated time: ~0.5 s of FFT plus ~0.2–0.4 s of decode for a 4-minute track on M1 [O: arithmetic on
    vDSP FFT throughput].
  - The finished profile is handed to the Realizer.
- **Realizer.** Holds `shared_ptr<const Profile>` for the current track and computes −ΔL at every EQ solve,
  about 0.3–0.6 ms for 4 minutes [O].
  - During a drag, the gain is computed on a 4× decimated block set and refreshed in full at stroke end [O].
  - When a profile arrives or the track changes, a gain-only publish is made (τ 500 ms).
- **Not in a kernel module.** So it survives AU re-allocation.
- **Phase 2 (the system tap):** a causal profiler fed from the kernel input (the LoudnessModule SPSC-worker
  pattern). Not in R1.

### 4.3 First seconds, and On ↔ Off fairness [M s4, s4c]

| Gain schedule | On vs Off integrated, max / p90 | First 10 s, max / p90 |
|---|---|---|
| **Load-time pre-analysis (static per track)** | **0.112 / 0.036 dB** | (same, static) |
| Causal: pink prior for 0–3 s, running estimate every 1 s, slew 1 dB/s | 0.666 / 0.361 dB | 2.69 / 1.04 dB |

- The running estimate is still off by 5.8 dB max (p90 1.7) at 10 s and 0.37 dB at 30 s.
- Even the 3.7-minute track is off by 0.21 dB integrated (static: 0.031).
- **Before the profile lands** (the first track the user starts, ~1 s [O]): use the pink-curve prior
  (≤ 3.4 dB off), then glide over 500 ms.
- **Inherent, and not chased:** within a track, 3 s short-term On vs Off still wanders, because the music's
  spectrum moves. The p05–p95 range is −0.8…+0.9 dB (Warm), −1.2…+0.8 dB (Presence) and −2.9…+0.9 dB (the
  strong Tone) **[M s4c]**. Tracking it would pump [R-S]. Disclose it; don't call Compare perceptually exact
  [C literature §5].

### 4.4 Interaction with the normaliser and the limiter (chain from the code)

- **The chain** (decision 25):
  input → **EQ** → dry tap → Clarity → BRIR → Crossfeed → blend → Loudness (−16 LUFS, −20…+12 dB,
  0.1 dB/100 ms) → limiter (−1 dBTP, 8× ISP, 3 ms look-ahead) [code].
- **The normaliser** measures after the blend and sees the source loudness ±0.11 dB whatever the EQ does, so
  EQ edits, Off and Compare no longer perturb it.
  - The v1 problem, a preamp that cost 1.7–12 dB and was won back only slowly [R-S], is gone.
- **Limiter load at −16 LUFS** (4× true peak over −1 dBTP): worst **+1.50 dB on 0.56 % of 10 ms frames**; the
  source alone never exceeds −1 dBTP (−0.81) **[M s4]** (SOTA: +1.2 dB / 0.5 % [R-S]).
- **At Intensity 0** (no normaliser; §5): the EQ'd source at its own loudness loads the limiter more **[M s5b]**:

  | Track | Source | EQ On, worst curve |
  |---|---|---|
  | Synthetic −9 LUFS master | +0.79 dB, 7.9 % of frames | **+4.29 dB, 8.9 %** |
  | Generated tracks | ≤ +0.24 dB, ≤ 0.04 % | up to +3.0 dB, ≤ 3.2 % |

  That is the price of a level-fair On ↔ Off at Intensity 0 (founder Q2).

## 5. Intensity and the kernel order (decision 25)

### 5.1 Paths

**Notation.** `eqIdentity` means every m1 is exactly 0, the output gain is exactly 0 dB and the ramp is
settled. Off and a flat curve both settle there bit-exactly. "Settled-0 for 2 s" is a hysteresis.

| Path | When | Chain |
|---|---|---|
| P0 bit-perfect | Intensity settled at 0 **and** `eqIdentity` for ≥ 2 s | return (input untouched); the limiter's delay ring is primed with the input |
| P1 EQ-only | Intensity settled at 0, otherwise | EQ → limiter (no normaliser, so On ↔ Off stays level-fair) |
| P2 full | Intensity settled at 1 | EQ → Clarity → BRIR → Crossfeed → Loudness → limiter |
| P3 blend | otherwise | EQ → **dry snapshot** → coloration → blend → Loudness → limiter |

- The limiter delays the signal by its 3 ms look-ahead; P0 doesn't [code: `LimiterModule.h` ring read].
- **So a P0 ↔ P1/P3 switch skips or repeats 3 ms.** Leaving P0 today plays 3 ms of the limiter's *stale*
  ring, because it hasn't run since [code]. This is a pre-existing glitch on every Intensity 0 → >0 move,
  and decision 25 adds EQ toggles at Intensity 0.
- **The fix:**
  - prime the limiter ring while in P0 (write-only, no detection);
  - switch with a 5 ms equal-gain crossfade between the undelayed and delayed streams;
  - add the 2 s hysteresis, so most Compare holds at Intensity 0 never switch.
- Gate `Kernel_PathSwitch_NoGlitch`.

### 5.2 What the gates now vary

Every EQ gate runs at r ∈ {0, 0.2, 0.5, 1}, plus the path transitions:
- **Shape:** the EQ'd output divided by the identity-EQ output at the same r equals the read-back within 0.05 dB.
- **Bit-perfect:** only in P0.
- **Loudness:** On ↔ Off neutral at every r.
- **Limiter:** −1 dBTP holds at every r.

`makeIdentityState()` must stop being the only intensity the EQ tests use [R-B].

### 5.3 Equal-power blend

- With today's stub coloration, r = 0.2 gives +2.0 dB pre-normaliser and r = 0.5 gives +3 dB [arithmetic].
- That is a level change, not a shape change; the normaliser absorbs it.
- It is independent of the EQ now.

### 5.4 Launch publish

- On engine-ready, publish every intent from the view model: Intensity, crossfeed and EQ.
- After re-init, the Realizer republishes its canonical state.
- **FYI for the founder:** launch then plays the displayed 20 %, not today's hidden 100 %. With stub
  coloration the audible difference is only the normalised blend level [O].

## 6. Re-allocation (architect F3, breaker M3)

- **`Realizer::reinitializeKernel(fs, frames)`.**
  - **Entry:** called from `allocateRenderResources` and executed with `dispatch_sync` on the Realizer's
    serial queue. That serialises it with every publish (the use-after-free race [R-A]). The Realizer never
    waits on the allocate thread, so it cannot deadlock [code].
  - **Steps:**
    1. `kernel->initialize(fs, frames)`.
    2. Re-solve the EQ from the stored **points** at the new fs, and re-predict the gain from the profile at
       the new fs.
    3. Re-derive the crossfeed coefficients at the new fs.
    4. Bump the sequence and publish once.
- **Seeding.** `EQModule::initialize` sets `snapOnFirstAdopt`. The first EQParams it adopts are applied
  without a ramp and the states are zeroed, so there is no fade-in from identity. No audio is rendering yet,
  so this cannot click.
- **fs guard.** If `eq.designSampleRate ≠ module fs`, hold the last good coefficients (identity if none).
  Never run coefficients designed for another rate; they are off by 1.41–2.89 dB [R-B].
- **Ownership.**
  - The Realizer owns fs, so the per-slot `sampleRate` fields and the Swift bus-rate read go.
  - The track loudness profile lives in the Realizer, so it survives.
  - The normaliser's meter resets in `initialize` (existing behaviour; noted).
- **Gates:**
  - `EQ_Reallocate_KeepsCurve` (same fs, ≤ 0.1 dB);
  - `EQ_Reallocate_NewRate` (Air +12 designed at 48 k, re-init at 44.1 k);
  - `Realizer_ReinitDuringDrain` (tsan);
  - `Crossfeed_RederivedOnRateChange`;
  - `VerifyAUGraph`: stereo → 6 ch → stereo keeps the EQ.

## 7. RT structure, guards, cost

- **TargetState.eq:** `double k[31], m1[31]; double outputGainDb; float designSampleRate; uint8 flags` (slow
  ramp / gain-only / identity), plus a generation. About 520 B, so the TargetState size assert is re-measured
  and the golden master re-baselined, with documentation.
- **Per sample, while ramping:**
  - (k, m1, output gain) one-pole;
  - a1 = 1/(1 + g(g + k)), a2 = g·a1, a3 = g·a2;
  - the SVF tick across channels (SIMD).
- **Settled:** snap at a relative 1e-12, then skip the smoothing. At identity, skip the cascade and zero the
  states.
- **CPU** (% of one core) **[M s5]**:

  | Load | Ramping | Settled |
  |---|---|---|
  | 192 kHz × 8 ch | 2.67 % | 2.00 % |
  | 48 kHz × 2 ch | 0.63 % | 0.29 % |

  M1 Pro estimate: ×1.4–1.8 → ≤ ~4.9 % [O].
- **NaN guards (all four layers):**
  1. The C-ABI rejects any non-finite point and clamps to ±12.
  2. The designer guards \|g\| < 1e-3 dB and returns false on any non-finite result, so the Realizer keeps
     the last good design.
  3. The profile and predictor reject non-finite values and keep the last gain.
  4. The RT checks `isfinite` on the 63 adopted values and ignores a bad snapshot; it checks the states per
     block and zeroes them on failure.
- **Peak scan:** product use is gone. A 1024-point scan with refinement remains as a test helper (tolerance
  0.02 dB; under-reads up to 0.0125 dB [R-B]).
- **Denormals:**
  - Assert FPCR.FZ inside the render block (test hook).
  - Run the seeded-subnormal test: states seeded at 1e-300, silence in, the slowest band (20 Hz @ 192 k). It
    finds 161 subnormal samples without FZ and 0 with FZ **[M s7_fz]**.
  - Exact zero is not a usable criterion: the decay takes over 200 k samples.

## 8. The ENGINE ↔ UI contract (the architect's reconciled contract, amended)

- **`EQEditKit`** (pure, zero dependencies): exactly as in architect §2. That covers `EQBands`,
  `EQToneRegion` (§6 weights unchanged), `EQCurve` {base ±24, tone ±12, `points`}, `EQBuiltInPreset`
  (stable ids), `EQPresetRef`, `EQState` {preset, curve, isOn}, `EQOutputKey`, `EQStore`, `EQMigration` and
  `EQStroke`. One amendment: **`EQPlayed` = {static frequencies (256), `responseDb[256]`, `centreDb[31]`,
  `sampleRate`}**. Headroom, peak and loudness are dropped (decision 26).
- **App:**
  - `AudioPlaybackEngine.publishEQ(points:isOn:)` with `isOn = current.isOn && !isComparing` (decision 28:
    the hold is Off);
  - `eqSampleRate()`;
  - `EQDesigner.played(points:sampleRate:)`, owner-local and memoised;
  - the view model as in architect §2.

  The UI builder needs nothing else.
- **Engine-internal (playback layer → Realizer, not UI):**
  - `publishTrackLoudnessProfile(au, trackToken, profile)`;
  - `setCurrentTrack(au, trackToken)`, called where `publishChannelLayout` is called today and at the
    gapless seam.
- **C-ABI:**
  - `asEqDesignerCreate`, `asEqDesignerDestroy`;
  - `asEqDesign(designer, points, 31, fs, out)` with `out` = {responseDb, centreDb, k, m1, fs};
  - `publishEQ(au, points, 31, isOn)`: validates, then the Realizer solves, predicts the gain and publishes;
  - `eqDesignSampleRate(au)`;
  - `asLoudnessProfiler*`.
- **Engine rules:**
  - On: (k, m1) from the design, gain −ΔL(profile).
  - Off: identity. It is a true bypass and level-fair, because On is matched.
- **Off copy:** "Equalizer off" can again say "playing the original".

## 9. The C++ gate (extends `Tests/*.inc`; runs under `make gate`, `sanitize`, `tsan`)

| Test | Bound (measured) |
|---|---|
| `EQ_ACGE_Presets_Tone_Smooth` × 6 rates | ≤ 0.2 / 0.2 / 0.3 dB (0.084 / 0.081 / 0.157) |
| `EQ_ACGE_Ramo1000` (seeded binary + integer) × 6 rates | ≤ 0.6 (0.440) |
| `EQ_ACGE_Hard` (incl. the 4 breaker `.npy` commands, pinned) × 6 rates | ≤ 0.6 (0.322) |
| `EQ_ACGE_SingleBand` ±6/±12 every band, analytic and Goertzel | ≤ 0.25 / 0.3 (0.142) |
| `EQ_Ultrasonic_Property` | ≤ in-band peak + 1.5 dB at 44.1 k (1.41); logged |
| `EQ_ReadbackEqualsEngine`: settled RT (k, m1) == design, and Goertzel vs `responseDb` | bit-exact; ≤ 0.05 dB |
| `EQ_ResponseIndependentOfIntensity`, r ∈ {0, 0.2, 0.5, 1} (B-1) | shape vs read-back ≤ 0.05 dB |
| `EQ_BitPerfect_P0` / `EQ_Off_BitExact` / `EQ_Flat_BitExact` | bit-identical |
| `Kernel_PathSwitch_NoGlitch` (P0 ↔ P1/P3, Intensity 0 ↔ 0.2, EQ toggles) | no sample step > 1.2× the input's max slope |
| `EQ_Transitions_Realistic` (TD; 42 preset pairs, Off ↔ presets, Tone, smooth, drags; τ by rule) (B-2) | local ≤ +0.75, peak ≤ +0.5 dB (0.47 / 0.37) |
| `EQ_Transitions_Adversarial` (pinned `worst_pair.npy`, `adv_pair_S1/S2.npy`, alt flip; τ 40) | peak ≤ +2.0 dB (1.49); local logged |
| `EQ_ZipperFree` (Off → Warm, Warm → Presence, Presence → Off: SB vs analytic reference) | SB ≤ SBref + 3 dB (+1.8) |
| `EQ_LoudnessNeutral_OnOff`: deterministic synthetic programme families (tilted noise with gated dynamics, ≥ 5 spectra; B-9), integrated, libebur128 oracle; the research WAVs as an optional local run | ≤ 0.15 dB (0.112 on the corpus) |
| `EQ_Predictor_Table`: −ΔL per preset on fixtures | ±0.05 dB regression |
| `EQ_Limiter_HoldsAfterCut` (clipped master, cut curve, full chain) (B-8) | TP ≤ −1 dBTP + 0.1 |
| `Safety_EQToggle_AfterNormaliserAdapted` | loudness step ≤ 0.2 dB; TP ≤ −1 dBTP |
| `EQ_Reallocate_KeepsCurve`, `EQ_Reallocate_NewRate`, `Realizer_ReinitDuringDrain` (tsan), `Crossfeed_RederivedOnRateChange` (B-4, B-5) | ≤ 0.1 dB; re-solve or hold; no race |
| `VerifyAUGraph`: stereo → 6 ch → stereo keeps the EQ (B-5) | played response unchanged ≤ 0.1 dB |
| `EQ_Design_Rejects_NonFinite`, `EQ_Design_FlatFinite`, `EQ_PublishRejectsNonFinite`, `EQ_RT_IgnoresBadSnapshot`, `EQ_NaNInput_Recovers` (B-6) | false or kept; recover in 1 block |
| `EQ_FZ_Set_OnRenderThread`, `EQ_NoSubnormalStates` (B-10) | FZ = 1; 0 subnormal (fails without FZ) |
| `Designer_TwoThreads` (tsan), `Designer_Timing` | no race; ≤ 0.25 ms M1 budget [R-A] |
| `Soak_DSPKernel_ZeroRtAlloc_*`: 8 ch, random targets every 10 ms, all 4 paths | 0 allocations |
| `EQ_Cpu_7_1_192k` | report; ≤ 5 % (2.67) |
| Golden master + crossfeed hash re-baseline (documented) | new hashes |

Kit tests (Swift): Tone partition, landing \|Δ\| ≤ 1e-5 dB (B-9), the engine-side ±12 clamp contract (B-11),
and the migration fixtures [R-A].

## 10. PR split (the architect's lanes; my sizes)

| PR | Scope | Size | Depends on | Lane |
|---|---|---|---|---|
| EQ0 | Kit value types + `AudioPlaybackEngine` extension | 0.5 | — | day 1 |
| DEV-UID | Device UIDs + identity-change edge | 0.5 | — | day 1 |
| EQ1a | `GraphicEQDesigner` (5 passes, (k, m1), read-back) + `asEqDesign` + `EQDesigner` | 1.5 | — | DSP |
| EQ1b | SVF module + S2 smoother + adaptive τ + identity bypass + guards; EQParams relayout; Realizer (points/isOn, fs, `reinitializeKernel`, `PendingSlot<T>`, crossfeed); **kernel paths P0–P3 + limiter priming/crossfade**; launch publish; golden re-baseline | 4 | EQ1a | DSP |
| EQ1c | `TrackLoudnessProfiler` + load-time/prefetch analysis job + Realizer predictor + gain-only glides + pink prior + track hooks; oracle tests | 2.5 | EQ1a (∥ EQ1b); integrates after EQ1b | DSP |
| EQ2 | Bridge cut-over; delete `EQSafetyClamp`, its script and the `.gitignore` line; doc annotations | 1 | EQ1b, EQ1c, EQ3a | DSP |
| EQ3a / EQ3 / EQ3t / EQ4 | As the architect specified | 2 / 3 / 2 / 2 | — | UI |

- The DSP lane totals 9.5 points (the architect had 6). EQ1c is new under decision 26 (+2.5), and the path
  work adds +0.5.
- The critical path is about 10 points, because EQ1c's profiler runs in parallel with EQ1b.
- The UI lane is unchanged and can start on EQ0 from day 1.

## 11. Questions for the founder (recommended option first)

1. **Analyse each song when it loads,** for the loudness-neutral EQ.
   - **(A, recommended)** A ~1 s background pre-scan per track, done ahead for the next track. Off ↔ On
     stays within 0.11 dB.
   - (B) Estimate while playing. That is cheaper, but the level is off by up to 2.7 dB in a song's first
     10 s and 0.67 dB overall.
2. **At Intensity 0 with the EQ On, the safety limiter works harder on loud masters.** It reaches up to
   ~4 dB on ~9 % of moments for a −9 LUFS master with +12 dB bass.
   - **(A, recommended)** Accept it. Off and On stay equally loud, and the bit-perfect Off is unchanged.
   - (B) Run the loudness normaliser there too. On would then jump in level against the bit-perfect Off.
3. *FYI:* after the launch fix, the app plays the 20 % Intensity it already shows.

## 12. Residual risks

- **Jagged ↔ jagged switches:** local transients up to +7 dB at 25 Hz (low absolute level); the TD peak is
  ≤ +1.5 dB at τ 40. The limiter covers them [M].
- **Compare:** short-term level wanders ±1 dB within a song; this is inherent [M].
- **The first track the user starts:** ≤ ~1 s on the prior (≤ 3.4 dB off) before the profile lands [M/O].
- **Ultrasonic boost** up to +5.5 dB at 25 kHz at high rates; a property [M].
- **Profile memory:** about 2.5 MB per 4-minute track, for the current and next tracks only [arithmetic].

## 13. Sources

Opened in this session or the last, via search results; full texts were opened by the SOTA reviewer and the
literature survey.
- V. Välimäki & J. Liski, "Accurate Cascade Graphic Equalizer," IEEE SPL 24(2):176–180, 2017.
  https://aaltodoc.aalto.fi/handle/123456789/33567
- J. Liski & V. Välimäki, "The Quest for the Best Graphic Equalizer," DAFx-17.
  https://dafx.de/paper-archive/details/Ycir51R86FWcfPNqrjV2kQ
- J. Rämö, J. Liski & V. Välimäki, "Third-Octave and Bark Graphic-Equalizer Design with Symmetric Band
  Filters," Appl. Sci. 10(4):1222, 2020. https://www.mdpi.com/2076-3417/10/4/1222
- J. Liski, J. Rämö & V. Välimäki, "Graphic Equalizer Design with Symmetric Biquad Filters," WASPAA 2019.
  https://research.aalto.fi/en/publications/graphic-equalizer-design-with-symmetric-biquad-filters/
- A. Wishnick, "Time-Varying Filters for Musical Applications," DAFx-14 (the SB metric; full text opened by
  R-S). https://dafx.de/paper-archive/2014/dafx14_aaron_wishnick_time_varying_filters_for_.pdf
- ITU-R BS.1770-5 (K-weighting, gating, true peak; via the literature survey).
  https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf
- A. Simper (Cytomic), trapezoidal SVF (bell form verified numerically, 3e-10 dB cascade agreement [M]).
  https://docs.rs/simper-filter
- Apple `vDSP_biquadm_SetTargetsDouble` (not used).
  https://developer.apple.com/documentation/accelerate/vdsp_biquadm_settargetsdoubled.md
- FabFilter Pro-Q Auto Gain (curve-based; superseded by our track-based predictor).
  https://www.fabfilter.com/help/pro-q/using/output
