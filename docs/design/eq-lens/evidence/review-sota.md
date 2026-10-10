# Sprint EQ engine: the state-of-the-art challenge (Reviewer 2)

*2026-10-09. Independent review of `dsp/dsp-plan-check.md`. Everything is re-implemented from the papers in
this folder; I did not reuse the author's code. `sh run_all.sh` re-creates every number in about 5 minutes,
with outputs in `results/`. The repo was only read.*

**Machine.** Apple M4 Pro (P-core 4.51 GHz), FTZ on, `clang++ -O3 -mcpu=native`. The M1 Pro floor (3.22 GHz)
is estimated at **×1.4** for these latency-bound floating-point loops. That factor is the clock ratio only:
an **[O]**, with the clocks taken from a Notebookcheck search result.

**Labels.** **[M]** measured here (result file named) · **[C]** cited from a source opened this session (URLs
in §9) · **[A]** the author's own measurement · **[O]** my opinion.

**Corpus for Q3 and Q4** (read-only, from the repo's `research/`): 7 tracks. One old recording in 4 variants (the
excerpt, a band excerpt, a 3.7-minute remaster, a synthetic loud master at −9 LUFS / PLR 8.9) and 3 generated tracks
at 48 kHz (PLR 12.8–14.2). It is small and has no commercial masters, so treat it as indicative.

## 0. Verdict: **IMPROVE**

The author's core design is the best of the six families compared (five measured here; the neural one is ruled
out from its paper plus my solve timings).
- **Filter design:** a bilinear bell, an interaction-matrix WLS solve and a per-rate basis.
- **Real-time structure:** a double-precision TPT SVF with one shared dB ramp.

I would not replace either. What needs work is around them: one extra solver pass, how loudness is handled, how
level matching is predicted, and the test gates.

| # | Change | Why (measured) | R1? |
|---|---|---|---|
| 1 | **Add a 3rd refinement pass** (4 solves) | The SPL-17 "every-third-down" command plays **0.93 dB** off at the centres; with the extra pass it is 0.27 dB. Jagged commands improve from 0.49 to 0.46 dB. Cost: +20 µs. | R1 |
| 2 | **Level-match Compare and Off with a gated block-spectral predictor** instead of the curve-on-pink estimate | Prediction error on 84 track×curve pairs: **max 3.42 dB, p90 2.55** for the curve estimate, against **max 0.10, p90 0.03** for the new predictor | R1 |
| 3 | **Loudness-neutral EQ output gain** (founder decision, see §4) | The chain's always-on −16 LUFS normaliser undoes the −max\|H\| preamp anyway: slowly within a track, fully only from the next track load. Meanwhile the preamp costs **1.7–12 dB** of loudness. With a neutral gain, the −1 dBTP limiter has to catch at most **+1.2 dB on ≤ 0.5 % of 10 ms frames**. | R1, recommended |
| 4 | **Gates built from a Rämö-style set** (binary {0,±12} + integer random), plus every-third-down and steep cliffs | The plan's "≤ 0.31 dB on every tested command" does not hold for these sets (0.44–0.49 and 0.93 dB) | R1 |
| 5 | **C++ port rule:** evaluate \|H\|² in factored or complex form, never as the expanded cos-polynomial | The expanded form is wrong by **0.63 dB** at 20 Hz / 192 kHz, and a near-zero-gain basis column is wrong by 196× | R1 |
| 6 | Analog-Nyquist-gain bells for bands with fc > 0.25 fs | Cross-rate deviation (44.1 vs 192 kHz, ≤ 20 kHz) falls from 1.21 to 0.36 dB at 44.1 and from 0.69 to 0.16 dB at 48. Jagged accuracy at 44.1 drops from 0.49 to 0.54 dB. | later |

**Structure conflict (Q2): keep the double SVF.**
- Wishnick's TDF-II win (95 vs 43) came from a **single unsmoothed** gain jump on one Q 6 bell, with the probe
  tone at the bell's centre [C].
- I reproduced the direction of that result under an abrupt step [M].
- Under the author's 10 ms dB ramp, no double-precision structure adds sideband energy beyond the ramp's own:
  at most +0.1 dB above the quasi-static reference, and TDF-II/DF-I sit up to 3.5 dB below it [M].
- The SVF also tracks the quasi-static response 10–17 dB more closely [M].
- In float, the SVF is about 70–76 dB more precise than TDF-II or DF-I at 192 kHz [M].

**Rejected, with data:**
- Minimum-phase FIR (d): wrong by 5.4 dB at 20–40 Hz at 16k taps; needs ~131k taps (2.7 s) to compete, which
  costs 39 % of one core at 192 kHz × 8.
- Matched-Z / analog-matched bells (e): no gain, and +40 % CPU.
- SGE3 (c) as a replacement: 1.0 dB on jagged commands.
- Neural gain prediction (f): it adds error to save under 0.1 ms per update.
- Per-rate bandwidth tables (≤ 0.03 dB, mixed).
- Ultrasonic guard points (they push the 20 kHz band 3 dB off).
- Float SVF and `vDSP_biquadm`.

## 1. Q1: the design choice, measured on one command set

**Command set** (`designs.command_set`), all on the plan's base-10 centres:
- 6 presets;
- single ±12 on every band (62 commands);
- alternating, pairs and every-third-down, with their negations (6);
- 12 steep tilts and cliffs;
- 4 broadband levels;
- **1,000 random jagged** commands (500 binary {−12, 0, 12} and 500 integer, the Rämö 2020 protocol [C]);
- 300 smooth curves: splines through 6 random knots, kept as continuous functions so the error *between*
  centres is judged against the true intent;
- 100 Tone settings.

**Designs as implemented:**
- **(a) ACGE3** [C DAFx-17]: pareq with c = 0.4, B = 0.4662 ωc, the top six bandwidths hand-tuned at 44.1 kHz,
  g_p 17 dB, unweighted LS, 1 iteration.
- **(b) the author's design:** bilinear bell, B = 0.40 ωc, WLS, 1+2 passes. It reproduces the author's
  Warm g₀ = 4.7190 exactly [M].
- **(c) SGE3** [C Rämö 2020]: the Orfanidis prescribed-Nyquist bell, c = 0.38, the Table-1 bandwidths, the
  Table-2 Nyquist polynomial at 44.1 kHz and the analog-like Nyquist gain at other rates, g_p 11 dB, 1 iteration.
- **(d) Equalizer APO-style minimum-phase FIR** (recipe as described in `research/players-implementation.md`; I did not
  re-open the APO source): the 31 nodes linear in
  dB against log f, held flat beyond the ends, cepstral minimum phase, half-Hann fade; 16,384 taps, or scaled with fs.
- **(e) Vicanek §4.4 matched peaking** [C], using the solver of (b).
- **"rt"** marks a variant whose top-band bandwidths were **re-tuned per rate** by coordinate descent on a
  disjoint training set (`retune.py`). This is the "per-rate re-tuning" the papers did by hand, at 44.1 kHz only.

**Reproduction check** [M vs C]:
- My ACGE3 mean-of-max error is 0.545 dB; Rämö Table 5 reports 0.53.
- My SGE3 mean-of-max is 0.53 dB against the published 0.50, but my **maximum is 1.00 dB against the published
  0.81**. I could not reproduce SGE3's maximum: in my build the binding errors are mid-band (c = 0.38, one
  iteration), not near Nyquist.

**Table A: accuracy at the 31 centres, in dB** [M `results/q1_table.txt`, `q1_fir_length.txt`]

| Design | jagged max, 44.1 / 48 / 96 / 192 kHz | jagged p99 (44.1) | hard max (44.1) | presets / Tone (44.1) | smooth: max error vs true intent | flat +12 ripple p-p (44.1) |
|---|---|---|---|---|---|---|
| (a) ACGE3 | 1.00 / 1.00 / 1.00 / 1.00 | 0.90 | 0.49 | 0.22 / 0.49 | 0.45 | 0.78 |
| (a) re-tuned | 1.03 / 1.06 / 1.00 / 1.00 | 0.89 | 0.73 | 0.19 / 0.73 | 0.83 | 1.17 |
| **(b) author** | **0.49 / 0.45 / 0.44 / 0.44** | **0.43** | 0.93 | **0.08 / 0.08** | 0.45 | **0.33** |
| **(b) + 3rd pass** | **0.46 / 0.43 / 0.43 / 0.43** | **0.41** | **0.27** | **0.08 / 0.08** | 0.45 | **0.33** |
| (b) re-tuned | 0.50 / 0.49 / 0.45 / 0.44 | 0.43 | 0.93 | 0.07 / 0.11 | 0.45 | 0.53 |
| (c) SGE3 | 1.00 / 1.00 / 0.99 / 0.99 | 0.90 | 0.52 | 0.20 / 0.40 | 0.38 | 0.67 |
| (c) re-tuned | 1.06 / 1.08 / 0.99 / 0.99 | 0.90 | 0.56 | 0.20 / 0.29 | 0.44 | 0.73 |
| (d) FIR, 16,384 taps (APO) | 4.98 / 5.39 / 9.58 / 14.96 | 4.93 | 4.72 | 0.03 / 0.10 | 0.44 | 0.00 |
| (d) FIR, taps scaled with fs | 5.39 at every rate | 5.33 | 5.10 | 0.03 / 0.11 | 0.47 | 0.00 |
| (d) FIR, 131,072 taps @ 48 k | 0.58 (40 jagged commands) | – | – | – | – | 0.00 |
| (e) matched | 0.75 / 0.49 / 0.44 / 0.44 | 0.64 | 0.91 | 0.08 / 0.07 | 0.63 | 0.33 |
| (e) re-tuned | 0.53 / 0.51 / 0.46 / 0.44 | 0.42 | 0.92 | 0.07 / 0.12 | 0.47 | 0.42 |

**Table B: everything other than centre accuracy** [M `q1_table.txt`, `q5_*.txt`, `q6b_*.txt`]

| Design | cross-rate \|H_fs − H_192k\| ≤ 20 kHz, max at 44.1 / 48 | ultrasonic at 192 k, +12 @ 20 kHz | group delay at 20 Hz: +12 @ 20 Hz / Warm | 1 − max\|pole\| at 192 k | CPU at 192 k × 8 ch (one core) | full design time in C++ |
|---|---|---|---|---|---|---|
| (a) | 0.81 / 0.63 | +9.2 dB, above +3 dB up to 28 kHz | 82 / 16 ms | 2.6e-5 | 2.66 % (same bell SVF form as (b)) | 55 µs |
| **(b)** | 1.21 / 0.69 (≤ 16 kHz: 0.38 / 0.26) | +9.6 dB, to 29 kHz | 78 / 15 ms | 2.5e-5 | **2.66 %** | **75 µs; 95 µs with a 3rd pass** |
| (c) | **0.47 / 0.38** | +9.0 dB, to 28 kHz | 85 / 17 ms | 2.6e-5 | +40 % (general-mix SVF: 2.93 vs 2.10) | 58 µs |
| (d) | 5.10 / 4.94 (APO); 0.02 / 0.00 (scaled) | **+12.0 dB all the way to 96 kHz** ("hold" rule); +5.6 dB to 23 kHz with a roll-off | 28 / −1.4 ms | – | 0.45 % (16k taps @ 48 k × 8) up to **39 %** (524k taps @ 192 k × 8) | 0.4–19.8 ms, plus a 2× cross-fade and +512 samples of latency |
| (e) | 1.13 / 0.59 | +9.6 dB, to 29 kHz | 78 / 15 ms | 2.5e-5 | +40 % (general mix) | 92 µs |

Other measurements behind these tables:
- **Stability.** Float32-rounded coefficients keep every pole inside the unit circle for all IIR designs [M].
  The coefficients still need double, because float rounding moves gain: −0.87 dB at 20 Hz / 192 k [A].
- **Group delay at low frequencies follows from the magnitude** (minimum phase), not from the design family.
  - It is about 78–85 ms at 20 Hz for a +12 dB third-octave bell, which is about 1.6 periods [M].
  - The FIR numbers differ only because it realises a different shape below 20 Hz: it holds flat where the
    bell returns to 0.
  - A linear-phase FIR would add 170 ms or more of latency at 192 kHz (N/2 of 65k taps; my arithmetic) [O]:
    unnecessary for a graphic EQ.
- **(f) neural GEQ: ruled out.**
  - Rämö 2020 Table 5 [C]: NGEQ3 is 1.05 dB against ACGE3's 0.97, and NSGE3 is 0.86 against SGE3's 0.81. That is
    +0.05 to +0.08 dB of extra error.
  - Its only benefit is speed, and the WLS solve already takes 75–95 µs in C++ [M], or about 0.13 ms on an
    M1 Pro [O]. Saving that at a 120 Hz drag rate is under 1.2 % of one *non-real-time* core.
  - Against that it brings a training pipeline per rate and a black box [O].
- **FIR (d) in detail.**
  - Third-octave spacing at 20 Hz is only 5 Hz, so a practical FIR cannot resolve jagged low-band commands.
    At 48 kHz [M `q1_fir_length.txt`]: 16k taps gives 5.4 dB, 65k gives 1.24 dB and 131k gives 0.58 dB.
  - Its impulse-response ringing lasts 214–434 ms [M].
  - Equalizer APO's "hold the last node to Nyquist" rule boosts the whole 20–96 kHz range at 192 kHz [M].
  - For smooth curves it is the most exact option: presets 0.03 dB, no ripple. That gain does not justify the
    cost or the low-band failure [O].

**What Table A says** [O, from the numbers above]:
- (b) is the most accurate on every family that matters to users: presets, Tone, smooth curves, jagged commands
  and broadband ripple.
- Its one weak case, every-third-down, is fixed by the 3rd pass (0.93 → 0.27 dB).
- (a) and (c) carry about 1.0 dB on jagged commands, because their c-level bandwidth convention plus a single
  iteration leaves mid-band error.
- Per-rate re-tuning gains ≤ 0.03 dB on some metrics, loses on others, and costs cross-rate consistency
  [M `q1_retune.txt`]: **not worth it.**
- SGE3's real advantage is cross-rate consistency above 16 kHz. The hybrid in §7 captures most of it.

## 2. Q2: SVF vs TDF-II vs DF-I under time variation

**What Wishnick actually tested** [C, DAFx-14 §6, full text opened]:
- MUSHRA, 21 subjects, headphones.
- A **100 Hz sine at 48 kHz**, chosen because it "masks the transient very little".
- **Five trials, each "a single discontinuous parameter change".** Trial 4 is a peaking bell at 100 Hz, Q 6,
  with the gain stepped **−4 → +4 dB**. Scores: DF2 43, **SVF 43**, **TDF2 95**, TDF2RC 94.
- The other trials are mixed:
  - low-pass Q change: SVF wins clearly, 96 vs TDF2 70;
  - low-pass frequency change (63 vs 69) and peaking frequency change (72 vs 77): close;
  - peaking Q change: SVF loses, 25 vs 64.
- The hidden reference was the gain envelope **smoothed with a 10 ms Hann**.
- Sideband energy predicts the score (r = −0.59); transient variance does not (r = 0.11).
- The paper's own conclusion: "it may be desirable to smooth the changes in coefficients cHP, cBP and cLP,
  which set the filter's zeros".
- So the 95 vs 43 result is about **unsmoothed** jumps. The literature survey's inference that "TDF-II with
  smoothed gains is the evidence-backed default" was never tested in the paper.

**My test** [M `cpp/tv.cpp`, `q2_analyze.py`, `q2_static.py`].
- All three structures realise the **same** transfer function at every sample, built from one set of
  (g, k, A) bell parameters, so any difference comes from the structure alone.
- Update schemes:
  - **abrupt:** coefficients switch instantly;
  - **author:** τ = 10 ms on the dB gain, 32-sample control rate, per-sample linear interpolation of the coefficients;
  - **per-sample:** coefficients recomputed every sample.
- Scenarios:
  - a replica of Wishnick's trial 4;
  - full 31-band changes from the author's own solve: Off → Warm, Warm → Presence, alternating ↔ its negation,
    and 120 Hz pointer drags of the 125 Hz and 20 Hz points, with neighbours following;
  - each at 48 and 192 kHz.
- Metrics:
  - **SB:** Wishnick's sideband metric (85 ms Hann, one ERB around each tone removed), in dBFS, maximum over
    the transition;
  - **SBref:** the same metric on the quasi-static reference;
  - **Etr:** transient energy relative to the quasi-static output;
  - **f32 static:** float error against the double SVF in a 200 ms steady segment, pink noise at about −25 dBFS.

| Scenario, scheme | Metric | SVF f64 | TDF-II f64 | DF-I f64 | SVF f32 | TDF-II f32 | DF-I f32 |
|---|---|---|---|---|---|---|---|
| Wishnick T4 replica, **abrupt** | SB (ref −46.8) | −48.6 | **−54.6** | −54.6 | −48.6 | −54.6 | −54.6 |
| Wishnick T4 replica, author ramp | SB (ref −52.0) | −52.9 | −55.5 | −55.5 | −52.9 | −55.5 | −55.4 |
| Wishnick T4 replica, author ramp | Etr (dB) | **−35.8** | −20.5 | −20.4 | −35.8 | −20.4 | −20.4 |
| Off → Warm @ 48 k, author ramp | SB (ref −62.6) / Etr | −62.6 / **−50.7** | −62.6 / −40.1 | −63.2 / −34.3 | −62.6 / −50.7 | −62.3 / −34.5 | −62.7 / −30.9 |
| Off → Warm @ 192 k, author ramp | SB (ref −69.1) / Etr | −69.1 / **−50.7** | −69.1 / −40.1 | −69.7 / −34.3 | −69.1 / −50.7 | −65.6 / −19.9 | −65.8 / −19.7 |
| Warm → Presence @ 192 k, author ramp | SB (ref −67.7) / Etr | −67.7 / −51.2 | −67.9 / −34.2 | −68.0 / −29.6 | −67.7 / −51.2 | **−62.9** / −17.4 | **−62.3** / −16.3 |
| Drag of 20 Hz @ 192 k, author ramp | SB (ref −76.9) | −76.9 | −76.9 | −76.9 | −76.9 | −76.3 | −76.3 |
| Alternating flip @ 48 k, abrupt | peak transient (dBFS) | −10.9 | **+0.7** | −6.4 | −10.9 | +0.9 | −6.3 |
| Static Warm @ 192 k | error vs SVF f64 (dB re signal) | ref | −194 | −194 | −97 | **−21** | **−21** |
| Static alternating @ 192 k, 15–200 Hz | error vs SVF f64 | ref | −184 | −184 | −81 | **−12** | **−12** |

What the table shows:
- **Under the author's ramp the zipper metric is decided by the ramp, not the structure.** In every scenario, no
  double structure exceeds the quasi-static reference's own sidebands by more than 0.1 dB. TDF-II and DF-I sit up
  to 3.5 dB *below* it, because their lag adds smoothing [M].
- Float direct forms **add** up to 4.8–5.4 dB of sideband at 192 k [M].
- The author's 32-sample interpolation equals per-sample recomputation: Etr within 0.30 dB, sideband within
  0.10 dB [M].
- The SVF follows the ideal response 10–17 dB more closely (Etr). TDF-II's apparent advantage under abrupt steps
  is that it lags, which acts as extra smoothing; with a ramp already in place, that lag only means deviation.
- Statically, all double structures agree to −184 dB or better. Float TDF-II and DF-I are unusable at
  192 kHz (−12 to −21 dB), which confirms the author's 28 dB [A].

**Recommendation: keep the double TPT SVF with the author's ramp.**
- Its zipper behaviour equals TDF-II under the ramp, and it tracks the quasi-static response better.
- It survives float, and at m1 = 0 it is an exact pass-through.
- It is **not** the cheapest option: TDF-II double costs 0.77 % against 1.34 % at 192 k × 2 (§6). At 1.3 % of
  one core, that cost does not matter [O].
- Under abrupt events (re-initialisation after a sample-rate change, NaN reset, bypass re-entry), both structures
  must start from a ramp, never a step.

## 3. The real chain, as read in the code

DSPKernel.cpp:
`EQ → Clarity (pass-through stub) → BRIR (stub) → Crossfeed (off by default) → [intensity blend] → Loudness → Limiter`.

- **Loudness module** (LoudnessModule.cpp):
  - always enabled in Enhanced mode; target −16 LUFS;
  - measures the **post-EQ** signal;
  - makeup gain clamped to −20…+12 dB and slewed at 0.1 dB per 100 ms gated block;
  - the meter **is** reset at each `playFile` load, because `publishChannelLayout` bumps the layout generation
    and the worker then calls `configureChannels()` → `reset()`.
  - **Correction to the author's §4.3:** the integration runs per explicit track load, not over the kernel's
    lifetime. Whether gapless continuations also reset it was not checked. The author's slowness *within* a
    track still stands [A].
- **Limiter** (LimiterModule.h): −1 dBTP ceiling, 8× polyphase inter-sample-peak detection (under-read
  < 0.17 dB), 3 ms look-ahead, dual release. That is state-of-the-art for a playback safety limiter [O].

## 4. Q3: headroom and peaks

Measured on the corpus with design (b) [M `results/q3_headroom_music.txt`]. Ranges are over the 7 tracks.

Column meanings:
- **preamp** = −max(0, peak\|H\|);
- **ℓ₁ extra** = how much more the sum-of-\|h\| bound would cut;
- **ΔL net** = the BS.1770 loudness change the user hears with the preamp, relative to the source;
- **ΔTP** = the true-peak change at the EQ output with the preamp;
- **limiter load** = after the −16 LUFS normaliser has converged, the 4× true-peak overshoot above −1 dBTP and
  the share of 10 ms frames over it.

| Curve | preamp | ℓ₁ extra | ΔL net (user loses) | ΔTP max | limiter load |
|---|---|---|---|---|---|
| Warm | −10.12 | −4.83 | −1.7 … −2.9 | −1.13 | none (≤ −1.1 dB) |
| Presence | −8.00 | −2.2 | −4.4 … −7.2 | −2.65 | +0.3 dB, 0.0 % |
| Clarity | −6.09 | −2.1 | −4.1 … −5.5 | −2.95 | +0.3 dB, 0.0 % |
| Vocal | −6.02 | −2.4 | −2.8 … −5.1 | −1.54 | +0.9 dB, 0.1 % |
| Loudness | −4.11 | −4.9 | −1.9 … −3.3 | −0.97 | none |
| Studio | −2.06 | −1.4 … −1.7 | −2.0 | −1.22 | none |
| +12 @ 100 Hz / 1 kHz / 8 kHz | −12.04 | −1.6 … −1.9 | **−8.5 … −12.0** | −4.99 | up to +1.1 dB, ≤ 0.1 % |
| Tone B+6 Bo−3 P+4 A+6 | −6.16 | **−8.4 … −8.8** | −1.8 … −4.3 | **+0.37** | **+1.2 dB, 0.5 %** |
| Source alone (PLR 8.9–14.2) | – | – | – | – | none (−0.8 … −6.1 dB) |

What the table shows:
1. **The ℓ₁ bound is rejected.** It costs 1.4–8.8 dB *more* loudness than −max\|H\|, to guarantee something the
   limiter already enforces [M].
2. **−max\|H\| does not guarantee "no peak above the source".** Phase raised the true peak by +0.37 dB once [M],
   matching the survey's ℓ₁ argument [C].
3. **The preamp's loudness cost is large and temporary at the same time.** The normaliser measures post-EQ, so in
   steady state it restores −16 LUFS whether or not a preamp is applied; the output and the limiter's work are
   *identical* either way.
   - What the preamp actually buys is 1.7–12 dB of extra quietness [M]. Within the current track the normaliser
     wins it back only slowly (0.45 dB after 10 s with 60 s of history [A]); from the next load it is restored at
     ≤ 1 dB/s [code read].
   - The normaliser's +12 dB makeup clamp can bind as well: 2 of 84 cases [M].
4. **A loudness-neutral EQ is safe.** Set the EQ output gain to −ΔL_pred (the §5 predictor) instead of −peak. Then:
   - the normaliser sees no level change;
   - On, Off and Compare are level-fair *by construction*;
   - the existing limiter catches at most +1.2 dB on 0.5 % of frames, in the most aggressive Tone move on the most
     dynamic track (PLR 13.3) [M]. A 3 ms look-ahead true-peak limiter doing that is inaudible [O].

**Recommendation.** Make the EQ's shared-ramp output gain **−ΔL_pred**; keep −max\|H\| as the "Headroom" figure the
graph shows; keep the limiter as the safety guarantee. This changes what decision 23 *sounds* like (a boost sounds
like tone, not like a level drop), so it needs the founder.
- **(a) Recommended:** loudness-neutral.
- **(b)** Keep −max\|H\|, as planned. It is safe, but quieter by 1.7–12 dB for most of the current track, and
  Off/Compare then need the §5 predictor to be fair.

## 5. Q4: level matching for Compare and Off

Prediction error against the measured BS.1770 integrated change of the EQ'd track, 7 tracks × 12 curves
[M `q4_levelmatch_music.txt`, `q4_gated_spectral.txt`]:

| Predictor | max \|err\| | p90 | Needs |
|---|---|---|---|
| Curve on a pink reference (the author's plan) | **3.42 dB** | 2.55 | nothing (the author estimated ±1.2 [A]) |
| Track's long-term third-octave powers × \|H(f_c)\|² | 1.04 | 0.68 | the 31-band analyzer |
| Track's long-term fine spectrum × \|H\|², ungated | 0.73 | 0.15 | a Welch spectrum |
| **Gated block-spectral** (below) | **0.10** | **0.03** | 1/12-octave K-weighted band powers per BS.1770 block |

How the gated block-spectral predictor works [M]:
- For every BS.1770 block (400 ms window, 100 ms hop), keep the K-weighted source power in 1/12-octave bins.
  That is about 120 floats per block, or 1.2k floats per second.
- For any curve, compute each block's power as Σ P_b\|H_b\|², then apply the **real** two-stage BS.1770 gating.
- This is exact for gating, which is why the fine but ungated spectrum still misses by up to 0.73 dB.
- It also needs **no second audio path:** one analysis serves A, B, Off and the curve being edited.
- Cost: about 0.1 ms per prediction for 5 minutes of blocks [O, arithmetic].

**Time behaviour** [M]:
- A short-term (3 s) dual-path loudness ratio wanders over a track: by 1.4–3.7 dB for the presets and up to
  **5.8 dB** for +12 @ 100 Hz. Any short-window real-time matcher would therefore pump.
- Matching must use a long window.
- A running estimate from the track start is within 0.45 dB after 30 s, but can be off by 3.3 dB after 3–10 s.

**R1:**
- Run the gated block-spectral accumulation on a worker fed by the existing pre-DSP tap (the LoudnessModule
  SPSC-worker pattern).
- Take a snapshot at each curve change (no continuous drift).
- Fall back to the curve estimate for the first ~10 s of a track.

**Later:**
- Compute the same block spectra in a full-track pre-analysis at load, so the match is exact from the first
  second. The own-player owns the decode, so latency is free.
- Use the dual-path K-weighted meter (+1 EQ cascade: 0.34 % at 48 k × 2, 2.7 % at 192 k × 8 [M]) only as a test
  oracle; it is not needed in the product [O].

## 6. Q5: performance

[M `q5_cpu.txt`, `q5_svf_mix.txt`, `q5_solve_cpp.txt`] Percent of one P-core; 31 sections; 512-frame blocks.

| Engine | 48 k × 2 | 192 k × 2 | 48 k × 8 | 192 k × 8 | M1 Pro est. at 192 k × 8 [O] |
|---|---|---|---|---|---|
| **SVF double, author ramp, SIMD across channels** | **0.34** | **1.34** | 0.68 | **2.66** | ~3.7 |
| SVF double, static | 0.28 | 1.14 | 0.62 | 2.49 | – |
| TDF-II double, ramp, SIMD | 0.19 | 0.77 | 0.60 | 2.36 | ~3.3 |
| SVF double, scalar, channel-outer | 0.53 | 2.12 | 1.78 | 7.11 | – |
| SVF float, ramp | – | – | 0.43 | 1.73 | (rejected: −81 to −97 dB static) |
| `vDSP_biquadm` float, static (DF) | 0.19 | 0.78 | 0.53 | 2.13 | (rejected: −12 to −21 dB) |
| `vDSP_biquadmD` double, static | 0.25 | 1.01 | 1.01 | **4.05** | – |
| FIR, 16k taps @ 48 k / 65k @ 192 k (UPOLS) | 0.11 | 1.34 | 0.45 | 5.33 | – |

What the table shows:
- **SIMD across channels beats the scalar double cascade by 1.6× at 2 channels and 2.7× at 8.**
- `vDSP_biquadmD` is slower than the hand-written double SVF (4.05 vs 2.66).
- `vDSP_biquadm` is only competitive in float, where its direct form fails at 192 kHz.
- **Update latency while dragging:** a full design costs 75 µs (95 µs with the 3rd pass). That covers the 31×61
  basis, Cholesky, the headroom scan and the 256-point read-back [M]; on an M1 Pro it is about 0.13 ms [O].
  - Publishing through the triple buffer is a 320-byte copy.
  - The kernel picks it up at the next render quantum: ≤ 10.7 ms at 512 frames / 48 kHz.
  - The 10 ms ramp then reaches 63 % after one τ.
  - So drag-to-ear is about 11–21 ms. No rate limit is needed [O].

## 7. Improvements: what is worth it

| Change | Measured gain | Cost | When |
|---|---|---|---|
| 3rd refinement pass (fixed count of 4 solves) | every-third-down 0.93 → 0.27 dB; jagged 0.49 → 0.46 (44.1); 6 or 10 passes add ≤ 0.04 more [M `q6b`] | +20 µs | **R1** |
| Gated block-spectral loudness predictor | level-match error 3.42 → **0.10 dB** max | worker + ~1.2k floats/s | **R1** |
| Loudness-neutral EQ gain (= −ΔL_pred) | ΔL net −1.7…−12 dB → 0 ± 0.1; limiter ≤ +1.2 dB on ≤ 0.5 % of frames | one field; founder decision | **R1 (recommended)** |
| Rämö-style gate set (binary/integer random, every-third-down, cliffs) at every rate | catches the 0.93 dB case the plan's set missed | tests only | **R1** |
| Factored or complex \|H\|² in the C++ basis and headroom scan | avoids 0.63 dB / 196× basis errors at 20 Hz / 192 k [M `q5_eval_precision`] | none | **R1** (the author's C++ already uses complex form) |
| Analog-Nyquist bells for fc > 0.25 fs | cross-rate 1.21 → 0.36 (44.1), 0.69 → 0.16 (48); jagged 0.49 → 0.54 (44.1) | +40 % CPU on 2–3 sections | later |
| Full-track pre-analysis at load | exact match from second 1 (vs 0.45–3.3 dB early) | decode-pass plumbing | later |
| Adaptive bandwidth c (narrow for rough, wide for smooth commands) | c 0.34: jagged 0.34 / ripple 0.62; c 0.46: jagged 0.66 / ripple 0.21 [M `q6_extras`] | k0 becomes time-varying | later, low value |
| Per-rate top-band tables | for (a)–(c): ≤ 0.03 dB better on some metrics, worse on others and on cross-rate; they only rescue (e) at 44.1 (0.75 → 0.53), which still trails (b) [M `q1_retune`] | tables | **no** |
| Ultrasonic guard points (0 dB targets at 24–40 kHz) | ultrasonic 9.6 → 7.1–7.4 dB, but the **20 kHz error becomes −3.0 to −3.3 dB** and jagged 3.3–3.6 dB | – | **no** |
| Matched (e), SGE3 (c), FIR (d), neural (f), float SVF, vDSP | see §1 and §6 | – | **no** |

**Accepted as a property, not fixed** [O]:
- At ≥ 88.2 kHz, a +12 dB 20 kHz band also boosts up to about 29 kHz, by up to +9.6 dB [M].
- One bell cannot be both accurate at 20 kHz and silent at 24 kHz.
- It never forces extra preamp: the in-band peak is higher [M].
- Document it in the gate.

## 8. Corrections to numbers in the plan and the survey

- **Plan §1.2 / §0.1, "≤ 0.31 dB at the centres on every tested command":**
  - binary/integer random commands: 0.44–0.49 dB;
  - every-third-down: 0.93 dB [M].
  - The proposed 0.5 dB "rough" gate is marginal (0.49 at 44.1). Gate the hard patterns *after* adding the 3rd pass.
- **Plan §1.1, "a third pass gains < 0.02 dB":** true on its own set; false for every-third-down (−0.66 dB) [M].
- **Plan §4.4, "±1.2 dB by spectrum":** the curve estimate was 3.42 dB max, p90 2.55 on real tracks [M].
- **Plan §4.3, "the meter integrates over the kernel's lifetime":** it is reset at every `playFile` load (§3).
- **Survey §3, "TDF-II with smoothed gains is the evidence-backed default":** the cited test used unsmoothed
  jumps. Under smoothing, TDF-II has no zipper advantage and tracks the response 10–17 dB worse (§2).
- **Survey Appendix A, "B_m = (2^(1/6) − 2^(−1/6))·ωc ≈ 0.4662 ωc":** the factor is 2^(1/3) − 2^(−1/3). The
  (2^(1/6) − 2^(−1/6)) expression equals 0.2316, so it would halve the bandwidths [C Rämö §3.1].

## 9. Sources opened this session (PDFs fetched into `dl_*/` and read with pdftotext)

- A. Wishnick, "Time-Varying Filters for Musical Applications," DAFx-14, §6 and Tables 3–5:
  https://dafx.de/paper-archive/2014/dafx14_aaron_wishnick_time_varying_filters_for_.pdf
- J. Rämö, J. Liski, V. Välimäki, "Third-Octave and Bark Graphic-Equalizer Design with Symmetric Band Filters,"
  *Appl. Sci.* 10(4):1222, 2020, Eqs. 9–16 and Tables 1, 2, 5:
  https://acris.aalto.fi/ws/portalfiles/portal/41964159/Third_octave_and_Bark_graphic_equalizer_design.pdf
- J. Liski, V. Välimäki, "The Quest for the Best Graphic Equalizer," DAFx-17:
  https://dafx.de/paper-archive/2017/papers/DAFx17_paper_94.pdf
- M. Vicanek, "Matched Second Order Digital Filters," 2016, §3.3–3.4 (Orfanidis, Massberg) and §4.4:
  https://www.vicanek.de/articles/BiquadFits.pdf
- Clocks: M4 Pro 4.51 GHz, M1 Pro 3.22 GHz. Taken from a Notebookcheck search result only; a direct fetch of the
  page was blocked:
  https://www.notebookcheck.com/M1-Pro-vs-M4-Pro-14-cores_13845_18019.247552.0.html
- Code read (repo, read-only): `DSPKernel.cpp`, `Loudness/LoudnessModule.{h,cpp}`, `Loudness/LufsMeter.h`,
  `Limiting/LimiterModule.h`, `EQ/EQModule.{h,cpp}`, `include/TargetState.h`, `Clarity/ClarityModule.h`,
  `AudioEngineBridge+{Playback,ChannelLayout}.swift`.

## 10. Reproduce

Run `sh run_all.sh` from this folder.
- **Python:** `designs.py` (all band filters and the batched WLS), `fir.py`, `retune.py`, `q1_eval.py`,
  `q1_table.py`, `q1_fir_length.py`, `q2_*.py`, `q3q4_music.py`, `q4_gated_spectral.py`,
  `q5_eval_precision.py`, `q6_extras.py`, `q6b_passes_hybrid.py`.
- **C++:** `cpp/tv.cpp` (structures), `cpp/bench_solve.cpp`, `cpp/bench_cpu.cpp`, `cpp/bench_svfmix.cpp`.
- **Results:** `results/*.txt|json`. The raw time-varying audio (about 300 MB) is deleted after analysis.
