# Panel P2: loudness, limiter, crossfeed, spatial, blend. BREAKER report

Repo `main` @ 7d7c2cd. I built and ran everything in my own worktree (`.claude/worktrees/panel-p2-breaker`), with
scratch in `scratchpad/council/exp-p2-breaker/`. I did not edit Sources/Tests, launch the app or play audio. The
AVAudioEngine probes ran in offline manual-rendering mode, so no device was touched.

**Method.** `p2harness.cpp` links the **real** production translation units: DSPKernel, LoudnessModule (with its own
worker thread), LimiterModule, CrossfeedModule, SpatialRenderKernel, ChannelLayoutDecoder and LufsMeter. It drives
them with adversarial inputs. The results are judged by oracles that are independent of the code:
- **libebur128** in exact-gating mode (vendored v1.2.6).
- **The analytic truth for sinusoids:** the continuous peak of a unit sine is 1.0.
- **An ideal band-limited true-peak oracle:** periodic-FFT ×32 interpolation on segments with discarded margins
  (`tp_oracle.py`).
- **A "DAC-like" reconstruction oracle:** ×16 linear-phase Kaiser FIR with passband 0.4535·fs and stopband 0.5465·fs
  (`tp_multi.py`).
- **The bs2b reference source**, opened and re-implemented in `xfeed.py`.
- **ITU-R BS.775-4, Table 2** (the PDF, opened).
- **An offline AVAudioEngine probe** of real 5.1 files (`layout/probe.swift`, `layout/lvl.swift`).

Every number below comes from those runs. The repro commands are in §5.

Production context that matters:
- The kernel runs **only at the 48 kHz graph rate** (`AudioEngineBridge+Lifecycle.swift:46`, `+Reconfigure.swift:97-105`).
  Every other file rate is resampled first.
- The **default Intensity is 0.20** (`AudioViewModel.swift:132`). So the default Enhanced path is P3:
  - EQ;
  - an equal-power blend with stub wet stages;
  - the normaliser at full contribution (min(1, 0.2/0.1) = 1), target −16 LUFS, always enabled, with no UI control
    (no writer of `loudness.enabled` or `lufsTarget` exists in `Sources/`);
  - the limiter at −1 dBTP.

---

## 1. Verdict table

| Row | Algorithm | Verdict | Evidence (mine) | Missing proof |
|---|---|---|---|---|
| D17 | K-weighting | **PROVEN-CORRECT** | The coefficient form is identical to libebur128 `ebur128.c` (shelf + RLB, numerator 1,−2,1). 11 rates (8 k…384 k) × 8 signals: integrated within **≤1e-4 LU** of libebur128 exact gating. Momentary and short-term match at hop boundaries. | none. One LOCAL doc error: see D67. |
| D18 | Gated LUFS meter | **PROVEN-CORRECT** | The relative-gate straddle (−9.95 / −10.05 LU), the absolute-gate straddle (−69.97 LUFS) and a block above the histogram top (+12 LUFS) are all exact. The histogram bin-centre gate costs at most **0.012 LU** (a 60 s ramp at 176.4 k / 384 k). Sub-400 ms input reads −200 where libebur128 reads −inf; they are equivalent. | none |
| D19 | BS.1770 weights / layout decode | **DEFECT** | Only 5 tags are decoded. AAC_5_1 = MPEG_5_1_D (every **ALAC/AAC 5.1** file), MPEG_5_1_C, WAVE_5_1_B, WAVE_7_1, DiscreteInOrder\|6 (plain WAV) and Unknown\|6 all decode to **weight 1.0 on all 6 slots**, LFE included. UseChannelBitmap and UseChannelDescriptions decode to **numCh 2, weights {1,1,0,0,0,0}**. | no test outside the 5 tags |
| D20 | Auto-makeup normaliser | **DEFECT** (STRUCTURAL) | Detail in §2.1: makeup carried across tracks; gapless chains never re-measure; ~1 dB/s; +12 dB makeup plus the limiter equals DRC on dynamic music at the default Intensity; makeup reset to 0 dB on re-allocation. | no test of the law, the reset points or the track-change behaviour |
| D31 | 8× polyphase TP kernel | **CORRECT-UNPROVEN** | Against the analytic sine truth, the worst under-read is **−0.164 dB** (0.49 fs) and −0.109 dB at 0.40 fs, where libebur128 reads −0.436 dB. Its own response is −0.82 dB at 0.45 fs and −6.0 dB at fs/2, by design. The "< 0.17 dB" claim holds. | The tests use libebur128 as the oracle, and libebur128 is **less accurate than the kernel**. A sine sweep against the analytic peak is missing. |
| D32 | Look-ahead limiter core | **CORRECT-UNPROVEN** (48 k); latent DEFECT above 192 k | At 48 k the whole battery (sines 1–23.5 kHz at 0 / +6 dBFS, fs/4 at 45°, the "1100" ISP pattern, a +24 dB step, hot pink, clipped and tanh masters) holds −1 dBTP by libebur128 and by the DAC-like oracle. The one exception is HF-emphasised clipped noise: +0.15 dB over the DAC-like oracle. Under the ideal oracle, crushed masters exceed by 0.9–2.3 dB (energy at 0.45–0.5 fs). At **384 kHz** a +24 dB step reads **−0.36 dBTP (0.64 dB over)**: the look-ahead is capped at 576 frames. | The test margin is +0.30 dB **and** both meters must agree. libebur128 reads −1.99 dBTP on an output that is +1.33 ideal / −0.86 DAC-like, so the test is blind to near-Nyquist breaches. |
| D33 | Sliding-window max | **CORRECT-UNPROVEN** | Reading: a monotonic deque, eviction at `idx+L ≤ n`, capacity 577. Consistent with the battery. | a brute-force equivalence test |
| D34 | Gain computer + ballistics | **DEFECT** | Both branches attack identically, so the slow branch is always the deeper one and "deeper wins" always picks it. The **100 ms fast release never acts.** One 1 ms transient at 6.4 dB GR still reads −4.7 dB at 200 ms, −2.6 at 500 ms and −0.95 at 1 s. A 100 ms branch would read −1.7 / −0.08 / 0.0. | the release / hold timing test (none exists) |
| D35 | Prime / re-seed | **PROVEN-CORRECT** | Re-seed replays the window. The envelope restarts at 0 dB, but the 5 ms cross-fade from the (unlimited, bit-perfect) P0 input hides it. | — |
| D36 | Per-transport EQ-only ceiling | **PROVEN-CORRECT** (as specified) | The mapping matches the policy. Edge: USB-transport wireless dongles (lossy) get −0.1 dBTP. | — |
| D44 | Crossfeed DSP + device gate | **DEFECT** | Real module, centre (L = R) content: a **notch of −4.2 / −4.5 / −6.3 dB at 1 kHz**, then −2.5 / −2.6 / −3.5 dB above 3 kHz, for Relaxed / Default / Strong. bs2b, the cited origin, is a smooth ≤ −1.06 / −1.75 / −1.48 dB shelf. The **gate excludes the Mac's own headphone jack** (transport BuiltIn) and **includes AirPlay / Bluetooth speakers**. | The tests check ≤ 180 Hz only (CF-3 at 60 Hz, CF-10 at 60–180 Hz). |
| D45 | Crossfeed coefficients | **QUESTIONABLE** | "Default/Bauer" α = 0.355 (−9.0 dB) is labelled bs2b Default (−4.5 dB, α = 0.596). Departures from bs2b: an explicit ITD delay on top of the LPF (bs2b's delay *is* the LPF group delay), and a flat direct path (bs2b uses a high-boost shelf). These are the root of the notch. | — |
| D46 | Spatial render N→M | **DEFECT** | Confirmed bit-exact: 6→2 keeps slots 0 and 1, and C, LFE, Ls and Rs are discarded. For ALAC/AAC 5.1 (D order, not remapped; see §2.5) the **Left speaker plays the CENTRE and the Right plays front-LEFT**. Loss: −4.6 LU for equal-power channels, and centre content disappears entirely. | no out < in test |
| D47 | Device-width format | **DEFECT** | Only 6 and 8 channels are mapped. A 3/4/5/7-channel file falls back to a **stereo graph**, and the player node then keeps L/R only (measured on 5.0: C, Ls, Rs absent at ≤ −47 dB). 8 ch is forced to MPEG_7_1_A (Lc/Rc), so 7.1 sources with back surrounds are passed positionally. | — |
| D48 | BRIR / Clarity modules | **QUESTIONABLE** | True pass-through stubs, so the Intensity "wet" is empty unless crossfeed is on. | — |
| D49 | Path selection P0–P3 + hysteresis | **PROVEN-CORRECT** | The bit-exact endpoints are tested. What each path changes audibly is in §2.4. | — |
| D50 | Equal-power wet/dry blend | **DEFECT** | Real kernel, stubs, crossfeed off: **+2.01 dB at the default 20 %**, +3.01 dB at 50 %, 0 dB at both ends. This matches 20·log10(sin + cos) exactly. The test *pins* +3 dB as correct. | — |
| D51 | Normaliser contribution fade | **PROVEN-CORRECT** | Reading plus the tests: a glide of ≤ 1 per 2 s, makeup^w, and the endpoints are reached exactly. | — |
| D52 | Correlation-compensated bypass fade | **PROVEN-CORRECT** | I re-derived it: (g_p + ρ·g_i)² + g_i²(1 − ρ²) = 1, so power is kept exactly for ρ ∈ [0, 1], and g_p ≥ 0. Known, documented limit: an anti-phase tone (ρ clamped from −1 to 0, e.g. 166.7 Hz with a 3 ms offset) nulls completely at mid-fade. | — |
| D59 | UI meter bridge | **DEFECT** (LOCAL) | The meter is created once per graph build (`+Graph.swift:108`) and has no reset API, so **"Integrated" is integrated over the whole session**: all tracks and pauses. It is stereo-only (documented as ENH-002). | — |
| D60 | ParameterRamp | **CORRECT-UNPROVEN** | The maths is right. Float stagnation is measured: 50 ms makeup ramp to unity sticks at **+1.43e-4 / −7.15e-5**. LoudnessModule's "settled at unity" test (`< 1e-6`, `LoudnessModule.cpp:166-171`) can therefore never pass after any makeup move: the fast path is dead and a residual of ~0.001 dB stays applied. | a direct test |
| D67 | Flush-to-zero | **PROVEN-CORRECT** | On this M-series machine, **FPCR.FZ flushes DOUBLE subnormals too** (`ftz.cpp`: 1e-310 → 0). So `LufsMeter.h:123-128` ("FZ does NOT flush doubles") is **wrong**. The manual flush still earns its keep on the UI tap thread, which never sets FZ. | — |
| D68 | Non-finite scrub | **PROVEN-CORRECT** | The exponent-mask reduction is correct, and the tests exist. | — |
| D69 | Realizer intent coalescing | **PROVEN-CORRECT** | `take()` and `drainPosted_ = false` happen under one lock, so no intent is lost and at most 1 drain is posted. Tested. | — |
| D70 | Layout-weight buffer | **DEFECT** | The "stereo seed" is **{1,1,0,0,0,0,0,0}**, not the {1,1,…} its comment claims (`LoudnessModule.cpp:70-84`). It is the active state after every re-allocation, because `Realizer::reinitializeOnQueue` (`Realizer.mm:341-361`) never re-publishes the layout. Real LoudnessModule on a C/surround-heavy 5.1 programme: **−40.8 LUFS measured vs −23.9 correct (−16.9 LU)**. The 2-slot parity also tears if two publishes land inside one worker read. | `publishChannelLayout` is in no test |

**Counts (25 rows):**
- PROVEN-CORRECT: 10 (D17, D18, D35, D36, D49, D51, D52, D67, D68, D69);
- CORRECT-UNPROVEN: 4 (D31, D32, D33, D60);
- DEFECT: 9 (D19, D20, D34, D44, D46, D47, D50, D59, D70);
- QUESTIONABLE: 2 (D45, D48).

---

## 2. Details for every DEFECT and QUESTIONABLE row

### 2.1 D20: the normaliser is a session-level slow AGC that, with the limiter, acts as DRC by default. STRUCTURAL

**Evidence.**
- Real LoudnessModule (worker thread) plus the real LimiterModule, paced at 20× real time, with 0 dropped frames
  (`./p2harness norm 20`, `normE 20`, CSVs `norm_*.csv`).
- Law, `LoudnessModule.cpp:264-287`: target = clamp(−16 − I, −20, +12), slewed 0.1 dB per gated block (≈ 1 dB/s).
- I is the gated integrated loudness of **everything since the meter was last reset**.

When the meter and the makeup reset:

| Event | Meter reset? | Makeup state reset? |
|---|---|---|
| User-initiated `playFile` (new track, resume from pause, device move): `+Playback.swift:171` → `configureGraphForSource` → `publishChannelLayout` → `configureChannels` → `reset()` | yes | **no** (`currentMakeupDb_` persists) |
| Gapless auto-advance | **no** | no |
| Enhanced seek (`+PureMode.swift:174-230` reschedules; no `playFile`) | **no** | no |
| AU re-allocation (`DSPKernel.cpp:62-76` builds a fresh LoudnessModule) | yes | **yes, to 0 dB** |

Measured scenarios:

| Scenario | Result |
|---|---|
| A. Loud (−8 LUFS) → user-chosen quiet (−24) | The quiet track starts at the loud track's −7.8 dB makeup: output **−32 LUFS**, climbing 1 dB/s. It reaches −16 only **~16 s** into the track. |
| B. Same, as a **gapless** roll | The relative gate (−10 LU below the loud-dominated mean) excludes every quiet block, so the makeup **stays −7.76 dB**. The quiet track plays at **−32 LUFS (16 LU under target) for the whole 40 s**. Analytically its blocks only start passing the gate after **≈133 s**. A whole gapless album is levelled by its first loud track. |
| E. Quiet (−24) → user-chosen loud (−8) | The loud track starts at +8.2 dB makeup: output momentary **−9.5…−11 LUFS (~6 LU over target)**, the limiter at **9–10 dB GR for ~6 s** and > 1 dB for ~10 s. It takes ~16 s to settle. |
| C. Classical: pp −38 LUFS for 60 s, then ff −14 LUFS (single track) | The makeup reaches the **+12 dB clamp**, so pp plays at −26 LUFS. At the ff onset the output is −11 LUFS with **up to 14 dB of limiter GR**; GR is > 1 dB on 47 % (> 3 dB on 36 %) of samples above −26 dBFS. The makeup takes ~14 s to come down. The ff−pp contrast is **24 LU → ~9.5 LU**. |
| D. Quiet dynamic master (−24 LUFS, crest-rich) | Makeup +8 dB. Transients are limited: GR > 1 dB on 48 % of samples above −26 dBFS, up to ~3 dB. |
| Re-allocation (DSP-07) | Makeup snaps to 0 dB. On a −8 LUFS master the output jumps from −16 to ≈ −8.5 LUFS and takes ~8 s (1 dB/s) to return. |

**Lead #1 (product reviewer): CONFIRMED, with a correction.** The meter *is* reset on every user-initiated load (the
earlier SOTA review noted this as well). It is **not** reset on gapless advance or seek, and the makeup *state* is
never reset except by re-allocation. There is no ReplayGain, track or album awareness.

**Is it right for an audiophile player? No.**
- LD-17 says "transparent normalisation, no program DRC by default". A +12 dB makeup feeding a hard −1 dBTP limiter
  is DRC on exactly the material audiophiles care about. It is on at the default 20 % Intensity, and there is no
  control for it.
- State of practice is a *static per-track gain*. Spotify Normal mode lifts quiet tracks **only up to their
  true-peak headroom**; its limiter belongs to "Loud" mode only. ReplayGain / Sound Check use track or album gain.

**Root cause.** A causal, programme-integrating meter is used as the gain law. The pre-analysed per-track loudness
already exists in the codebase (TrackLoudnessAnalyzer / profile, D21–D29) but is not used here.

**Remedy.**
- Replace the time-varying makeup with a **static per-track gain**: −16 − I_track from the existing offline profile,
  with gapless-group / album gain from the D27 group machinery.
- Cap positive gain by the track's true-peak headroom (needs a TP field in the analysis).
- Keep the causal meter only as the fallback for unanalysed tracks: reset per track, no carry-over, fast first
  estimate.
- Effort M; risk M (touches loudness-neutral EQ ordering). Add tests: track-change, gapless, re-allocation, classical
  crescendo with a limiter-GR budget.

### 2.2 D50: the equal-power blend adds +2 dB at the default Intensity while the wet stages are stubs. SIGNIFICANT

**Evidence.** Real kernel with loudness and limiter off (`./p2harness blend`). Output relative to Intensity 1:

| r | 0.05 | 0.1 | **0.2** | 0.3 | 0.5 | 0.7 | 0.9 |
|---|---|---|---|---|---|---|---|
| dB | +0.63 | +1.17 | **+2.01** | +2.57 | +3.01 | +2.57 | +1.17 |

- This is 20·log10(sin + cos) to 0.001 dB.
- `Intensity_EqualPowerAtHalf` (`IntensityTests.inc:236-280`) asserts +3.01 dB as the *expected* result, so the
  test enshrines the artifact.
- `DSPKernel.cpp:267-270` says "the normaliser downstream absorbs" it. In fact it absorbs only as the
  track-integrated I moves: a +2 dB step after 60 s is ~1.1 dB absorbed 60 s later.
- **DSP-10 confirmed.**

**Root cause.** Equal-power is the right law only for *decorrelated* wet and dry signals. Here wet = dry, or is highly
correlated (crossfeed).

**Remedy.**
- Reuse the kernel's own correlation-compensated law from D52, with input = dry and processed = wet. That gives 0 dB
  at ρ = 1 and equal power at ρ = 0. ρ can be measured per block, or set from the module chain: 1 while every wet
  stage is identity.
- Effort S; risk L. Re-baseline the intensity test against a level-match oracle.

### 2.3 D34: the "dual-stage release" is a single 500 ms release. SIGNIFICANT

**Evidence.** `LimiterModule.h:396-424`.
- On attack, both `envFastDb_` and `envSlowDb_` move with the same `attackCoeff_`, so they end equal.
- On release the fast branch rises sooner, so `min(fast, slow)` is always the slow branch.
- Measured (`./p2harness release`): one 1 ms over-ceiling burst (6.4 dB GR) on a −20 dBFS tone:

| t after the burst | 50 ms | 100 | 200 | 500 | 1000 | 1500 ms |
|---|---|---|---|---|---|---|
| GR (dB) | −6.37 | −5.77 | −4.72 | −2.59 | −0.95 | −0.35 |

- That is the 500 ms τ (after the 50 ms hold). A 100 ms branch would give −1.7 dB at 200 ms.
- A single snare, clap or ISP spike ducks the following ~1–1.5 s of music. This explains the prior evidence's
  "500 ms release keeps it working far longer" (`verify-sota.md:46`).
- I **disagree** with `review-sota.md:234`, which calls it a state-of-the-art dual release.

**Remedy.**
- Make the slow branch *charge slowly*: give it its own slow attack, or cascade it from the fast envelope (the
  program-dependent release in Giannoulis / Massberg / Reiss 2012). Then it only deepens under sustained GR.
- Add a release-timing test: GR at 200 ms ≤ 2 dB after an isolated transient.
- Effort S; risk L.

### 2.4 Lead #4: what the P0–P3 selection and blend actually change across Intensity 0 → 1

| Intensity | Path | Audible effect (stubs as shipped) |
|---|---|---|
| 0, EQ flat ≥ 2 s | P0 | bit-perfect |
| 0, EQ on | P1 | EQ, then the limiter at −0.1 dBTP (wired / built-in); **no normaliser** |
| (0, 0.1) | P3 | The normaliser fades in as makeup^(r/0.1), gliding ≤ 1 per 2 s. Blend hump +0…+1.2 dB. Ceiling drops to −1 dBTP. |
| [0.1, 1) | P3 | **Full −16 LUFS normaliser (§2.1)**, plus the hump up to +3.01 dB, plus a crossfeed wet share if it is enabled, plus −1 dBTP |
| 1 | P2 | the same without the hump |

With crossfeed off, the whole "Reimagine" knob does two things:
1. Leaving 0 switches the session AGC and the −1 dBTP limiter on.
2. Moving between 0 and 1 changes level by up to 3 dB.

Clarity and BRIR do nothing. With crossfeed Default on, the centre response relative to 100 Hz at 1 kHz is −0.9 dB at
r = 0.2, −1.9 dB at r = 0.5 and −4.4 dB at r = 1.

### 2.5 D46 / D47 / D19 / D70: multichannel handling is positional and partly lossy (shared root cause). SIGNIFICANT

**Lead #2: CONFIRMED and quantified.**
- `SpatialRenderKernel.cpp:75-91, 165-178` copies slots 0 and 1 verbatim for 6→2. My harness confirmed it
  byte-for-byte (C, LFE, Ls and Rs discarded).
- For uncorrelated, equal-power main channels the listener gets 2 / (2 + 1 + 2·1.41) = **−4.6 LU**. Any
  centre-only element (vocal, dialogue) is **lost entirely**.
- The normaliser meanwhile measures all 6 weighted channels, so on a stereo device it targets loudness nobody hears.

**New: no channel remapping.** The offline AVAudioEngine probe on real files shows that AVAudioFile delivers ALAC and
AAC 5.1 in **C L R Ls Rs LFE** order (tag 0x007C0006). AVAudioPlayerNode passes the channels **positionally** into the
graph's MPEG_5_1_A (L R C LFE Ls Rs) connection; it does not remap by layout. In the app this means:
- **Stereo device:** Left = Centre, Right = front-Left.
- **5.1 device:** every channel lands on the wrong speaker.

D47 adds further losses:
- `resolveReconfigureFormat` (`+Reconfigure.swift:97-105`) falls back to **stereo** for 3, 4, 5 and 7 channels.
  The player node then emits only L/R. On a 5.0 file I measured C, Ls and Rs at ≤ −47 dB, which is leakage only.
- 8 channels is forced to MPEG_7_1_A (front-wide Lc/Rc), although 7.1 music is normally back-surround
  (MPEG_7_1_C or WAVE_7_1).

D19 and D70 (weights), as in the table:
- The decoder handles 5 tags.
- `resolveSourceLayoutTag`'s `!= kAudioChannelLayoutTag_Unknown` check (`+ChannelLayout.swift:41`) misses
  `Unknown | N`.
- After every re-allocation the weights fall back to {1,1,0,…} with no re-publish (−16.9 LU on my 5.1 probe).
- **DSP-07 confirmed:** re-allocation resets both the makeup and the layout weights.

**Root cause.** Channel *roles* are never derived from channel labels. The kernel assumes the file tag, while the
graph, the spatial AU and the mixer assume MPEG_5_1_A / MPEG_7_1_A. Nothing owns the canonical channel order.

**Remedy.**
1. Derive per-slot roles for ANY tag through AudioToolbox: `kAudioFormatProperty_ChannelLayoutForTag`, then
   `AudioChannelDescription.mChannelLabel`.
2. Remap the source into one canonical graph order at load, with an AVAudioConverter channel map or the decoder's
   own channel map.
3. Re-publish the layout from `reinitializeOnQueue`.
4. Interim fold-down while S18 binaural is pending, the standardised one rather than truncation: **ITU-R BS.775-4
   Table 2**, Lo = L + 0.7071·C + 0.7071·Ls and Ro = R + 0.7071·C + 0.7071·Rs, LFE omitted (BS.775 Annex 7 §5:
   "typically discards LFE").

The fold-down is a standard matrix, not a "naive downmix". It can raise peaks by up to **+7.7 dB** (gains summing to
2.414), and today the limiter sits *before* the spatial AU. So it must either be followed by a final safety limiter
or be placed in the effects AU ahead of the limiter.

Effort M; risk M. Tests: a 6→2 fold-down against the BS.775 matrix, a D-order source tone-to-speaker map, and
weights after re-allocation.

### 2.6 D44 / D45: the crossfeed notches centre content, and its device gate is wrong. SIGNIFICANT

**DSP.** Real CrossfeedModule, 48 kHz, centre (L = R) response in dB (`./p2harness xfeed`):

| Preset | 100 Hz | 500 | 700 | **1 k** | 1.5 k | 3 k | 10 k |
|---|---|---|---|---|---|---|---|
| Relaxed | −0.12 | −2.29 | −3.47 | **−4.19** | −3.24 | −2.07 | −2.52 |
| Default | −0.12 | −2.29 | −3.59 | **−4.51** | −3.49 | −2.13 | −2.65 |
| Strong | −0.14 | −2.86 | −4.73 | **−6.28** | −4.71 | −2.81 | −3.54 |

- The bs2b source (opened; `bs2b.c` `init()` / `cross_feed_d`, presets from `bs2b.h`) gives a smooth centre shelf
  ≤ −1.06 / −1.75 / −1.48 dB, with no notch.
- Cause: the explicit ITD delay (D = 15 samples, 0.31 ms) plus the LPF phase put the cross path ~167° out of phase
  near 1 kHz. bs2b instead uses the LPF's own group delay as the ITD and puts a high-boost shelf on the direct path.
- The tests only look at 60–180 Hz (`CrossfeedTests.inc:215-230`, `LoudnessOracleTests.inc:405-440`) and call the
  HF loss "benign".
- The Default preset label is wrong. α = 0.355 is −9.0 dB of feed, which is almost Relaxed. bs2b Default is
  −4.5 dB (α = 0.596).

**Gate.** `AudioViewModel.swift:166-171` treats only `.wireless` and `.usb` as headphones, from
`CoreAudioDevice.cpp:321-354`:
- **Wired headphones in the Mac's own jack** report transport BuiltIn, so the toggle is disabled ("Connect
  headphones to enable", `InspectorColumn.swift:143`). This is the most common crossfeed use case.
- AirPlay receivers, HomePods and Bluetooth speakers are speakers, but they enable it.
- Thunderbolt / PCI / FireWire interfaces with headphone outs are excluded.

**Remedy.**
- Port bs2b faithfully (direct-path high-boost, no extra delay), or keep the delay and compensate the direct path.
- Add a broadband centre-flatness test, e.g. |centre response| within 2 dB at 0.1–10 kHz.
- Classify built-in outputs by `kAudioDevicePropertyDataSource` ('hdpn' vs 'ispk'). Leave crossfeed user-enableable
  on any output rather than auto-gated.
- Effort S–M; risk L.

### 2.7 D59: the UI "Integrated" readout covers the whole session. LOCAL

`LoudnessMeterBridge.cpp:51-60` has no reset, and the handle is created once per graph build (`+Graph.swift:108`).
Integrated loudness therefore spans every track and pause since launch. **Remedy:** add a reset entry point and call
it on track change, or relabel. Effort S.

### 2.8 Smaller LOCAL items

- **D32, latent: the limiter breaks above 192 kHz.** At 384 kHz the look-ahead is capped at 576 frames = 1.5 ms ≈ 2.9 τ
  of attack, which leaves a 5.3 % residual. A +24 dB step measures −0.36 dBTP. **DUP-16 confirmed**, but latent
  (the kernel only runs at 48 kHz). Fix: size the deque from the maximum rate the EQ accepts, or reject rates above
  192 k in `DSPKernel::initialize`.
- **D31 / D32 test weakness.** The ceiling test (`LimiterTruePeakTests.inc:49`, `:355`) allows +0.30 dB and needs
  both meters to agree, and libebur128 under-reads near Nyquist (reads −1.99 where the DAC-like oracle reads
  −0.86 dBTP). Add an ideal or declared-passband oracle and HF-rich clipped-master fixtures.
  `Limiter_NearNyquistCeiling` checks the **sample** peak only (`LimiterTests.inc:231-280`).
- **D60.** Make LoudnessModule's settle epsilon match the float stagnation floor (~2e-4, as the kernel already
  does with 1e-4), or snap the ramp.
- **D67.** Correct the comment at `LufsMeter.h:123-128`.
- **D45 / D48 (QUESTIONABLE).**
  - The preset ladder is a founder decision.
  - The stub modules make the Intensity UI describe processing that does not exist. Either hide Intensity until a
    wet stage ships, or make it the honest "Normalise + limit" switch it currently is.

---

## 3. Lead #3 (limiter) summary

- **True-peak compliance, 48 kHz.** The −1 dBTP and −0.1 dBTP ceilings hold under the BS.1770-style meter and the
  DAC-like reconstruction. The worst miss is +0.15 dB, on pathological Nyquist-emphasised clipped noise.
- **Against an ideal brickwall reconstruction,** crushed masters exceed by 0.9–1.6 dB. This is a definitional
  limit of a 24-tap detector that is −6 dB at fs/2, the same as the BS.1770 reference filter, not a code bug.
- **Look-ahead vs attack.** Detection lag is 12 samples, so there are 132 samples = 2.75 ms = 5.5 τ before the peak
  emerges. The residual is 0.41 % of GR in dB: 0.1 dB at a 25 dB GR step, inside the 0.27 dB margin (measured
  −1.204 dBTP for a +24 dB step).
- **Pumping.** It comes from D34: every over-ceiling event costs about 1 s of recovery.

## 4. Agreement and disagreement with prior evidence

- **Agree** with `verify-sota.md:46` (the limiter works far longer than its frames-over count suggests). D34 is the
  mechanism.
- **Agree** with `review-sota.md` that the meter resets per `playFile`. **Adds:** it does not reset on gapless or
  seek, and the makeup state carries over.
- **Disagree** that the dual release is state of the art (§2.3).
- **Agree** with DUP-16, DSP-07 and DSP-10 (all proven above).

## 5. Repro (scratch `exp-p2-breaker/`)

```
./build.sh                                    # links the real Sources/ + vendored libebur128
./p2harness meter > meter.csv                 # D17/D18/D19 vs libebur128 (11 rates)
./p2harness tpk                               # D31 vs analytic sine truth
./p2harness limiter 48000 0.891 c891 512 && python3 tp_oracle.py c891 0 48000 -1.0022 && python3 tp_more.py
./p2harness limiter 384000 0.891 c891r384 512 && ./ebtp lim_c891r384_step_+24dB_1k.f32 384000
./p2harness release                           # D34
./p2harness blend                             # D50
./p2harness norm 20 ; ./p2harness normE 20    # D20 scenarios (CSV traces norm_*.csv)
./p2harness layout ; ./p2harness spatial      # D70, D46
./p2harness xfeed ; python3 xfeed.py          # D44 vs bs2b
./p2harness ramp ; xcrun clang++ ftz.cpp -o ftz && ./ftz   # D60, D67
cd layout && ./probe *.caf *.m4a *.wav *.flac && ./lvl caf50.caf   # channel-order / 5.0 probes
```

## Sources (opened)

- libebur128 v1.2.6, vendored: `third_party/libebur128/ebur128/ebur128.c`.
- ITU-R BS.775-4 (PDF, Table 2 and Annex 7 §5):
  https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.775-4-202212-I!!PDF-E.pdf
- libbs2b `bs2b.c` / `bs2b.h`:
  https://raw.githubusercontent.com/alexmarsev/libbs2b/master/src/bs2b.c ;
  [bs2b project](https://bs2b.sourceforge.net/) ;
  [FFmpeg af_bs2b](https://ffmpeg.org/doxygen/3.1/af__bs2b_8c.html)
- [Spotify: Loudness normalization](https://support.spotify.com/artists/article/loudness-normalization/)
- [TV Technology: What is downmixing, Part 1 (LoRo)](https://www.tvtechnology.com/opinions/what-is-downmixing-part-1-stereo-loro) ;
  [VLC downmix (ITU-R BS.775 matrix)](https://mailman.videolan.org/pipermail/vlc-devel/2012-February/086333.html)
- The Apple SDK `CoreAudioBaseTypes.h` (tag values and channel orders).
- BS.1770-5: the ITU PDF download was blocked, so libebur128 serves as the opened reference implementation.
