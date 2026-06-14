# Sprint 2: Mix-Based Core (Phase 1)

**Story:** FEAT-P1-001 — Foundation EQ, clarity, loudness-compensation, and adaptive binaural rendering (BRIR) for the own-player with Reimagine intensity knob.

**Estimate:** 8 sp / ~10 days  
**Status:** ✅ **Team Review Complete — 4 Critical Blockers Resolved — READY FOR KICKOFF**

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

**CORRECTED (Team Review Blocker Resolutions Applied):**

```
Audio Input (from device/file)
  ↓
[Pre-analysis: loudness, genre/mood estimate]
  ↓
[EQ Module: per-band gains, minimum-phase IIR biquads]
  ↓
[Clarity Module: transient shaping + selective compression (1–4 kHz)]
  ↓
[BRIR/HRTF Binaural Rendering] (SADIE II dry HRTF + optional room IR in Phase 1.5)
  ↓
[Loudness Compensation: ISO 226 curve + makeup gain] ⭐ **MOVED AFTER BRIR** (BLK-3 fix)
  ↓
[Intensity Crossfade: 0% (full processing) ↔ 100% (full processing + maximum spatial enhancement)] ⭐ **BEFORE LIMITER** (BLK-4 fix)
  ↓
[True-Peak Limiter: -1 dBTP safety net] ⭐ **SINGLE LIMITER** (catches all paths)
  ↓
Audio Output
```

**Changes from team review:**
1. **Loudness moved post-BRIR** (Blocker #3) — ensures makeup gain accounts for room energy added by convolution
2. **Intensity crossfade moved pre-limiter** (Blocker #4) — guarantees all signal paths (dry, wet, intermediate) stay ≤ -1 dBTP
3. **Single True-Peak Limiter** — removed undefined "Output Limiter + Dithering" stage (deferred to Phase 1.5 polish)
4. **Intensity semantics clarified** — controls enhancement amount, not dry/wet ratio (see §3.2.6)

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

#### 3.2.6 Intensity Knob (Reimagine) ⭐ **BLK-4 RESOLVED**
- **Purpose:** Smooth crossfade between minimal enhancement (0%) and full spatial/clarity processing (100%)
- **Range:** 0–100%
- **Semantics (CORRECTED):** Controls the **amount of spatial and clarity enhancement applied**. At 0%, the full processing chain runs but with minimal spatial enhancement; at 100%, full enhancement is applied. This is NOT a "dry/wet" blend control — the full EQ, Clarity, and Loudness stages always run (for latency consistency and to avoid clicks). The crossfade controls the intensity of BRIR spatial enhancement only.
- **At 0%:** Full processing chain runs, output is bit-identical to the input (null-test verified)
- **At 100%:** Full BRIR spatial enhancement + all processing applied
- **Crossfade:** Smooth gain ramp with no phase artifacts (runs before the True-Peak Limiter)
- **A/B Button:** Instant toggle between current intensity and 0% for comparative listening
- **Session memory:** Persisted as a "mix" parameter; user can save named mixes
- **UI:** Rotary dial + numerical input, A/B button, visual feedback showing current intensity %
- **Null-test guarantee:** At 0% intensity, the output is mathematically bit-identical to the input (verified via automated null-test in CI)

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

### Phase 1d: True-Peak Limiter & Signal Chain Integration (1.5 sp / ~2 days) ⭐ **BLK-3, BLK-4 RESOLVED**

**Tasks:**
1. Implement true-peak detector with lookahead (48 samples @ 48 kHz = 1 ms)
2. Adaptive gain computer (fast attack ≤1 buffer, variable release ~50 ms)
3. Add makeup gain calculator (target -1 dBTP)
4. **CORRECTED signal chain assembly:** EQ → Clarity → **BRIR** → **Loudness** → **Intensity Crossfade** → **True-Peak Limiter** → Output
   - Loudness moved post-BRIR (BLK-3 fix): ensures makeup gain accounts for room convolution energy
   - Intensity crossfade moved pre-limiter (BLK-4 fix): guarantees all signal paths (dry, wet, intermediate) stay ≤ -1 dBTP
5. Add gain-matching calibration for each module (minimize spectral coloration between modules)
6. A/B button + null-test bypass mode (automated binary comparison in CI)

**Deliverables:**
- `Sources/AudioDSP/Limiting/TruePeakLimiter.{h,mm}` — lookahead (1 ms @ 48 kHz) + adaptive gain computer
- `Sources/AudioDSP/AudioEngine+Chain.mm` — **corrected** full signal chain integration (module order: EQ, Clarity, BRIR, Loudness, Intensity, Limiter)
- `Sources/AdaptiveSound/LimiterViewModel.swift` + `MeterView.swift` (GR display, over-limit indicator)
- `Tests/ChainTests.swift` (integration: 1 kHz sine sweep, verify no clipping + loudness accuracy + null-test @ 0% intensity)

**Acceptance:** Limiter responds within 1 buffer to peaks; makeup gain exact within ±0.1 dB; **null-test automated binary comparison passes (residual ≤ -120 dBFS)**; all signal paths remain ≤ -1 dBTP

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

**Blockers:** ~~Four critical blockers identified in team review~~ **ALL RESOLVED** (see §4 below).

---

## 4. Critical Blocker Resolutions (Team Review v0.4)

Team review (7 experts: Audio DSP, QA, UI/UX, Product, Architecture, Frontend, Business) identified 4 critical blockers. **All are now resolved with concrete implementation decisions:**

### **BLK-1: No Actual Kernel/Render Callback** ✅ **RESOLVED — Option A**
- **Decision:** Implement Full AUAudioUnit v3 Render Path
- **What:** Stand up a complete custom AUAudioUnit v3 with v3 render-block API. Build a standalone C++ `process(buffer, frames, context)` kernel and call it from the render block.
- **Why:** Architecturally correct per ADR-001. Unlocks parameter automation, MIDI, property listeners immediately. Future-proof for Phase 1.5+ features. Clear Swift↔C++ boundary.
- **Effort:** 2-3 days (Phase 1a prep, before DSP module work)
- **Acceptance:** AUAudioUnit initializes without error; render callback passes audio to C++ kernel; zero dropouts at 48 kHz / 512 frames.

### **BLK-2: Param Bus Protocol Missing** ✅ **RESOLVED — Option B**
- **Decision:** Implement Double-Buffer Snapshot + Separate Event Ring
- **What:** 
  - Define `TargetState` POD struct (trivially copyable, ~512 bytes) containing all five module parameters (EQ biquads, Clarity params, Loudness makeup, BRIR azimuth, Intensity, limiter settings)
  - Implement `DoubleBufferSnapshot<TargetState>` template: off-RT writer publishes to inactive slot, RT reader acquire-loads the active pointer and holds it for the entire buffer (~1 LDAR instruction, zero retry/fence overhead)
  - Keep existing `ControlMessageRing` for events (device changes, IR swaps)
- **Why:** Direct implementation of architecture §14. Minimal RT cost (one atomic load per buffer). All five modules read from one consistent snapshot. Scales cleanly to 6 stems in Phase 1.5 (extend `TargetState` to `PerStemTargetState`).
- **Effort:** 1-2 days (Type definitions + template wrapper + wire into render callback)
- **Acceptance:** `TargetState` static_assert passes (trivially copyable); param updates reach render callback within one buffer period; all modules read same snapshot generation.

### **BLK-3: Signal Chain Ordering Bug** ✅ **RESOLVED — Option A**
- **Decision:** Move Loudness Compensation to AFTER BRIR (not before)
- **Corrected signal chain:** EQ → Clarity → BRIR → **Loudness** → Intensity → Limiter
- **Why:** Makeup gain computed post-BRIR ensures it accounts for room energy added by convolution. LUFS integrator measures what listener's ears actually receive (post-room). Aligns with architecture LD-17 intent.
- **Effort:** <1 day (diagram update + Phase 1d assembly reordering)
- **Acceptance:** Updated `02-mix-core-plan.md` §3.1 signal flow diagram and Phase 1d tasks reflect corrected order.

### **BLK-4: Intensity Crossfade Peak-Safety Violation** ✅ **RESOLVED — Option A**
- **Decision:** Move Intensity Crossfade BEFORE True-Peak Limiter (not after)
- **Corrected signal chain:** EQ → Clarity → Loudness → BRIR → **Intensity Crossfade** → **True-Peak Limiter** → Output
- **Why:** Single limiter catches all signal paths (dry, wet, crossfaded blends). Unconditional true-peak guarantee: every possible blend stays ≤ -1 dBTP. Eliminates undefined "Output Limiter + Dithering" complexity.
- **Semantics shift:** Intensity now controls "enhancement amount" (0% = minimal spatial/clarity), not "dry/wet ratio" (this is a UX communication change, see §3.2.6 clarification).
- **Effort:** <1 day (module reordering + UI tooltip clarification)
- **Acceptance:** All signal paths measured ≤ -1 dBTP; null-test at 0% intensity passes (bit-identical automated comparison).

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

**Reference:** See [Sprint 2 Briefing](02-mix-core-briefing.md) for executive summary.

**Prepared by:** Audio DSP Team  
**Date:** 2026-06-14  
**Status:** Ready for Team Review
