# Sprint 2: Mix-Based Core (Phase 1)

**Story:** FEAT-P1-001 — Foundation EQ, clarity, loudness-compensation, and adaptive binaural rendering (BRIR) for the own-player with Reimagine intensity knob.

**Estimate:** 8 sp / ~10 days  
**Status:** Ready for Team Review → Implementation

---

## Executive Summary

Build the foundational **DSP signal chain** and **intensity-controlled output mixer** for the own-player (Phase 1). Deliver:
1. **Per-band parametric EQ** with user-visible frequency graph
2. **Clarity (unmask)** module — frequency-selective compression + transient shaping
3. **Loudness compensation** (ISO 226) + true-peak safety limiter  
4. **BRIR binaural rendering** (HRTF + early + late reverb via SADIE II) — OR defer to Phase 1.5 if timeline compressed
5. **Reimagine intensity knob** (0% = bypass/bit-faithful → 100% = full processing)
6. **Perceptual loudness metering** (ERB/Bark) and masking cost estimation

Output: Single-file .m4a export with adaptive processing baked in, OR live playback through the engine with a visual intensity dial.

---

## Acceptance Criteria

- ✅ **EQ module:** 31-band parametric EQ, minimum-phase by default, settable gain ±12 dB per band
- ✅ **Clarity module:** masking-aware transient sharpening (attack <2ms) + selective compression in the clarity bands (1–4 kHz)
- ✅ **Loudness:** LUFS metering per-track + loudness-matched makeup to LUFS-16 reference (configurable)
- ✅ **True-peak limiter:** prevents clipping, responds within <1 buffer period
- ✅ **BRIR or minimal-mode HRTF:** at least dry HRTF from SADIE II (defer full BRIR convolution if necessary)
- ✅ **Intensity knob:** crossfade-able, 0–100%, persisted in session/saved mixes
- ✅ **A/B switching:** instant-mute bypass mode for null-testing
- ✅ **UI:** frequency graph, loudness meter, intensity dial, A/B button
- ✅ **Real-time safety:** no dropouts at 48 kHz / 512 frames (11.6 ms), preload all BRIR/HRTF data
- ✅ **Test coverage:** unit tests for EQ, limiter, loudness calc; integration tests for signal chain; manual QA for spatial/phase
- ✅ **Zero git warnings; code formatted; documentation updated**

---

## Architecture & Design

### 3.1 Signal Flow

```
Audio Input (from device/file)
  ↓
[Pre-analysis: loudness, genre/mood estimate]
  ↓
[EQ Module: per-band gains, minimum-phase FIR]
  ↓
[Clarity Module: transient shaping + selective compression]
  ↓
[Loudness Compensation: ISO 226 curve + makeup gain]
  ↓
[BRIR/HRTF Binaural Rendering] (SADIE II)
  ↓
[True-Peak Limiter: <-1 dBTP]
  ↓
[Intensity Crossfade: 0% (dry bypass) ↔ 100% (full processing)]
  ↓
[Output Limiter + Dithering]
  ↓
Audio Output
```

### 3.2 Module Breakdown

#### 3.2.1 EQ Module
- **Type:** Parametric (IIR biquads) for real-time, OR FIR (minimum-phase) if latency budget allows
- **Bands:** 31 ISO-standard frequencies (20 Hz → 20 kHz)
- **Gain range:** ±12 dB per band (Q ≈ 1.0 for moderate precision)
- **Phase mode:** minimum-phase by default; user can override to linear-phase for specific sources
- **Presets:** Flat, Presence, Clarity, Warm (examples; customizable)
- **UI:** Interactive frequency graph with draggable band points, numeric entry, preset recall

#### 3.2.2 Clarity Module
- **Purpose:** Unmask overlapping sources by selectively sharpening transients and compressing dynamic content in the presence band (1–4 kHz)
- **Transient shaper:** detect onset → gate or boost pre-compression (attack ~0.5 ms, decay ~50 ms)
- **Compression:** 2:1 ratio, threshold -20 dB, knee soft (6 dB), makeup gain auto-calculated
- **Gate condition:** confidence mask (internal estimate: is this a "clean" transient or spectral noise?) — if low confidence, skip
- **UI:** "Clarity" toggle + intensity slider (0–100%); visual meter shows transient confidence

#### 3.2.3 Loudness Compensation
- **Standard:** ISO 226:2023 equal-loudness contours (or 2003 fallback if unavailable)
- **Input:** measured per-track LUFS (integrated), reference = -16 LUFS
- **Output:** gain applied to match perceived loudness across tracks
- **Rate limiting:** makeup gain changes only on volume fader moves (not continuously), preventing audible pumping
- **UI:** LUFS meter (integrated + short-term), reference level selectable, makeup gain display

#### 3.2.4 BRIR Binaural Rendering (Phase 1.5; or minimal HRTF now)
- **Now (Phase 1):** Dry HRTF from SADIE II (45 HRTF azimuths × 10 elevations) via linear interpolation + fast convolution (Convolver/vDSP)
- **Phase 1.5:** Full BRIR (early reflections + late reverb tail), content-adaptive room amount
- **Bass exemption:** frequencies ≲120 Hz high-passed out, summed mono (patent avoidance, LD-17)
- **Vocal center-lock:** lead vocal detected → no L/R spread (intensity control only)
- **Presets:** Neutral room (SADIE II anechoic), "Living Room", "Concert Hall" (apply room IR only)
- **UI:** Room selector, spatial width slider, optional head-tracking toggle (macOS 14+)

#### 3.2.5 True-Peak Limiter
- **Algorithm:** Adaptive threshold, <1 ms attack, variable-rate release
- **Target:** -1 dBTP (European standard; -1.5 dBTP alternative for streaming legacy)
- **Lookahead:** 1–2 buffer periods (48 samples @ 48 kHz = 1 ms)
- **Metering:** gain reduction (GR) dB displayed; over-limit indicator (red flash if held >100 ms)
- **UI:** Threshold, makeup gain (auto-calibrated), GR meter, bypass (for measurement/null-test)

#### 3.2.6 Intensity Knob (Reimagine)
- **Purpose:** Smooth crossfade between original (dry, bit-faithful) and processed (wet, full chain)
- **Range:** 0–100%
- **At 0%:** Processor chain still runs (for latency consistency), output is bit-identical bypass
- **At 100%:** Full processing (EQ + clarity + loudness + BRIR + limiting)
- **Crossfade:** Gain-matched crossfade on wet/dry signal (amplitude envelope only, no phase warping)
- **Session memory:** Persisted as a "mix" parameter; user can save named mixes
- **UI:** Rotary dial + numerical input, A/B button (flip between current intensity and 0%)

### 3.3 Perceptual Loudness & Masking (Analysis Layer)

Pre-analysis (done offline; cached):
- **File-level LUFS:** integrated loudness
- **Genre/mood:** optionally use Create ML classifier (trained on >1000 labeled clips) to inform EQ presets
- **Transient density:** onset detection → trigger clarity shaping confidence

Real-time (on per-buffer):
- **ERB-band loudness:** ~40 bands (ERB scale) instead of full spectrum
- **Masking cost:** estimate frequency-band masking per each other band; used to constrain gain changes
- **Confidence mask:** per-stem (Phase 1.5) or per-frequency-region (Phase 1), for gating clarity/compression moves

---

## Implementation Breakdown

### Phase 1a: EQ Module & Testing (2 sp / ~2.5 days)

**Tasks:**
1. Design vDSP/Accelerate-based biquad cascade (IIR EQ) with per-band coefficient updates
2. Implement 31-band parametric EQ with ISO-standard center frequencies
3. Add unit tests (frequency response sweeps, gain linearity, group delay check)
4. SwiftUI: interactive frequency graph + band editor
5. Serialize/deserialize EQ state (JSON) for preset saving

**Deliverables:**
- `Sources/AudioDSP/EQ/ParametricEQ.{h,mm}` — C++ vDSP/Accelerate kernel
- `Sources/AdaptiveSound/EQViewModel.swift` + `EQView.swift` — UI
- `Tests/EQTests.swift` — unit tests (gain, frequency, phase)

**Acceptance:** Zero dropouts at 48 kHz; frequency response matches expected ±0.2 dB; UI responsive

---

### Phase 1b: Clarity Module & Loudness (2 sp / ~2.5 days)

**Tasks:**
1. Implement transient detection (peak-picking + envelope follower)
2. Build selective compressor (1–4 kHz band, 2:1 ratio, soft knee)
3. Add gate confidence logic (check spectral flatness near transient)
4. Implement ISO 226 loudness curve lookup table
5. Calculate per-track LUFS (via libebur128 or Core Audio loudness API)
6. Makeup gain logic (rate-limited, only on volume change)

**Deliverables:**
- `Sources/AudioDSP/Clarity/ClarityModule.{h,mm}` — transient shaper + selective compressor
- `Sources/AudioDSP/Loudness/LoudnessAnalyzer.{h,mm}` — LUFS metering + ISO 226 makeup
- `Sources/AdaptiveSound/ClarityViewModel.swift` + `ClarityView.swift`
- `Sources/AdaptiveSound/LoudnessViewModel.swift` + `LoudnessView.swift`
- `Tests/ClarityTests.swift`, `Tests/LoudnessTests.swift`

**Acceptance:** Clarity toggle measurable in A/B tests; LUFS accuracy ±0.5 LU vs. reference tool; makeup gain smooth + imperceptible rate

---

### Phase 1c: BRIR/HRTF & Intensity (2 sp / ~2.5 days)

**Tasks:**
1. Integrate SADIE II HRTF dataset (precompiled IR file, ~5 MB)
2. Implement fast convolution (FFTConvolver or vDSP-based linear convolution with latency budget)
3. Design spatial width interpolation between center-lock (0%) and max spread (100%)
4. Implement wet/dry crossfade logic for intensity knob (0–100%)
5. Build UI: room selector, intensity dial, width slider
6. Session + mix state serialization (JSON)

**Deliverables:**
- `Sources/AudioDSP/Spatial/HRTFRenderer.{h,mm}` — SADIE II convolution
- `Sources/AdaptiveSound/SpatialViewModel.swift` + `SpatialView.swift`
- `Sources/AdaptiveSound/IntensityViewModel.swift` + `IntensityDialView.swift`
- `Assets/SADIE-II-HRTF-compact.bin` (precompiled IR set)
- `Tests/SpatialTests.swift` (phase coherence, latency check)

**Acceptance:** No phase wrapping audible; latency ≤5 ms added; intensity knob crossfade imperceptible; room selector loads ≤1 sec

---

### Phase 1d: True-Peak Limiter & Signal Chain Integration (1.5 sp / ~2 days)

**Tasks:**
1. Implement true-peak detector with lookahead (1–2 buffers)
2. Adaptive gain computer (fast attack <1 ms, variable release)
3. Add makeup gain calculator (target -1 dBTP)
4. Assemble final signal chain: EQ → Clarity → Loudness → HRTF → Limiter → Output
5. Add gain-matching calibration for each module
6. A/B button + null-test bypass mode

**Deliverables:**
- `Sources/AudioDSP/Limiting/TruePeakLimiter.{h,mm}` — lookahead + adaptive gain
- `Sources/AudioDSP/AudioEngine+Chain.mm` — full signal chain integration
- `Sources/AdaptiveSound/LimiterViewModel.swift` + `MeterView.swift` (GR display)
- `Tests/ChainTests.swift` (integration test: 1 kHz sine sweep, verify no clipping + loudness accuracy)

**Acceptance:** Limiter responds within 1 buffer to peaks; makeup gain exact within ±0.1 dB; null-test button reveals processing artifacts clearly

---

### Phase 1e: Manual QA, Bug Fixes & Documentation (0.5 sp / ~1 day)

**Tasks:**
1. Manual listening tests (headphones + speakers, A/B null tests)
2. Check for RT-safety violations (no allocations, sleeps, etc. on audio thread)
3. Fix any remaining UI responsiveness issues
4. Update README, architecture docs, and acceptance criteria
5. Sprint retro: velocity, blockers, next-sprint lessons

**Deliverables:**
- Updated `README.md` (Phase 1 feature list, usage guide)
- Updated `docs/architecture/` (revised signal chain, module specs)
- Sprint 2 retro doc: `docs/sprints/02-mix-core-retro.md`

**Acceptance:** Zero compiler warnings; all tests green; no audio dropouts; manual QA sign-off

---

## Dependencies & Blockers

| Dependency | Status | Note |
|---|---|---|
| SADIE II HRTF dataset (Apache-2.0) | Available | Precompiled / pre-linked; no build dependency |
| FFTConvolver or vDSP fast convolution | Available | vDSP preferred; FFTConvolver fallback (MIT) |
| libebur128 or Core Audio loudness API | Available | libebur128 (MIT) or use AVAudioEngine metering |
| Create ML trained model (genre/mood) | Deferred to Phase 1.5 | Not required for Phase 1 MVP |
| Stem separation (Demucs/MLX) | Deferred to Phase 1.5 | Not on critical path; band approximation sufficient for Phase 1 |

**Blockers:** None known. Real-time safety constraints are well-understood from Sprint 1.

---

## Risk Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Convolution latency exceeds budget | Medium | Pre-compute short IRs (~256 samples); partition-convolution if needed; profile early |
| Clarity module false positives (gating noise) | Medium | Use confidence masking (spectral flatness check) + manual tuning on reference tracks |
| Loudness makeup pumping audible | Low | Rate-limit makeup gain to fader-change events only; validate with 20–30 sec audio loop |
| Phase artifacts from minimum-phase EQ | Low | Profile phase response; add linear-phase option for sources with known phase-sensitive content |
| HRTF rendering off-center (head-tracked) | Low | Defer head-tracking to Phase 1.5; Phase 1 uses fixed azimuth (front-center, 0°) |
| iOS/iPad port scope creep | High | Explicitly scope to **macOS only** for Phase 1; defer iOS to post-Phase 2 |

---

## Definition of Done

### Before Implementation
- [ ] Sprint 2 plan approved by team (architecture, story breakdown, test strategy)
- [ ] Risks reviewed with team; mitigation plan locked
- [ ] Implementation schedule agreed (target: ~2 weeks / 10 business days)

### During Implementation
- [ ] Code commits follow naming conventions (feat/fix/test prefix + story ID)
- [ ] Each module has unit tests (EQ, Clarity, Loudness, Limiter, Spatial)
- [ ] Integration tests verify signal chain (sweep + null-test audio)
- [ ] Real-time safety reviewed: no malloc/locks on audio thread
- [ ] UI updates reviewed for responsiveness + accessibility

### Pre-Release / Merge to main
- [ ] All tests pass (Unit + Integration)
- [ ] Manual QA checklist complete:
  - [ ] Headphone listening test (A/B null tests)
  - [ ] Speaker listening test (mono-compatibility check)
  - [ ] No dropouts at 48 kHz / 512 frames
  - [ ] Intensity knob crossfade smooth + imperceptible
  - [ ] All presets load without error
- [ ] Code formatted (clang-format + swiftformat)
- [ ] Zero compiler warnings
- [ ] Documentation updated (README, architecture, API comments)
- [ ] Sprint 2 retrospective completed
- [ ] Sign-off from Founder/Audio Engineer

---

## Timeline

| Phase | Duration | Key Milestones |
|---|---|---|
| **Kickoff** | 0.5 days | Team review meeting, blockers cleared, development starts |
| **1a: EQ** | 2.5 days | EQ kernel + UI complete, unit tests green |
| **1b: Clarity + Loudness** | 2.5 days | Both modules integrated, manual listening QA starts |
| **1c: BRIR + Intensity** | 2.5 days | Spatial rendering works, intensity knob responsive |
| **1d: Limiter + Chain** | 2 days | Full signal chain, null-test validated |
| **1e: QA + Retro** | 1 day | Manual tests, bug fixes, sprint retro, merge to main |
| **Total** | ~10 days (2 weeks) | Ready for Phase 1.5 planning or Phase 2 research |

---

## Open Questions / Deferred

1. **OQ-23 (Phase 1.5):** Should stem separation happen in Sprint 2 or Sprint 3?  
   → **Deferred to Phase 1.5.** Band-approximation EQ is the MVP for Phase 1; stem-object engine is a separate sprint.

2. **OQ-24 (Export/Save):** File export (render to .m4a) or live playback only in Phase 1?  
   → **Deferred to Phase 1.5.** Phase 1 focuses on playback + real-time tuning. Export comes after audio pipeline is stable.

3. **OQ-25 (Genre Model Training):** Train Create ML model in-house or use a pre-trained model?  
   → **Deferred to Phase 1.5.** Phase 1 uses heuristic genre detection (spectral shape); ML model is optional enhancement.

---

## Success Metrics

- ✅ Phase 1 shipped on main without blocking Phase 1.5 or Phase 2
- ✅ Zero audio dropouts at 48 kHz on target hardware (M1 Pro / 16 GB)
- ✅ Listening tests show measurable improvement (A/B null tests + blind panel feedback)
- ✅ Velocity ≥7 sp / sprint (estimate quality for future planning)
- ✅ Code quality: ≥90% unit test coverage, zero RT-safety violations

---

**Prepared by:** Audio DSP Team  
**Date:** 2026-06-14  
**Status:** Ready for Team Review
