# Level and fold — the R1.1-B sound design note (revision 1, after the panel; as built, §16)

*Step 1 of the full loop (`docs/sprints/00-sprint-model.md` §5) for the sprint's sound lanes. Revision 1 is the one author revision after the blind three-reviewer panel (breaker, state-of-the-art challenger, architect). The first draft is this file's first commit (`git log --follow` on it). §14 maps every panel finding to what changed.*

*As built (2026-10-30): §16 records what the build settled and where it departed from this note, lane by lane and through the fix round. The sections above keep the design as the panel reviewed it; where a number or a signature changed, a short "as built" note at that place points to §16. Where this note and the code differ, the code wins.*

*Basis: code claims cite file:line at 966cb205 on `main` (the plan-check commit the design branch started from). The standards and implementations cited were opened in the drafting session (list at the end).*

*Labels:*
- ***Measured*** — a prototype run on synthetic material (scripts: §15). No founder music was read.
- ***(from DSP principle)*** — reasoning, not measurement.
- ***Unverified*** — not checked.

*Decisions: the only founder decisions named here are the ones in [the sprint record](../../sprints/r1-1b-record.md) ("Decisions at the gates"). The roadmap's sound plan is cited as the plan of record. Listener-facing choices that belong to the founder are **not decided here**; they are in §12, "For the founder".*

**Scope.**
- In scope:
  - **Lane 1:** the one analysis pass, the per-track plan (leveling gain, cap, fold trim), the peak-safe turn-down, Compare, and the old leveller's deletion.
  - **Lane 2:** the interim fold, the LFE rule, the backstop, and **a fix to shipped code** (F1: the resampler route drops or reorders channels).
  - **Lane 3:** the app-side decisions, the store and the album scheduler.
- Out of scope: Pure. Leveling in Pure is deferred until the USB DAC (record, decision 1), so nothing here runs in Pure.

## 0. The answers, revised

| Q | Answer |
|---|---|
| **P1** | **Where:** every true peak is measured on the engine-rate stream after the engine's own Mastering converter, with the converter's output format set to **the file's own channel layout** (F1).<br>**How:** analysis peak = max(shipped 8×24 reading, an 8×64 reading). The limiter therefore never reads above the field, and the reconstructed peak is under-read by at most 0.09 dB.<br>**What:** max over all N channels including the LFE, plus the fold at LFE gains 0, 0.5, 1.0 and 1.585.<br>**Cost:** 110× real time for 44.1 kHz stereo; 6× for 192 kHz × 8; 3.1–3.3× for 352.8/384 kHz × 8. |
| **P2** | The album's loudness **anchor** (pooled gated blocks, or the loudest track per AES77 / Grimm) is the **founder's** choice (§12 F-1). Both are computable from the stored record without re-analysis. A folded album uses **one trim** (F2), so pooling or max is over member numbers that share it. Album peak = max of the members' peaks. |
| **P3** | **The trim:** stays `min(0, C_work − TP_F)` in Track scope at seams across silence.<br>**Groups:** any group (Album scope, or a continuous gapless run) shares one trim, one leveling gain and one LFE choice. The trim is the group's worst.<br>**Output change mid-track:** a protective re-plan with the frozen g: `trim′ = min(0, C_work′ − (TP_F + g))` (F5).<br>**One planner:** a pure C++ planner computes the plan **once**, and the same value goes to both audio units (B1). |
| **P4** | The LFE decision is made **at plan time** from stored statistics (M4).<br>**Statistics:** a global lag search; a multi-input least-squares fit; a scale-invariant per-block shape match; an "explaining gain" bound.<br>**Result:** 117 of 117 fixture runs are correct, from my fixtures and both reviewers': delayed, linear-phase, kick-stem, automated-send and EQ'd copies are omitted; independent layers and redirected bass are included.<br>**Include gain:** the founder's choice (§12 F-3). |
| **P5** | **Frozen at audibility:** g, P, C_work, the trim, the LFE choice, and now **G** too, from a persisted −ΔL profile (challenger #2).<br>**What may move:** a listener's mode change glides; an output change re-plans protectively.<br>**Silent or very short tracks:** unknown loudness (F4); g ≤ +12 dB.<br>**When it closes:** exactly with the EQ Off **and crossfeed off**. With the EQ On it holds only as far as `TP + B_eff` bounds the peak; the measured envelope is +1.56 dB on boosts and +0.69 dB on cuts before the cut allowance (F6). |
| **P6** | **Compare** = identity at g + T. On a fold, ΔL must come from the fold's own profile: the 5.1 basis misses by up to 2.14 dB (F7).<br>**Deletion:** `LoudnessModule` is deleted entirely (M8).<br>**Size and golden masters:** `sizeof(TargetState)` stays 768 B (728 B used). The stereo golden master should hold. A new golden covers P1 with a leveling gain. |

## 1. The model

### 1.1 Symbols

| Symbol | Meaning |
|---|---|
| C | The output's ceiling by scope (roadmap sound plan §1): −0.1 dBTP lossless at the engine rate, else −1 dBTP. |
| **C_work** | 20·log10(ceiling_lin × `kIspSafetyMargin`) − ε. `kIspSafetyMargin` is 0.96939 (`Limiting/LimiterModule.h:105`). ε = 0.01 dB guards rounding, because the limiter acts only when `peak > workingCeiling` (`:440`). Values: **−1.282 dBTP** on Bluetooth (0.891), **−0.380** wired (0.98855). The backstop computes its working ceiling the same way, from the same float. |
| L_T | −18 LUFS |
| B | Max over f of the EQ program's played response (≥ 0). |
| **B_eff** | max(B, min(20·log10‖h‖₁, 0.7 dB)): the cut allowance (§6). |
| ΔL | The taste layer's predicted loudness change (`Loudness/TrackLoudnessProfile.h:123-135`). |
| Processed-path ceiling | `max(truePeakCeiling, eqOnlyCeiling)` (`DSPKernel.cpp:257-259`). |

### 1.2 Per track: what the pass measures (off the audio thread)

The pass decodes once at the source rate.
- **Source rate:** feeds today's profiler first (−ΔL prefix, unchanged, published before any conversion — architect N12).
- **Engine rate:** the stream converts to 48 kHz through `StreamingResampler` **with the file's own layout as the output format** (F1), and feeds the analyzer:

| Quantity | Definition |
|---|---|
| L (N-channel) | BS.1770-5 gated, BS.1770-5 Table 3 weights (LFE 0). A mono file is stored as measured; the planner adds +3.01 LU when it plays to ≥ 2 output channels (F8, measured below). |
| TP_N | max(8×24 shipped kernel, 8×64 kernel), over **all N** channels including the LFE (the linked effects limiter, `LimiterModule.h:267-271`). *As built: and the sample peak (§16, lane 1-B).* |
| L_F[v], TP_F[v] | The same on the BS.775 stereo fold, for LFE gains v ∈ {0, 0.5, 1.0, 1.585} per side. |
| head, tail | First and last whole 400 ms block (N-channel weights). |
| histograms | 0.1 LU, count + exact energy sum (LufsMeter's form, `Loudness/LufsMeter.h:93-97, 453-460`), N-channel and each fold variant. |
| LFE statistics | §5. |
| compact −ΔL profiles | 1/12-octave bands, 400 ms non-overlapping blocks, float16, one per playable basis (N-channel; fold × 4 variants). *As built: 1/24-octave, every block up to 1,200 then decimated, binary16 × 2^10; one profile for a fold without an LFE (§16).* |

**Measured, mono (F8, `bench/mono.swift`):** AVAudioEngine's main mixer, fed a 1-channel source into a 2-channel output (offline manual rendering, mirroring the app's last edges), puts it on **both sides at 0.00 dB**. The heard programme is therefore dual mono, 3.01 LU above the one-channel measure (libebur128's `EBUR128_DUAL_MONO`). Lane 1 confirms this on the device path with VerifyAUGraph.

**Why each fold variant is kept.**

| Fixture | L_F(omit) − L_N | L_F(0.5) − L_F(omit) | L_F(1.0) − L_F(omit) |
|---|---|---|---|
| uncorrelated, equal | −1.63 LU | 0 | 0 |
| surrounds −6 dB | −0.57 | 0 | 0 |
| centre only | 0.00 | 0 | 0 |
| divergent vocal (L = R = C) | **+2.88** | 0 | 0 |
| strong LFE sub | −0.85 | +0.73 | +2.39 |
| film-level LFE | −0.83 | +2.29 | +5.81 |

The first four rows are the breaker's analytic values; my noise fixtures read within 0.13 LU. EBU Tech 3343-2023 §7.1 predicts the sign change and prescribes "a subsequent loudness measurement and potential static gain correction".

### 1.3 Per play: the plan — one pure function, called once (B1)

`AsTrackPlan asPlanTrack(const AsTrackLeveling* decision, const AsOutputState* output, const AsTrackPlan* frozenOrNull)` lives in C++ in AudioDSP (`Planning/TrackPlan.{h,cpp}`, new). Inputs:
- the app's decision (§8, S3): measured numbers only, already scope-resolved;
- the output state (M2): {transport, nominal rate, M, N}.

```
TP     = unknown, or peakRateHz ≠ the kernel's 48 kHz → 0 dBTP     (RG2's "assume 1.0"; architect N6)
v      = the decision's LFE variant (Omit unless chosen; a group shares one, §4)
C_work = from the output state (one rule, in C++)
fold   = N > 2 and M < N  (mono: no fold; L += 3.01 when M ≥ 2)
trim   = fold ? min(0, C_work − TP_F[v]) : 0          (group/album: TP_F = max over the members)
P      = max(TP_N, fold ? TP_F[v] + trim : −∞)        (group: maxima over the members)
L      = (fold ? L_F[v] : L_N) + trim                 (group/album: the anchor over the members, §3)
g      = Leveling Off → 0
         no gated block, or duration < 0.4 s, or unknown → min(0, −5 − trim)   (F4; the unknown rule;
                  a fold's fallback trim already cuts more than −5, so it is not cut twice)
         else min(L_T − L, C_work − P, +12 dB)        (F4: the +12 dB clamp, as −ΔL's)
```

*As built (§16, lane 1):* the unknown rule is `min(0, −5 − trim, C_work − P)` — always capped by the peak, an unknown
peak counting as 0 dBTP; a mono or stereo source's M is the width the device plays it on, so the mono +3.01 applies
(§16, the fix round).

**Where the plan's parts are applied.**
- **The effects unit** gets `setCurrentTrack(token, seam, plan)` *(as built: `applyTrackPlan(token, event, plan, continuous)`, `AudioEngine/Realizer.h:149`)*. Its Realizer keeps `levelDb_ = g` from plans only. In `TrackLoudnessGain`'s `neutralDb_` it computes **C_cap = C_work − (P + g + B_eff)**, **G = min(−ΔL, C_cap)** and **T = G + ΔL ≤ 0**.
- `eq.outputGainDb = g + G` (`include/TargetState.h:32-33`).
- With the EQ Off, G = min(0, C_cap). That is 0 by construction at plan time, and becomes negative only after a protective output re-plan. With Leveling Off and the EQ Off, nothing is applied (P0 holds).
- **The spatial unit** gets the matrix, v's gain and the **computed** trim, from the same plan value, in the same turn (M1).

**When the planner runs** — on the queue that declares audibility, and only then:
1. **A new token becomes audible.** This includes the same token at a real seam (Repeat One — architect N3). The gain **snaps** at a fresh start, so no 10 ms glide from the previous gain (N4), and glides 10 ms at a gapless seam.
2. **The listener changes the Leveling mode (`appliesNow`).** The current track re-plans; both units glide at τ = 0.15 s. The next track's armed decision is replaced (N11).
3. **The output state changes at a re-establish.** This is the protective re-plan with g frozen:
   - `trim′ = min(0, C_work′ − (TP_F[v] + g))`;
   - `P′ = max(TP_N, TP_F[v] + trim′)`;
   - the effects side's C_cap uses P′ and C_work′.

   F5's example (g = +5.62, TP_F = −3.5, switching to Bluetooth): trim′ = −3.40 dB, backstop asleep.

A resume, seek or device move with the same token and the same output state sends **nothing** (B1).

*As built (§16, the fix round — break-it MEDIUM-1, review B2):* a start says which listen it is. A **resume** keeps
its plan — the level never steps inside a song — and re-sends the plan's fold half, snapped; a **new play** of the
same token (Play after Stop, Previous restarting the song, Repeat One) is decided and planned afresh; a seek or a
device move sends nothing. Both units glide on one one-pole law, and an output change glides 10 ms on both.

### 1.4 What may change inside a track

| Quantity | Automatic change inside a track | Listener's act |
|---|---|---|
| g, P, C_work, trim, LFE variant | never — the plan is frozen at audibility | mode change: re-plan, glide 0.15 s |
| −ΔL (so G, T) | **never** when a persisted profile exists (challenger #2). Otherwise, on a never-analysed first play only, today's refinement: prior → prefix → whole (`TrackLoudnessGain.h:17-24`). | EQ edits, Compare |
| output-state change (fold, ceiling) | — | protective re-plan at the re-establish (above) |

## 2. P1 — the pass and the true peak

**The kernel.**
- Against an exact FFT-sinc reference, the shipped 8×24 kernel never read above the reference on band-limited pulses.
- It is accurate to ≤ 0.04 dB only below about 19 kHz. On HF-only bursts at 48 kHz it errs +0.09 / −0.28 dB to 22 kHz (breaker N1).
- Through Apple's real converter (which is flat to 21.5 kHz from 44.1 kHz and to 23.5 kHz from 96/192 kHz), it under-reads the reconstructed peak by up to 0.22 dB (clipped 44.1), 0.56 (clipped 96), 0.34 (dynamic 96 — where the cap binds) and 1.01 dB (clipped native 48). Challenger #4, measured.
- An 8× kernel with **64 taps per phase** cuts those to 0.07 / 0.06 / 0.04 / 0.09 dB.

**Decision.**
- Analysis TP = max(64-tap reading, shipped reading), in a new analysis-only header (`Loudness/AnalysisTruePeak.h`). The limiter's own kernel is untouched.
- So the limiter's reading ≤ the field (the net sleeps), and the reconstructed peak lands at ≤ C_work + 0.09 dB < C.

**Source rate vs the limiter's view.**

| Source | R_limiter(48 kHz after SRC) − R_analysis(source rate) | Who measured |
|---|---|---|
| 44.1 kHz clipped masters | +0.02 … +0.53 dB (my Kaiser stand-in); **+0.12 … +0.65 dB, median +0.25** | breaker, through Apple's real converter |
| hi-res sources | negative, i.e. the source rate over-states (direction confirmed; the 4.6 dB magnitude is fixture-dependent) | — |

So peaks are measured after the engine's own converter.

**F1 — a fix to shipped code (blocker).** On the resampler route (any file not at 48 kHz, `AudioEngineBridge+EnhancedRestart.swift:93-95` → `+EnhancedResampler.swift:169-170`), the converter maps the file's layout into the graph's count-derived layout (`AudioFormatKit/MultichannelFormat.swift:33-67`). Measured with Apple's converter (breaker `chmatrix2`, re-run here):

| Source layout | What happens on the resampler route |
|---|---|
| `WAVE_7_1` | loses Rls/Rrs; slots 6/7 are silent |
| `MPEG_7_1_C` | loses its back pair |
| `AAC_5_1` | reordered (so roles from the file's labels are wrong) |
| 3/4/5/7-channel files | fall back to a stereo graph (`+Reconfigure.swift:110-118`): only L and R play; C, the surrounds and the LFE are dropped |

**The fix**, measured to map every channel identity (breaker `chmatrix3`, re-run here: `WAVE_7_1`, `WAVE_5_0_B`, `AAC_5_1`, `DiscreteInOrder|8` at 96 kHz):
- The graph's source-width format is **the file's own layout** (`DiscreteInOrder | N` when unlabelled), for every N in 1…8.
- The converter's output format is that layout at 48 kHz, so it converts the rate only.
- Roles are derived once from that layout (S1b). The analysis uses the same function for its converter.

Lane 2 owns the fix; VerifyAUGraph proves it (§10).

**Cost** (M4 Pro; the M1 Pro floor is unmeasured):
- Mastering SRC: 110× real time (44.1 kHz × 2), 32× (44.1 kHz × 6), 16× (96 kHz × 6), 6.1–6.3× (192 kHz × 8), 3.3× / 3.1× (352.8 / 384 kHz × 8 — breaker N11; about 75 s per 4-minute DXD track).
- Detectors: 14 channels at 48 kHz × (24 + 64 taps) is about 2.7× the first draft's multiply-adds, still a few percent of the pass. The exact pruning bound (max_p‖h_p‖₁ = 2.18) applies to both kernels.

## 3. P2 — album loudness

**The anchor is the founder's** (§12 F-1). Both candidates are computed from the stored record:
- **Pooled:** BS.1770 gating over all the album's blocks.
  - The ReplayGain 2.0 specification ("with all tracks concatenated").
  - libebur128's `ebur128_loudness_global_multiple` (`ebur128.c:1086-1159, 1178`).
  - rsgain's default (`src/scan.cpp:722-760`).
- **Loudest track:** the max of the members' L.
  - rsgain's `--album-aes77`.
  - Grimm 2017: "always the 'loudest track' version"; Tidal (per secondary sources).
  - Proposed outlier guard: tracks under 30 s are left out.

**Measured.**
- My synthetic albums: a power average sits up to 2.83 LU off pooled.
- The challenger's 100 synthetic albums (p5–p95 of each album's loudest song after its gain): pooled 3.7–4.1 dB wide, loudest-track 0.0 dB; albums whose loudest song plays > 3 dB over target: pooled 15–17 %, loudest-track 0 %.

**One trim per folded album (F2).** The trim is min(0, C_work − max over the members of TP_F[v]), with one v for the album (§5).
- Pooled: L_album = pool(L_F[v]) + trim.
- Loudest track: L_album = max(L_F[v]) + trim.
- P_album = max(max TP_N, max TP_F[v] + trim).
- Per-track trims are gone from Album scope. Measured by the breaker: they squashed a hot 5.1 album's 9.90 LU loud-to-ballad spacing to 3.02 LU.

**Payload and gate.**
- The sparse histogram is 0.9 KB median and 3.3 KB max per variant.
- Its pooling error is ≤ 0.005 LU typically. It is not a bound: a constant-level interlude within 0.05 LU of the album's relative gate gives −0.35 to −1.94 LU against the exact gate, because LufsMeter gates by bin centre (`LufsMeter.h:486-491`; breaker N4). The exact gate is equally discontinuous there, so the listener harm is nil. The test uses libebur128 in `EBUR128_MODE_HISTOGRAM`.
- Pooling is one pure function: `asLoudnessPoolHistograms` over (member, variant) pairs. The "album complete" rule lives in LevelingKit only (M6).
- The gate math stays once, in C++.

## 4. P3 — the trim, groups and the output change

1. **Track scope, seam across silence:** each track's own trim = min(0, C_work − TP_F[v]). The level stage protects P = max(TP_N, TP_F + trim) and levels L_F + trim (§1.3).
2. **Any group shares the whole plan** (B3). A group is Album scope, or a continuous gapless run.
   - g, the trim and the LFE variant are shared.
   - The trim is the group's worst.
   - v = Omit unless every analysed member decides Include.
   - Continuity has **one judge**: LevelingKit, from the persisted head/tail (both > −50 LUFS; unknown counts as sounding). *As built: −70 LUFS, BS.1770's silence gate — only silence is a gap (founder, 2026-10-30; §16, lane 3-A). A run is shared only between songs that join in play order (§16, the fix round).* Its verdict travels in the decision, and the engine's −ΔL group lock reads that flag instead of judging again.
   - At a continuous seam in an album not yet fully analysed, B inherits A's plan, and B's excess is metered by the backstop.
3. **The proof that both nets close** (given §6's bound). Effects peak ≤ TP_N + B_eff + g + G ≤ P + B_eff + g + G ≤ C_work. Fold peak ≤ TP_F + trim + B_eff + g + G ≤ C_work.
   - This holds because the EQ is identical per channel and the effects limiter's gain is common to every channel, so both commute with the matrix (from DSP principle).
   - **Crossfeed is not covered.** It sits between the gain and the limiter. bs2b's worst-case ℓ1 gain is +1.84 / +2.30 / +2.45 dB (architect M7, breaker N8). On 8 music-like fixtures it lowered TP by 0.50–2.17 dB. The claim is therefore narrowed to crossfeed off, with crossfeed-on rows in §10. Crossfeed's ℓ1 is not folded into B: that would turn every track down by about 2 dB.
4. **Fallback with no folded analysis:** trim = min(0, C_work − 20·log10(max-row Σ|gain|)). *As built: the row bound is over TP_N, an unknown TP_N as 0 dBTP — trim = min(0, C_work − (20·log10(max-row Σ|gain|) + TP_N)) (§16, lane 1).*

   | Layout | Bluetooth | Wired |
   |---|---|---|
   | 5.1 | −8.94 dB | −8.04 dB |
   | 7.1 at 0.5 surrounds | −9.93 dB | −9.03 dB |

**Worked example** (5.1, Bluetooth; computed without ε — every cap is 0.01 dB lower with it; reproduced exactly by the breaker):

| Step | Value |
|---|---|
| analysis | TP_N +0.23, TP_F +5.56 dBTP; L_N −6.50, L_F −4.10 LUFS |
| plan | trim −6.84 dB → P = +0.23 → L = −10.93 → g = −7.07 dB |
| EQ (B = +11.88, ΔL = +1.72) | C_cap = −6.31, G = −6.31, **T = −4.59 dB** |
| net readings | effects −5.50, backstop −9.82 dBTP: GR 0.0 |
| Compare | matched |
| EQ Off | output −18.00 LUFS |

## 5. P4 — the LFE

**Standards.** BS.775-4 Annex 7:
- The LFE is recorded at −10 dB and reproduced at +10 dB (p. 11).
- DVD-Audio and SACD code it for zero offset (NOTE, pp. 11 and 20).
- It "must therefore be considered as, at most, an enhancement" (p. 19).
- Fig. 5 (p. 15) folds it at +10 then −6 dB per side. That is **0.5** per side for the music convention and **1.585** (+4 dB) for the film convention.
- The challenger's measured k* (p4_lfe) keeps the room's LFE-to-mains balance on a headphone fold: 0.48–0.71 for music and 1.53–2.24 for film. So 0.5 is right on headphones too; the first draft's "1.0 matches the speaker level" was about absolute level, not balance.

**The include gain is the founder's** (§12 F-3). The pass measures v ∈ {0, 0.5, 1.0, 1.585}, so any choice needs no re-analysis.

**Statistics** (stored as `AsLfeStats`; measured, `proto/p4_lfe_v2.py`). All on the 20–120 Hz band at 500 Hz, in 400 ms blocks with a 100 ms hop, over **active** blocks (LFE band ≥ −50 dBFS):

| Statistic | Definition |
|---|---|
| lag, lagPeak | Global normalised cross-correlation of the LFE with the mains' sum over **±200 ms**: its best lag and peak. Catches delayed and uncompensated linear-phase copies (breaker F3). |
| coherentShare, medianR2 | One least-squares FIR per main (±20 ms) **centred on the lag**. Per block, r² = the squared correlation of the LFE with the prediction. It is **scale-invariant**, so automated sends and compressed copies still match. coherentShare = share(r² ≥ 0.8). |
| excess20 | Share of blocks whose unexplained power P_LFE·(1 − r²) is ≥ the mains' low-band power − 20 dB. |
| explainGain | Max over the 25–63 Hz third-octaves of the prediction's power over the **mains' plain sum**. A copy stays near 0 dB, whatever its filter or delay. A fit that must invert an authoring high-pass (bass moved out of the mains into the LFE) reads +38 dB or more. This is the challenger's bound, re-normalised: against the strongest single main, a plain L+R+C copy read +8.6 dB and was wrongly included. |

**Rule `foldDecideLfe`** (a pure C function; lane 2's; applied at **decision time** from the stored statistics, so its thresholds tune without re-analysis — M4):
1. Fewer than 50 active blocks (5 s) → Omit (unknown).
2. Copy-like (medianR2 ≥ 0.5, or coherentShare ≥ 0.4, or lagPeak ≥ 0.8) with explainGain ≤ +15 dB → Omit (a copy).
3. Copy-like with explainGain > +15 dB → Include (redirected bass).
4. coherentShare < 0.2 and excess20 ≥ 0.5 → Include (independent).
5. Else → Omit.

The asymmetry follows Annex 7: a wrong Include combs or doubles the bass, while a wrong Omit loses an enhancement.

**Measured: 117 / 117 correct** (my 12 cases × 3 seeds, the breaker's 22 cases × 3, the challenger's 5 × 3). Ranges:

| Case | Statistic | Range | Decision (margin) |
|---|---|---|---|
| plain, LR4, film, EQ'd, subset, delayed 15–38 ms, linear-phase 21/43 ms, polarity, compressed, automated sends | coherentShare | 0.98–1.00 | Omit (≥ +0.58) |
| | explainGain | ≤ +6 dB | (≥ 9 dB under +15) |
| kick-stem copy, kick and bass panned alike | coherentShare | 0.39–0.59 | Omit, via medianR2 0.75–0.81 (+0.25) |
| 6 tandem LPFs | lagPeak | 0.47–0.49 | Omit, via coherentShare 0.83–0.86 |
| copy + rare / frequent booms (mixed) | — | — | Omit (by the asymmetry) |
| independent sub layers, octave-down sub, bass only in the LFE | medianR2 | ≤ 0.08 | Include (+0.42) |
| | lagPeak | ≤ 0.19 | |
| | excess20 | ≥ 0.98 | (+0.48) |
| mains high-passed, bass redirected to the LFE | explainGain | +38 dB | Include (+23 dB) |

- The breaker's envelope-onset statistic is **not** used. It flagged independent sub layers that follow the bass rhythm (onset share 0.77–1.00 on two Include cases), and medianR2 separates the kick-stem copy without it.
- The challenger's residual include (LFE minus its predicted copy) is the better rule for mixed LFEs. It needs the fit's filter in the playing path, so it is an Engine-sprint candidate.

## 6. P5 — what may move, and the peak arithmetic

**Freeze.**
- §1.4 governs.
- With the persisted compact profile (§8), G and T are frozen too: the challenger measured 1.0–3.3 dB glides at every fresh start with an EQ on, plus 1.2–4.8 dB on songs with a quiet intro, all removed. The compact form predicts ΔL within 0.023 dB. *As built: the 1/24-octave form, within 0.014 dB (§16, lane 1-B).*
- The acceptance "one gain value for the whole of a track" is asserted on g and on G with the EQ Off and the EQ On (§10).

**Unknown TP** = 0 dBTP (RG2 "assume a peak level of 1.0"). It is raised to a tag's sample peak only above full scale, so an unanalysed or tag-sourced track is never raised.

**Silence and stings (F4).** No gated block, L ≤ −70, or a duration under 0.4 s is unknown loudness (the −5 dB rule). g ≤ +12 dB always: without it, a −60 dBTP hiss track would get +58.7 dB.

**The bound.** The closure with the EQ On rests on `TP_H ≤ TP + B_eff`, which is not a strict bound.

| Curve | Measured violation (worst fixture) | Who |
|---|---|---|
| Boost curves | up to **+1.56 dB** (a driven 808 sub under +5 dB on 20–125 Hz) | breaker F6 |
| Boost curves | up to +1.07 dB (square-ish bass) | mine |
| Cut-only, −12 dB at 100 Hz | up to **+0.69 dB** on a clipped master | breaker |

- **B_eff** = max(B, min(20·log10‖h‖₁, 0.7 dB)) ~~covers the cut-only cases measured (0.69 < 0.7)~~. The Realizer computes ‖h‖₁ on its idle refresh, as it does −ΔL. *As built (C5): the figures above are fixture-dependent lower bounds, and the verify pass measured +2.5 / +1.9 dB envelopes; the allowance covers no class of cases — known issue KI-LEV-07 (§16, lane 1).*
- The boost envelope stays a **known issue** until S14-lite's measured TP_H. Its acceptance reads "GR 0.0 with the EQ Off and crossfeed off; with the EQ On, GR ≤ the stated envelope" (§10).
- With Leveling **Off** (the default) and the EQ On, the cap binds on every hot master: a +0.5 dBTP master with B = +5 turns down 4.8 dB. That is the plan of record ("quieter by the turn-down").

**Seams.**
- Seam across silence: B's plan lands "as the engine counts it", up to one buffer late (KI-GAP-02), then glides 10 ms.
- Continuous seam: B shares the group plan, so nothing steps.
- Seek or restart: a fresh converter starts mid-waveform. Exclude the first 5 ms after it from GR acceptance; a fade-in belongs to the Engine sprint (breaker N10, architect N5).

## 7. P6 — Compare, the deletion, the golden masters

**Compare.**
- Compare = identity cascade at g + T. The mismatch is the predictor's error: ≤ 0.112 dB on the corpus and ≤ 0.14 dB on broadband music. On pathological curves it can be up to 2.8 dB past (`TrackLoudnessProfile.h:19-20, 36-38`; breaker N12).
- **Fold basis (F7).** Predicting on the 5.1-weighted basis misses the heard fold by **−1.05 dB** (LFE omitted), −1.15 dB (v = 0.5) and **−2.14 dB** (v = 1.0) on a +5 dB 20–125 Hz curve, and by +0.45 to +0.84 dB on +6 dB at 8–16 kHz (breaker, measured).
- So the persisted profiles cover every playable basis, and the planner's variant picks one. A never-analysed first play profiles on omit. On an Include track with the EQ on, that first play can miss by up to 1.09 dB, until the record lands. *As built: not met — a never-analysed folded first play profiles the decoded basis, about 1 dB off with the EQ on (review N15, a recorded deviation; KI-LEV-03; §16).*
- `EqIntent` gains `comparing` (`Realizer.h:88-92`), and the Realizer keeps the last EQ-on design for B_eff and ΔL.
- **The loudness model itself** (BS.1770 vs ISO 532-1 differ by 1.2–2.0 dB on bass presets; challenger #5) is a by-ear check before S14-lite's blind tests (§12 F-7).

**The deletion (M8).**
- Delete **`LoudnessModule` entirely**: the class, its worker, the kernel's construction (`DSPKernel.cpp:63, 71`), layout forwarding (`:110-112`) and the worker accessors (`:142-157`).
- Delete `LoudnessParams`, the makeup law, `loudnessContribution_` and its glide (`:39, 294-299, 348-351`), and the P2/blend calls (`:267, :316`).
- The parking tests point at `CausalLoudnessTap` alone.
- semgrep bans both names.
- The proof is the Intensity sweep 0 → 1 → 0 at ≤ 0.1 dB.

**`sizeof(TargetState)`.** 768 B before and after; used bytes go 744 → **728** (measured by both reviewers). `kMeasuredTargetStateBytes` (`TargetState.h:161`) holds. Re-run the assert as the recorded step.

**Golden masters.**
- `0xF0E1D4EF83763709` (`Tests/TestSupport.h:126`) runs P2 with `loudness.enabled = 0` (`:371`). Its makeup ramp is snapped to unity and stays on the identity fast path (`LoudnessModule.cpp:56-58, 128-131, 163-169`), so the hash is expected to hold. The run is the proof.
- **New** (architect N8): a stereo hash for the path that ships — P1, EQ Off, g = −7.07 dB.
- Tests that drive the makeup re-baseline or go: 16 references in the listed `.inc` files and `TestSupport.h`.

## 8. The seams, frozen

### S1 — the analyzer (lane 1)

The analyzer is a separate C++ object fed the engine-rate stream (a deviation from the plan check's stub; the panel agreed).

```c
// include/TrackLoudnessBridge.h
#define AS_TRACK_ANALYSIS_VERSION 1u  /* as built: an anonymous-enum constant, as AS_TRACK_PLAN_VERSION (§16). bump on: fold coefficients, LFE variant set, LFE statistics' definition,
   peak kernels or rate, the SRC or its output format, K-weighting, gates, histogram or profile form,
   role numbering, the role resolver, the count fallbacks. NOT on decision thresholds (planner-side). */
typedef struct AsTrackAnalyzer AsTrackAnalyzer;
enum { AS_FOLD_LFE_VARIANTS = 4 };       /* per-side LFE gain 0, 0.5, 1.0, 1.585 — one table, shared */
typedef struct { uint32_t activeBlocks; float lagMs, lagPeak, coherentShare, medianR2, excess20Share, explainGainDb; } AsLfeStats;
typedef struct {
  uint32_t version, channelCount; uint8_t roles[8];              /* AsChannelRole values */
  double sourceRateHz, peakRateHz, durationSeconds;
  double integratedLufs, truePeakDbtp;                            /* NaN when no gated block */
  double headBlockLufs, tailBlockLufs;
  uint8_t folds;
  double foldedLufs[AS_FOLD_LFE_VARIANTS], foldedTruePeakDbtp[AS_FOLD_LFE_VARIANTS];
  AsLfeStats lfe;
} AsTrackAnalysis;
AsTrackAnalyzer* asTrackAnalyzerCreate(double engineRateHz, uint32_t channels, const uint8_t* roles) AUDIODSP_C_NOEXCEPT;
bool asTrackAnalyzerFeed(AsTrackAnalyzer*, const float* const*, uint32_t channelCount, uint32_t frames) AUDIODSP_C_NOEXCEPT;
bool asTrackAnalyzerFinish(AsTrackAnalyzer*, AsTrackAnalysis* out) AUDIODSP_C_NOEXCEPT;  /* measures; decides nothing */
uint32_t asTrackAnalyzerHistogram(const AsTrackAnalyzer*, uint8_t variant, AsLoudnessBin* out, uint32_t capacity) AUDIODSP_C_NOEXCEPT;
uint32_t asTrackAnalyzerProfile(const AsTrackAnalyzer*, uint8_t basis, uint16_t* out, uint32_t capacity) AUDIODSP_C_NOEXCEPT;
/* both return the count required; nothing is written when capacity is short (architect N10) */
void asTrackAnalyzerDestroy(AsTrackAnalyzer*) AUDIODSP_C_NOEXCEPT;
```

The Swift `TrackAnalysis` (Codable) mirrors it, plus the identity, histograms, compact profiles and `analysedAt`.

### S1b — roles and the matrix (lane 1; the LFE rule is lane 2's)

**Roles (M3).**
- The C enum is `AsChannelRole` in `include/TrackPlanBridge.h`, with fixed numbers: Unknown 0, L 1, R 2, C 3, Lfe 4, Ls 5, Rs 6, Lb 7, Rb 8, Cs 9, Lc 10, Rc 11, Lw 12, Rw 13, Mono 14. A `static_assert` ties it to the C++ enum, and a Swift test checks the same.
- One pure C function, `asResolveChannelRoles(const AudioChannelLayout*, uint32_t channels, uint8_t* roles)`, is called once per file by **one Swift resolver** in AudioFormatKit (`ChannelRoles.swift`). *As built: in TrackLoudnessKit (`Sources/TrackLoudnessKit/ChannelRoles.swift`), since AudioFormatKit does not depend on AudioDSP (§16, lane 1-B).* Its result goes by value to the analyzer, the effects unit and the planner.
- Labels come from `CoreAudioBaseTypes.h:976-1064`.
- Count fallbacks follow RFC 9639's table for every count 1–8 (breaker N9): 3 L R C; 4 FL FR BL BR; 5 FL FR FC BL BR; 6 FL FR FC LFE BL BR; 7 FL FR FC LFE BC SL SR; 8 FL FR FC LFE BL BR SL SR.
- The planner uses fold numbers only if the record's roles equal the playback roles. Otherwise it uses the fallback trim.

**`makeBs775Fold(const ChannelLayout&, uint8_t lfeVariant)`** builds two output rows.

| Role | Into L′ / R′ | Source |
|---|---|---|
| L / R | 1.0 into its own side | BS.775-4 Table 2, p. 8 |
| C, Mono | 0.7071 to both | Table 2; Annex 5 §1.1 |
| the one surround pair (Ls/Rs, or Lb/Rb alone) | 0.7071 into its side | Table 2 |
| Ls **and** Lb present (7.1) | **0.5** each into its side, by default | Derived from Note 5 and Table 2; **BS.775-4 has no 7.1 row** (both reviewers confirmed). The alternative is §12 F-4. |
| Cs | 0.5 to both | derived |
| Lc, Lw | 1.0 into its side | judgment, unverified |
| Unknown | 0.5 to both | judgment |
| Lfe | the variant's gain to both | — |

`foldTrimDb(cWorkDb, tpDbtp, matrix)` = min(0, cWorkDb − tp); with NaN it falls back to the matrix's worst case. `foldDecideLfe` lives in lane 2's new `Spatial/FoldLfeRule.{h,cpp}`, with a C entry for the decision builder.

### S3 — decisions, the planner and the units (B1, B2, M2)

**The decision travels with the transport request that can make its token audible** (B2). The D41 ticket already orders those requests (`OnDeckGate`, `+Gapless.swift:66-80`).

```swift
// AudioPlaybackEngine — FakeEngine records every one
func startAudio(fileURL: URL, pureMode: Bool, startAt: Double, epoch: UInt64, leveling: TrackLevelingDecision) async throws
func setNextTrack(_ fileURL: URL?, ticket: OnDeckTicket, leveling: TrackLevelingDecision?) async  // D41 on-deck
func applyLevelingChange(current: TrackLevelingDecision, next: TrackLevelingDecision?)  // the listener's mode change
// As built (§16, the fix round): startAudio(…, leveling: LevelingStart)  — {decision, listen: .resume | .newPlay}
//                                applyLevelingChange(current: SongLeveling?, next: SongLeveling?) async — {url, decision}
func publishEQ(points: [Float], isOn: Bool, comparing: Bool)
// LevelingKit (pure): measured numbers only, scope-resolved; no ceiling rule, no C_work
public struct TrackLevelingDecision: Sendable, Equatable {
  public enum Mode: Sendable, Equatable { case off, leveled, unknownCut }
  public var mode: Mode; public var source: Source               // .analysis | .tags | .unknownCut
  public var continuousWithPrevious: Bool                        // the one continuity judge (§4)
  public var unfolded: LevelNumbers                              // L, TP_N — or the group/album's anchor and maxima
  public var folded: FoldedNumbers?                              // L_F[v], TP_F[v], TP_N (group: anchor/maxima), variant v
  public var roles: [UInt8]                                      // must equal playback's, else the fallback trim
}
```

**Defaults and delivery.**
- **No decision at audibility** means Off (g = 0) with the fallback trim, logged. That is a bug state, because every start and arm carries one.
- **Per-token leveling in `TrackEntry` is dropped**, so slot eviction cannot lose a decision (B2). The C-ABI mirrors the struct with NaN for unknown.
- **One `AsOutputState`** {transport, nominal rate, M, N} is assembled on `engineQueue` at `configureGraphForSource` and at every re-establish (M2). The view model hands the transport over as a value and never reads it on main. It is the planner's only input for C_work and the fold, and is published to the effects Realizer.
- The new or changed entries (`startAudio`, `setNextTrack`, `applyLevelingChange`, `publishEQ(…comparing:)`) join the stall self-test's `EntryProbe` as `architecture.md:259` requires for synchronous members.

**The spatial unit (M1).**
- `SpatialUnit {node, au}` sits under `stateLock`, with a borrow count and a teardown wait, mirroring `EffectsUnit` (`+Values.swift:7-13`, `+SharedState.swift:260-265`).
- `FoldParams` reach the render thread through a `TripleBufferSnapshot`, copied once per block and ramped per sample.
- The unit keeps its last `FoldParams` across an allocate. If N or M changed with no new set, it uses the matrix's worst-case trim, **never 0**.

### The store and the scheduler (lane 3; M5, M6, architect N7)

**The store.**
- The file is `AppDataLocation.directory/track-analysis.sqlite3` (`AppDataLocation.swift:26-28`), a GRDB `DatabaseQueue` separate from the library.
- Records are keyed by the full identity (path, size, mtime).
- Compact profiles are LRU-capped at 1 GB (rebuildable). Scalar records are about 4 KB each and uncapped.

**Rebuild and re-key.**
- **Rebuild:** another version, or a payload that will not decode, counts as not analysed and is overwritten. A broken file is recreated with GRDB's `erase()` on the open connection, or by closing it and deleting the main file plus its `-wal` and `-shm`. Never with `eraseDatabaseOnSchemaChange`. *As built: "broken" is SQLite's NOTADB or CORRUPT only — a busy or locked file is never recreated (§16, the fix round).*
- **Re-key on "Use this drive":** old root → new root, same size and mtime, called after a successful rebind.

**The scheduler.**
- **Horizon:** analyse the albums of the current slot and the next ~2 hours of queue (at least the next 3 albums), re-evaluated on each advance. This reconciles the founder's 2026-10-25 rule ("analysed once any of its tracks is queued; no library-wide sweep") for genre and artist plays (§12 F-8).
- At most 2 album jobs at `.background`. The current/next jobs run the engine-rate pass only when the store has no current-version record; otherwise they decode for the profile only, which is today's cost. *As built: the deadline rule, measured — `.utility` for a job due within 10 minutes, `.background` further ahead only while it still finishes in time (§16, lane 3-A).*
- File identities are read off main.
- **Prefetch:** the coordinator keeps the horizon's decisions in memory, prefetched off main on every queue change. At Play it waits at most 50 ms for a missing record, then uses `.unknownCut`.

**The analysis tool** (founder decision 4) is lane 1's executable `AnalyzeTracks`. It prints and writes nothing in `AppDataLocation`.

## 8½. Conditions from the verify pass (2026-10-26) — binding before W4

The verify pass (one fresh reviewer, after this revision) found the revision **ready to build with conditions**: 16 findings closed, 4 partly closed (F3, F6, F8, B4), none open. Its report was a working file of the sprint's session, not kept in the repo; its conditions are recorded here. The conditions, as settled by the coordinator and the founder:

- **C1 — mono, stereo and narrower multichannel outputs (settled).** F1's fix applies to sources of **3 or more channels**; mono and stereo keep today's graph formats. The founder's live listen on the XM4 (2026-10-26): a 44.1 kHz mono file plays in **both ears, centred** — macOS spreads it to both sides, so the offline left-only render does not happen on the device; the +3.01 LU mono correction (F8) stands. The first draft's rule for a device with fewer channels than the file but more than two (2 < M < N, e.g. 7.1 on a 5.1 output) is restored: **fold to stereo, never truncate**; 7.1 → 5.1 waits for the Engine sprint.
- **C2 — the saved −ΔL profile at audibility (lane 1, step 1, before S1 / S3 freeze).** The decision that travels with the start and on-deck requests also carries what the planner needs to know −ΔL at audibility when a stored compact profile exists (the profile's key, or the off-thread value it implies) — so a fresh start of an analysed track never glides (NI-1). Add a **90th-percentile r²** field to `AsLfeStats` now, in version 1 of the analysis, so C4 never forces a re-analysis.
- **C3 — W4 ownership, the five gaps (coordinator).**
  1. The view-model call sites that pass `leveling:` to `startAudio` / `setNextTrack` (`AudioViewModel+Playback.swift`, `+AutoAdvance.swift`): **lane 1** in W4, passing a stub decision; lane 3 fills the decisions in W5.
  2. `OnDeckEngineModel.swift` and the seam / seek tests that call `setNextTrack`: **lane 1** (the signature's owner).
  3. The bridge's stored state lane 1 needs in `AudioEngineBridge.swift` (lane 2's file): the **coordinator's commit 0** adds one stored `leveling` property of a type lane 1 owns in its own file (`AudioEngineBridge+Leveling.swift`); lane 2 never touches it.
  4. The ~10 test files the `LoudnessModule` deletion touches: **lane 1** (the deletion's owner).
  5. Where `TrackLevelingDecision` lives in W4: the **coordinator's commit 0** creates the `LevelingKit` target holding only the struct (lane 1 owns it in W4; lane 3 adds the logic in W5).
- **Deviations to reconcile in the plan check** (adds to §9's list): the S3 contract changed shape — the decision rides `startAudio(…, leveling:)` and `setNextTrack(…, leveling:)` plus `applyLevelingChange(current:next:)` and `publishEQ(…, comparing:)`, replacing the plan check's `publishTrackLeveling(_:for:)`.
- **C4 / C5 (in the build, lane 1 / lane 2):** tighten the LFE include test with the p90 r² (it separates a kick-stem copy down to a kick 6 dB under the bass); add the kick-balance sweep and the 60 Hz high-pass case to the LFE tests; log the remaining case (a copied stem ≥ 10 dB under the bass) as a known issue; `AnalyzeTracks` prints the LFE statistics for the founder's surround albums. Restate F6's figures as fixture-dependent lower bounds (drop "the allowance covers the cut-only cases"); the known-issue tests log gain reduction instead of asserting one fixture's number, and the real figures are measured on the founder's hot masters. Add the Leveling-mode-change test row (NI-4); fix NI-7 (the unknown-loudness rule uses a known peak); size lane 1 at the start of W4.

## 9. W4 ownership (B4) and build order

**Ownership, one owner per file in W4.**

| Owner | Files |
|---|---|
| **Coordinator, commit 0** | `Package.swift` (TrackLoudnessKit → AudioFormatKit and GRDB; empty `AnalyzeTracks` target); the test registries' hooks for the new `.inc` files (lane 1: `LevelPlanTests.inc`, `AnalyzerTests.inc`; lane 2: `FoldTests.inc`, `LfeRuleTests.inc`); an empty `include/SpatialBridge.h` included from `DeviceBridge.h`. |
| **Lane 1** | `Loudness/*` (`LoudnessModule.*` deleted); `Planning/TrackPlan.*` (new); `include/{TrackLoudnessBridge,TrackPlanBridge,ChannelLayout,TargetState,AudioUnitRegistrationBridge}.h`; `Spatial/FoldMatrix.h`; `AudioEngine/{Realizer.*,AUAudioUnit.mm}`; `DSPKernel.*`, including S2's atomic and its C-ABI (moved from lane 2: one owner); `Tests/{DSPKernelNullTest.cpp,TestSupport.h,MultichannelTests.inc}`; `TrackLoudnessKit/*` minus the store; `AudioFormatKit/ChannelRoles.swift` (new); `+TrackLoudness.swift`, `+EQControl.swift`, and the decision and planner hunks of `+Playback.swift` / `+Gapless.swift`; `AudioPlaybackEngine.swift`, `FakeEngine.swift`, `SheetEngine.swift`; the `EntryProbe`; `AnalyzeTracks`. |
| **Lane 2** | **F1:** `AudioFormatKit/MultichannelFormat.swift`, `+Reconfigure.swift`, `+ChannelLayout.swift` (it also assembles `AsOutputState`), `+EnhancedRestart.swift`, `+EnhancedResampler.swift`. **Fold:** `Spatial/{SpatialRenderKernel.*,FoldLfeRule.*}`, `AudioEngine/SpatialRendererAU.mm`, `include/SpatialBridge.h`. **Spatial handle and S2's Swift side:** `AudioEngineBridge.swift` (spatial handle, `snapshot()`), `+Graph.swift`, `+Values.swift`, `+SharedState.swift` (spatial borrow), `+Lifecycle.swift` (spatial teardown), `EngineSnapshot.swift`, `SignalPathInfo.swift`. **Tests:** `VerifyAUGraph/*`, `SpatialTests.inc`, `FoldTests.inc`, `LfeRuleTests.inc`. |
| **Lane 3 (W5)** | `LevelingKit/*` (decisions, Auto, album anchor and completeness, continuity, groups, `foldDecideLfe` calls); the store; the scheduler; the coordinator (`AudioViewModel+Leveling.swift`); SettingsKit; the UI; the rebind re-key call. |

**Order.**
- **Lane 1:**
  1. The seam headers (`TrackPlanBridge.h`: roles, `AsOutputState`, the decision and plan structs, the LFE variant table, `AsLfeStats`; the planner's signature as a stub; `FoldMatrix.h` with the full table; the version), the Swift fixtures, no-op engine members, and S2's atomic.
  2. Roles and the one resolver.
  3. The analyzer: two kernels, folds × 4, histograms, LFE statistics, compact profiles, prefix before the SRC. It consumes lane 2's F1 format function.
  4. The planner body and the `TrackLoudnessGain` split (`levelDb_` / `neutralDb_`, the frozen persisted profile, B_eff, Compare, snap, repeat).
  5. The bridge: decisions with start and arm, the planner at audibility, both units in one turn.
  6. The deletion, the size assert and the golden masters.
  7. Oracles and `AnalyzeTracks`.
- **Lane 2:**
  1. **F1** and its VerifyAUGraph proof (day 1–2; lane 1's step 3 needs it).
  2. The `SpatialUnit` handle, the snapshot and keep-across-allocate.
  3. Matrix, variant gain, trim, the backstop and its GR atomic.
  4. `FoldLfeRule` with §5's thresholds and fixtures.
  5. S2's Swift side.
  6. VerifyAUGraph M == N bit-exact.

**Deviations from the plan check**, for the coordinator to reconcile in plan check §3–§4:
- g is computed in the C++ planner, not LevelingKit (architect N9).
- The store and scheduler move to lane 3.
- S2's engine end moves to lane 1.
- The analyzer is a separate object (S1).

## 10. Proving measurements (rig · tolerance)

| Acceptance line | Rig | Tolerance |
|---|---|---|
| gain to −18 (Track, Album; stereo, folded, **mono**) | C++: decision → planner → apply → libebur128 (`_multiple`; `EBUR128_DUAL_MONO` for mono) | 0.2 LU where the cap allows |
| TP field | C++: ≥ the limiter's own reading on the same 48 kHz samples (always); vs an exact FFT reference on band-limited fixtures; vs libebur128 only below 20 kHz | ≤ 0.1 dB; ≤ 0.3 dB |
| F1 channel identity | VerifyAUGraph: a tone per channel, layouts `WAVE_7_1`, `MPEG_7_1_C`, `AAC_5_1`, `WAVE_5_0_B`, 3/4/5/7-channel labelled, `DiscreteInOrder|5/8`, at 44.1 / 48 / 96 kHz | each input on its own slot, ±0.05 dB, others < −80 dB |
| one plan per token (B1) | C++ + FakeEngine: seek, resume, device move after a mid-track landing; both units receive bit-identical plans | g and trim constant (100 samples); bit-identical |
| decision ordering (B2) | FakeEngine: every start and arm carries a decision; C++: audibility with none gives Off, held | exact |
| group (B3, F2) | C++ / LevelingKit: late profile at a gapless seam, EQ Off; differing LFE stats in a group; a folded album with silence seams | g constant; one variant; spacing = source fold's ±0.1 LU |
| output change (F5) | C++: unfolded → folded and wired → Bluetooth mid-track | backstop and effects GR < 0.01 dB |
| silence and stings (F4) | C++: digital zero, −75 LUFS noise, a 300 ms file | unknown rule; g ≤ +12 |
| net GR, leveled corpus | C++ at 48 kHz; `AnalyzeTracks` through the real converter on the founder's files; **crossfeed on and off, each preset** | < 0.01 dB with crossfeed off; crossfeed rows logged |
| T with the EQ On | C++: music-like −9 LUFS fixture with a bass preset; known-issue fixtures (808, cut-only) | music-like < 0.01 dB; the known-issue fixtures ≤ their stated envelope |
| Compare | C++: stereo and folded fixtures, persisted profiles | ≤ 0.2 dB |
| no motion inside a song | C++: g and G sampled 100× on analysed tracks, EQ On | max − min = 0 |
| LFE rule | `LfeRuleTests.inc`: §5's 39 cases × seeds | the table's decisions |
| matrix | C++: C-only −3.0 dB per side; L = R = C +4.6 dB; stereo-in-5.1 null | ±0.1 dB; bit-exact |
| spatial re-allocation (M1) | C++ / VerifyAUGraph: re-allocate mid-play | trim unchanged; never 0 on an unknown layout |
| backstop | `AnalyzeTracks` over the founder's surround albums; VerifyAUGraph M == N bit-exact with the backstop bypassed | GR < 0.01 dB; bit-exact |
| AGC gone | C++ Intensity sweep; semgrep `LoudnessParams`, `LoudnessModule` | 0.1 dB; 0 hits |
| persistence | store round trip, version bump, undecodable payload, `erase()`, re-key; VerifyLibraryStore: no loudness column | exact |
| golden masters | the stereo hash; the new P1 leveled hash; fresh-launch MD5 | bit-exact |

GR acceptance excludes the first 5 ms after a seek or start (§6).

## 11. Known issues to log at close

*As built: logged 2026-10-30 in [known issues](../../product/known-issues.md) — the boost envelope, crossfeed and the
seek-start overshoot as KI-LEV-07; the hot omitted LFE capping g under Known limitations (peak-bound tracks); M == N by
file order as KI-MC-05; F1 closed with KI-MC-02.*

- **The boost-curve envelope** of `TP + B` (+1.56 dB measured) → S14-lite's measured TP_H.
- **Crossfeed** may add up to +2.45 dB worst case before the limiter on stereo files.
- **A hot omitted LFE caps g** (the linked effects limiter, breaker N7).
- **The seek-start overshoot** (≤ 5 ms) → Engine sprint.
- **M == N on a multichannel device routes by file order**, not device order → Engine sprint's layout owner.
- **Before F1:** non-48 kHz 7.1 files lost their back pair, and 3/4/5/7-channel files played only L and R. This is fixed in this sprint; log it as fixed.

## 12. For the founder (plain options; recommendation first)

**F-1. How an album's level is set** (Album mode, and Auto when a neighbour is from the same album).
- **Recommended — the album's loudest song sits at −18.** Every album's loudest moment lands at the same level, and soft songs stay as soft as the album made them. You will never hear one album's big single jump out above the others. The cost: albums with many quiet songs play quieter on average, about 3–6 dB for "one loud single among soft songs" albums. This is what AES77 and Tidal do, and what Grimm's research recommends.
- **Alternative — the album's average (all songs measured as one) sits at −18.** This is ReplayGain's and Apple's way. Quiet-song albums sound fuller, but an album with one loud single plays it 3–6 dB above other albums' loud songs (15–17 % of synthetic albums put their loudest song > 3 dB over target).
- Either can be switched later without re-measuring.

**F-2. What "Auto" means in shuffle.**
- **Recommended — keep today's rule:** album level when the song next to it is from the same album, else each song at its own level. The leveling story (US-R1F-10) asks for "albums and shuffled songs to sit at one level".
- **Alternative:** album level always, once the album is measured. In Grimm's blind test of a shuffled list, 71 % preferred it. You already get this by choosing "Album" instead of "Auto".

**F-3. How loud the LFE (".1") is when a surround track includes it.** Decided by your listen on the two albums.
- **Recommended — −6 dB per side.** This is the standard's figure for music discs (SACD, DVD-Audio). It keeps the sub-to-main balance the mixer heard, on headphones too.
- **Full (0 dB) per side.** The plan's wording. About 6 dB more sub-bass; the rumble can feel heavy.
- **+4 dB per side.** The standard's figure for film-convention discs (DVD-Video, many Blu-rays). It only fits those, and is boomy on music discs.
- All three are measured, so your choice needs no re-analysis. If one of your two albums is a Blu-ray or DVD-Video rip, include the +4 dB option in the listen.

**F-4. 7.1 files: how much of the back and side surrounds goes into stereo.**
- **Recommended — half each (−6 dB).** Folded like a 5.1 file when the mix spreads one surround sound across both speakers.
- **Alternative — −3 dB each.** About 1 dB more room sound on 7.1 mixes whose four surrounds carry separate ambience.
- These files are rare; a quick listen on one 7.1 file is enough.

**F-5. The first play of a surround track nobody has measured yet.**
- **Recommended — play it quieter and clean** until it is measured: up to about 9 dB under how it will play once measured. The next play is exact, and the badge reads "5.1 → stereo · measuring". *(Decided as recommended, 2026-10-26. As built: up to about 10.5 dB under on Bluetooth, the founder accepting it on 2026-10-30 — the unknown rule's peak cap adds −1.28 dB to the worst-case trim; §16.)*
- **Alternative — play it at level** and let the safety limiter catch the peaks; it may pump on loud passages.

**F-6. A song with unknown loudness** (not yet measured, no tags).
- **Recommended — keep the fixed −5 dB for now.** It is rare, since albums are measured as soon as they are queued. Revisit it with the numbers from your own library once the analysis tool runs.
- **Alternative — the typical cut of your already-measured songs** (likely nearer −10 dB for modern albums).

**F-7. A ten-minute ear check before the S14-lite blind tests** (not this sprint). Match Compare to EQ-on by ear on two bass presets and one cut. Two standard loudness models disagree by 1–2 dB on bass boosts, and your ear decides which one Compare should follow.

**F-8. A clarification of your 2026-10-25 rule** ("analyse an album once any of its tracks is queued; no library-wide sweep").
- **Recommended — only albums within the next ~2 hours of the queue are analysed,** re-checked as it plays. Otherwise "Play" on a genre or artist would analyse hundreds of albums at once: a library sweep in all but name, with fan noise and battery drain.

**F-9. A never-measured song with an EQ on:** start at once (**recommended**). The level settles within the first second on that first play only. The alternative is to start 0.2 s late so it doesn't.

## 13. Engineering questions still open

1. CPU on the M1 Pro floor with 192 kHz × 8 and DXD albums. Measure at lane 1 step 3. Stop rule: if a 4-minute track takes over 2 minutes, drop to 1 album job. *As built: measured on an M4 Pro (the stop-rule table, §16); it tripped at `.background` on hi-res multichannel, which the deadline rule answers. The M1 Pro floor stays unmeasured (KI-LEV-10).*
2. The mono upmix on the real device path (VerifyAUGraph), not only offline.
3. The compact profile's 1/12-octave grid needs `bandsPerOctave` to become a field of `TrackLoudnessProfile`. If that proves invasive, use 1/24-octave (about 289 KB per 4 minutes, error 0.010 dB). *Settled: 1/24-octave (§16, lane 1-B); `bandsPerOctave` is a field, and 1/12 stays supported.*
4. The AES77 text was not opened; its rule is taken from rsgain's code and help, Grimm 2017, and TD1008 summaries.

## 14. Changes since the panel

| Finding | Change |
|---|---|
| **Breaker** | |
| F1 | Shipped-code fix (lane 2): graph format = the file's layout, N 1–8; converter rate-only; one role resolver; VerifyAUGraph proof (§2, §9, §10) |
| F2 | One trim per album and per group; S3 separates group numbers from the variant (§3, §4, §8) |
| F3 | LFE statistics v2: lag search, scale-invariant shape match, `bestLag` persisted; Include made harder. **Adapted:** the onset statistic was rejected (it misfires on rhythm-following sub layers, measured); medianR2 covers the kick-stem copy. 117/117 (§5) |
| F4 | No gated block or < 0.4 s → unknown rule; g ≤ +12 dB (§1.3, §6) |
| F5 | Protective re-plan with the frozen g at an output change (§1.3) |
| F6 | Honest envelope (+1.56 / +0.69); cut allowance B_eff; acceptance reworded; known issue (§6, §10, §11) |
| F7 | Magnitude corrected (−2.14 dB); persisted profiles for every basis; first-play Include residue stated (§7) |
| F8 | Measured: mono plays dual mono at 0 dB per side; the planner adds +3.01 LU; mono oracle row (§1.2, §10) |
| N1 | Kernel claim reworded; TP tests vs an exact reference, libebur128 only below 20 kHz (§2, §10) |
| N2 | C_work −1.282 / −0.380; the backstop computes it identically (§1.1) |
| N3 | Used bytes 728 (§7) |
| N4 | Pool error stated as typical, with the knife-edge; test in histogram mode (§3) |
| N5 | 7.1 coefficient → F-4, with both correlation cases |
| N6 | Fourth variant, 1.585 (§1.2, §5) |
| N7 | Known issue (§11) |
| N8 | Crossfeed narrowing + rows (§4, §10) |
| N9 | RFC 9639 counts 1–8 (S1b) |
| N10 | Seek exclusion; fade-in → Engine sprint (§6) |
| N11 | DXD cost rows (§2) |
| N12 | Predictor limits stated (§7) |
| N13 | Analytic fold rows (§1.2) |
| **Challenger** | |
| 1 album anchor | → **founder F-1** (recommended: loudest track). Histograms kept, so both stay computable. The "drop the histograms" simplification is **rejected** until the founder chooses |
| Auto in shuffle | → **founder F-2** |
| 2 persisted −ΔL profile, freeze G | **Adopted** (§1.4, §6, §8); the start-delay option → F-9 |
| 3 LFE gain bound, k = 1.58 | **Adopted, re-normalised** to the mains' sum at +15 dB (the strongest-main form wrongly included plain copies, measured +8.6 dB); 1.585 measured; include gain → F-3 |
| 4 64-tap analysis kernel | **Adopted:** max with the shipped reading (§2) |
| 5 Compare loudness model | → F-7 (before S14-lite) |
| 6 unknown fallback | → F-6 |
| 7–8 fold, trim, 7.1 row, glide | kept |
| TP oracle vs exact | **Adopted** (§10) |
| **Architect** | |
| B1 | One pure C++ planner, called once by the bridge, same value to both units, no-op on repeats (§1.3, §8) |
| B2 | Decisions travel with start and arm; "no decision" defined; per-token slots and "kept for next play" dropped (§8) |
| B3 | `levelDb_` / `neutralDb_` split; one continuity judge; groups share g, trim, LFE (§4, §9) |
| B4 | W4 ownership table; coordinator commit 0 (§9) |
| M1 | `SpatialUnit` handle, snapshot, keep across allocate, never trim 0 (§8) |
| M2 | One `AsOutputState` on `engineQueue`; `EntryProbe` additions (§8) |
| M3 | C role enum, one resolver, roles in the version list (S1b, S1) |
| M4 | Statistics stored; decision at plan time; variant index (§5, S1) |
| M5 | Horizon (F-8), `.background`, skip the pass when stored, identities off main, prefix before the SRC (§8) |
| M6 | `erase()` or a sidecar-aware delete, undecodable payload → re-analyse, pure pool, the tool writes nothing (§8) |
| M7 | Crossfeed (§4, §10, §11) |
| M8 | `LoudnessModule` deleted entirely (§7) |
| N1 | 728 B |
| N2 | `groupKey` dropped |
| N3 | Repeat = new play |
| N4 | Snap at a fresh start |
| N5 | Seek exclusion |
| N6 | TP unknown on a rate mismatch |
| N7 | Re-key on rebind; LRU cap |
| N8 | New golden master |
| N9 | Deviation flagged (§9) |
| N10 | C-ABI typedef and buffer rule |
| N11 | Mode change re-arms next |
| N12 | Prefix before the SRC |
| N13 | Superseded by F5 |
| Pre-mortem 1–3 | Covered by B1–B3 |
| Pre-mortem 4 | Covered by M5 |
| Pre-mortem 5 | → F-5; the unknown rule no longer stacks −5 dB on the fallback trim (§1.3) |

## 15. Prototype index

The prototypes ran in the drafting session's scratch folder and are not kept in the repo; their results are quoted in the sections above, each with its fixture. The names, for reference (Python, run from `proto/`):

**First draft:**
- `common.py`
- `p1_*`, `p2_*`, `p3_bound`, `p35_chain`
- `p4_lfe`, `p4_lfe2`, `p4_lfe3`
- `p6_*`
- `bench/{tpbench.cpp, srcbench.swift, sz.cpp}`

**Revision:**
- `proto/p4_lfe_v2.py` and `.out` (the LFE rule on all three fixture sets).
- `bench/mono.swift` (F8).

**The reviewers' prototypes**, cited by finding (the breaker's and the challenger's own scratch folders, not kept either).

## 16. As built (2026-10-30)

What the build settled, and where it departed from the sections above. The reasons come from the lanes' reports, the
code review (findings B, S, N) and the break-it (HIGH, MEDIUM, LOW; tests BI-S…); the founder's decisions are the
[sprint record](../../sprints/r1-1b-record.md)'s. What stays open is in [known issues](../../product/known-issues.md).

### Lane 1 — the plan and the planner

- **C5, restated.** F6's figures (§6) are fixture-dependent lower bounds — the verify pass measured +2.5 / +1.9 dB
  envelopes — so "B_eff covers the cut-only cases measured" is dropped. LP-21 logs gain reduction instead of asserting
  one fixture's number (0.371 dB on a clipped master under a −12 dB cut at 100 Hz on Bluetooth); the real figures come
  from the founder's hot masters. Known issue KI-LEV-07.
- **The unknown rule is `min(0, −5 − trim, C_work − P)`, always** (`Planning/TrackPlan.cpp:129-134`): an unknown peak
  counts as 0 dBTP, so the cap binds. An unmeasured 5.1 fold on Bluetooth therefore plays at trim −8.94 plus g −1.28 =
  **−10.22 dB**; on the corpus first plays land 4.8 to 10.5 dB under their measured plays (lane 3-A; file 34 the
  most) — "the limiter never acting" (decision 3) holds, and "up to ~9 dB" (§12 F-5) reads up to ~10.5 dB on
  Bluetooth. The founder accepted it, 2026-10-30. On a lossy decode above full scale
  the effects limiter still acts on that one play (KI-LEV-01).
- **The fold fallback's row bound uses TP_N** (an unknown TP_N as 0 dBTP): the matrix's worst row over the N-channel
  peak (`foldPeakDbtp`, `TrackPlan.cpp:149-170`), not 0 dBTP alone.
- **The version constants** `AS_TRACK_ANALYSIS_VERSION` and `AS_TRACK_PLAN_VERSION` are anonymous-enum constants (value
  1), not `#define`s: clang-tidy's macro rules.
- **`setCurrentTrack(token, seam)` became `applyTrackPlan(token, event, plan, continuous)`**
  (`AudioEngine/Realizer.h:149`): the event (fresh start, gapless seam, mode change, output change) picks the glide;
  `continuous` is the one judge's verdict, carried in the decision.
- **The deletion** (§7) as planned: `sizeof(TargetState)` 768 B before and after, used bytes 744 → 728; LP-22's
  Intensity sweep 0 → 1 → 0 at −25.565 / −25.564 / −25.565 LUFS (red before the deletion: the AGC lifted Intensity 1 by
  4.6 dB); the stereo golden master held, and LP-23 pins the leveled P1 path.
- **For S17, when Intensity returns:** the cap uses the P1 path's ceiling (−0.1 dBTP wired, the EQ-only ceiling);
  P2 and the blend limit at −1 dBTP, so the cap must take the ceiling of the path that plays once they are reachable.
  Intensity is hidden and held at 0 in R1.1, so nothing plays them today.

### Lane 1-B — roles and the one analysis pass

- **The persisted −ΔL profile is on the 1/24-octave grid, every block up to 1,200 (two minutes), then every 2nd,
  4th, … block** (the profiler's own decimation), binary16 of the power × 2^10 (`kCompactPowerScaleLog2`; binary16
  alone flushes quiet bands to zero). The design's 1/12-octave form on non-overlapping blocks missed today's full
  profile by up to 0.22 dB (AN-P1, over 5 programmes × 8 curves × 20 / 120 / 240 s); the built form is within
  **0.014 dB** on all of them, exact under two minutes, at most 1,200 × 247 × 2 B ≈ 593 KB per basis whatever the
  length. A cap of 600 measured 0.023 dB, the design's bound exactly; 1,200 keeps margin. `bandsPerOctave` is a field
  of the profile; the predictor still reads a 1/12 profile on its own grid. §13.3 is settled at 1/24.
- **`ChannelRoles.swift` lives in TrackLoudnessKit, not AudioFormatKit**, which has no AudioDSP dependency.
- **The analysis true peak also takes the sample peak**: max(8×24, 8×64, |x|). Both kernels' phases sit 1/16 sample off
  the input grid, so a reconstruction through every sample is a floor neither guarantees; it only ever raises the
  reading (still ≥ the limiter's own, AN-T2). A digital-silence peak reads −200 dBTP.
- **BS.1770-5 Table 5's weights for 7.x**: the side pair 1.41, the back pair 1.0 (M±135), Cs 1.0, Lw / Rw 1.41. The
  live tag table weighs the back pair 1.41 (KI-LEV-08).
- **`sourceRateHz` is NaN from C**: the C analyzer sees only the engine-rate stream; the Swift pass fills it.
- **Two shipped bugs fixed on the way**: `AVAudioFile.framePosition` — the getter too — is fatal on a FLAC with blocks
  under 192 samples, so the pass counts the frames it reads (KI-PB-22's first half); and E-AC-3, AC-3, ffmpeg-made MP3
  and Vorbis deliver a few hundred frames fewer than `length`, then throw, so a short read now ends the stream (the old
  analyzer published only its 25 s prefix for such a track).
- **§13.1, measured** (an M4 Pro, release build, one job; a 4-minute track):

  | Material | Default QoS (P-cores) | `.background` (E-cores) |
  |---|---|---|
  | 44.1 kHz stereo (SRC) | 4.2–4.4 s | — |
  | 48 kHz stereo | 0.9 s | 4.3 s |
  | 48 kHz 5.1 | 4.4 s | 24.0 s |
  | 44.1 kHz 5.1 (SRC) | 11.7 s | 53.7 s |
  | 48 kHz 7.1 | 5.2 s | 26.5 s |
  | 192 kHz × 8 (synthetic, dense) | 59.7 s | 225.5 s |
  | 352.8 kHz × 5 (DXD) | 62.7–65.2 s | 227–264 s |

  At default QoS everything is under two minutes (the Mastering converter dominates; the analyzer itself is about 5 s
  for a 7.1 track). At `.background`, hi-res multichannel takes 3.8–4.4 minutes: the stop rule trips with one job. The
  M1 Pro floor (expected ~1.5–1.7× the default figures) is unmeasured. Lane 3-A's deadline rule answers it (below).
- **Conformance**: 61 of 61 EBU Tech 3341 / 3342 and ITU-R BS.2217 signals with an integrated or true-peak verdict pass
  (integrated within ±0.1 LU, worst 0.048; true peaks within +0.2 / −0.4 dB); 19 of 19 voice files resolve every
  channel's role to its label's. AC-3 / E-AC-3 differ from ffmpeg's figures by its dynamic-range control, which Apple's
  decoder does not apply; Apple's MP3 decoder clamps at 0 dBFS.

### Lane 2 — F1 and the fold

As §2 (F1), §4 and §5 designed, with these specifics: both custom units are one `GraphUnit` each (node and
`AUAudioUnit`), reached through `effectsNode` / `withEffectsAU` and `spatialNode` / `withSpatialAU` with one counted
borrow; `FoldParams` reach the render through a `TripleBufferSnapshot` and are kept across an allocate, played only at
the width they were made for (silence otherwise — never truncation); the backstop is the effects chain's
`LimiterModule` reused unchanged, its ceiling held at or under −0.1 dBTP so it never bypasses on the fold path, and its
meter reads output ÷ the limiter's input delayed by its look-ahead. The LFE rule carries C4's `p90R2 < 0.3` gate on
rule 4; its limits on the measured cases are KI-MC-04.

### Lane 3-A — the rules, the store and the scheduler

- **The continuity judge: only silence is a gap.** Two songs are continuous unless an edge block is below **−70 LUFS**,
  BS.1770's absolute gate (`LevelingRules.silenceLufs`), replacing §4's −50 (founder, 2026-10-30). On the live show
  (corpus 9i) applause and room sound ran through three of four pauses, and at −50 Track mode stepped 6.87 dB inside
  the music at the 34:15 dip; at −70 the two silence verdicts sit at near-digital silence. The cost: two separate
  recordings with room tone at their edges join one run (0 dB on corpus 9g).
- **The scheduler's QoS rule** (`AnalysisQoS`), replacing §8's "at most 2 album jobs at `.background`": a job due
  within 10 minutes — the playing album included — runs at `.utility`; one further ahead at `.background` while it
  would still finish there before it is due, else at `.utility`; two jobs at once, one when either of the two most
  urgent would run under 2× real time (§13.1's stop rule). The work is estimated from per-class rates measured on an
  M4 Pro, replaced by a job's own measured speed once it has one. Measured: no playback, UI or resampler deadline
  misses with two DXD jobs at `.utility`; a four-album horizon, hi-res included, done in 314 s (coordinator,
  2026-10-30).
- **Tags:** a gain tag that implies a loudness outside −70…0 LUFS is ignored, and tags never raise a track (the
  unknown peak counts as 0 dBTP).
- **Track mode:** a run of songs that join without a pause shares its own loudest member's level, not the whole
  album's (founder, 2026-10-30); when the run is the album the two are the same.
- **The store**: one record per path, keyed by (path, size, mtime); profiles are rows of their own, LRU-capped at 1 GB
  per basis, so a 5.1 track's unplayed fold variants go first.

### The fix round (after the review and the break-it)

- **§1.3 and the resume rule.** A start says whether it **resumes** the listen or is a **new play**:
  `LevelingStart {decision, listen: .resume | .newPlay}` (`AudioPlaybackEngine.swift:82`), chosen from the start's
  `resumeFrom`. A resume (Pause → Play, a move to another device) keeps the decision playing, and the bridge keeps the
  audible plan whatever the resume carries — the level never steps mid-song, even when the analysis landed during the
  pause — and re-sends the plan's fold half, snapped (a resume re-configures the graph, which re-publishes the
  layout's worst-case fold: review B2, Pause → Play had dropped a measured 5.1 track by 8.94 dB); if the output changed
  since the plan was made, it first re-plans protectively (F5). A new play — Play after Stop or after the queue ended,
  Previous restarting the song, Repeat One — is decided afresh and planned afresh, the same token too; a gapless seam
  is always a new listen. Token 0 is never "the same track", and a saved profile is final only for the play it arrives
  with (N2). The loudness readout starts afresh on a new play. Proof: BI-S06, BI-S07, LB-2 (its new form),
  FOLD-BADGE-02, LEVEL-VM-14; on the corpus, file 34 replays after Stop at its measured level (−30.0 LUFS over its
  first 20 s, not −40.5) and keeps it across Pause → Play (break-it MEDIUM-1, coordinator 2026-10-30).
- **§S3's signatures.** `startAudio(…, leveling: LevelingStart)`; `setNextTrack(…, leveling:
  TrackLevelingDecision?)` unchanged; a mode change's decisions name their songs, `SongLeveling {url, decision}`, and
  `applyLevelingChange(current: SongLeveling?, next: SongLeveling?)` is **async**: `current` goes to the audible track
  (or a start not yet audible), `next` to the armed pick (or to the audible track if a seam already made it audible),
  and a mismatch is dropped and logged (review S2, BI-S08; LB-7). It rebuilds the saved profiles on `engineQueue`
  after any start and applies on `resampleQueue` after any arm, off main; the view model chains its mode changes and
  re-sends one that outran a start or an arm in flight. A mode change re-sends the saved profile for the new plan's
  basis (S3). Main compares decisions by what they play (`playsLike`), never by their profile payloads (N14).
- **The planner's output width.** For a mono or stereo source, M is the width the device plays it on
  (`heardOutputChannels`, `AudioEngineBridge+ChannelLayout.swift:133`), so the dual-mono +3.01 LU applies; for more than
  two channels it stays the spatial unit's output, so the fold is unchanged. Before, the bridge reported the spatial
  unit's width — 1 for mono — and mono played 3 dB loud (review B1, BI-S09; corpus 05: −15.3 LUFS, now −18.0).
- **One glide law for both units.** The fold glides on the effects gain's one-pole — its trim in dB, its rows in
  amplitude, settling exactly — from one table (`planGlideSeconds`, `Planning/TrackPlan.h:35-57`: a fresh start snaps;
  a seam 10 ms; a mode change τ 0.15 s; an output change 10 ms on both units, where the fold used to snap — S4). A mode
  change that trades g for the trim swelled 1.18 dB; it now moves 0.055 dB, the effects limiter's 3 ms look-ahead
  (N16; LG-1, LG-3). A fresh start's and a mode change's plans apply on the Realizer's queue before the call returns
  (N4).
- **The output state's facts each have one owner** (S1, N5, N12): the transport hand-over alone owns the transport; a
  configure owns the rate, widths and roles and re-plans nothing; a re-establish updates M and the rate under the
  leveling lock and does nothing while a configure of another N is in flight; the readout takes the plan and its output
  in one read (LOS-1…3). A re-establish still never re-resolves the device width (S5): KI-MC-03.
- **§4's groups.** A run shares its loudest member's level only between songs that join in **play order** — the song
  before it in play order is the one before it in the run, or the song after is the one after (`joins`,
  `Sources/LevelingKit/LevelingDecisions.swift:213`) — in Auto, Track and Off (Off keeps the run's peaks by the same
  rule); shuffled songs never join (founder decision 2, 2026-10-26; the Track-mode run rule, 2026-10-30; break-it
  MEDIUM-2, BI-S10, DEC-17). A group's anchor compares a mono member as heard (+3.01) and is stated in the playing file's
  own measure, so the planner's one +3.01 lands every member on one g (review N1; DEC-18, LEVEL-MONO-01). A continuous
  mono ↔ stereo seam after a tag-only song can still step (KI-LEV-04).
- **The store and the scheduler.** A busy or locked file is never recreated — only SQLite's NOTADB or CORRUPT
  (`isBroken`, `TrackAnalysisStore.swift:203-204`; review N9, BI-S20); a lock past 5 s at launch plays that session
  unanalysed (KI-LEV-05). Records match without a JSON round trip (N10). A fold without an LFE keeps one profile row,
  answered for every variant, with no version bump (N11). The store is handed to the library
  (`LibraryModel.analysisStore`) for the "Use this drive" re-key, replacing a process-wide list (REKEY-02). The scheduler reads
  identities and headers off the cooperative pool (N8; SCHED-08) and reports each file it cannot analyse once per
  session — not found, header unreadable, the pass failed, the store refusing the result — so "· measuring" shows only
  while a measurement is coming (LEVEL-VM-18…20, SCHED-09).
- **The reader** (break-it HIGH-1, MEDIUM-3, LOW-6). Only a 48 kHz linear-PCM, FLAC or ALAC file is scheduled on the
  player as a file (`playsStraightThrough`, `AudioEngineBridge+TrackFile.swift:147`): those decoders deliver exactly
  `length`. Every other 48 kHz file streams through the bridge's own reader **with no conversion** and ends on the
  frames the decoder delivered — AC-3 and E-AC-3 deliver 288 short (Vorbis 128, ffmpeg-made MP3 302), and the player
  had completed such a schedule about 1 s early. Files at other rates go through the reader and the Mastering
  converter, as before. The reader is `TrackFileReader` (`ExtAudioFile`, bit-identical to `AVAudioFile` on the
  corpus): its place is counted, `framePosition` is never asked or set (Semgrep `app-no-avaudiofile-position`), and
  every start and seam probes a file's first frames before committing to it, refusing one the decoder can't read with
  why. A short-read file joins the next in one stream at its delivered end. The old restart through `playFile` after a
  failed roll is gone: a seam refuses a file that can't play, and the queue moves on.
- **N15, a recorded deviation from §7.** A never-analysed folded track's first play profiles its −ΔL on the decoded
  basis, not on the fold with the LFE omitted: about 1 dB off with the EQ on, that play only (F7's −1.05 dB on a +5 dB
  bass curve, +0.45 to +0.84 dB on treble). The fix — a fold-basis profiler entry in `TrackLoudnessBridge`, about 1.5
  days — is KI-LEV-03.
- **One Leveling enum.** LevelingKit's `LevelingMode` is the one enum; SettingsKit stores it, and `LevelingSetting`
  stays as its alias for now (`Sources/SettingsKit/LevelingSetting.swift:11`; the coordinator, 2026-10-30). The stored
  words are unchanged.

## Sources opened

- ITU-R BS.1770-5 (11/2023): Annexes 1 and 2.
- ITU-R BS.775-4 (12/2022): recommends §2–7, Notes 1–5; Annexes 4, 5, 7 (Figs 5, 9) and 8.
- EBU R 128-2023; EBU Tech 3341, 3342 and 3343-2023.
- libebur128 @ 67b33ab.
- ReplayGain 2.0 specification (archived).
- rsgain @ aae8cc74.
- Roon KB "Volume Leveling" (archived).
- MPD `doc/user.rst`.
- foobar2000 wiki "Preferences: Playback" (archived).
- RFC 9639.
- `CoreAudioBaseTypes.h`.
- Grimm, "Recommendation for loudness normalization by Music Streaming Services" v1.2 (2017), pp. 6–8 (the challenger's downloaded copy, read with pdftotext): the shuffle test ("71% of the subjects preferred album normalization blindly") and Additional note 2 ("always the 'loudest track' version").
