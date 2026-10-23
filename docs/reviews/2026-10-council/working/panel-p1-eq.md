# Panel P1: EQ, track loudness, spectrum and EQ session logic (algorithm correctness)

Panelist: P1 (adversarial breaker with its own oracles). Repo `main` @ 7d7c2cd. My own worktree is
`.claude/worktrees/panel-p1`. Experiments are in `scratchpad/council/exp-p1/` (`h/` holds the C++ and Python harnesses,
`spec/` and `tap/` the Swift probes). Nothing in the repo was edited. A scratch Swift fuzz test ran in my worktree and
was then removed; a copy is at `exp-p1/h/ZZPanelP1FuzzTests.swift`.

## Method in one paragraph

I formed my own view first:
- **Solver and bell.** I derived the bell from the ACGE / Orfanidis biquad equations and wrote my own Gauss–Newton
  solver of the true non-linear weighted objective.
- **Predictor.** I wrote my own BS.1770 meter from the Recommendation's 48 kHz coefficient table, and my own
  rectangular and Hann profile models.
- **The real code, driven directly.** Small C++ harnesses link the real `GraphicEQDesigner.cpp`, `EQModule.cpp`,
  `EQTargets.h`, `TrackLoudnessProfiler.cpp` and `TrackLoudnessProfile.cpp`. The real `SpectrumAnalyzer.swift` and
  `SpectrumDoubleBuffer.swift` are compiled into a Swift probe. `EQEditKit` was driven by a model-based fuzz.
- **The existing gate.** All 86 EQ / loudness null tests pass in my worktree, and the 137 `EQEditKitTests` pass.
- **References opened:**
  - Liski & Välimäki, "The Quest for the Best Graphic Equalizer", DAFx-17
    (https://dafx.de/paper-archive/2017/papers/DAFx17_paper_94.pdf), §§4–5 and Table 1.
  - Apple `vDSP.h` (`vDSP_hann_window`).
  - Apple `AVAudioNode.installTap` documentation ("Supported range is [100, 400] ms",
    https://developer.apple.com/documentation/avfaudio/avaudionode/installaudiotap(onbus:buffersize:format:tapprovider:)).
  - Simper's trapezoidal SVF (Cytomic "SvfLinearTrapOptimised2"), the RBJ cookbook, and ITU-R BS.1770-5.

After that I read the Sprint EQ evidence and compared it with my results (see "Agreement with earlier evidence").

## Verdict table

P = PROVEN-CORRECT · CU = CORRECT-UNPROVEN · Q = QUESTIONABLE · **D** = DEFECT

| Row | Algorithm | Verdict | Evidence (mine) | Missing proof |
|---|---|---|---|---|
| D1 | 31-band grid | P | `10^(1.3+0.1m)` = IEC 61260-1 base-10 mid-band `1000·10^(0.1x)`, x = −17…13. Kit and C++ are pinned to one table (EQ_Bands_MatchKit). | — |
| D2 | Bell coefficients (SVF ≡ RBJ / Orfanidis) | P | Algebra: `m1(2k+m1) = k²(A⁴−1)`. The bilinear denominator gives `β = k0·sinω/(2A) = tan(0.2ω)/√G`, which is Orfanidis' β with G_B = √G and B = 0.4ω. My numbers: `k·A/k0 − 1` ≤ 6.7e-16, and the encoded gain `20log10(1+m1/k)` matches `filterGainDb` within 8.5e-14 dB across 2 142 designs × 6 rates. | — |
| D3 | Cancellation-free magnitude | P | The read-back equals my independent complex-z biquad cascade (written from the ACGE equations) within 2e-9 dB at 44.1–96 kHz, 3.7e-8 at 192 kHz and 5.9e-7 at 768 kHz (the oracle's own double precision), over a dense 1/48-octave grid. | — |
| D4 | ACGE WLS solver | P | (1) **Port:** today's C++ equals the research reference `geq2.solve_passes(t,fs,5)` within ≤ 6.3e-8 dB on 600 random curves × 4 rates. (2) **Accuracy:** centre error ≤ 0.448 dB on 1 000 binary ±12 commands, ≤ 0.33 dB uniform, 0.028 dB on the presets, at every rate from 44 to 768 kHz. (3) **Optimality:** the weighted cost is ≤ 1.027× the true non-linear optimum from my own Gauss–Newton. The 5-pass fixed point is near-optimal and never diverged. | Accuracy is not gated above 192 kHz (it plays to 768 kHz). I measured the same accuracy there. |
| D5 | Played read-back | P | As D3. In time, the real module's impulse-response FFT equals the oracle (see D9). | — |
| D6 | Design C-ABI, Swift wrapper, plot grid | P | The C-ABI writes nothing on failure (tested). The grid `20·1000^(i/255)` is < Nyquist at ≥ 44 kHz. | `EQDesigner.swift` (app target, about 20 LOC of pointer plumbing) has no test. |
| D7 | Realizer EQ realisation | **Q** | Correct as specified. But at a device rate < 44 kHz the EQ silently plays **flat**, and the graph loses its played line (`EQViewModel.played` is `nil`). AirPods in HFP (16 / 24 kHz) hit this. See Q-1. | — |
| D8 | Per-band τ rule | P | My own **gesture sequences** (not in the gate) drive the real designer → `rampsFor` → `EQModule`: 1 dB drag steps every 16.7 ms on bands 0/1/2/4, and +12 / 0 toggles every 50 ms. Worst overshoot over the loudest endpoint is **+0.64 dB**, with 0 ms above +1 dB. That is inside the gate's own +0.75 dB local bound. | Add a mid-glide re-target (drag) case to `EqTransitionTests`. Today only A→B pairs are gated. |
| D9 | RT SVF cascade (double, simd_double2) | P | The real `EQModule`'s impulse-response FFT vs the independent oracle is ≤ **3.4e-6 dB** at 44.1/48/192/384 kHz, for 1/2/3/6/8 channels (odd counts included), on zigzag, binary-worst, ±12 single-band and uniform curves. Channels are identical up to float rounding. Tails decay to 0. | — |
| D10 | Coefficient glide (one-pole on k, m1) | P | Proof: with one α for both, `m1+k` stays a convex combination of positives, so every intermediate is a stable bell (`A² = 1+m1/k > 0`). The re-target sequences are measured under D8. | (as D8) |
| D11 | Output-gain glide | P | One-pole in dB, per-sample exp. Tested. | — |
| D12 | Identity bypass and guards | P | m1 == 0 everywhere and settled → skip, bit-exact. Tested. | — |
| D13 | Tone weights | P | Each raised-cosine step is C¹ (`cos(±π/2)=0`). The steps are ≥ 1.58 octave apart, so the weights lie in [0,1] and telescope to 1. TONE-01..05 test the property. | — |
| D14 | Curve composition | P | `\|tone offset\| ≤ 12·Σw = 12`, so `base = point − offset` never meets its ±24 clamp, and `setPoint` is an exact inverse. Tested. | — |
| D15 | Stroke interpolation | P | Mouse-down snapshot, contiguous drawn run, 0.75 / 0.25 shoulder. Tested and fuzzed (N108). | — |
| D16 | Plot map | P | Continuous log-f map. Dots at nominal f are ≤ 0.14 % of the axis from the exact centres. Tested. | — |
| D21 | Profiler block spectra | P | My own Python rectangular re-implementation equals the C++ prediction to 3 decimals in **all 49** programme × curve cases. Source loudness equals my independent BS.1770 meter exactly (e.g. −19.23 / −22.56 LUFS). | — |
| D22 | Decimation | P | Kept blocks are always at multiples of `strideHops` (`completeHop` re-checks after `decimate`). Tested. | — |
| D23 | 1/24-octave grid | P | 244 bands at 44.1 kHz and 247 at 48 kHz, recomputed. Tested. | — |
| D24 | Gated ΔL predictor | P | Gates are BS.1770 two-stage, strict `>`, applied per set. **True ΔL** comes from filtering with the real EQ and measuring with my meter. Broadband / dynamic / gated programmes: error ≤ **0.017 dB**. Realistic bass edits on a pure low tone: ≤ 0.5 dB, adjacent ±6 ≤ 0.96 dB. Adversarial pointed curves on a sustained 31–63 Hz tone: under-compensation up to **5.1 dB**, over-compensation up to **1.0 dB**. That sits inside the documented envelope (8.2 dB under, ≤ 3 dB past; `TrackLoudnessProfile.h`). See O-1. | — |
| D25 | Profile / block loudness | P | As D21. | — |
| D26 | Pink-noise prior | **CU** | Correct: ln-width × \|K(f_c)\|², scaled to −23 LUFS. **My oracle:** ΔL on the prior vs ΔL on profiled 30 s pink noise, 42 curves × 4 rates, max **0.034 dB**. | No test checks the prior's *shape*. Add "prior ≈ profiled pink noise, ΔL within 0.05 dB". |
| D27 | Loudness-neutral gain state machine | P | Rule-by-rule tests (`TrackLoudnessGain_Rules`). I read every transition, including LRU eviction (it never evicts the current track; 4 slots). | (The input-timing issue is P3's; see cross-checks.) |
| D28 | Causal tap | P | Pre-EQ placement confirmed (`DSPKernel.cpp:168-170`). Fallback tested. | The drop-on-full and channel-width-change discard paths are not tested. |
| D29 | Swift analysis pipeline | P | ANALYZER-01..06. Token = FNV-1a over path, size and mtime. | — |
| D30 | Profiler C-ABI weights | P | Weights are applied only when the layout matches the channel count. Tested. (`asLoudnessPredictChangeDb` has no production caller: DUP-15.) | — |
| D53 | Spectrum FFT and magnitude | **D** | The real Swift analyzer reads a **0 dBFS sine at +3.0 … +4.2 dB**, normalised **1.04–1.05**, outside its own documented [0,1]. A −20 dBFS sine reads −16 dB. Only the first 4096 frames of each ~100 ms tap are analysed: 21 % of the audio at 192 kHz. See D-1. | No tests at all. |
| D54 | Band mapping | **D** | N is fixed at 4096 at every rate. At 192 kHz, 6 of 44 bands duplicate a neighbour's bins and 2 include the DC bin. At 96 / 192 kHz a 100 Hz tone lights the 90 Hz and 101 Hz bands equally. See D-1. | No tests. |
| D55 | Release ballistics | **Q** | `y = max(x, 0.85·y)` per tap buffer, in normalised-dB units: about 12 dB of fall on the first 100 ms step from full scale, 1.5 dB at −70 dB. The comment's "20 Hz / ≈150 ms" is wrong: taps arrive at 10 Hz. See Q-2. | No tests. |
| D56 | Spectrum hand-off buffer | **D** | **ThreadSanitizer reports a data race** between `write` and `read`. A torn-frame counter saw **1 033 torn frames in 160 984 reads** under contention. The type documents "no torn frame". See D-2. | No tests. |
| D57 | Peak-hold caps (as deployed) | **D** | `PeakHoldTracker` itself is right (PH-01..09). Its feed is wrong: it advances 1/20 s **per new frame**, but frames arrive at 10 Hz. The caps hold **1.2 s** instead of 0.6 s and fall at **0.625** instead of 1.25 FS/s. See D-3. | A test of the feed (elapsed = real time between frames). |
| D58 | Colour ramp | P | Clamped piecewise-linear sRGB. R4-SPEC tests. (OKLab interpolation would be the modern choice; it is cosmetic.) | — |
| N102 | Slot resolution | P | STORE tests. Fuzz invariants hold (below). | — |
| N103 | Pin / unpin | P | PIN / OUTKEY tests and the fuzz. The aggregate-UID prefix is duplicated in Swift and C++ (map). | — |
| N104 | Store codec | P | STORE-07..09, BRK-01. **Fuzz I3:** the store round-trips through JSON after every one of 48 000 random verbs. | — |
| N105 | Canonical form / edited rule | P | STATE tests and the fuzz (canonical form survives the codec). | — |
| N106 | Bring back | P | BRING tests. **Fuzz I4:** Esc restores current and the offer exactly. | — |
| N107 | Session verbs | P | **Fuzz I1:** whenever what plays (points or plays) changed, the outcome had `.send`. **I2:** with no stroke open, the store and My Presets always equal what the verbs asked to write. 0 violations. | Example tests only. Adopt the fuzz as a permanent property test. |
| N108 | Stroke lifecycle | P | SESSION-06..09 and the fuzz (8 182 steps mid-stroke). | — |
| N109 | EQStroke (= D15) | P | — | — |
| N110 | Output switch | P | SESSION-01..05 and the fuzz (send rule). | Toast rule only by example. |
| N111 | Slot changes from pin / preset edits | P | SESSION-10/11 and the fuzz. | — |
| N112 | My Presets and naming | P | MINE tests. Reserved ids and display names are case-insensitive. Fuzzed with "late night" / "Warm" / "Studio" / "" names. | — |
| N113 | v1→v2 migration | P | MIGRATE-01..10. Fingerprint rule read in full. | — |
| N114 | Audible-state precedence | P | HEAR-01..04. | — |

**Counts (45 rows):** PROVEN-CORRECT 38 · CORRECT-UNPROVEN 1 (D26) · QUESTIONABLE 2 (D7, D55) · DEFECT 4 (D53,
D54, D56, D57).

**Fuzz coverage, for scale:** 400 seeds × 120 verbs over 22 verb kinds.
- 7 outputs: no output, built-in, two units of one model, a DAC, a private aggregate, and an empty UID.
- Steps spent in each state: 16 934 with pins, 5 440 with My Presets, 8 182 mid-stroke, 4 266 comparing.
- 18 393 sends.

## Does today's code still match the proven design? (the re-baselined golden master)

- The golden master `GoldenMaster_StereoN2_v1` is a **change detector**, not a proof. It is one hash of a +6 dB @ 1 kHz
  chirp. Its hash `0xE7AF0C67F9340785` was introduced once, in EQ1b (`a303cde`, the deliberate re-baseline), and has
  not changed since (`git log -S`).
- Independent of the hash, today's EQ still is the proven design:
  - the designer matches the research reference within ≤ 6.3e-8 dB on 600 curves × 4 rates;
  - the RT cascade's impulse response matches an oracle written from the paper's equations within ≤ 3.4e-6 dB, at four
    rates and five channel counts.
- So the re-baseline hides no drift.
- **Test-quality note:**
  - `EQ_Designer_MatchesOracle` proves **port fidelity**: six pinned vectors from the same algorithm in Python.
  - Correctness of the *accuracy* claim rests on `EQ_ACGE_*` (centre error) measured through the read-back, and the
    read-back is itself proven against an independent RBJ product (`EQ_Readback_MatchesIndependentEval`). That chain
    is sound.

## DEFECT details

### D-1 (D53, D54): the spectrum analyzer is mis-calibrated, and its resolution and coverage do not follow the sample rate. LOCAL
- **Evidence.** The real `SpectrumAnalyzer.swift` is compiled with a probe (`exp-p1/spec/main.swift`), and the tap
  sizes were measured in offline manual rendering (`exp-p1/tap/tap.swift`, no device I/O).
  - **Level.** A 0 dBFS sine at 1 kHz / 997 Hz / 100 Hz / 45 Hz reads +3.0…+4.23 dB (normalised 1.038–1.053) at 44.1,
    48, 96 and 192 kHz. −20 dBFS reads −15.8…−16.4 dB.
    - Theory: `vDSP_HANN_NORM` makes `W = 0.8165·(1−cos)` (`vDSP.h`), so the coherent gain is 0.8165. `vDSP_fft_zrip`
      returns 2× the DFT. The code scales by `2/N`, which is right only for a coherent gain of 0.5 (HANN_DENORM).
    - Result: 2·0.8165 = 1.633, or **+4.26 dB** at the bin centre.
    - The header comment (`SpectrumAnalyzer.swift:108`) says `0.5·(1−cos(2πn/(N−1)))`. Both the scale and the period
      are wrong.
    - The views clamp at 1 (`SpectrumAnalyzerView.swift:58`, `EQGraphSilhouette.swift:49`), so everything from about
      −4.3 dBFS up to 0 dBFS draws as a flat-topped full bar.
  - **Coverage.** `installTap(bufferSize: 4096)` delivers **4410 / 4800 / 9600 / 19200** frames at 44.1 / 48 / 96 /
    192 kHz. That is Apple's documented 100 ms floor. `processTapBuffer` takes `min(frameCount, 4096)`
    (`SpectrumAnalyzer.swift:140`), so 93 / 85 / 43 / **21 %** of the audio is analysed. Transients in the rest are
    never shown.
  - **Resolution.** N = 4096 at every rate (`SpectrumConstants.swift:6`), so bins are 46.9 Hz at 192 kHz.
    - 6 of 44 bands duplicate the previous band's bin range.
    - Bands 0–1 (40 / 45 Hz) include DC.
    - At 96 / 192 kHz a 100 Hz tone shows equally in the 90 Hz and 101 Hz bands.
  - The same code feeds Monitoring's per-channel BEFORE / AFTER analyzers.
- **Root cause.** The analyzer assumes a 4096-frame tap at about 48 kHz and a rectangular-window gain. Neither holds.
  Nothing tests it (map §8: "none").
- **Remedy.**
  1. Window-gain-correct scaling: use HANN_DENORM, or divide by Σw/2. Clamp the normalised value.
  2. Make N follow the tap: the next power of two ≥ the delivered frames, or Welch-average 4096-point segments over the
     whole buffer. Build the band ranges from the actual rate, and drop bins below about 20 Hz.
  3. Add the oracle test area-ui asked for: "a known sine lands in its band at its dBFS ±0.5 dB, at every rate". My
     probe is that test.
- **Effort / risk.** S / low (visual only; no audio path).

### D-2 (D56): `SpectrumDoubleBuffer` tears frames and is a data race, against its own contract. LOCAL
- **Evidence.**
  - `exp-p1/spec` race mode, real `SpectrumDoubleBuffer.swift`, built with `-sanitize=thread`: **"ThreadSanitizer:
    data race … in SpectrumDoubleBuffer.read(into:)"** against `write(_:)`.
  - Without TSan, a writer that fills every element with one value against a reader that checks uniformity: **1 033
    torn frames / 160 984 reads**.
  - The doc comment claims "a reader that observes the new generation is guaranteed to see the fully-written slot (no
    torn frame)" (`SpectrumDoubleBuffer.swift:24-26, 35-38`).
  - Release / acquire only orders the *publish*. Nothing stops the writer from lapping the reader: two writes during one
    read land in the slot being copied.
  - In production the writer runs at 10 Hz and the reader copies 44 floats, so a lap needs the main thread preempted
    for about 100 ms mid-copy. That is rare, but this codebase has documented main-thread stalls.
  - The nested `[[Float]]` storage adds copy-on-write uniqueness checks on the RT side whenever the reader holds a
    reference.
- **Root cause.** A two-slot generation-parity hand-off. It is the same hazard area-dsp-cpp DSP-07 reports for the
  `LoudnessModule` layout buffer, and the one the project already fixed in C++ by moving `TargetState` to a triple
  buffer (`DoubleBufferSnapshot.h`).
- **Remedy.** One SPSC triple buffer: three pre-allocated `UnsafeMutableBufferPointer<Float>` slots and an
  `Atomic<Int>` exchange (acq_rel), mirroring `DoubleBufferSnapshot`. Better still, one shared Swift type for every
  RT→UI readout, which is arch.md ARCH-8's single readout channel.
- **Effort / risk.** S / low.

### D-3 (D57 as deployed): the peak-hold caps run at half speed. LOCAL
- **Evidence.**
  - `AudioViewModel+SpectrumTimer.swift:181` returns early when `readSpectrumBands` reports "no new frame". That
    became true with F2 (`SpectrumDoubleBuffer.read` returns new-data-only).
  - `:208` then feeds `peakTracker.update(…, elapsed: 1.0 / 20.0)` on each **new** frame only.
  - New frames arrive once per tap buffer, every 100 ms (measured; Apple range 100–400 ms).
  - So fed time runs at half of real time: the 0.6 s hold lasts **1.2 s**, and the 1.25 FS/s fall becomes **0.625
    FS/s**. If the system picks a longer tap, it is slower still.
- **Root cause.** A nominal-tick `elapsed` stands in for measured time. The tracker's own design (time-fed) is right;
  the feed broke it when the reader became new-data-only.
- **Remedy.** Feed the real time between fed frames: the monotonic time while playing, or the tap's
  `AVAudioTime.sampleTime` delta / rate published with the frame. area-ui's `TimelineView` + `context.date` primitive
  does the same. Add a feed test.
- **Effort / risk.** S / low.

## QUESTIONABLE details

### Q-1 (D7): below 44 kHz the EQ silently plays flat. LOCAL. A product decision
- **Evidence.**
  - `GraphicEQDesigner::kMinSampleRateHz = 44000` (`GraphicEQDesigner.h:63`).
  - `Realizer::realizeEq` publishes `EQParams{}` (identity) on design failure (`Realizer.mm:416-423`). It logs, but
    the user is not told.
  - `EQViewModel.played` turns `nil`, so the graph drops its played line but still draws the set points
    (`EQGraphPainter.swift:136`).
  - Bluetooth HFP routes (AirPods with the mic open: 16 / 24 kHz) and 32 kHz devices hit this.
- **Options (recommended first).**
  - (a) Design only the bands whose centre is below about 0.45·fs, hold the rest at 0 dB, and draw them as "not
    available at this rate". The solver takes a reduced basis.
  - (b) Keep the flat fallback, but say so in the EQ strip ("EQ unavailable at 24 kHz").
- **Effort.** (a) M; (b) S.

### Q-2 (D55): the release law is per buffer and in normalised dB, and its documentation is wrong. LOCAL
- `y = max(x, 0.85·y_prev)` on values normalised over an 80 dB span (`SpectrumAnalyzer.swift:280-286`).
- The fall rate in dB is proportional to the height above the −80 floor: about 12 dB on the first 100 ms from full
  scale, about 1.5 dB per step near −70 dB.
- The comment's "≈150 ms at 20 Hz display rate" is wrong (10 Hz frames).
- Meter practice (IEC 60268-10 / -18 fall-back) uses a constant dB/s, and time-based, not per-callback.
- **Remedy.** α = exp(−Δt/τ) from the measured Δt, or a constant dB/s fall. This folds into D-3's "measured time" fix.
- **Effort.** S.

## Observations (no change of verdict)

- **O-1, the predictor's tonal-bass envelope (D24), confirmed independently.**
  - Cause: the rectangular 400 ms block spreads a sustained low tone over sidelobes across many 1/24-octave bands.
    Weighting that spread by \|H\|² misses when the curve changes fast exactly there.
  - Measured, under-compensation: 63 Hz tone under zigzag ±12, true −11.0 dB vs predicted −5.9; 31.5 Hz under zigzag
    −2.5; 50 Hz under −12 @ 50 Hz +2.0.
  - Measured, over-compensation: ≤ 1.0 dB (alternating bass / treble programme under zigzag).
  - A Hann-rescaled variant (my prototype: Hann shape, rectangular total) is not uniformly better (63 Hz zigzag 1.5 dB,
    but 31.5 Hz 3.1 dB). The real fix is resolution: a longer analysis window for the bands below about 150 Hz,
    carrying only the spectral *shape* into each block while keeping each block's exact Parseval total.
  - Sprint EQ accepted this envelope deliberately (amendment 19), so I report it, but not as a defect.
- **SOTA for the solver (D4).**
  - The in-house variant (c = 0.5 half-dB convention, B = 0.40ω, weights 1 / 0.5, 5 passes, no hand-tuned top bands)
    beats the published third-octave ACGE parameterisation. On my run, ACGE3 *without* its 44.1 kHz-only hand-tuned
    top bandwidths gave 2.05 dB worst on binary ±12, against 0.42 dB for the code. Published SGE3 reaches 0.81 dB max
    (Rämö 2020).
  - Cost: 552 µs per design at −O0 (`Designer_Timing`). That is the right choice today.
  - Doc nit, not a finding: `GraphicEQBands.h:49-50` calls B = 0.40·ω "the ACGE convention". The published convention
    is c = 0.4 at neighbour spacing, 0.4662ω. `engine-plan.md` describes it correctly.
- **The ARCH-7 question for the DSP reviewer: can the SVF host shelves and pass filters?** Yes, by Simper's mixing:
  - low shelf: `g = tan(πf/fs)/√A`, `m0 = 1`, `m1 = k(A−1)`, `m2 = A²−1`;
  - high shelf: `g·√A`, `m0 = A²`, `m1 = k(1−A)A`, `m2 = 1−A²`;
  - LP / HP / BP / notch through `(m0, m1, m2)`.
  - Today's tick hard-codes `m0 = 1, m2 = 0` and a per-band *fixed* prewarp (`EQModule.cpp:46, 207`). Layered EQ
    programs need per-band `(g, m0, m2)` targets as well, and a shelf's `g` changes with gain, so `g` must glide too.
  - The convex-combination stability argument (D10) carries over: g, k > 0 are preserved. The "every intermediate is a
    bell" property does not.

## Agreement with earlier evidence and the finished reviews

- **Sprint EQ evidence** (`docs/design/eq-lens/evidence/`, read after my runs). I agree on every point I re-measured:
  - centre accuracy (0.028 presets / 0.45 binary);
  - the ACGE3 / SGE3 comparison and its hand-tuning caveat (`review-sota.md` §§ on ACGE3, SGE3);
  - the readback precision rule;
  - the predictor's broadband accuracy and its documented tonal limits.
  - My gesture-sequence measurement adds a case their A→B gates do not cover; it passes.
- **area-ui** ("D53–D56 zero coverage; oracle: a known sine must land in the expected band at the expected dB"). Agree,
  and I ran that oracle: it fails on level (+4.3 dB) and on band placement at high rates (D-1). Agree with its
  `TimelineView` + time-fed peak-hold remedy. D-3 is the concrete bug it prevents.
- **area-dsp-cpp DSP-07** (two-slot parity buffer for layout weights; weights reset on re-init). Agree. D-2 is the same
  lapping hazard on the Swift side, now with TSan and torn-frame evidence. The weight reset also affects my D28 / D29
  rows: the causal tap and the kernel meter fall back to stereo weights after a device change. One remedy covers both:
  one triple-buffer type.
- **panel-p3-path-breaker** ("B's gain is applied to the last ≤ ~190 ms of A"). Agree that the gain *state machine*
  (D27) is right and its *input event* is early. The fix belongs at the seam's audibility timing, not in
  `TrackLoudnessGain`.
- **duplication S40 / DUP-15** (`asLoudnessPredictChangeDb` test-only C-ABI). Agree (D30).
- **duplication X1** (the multichannel "oracle" re-types the production K-weighting). Not my rows. My D21 / D24 checks
  used an independent meter built from the Recommendation's coefficient table, so they do not depend on it.

## Top missing proofs (ranked)

1. A spectrum analyzer oracle test: sine level and band at 44.1 / 48 / 96 / 192 kHz (D53 / D54). Today it would fail.
2. A model-based property test for `EQSession` (I1 send-on-change, I2 written-when-idle, I3 codec round-trip, I4 Esc
   restores). It found 0 violations, so it costs nothing to adopt.
3. A peak-hold feed test and a hand-off lapping test (D57 / D56).
4. Pink prior ≈ profiled pink noise, ΔL within 0.05 dB (D26).
5. An EQ mid-glide re-target (drag / toggle sequence) transition gate (D8 / D10).
6. Designer accuracy above 192 kHz (it is in the design domain to 768 kHz).

## Evidence index (`scratchpad/council/exp-p1/`)

- `h/eqh.cpp`: drives the real designer, τ rule and `EQModule` (design dump, impulse response, apply, glide).
- `h/eqseq.cpp`: Realizer-style publish sequences with cos / sin envelope probes.
- `h/proh.cpp`: the real profiler, predictor and pink prior.
- `h/oracle.py`: the ACGE / Orfanidis bell and z-domain cascade, my Gauss–Newton WLS solver, and the paper's ACGE3.
- `h/t_solver.py`, `t_paper.py`, `t_ir.py`, `t_seq.py`, `t_port.py`, `t_pred.py`, `t_pred2.py`, `t_prior.py`: the
  runs above.
- `h/ZZPanelP1FuzzTests.swift`: the `EQSession` fuzz.
- `spec/main.swift`: the real analyzer, level, band and race probes.
- `tap/tap.swift`: tap buffer sizes in offline manual rendering.
- `t_*.log`: the 86 null-test runs (all pass).
