# AdaptiveSound — Multichannel Pipeline Epic QA Plan

**Document ID:** MULTICHANNEL-QA-001
**Date:** 2026-06-16
**Author:** qa-expert
**Status:** Ready for founder review and sprint execution
**Epic ref:** MULTICHANNEL-EPIC-001 / MULTICHANNEL-PIPELINE-001
**Sprint model ref:** 00-sprint-model.md
**Companion:** 05-sprint-5b-multichannel-epic-plan.md (the plan this document extends)

---

## 1. QA Strategy & Scope

### 1.1 What this plan does NOT duplicate

The epic plan already defines: the golden-master fence (T-C1/T-C2), the test-stub progression,
gates A–E, and per-step exit criteria. This plan organises those into a holistic QA strategy and
adds the test pyramid, defect taxonomy, environment model, manual scripts, traceability matrix, and
metrics framework the epic plan does not contain.

### 1.2 Quality risks ranked for this epic

| Rank | Risk | Failure mode | Severity |
|------|------|--------------|----------|
| R1 | Channel mis-order / crosstalk from count-only `AVAudioFormat` | Silent: BS.1770 weights wrong, BRIR mapped to wrong speaker, phantom centres collapse | Critical |
| R2 | True-peak breach after BRIR convolution | HRTF inter-channel sum can exceed pre-binaural ceiling by up to +9 dB | Critical |
| R3 | Stereo golden-master regression | Any bit-difference at N=2 means existing sound is broken | Critical |
| R4 | Hidden input downmix at `scheduleFile` | 5.1 content folded to stereo before the AU sees it | High |
| R5 | Linked-gain violation in the limiter | Independent per-channel GR → image shift audible at >1 dB delta | High |
| R6 | EQ click / zipper at N>2 | Coefficient swap glitch on channels 3–N | High |
| R7 | RT allocation when `kMaxChannels` grows to 8 | XRun or ASAN abort on render thread | High |
| R8 | BS.1770 weight error (LFE included, surround not weighted) | Makeup gain overdrives surround by up to +3 dB | High |
| R9 | Reconfiguration race (running engine, tap drift) | Engine hard-stop, silence, crash | Medium |
| R10 | BRIR energy non-preservation / ITD-ILD inversion | Spatial image collapsed or inverted | Medium |
| R11 | Zero-XRun soak failure on M1 Pro at N=8 | Listener hears dropouts | Medium |
| R12 | `ChannelLayout` tag round-trip failure (AAC vs broadcast ordering) | Wrong BRIR azimuth per channel | Medium |

### 1.3 Scope boundary

In scope: all C++ DSP modules (EQ, Limiter, Loudness, SpatialRenderKernel), the Swift graph
lifecycle (`AudioEngineBridge`, `reconfigureGraph`), the `ChannelLayout` decode path, the Monitoring
UI channel rows (smoke only), and all automated harness targets. Out of scope: NL control, stem
engine, per-speaker room correction (separate epics).

---

## 2. Test Levels and Pyramid

Adapted to the hard constraint that `swift test` is broken; the automated mechanisms are the
standalone C++ null-test harness plus `swift run`-style offline-render executables.

```
        /\
       /  \   L3  Manual / Listening (founder) — audible A/B, binaural, MUSHRA, UI, hardware
      /----\
     /  L2  \  Offline-Render Integration (automated) — VerifyAUGraph / VerifyMultichannelGraph /
    /--------\                                          VerifyDeviceBoundary (synthetic N-channel)
   /    L1    \  C++ null-test harness (DSPKernelNullTest.cpp) — bit-exact, ceiling, independence,
  /------------\  linked-gain, FR, click-free, ChannelLayout decode — pre-commit gate
```

### Level 1 — C++ unit/integration (null-test harness)
Runner: `scripts/build-null-test.sh` (pre-commit). Everything exercisable by building an
`AudioBufferList`, calling `DSPKernel::process`, asserting on output: bit-exact comparisons, ceiling,
per-channel independence, linked-gain lockstep, FR accuracy, click-free swap at N>2, `ChannelLayout`
decode (no CoreAudio runtime). Currently 19 tests; every new L1 test extends the same file + script.
**N-channel `TestABL` must use statically-correct structs (embed `AudioBufferList` + extra
`AudioBuffer`s), never a pointer-cast of a smaller allocation (UB).**

### Level 2 — Offline-render integration (Swift executables)
Runner: `swift run <Target>` (the `Sources/VerifyAUGraph/main.swift` pattern; exit 0 = pass). New
targets: **`VerifyMultichannelGraph`** (synthetic N-channel through player→AU→mixer offline; per-
channel integrity, reconfiguration continuity) and **`VerifyDeviceBoundary`** (`SpatialRendererAU`
passthrough bit-exact + binaural finite/non-silent/energy-preserving). No multichannel hardware
needed; added to `Package.swift` as executable targets, gated on exit code.

### Level 3 — System/manual (founder)
All UI, audible-quality, binaural listening, MUSHRA, and hardware-dependent (real 5.1/7.1 interface,
headphones) tests. Cannot be machine-verified. Scripts in §9.

### Automation
| Level | Tests | Automated | Coverage target |
|-------|-------|-----------|-----------------|
| L1 C++ | 19 + ~20 new | pre-commit | 100% of DSP arithmetic correctness |
| L2 offline-render | ~4 `swift run` targets | CI | 100% of graph lifecycle / boundary logic |
| L3 manual | 5 checklists (one/sprint) | no | 100% of UI/audio-quality/hardware |

Realistic automation: ~70–75% of the verification surface is machine-runnable (all L1+L2); the rest
(audible quality, binaural perception, UI) is inherently manual.

---

## 3. Quality Gates Per Sprint

Each gate is a hard stop; a sprint is not Done-Done until its gate passes. Tie to epic gates A–E and
the `00-sprint-model.md` Done-Done template.

### Gate S0 — Safety net + structural foundation
- 19/19 existing null tests green (`scripts/build-null-test.sh`, exit 0).
- **T-C1 golden master captured** (fixed-seed chirp through non-trivial EQ + active limiter; `memcmp`
  bit-exact at N=2; `constexpr` reference committed). **T-C2** (N=2 via `MultichannelView`) bit-exact.
- T-C3/T-C4/T-C5 stubs compile.
- **Exactly one `mNumberBuffers` read in the codebase**: `grep -r 'mNumberBuffers' Sources/AudioDSP | wc -l` = 1.
- ASAN clean; clang-tidy + swiftlint clean; "after" tap relocated to AU output (`VerifyAUGraph` still 0).
- Founder manual S0 (§9.1): stereo sounds identical.

### Gate S1 — C++ modules N-channel
- 19 + T-C1/T-C2 bit-exact at N=2.
- **T-C3** per-channel independence (N=4/6/8): each output channel only its tone `f0·(k+1)`; cross-channel < −60 dB.
- **T-C4** linked-gain lockstep (hot ch0 → all channels' GR within 0.01 dB).
- Per-channel EQ FR ±1 dB; **click-free EQ swap at N=4 (Gate A)**; N=8 hot-noise soak ≤ ceiling+0.01.
- **BS.1770 multichannel weights (Gate C)**: within ±0.2 LU of analytic; LFE contributes 0.
- ASAN + clang-tidy clean; founder S1 (§9.2): stereo identical A/B.

### Gate S2 — Source-driven N input + graph at N
- All S0/S1 L1 tests pass; **T-C5** reconfiguration continuity (stereo→5.1→stereo: no crash/silence).
- **`ChannelLayout` tag round-trip (Gate D)**: MPEG_5_1_A/_B/7_1 + a broadcast ordering decode to
  correct weights + azimuth/elevation.
- **`VerifyMultichannelGraph`** (L2): synthetic 5.1 → 6 channels preserved through AU, no swap/silence.
- Interim limiter ceiling −6 dBTP (no sample exceeds it through the mixer-fold path).
- Founder S2 (§9.3): Monitoring shows 6 rows; 5.1 plays (interim fold); stereo no-regression.

### Gate S3 — SpatialRendererAU passthrough/route
- All prior L1 pass; **`VerifyDeviceBoundary`** passthrough deviceCh=N bit-exact.
- **Zero-XRun soak N=6/8, 30 min** `[HW-REQUIRED]` (Console/`log stream` audio subsystem: 0 XRuns).
- `AVAudioEngineConfigurationChange` reconfigures cleanly (device hot-plug, §9.4); stereo through the
  full two-AU graph bit-exact; ASAN + TSan clean during soak.

### Gate S4 — BRIR binaural path
- All prior L1 pass; BRIR output finite/non-NaN/non-silent (RMS > −60 dBFS); energy ±3 dB.
- ITD/ILD sanity (L≠R for off-centre channels); hot-swap no-click.
- **True-peak ≤ −1 dBTP after both limiters (Gate B)** — pre-binaural ceiling **measured on actual
  SADIE II HRIRs**, committed to `AudioConstants.h`; libebur128 oracle ≤ −1 dBTP on full-scale stimulus.
- **BS.1770 multichannel oracle** (libebur128/ffmpeg) ±0.2 LU; LFE excluded from binaural (tone on LFE → L/R < −60 dBFS).
- `VerifyDeviceBoundary --binaural` (deviceCh=2, 5.1 source) passes; 30-min soak with BRIR 0 XRuns.
- Founder S4 (§9.5): binaural spatial quality; stereo regression unchanged.

### Epic release gate
All S0–S4 gates green + golden master unchanged + full null suite + both `Verify*` targets green +
**zero open Critical/High defects** + 1-hour N=8 soak 0 XRuns + all 5 founder checklists signed off +
ASAN/TSan clean + docs updated.

---

## 4. Defect Taxonomy & Severity (audio-tuned)

**Critical (blocker — do not merge/ship):** true-peak breach (> −1 dBTP any stimulus/channel);
stereo golden-master diff; channel swap/crosstalk (>−60 dB bleed); NaN/Inf output; XRun during the
gate soak; RT-path allocation (ASAN); BS.1770 weight error breaching the ceiling.

**High (fix before sprint gate):** audible click/zipper on EQ swap at N>2; non-linked per-channel GR
(>0.1 dB deviation); `ChannelLayout` decoded wrong; binaural silent / energy not preserved; BRIR
hot-swap click; post-binaural ceiling not enforced; `reconfigureGraph` crash/hang/silence; hidden
`scheduleFile` downmix.

**Medium (fix before release gate; may merge w/ tracking):** minor weight inaccuracy (±0.5 LU, no
breach); BRIR ITD/ILD slightly off; Monitoring shows wrong channel count; 1–2 self-recovering XRuns
over 30 min; libebur128 delta 0.2–0.5 LU.

**Low (backlog):** Monitoring cosmetics; over-budget perf without XRuns; `vDSP_biquadm` deferral.

Tracking: at current solo+agents size, defects are recorded in the sprint plan's blockers section +
commit messages. Any Critical/High must be recorded before gate review and resolved (or deferred
with documented risk acceptance) before merge.

---

## 5. Regression Strategy

**Golden master:** T-C1 = `constexpr` float arrays in `DSPKernelNullTest.cpp` capturing the exact
output of a fixed-seed chirp (20 Hz→20 kHz, 1 s, amp 0.5) through a non-trivial EQ + active limiter
at N=2, committed and `memcmp`-asserted every run. **Bit-exact, not within-tolerance** (deterministic
`constexpr` inputs on Apple Silicon). Frozen from S0; re-baselined only for a deliberate, founder-
approved DSP change (the implementer proposes in the PR; the founder listens old-vs-new; new arrays
land in the same commit; the test name version increments). T-C3 per-channel references follow the
same discipline. Every sprint gate re-runs the **entire** L1 binary (no subset runs) so shared-module
changes can't silently regress a prior test.

---

## 6. Risk-Based Prioritisation

R1 → `ChannelLayout` round-trip (Gate D, S2) + per-channel independence (T-C3, S1) + the
`mNumberBuffers` grep gate (S0). R2 → measured SADIE II headroom + post-binaural limiter test (Gate
B, S4); no estimated value accepted. R3 → T-C1/T-C2 every gate + pre-commit. R4 →
`VerifyMultichannelGraph` (S2) + the `AVAudioChannelLayout` assertion. R5 → T-C4 lockstep (S1). R6 →
click-free swap extended to N=4 (Gate A, S1). R7 → ASAN at every gate + `PerChannel<T>` fixed-storage
policy. R8 → BS.1770 weight test (S1) + libebur128 oracle (S4) + LFE-exclusion test. R9 → T-C5 (S2) +
`GraphState` review + manual reconfig (S3). R10/R11/R12 → soak (S3/S4) + ITD/ILD (S4) + tag round-trip (S2).

---

## 7. Test Environments & Data

**A — Stereo dev machine (primary, all sprints):** all L1 + L2 run here; N>2 verified via synthetic
ABL construction — no multichannel hardware required up to and including S2.
**B — Multichannel interface (S3/S4, `[HW-REQUIRED]`):** ≥6-channel USB/TB interface for the
zero-XRun soak + passthrough-on-hardware. If unavailable when needed, the soak is **explicitly
deferred + documented**, never silently skipped or substituted with a weaker check.
**C — Headphones (S4):** binaural spatial listen (subjective, founder-assessed).

**Synthetic vectors:** distinct-per-channel tones (ch k = sine at `200·(k+1)` Hz, amp 0.25) to catch
swap/crosstalk; fixed-seed chirp (golden master); LFE-exclusion vector (60 Hz on LFE only); hot-noise
soak (`mt19937` fixed seed, N=8, 100×512); reference layout tags (MPEG_5_1_A/_B, MPEG_7_1_SDDS, a
`UseChannelDescriptions` custom ordering) with `constexpr` expected weights/azimuths.
**BRIR/HRIR:** SADIE II for the pre-binaural headroom measurement + the manual binaural listen;
synthetic unit-impulse HRIRs suffice for the finite/energy automated checks.
**libebur128 oracle:** extend `scripts/validate-lufs.sh` → a multichannel variant feeding a 6-channel
WAV (correct `WAVE_FORMAT_IEEE_FLOAT` + channel mask) through `LufsMeter` (N-channel) and
`ffmpeg ebur128`; tolerance ±0.2 LU (vs ±0.1 stereo).

---

## 8. Traceability Matrix

| Req | Description | Tests |
|-----|-------------|-------|
| REQ-MC-01 | N channels processed, no downmix (N=1..8) | T-C3 (L1), `VerifyMultichannelGraph` (L2) |
| REQ-MC-02 | Stereo golden-master unchanged at N=2 | T-C1, T-C2 (L1, every sprint) |
| REQ-MC-03 | Channel order correct for all layout tags | `ChannelLayout` round-trip (L1, Gate D, S2) |
| REQ-MC-04 | No downmix at `scheduleFile` | `VerifyMultichannelGraph` (L2, S2) + manual: Monitoring shows 6 rows |
| REQ-MC-05 | Limiter gain linked across channels | T-C4 (L1, S1), inter-channel GR < 0.01 dB |
| REQ-MC-06 | EQ click-free swap at N>2 | `EQ_CoefficientSwapNoClick` @ N=4 (L1, Gate A, S1) |
| REQ-MC-07 | BS.1770 multichannel weights (surround ×1.41, LFE=0) | weight test (L1, S1), libebur128 oracle (S4) |
| REQ-MC-08 | LFE excluded from binaural | LFE-exclusion test (L1, S4) |
| REQ-MC-09 | True-peak ≤ −1 dBTP after post-binaural limiter | post-binaural test (L1, Gate B, S4) + oracle |
| REQ-MC-10 | Stereo passthrough bit-exact through two-AU graph | `VerifyDeviceBoundary` passthrough (L2, S3) |
| REQ-MC-11 | Spatial render when deviceCh < N (binaural, not fold) | `VerifyDeviceBoundary --binaural` (S4) + manual listen |
| REQ-MC-12 | BRIR finite/non-silent/energy-preserving (±3 dB) | BRIR energy test (L1, S4) |
| REQ-MC-13 | ITD/ILD correct for layout positions | ITD/ILD sanity (L1, S4) |
| REQ-MC-14 | BRIR hot-swap no-click | hot-swap click test (L1, S4) |
| REQ-MC-15 | RT-safe: no heap alloc on render thread | ASAN soak (every sprint), grep gate (S0), `PerChannel` review |
| REQ-MC-16 | Zero XRuns, 30-min soak at N=8 | manual soak + OS audio log (S3/S4) `[HW-REQUIRED]` |
| REQ-MC-17 | Reconfiguration stereo→5.1→stereo clean | T-C5 (L1+L2, S2), manual reconfig (S3) |
| REQ-MC-18 | `GraphState` prevents re-entrant reconfig | code review (S2) + T-C5 stress variant |
| REQ-MC-19 | Pre-binaural ceiling measured (not estimated) | documented measurement in S4 PR + `AudioConstants.h` |
| REQ-MC-20 | Monitoring UI shows N channel rows | founder manual (L3, S2) |

---

## 9. Manual Test Scripts (founder run-and-listen, ~20–30 min each)

### 9.1 S0 — Safety net (no audible change expected)
- App launches, Monitoring visible. Play reference stereo track — clean.
- Monitoring on: meters animate, 2 rows. A/B vs prior build: no audible difference (no new hiss/click/level shift). Pause/resume: no click.
- `scripts/build-null-test.sh` → all pass. `grep -r 'mNumberBuffers' Sources/AudioDSP | wc -l` → 1.

### 9.2 S1 — C++ modules N-channel (still stereo)
- Play 3 stereo tracks (quiet acoustic / loud electronic / wide-dynamic classical): no artifacts.
- Big EQ swing while playing (boost 1 kHz +12 dB → flat): no click/zipper (headphones). Hot track: limiter engages, no new pumping. A/B vs S0: identical. Harness incl. T-C3/T-C4 pass.

### 9.3 S2 — Source-driven N input (interim fold)
- Open 5.1 file: Monitoring shows 6 rows, all animating; audio plays (folded), no crash. Switch to stereo (2 rows), back to 5.1 (reconfig) ×5 rapidly: no crash/hang. `swift run VerifyMultichannelGraph` passes. Stereo A/B vs S1: identical.

### 9.4 S3 — SpatialRendererAU passthrough `[HW for full soak]`
- `swift run VerifyDeviceBoundary` first. Stereo reference: no change vs S2. If multichannel interface available: 5.1 file shows 6 channels active on the interface meters. Device hot-plug mid-playback: recovers, no crash. 30-min N=6/8 soak → `log show --last 35m --predicate 'subsystem == "com.apple.audio"' | grep -i xrun` → 0. (No HW → run extended offline `VerifyDeviceBoundary` as a partial substitute + document the gap.)

### 9.5 S4 — BRIR binaural (headphones required)
- Stereo reference (headphones): no change vs S3. 5.1 file: sources externalised + directionally placed (L front-left, surrounds to sides/behind), not a flat in-head fold. Distinct-tone WAV: each channel from its BS.775 direction. Reverb decays naturally, no clip. BRIR preset swap: no click. Binaural not louder than the S2 fold (else flag High). Hot 5.1 source: no distortion. 30-min soak: no XRuns/dropouts, no GR-stuck quieting. A/B BRIR vs S2 fold: BRIR clearly wider/more accurate (else evaluate HRIR quality). Document the HRIR source used.

---

## 10. Metrics & Exit Criteria

**Coverage** (requirements with ≥1 automated test): start 8/20 (40%) → end ≥16/20 (80%); automation
fraction ≥70% (REQ-MC-16 hardware soak + REQ-MC-20 UI excluded from the automatable denominator).
**Defect density:** Critical/High = 0 at every gate; Medium ≤3 (documented) per gate, 0 at release;
Low tracked.
**True-peak compliance** (the key quantitative audio metric): L1 tests assert ≤ `kTruePeakCeilingLinear
+ 0.01`; release gate confirms ≤ −1 dBTP via libebur128 on worst-case full-scale N-channel hot noise.
**Golden-master integrity:** binary pass/fail every run; any fail = Critical; re-baseline count >2
over the epic is a stability smell.
**Zero-XRun soak:** 0 over 30 min; 1–2 OS-scheduling-spike XRuns acceptable at Medium with docs; any
XRun correlated with a DSP state change (reconfig, hot-swap) is High.
**CI / pre-commit:** pre-commit unchanged (clang-format/tidy + swiftlint/format + `build-null-test.sh`).
Add `swift run VerifyMultichannelGraph` + `VerifyDeviceBoundary` to the PR gate (exit-code gated,
<30 s each, no HW). Add the `mNumberBuffers` grep check to CI in S0. Nightly (manual trigger ok):
`validate-lufs.sh` + its multichannel variant.

---

## Implementation notes for the test engineer

1. N-channel `TestABL`: extend the `AudioBufferList2` statically-correct pattern to `AudioBufferList6`/
   `8` (or a careful `TestABLN<N>`); never pointer-cast a `sizeof(AudioBufferList)` allocation (UB).
2. `makeIdentityState()` sets the limiter to bypass (ceiling 2.0); active-limiter tests construct
   state like `testLimiterCeilingEnforcement`, not via `makeIdentityState`.
3. T-C3 independence: don't `memcmp` full buffers (EQ/limiter alter amplitude); measure per-channel
   dominant frequency (correlate output vs a reference sine at each of the N tone frequencies; own
   frequency dominates, others < −60 dB).
4. `ChannelLayout` round-trip: pure C++ unit test (mock `AudioChannelLayout` → `fromTag` → assert
   arrays); no CoreAudio runtime/Swift dependency; lives in the harness.
5. Multichannel libebur128 oracle: extend `lufs-tool.cpp` to write a 6-channel `WAVE_FORMAT_IEEE_FLOAT`
   WAV with the correct channel mask so `ffmpeg ebur128` applies BS.1770 weights.

---

**Files referenced:** `Tests/DSPKernelNullTest.cpp` · `scripts/build-null-test.sh` ·
`scripts/validate-lufs.sh` · `scripts/build-eq-clamp-test.sh` · `Sources/VerifyAUGraph/main.swift` ·
`docs/sprints/05-sprint-5b-multichannel-epic-plan.md` · `docs/sprints/05-sprint-5b-multichannel-pipeline-plan.md` ·
`docs/sprints/00-sprint-model.md`
