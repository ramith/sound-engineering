# Sprint 4 (US-TONAL-LOUDNESS) Test & Validation Plan
## Loudness Safety & Transparent Dynamics — True-Peak Limiter + LUFS Normalization

**Document ID:** SPRINT-4-TEST-001
**Version:** 1.0
**Date:** 2026-06-16
**Author:** QA review (audio-dsp-agent verification matrix), synthesized
**Status:** Ready for Sprint 4 Execution
**Companion docs:** [04-sprint-4-loudness-safety.md](04-sprint-4-loudness-safety.md) (spec) · [04-sprint-4-loudness-safety-plan.md](04-sprint-4-loudness-safety-plan.md) (implementation)

---

## Executive Summary

Sprint 4 ships the **safety floor**: a true-peak lookahead limiter (−1 dBTP, ≥4× ISP) and ITU-R BS.1770-5 LUFS normalization with transparent makeup gain. This plan verifies (1) the limiter enforces the ceiling with no inter-sample clipping and no audible pumping, (2) LUFS measurement is accurate to ±0.1 LUFS against `ffmpeg ebur128`, (3) the makeup-gain round-trip converges to target, (4) hearing-safety clamps scale proportionally, and (5) the render thread remains allocation/lock/throw free.

**Primary test path:** the standalone C++ harness `Tests/DSPKernelNullTest.cpp` (built via `scripts/build-null-test.sh`) — it compiles and runs today, independent of the broken `swift test` target.

**Pass Criteria:** all limiter tests (#9–#14) and loudness tests (#15–#20) pass; clamp tests pass; LUFS within ±0.1 LUFS of `ffmpeg ebur128`; 1-hour soak with 0 XRuns; ASAN/TSan clean; founder manual sign-off.

---

## Test Breakdown & Coverage

### 1. Limiter Unit Tests (standalone C++ harness)

**Scope:** ceiling enforcement, ISP detection, ballistics, ring geometry, multi-buffer stability.

| Test ID | Category | Focus | Pass Criteria |
|---|---|---|---|
| **#8** (exists) | Bypass | Ceiling ≥ 1.0 → zero-latency identity | Output bit-exact (MD5) vs input |
| **#9** (re-enable) | Ceiling | 0 dBFS sine (0.999) → output ≤ ceiling | `outPeak ≤ ceiling + 0.002` after prime |
| **#10** (re-enable) | Ballistics | GR onset on +6 dB spike | GR ramps in < 2 ms (< 96 frames) |
| **#11** (new) | ISP | Near-Nyquist tone (~0.4·fs), sample peak below ceiling | Output true-peak ≤ ceiling + 0.002 (catches inter-sample peak naive detection misses) |
| **#12** (new) | Release | Burst then silence; measure GR decay | Release ≈ 100 ms ± 10 %; GR < 0.5 dB after 500 ms silence |
| **#13** (new) | Soak | 100 × 512f blocks of 0.999 white noise | Every post-warmup sample `|x| ≤ ceiling + 0.002` (catches ring-wrap bugs) |
| **#14** (new) | Geometry | Dirac impulse through active limiter | Output impulse delayed by exactly `kLimiterLookaheadFrames` |

**Tools:** `scripts/build-null-test.sh`; peak/true-peak measurement helpers in the harness.

---

### 2. Loudness Unit Tests (BS.1770-5)

**Scope:** K-weighting response, gated integration, makeup-gain round-trip. Reference values from EBU Tech 3341/3342 and libebur128.

| Test ID | Category | Focus | Pass Criteria |
|---|---|---|---|
| **#15** (new) | K-weighting | Stage-1 shelf + Stage-2 HPF magnitude response | Within ±0.1 dB of published values at 100 Hz / 1 kHz / 4 kHz / 10 kHz |
| **#16** (new) | Integrated LUFS | 1 kHz sine at −23 dBFS, 3 s | Measured −23.0 LUFS ± 0.1 (K-weighting is unity at 1 kHz) |
| **#17** (new) | Absolute gate | 1 s silence + 2 s −23 dBFS sine | Silence discarded (−70 LUFS gate); integrated ≈ −23.0 ± 0.2 |
| **#18** (new) | Relative gate | EBU 3341 seq 3 (−20/−30 dBFS segments) | −30 segment excluded (−10 LU gate); integrated ≈ −20.0 ± 0.1 |
| **#19** (new) | Makeup round-trip | Measure −20 LUFS → apply +6 dB → re-measure | Re-measured −14.0 LUFS ± 0.1 |
| **#20** (new) | Reference accuracy | vs `ffmpeg ebur128` over generated tones | \|native − ffmpeg\| ≤ 0.1 LUFS (tones); ≤ 0.2 (pink noise) |

**Test #20 mechanics** (`scripts/validate-lufs.sh`):
```bash
ffmpeg -i ref.wav -af ebur128=framelog=verbose -f null - 2>&1 | grep 'I:'
./Tests/LoudnessAccuracyTest ref.wav     # native K-weight + gate + integrate
# diff the two; assert within tolerance
```
Reference tones (generated programmatically, not committed as binaries): 1 kHz sine at −23 / −18 / −14 / −10 dBFS (expect matching LUFS ± 0.1); pink noise at −16 dBFS RMS, 10 s (expect −16.0 ± 0.2).

**Sample-rate note:** K-weighting coefficients are 48 kHz-specific; re-derive via bilinear transform with pre-warp for non-48k and re-run #15/#16 at 44.1 kHz.

---

### 3. Hearing-Safety Clamp Tests (Swift control path)

| Test ID | Focus | Pass Criteria |
|---|---|---|
| **CLAMP-01** | Proportional scaling: {+20×5} cumulative → scale to +12 | Output = {+2.4×5}; cumulative = +12 dB |
| **CLAMP-02** | No-op when under threshold: {+8,−3,+5,−1,+2} (sum +11) | Output unchanged |
| **CLAMP-03** | Direction preserved: {+20,−3,+5,−1,+2} (sum +23) → clamp +12 | Boosts stay positive, cuts stay negative; cumulative = +12 |

---

### 4. Real-Time Safety Validation

| Test ID | Focus | Method | Pass Criteria |
|---|---|---|---|
| **RT-SAFE-01** | No heap alloc on render thread | ASAN, RT-aware | Zero malloc/free in `process()` (limiter + loudness apply) |
| **RT-SAFE-02** | No locks/throws/OS calls on RT path | Code review + grep | `noexcept` throughout; no mutex/log/ObjC on render thread |
| **RT-SAFE-03** | SPSC ring + atomic handoffs race-free | ThreadSanitizer over concurrent RT-produce / measurement-consume | 0 data races over ≥ 20k iterations |
| **RT-SAFE-04** | RT cost within budget after B1/B2 | Instruments signpost on `process()` | p99.9 ≤ 5 ms per 512f block; 0 XRuns |

---

### 5. Integration & Soak Tests

| Test ID | Scenario | Pass Criteria |
|---|---|---|
| **IT-LOUD-01** | 1-hour continuous 20-track playlist, varied targets (−20/−16/−12/−6 LUFS) | 0 XRuns; LUFS variance < 0.5 LU over 5-min window; stable memory; CPU headroom |
| **IT-LOUD-02** | Synthetic hot master (pink noise −10 dBFS + +10 dBFS clicks) | Output true-peak ≤ −1 dBTP; clicks inaudible |
| **IT-LOUD-03** | Makeup transparency: same track at 3 levels ± makeup | With makeup, perceived loudness matches reference; no clicks/zipper |
| **IT-LOUD-04** | Track change (level discontinuity) | Makeup re-converges smoothly; no audible step/pump |

---

## Manual Testing Checklist (founder, per `00-sprint-model.md`)

- [ ] App loads / initializes without crash; loudness meters appear when toggled on
- [ ] Play a hot master at a normal level → no swelling/pumping/breathing (limiter transparent)
- [ ] LUFS meter reads a plausible integrated value; GR meter taps a few dB on peaks
- [ ] Drop to a quiet track → makeup engages transparently; perceived loudness consistent
- [ ] Toggle meters off → no UI clutter, polling stops
- [ ] A/B vs prior build: no new artifacts/glitches
- [ ] Performance acceptable (no lag, no dropouts)

---

## Pass Criteria / Gates

**Per-merge (< 15 min):** limiter #8–#14 + loudness #15–#19 green; null-test bit-exact bypass; ASAN/TSan/clang-tidy clean.
**Nightly:** LUFS accuracy #20 vs `ffmpeg ebur128`; RT-safety metrics (p99.9 ≤ 5 ms, XRuns = 0).
**Sprint final:** 1-hour soak (IT-LOUD-01) pass; peak protection (IT-LOUD-02); listening-panel transparency ≥ 80 % "inaudible/subtle"; founder manual sign-off.

---

## Optional Listening Panel (5–10 engineers, MUSHRA-style)

Blind A/B on 5 reference tracks: original vs limiter+makeup. Pass: ≥ 80 % rate the processed candidate "inaudible" or "subtle"; no reports of swelling/pumping/breathing.

---

**Status:** Ready for Sprint 4 Execution
**Next:** Re-enable limiter tests #9/#10 and add #11–#14 against the standalone harness (Milestone 1)
