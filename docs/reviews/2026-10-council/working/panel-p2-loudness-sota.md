# Panel P2: state of the art and correctness by reference (loudness, true peak, limiter, crossfeed, spatial, blend)

Panelist: STATE-OF-THE-ART / CORRECTNESS-BY-REFERENCE. Repo `main` @ a206107, read in my own worktree
`.claude/worktrees/panel-p2-sota`. Experiments live in `scratchpad/council/exp-p2-sota/` (`cpp/`, `py/`, `t3341/`, `layout/`,
plus downloaded sources in `dl-*`). Every C++ probe `#include`s or links the real production sources (headers and `.cpp`
files under `Sources/AudioDSP`); only stimuli and oracles are mine. I never launched the app and never played audio.
I formed my verdicts before reading `area-dsp-cpp.md` (DSP-07/08/10) and `duplication.md` (DUP-16). Where I agree,
disagree or add, it is said in §4.

Rows covered: D17–D20, D31–D36, D44–D52, D59, D60, D67–D70 (25 rows).

## 1. Verdict table

| Row | Algorithm | Verdict | Evidence (mine unless stated) | Missing proof |
|---|---|---|---|---|
| D17 | K-weighting | CORRECT-UNPROVEN | At 48 kHz the derived coefficients equal BS.1770-5 Annex 1 Tables 1 and 2 to ≤ 9e-16. They match libebur128's derivation term for term (`ebur128.c:255-283`). On EBU Tech 3341 cases 1–6, 9 and 12, synthesised by me at 48 and 44.1 kHz and run through the real `LufsMeter`, every reading is within 0.04 LU (spec: ±0.1). | No test asserts the coefficients against the Tables. Oracle tests allow ±0.2 LU (`LoudnessOracleTests.inc:36`) and ±0.15 (`LoudnessTests.inc:17`), both looser than Tech 3341's ±0.1. The earlier 0.043 LU RLB bug fit inside that budget. |
| D18 | Gated meter | CORRECT-UNPROVEN | Block, hop, gating and momentary/short-term timing match BS.1770-5 eq. 2–7 and Tech 3341 §2.3. The histogram keeps the exact block energies, which is more accurate than libebur128's bin-centre energies. Tech 3341 cases pass (see D17). Two cosmetic deviations: `>= −70` (`LufsMeter.h:403`) and the bin-centre `>=` (`:456`) where the spec says strict `>` (eq. 6–7); the effect is measure-zero. | Tech 3341 Table 1 cases 1–6, 9, 12 and 13 at ±0.1 LU as a spec oracle. The gate tests allow ±0.3 and ±0.5 LU. |
| D19 | Channel weights / layout decode | **DEFECT** | (a) The back surrounds of 7.1 C get 1.41, but BS.1770-5 Annex 3 Tables 4/5 give M±135 = **1.00** (and libebur128 agrees). (b) The tags AVAudioFile actually reports for common files fall back to weight 1.0 on every channel, **LFE included** (probed). (c) The test pins the wrong value. See P2-4. | A label-driven test against Table 5. |
| D20 | Auto-makeup normaliser | **DEFECT** | The meter integrates over the whole session and is never reset per track. The relative gate then discards a quiet track entirely. Measured with the real module: a −25.2 LUFS track after a −7.7 LUFS track plays with **−8.26 dB** makeup (ideal: +9.24). See P2-2. | A clamp/slew law test (map), a multi-track test, and a reset contract. |
| D31 | 8× true-peak kernel | PROVEN-CORRECT | Tech 3341 TP cases 15–19 (my synthesis): −6.03…−6.06 and +2.94 dBTP, against spec −6.0/+3.0 (+0.2/−0.4). Cases 20–23: −0.10…−0.14 against my 64× reference of −0.11…−0.17. Sine sweep to 20 kHz: worst under-read 0.065 dB (44.1k) and 0.045 dB (48k); worst over-read 0.002 dB. That is better than libebur128's 4×49 filter (0.145 dB under, 0.11 dB over). Local caveats are in §3. | The libebur128 oracle (±0.3 dB) is weaker than the kernel itself. Add Tech 3341 cases 15–23. |
| D32 | Look-ahead limiter core | CORRECT-UNPROVEN | Independent 32× oracle on the real limiter output, including adversarial onsets from rest with 20–30 dB of gain reduction (GR): worst **−1.156 dBTP** (published ceiling −1.0). The one-pole attack converges to 99.6 % within the effective look-ahead of L−12 samples. | The shipped test accepts ceiling **+0.30 dB** (`LimiterTruePeakTests.inc:56`). It proves ≤ −0.70 dBTP, not ≤ −1.0. It has no deep-GR onset-from-rest fixtures and nothing above 48 kHz. |
| D33 | Sliding max (monotonic deque) | CORRECT-UNPROVEN | Fuzzed against brute force over 2 M samples at 44.1/48/96/192/384 kHz: 0 mismatches and no overflow (`cpp/deque_fuzz.cpp`). This is the standard Lemire streaming max. | A direct property test (the code is private; expose it through a seam). |
| D34 | Gain computer + ballistics | **DEFECT** | The "dual-stage release" is dead. With equal attack coefficients, slow ≤ fast holds as an invariant, so `min()` always returns the slow branch. Measured: GR recovers with τ = 500 ms (−7.29 → −1.11 dB after 0.94 s). See P2-1. | Tests of the release τ and the LF hold (map). |
| D35 | Prime + re-seed | CORRECT-UNPROVEN | The replay of the window's ISP values is right (the window maximum equals a continuously run deque, by construction). The envelope restarts at 0 dB. | An equivalence test: re-seeded window-max == continuous window-max at resume. |
| D36 | EQ-only ceiling per transport | PROVEN-CORRECT | Lossless local links get −0.1 dBTP; re-encoding or unknown links get −1 dBTP (the R128 / TD1004 rationale). `Limiter_EqOnlyCeiling` asserts the mapping and the measured ceilings. | — |
| D44 | Crossfeed DSP | PROVEN-CORRECT (against its own equations) | Read-both-then-write-both, one-pole, ITD line, ramp. The tests cover the LPF −3 dB point, separation and bit-exact bypass. The *design* defect is under D45. | — |
| D45 | Crossfeed coefficients / topology | **DEFECT** | It is "bs2b-inspired" but not bs2b. A flat direct path plus an explicit 0.318 ms delay on top of the LPF's own group delay gives an LF ITD of **0.53–0.54 ms** (bs2b: 0.25 ms). Centre (mono) content gets a comb dip: **−4.2 dB (Relaxed) / −4.5 dB ("Bauer") / −6.3 dB (Strong) at ~1 kHz**, measured on the real module; bs2b is smooth at −1.1…−1.8 dB. See P2-3. | A mono (centre) response test across frequency and a libbs2b oracle. |
| D46 | Spatial render N→M | **DEFECT** | A 5.1 file on a stereo device keeps only L and R. C (lead vocal), LFE, Ls and Rs are discarded (`SpatialRenderKernel.cpp:75-91, 172-178`). BS.775-4 Annex 4 Table 2 gives the standard fold-down. See P2-6. | A test for the out < in case. |
| D47 | Device-width format | QUESTIONABLE | Correct to its own spec (M = min(N, device)). The spec silently relies on D46 doing a fold, and maps only 6 → 5.1 A and 8 → 7.1 A. See P2-8. | — |
| D48 | BRIR / Clarity stubs | QUESTIONABLE | They are identity stubs sitting inside the Intensity blend, so Intensity is today a level control plus a normaliser on/off switch (see P2-7 and P2-9). | — |
| D49 | Path selection P0–P3 | PROVEN-CORRECT | Bit-exact P0 and the hysteresis are covered by independent bit-exact tests. Product note: the default Intensity is **0.20** (`AudioViewModel.swift:132`), so default Enhanced playback is never bit-perfect and is always normalised. | A pure `PathSelector` seam (agree with DSP-10). |
| D50 | Equal-power wet/dry blend | **DEFECT** | With wet == dry (both stubs, crossfeed off by default) the output is `sin+cos`: **+2.0 dB at the default 0.20** and +3.0 dB at 0.5. A test pins the +3.01 dB as "expected" (`IntensityTests.inc:263-272`). The claim that "the normaliser absorbs it" does not hold for a session-integrated meter (P2-2). See P2-7. | A power-preservation test on correlated input. |
| D51 | Normaliser contribution fade | PROVEN-CORRECT | `Intensity_Zero_LevelGlide` is a property test (swing ≥ 6 dB, 10–90 % ≥ 1 s, ≤ 0.5 dB per 50 ms). | — |
| D52 | Correlation-compensated crossfade | PROVEN-CORRECT | Processed gain = −ρ·in + √(1 − in²(1 − ρ²)) satisfies Fink, Holters & Zölzer (DAFx-16) eq. (11), w² + 2·w·wᵢ·r + wᵢ² = 1, exactly (derivation in §3). `Kernel_P0Fade_KeepsPower` covers ρ ≈ 0, ρ = cos 65° and ρ ≈ 1. | Cite the paper (non-recoverable rationale). ρ comes from one block (documented). |
| D59 | UI meter bridge | QUESTIONABLE | The TP part is the verified kernel. "Integrated" has **no reset API** (`DeviceBridge.h:94-106`), so the readout is session-long, not per track. It is L/R-only on a >2-channel device (known ENH-002). See P2-10. | — |
| D60 | ParameterRamp | CORRECT-UNPROVEN | α = 1 − e^(−1/(τ·fs)) is exact RC. The float one-pole stalls 0.7–1.4e-4 short of its target (measured). The kernel's 1e-4 epsilon knows this; `LoudnessModule`'s 1e-6 identity epsilon (`.cpp:28`) can never be reached after a move. That is latent today, because the normaliser is always enabled. | A direct τ test. |
| D67 | FlushToZero | PROVEN-CORRECT | Measured on an M4 Pro: FPCR.FZ = 0 gives a double subnormal (0x1p-1023); FZ = 1 flushes **double** and float alike. So `LufsMeter.h:123-128` ("FZ does NOT flush double subnormals") is factually wrong. The manual flush is harmless and still useful on the UI tap thread, which never sets FZ. | — |
| D68 | Non-finite scrub | PROVEN-CORRECT | The exponent-mask max-reduction is exact (all-ones exponent ⇔ non-finite). Several tests cover it. | — |
| D69 | Realizer coalescing | PROVEN-CORRECT | Existing RMW and tsan tests. Not re-derived by me; this row is outside my reference emphasis. | — |
| D70 | Layout-weight parity buffer | **DEFECT** | Re-initialisation seeds the slots from the *stereo* decode, `{1,1,0,0,0,0}` (`LoudnessModule.cpp:70-84`; `ChannelLayout.h:19` zero-initialises). Nothing republishes. Measured with the real module: after `initialize()`, a 6-channel stream's **C, Ls and Rs read −200 LUFS (excluded)**. The buffer also laps on back-to-back publishes, and the publish is not serialised with re-initialisation. See P2-5. | Any test that calls `publishChannelLayout` (map). |

**Counts:** PROVEN-CORRECT 9 · CORRECT-UNPROVEN 6 · DEFECT 7 · QUESTIONABLE 3.

## 2. DEFECT and QUESTIONABLE details

### P2-1 (D34) The limiter's "dual-stage release" is dead code; the real release is a single 500 ms pole. SIGNIFICANT
- **Evidence:**
  - `LimiterModule.h:396-424`. Both branches attack with the same `attackCoeff_`. Release moves fast toward the target with 100 ms and slow with 500 ms, and the output is `min(fast, slow)`.
  - Invariant proof that slow ≤ fast always:
    - They start equal at 0.
    - Attack: new_f − new_s = (1−α)(f − s) ≥ 0.
    - Release with t ≥ f ≥ s: new_f − new_s = (f − s)(1 − r_s) + (r_f − r_s)(t − f) ≥ 0.
    - Release with s ≤ t < f: both converge on t from opposite sides.
    - Hold: both freeze.
    - So the output is always the slow branch.
  - Probe on the real header (`cpp/limiter_probe.cpp`): one 5 ms burst at +6 dBFS on a −10 dBFS sine. GR −7.29 dB, then −5.49 at +0.14 s, −3.01 at +0.44 s, −1.11 at +0.94 s and −0.15 at +1.94 s, which is τ = 500 ms.
  - The Sprint-4 plan (§M3 item 4, table row "Release ballistics") and the retro (`04-...-retro.md:37`) claim the dual release shipped.
- **Root cause:** the "deeper wins" combiner only works when the slow branch also *attacks* slowly, so that a transient drives the fast branch deep while the slow one integrates sustained GR. Here the branches differ only in release, so the deeper one is always the slow one. No test measures the release τ.
- **Why it matters:** an isolated transient (a snare hit, or a +12 dB boosted quiet master; see P2-2) ducks the music for 1–2 s. That is the audible "hole" that program-dependent release exists to avoid. Giannoulis, Massberg & Reiss 2012 (cited in the code) recommend the log-domain smoothed detector after the gain computer, which the code does correctly. The fast/slow construction is not from that paper.
- **Remedy (pick one, then test the release τ and the LF hold):**
  - (a) Give the slow branch a slow attack (≈ 50–150 ms), so transients release on the fast branch and sustained GR on the slow one. This is the usual program-dependent release.
  - (b) Delete the fast branch and document a single release.
  - (c) Go state of the art: hold for the look-ahead window plus a box/FIR or cascaded-one-pole smoother that reaches the target exactly at the peak. Examples: Sanfilippo's cascaded smoothers, [LimiterClass](https://github.com/dariosanfilippo/LimiterClass); the plan's own "BoxStackFilter" option (`04-...-plan.md:104`). It also removes the 0.27 dB working margin.
- **Effort / risk:** S for (a) or (b); M for (c). Low risk: the golden master needs a deliberate re-baseline.

### P2-2 (D20) The normaliser is session-integrated: it neither normalises per track nor per album, and it gates quiet tracks out. SIGNIFICANT (root cause STRUCTURAL)
- **Evidence:**
  - `LoudnessModule` never resets `meter_` except in `initialize()`, which only re-allocation calls (`AUAudioUnit.mm:152-171` → `Realizer.mm:341-361`). There is no track-change hook. `updateMakeupGain` (`LoudnessModule.cpp:264-287`) uses the session's gated integral.
  - Probe on the real module (`cpp/normaliser_probe.cpp`), tracks A, B, C of 150 s each:
    - A at −7.73 LUFS → makeup −8.27 dB (correct).
    - B at −25.24 LUFS → makeup stays **−8.26 dB**. B lies more than 10 LU below the session integral, so the relative gate drops every one of its blocks, and B plays at about −33.5 LUFS instead of −16.
    - C → −8.26 dB.
  - At session start the gain slews from 0 dB at 1 dB/s, so a loud first track audibly fades down about 8 dB over about 8 s. The same happens after every re-allocation (DSP-07).
  - Positive makeup reaches +12 dB (`LoudnessModule.h:49-50`) into the −1 dBTP limiter. P2-1's 500 ms release makes that pump.
- **Reference check:**
  - Every reference player computes one *constant* gain per track or album ahead of time, and caps positive gain by peak headroom:
    - **Roon:** "multiplied by a constant gain value"; positive gain is reduced using the analysed true peak; Track / Album / Auto modes; default target −14 LUFS ([Roon KB](https://help.roonlabs.com/portal/en/kb/articles/volume-leveling)).
    - **ReplayGain** (foobar2000): pre-scanned track and album gain; "apply gain and prevent clipping according to peak" ([RG player spec](https://replaygain.hydrogenaudio.org/player.html), [foo_dsp_replaygain](https://www.foobar2000.org/components/view/foo_dsp_replaygain)).
    - **Spotify:** pre-computed, −14 LUFS. In Normal mode positive gain is capped at −1 dBTP; only Loud mode (−11) uses a limiter (5 ms attack / 100 ms decay) ([Spotify](https://support.spotify.com/artists/article/loudness-normalization/)).
    - **Audirvana:** a stored per-album or per-track R128 value, with "preserve album dynamics" ([Audirvana help](https://help.audirvana.com/en/support/solutions/articles/202000050819)).
    - **Apple Music Sound Check:** −16 LUFS, one uniform per-track gain, according to secondary sources only. I could not open an Apple document.
  - The standards bodies prefer album or anchor normalisation:
    - EBU R 128 s2 (2023) §i (opened): "album normalisation", "anchor-based normalisation".
    - AES TD1008 (now AES77): −16 LUFS for track mode and −14 for loudest-track album mode, "minimise additional processing like limiting" ([summary](https://productionadvice.co.uk/td1008/); I could not open the AES PDF).
  - The plan intended per-track behaviour ("boosting a quiet track toward −14 LUFS", the "Spotify/Apple Music model", `04-...-plan.md:59`).
- **Root cause:** a live, causal AGC was built when the product already has full-track analysis: the `TrackLoudnessProfiler` / analyser (D21–D29) computes gated per-track loudness for the EQ's loudness-neutral gain. That makes two loudness systems with different scopes. Nothing defines what "the measurement interval" is.
- **Remedy:**
  - Drive the normaliser from the track analysis: gain = target − I_track, or I_album by playback context (Roon "Auto"). Apply it as a constant per track, swapped at the gapless seam. The seam group-gain logic already exists in `TrackLoudnessGain::resolveSeam`.
  - Cap positive gain at (ceiling − TP_track). This needs a true peak from the analyser; `TruePeakKernel` is reusable.
  - Keep the causal meter only as a per-track fallback, reset at each track start.
  - Read existing `REPLAYGAIN_*` / `R128_*` tags.
  - Founder decisions, recommendation first:
    - (A) Album / Auto mode with peak-capped boost and no limiting in normal mode; the "faithful" choice.
    - (B) Today's +12 dB plus limiter, as an opt-in "Loud" mode.
- **Effort / risk:** M (the analyser exists; add TP, album aggregation and persistence). Medium risk: it changes what users hear, and that change is the point.

### P2-3 (D45) The crossfeed notches centre content by 4–6 dB around 1 kHz: an ITD counted twice, and no direct-path compensation. SIGNIFICANT
- **Evidence:**
  - `CrossfeedModule.cpp:95-120`, `Realizer.mm:39-41, 74-117`: Lout = gD·L + gC·LPF(z^−D·R) with D = round(0.0003178·fs) = 15 samples at 48 kHz.
  - libbs2b (opened, `bs2b.c:133-214`) has **no delay line**. Its ~0.25 ms ITD comes from the cross low-pass's group delay against a first-order **high-boost shelf on the direct path** (`a0_hi`, `a1_hi`, `b1_hi`), which also keeps the mono sum smooth.
  - Response comparison, my model (`py/crossfeed_cmp.py`) confirmed on the real module (`cpp/crossfeed_probe.cpp`), mono input:

    | | 500 Hz | 1 kHz | 2 kHz | 10 kHz |
    |---|---|---|---|---|
    | App Relaxed | −2.29 | −4.19 | −2.17 | −2.52 |
    | App Strong | −2.86 | **−6.28** | −2.99 | −3.54 |
    | bs2b Jmeier | | −0.90 | | −1.06 (smooth) |
    | bs2b Cmoy | | −1.19 | | −1.48 |

  - ITD at 100 Hz: app 0.525–0.541 ms; bs2b 0.25–0.26 ms (≈ ±30° loudspeakers).
  - The presets match bs2b's Jmeier (650 Hz / 9.5 dB) and Cmoy (700 Hz / 6.0 dB). "Bauer" (700 Hz / 9.0 dB) matches no bs2b level; bs2b's Default is 700 Hz / 4.5 dB, the *strongest* of the three.
  - `Crossfeed_Mono_LevelNeutral` probes only 60 Hz, and its comment calls the high-frequency loss "benign" (`CrossfeedTests.inc:211-222`).
- **Root cause:** a delay-line ITD was layered onto a filter topology whose LPF already supplies most of the ITD, and the direct path was left flat. It was "inspired by" bs2b rather than checked against bs2b's response.
- **Remedy:**
  - Implement bs2b's actual structure (MIT; two one-poles per channel), or Meier's crossfeed. Drop the explicit delay, or cut it to (target ITD − LPF group delay).
  - Ladder: Relaxed = Jmeier (650 / 9.5), Default = Cmoy (700 / 6.0), Strong = bs2b Default (700 / 4.5). This answers the AC-3 worry that a 0.596 α "inverts the ladder": bs2b Default *is* the strongest rung.
  - Gate it with a vendored libbs2b oracle (as with libebur128), plus centre-response tests from 100 Hz to 10 kHz and an ITD test.
- **Effort / risk:** S–M; low risk (opt-in feature, headphones only).

### P2-4 (D19) BS.1770 channel weights: wrong for 7.1 back surrounds; common real-world tags fall back to "LFE = 1". LOCAL to SIGNIFICANT
- **Evidence:**
  1. **7.1 C back surrounds.** BS.1770-5 Annex 3 Table 4 (opened) gives G = 1.41 only for 60° ≤ |θ| ≤ 120°. Table 5 lists M±135 = 1.00 for 0+7+0. The code gives Rls/Rrs (which its own constants place at ±135°) **1.41** (`ChannelLayoutDecoder.cpp:234-235`). libebur128 weights Mp135 at 1.0 (`ebur128.c:737-743`). `MultichannelTests.inc:1466-1476` **pins** the wrong value. The code also cites "Annex 1 Table 1" for the weights; in BS.1770-5 Table 1 is the stage-1 filter, and the weights are Table 3 (5.1) and Tables 4/5.
  2. **Fallbacks on real files.** Files made with `afconvert` (`layout/`) and read through `AVAudioFile` report:
     - plain 6-channel WAV → `DiscreteInOrder|6` (0x00930006);
     - ALAC 5.1 .m4a → `MPEG_5_1_D` / AAC_5_1, "C L R Ls Rs LFE" (0x007C0006);
     - FLAC 7.1 → `WAVE_7_1` (0x00BD0008).

     `resolveSourceLayoutTag` passes the file's tag through (`AudioEngineBridge+ChannelLayout.swift:41-43`). The decoder handles only 5.1 A/B and 7.1 A/C, so these fall back to all 1.0 (`:126-138`). Measured with the real module (`cpp/layout_probe.cpp`): for 5_1_D and DiscreteInOrder **the LFE channel counts at weight 1 (−26.0 LUFS) and the surrounds lose their +1.5 dB**. BS.1770 excludes LFE; EBU Tech 3341 §2.10 says that if LFE were included it would need +10 dB.
  3. 7.1 A labels Lc/Rc as ±60° (`:56-57`), but CoreAudio's Lc/Rc is "left/right centre", between L and C. Under Table 4, ±60° would mean 1.41. The weight (1.0) is right; the azimuth used by the future BRIR is not.
- **Root cause:** four hand-written per-tag tables instead of the standard's position rule applied to channel *labels*.
- **Remedy:** expand any tag via `kAudioFormatProperty_ChannelLayoutForTag` / `AVAudioChannelLayout` channel descriptions, map each `kAudioChannelLabel_*` to (azimuth, elevation, isLFE), and apply Table 4 (LFE → 0). Test against Table 5. This fixes every tag, bitmap and description layout at once.
- **Effort / risk:** S; low.

### P2-5 (D70, refines DSP-07) After any re-allocation the audible normaliser is deaf to centre and surrounds. SIGNIFICANT
- **Evidence:**
  - `LoudnessModule::initialize` seeds both parity slots from `decodeChannelLayout(Stereo)`, whose `lufsWeight` is `{1,1,0,0,0,0,0,0}` (`ChannelLayout.h:19` zero-initialises; `ChannelLayoutDecoder.cpp:149-156`). Nothing republishes after `reinitializeOnQueue` (`Realizer.mm:341-361`).
  - Probe (`cpp/layout_probe.cpp`), −23 dBFS 1 kHz in one channel of a 6-channel stream:
    - after `initialize()`: L and R −26.0; **C, Ls and Rs −200 (excluded)**;
    - with MPEG_5_1_A published: correct (C −26.0, Ls/Rs −24.5, LFE excluded).
  - This differs from the `CausalLoudnessTap` default, `{1,…,1}` (`CausalLoudnessTap.h:133`): two default policies for one datum.
  - The two-slot parity buffer laps when two publishes land during one worker copy.
  - `publishChannelLayoutTag` reaches `_kernel->publishChannelLayout` without going through the Realizer (`AUAudioUnit.mm:231-236`), while `DSPKernel::initialize` replaces `loudnessModule_` on the Realizer queue (`DSPKernel.cpp:62-76, 110-121`). That leaves a use-after-free window by construction; I did not reproduce it.
- **Root cause:** the source channel layout is not part of the Realizer's canonical state (DSP-07).
- **Remedy:** follow DSP-07: a Realizer intent, re-applied on re-initialisation, delivered through `DoubleBufferSnapshot` or `TargetState`, with the parity buffer deleted. Also make the "unknown layout" default one rule, BS.1770 by labels (P2-4).
- **Effort / risk:** M; medium risk (shared with DSP-07).

### P2-6 (D46) N > M truncation drops C, LFE and surrounds. And any real fold-down will break the ceiling, because the limiter is not last. SIGNIFICANT (second part STRUCTURAL)
- **Evidence:**
  - Truncation: `SpatialRenderKernel.cpp:75-91, 172-178`; reachable through `deviceWidthFormat` (M = min(N, device)) for any 5.1 file on a stereo output.
  - BS.775-4 Annex 4 Table 2 (opened): Lo = L + 0.7071·C + 0.7071·Ls; Ro = R + 0.7071·C + 0.7071·Rs. On LFE: "often not included in a 2-channel down-mix" (BS.775-4 LFE section, opened).
  - The graph is player → effects AU (EQ … **limiter**) → spatial AU (N→M) → mixer. A Table 2 fold-down can reach 1 + 0.707 + 0.707 = 2.414× (+7.7 dB) *after* the −1 dBTP limiter, and the S18 HRIR sum will too.
- **Founder rule ("no naive downmix"), weighed:**
  - Truncation is the most naive option of all.
  - BS.775 is the standardised fold-down that every reference decoder implements (swresample, foobar2000, ATSC A/52 LoRo).
  - The rule's real goal is to process at N and render once, at the device boundary. A BS.775 matrix in the spatial stage satisfies that, and S18's binaural renderer replaces it in the same slot.
- **Remedy:**
  - Interim: a BS.775 Table 2 matrix in the spatial kernel, LFE omitted (optionally at −10 dB), for 5.1/7.1 → 2 and 7.1 → 5.1.
  - Make the true-peak limiter the **last** stage after the N→M render, or add a second ceiling stage after it. Otherwise the matrix needs worst-case normalisation (−7.7 dB, audibly quieter).
  - The state-of-the-art endpoint for headphones is HRTF/BRIR binaural (SADIE II via libmysofa plus partitioned convolution). Cost: L, already planned for S18.
- **Effort / risk:** S–M for the matrix plus tests. M for moving the limiter: the chain order and the P0 crossfade are involved.

### P2-7 (D50, agrees with DSP-10) The Intensity blend is a +0…+3 dB level control on today's chain. SIGNIFICANT
- **Evidence:**
  - Wet and dry are identical because the Clarity/BRIR stubs are identity and crossfeed is off by default (`DSPKernel.cpp:399-407`). `runBlendPath` applies `sin + cos` (`:271-292`). At the default 0.20 that is +2.01 dB; at 0.5 it is +3.01 dB.
  - The comment's "the normaliser downstream absorbs" assumes a responsive meter. A session-integrated meter (P2-2) barely moves after the first minutes, so the bump persists.
  - `Intensity_EqualPowerAtHalf` asserts the +3.01 dB as correct, a test that mirrors the implementation's law.
  - Even with crossfeed on, wet and dry are highly correlated (crossfeed is mostly the dry signal).
- **Reference:** Fink, Holters & Zölzer, "Signal-Matched Power-Complementary Cross-Fading and Dry-Wet Mixing", DAFx-16, §4 (opened). Equal power is right only for r = 0; for dry/wet mixing the gains should be derived from the measured correlation. The same file already implements that law for P0 (D52).
- **Remedy:** reuse the D52 law for the blend, with ρ tracked per block and smoothed. While the wet chain is identity, use equal gain. Re-write the test as "power within ±0.5 dB for correlated and for uncorrelated wet".
- **Effort / risk:** S. Low risk; the golden master needs a deliberate re-baseline.

### P2-8 (D47) Device-width mapping. QUESTIONABLE
- M = min(N, device) and 6/8 → MPEG 5.1 A / 7.1 A are correct to their own rules.
- But the result depends on D46 folding, and it never consults the device's preferred channel layout (`kAudioDevicePropertyPreferredChannelLayout`).
- An 8-channel 7.1 C file on a 5.1 device truncates Rls/Rrs. A 4-channel device keeps N = 6.
- **Remedy:** fold with the D46 matrix toward the device's preferred layout. Effort S once P2-6 lands.

### P2-9 (D48) Placeholder stages make "Reimagine Intensity" mean something other than its label. QUESTIONABLE
- With the stubs, Intensity does three things:
  - 0 → bit-perfect / EQ-only;
  - 0 → 0.1 → the normaliser fades in (up to −20 / +12 dB);
  - 0.1 → 1 → a 0…+3 dB hump and nothing else (crossfeed off).
- This is a product-honesty question for the founder. Recommendation: (A) agree with DSP-10, remove the stubs from the RT path and hide or relabel Intensity until a wet stage exists.

### P2-10 (D59) UI "Integrated" is session-long. QUESTIONABLE
- The meter bridge has no reset (`DeviceBridge.h:94-106`), so "Integrated" covers everything since the engine was initialised, which is not what a Now Playing readout implies.
- Tech 3341 §2.3 lets the user define the measurement interval with start / pause / reset. Pick one explicitly: per track (reset at the track or gapless seam) is the recommendation.
- The stereo-only limitation is known (ENH-002) and not re-reported.

## 3. Local notes (they do not change verdicts)
- **D31, sub-sample peaks.** The prototype is 192 taps (centre 95.5), so no phase evaluates the sample instants (the grid is offset by 1/16 sample). On Tech 3341 case 15 (fs/4, phase 0) TP reads **−6.062 against a sample peak of −6.021**: a "true peak" below the sample peak, by up to 20·log₁₀(cos(π·f/fs/8)). This is within spec (−0.4), but a meter should never read below |x[n]|.
  - Fix: `max(|x[n]|, ISP)` (one compare), or a 193-tap prototype with an integer centre.
  - The header claims "Kaiser β=8 ≈ −98 dB stopband". The filter's image rejection is in fact −21 dB at 0.55·fs, −62 dB at 0.6·fs and ≤ −86 dB beyond about 0.65·fs. Passband −0.1 dB at 0.42·fs, −0.98 dB at 0.4535·fs. The under-read stays small because image and droop partly offset each other on steady tones.
- **D32.** The look-ahead is capped at 576 frames, which is 1.5 ms at 384 kHz (one-pole convergence about 95 %). This is latent: the Enhanced graph is fixed at 48 kHz (`+Reconfigure.swift:103-106`), so I agree with DUP-16 that it is not live today.
- **D35.** Seed the envelope at `targetGrDb(windowMax)` rather than 0 dB, to remove the attack lag at resume. A trivial change.
- **D52, derivation.** With a = −ρb + √(1 − b²(1−ρ²)): a² + 2abρ + b² = (a + ρb)² + b²(1 − ρ²) = 1. a ≥ 0 and a is monotonically non-increasing in b for ρ ∈ [0, 1]. The endpoints are exact for ρ ≥ 0.
- **D67.** The comment at `LufsMeter.h:123-128` is false on Apple Silicon (probe `cpp/fz2.cpp`). Keep the manual flush (the UI tap thread has no FZ) but correct the rationale. This also resolves map fact 1: `EQ_NoSubnormalStates` is consistent with FZ flushing doubles.

## 4. Agreement with earlier reviews
- **DSP-07: agree, with a correction.** It says that after a device change the meter weights "LFE 1, surrounds 1.0". That is true only of `CausalLoudnessTap`. The *audible* `LoudnessModule` gets `{1,1,0,0,0,0}` and excludes C and the surrounds entirely (measured, P2-5). That is worse for vocal-centred 5.1.
- **DSP-08: agree.** Added: the limiter-before-render ordering makes any fold or binaural sum break the −1 dBTP guarantee (P2-6).
- **DSP-10 item 4: agree**, and I supply the literature basis (Fink et al. 2016) plus the evidence that the pinning test mirrors the implementation.
- **DUP-16: agree, latent.** The Enhanced graph runs at 48 kHz only. Once the founder picks a supported-rate domain, it must hold for the loudness profiler, the limiter cap and the crossfeed line (64 frames, ≤ 192 kHz).
- **New in this panel:** P2-1 (dead release branch), the P2-2 session-integration and gating behaviour, P2-3 (crossfeed comb), P2-4 (BS.1770 Table 4/5 error and real-tag fallbacks), and the local notes on D31 and D67. None of them appears in `docs/design/eq-lens/evidence/*`, the Sprint-4 retro or `area-dsp-cpp.md`.

## 5. Top missing proofs (by value)
1. EBU Tech 3341 Table 1 cases 1–23 as a spec oracle at ±0.1 LU and +0.2/−0.4 dBTP, for 44.1 and 48 kHz (my synthesiser: `py/gen_t3341.py`), plus Tech 3342 for LRA if LRA is ever shown.
2. Limiter release τ and LF-hold tests; a ceiling test at +0.0 dB margin with a 32× oracle and onset-from-rest deep-GR fixtures.
3. A multi-track normaliser test (track change, gating, slew/clamp law).
4. A crossfeed centre-response test plus a libbs2b oracle.
5. BS.1770 Table 5 label-driven weight tests, plus a re-allocation test that asserts the weights survive.
6. A downmix test for 5.1/7.1 → 2 (BS.775 Table 2) and an output TP ≤ ceiling *after* the spatial stage.

## 6. Sources opened
- ITU-R BS.1770-5 (11/2023), [PDF](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf): Annex 1 Tables 1–3, eq. 2–7; Annex 2 and its Attachment (under-read table: 8× gives 0.136 dB at f = 0.45 and 0.169 dB at 0.5); Annex 3 Tables 4–5.
- ITU-R BS.775-4 (12/2022), [PDF](https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.775-4-202212-I!!PDF-E.pdf): Annex 4 Table 2; the LFE section.
- EBU Tech 3341 (2023), [PDF](https://tech.ebu.ch/docs/tech/tech3341.pdf): Table 1 and §2.10. EBU R 128 (2023), [PDF](https://tech.ebu.ch/docs/r/r128.pdf). EBU R 128 s2 (2023), [PDF](https://tech.ebu.ch/docs/r/r128s2.pdf), §g–l.
- libebur128 v1.2.6 (vendored, `third_party/libebur128/ebur128/ebur128.c`); libbs2b, [bs2b.c / bs2b.h](https://github.com/alexmarsev/libbs2b).
- Fink, Holters & Zölzer, DAFx-16, [PDF](https://www.hsu-hh.de/ant/wp-content/uploads/sites/699/2017/10/Fink-Holters-Z%C3%B6lzer-2016-Signal-matched-power-complementary-cross-fading-and-dry-wet-mixing.pdf).
- Giannoulis, Massberg & Reiss, JAES 60(6) 2012 ([AES e-library abstract](https://aes2.org/publications/elibrary-page/?id=16354); full text is paywalled).
- Player practice: [Roon Volume Leveling](https://help.roonlabs.com/portal/en/kb/articles/volume-leveling), [Spotify loudness normalization](https://support.spotify.com/artists/article/loudness-normalization/), [ReplayGain player requirements](https://replaygain.hydrogenaud.io/player.html), [foo_dsp_replaygain](https://www.foobar2000.org/components/view/foo_dsp_replaygain), [Audirvana volume settings](https://help.audirvana.com/en/support/solutions/articles/202000050819), [AES TD1008 summary (Production Advice)](https://productionadvice.co.uk/td1008/), [Sanfilippo LimiterClass](https://github.com/dariosanfilippo/LimiterClass).
- Not opened: the Hydrogenaudio RG2 specification (behind Cloudflare), the AES TD1008 PDF (paywalled) and any Apple Sound Check document. Claims about these are marked as secondary.
