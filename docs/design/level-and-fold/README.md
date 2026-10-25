# Level and fold — the R1.1-B sound design note

*Step 1 of the full loop (`docs/sprints/00-sprint-model.md` §5) for the sprint's sound lanes, written before their code, for the blind three-reviewer panel. Drafted 2026-10-26 against `r1.1b/level-and-fold-design` @ da728c00. Code claims cite file:line on that commit. Standards and implementations cited were opened this session (list at the end). **Measured** = a prototype run this session on synthetic material (scripts: §13); **(from DSP principle)** = reasoning, not measurement; **unverified** = not checked. The only founder decisions named here are the ones in [the sprint record](../../sprints/r1-1b-record.md) ("Decisions at the gates"). The roadmap's sound plan is cited as the plan of record. Everything else here is a proposal.*

**Scope.** This note covers the one analysis pass, leveling's gain, the cap and the peak-safe turn-down, Compare, the old leveller's deletion (lane 1), and the interim fold's arithmetic and LFE rule (lane 2), plus the app-side contract they need (lane 3). Pure is out of scope: leveling in Pure is deferred until the USB DAC (record, decision 1). So the analysis does not run in Pure this sprint.

## 0. The answers, and what changes from the plan

| Q | Answer (one line) |
|---|---|
| **P1** | Measure every true peak **on the engine-rate signal, after the engine's own Mastering converter**. Use the shipped 8× kernel, take the max over all N channels (LFE included), and measure the fold at three LFE gains. At the source rate the reading misses by +0.53 dB on clipped 44.1 kHz masters and over-states hi-res files by up to 4.6 dB (measured). Extra cost: 110× real time for 44.1 kHz stereo and 6× for 192 kHz × 8. |
| **P2** | **Pool the album's gated blocks** (BS.1770 on the concatenation). This is the ReplayGain 2.0 definition and what rsgain/libebur128 compute. A duration-weighted power average differs by up to 2.8 LU (measured). The payload is a sparse 0.1 LU histogram with exact energy sums: 0.9 KB median per track, pooling error ≤ 0.005 LU. Album peak = the max of the tracks' peaks. |
| **P3** | **No.** The trim stays `min(0, C_work − TP_fold)`, a per-track constant independent of g and G. The **level stage** protects `P = max(TP_N, TP_fold + trim)` and levels `L_fold + trim`, so both nets close with one owner of level. A continuous gapless group keeps one trim: the group's worst TP_fold. |
| **P4** | Zero-lag ρ **fails** on a plain low-passed copy (ρ₀ = −0.64, measured). Use one global least-squares FIR per main channel instead. Omit when ≥ 40 % of active blocks are ≥ 80 % explained. Include when ≥ 50 % carry unexplained LFE power within 12 dB of the mains' low band. Omit otherwise, and omit when unknown. Margins ≥ 0.4 on every clean case. Proposed include gain **−6 dB per side** (BS.775-4 Annex 7 Fig. 5), not 0 dB. |
| **P5** | Nothing automatic moves inside a track: g, P, C_work and the trim freeze at audibility. −ΔL refines as today. A listener's mode change glides at τ = 0.15 s. An unknown TP counts as 0 dBTP (the RG2 rule). The arithmetic closes **exactly** with the EQ Off. With the EQ On it closes **only as far as `TP + B` bounds the EQ'd peak**. That is a heuristic, measured to fail by up to +1.07 dB on a phase-coherent synthetic bass. |
| **P6** | Compare = the identity cascade at `g + T`. It matches EQ-on to within the predictor's error. On a folded file the profile must be built **on the fold**: the 5.1-weighted profile misses by up to 0.22 dB (measured). `sizeof(TargetState)` stays **768 B** (measured: 744 → 732 used bytes, `alignas(64)`). The stereo golden master should hold bit for bit. |

**Findings that change the plan** (each detailed below):
- (a) Source-rate true peaks cannot close the cap (P1).
- (b) The architecture's zero-lag LFE rule would include every film-style copy and double the bass by about +5.6 dB (P4).
- (c) BS.775-4 has **no 7.1 row** (P3, S1b).
- (d) The folded loudness can read **2.75 LU above** the 5.1 figure, not only 1–2 LU under. An included LFE moves it by up to +5.8 LU (§1.2).
- (e) The `TP + B` "bound" is not a bound (P5).
- (f) The −ΔL profile must follow the fold (P6).
- (g) MPD's and foobar2000's "auto" pick track gain by shuffle state, not by the neighbour rule the architecture attributes to them (§12, Q11).

## 1. The model in one page

### 1.1 Symbols

- C = the output's ceiling by scope: −0.1 dBTP lossless at the engine rate, else −1 dBTP (roadmap sound plan §1).
- **C_work = 20·log10(ceiling_lin × kIspSafetyMargin) − ε**, with `kIspSafetyMargin` = 0.96939 (`Limiting/LimiterModule.h:105`). ε = 0.01 dB is a new rounding guard: the limiter acts only when `peak > workingCeiling` (`LimiterModule.h:440`), and the cap targets that reading itself. This gives −1.272 dBTP on Bluetooth (0.891, `include/AudioConstants.h:16`) and −0.372 dBTP wired.
- L_T = −18 LUFS.
- B = max_f of the EQ program's played response (≥ 0).
- ΔL = the taste layer's predicted loudness change (`Loudness/TrackLoudnessProfile.h:123-135`).
- The **processed-path ceiling** is the one P1 actually plays: `max(truePeakCeiling, eqOnlyCeiling)` (`DSPKernel.cpp:257-259`). With Intensity held at 0 that is the only processed path.

### 1.2 Per track: the numbers (one pass, off the audio thread)

| Number | Definition | Signal | Persisted |
|---|---|---|---|
| L_N | BS.1770-5 gated loudness, N-channel weights (L/R/C 1, surrounds 1.41, LFE 0 — BS.1770-5 Table 3) | engine-rate stream | yes |
| TP_N | 8× `TruePeakKernel` (`include/TruePeakKernel.h`), max over **all N** channels incl. LFE (the linked limiter, `LimiterModule.h:268-271`) | engine-rate stream | yes |
| L_F[k], TP_F[k] | the same on the BS.775 stereo fold with LFE gain k ∈ {0, 0.5, 1.0} per side | engine-rate stream, folded | yes (N > 2) |
| head, tail | loudness of the first / last whole 400 ms block (N-channel weights) | engine-rate stream | yes |
| histograms | 0.1 LU block histogram, count + exact energy sum per bin (LufsMeter's own form, `Loudness/LufsMeter.h:93-97, 453-460`), N-channel plus each fold variant | engine-rate stream | yes (sparse) |
| LFE stats | §5 | engine-rate stream | yes |
| profile | gated 1/24-octave block spectra for −ΔL (today's) | **source rate**, basis per §7 | no (memory cache, as today) |

**Measured, why each fold variant is kept** (p6_foldloud, 10 s pink fixtures, 48 kHz):

| Fixture | L_F(omit) − L_N | L_F(0.5) − L_F(omit) | L_F(1.0) − L_F(omit) |
|---|---|---|---|
| uncorrelated, equal in all 5 mains | −1.62 LU | 0 | 0 |
| uncorrelated, surrounds −6 dB | −0.58 LU | 0 | 0 |
| centre-only vocal | −0.04 LU | 0 | 0 |
| vocal equal in L, R and C (divergence) | **+2.75 LU** | 0 | 0 |
| strong LFE sub (−20 dBFS rms) | −0.85 LU | +0.73 LU | +2.39 LU |
| film-level LFE (−14 dBFS rms) | −0.83 LU | +2.29 LU | +5.81 LU |

EBU Tech 3343-2023 §7.1 predicts the sign change: the BS.1770 surround weight (+1.5 dB) against the −3 dB downmix coefficient, and up to 3 LU more loudness with divergence. Its remedy is the one adopted here: "a subsequent loudness measurement and potential static gain correction". The architecture's "leveling is unaffected [by the LFE] — BS.1770 weights the LFE 0" (`architecture.md` §7) holds for L_N but **not** for L_F. An included LFE is part of the folded stereo.

### 1.3 Per play: the plan (one pure function, computed off the audio thread)

The plan depends on the output's fold state (fold ⇔ N > 2 and M < N) and on C_work. Track scope uses the track's numbers. Album/group scope uses the pooled loudness (§3) and the **max** of the members' peaks.

```
unfolded:  P = TP_N                                  L = L_N            trim = 0
folded:    trim = min(0, C_work − TP_F[k])           (k = the decided LFE gain; group: max TP_F over the group)
           P = max(TP_N, TP_F[k] + trim)             L = L_F[k] + trim
level:     g = min(L_T − L, C_work − P)              (Leveling Off: g = 0.  Unknown loudness: g = −5 dB.  Unknown TP: 0 dBTP, §6)
turn-down: C_cap = C_work − (P + g + B)              G = min(−ΔL, C_cap)       T = G − (−ΔL) ≤ 0
applied:   effects unit  eq.outputGainDb = g + G     (Compare held: identity cascade at g + T)
           spatial unit  fold matrix · LFE gain k · trim, then the backstop at the same C
```

**Where each is computed and applied.**
- g, C_cap, G and T: in `TrackLoudnessGain` (`Loudness/TrackLoudnessGain.h`) on the Realizer's queue. They are added **outside** the `ownGainDb` early return (`TrackLoudnessGain.cpp:104-121`) and published in `eq.outputGainDb` (`include/TargetState.h:32-33`), as today. So with the EQ Off, g alone takes the kernel off P0, correctly.
- The trim: in the spatial unit, from the same inputs through one pure function, `foldTrimDb` (S1b).
- The numbers L, TP and the LFE gain come from the app through S3. The app resolves the scope; the engine resolves the fold state and C_work. No ceiling rule exists in Swift.

### 1.4 What may change inside a track

| Quantity | Automatic change inside a track | Listener's act |
|---|---|---|
| g, P, C_work, trim | **never** — frozen at audibility (`trackBecameAudible` → `setCurrentTrack`); a later publish for the playing token is kept for its next play | Leveling mode change: at once, one-pole τ = 0.15 s (reuse `kRefreshRampSeconds`) |
| −ΔL (so G, T) | as today: prior → prefix 0.5 s, prefix → whole 2 s, causal fallback ≤ 1 dB/s (`TrackLoudnessGain.h:17-24`) | EQ edits, Compare |
| fold state | an output change folds or unfolds at its re-establish; the trim engages **at once** (protection); g re-plans at the next track | (the output change is the act) |
| ceiling | US-R1F-10 item 6: re-caps at the next track start | — |

## 2. P1 — the pass and the true peak

**The kernel is accurate. The question is which signal it reads.**

*The kernel itself* (p1_kernel, against an exact FFT-sinc reference):
- It never over-reads: no reading came out above the exact reference (largest difference +0.000 dB, i.e. rounding).
- It under-reads band-limited pulses by at most 0.11 dB at 44.1 kHz and 0.04 dB at 48 kHz.
- BS.1770-5 Annex 2 Attachment 1 gives 0.136 / 0.169 dB for 8× at f_norm 0.45 / 0.5.
- Its worst phase droops to −2.0 dB for a 20 kHz tone at 44.1 kHz, against −0.14 dB at 48 kHz.

*Source rate vs the limiter's view* (p1_rate, n = 18 synthetic clipped masters per rate; the SRC is a Kaiser-14 polyphase stand-in for Apple's Mastering converter, **unverified** equivalence):

| Source | R_limiter(48 k after SRC) − R_analysis(source rate) |
|---|---|
| 44.1 kHz, clipped at −0.1 dBFS | **+0.02 … +0.53 dB** (median +0.23) |
| 88.2 / 96 / 192 kHz, ultrasonic noise at −40 dB | −0.94 … −4.64 dB (the source rate over-states) |

Clipping writes energy up to Nyquist. The 44.1 kHz kernel cannot reconstruct it: on these masters it reads up to 0.81 dB under the exact TP. The converter then removes 21–22 kHz content and lifts the peak the limiter sees. Neither error is bounded by the detector's 0.17 dB, and the first is larger than the whole 0.27 dB working margin.

**Decision.**
- Decode once at the source rate.
- Feed the existing profiler at the source rate, unchanged.
- Convert the stream with the engine's own `StreamingResampler` (`AudioFormatKit/StreamingResampler.swift:39, 57-64`) to the engine rate. Today that is 48 kHz on every graph edge (`architecture.md` §2.5). A 48 kHz source passes bit-exact.
- Measure every peak, histogram and LFE statistic on that stream. Record `peakRateHz` so the Engine sprint (engine at the device rate) knows what was measured.

The remaining difference comes from the engine converter's start state across a same-format gapless seam (C-22). It is bounded by a few milliseconds of filter history (from DSP principle).

**Cost** (measured on this machine, an M4 Pro; the M1 Pro floor is slower by an unmeasured factor):
- Apple Mastering at max quality: 110× real time (44.1 kHz × 2), 32× (44.1 kHz × 6), 16× (96 kHz × 6), **6.3× (192 kHz × 8)** (bench/srcbench).
- The shipped kernel: 308× real time per channel at 192 kHz, about 1 230× at 48 kHz.
- At 192 kHz × 8 there are N + 3 × 2 = 14 detector channels at 48 kHz, which run at 88× real time.
- An exact pruning — skip a sample whose 24-sample window max × max_p‖h_p‖₁ (2.18) cannot beat the running max — gives the identical peak at 2.7× the speed (bench/tpbench).
- Net cost per 4-minute track: about 2.4 s for 44.1 kHz stereo (SRC 2.2 s); about 41 s of one utility core for 192 kHz × 8 (SRC 38 s). The SRC dominates. The existing profiler's cost is unchanged and unmeasured here.

## 3. P2 — album loudness

**Pooled gated blocks.**
- The ReplayGain 2.0 specification: album gain is "calculated … with all tracks concatenated to make one long audio file".
- EBU Tech 3343-2023 §11.2.1 treats an album as a "dedicated sequence" whose Programme Loudness is the BS.1770 integrated measure. EBU Tech 3341 lets a meter "start/pause/continue" one integrated measurement.
- libebur128's `ebur128_gated_loudness` pools every state's blocks under one relative gate (`third_party/libebur128/ebur128/ebur128.c:1086-1159`, `ebur128_loudness_global_multiple` :1178).
- rsgain's default album loudness is exactly that call, and its album peak is the max of the track peaks (`src/scan.cpp:722-760`, commit aae8cc74). Its opt-in `album_as_aes77` uses the loudest track (AES77 not opened: **unverified**).
- foobar2000's scanner is closed source and its algorithm was not opened.

**Measured** (p2_album; block-level simulation; LU relative to pooled):

| Album | pooled | power avg (by duration) | power avg (equal) | mean of LUFS |
|---|---|---|---|---|
| pop, 10 loud + 1 ballad | −8.99 | −0.00 | −0.03 | −0.26 |
| classical, 4 movements | −19.67 | −0.34 | −0.06 | −1.25 |
| compilation, mixed eras | −11.22 | −0.33 | −0.67 | −2.62 |
| ambient intro + loud album | −9.00 | −0.66 | −0.79 | −4.49 |
| live, crowd between songs | −11.69 | +0.00 | +0.00 | −0.04 |
| quiet half + loud half | −9.95 | **−2.83** | −2.83 | −7.85 |

The power average counts quiet tracks' energy that the album's own relative gate discards. It plays the loud half of a "quiet + loud" album 2.8 dB over target. That is more than the ~1 dB a listener notices between albums. Pooling also keeps a one-track album equal to Track mode. **Album TP** = the max of the members' P.

**Payload** (p2_payload): LufsMeter's histogram (800 bins of 0.1 LU from −70 LUFS, count + energy). Album = per-bin sums, then the same two-pass gate.
- Error against exact pooling: ≤ 0.0045 LU with float32 sums.
- Sparse size (u16 bin, u32 count, f32 energy): median 96 bins = 0.9 KB, max 340 = 3.3 KB per variant. Dense: 9.6 KB.
- Histograms come from every block on the engine-rate stream, so the profiler's 10-minute decimation (`TrackLoudnessProfiler.h:27-35`) never touches them.
- The gate math lives **once**, in C++ (LufsMeter's gate as a free function over a histogram), called through TrackLoudnessKit. LevelingKit keeps only the rule: which tracks, and when the album is complete.

**Worked example.** "Quiet + loud halves" pools to −9.95 LUFS, so g_album = −8.05 dB. The loud tracks (−9.9) play at −17.95 and the quiet ones (−25.7) at −33.75: their 15.8 LU spacing is kept. The power average would give g = −5.22: loud tracks at −15.1, 2.8 dB over every other album's foreground.

## 4. P3 — the fold trim with g and G upstream

The plan check's `trim = min(0, C_work − (TP_fold + g + G))` couples the two units. It makes the trim move with every EQ edit and Compare press across two separately published audio units. Instead (§1.3):

1. **trim = min(0, C_work − TP_F[k])** is a per-track constant, independent of g, G and B. It is set at audibility and ramped at the track change. With nothing on (Leveling Off, EQ Off) it alone keeps the backstop asleep. The effects unit stays at P0.
2. **The level stage accounts for the trim.**
   - It protects P = max(TP_N, TP_F[k] + trim). The effects limiter needs TP_N; the backstop needs the trimmed fold.
   - It levels L_F[k] + trim. So g gives back the trim where the cap allows, and the track lands on −18.
   - The proof that both nets close, given the bound of §6: effects peak ≤ TP_N + B + g + G ≤ P + B + g + G ≤ C_work. Fold peak ≤ (TP_F + trim) + B + g + G ≤ P + B + g + G ≤ C_work, because the EQ is identical per channel and commutes with the matrix (from DSP principle).
3. **Compare keeps the trim.** The trim does not depend on the EQ, so Compare and EQ-on hear the same downstream gain.
4. **A continuous gapless group** (Album scope, or the group rule of `TrackLoudnessGain.cpp:247-270`) uses **one trim**: min(0, C_work − max TP_F over the group's analysed members). It is decided before the group's first track. An unanalysed member's excess goes to the metered backstop, never to a step mid-music. At a seam across silence each track keeps its own trim.

**Fallback with no folded analysis**: trim = min(0, C_work − 20·log10(max-row Σ|gain|)) — the matrix's own worst case.

| Layout | Max-row Σ\|gain\| | Fallback trim (Bluetooth / wired) |
|---|---|---|
| 5.1 | 2.414 (+7.66 dB) | −8.93 / −8.03 dB |
| 7.1 at 0.5 surrounds | 2.707 (+8.65 dB) | −9.92 / −9.02 dB |

The backlog's "−7.7 dB" omits C_work.

**Worked example** (p35_chain: hot 5.1 at 48 kHz, kick in L/R/C, vocal in L/R/C, LFE an independent sub → include 0.5, Bluetooth so C_work = −1.272):

| Step | Value |
|---|---|
| analysis | TP_N +0.23 dBTP · TP_F +5.56 dBTP · L_N −6.50 · L_F −4.10 LUFS |
| fold | trim = min(0, −1.272 − 5.56) = **−6.84 dB** · P = max(0.23, −1.28) = +0.23 · L = −10.93 |
| level | g = min(−18 + 10.93, −1.272 − 0.23) = **−7.07 dB** |
| EQ (+5 dB bells on 20–125 Hz, cascade B = +11.88, true ΔL = +1.72) | C_cap = −1.272 − (0.23 − 7.07 + 11.88) = −6.32 · G = min(−1.72, −6.32) = −6.32 · **T = −4.60 dB** |
| readings | effects limiter (6 ch, linked) −5.50 dBTP, backstop −9.82 dBTP: both ≤ C_work, **GR 0.0 dB** |
| Compare | identity at g + T = −11.66 dB: −22.60 LUFS against EQ-on −22.60 LUFS (true ΔL; the predictor adds ≤ 0.14 dB) |
| EQ Off | output −18.00 LUFS · backstop −8.34 dBTP |
| nothing on | backstop reads exactly −1.272 (= C_work, so the guard ε matters) |

## 5. P4 — the LFE rule

**Standards.**
- BS.775-4 Annex 7: the LFE is recorded at −10 dB for exchange and reproduced +10 dB (p. 11). The music industry (DVD-Audio, SACD) codes it for **zero** offset gain (NOTE, pp. 11 and 20).
- The LFE "is often not included in a 2-channel downmix" (p. 11, Fig. 9 p. 18).
- Where it is combined with two mains, Fig. 5 (p. 15) applies +10 dB then **−6 dB into each** of L and R: the coherent pair sums back to the LFE's own level.
- So the standard's include gain for a music-convention LFE is **0.5 per side**. The architecture's 1.0 is +6 dB over it on speakers. On headphones there is no acoustic sum across the pair, so 1.0 matches the speaker level (from DSP principle).
- **Proposal: default include gain 0.5.** It is the standard's figure and costs 6 dB less trim. The founder's three-way listen (omit / −6 dB / full, US-R1F-08 item 5) picks the shipping constant. The pass measures all three gains, so the choice needs no re-analysis.

**Statistics** (p4_lfe*):
- Take the 20–120 Hz band of each channel (LPF Butterworth-4 at 120 Hz, HPF Butterworth-2 at 20 Hz), decimated to 500 Hz.
- An *active block* is a 400 ms block (100 ms hop) whose LFE band is ≥ −50 dBFS.
- Fit **one** least-squares FIR per main channel (±20 ms = 21 taps × 5 mains = 105 unknowns) from the five mains' bands to the LFE band, over the active blocks.
- Per active block: e_j = 1 − P_residual / P_LFE, and x_j = 10·log10(P_residual / Σ P_mains).
- **coherentShare** = share(e_j ≥ 0.8). **lfeExcessShare** = share(x_j ≥ −12 dB).

**Rule `foldDecideLfe`:**
1. activeBlocks < 50 (5 s) → Omit (unknown).
2. coherentShare ≥ 0.4 → Omit (mostly a copy).
3. lfeExcessShare ≥ 0.5 → Include.
4. Else Omit.

**Measured** (5 seeds × 60 s each, ranges):

| Case | ρ₀ (arch. rule) | coherentShare | lfeExcessShare | Decision (margin) |
|---|---|---|---|---|
| copy, LPF Butterworth-8 120 Hz | −0.64 | 1.00 | 0.00 | Omit (+0.60) |
| copy via LR4 80 Hz | −0.72 | 1.00 | 0.00 | Omit (+0.60) |
| copy at −10 dB (film) | −0.64 | 1.00 | 0.00 | Omit (+0.60) |
| copy, EQ-boosted at 45 Hz | — | 1.00 | 0.00 | Omit (+0.60) |
| copy of L+R+C; surrounds own bass | — | 1.00 | 0.00 | Omit (+0.60) |
| copy + rare booms (1 per 8 s) | −0.59 | 0.89–0.90 | 0.15 | Omit (+0.49) |
| copy + frequent booms (1 per 1.5 s) | −0.45 | 0.50–0.51 | 0.71–0.74 | Omit (+0.10, the mixed case) |
| bass only in the LFE | 0.00 | 0.00 | 1.00 | Include (0.40 / 0.50) |
| mains HP 100 Hz + LFE sub | 0.03 | 0.00 | 1.00 | Include |
| independent sub layer at −10 dB | −0.04 | 0.00 | 1.00 | Include |
| silent, or noise at −62 dBFS | — | 0 active | — | Omit (unknown) |

- The architecture's rule (zero-lag ρ ≥ 0.7 → omit) never sees a copy. A production LPF's phase turns ρ₀ negative.
- A single-lag fit (max over ±10 ms) fixes plain copies (0.96–0.99) but fails the EQ'd copy (coherentShare 0.65–0.79) and the subset copy (0.10–0.16).
- The mixed case sits at the threshold by construction. In this fixture, including it would lift the copied bass by about +5.6 dB at gain 0.5 (L′ bass 0.88b → 1.68b).
- **Cost and memory:** 105-unknown normal equations at 500 Hz (about 3 M multiply-adds per second of audio). 6 × 500 Hz floats are kept for the fit, capped at the first 10 minutes like the profiler (7.2 MB). Past the cap, blocks are scored with the fitted filter on the fly.

## 6. P5 — what may move, and the peak arithmetic

**Freeze.** §1.4. The acceptance "one gain value for the whole of a track" is asserted on g with the EQ Off (US-R1F-10 items 4 and 9): 100 samples, max − min = 0. With the EQ On, g is constant and only G may refine with −ΔL, as today. A mode change (US-R1F-10 item 19) glides at τ = 0.15 s. The P0 crossfade (5 ms) handles the bit-exact edge after it.

**Unknown TP.**
- Assume 0 dBTP: the ReplayGain 2.0 player rule, "assume a peak level of 1.0".
- Raise it to a tag's peak only when that is above full scale. RG2 peaks are **sample** peaks ("the maximum absolute sample value"), so they never bound a true peak from above.
- So an unanalysed or tag-sourced track's gain never exceeds C_work (−0.37 / −1.27 dB): it is never raised until analysed. The −5 dB unknown cut never meets the cap.
- A TP that lands mid-track applies at the next track.

**The arithmetic closes exactly where the gain path is a multiply.**
- Leveling with the EQ Off: identity cascade, g a constant.
- The fold: a fixed matrix, its TP measured on the same engine-rate signal.
- Both readings come from the same kernel on the same samples. They differ only by float rounding, which the ε guard covers.

**With the EQ On it rests on `TP_H ≤ TP + B`.** The bound form the roadmap's sound plan §1 names for R1.1-B is not a bound: an all-pass or a cut can raise a peak (from DSP principle). Measured, p3_bound, violation v = TP_H − (TP + B):

| Curve (drawn gains, no solve) | B | v, music-like fixtures | worst v (any fixture) |
|---|---|---|---|
| +5 dB bells, 20–125 Hz | +11.88 | −7.65 … −3.04 | **+1.07** (square-ish 50 Hz bass) |
| +12 dB at 63 Hz | +12.00 | −11.25 … −6.08 | −4.15 |
| +6 dB at 4 kHz | +6.00 | −6.07 … −4.93 | −4.93 |
| smile +6/+6 | +13.87 | −7.58 … −0.64 | +0.23 |
| jagged ±12 | +4.44 | −4.83 … −2.65 | −1.10 |
| cut only, −12 dB at 100 Hz | 0.00 | −0.93 … **+0.09** | +0.09 (clipped master) |

"Music-like" = 3 clipped loud masters and 3 dynamic tracks; the extra fixture is a square-ish 50 Hz bass (odd harmonics in phase).

On music-like material with a boost curve the bound over-turns-down by 0.6–11.6 dB. A cut-only curve can exceed it by 0.09 dB on a clipped master. Phase-coherent harmonic bass under a stacked boost can exceed it by about 1 dB, and the net then works. The strict bound 20·log10‖h‖₁ (+16.4 dB for the first curve) would over-turn-down by 4.5 dB more. **Recommendation:**
- Keep the planned bound form, with **no extra margin**.
- State the failure envelope in known issues.
- Prove "GR 0.0 dB with the EQ On" on music-like fixtures and the founder's corpus.
- The measured TP_H (S14-lite) closes it.
- With leveling at −18 the cap rarely binds: a −9 LUFS master at +0.5 dBTP on Bluetooth has g = −9 and C_cap = 7.23 − B, so T = 0 for any B ≤ 7.2 dB.

**Seams.** B's gain lands at the seam "as the engine counts it", up to one buffer late (KI-GAP-02), then glides 10 ms. A continuous seam shares the group gain and trim, so nothing steps. At a seam across silence, a B that opens loud within about 20 ms can play its first ~20 ms at A's gain. If g_A > g_B, the net may act there. This is accepted until the Engine sprint. The gapless test reports the worst case on its fixture pairs.

## 7. P6 — Compare, the deletion, the golden master

**Compare.**
- Hold = the identity cascade published with outputGainDb = g + T.
- EQ-on loudness = L + g + G + ΔL_true. Compare = L + g + G + ΔL_pred.
- So the mismatch is the predictor's error alone: ≤ 0.112 dB on the 7-track corpus, ≤ 0.14 dB on broadband music (`TrackLoudnessProfile.h:19-20, 38`).
- The bound B changes G on both sides equally. The trim is EQ-independent (§4).
- **Folded files:** predicting ΔL on the 5.1-weighted profile while the listener hears the fold misses by −0.22 … +0.19 dB on a bass boost (p6_dl_fold). Combined with the predictor's own error, that breaks the 0.2 dB budget.
- **So the profiler is fed the signal heard.** When the graph folds (known at `configureGraphForSource`, `AudioEngineBridge+ChannelLayout.swift:65-76`), the profile basis is the stereo fold. It uses the LFE gain from the persisted analysis when one exists, else omit. The cache key gains the basis.
- Compare needs the EQ-on design while the identity plays. `EqIntent` gains `comparing` (S3), and the Realizer keeps the last EQ-on design for B and ΔL.

**The deletion.**
- `LoudnessParams`, the makeup law, `loudnessContribution_` and its glide (`DSPKernel.cpp:39, 294-299, 348-351`), and the P2/blend Loudness calls (`:267, :316`) go.
- `LufsMeter` and `CausalLoudnessTap` stay.
- The proof is the Intensity sweep 0 → 1 → 0 with Leveling Off: LUFS within 0.1 dB, plus a semgrep rule banning `LoudnessParams`.

**`sizeof(TargetState)`.** Measured offline with the shipped header: 768 B today (744 B used), 768 B without `LoudnessParams` (732 B used). `alignas(64)` absorbs the 12 B, so `kMeasuredTargetStateBytes` (`TargetState.h:161`) stays 768. The offsets of brir, crossfeed and limiter shift by −12 B, which does not touch the audio. Re-run the assert as the recorded step.

**Golden master.** `0xF0E1D4EF83763709` (`Tests/TestSupport.h:126`) runs P2 with `loudness.enabled = 0` (`:368-371`). There the makeup ramp is snapped to unity at initialize and stays on the identity fast path (`LoudnessModule.cpp:56-58, 128-131, 163-169`). Removing the stage is therefore expected to hold the hash bit for bit, and the run is the proof. Tests that set or assert the makeup re-baseline or are deleted as a recorded step: `LoudnessTests.inc`, `EqEngine{BreakItMeasurements,BreakItTests,FixTests}.inc`, `LimiterTests.inc`, `MultichannelTests.inc`, `SnapshotConcurrencyTests.inc` and `TestSupport.h` (16 `.loudness.` references). The fold is a no-op at N = 2.

## 8. The seams, frozen

### S1 — the pass (lane 1 → lanes 2, 3)

**A deviation from the plan check.** The analysis is a separate C++ object fed the **engine-rate** stream, not a field of the source-rate profile. Album jobs need it without a profile (§2), and it is measured at another rate. `TrackLoudnessProfile` is unchanged.

```c
// include/TrackLoudnessBridge.h (beside AsLoudnessProfileInfo)
#define AS_TRACK_ANALYSIS_VERSION 1u     // bump on any change to: fold coefficients, LFE rule/stats/gains,
                                         // peak rate or SRC, K-weighting, gates, histogram form
typedef enum { AsLfeUnknown = 0, AsLfeOmit = 1, AsLfeInclude = 2 } AsLfeChoice;
enum { AS_FOLD_LFE_VARIANTS = 3 };       // per-side LFE gain 0, 0.5, 1.0
typedef struct { uint32_t activeBlocks; double coherentShare, lfeExcessShare, medianExplained; } AsLfeStats;
typedef struct {
  uint32_t version, channelCount;
  double sourceRateHz, peakRateHz, durationSeconds;
  double integratedLufs, truePeakDbtp;           // L_N, TP_N (all N channels, LFE included)
  double headBlockLufs, tailBlockLufs;           // −200 = silent
  uint8_t folds, lfeChoice;                      // folds: N > 2 and makeBs775Fold succeeded
  double foldedLufs[AS_FOLD_LFE_VARIANTS], foldedTruePeakDbtp[AS_FOLD_LFE_VARIANTS];  // NaN when !folds
  AsLfeStats lfe;
} AsTrackAnalysis;
typedef struct { uint16_t bin; uint32_t count; float energy; } AsLoudnessBin;  // bin i = [−70 + 0.1 i, +0.1) LUFS
AsTrackAnalyzer* asTrackAnalyzerCreate(double engineRateHz, uint32_t channels, const uint8_t* roles) AUDIODSP_C_NOEXCEPT;
bool asTrackAnalyzerFeed(AsTrackAnalyzer*, const float* const* channels, uint32_t channelCount, uint32_t frames) AUDIODSP_C_NOEXCEPT;
bool asTrackAnalyzerFinish(AsTrackAnalyzer*, AsTrackAnalysis* out) AUDIODSP_C_NOEXCEPT;      // decides lfeChoice
uint32_t asTrackAnalyzerHistogram(const AsTrackAnalyzer*, uint8_t variant /*0 = N-ch, 1+k = fold k*/,
                                  AsLoudnessBin* out, uint32_t capacity) AUDIODSP_C_NOEXCEPT; // non-zero bins
bool asLoudnessPoolHistograms(const AsLoudnessBin* const* tracks, const uint32_t* counts, uint32_t trackCount,
                              double* outLufs) AUDIODSP_C_NOEXCEPT;  // LufsMeter's gate over the summed bins
void asTrackAnalyzerDestroy(AsTrackAnalyzer*) AUDIODSP_C_NOEXCEPT;
```

**Swift (TrackLoudnessKit).**
- `public struct TrackAnalysis: Codable, Sendable, Equatable`. It carries the version, the `TrackIdentity` (`TrackIdentity.swift:9-36`), the scalars above, `roles: [ChannelRole]`, `fold: Fold?` (lfeChoice, stats, loudness[3], truePeak[3], histograms[3]), `histogram`, and `analysedAt`.
- `static func fixture(…)` serves the stubs.
- The decoder's outcome becomes `.whole(profile?, analysis)`.

**Stub commit 1.** The analysis fields are NaN, `folds = 0`, `lfeChoice = Omit`.

### S1b — roles and the matrix (lane 1; rule body lane 2)

**Roles.**
- `ChannelLayout` gains `std::array<ChannelRole, kMaxChannels> role` (`include/ChannelLayout.h:16-23`), filled off the audio thread from CoreAudio's own expansion of the tag or bitmap into labels (`kAudioFormatProperty_ChannelLayoutForTag` / `…ForBitmap`, or the file's descriptions).
- `enum class ChannelRole : uint8_t { Unknown, L, R, C, Lfe, Ls, Rs, Lb, Rb, Cs, Lc, Rc, Lw, Rw, Mono }`. The labels come from `CoreAudioBaseTypes.h:976-1064`: Left 1, Right 2, Center 3, LFEScreen 4 / LFE2 37 → Lfe, LeftSurround 5 / LeftSurroundDirect 10 → Ls, RearSurroundLeft 33 → Lb, CenterSurround 9 → Cs, LeftCenter 7 → Lc, LeftWide 35 → Lw, Mono 42.
- The decoder today knows five tags (`Loudness/ChannelLayoutDecoder.cpp:143-245`). It falls back to weight 1.0 with no LFE for `WAVE_5_1_B`, `WAVE_7_1` (`L R C LFE Rls Rrs Ls Rs`, SDK :1416), `AAC_5_1` (`C L R Ls Rs Lfe`, :1356) and others. That is KI-MC-02 for loudness too.
- The analyzer passes `format.channelLayout?.layoutTag ?? Unknown` (`TrackLoudnessAnalyzer.swift:336`), not the bridge's resolved tag. **One resolver for both.**
- The count fallback for 8 channels should be `WAVE_7_1`: FLAC's default order (RFC 9639 channel table: "front left, front right, front center, LFE, back left, back right, side left, side right"). It should not be `MPEG_7_1_A` (`AudioFormatKit/MultichannelFormat.swift:62-63`).

**`std::optional<FoldMatrix> makeBs775Fold(const ChannelLayout&, float lfeGain) noexcept`** builds 2 rows × kMaxChannels.

| Role | → L′ | → R′ | Source |
|---|---|---|---|
| L / R | 1.0 | — / 1.0 | BS.775-4 Table 2 (p. 8) |
| C, Mono | 0.7071 | 0.7071 | Table 2; Annex 5 §1.1 (mono on two speakers −3 dB) |
| Ls (only surround pair) | 0.7071 | — | Table 2 |
| Ls **and** Lb both present (7.1) | 0.5 each | — | **derived**: recommends §2 Note 5 (one LS feeds several speakers at equal total power ⇒ the inverse sums them at 0.7071), then Table 2's 0.7071. **BS.775-4 has no 7.1 row** |
| Lb only (e.g. WAVE_5_1_B) | 0.7071 | — | treated as the surround pair |
| Cs | 0.5 | 0.5 | derived: mono surround fed to LS and RS (§3; Annex 5 §2.2 equal power), then Table 2 |
| Lc, Lw | 1.0 | — | judgment, **unverified** (rare SDDS / wide layouts) |
| Lfe | lfeGain | lfeGain | §5; BS.775-4 Fig. 5 |
| Unknown | 0.5 | 0.5 | judgment: keep it audible, bounded |

The mirrored right side follows the same rules. `foldTrimDb(double cWorkDb, double foldedTpDbtp, const FoldMatrix&) noexcept` = min(0, cWorkDb − tp); with NaN TP it uses the matrix's own worst case (§4). `AsLfeChoice foldDecideLfe(const AsLfeStats&) noexcept` holds §5's constants (lane 2's body; the W1 stub returns Omit).

### S3 — leveling and Compare into the level stage (engine end lane 1, sender lane 3)

```swift
// AudioPlaybackEngine (Sources/AdaptiveSound/AudioPlaybackEngine.swift:204) — FakeEngine records both
func publishTrackLeveling(_ leveling: TrackLeveling, for token: UInt64)  // replaceable until audible; frozen then
func publishEQ(points: [Float], isOn: Bool, comparing: Bool)            // replaces publishEQ(points:isOn:)
// LevelingKit (pure)
public struct TrackLeveling: Sendable, Equatable {
  public enum Scope: Sendable, Equatable { case off, track, album(groupKey: UInt64) }
  public enum Source: Sendable, Equatable { case analysis, tags, unknownCut }
  public var scope: Scope; public var source: Source
  public var unfolded: LevelNumbers            // album: pooled loudness, max peak
  public var folded: FoldedNumbers?            // N > 2; sent in every scope, .off included (the trim needs it)
  public var appliesNow: Bool                  // the listener's mode change only
}
public struct LevelNumbers: Sendable, Equatable { public var loudnessLufs: Double?; public var peakDbtp: Double? } // nil = unknown
public struct FoldedNumbers: Sendable, Equatable {
  public var loudnessLufs: Double; public var peakDbtp: Double; public var channelPeakDbtp: Double; public var lfeGain: Double
}
```

- **C-ABI:** `bool publishTrackLeveling(void* au, uint64_t token, const AsTrackLeveling*)`, a struct mirror with NaN for unknown. `setOutputTransport` (`Realizer.h:146`) becomes `setOutputTransport(uint32_t transport, double nominalRateHz, uint32_t outputChannels)`. That gives C_work, the rate condition (KI-SND-07) and the fold state, from the bridge's `configureGraphForSource`.
- `TrackLoudnessGain::TrackEntry` (`TrackLoudnessGain.h:120-126`) gains `std::optional<Leveling>`. `onCurrentTrack` freezes {g, P, C_work, trim}. `EqIntent` (`Realizer.h:88-92`) gains `bool comparing`.
- **The spatial unit** gets `asSpatialSetFold(void* spatialAU, const AsFoldParams*)`: {matrix, lfeGain, foldedPeakDbtp, ceilingLinear}. The bridge sends it at `trackBecameAudible` with the same frozen inputs. Lane 2 owns the receiving end; it must be the same numbers the effects plan used.

### The derived-data record and its scheduling

**The file.**
- `AppDataLocation.directory/track-analysis.sqlite3`, beside `library.sqlite3` (`AdaptiveSound/AppDataLocation.swift:26-28`). It is never the library DB (record, decided as recommended).
- One GRDB `DatabaseQueue` (the library's own engine, a separate file). Table `track_analysis(path, size, mtime, version, payload BLOB, analysed_at)` with primary key (path, size, mtime), the full identity, never the 64-bit token alone.
- `payload` = the binary-plist `TrackAnalysis` with its sparse histograms: about 1–4 KB per stereo track and ×4 for a folded one.

**The rebuild rule.**
- A record of another `version` is "not analysed" and is overwritten on re-analysis.
- An unreadable file or a schema mismatch **deletes and recreates the file**. This is derived data, the one store allowed to be wiped, never through `eraseDatabaseOnSchemaChange` (`posture.sh`).
- A moved or re-tagged file gets a new identity and costs one re-analysis. No pruning in R1.1-B.

**The contract.**
- `TrackAnalysisStore` (actor): `analysis(for:)`, `save(_:)`, `pooled(_ identities:) -> AlbumLoudness?` (nil unless every member is present at the current version).
- `TrackLoudnessAnalyzer.analyzeAlbum(_ tracks: [(URL, TrackIdentity)], priority:)` runs in the background at utility QoS, at most 2 jobs. It skips stored records, never pre-empts the current/next jobs (their slots stay), and emits `landed: AsyncStream<TrackIdentity>`.
- **Triggers** (lane 3's coordinator): any queue change → every queued track's album (the library's album identity; a loose file is its own album) not fully analysed, in queue order.
- No library-wide sweep, nothing while Pure is the path in use, and failures held in memory only (as today, `TrackLoudnessAnalyzer.swift:110, 195-198`).
- A landing never changes the playing track. Album mode before an album is complete follows the record's rule: tags if every track has them, else the track's own gain until the next seam across silence.

## 9. Proving measurements (rig · tolerance)

| Acceptance line | Rig | Tolerance |
|---|---|---|
| gain to −18 (Track, Album) | C++ null test: analysis → plan → apply → libebur128 (`ebur128_loudness_global_multiple` for albums) | 0.2 LU where the cap allows; else output TP ≤ C_work |
| TP field | C++: field vs the limiter's own reading on the same 48 kHz signal; vs libebur128 TP | ≤ 0.001 dB; ≤ 0.3 dB (`kOracleTpTolDb`, `LoudnessOracleTests.inc`) |
| folded TP | C++: field vs the kernel on the actually folded stereo | ≤ 0.01 dB (same kernel and samples; the plan's 0.1 dB is loose) |
| net GR, leveled corpus | C++ at 48 kHz (exact); the coordinator's read-only CLI through the real converter on the founder's files (decision 4) | max GR < 0.01 dB |
| T on a −9 LUFS fixture with a bass preset | C++, music-like fixture | GR < 0.01 dB; single application (output = input × (g + G) on the flat path) |
| Compare with T active | C++: EQ-on vs Compare LUFS (libebur128), stereo and folded fixtures | ≤ 0.2 dB |
| one gain per track; unknown −5 dB | C++ `RealizerTests` (g sampled 100×, EQ Off) + Swift FakeEngine records | max − min = 0 |
| gapless Album pair | C++ + Swift | one g, one trim across the seam |
| mode-change glide | C++: τ = 0.15 s one-pole | glide shape within 0.05 dB |
| AGC gone | C++ Intensity sweep 0 → 1 → 0, Leveling Off; semgrep `LoudnessParams` | 0.1 dB; 0 hits |
| folded file leveled on L_F | C++ fixture with L_F − L_N = 1.6 LU by design | asserts L_F |
| album pooling | C++ / TrackLoudnessKitTests: histogram pool vs exact blocks vs libebur128 multiple | ≤ 0.01 LU |
| LFE rule | C++ `SpatialTests`: §5's synthetic cases | the table's decisions; copy fold low band within 1 dB of mains-only |
| matrix | C++: C-only −3.0 dB/side, L = R = C +4.6 dB, stereo-in-5.1 null (fixture TP < C_work) | ±0.1 dB; bit-exact |
| backstop | the CLI over the founder's surround albums; VerifyAUGraph M == N bit-exact with the backstop bypassed | GR < 0.01 dB; bit-exact |
| persistence | TrackLoudnessKitTests: round trip, version bump → not analysed, corrupt file → recreated; VerifyLibraryStore: no loudness column | exact |
| fresh-launch null | golden master + MD5 | bit-exact |

## 10. Golden-master impact

The hash should hold (§7). `sizeof` stays 768. Tests that drive the makeup re-baseline or go (recorded). New fold fixtures get their own hashes in `MultichannelTests.inc` (lane 2). Nothing changes at N = 2 or with Leveling Off and the EQ Off.

## 11. Build order

**Lane 1:**
1. Stubs: S1 header/C-ABI with NaN, `FoldMatrix.h` 5.1 row, S3 members as no-ops, `TrackAnalysis.fixture`.
2. Roles from labels plus one layout resolver, then the full `makeBs775Fold`.
3. `AsTrackAnalyzer`: TP_N, fold × 3, histograms, LFE stats, head/tail. Swift feeds it through `StreamingResampler`.
4. Pooling and the store, then `analyzeAlbum`.
5. `TrackLoudnessGain`: leveling, freeze, cap, T, Compare. `setOutputTransport` gains rate and width.
6. The profile basis on the fold.
7. AGC deletion plus the size assert.
8. Oracle tests.

**Lane 2 (parallel from W4):**
1. S2 stub fields.
2. The spatial control path, matrix, LFE gain, `foldTrimDb`, and the ramp at the track change.
3. The backstop and its GR atomic.
4. The `foldDecideLfe` body.
5. Crossfeed engaged + `SignalPathInfo`.
6. VerifyAUGraph.

Lane 2 builds against the S1 fixture until lane 1's step 3 lands.

## 12. Open questions (recommendation first)

1. **LFE include gain** → 0.5 per side (BS.775-4 Fig. 5) by default. The founder's listen picks 0.5 or 1.0. The pass measures both, so no re-analysis.
2. **7.1 → 2.0** (no BS.775-4 row) → 0.5 per surround (derived, power-preserving). The alternative, 0.7071 each, puts the surround field +3 dB hotter than the 5.1 fold.
3. **2 < M < N** (a 7.1 file on a 6-channel output) → fold to stereo on device channels 0–1, never truncate. A 7.1 → 5.1 fold is the Engine sprint's (the layout owner). Founder check: how many channels the HDMI soundbar presents.
4. **The bound form** → keep it, with no margin, and log the measured envelope (+1.07 dB worst) as a known issue forwarded to S14-lite's measured TP_H.
5. **Ceiling or fold change mid-track** → the trim engages at once, and g re-caps at the next track (backlog item 6).
6. **The seam blip** (§6) → accept until the Engine sprint; measure and report it in the gapless test.
7. **The analysis CPU on the M1 Pro floor** → measure at lane 1's step 3. If 192 kHz × 8 albums are too slow, lower the album jobs to 1. Do not use a cheaper SRC (it reopens §2).
8. **The unknown-role fallback (0.5 to both)** → acceptable for R1.1-B; positional folding comes with the Engine sprint's layout owner.
9. **The first play of an unanalysed 5.1 track** → fallback trim −8.9 dB (Bluetooth) plus the −5 dB unknown cut. Accept: album analysis on queue makes the second play exact.
10. **Album pooling across fold states** (some tracks folded, some not) → pool each member's variant for the current output.
11. **Citation fix** (architecture §9.1 "the rule Roon, JRiver, foobar2000 and MPD share"):
   - MPD's `auto` is "track … if random play is activated, otherwise album" (`doc/user.rst:669-671`).
   - foobar2000's is "by playback order" (wiki, Preferences: Playback).
   - Roon's Auto is the neighbour rule ("adjacent tracks", Roon KB Volume Leveling).
   - JRiver: not opened.
   - The Auto rule itself is a state rule for the step-2 review.

## 13. Prototype index

Scripts are in `/private/tmp/claude-501/-Users-ramith-code-sound-engineering/3d4475b9-e75c-4bb0-9910-1b01ee070987/scratchpad/r11b/design/`. Run them with `venv/bin/python -I` from `proto/`.

- `proto/common.py`: exact ports of `TruePeakKernel.h`, BS.1770-5 K-weighting and gates (validated: −3.010 LKFS for a 0 dBFS 997 Hz tone; coefficients equal BS.1770-5 Tables 1–2), libebur128's 4× interpolator, the shipped bell, and synthetic signals.
- `p1_kernel` and `p1_rate` / `_check`: P1.
- `p2_album` and `p2_payload`: P2.
- `p3_bound`: §6.
- `p35_chain`: §4.
- `p4_lfe`, `p4_lfe2`, `p4_lfe3`: P4.
- `p6_foldloud` and `p6_dl_fold`: §1.2, §7.
- `bench/tpbench.cpp` (clang -O2 against the shipped header), `bench/srcbench.swift` (AVAudioConverter, Mastering/max), and `bench/sz.cpp` (sizeof).
- Every fixture is synthetic. No founder music was read.

## Sources opened this session

- ITU-R BS.1770-5 (11/2023): Annex 1 eqs (2)–(7), Tables 1–3; Annex 2 and its Attachment 1 table.
- ITU-R BS.775-4 (12/2022): recommends §2–7 and Notes 1–5; Annex 4 Table 2; Annex 5; Annex 7 with Figs 5 and 9; Annex 8.
- EBU R 128-2023; EBU Tech 3341 §2 (gating), 3342, and 3343-2023 §§4.1, 4.2, 7.1, 11.1.1, 11.2.1.
- libebur128 (vendored, 67b33ab): `ebur128.c` :110-200, :345-352, :687-780, :1062-1182.
- ReplayGain 2.0 specification (hydrogenaudio wiki, archived copy).
- rsgain `src/scan.cpp` @ aae8cc74.
- Roon KB "Volume Leveling" (archived).
- MPD `doc/user.rst` (master).
- foobar2000 wiki "Preferences: Playback" (archived).
- RFC 9639 (FLAC) channel table.
- `CoreAudioBaseTypes.h` (macOS SDK in Xcode).
