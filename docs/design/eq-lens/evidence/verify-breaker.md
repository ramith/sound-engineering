# Verify pass: breaker findings against `dsp-plan-v2.md`, `ui-plan-v2.md` and decisions 25–28

*2026-10-10. Reviewer 1 ("the Breaker"). This is the one bounded re-check.*

- **Repo:** read only; nothing in it was built or edited.
- **Re-runs:** `sh verify_run.sh` in this folder; outputs are in `out_v*.txt` and `out_repro_pathstep.txt`.
- **Labels:** [M] measured here, [C] cited, [O] opinion, [code] read in the repo.
- **v2 artefacts:** I read the author's v2 scripts only after my own runs, to compare numbers (§3).

## 1. Disposition of my findings

| # | Status | Evidence |
|---|---|---|
| B1 Intensity blend | **CLOSED** | Decision 25 puts the EQ ahead of the dry tap. With the stub coloration, out = (cos + sin)·EQ(x): the shape is exact at every r, and the level is the normaliser's job. The gate runs at r ∈ {0, 0.2, 0.5, 1} |
| M1 Transition overshoot | **PARTIAL** | The switch to S2 (finished (k, m1)) is right, and realistic sets stay inside the bound (§2.3). **The adversarial bound is refuted.** In a time-domain (TD) search of S2 under v2's own adaptive-τ rule, I found **+4.51 dB** peak at τ 40 (claim ≤ +1.49, gate ≤ +2.0), and **+2.42 dB** on a pair the rule sends to **τ 10** (only 3 bands differ; max solved change 11.5 dB) [M]. See §2.1 |
| M2 Level match | **CLOSED** | I re-implemented the gated 1/24-octave block predictor with a Hann window. On 14 curve × programme cases it errs ≤ 0.152 dB on 13; the 14th errs 0.354 dB, and 0.002 dB once the window is rectangular [M]. **A port rule is needed:** with a Hann window it errs **−0.36 dB**, and with Blackman-Harris **−0.59 dB**, on a tonal 808 track with +12 @ 100 Hz [M]. The author's code uses no window, which is correct. The time before the profile exists is not closed (§2.2) |
| M3 Re-allocation | **CLOSED** (design) | `reinitializeKernel` runs on the Realizer queue, snaps on first adopt, holds on an fs mismatch and re-derives crossfeed. Gates: `EQ_Reallocate_*` and `VerifyAUGraph` stereo → 6 → stereo |
| m1 Solver passes | **CLOSED: rejection accepted** | v2's "5 passes" are 5 refinements = 6 solves. On my 4 pinned commands, worst over 6 rates: 3 refinements 0.346–0.402, **5 refinements 0.225–0.323**, 8 refinements 0.240–0.345 [M]. So 8 is not better, and 5 is right |
| m2 Above 20 kHz | **CLOSED** (superseded by decision 26) | No gain is derived from the peak any more. Note: an adversarial search at 44.1 k finds an ultrasonic excess of **+2.07 dB** over the in-band peak [M]. That breaks `EQ_Ultrasonic_Property`'s "in-band + 1.5 dB" if the gate ever uses random commands. Keep it to named curves or raise the bound to 2.5 |
| m3 Peak scan | **CLOSED** (superseded) | The scan is test-only, with a 0.02 dB tolerance |
| m4 Peaks with \|H\| ≤ 0 | **CLOSED** | The guarantee is restated; `EQ_Limiter_HoldsAfterCut` is added |
| m5 NaN / 0/0 | **CLOSED** | Four guard layers; the RT checks the adopted (k, m1) |
| m6 Precision rationale | **CLOSED** | — |
| m7 Denormal test | **CLOSED** | The seeded-subnormal test can fail without FZ (161 vs 0 samples, the author's [M]) |
| m8 Contract | **CLOSED** | `base` / `tone` / `points` everywhere (`ui-plan-v2.md:16-18`). Compare = hold Off (decision 28). The C-ABI clamps to ±12 |
| m9 Float "exact" | **CLOSED** | Kit tolerance 1e-5 dB |
| m10 Launch Intensity | **CLOSED** | Every intent is published on engine-ready and after re-init |
| Gate #1, #3–#11 | **CLOSED** | Folded into v2 §9 (#7 retired with the preamp) |
| Gate #2 Transitions | **PARTIAL** | The pinned set lacks my two TD-found pairs (`v3_worst_tau40.npy`, `v3_worst_tau10.npy`); both would fail the ≤ +2.0 / ≤ +0.5 bounds |

## 2. New issues in what v2 introduced (BLOCKER / MAJOR only)

### 2.1 MAJOR: S2's adversarial bound is not +1.49 dB, and the τ rule sends jagged edits to τ 10 (re-opens part of M1)

- **Method** [M] (`v3_s2td.cpp`, `v3_s2search.py`).
  - S2 runs per sample: (k, m1) and the output gain in dB share one one-pole; a1..a3 are recomputed.
  - The output gain is loudness-neutral, with a pink stand-in for −ΔL.
  - Probes: 1/3-octave sines from 20 Hz to 16 kHz.
  - Metrics are v2's: *peak* = the max post-switch envelope minus the max steady level of either endpoint;
    *local* is per probe.
- **My simulator agrees with the author's pinned results within about 1 dB, slightly under them** (a
  coarser probe grid), so my figures are if anything low. Breaker B→A at τ 40: mine +1.70 / +1.03, theirs
  +1.69 / +1.49. S2-adversarial at τ 10: mine +11.7 / +2.0, theirs +12.6 / +3.3.
- **Results, TD peak by τ:**

  | Pair | τ 10 | 40 | 80 | 160 ms |
  |---|---|---|---|---|
  | Jagged jump (`v3_worst_tau40`; the rule picks τ 40) | +8.20 | **+4.51** | +2.56 | +1.00 |
  | Small edit of a jagged curve (`v3_worst_tau10`; the rule picks **τ 10**) | **+2.42** | +0.78 | +0.22 | −0.01 |

- **Why it matters.**
  - The second case is three bands moving by 6 dB on a jagged My Preset. A click-to-place drag start or a
    preset switch can produce that.
  - The rule keys only on the *change* in solved gain (≤ 12 dB → τ 10). But the swell comes from the
    endpoints being jagged (solved gains ±30 dB).
  - v2 §12 says the TD peak is "≤ +1.5 dB at τ 40". That is refuted by 3 dB. The limiter and the ~7 dB of
    normaliser margin stop clipping, but not an audible +2.5 to +4.5 dB swell [O].
- **Fix.**
  - (a) Key τ on endpoint jaggedness, e.g. max \|solved gain\| of either endpoint > 15 dB → slow τ.
  - (b) Use τ 160 ms for that class, which brings both pairs to ≤ +1.0 dB [M]. The settle is ~0.7 s, only
    for wild curves [O].
  - (c) Pin both `.npy` pairs in `EQ_Transitions_Adversarial`, with a TD-search-derived bound.

### 2.2 MAJOR: the load-time loudness profile has no specified behaviour when it is late, at a gapless seam, or failed

v2 §4.2–4.3 covers only "the first track the user starts, ~1 s, on the pink prior (≤ 3.4 dB off), then a
500 ms glide".

- **Late, which is the common case.**
  - Only the queued next track is prefetched.
  - Every manual pick, jump or shuffle start in a library app plays on the prior until its own analysis
    finishes. The prior is off by ≤ 3.44 dB on the author's corpus and up to ±3.9 / +7.3 dB on my spectra
    [M, v1 `a7`].
  - The analysis time scales with duration: ~0.25 s/min by v2's own estimate, so about 15 s for a
    60-minute file [O, arithmetic].
  - The listener therefore hears a level glide mid-music, and On ↔ Off (identity) is level-unfair until
    then. That is the founder's check.
- **Gapless seam.** Gains are static per track, so a seam triggers a gain-only τ 500 ms glide *inside
  continuous music*.
  - `setCurrentTrack` comes from the playback layer "at the gapless seam", with no sample accuracy
    specified.
  - The next track's opening therefore plays at the previous track's gain. v2 also notes "gapless
    continuation unchecked" for the meter.
- **Failure.** On a decode error, a format the second decoder rejects, or a moved or evicted file, no state
  is defined, so the prior stays for the whole track. v2 already has a causal estimator at 0.67 dB
  integrated [author, s4]; it should be the fallback, with a log line.
- **Seeks:** fine; the profile is whole-track and static.
- **Fix.**
  - (a) Analyse a prefix first (the first ~20–30 s at ≥ 100× real time, ≈ 0.3 s [O]), then refine to the
    whole track with a slow glide.
  - (b) At a gapless seam, keep the gain continuous: carry the profile token through the gapless source for
    a sample-accurate switch, or use one gain for the gapless group.
  - (c) Define failure → the causal estimator.
  - (d) Gates: profile-late, gapless-seam level step ≤ 0.2 dB, analysis-fails fallback.

### 2.3 MAJOR: P1 (no normaliser) ↔ P3 (normaliser) steps the level by the normaliser's whole adapted gain

- **Measured** [M] on today's kernel, compiled from a read-only copy (`repro_pathstep.mm`). Today's
  branch 1 ↔ 3 is exactly v2's P1/P0 ↔ P3 boundary.
  - Run 25 s of loud noise at Intensity 0.3; the steady gain is −12.9 dB.
  - Set Intensity to 0: the output jumps **+13.4 dB in one block** (−13.4 → 0.0 dB) when the ramp settles.
  - Leave 0 again: it drops **−15.5 dB in one block**.
- **Why v2 misses it.**
  - v2's 5 ms crossfade handles only the limiter's 3 ms latency; the normaliser's gain is not crossfaded.
  - `Kernel_PathSwitch_NoGlitch` runs on a fresh kernel, where the makeup is still unity (≥ 3 gated blocks
    + 1 dB/s slew), so it cannot see this.
  - It is pre-existing, but v2 designs P1 without the normaliser on purpose, and claims glitch-free switches.
- **Fix.**
  - Fade the normaliser's contribution to 0 dB continuously as r → 0. For example, the applied makeup =
    makeup·min(1, r/0.1), so P1 and P3 meet at r = 0 with no step.
  - Run the path-switch gate **after the normaliser has adapted** (≥ 10 s of a loud programme), with a
    bound of level step ≤ 0.5 dB, like `Safety_EQToggle_AfterNormaliserAdapted`.

## 3. Checked and not broken (v2-introduced)

- **S2 stability while k and m1 move.** k stays a convex combination of positive values (> 0), so every
  frozen state is stable.
  - 60 s of white noise with 5,510 random switches: finite and bounded (+1.5 dB) [M, v1].
  - Every TD run in this pass, at τ 10 / 40 / 80 / 160, is finite [M].
- **Realistic transitions.** My earlier preset-pair TD with S2 gave +0.21 dB, inside v2's ≤ 0.5 peak /
  ≤ 0.75 local.
- **The limiter carries "≤ +1.50 dB on 0.56 % of frames".** I could not exceed it at −16 LUFS. Two synthetic
  loud masters (−9.9 / −8.9 LUFS) were tested: an 808 sub master, and sustained mids with short kicks.
  - With Tone Bass +12, sub +12, +12 @ 100 Hz, Warm, Loudness and Presence, under loudness-neutral gain:
    **0.00 % of frames over −1 dBTP; worst margin −1.16 dB** [M].
  - It is a corpus figure, not a bound. The P1 exposure (+4.29 dB on 8.9 %) is already disclosed as founder
    Q2.
- **Limiter priming and the 5 ms crossfade** remove the 3 ms skip/repeat (design read). The brief comb during
  the fade is milder than a skip [O].
- **App sandbox:** none found, so the second decode on a utility thread can reopen the file [code].

## 4. Verdict: OPEN ITEMS

1. **M1 / §2.1 (MAJOR):** S2's adversarial peak is +4.51 dB at τ 40, and +2.42 dB under the τ 10 branch.
   Key τ on endpoint jaggedness, use τ ≈ 160 ms for that class, and pin both pairs.
2. **§2.2 (MAJOR):** the loudness profile has no defined behaviour when late (every manual pick, long files),
   at gapless seams, or on failure. Needed: a prefix-first analysis, a seam-continuous gain and an estimator
   fallback, with gates.
3. **§2.3 (MAJOR):** the P1 ↔ P3 normaliser gain step (+13.4 / −15.5 dB measured at today's identical
   boundary). Fade the makeup with r, and run the switch gate on an adapted normaliser.
4. **Gate #2:** PARTIAL until the two new pairs are pinned.
5. **Minor port and gate notes:** the predictor must use a rectangular block window (Hann −0.36 dB); the
   ultrasonic gate bound of 1.5 dB is exceeded at +2.07 dB by an adversarial command.

## 5-line summary

1. Closed: B1, M2 (predictor accurate; use a rectangular window), M3, m1–m10, and gate tests #1 and #3–#11. The author's 5-refinement choice is confirmed (≤ 0.323 dB on my commands).
2. M1 is PARTIAL. S2 is the right scheme, but a TD search finds +4.51 dB at τ 40 and +2.42 dB on a jagged edit the rule routes to τ 10; the claim was ≤ 1.49. τ 160 for jagged endpoints fixes both.
3. New MAJOR: the P1 ↔ P3 path switch steps the level by the normaliser's whole gain (+13.4 / −15.5 dB measured), and v2's path-switch gate runs on an unadapted normaliser.
4. New MAJOR: the loudness profile has no behaviour defined when late (every manual pick, long files), at gapless seams (a mid-music glide), or on failure (the prior for the whole track).
5. Not broken: S2 stability, realistic transitions, and the limiter-load claim (0 % of frames over −1 dBTP at −16 LUFS on two loud bass-heavy masters).
