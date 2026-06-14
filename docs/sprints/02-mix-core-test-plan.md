# Sprint 2: Mix-Based Core — Test & QA Strategy

**Document ID:** SPRINT-2-QA-001  
**Version:** 1.1 (Blocker Resolutions Applied)
**Date:** 2026-06-14  
**Status:** ✅ **Team Review Complete — Blockers Resolved — READY FOR EXECUTION**

---

## Executive Summary

Comprehensive test strategy for Phase 1 DSP signal chain: EQ, Clarity, Loudness, BRIR, Limiter, and Intensity knob. Covers unit tests (module isolation), integration tests (signal chain), RT-safety validation, and manual listening QA.

**Test approach:**
1. **Unit tests** — verify each module's math (frequency response, gain linearity, phase, metering)
2. **Integration tests** — signal chain with reference audio (sweep, pink noise, music)
3. **RT-safety audit** — static analysis + profiling (no allocations/locks on audio thread)
4. **Manual QA** — A/B null tests, listening panel feedback, edge cases

**Definition of done:** All tests green + manual QA sign-off.

---

## 1. Unit Test Coverage

### 1.1 EQ Module Tests

**Test Suite:** `Tests/EQTests.swift`

| Test | Input | Expected Output | Pass Criteria |
|---|---|---|---|
| **Flat response** | 1 kHz sine, all bands at 0 dB | Output magnitude = input ±0.1 dB | ±0.1 dB @ 1 kHz, 10 kHz, 100 Hz |
| **Gain linearity** | Sweep (-20 dB to +12 dB per band) | Gain matches ±0.05 dB | All bands ±0.05 dB across range |
| **Frequency accuracy** | 31-band test tones (20 Hz → 20 kHz) | Peak at center freq ±2% | ±2% or <±10 Hz (whichever is larger) |
| **Phase response** | Minimum-phase mode enabled | Phase lag increases @ higher freq | Group delay ≤ 0 (stable minimum-phase) |
| **Stability** | White noise, 10 sec @ fs=48 kHz | No clipping, no NaN/Inf | Output energy ≈ input (±0.5 dB) |
| **Preset load/save** | Save EQ state, reload, apply | Output matches original | Byte-identical coefficient reload |

**Tools:** Automated test harness (AudioUnit plugin simulator) + manual verification w/ Spectroid app

---

### 1.2 Clarity Module Tests

**Test Suite:** `Tests/ClarityTests.swift`

| Test | Input | Expected Output | Pass Criteria |
|---|---|---|---|
| **Transient detection** | Synthetic impulse (0.5 ms rise) | Gate signal triggers ≤1 ms after onset | Latency ≤1 ms |
| **Selective compression ratio** | 1 kHz sine + transient burst | Compression active only in 1–4 kHz band | Measurable GR in presence band only |
| **Soft knee** | Threshold -20 dB, input swept | Gain reduction curve is smooth (no knee artifacts) | Smooth dB/dB curve (no kinks) |
| **Confidence gating** | Noise floor vs. transient | Low-confidence = no compression | Gate output <-40 dB for noise-only |
| **Makeup gain** | Compressed signal | Makeup gain restores ~ original RMS ±1 dB | Output RMS within ±1 dB of input |
| **Stability under abuse** | +3 dBFS input (near clipping) | Module doesn't clip internally; limiter catches | No internal clipping (measured via peak detector) |

**Tools:** Synthetic test audio (impulses, sweeps, white noise)

---

### 1.3 Loudness Module Tests

**Test Suite:** `Tests/LoudnessTests.swift`

| Test | Input | Expected Output | Pass Criteria |
|---|---|---|---|
| **LUFS measurement accuracy** | Spotify reference (-14 LUFS) | Measured LUFS | ±0.5 LU vs. libebur128 reference |
| **Per-track LUFS** | 10 reference test files (varied loudness) | LUFS per file | ±0.3 LU vs. broadcast-grade meter |
| **ISO 226 curve lookup** | SPL 0–100 dB @ 1 kHz | Equal-loudness contour match | ±2 dB vs. ISO standard table |
| **Makeup gain calc** | Measured LUFS -10, target -16 | Makeup gain = +6 dB | Measured value = expected ±0.1 dB |
| **Rate limiting** | Volume knob ramp (0 dB → -6 dB in 100 ms) | Makeup gain follows volume curve, max 1 dB/100 ms | Gain ramp <1 dB/100 ms (smooth, no pump) |
| **Stability** | 10 min continuous audio | Accumulated error = 0 (no drift) | No variance >0.1 LU over 10 min |

**Tools:** Broadcast-grade loudness meter (Dolby Media Meter) as reference

---

### 1.4 BRIR/HRTF Module Tests

**Test Suite:** `Tests/SpatialTests.swift`

| Test | Input | Expected Output | Pass Criteria |
|---|---|---|---|
| **SADIE II load** | HRTF dataset file (binary) | 45 azimuths × 10 elevations loaded | File loads ≤100 ms, memory <20 MB |
| **Convolution latency** | Audio @ 48 kHz, 512-frame buffer | Latency from input → spatial output | ≤5 ms added latency |
| **Phase coherence** | Stereo pair (L/R HRTF filters) | Left/right channels are conjugate-symmetric (valid HRTF pair) | Cross-correlation ≈ -1 (L/R well-balanced) |
| **Bass mono summing** | <120 Hz content | Bass frequency summed mono (no L/R HRTF) | Sub-120 Hz energy is mono ±0.1 dB |
| **Width interpolation** | Intensity 0% → 100% | Center-lock @ 0%, max spread @ 100% | Smooth gain transition (no clicks) |
| **Vocal center-lock** | Lead vocal detected (future feature) | Lead vocal stays center (no L/R spread) | Vocal energy center-locked ±2 dB L/R balance |

**Tools:** Measurement microphone stereo pair (XMOS XU316) or Genelec 8351A nearfield monitors

---

### 1.5 True-Peak Limiter Tests

**Test Suite:** `Tests/LimiterTests.swift`

| Test | Input | Expected Output | Pass Criteria |
|---|---|---|---|
| **Peak detection accuracy** | Test signal peaked +2 dBFS | Gain reduction clamps output to -1 dBTP | Output ≤ -1 dBTP (measured via peak detector) |
| **Attack time** | Step +3 dBFS → trigger | GR onset ≤ 1 ms (1 buffer @ 48 kHz/512 frames) | Latency ≤1 buffer |
| **Release envelope** | Release time set to 50 ms | GR decay smooth (no zipper noise) | Release curve smooth (no artifacts) |
| **Makeup gain auto-calc** | Threshold -1 dBTP, makeup auto | Output RMS ≈ input RMS (makeup compensates GR) | Output peak normalized to -1 dBTP, RMS gain-matched |
| **Sustained limiting** | Held >-1 dBTP for 5 sec | Limiter holds steady; no pumping | GR stable ±0.2 dB (no oscillation) |
| **Lookahead effectiveness** | 1 ms pre-peak signal | Limiter reacts before peak reaches output | Anticipatory GR starts ≤1 ms before peak |

**Tools:** Audio workbench + peak detector plugin

---

## 2. Integration Tests

### 2.1 Full Signal Chain

**Test Suite:** `Tests/ChainIntegrationTests.swift`

| Test | Signal | Duration | Pass Criteria |
|---|---|---|---|
| **1 kHz sine sweep** | Amplitude ramp -20 dBFS → +1 dBFS, EQ+Clarity+Loudness+Limiter enabled | 30 sec | No clipping, no dropouts, output peak ≤ -1 dBTP |
| **Pink noise reference** | 60 sec @ -10 LUFS input | 60 sec | Output LUFS matches loudness target ±0.5 LU |
| **Null test (A/B bypass)** | 10 sec audio, bypass ON | 10 sec | Intensity @ 0% produces bit-identical output (null test) |
| **Intensity knob sweep** | Intensity 0% → 100% → 0% (10 sec each) | 30 sec | Crossfade smooth, no clicks/pops, imperceptible |
| **Realistic music test** | 3 varied tracks (pop/classical/jazz) + manual A/B | ~15 min | No dropouts, all modules respond, perceptual quality improved |

**Tools:** Audio workbench + test harness + manual listening

---

### 2.2 Real-Time Safety Validation

**Real-time audio thread audit:**

| Check | Method | Pass Criteria |
|---|---|---|
| **No allocations on audio thread** | Static analysis (grep C++ code for `new`/`malloc`/`alloca`) | Zero hits in `AudioEngine::render()` and module callbacks |
| **No locks held during render** | Code review + thread-safety audit | All mutable state pre-allocated; render callback read-only |
| **No sleeps / I/O on audio thread** | Static analysis (grep for `sleep`, `open`, `write`, `fstream`) | Zero hits |
| **Buffer overruns** | Address Sanitizer (ASAN) on test suite | Zero reported errors |
| **Stack usage** | Measure max stack depth on render | ≤16 KB (macOS typical stack slice) |

**Tools:** ASAN, clang static analyzer, manual code review

---

## 3. Manual QA Checklist

### 3.1 Listening Tests

**Environment Setup:**
- 2 headphone pairs: Apple AirPods Pro 2, Audio-Technica AT-M50x (reference studio phones)
- 1 speaker pair: Genelec 8010A (reference nearfield monitors)
- 1 reference loudness meter: Dolby Media Meter (software) or Behringer ECM8000 + RTA app
- Test audio: 3 tracks (pop, classical, jazz) + 6 synthetic test signals (sine, pink noise, sweeps, chirps)

**A/B Test Protocol (Per Track):**
1. Play track with **Intensity = 0%** (original/bypass)
2. Play track with **Intensity = 100%** (full processing)
3. Blind A/B swap 5× (listener doesn't know which is which)
4. Rate: *Better? Worse? No Change?* + describe differences
5. **Null-test:** A/B same instance → should hear **zero** difference (confirms bypass works)

**Manual QA Sign-Off Checklist:**
- [ ] Headphones: All 3 tracks improved or neutral (no regression)
- [ ] Speakers: All 3 tracks improved or neutral
- [ ] Null-test: A/B same content produces bit-identical output (measured + listening)
- [ ] Intensity knob: Smooth crossfade, no clicks/pops
- [ ] EQ: Presence band changes audible; low-freq changes subtle (as expected)
- [ ] Clarity: Transient sharpening audible on drums/vocals
- [ ] Loudness: Tracks match perceived loudness ±0.5 LU
- [ ] Limiter: Peaks never exceed -1 dBTP; makeup gain transparent
- [ ] UI responsive: No freezes, no dropouts, knobs track immediately

**Listeners:** 2–3 people (incl. Founder/Audio Engineer + 1–2 external reviewers)

---

### 3.2 Edge Cases & Stress Tests

| Scenario | Expected Behavior | Pass Criteria |
|---|---|---|
| **48 kHz, 512-frame buffer** | Nominal throughput | No dropouts, latency ≤10 ms |
| **96 kHz playback** | EQ/Clarity/Limiter all work at 2× sample rate | No glitches; latency ≤15 ms |
| **Very loud input (+3 dBFS)** | Limiter clamps to -1 dBTP | Output peak ≤ -1 dBTP; makeup gain compensates |
| **Very quiet input (-40 dBFS)** | Loudness makeup, no noise floor artifacts | Output noise floor <-100 dBFS; no pumping |
| **Sudden pause → resume** | No clicks, state resumes smoothly | Seamless playback, no audible artifacts |
| **Rapid intensity changes** | Smooth crossfade between states | No pops/clicks; gain ramp <1 dB per buffer |
| **Multiple files queued (future)** | State transitions between tracks | Loudness makeup updates for each track ±0.3 LU |

---

## 4. Test Execution & Reporting

### 4.1 Test Schedule

| Phase | Duration | Owner | Gate |
|---|---|---|---|
| **Unit tests** | ~3 days (during 1a–1d implementation) | Dev team | All tests green before phase completion |
| **Integration tests** | ~2 days (end of 1d + start of 1e) | Dev + QA | All tests green; null-test verified |
| **Manual QA** | ~2 days (1e) | QA + Audio Engineer | Sign-off checklist complete |
| **RT-safety audit** | ~1 day (1e) | Dev + Senior Reviewer | ASAN green, static analysis clear |

### 4.2 Test Results Reporting

**Format:** Test results logged in `docs/sprints/02-mix-core-test-results.md`

**Each test includes:**
- Test name + ID
- Input signal (file name / parameters)
- Expected vs. actual result
- Pass/Fail status
- Notes (if failed: root cause, mitigation)
- Timestamp

**Example:**
```
### Unit Test: EQ-FR-001 (Flat Response)

- Input: 1 kHz sine, 0 dBFS
- Expected: Output magnitude = input ±0.1 dB
- Actual: Input = -3.02 dBFS, Output = -3.04 dBFS (diff = 0.02 dB)
- Status: ✅ PASS
- Notes: Frequency response nominally flat; verified with audio analyzer
```

---

## 5. Definition of Test Done

### Pre-Implementation
- [ ] Test plan approved by Audio Engineer + QA Lead
- [ ] Test audio files prepared (pop, classical, jazz; 60 sec each)
- [ ] Listening environment verified (headphones + speakers + meter calibrated)
- [ ] Test harness scaffolding (unit test framework, integration test runner)

### During Implementation (Per Phase)
- [ ] Unit tests written + passing before module integration
- [ ] Code passes ASAN (no memory issues)
- [ ] Compiler warnings = 0

### Pre-Merge to main
- [ ] ✅ All unit tests passing (EQ, Clarity, Loudness, Limiter, Spatial)
- [ ] ✅ All integration tests passing (chain sweep, pink noise, music loop)
- [ ] ✅ Manual QA checklist signed off (≥2 listeners, all 3 test tracks)
- [ ] ✅ Null-test verified (A/B bypass = bit-identical)
- [ ] ✅ Real-time safety audit passed (ASAN + static analysis + code review)
- [ ] ✅ Test results documented in `02-mix-core-test-results.md`
- [ ] ✅ Zero compiler warnings
- [ ] ✅ Test coverage ≥90% (line coverage for critical modules)

---

## 6. Risk Mitigation via Testing

| Risk | Test | Mitigation |
|---|---|---|
| Convolution latency exceeds budget | Integration: latency measurement @ 48/96 kHz | Profile early; defer to phase 1.5 if >5 ms |
| Clarity false positives | Unit: confidence gate test; Manual: edge case listening | Tune gate threshold on reference tracks |
| Loudness makeup pumping | Manual: rapid volume changes + sustained audio loops | Rate-limit makeup to fader changes only |
| Phase artifacts audible | Manual: listening on phase-sensitive music (orchestral) | Offer linear-phase mode if detected |

---

## 7. Test Tooling & Automation

### Tools & Frameworks
- **Unit test runner:** XCTest (Swift) + custom C++ test harness
- **Audio generation:** Accelerate.vDSP (reference sweeps, pink noise)
- **Measurement:** Audio Analyzer app (iOS) + Audacity (spectral analysis) + Dolby Media Meter
- **CI/CD:** GitHub Actions (run unit tests on every commit)
- **Memory safety:** ASAN (AddressSanitizer) + Valgrind (optional)
- **Code coverage:** llvm-cov (generate coverage reports)

### Automated Test Execution
```bash
# Unit tests
swift test --parallel --verbose

# Integration tests (audio workbench)
./scripts/test-audio-chain.sh --input music.flac --config full-chain

# ASAN (memory safety)
swift test -Xswiftc -sanitize=address

# Coverage report
llvm-cov export --format lcov swiftc-coverage > coverage.lcov
```

---

## 8. Acceptance Criteria Summary

**All of the following must be true to mark Phase 1 complete:**

1. ✅ **Unit test coverage ≥90%** (critical paths: EQ, Limiter, Loudness)
2. ✅ **Zero compiler warnings**
3. ✅ **Zero ASAN violations** (memory safety)
4. ✅ **Integration tests green** (chain sweep, pink noise, music loop)
5. ✅ **Null-test passed** (Intensity 0% = bit-identical bypass)
6. ✅ **Manual listening QA sign-off** (≥2 listeners, ≥3 test tracks, all criteria met)
7. ✅ **No dropouts @ 48 kHz, 512 frames** (11.6 ms buffer; worst-case latency ≤5 ms added)
8. ✅ **Real-time safety audit passed** (code review + ASAN + static analysis)
9. ✅ **Test results documented** (`02-mix-core-test-results.md`)
10. ✅ **All code committed, formatted, documented**

---

**Reference:** See [Sprint 2 Implementation Plan](02-mix-core-plan.md) and [Sprint 2 Briefing](02-mix-core-briefing.md).

**Prepared by:** QA Team  
**Date:** 2026-06-14  
**Status:** Ready for Team Review & Execution
