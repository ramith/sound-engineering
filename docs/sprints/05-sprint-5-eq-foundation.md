# SPRINT 5: Minimum-Phase EQ Wiring & Spectral Correction

**Theme:** Professional-grade EQ foundation with device correction profiles  
**Effort:** 5–10 story points  
**Owner:** Audio DSP Agent + SwiftUI Pro  
**Prerequisite:** Sprint 4 (limiter + LUFS normalization wired)

---

## Vision

**EQ is the core user-facing feature.** This sprint wires the 31-band EQ module into the real-time AU graph, validates frequency response, loads device-correction profiles (AutoEq), and provides before/after spectrum visualization. Users move sliders and hear the result immediately.

**Why Industry-Best:**
- Minimum-phase EQ avoids pre-ringing (no audible artifacts before transients) — reference: FabFilter Pro-Q
- Biquad cascade is RT-efficient (no time-domain FIRs on audio thread)
- AutoEq profiles are scientifically grounded (crowd-sourced headphone measurements from Crinacle's rig)

---

## Core Deliverable

### 1. EQ Module Wired into RT Chain

**Specification:**
- **Type:** 31-band parametric EQ (ISO 266 standard frequencies)
- **Implementation:** Biquad cascade (10 biquads max, greedy least-mean-square fitting)
- **Phase Characteristic:** Minimum-phase (via vDSP coefficient calculation)
- **Gain Range:** ±20 dB per band
- **Update Rate:** Real-time parameter automation (slider move → audio change < 50 ms latency)

**Signal Flow:**
```
[Before-DSP Tap] → [EQ Module] → [Clarity stub] → [Loudness stub] → [BRIR stub] → [Limiter] → [Master Gain]
```

**Frequency Coverage (31 Bands):**
```
20, 25, 31.5, 40, 50, 63, 80, 100, 125, 160,
200, 250, 315, 400, 500, 630, 800, 1k, 1.25k, 1.6k,
2k, 2.5k, 3.15k, 4k, 5k, 6.3k, 8k, 10k, 12.5k, 16k, 20k
```

**RT Implementation Notes:**
- EQParams struct: array of 31 floats (gain per band, in dB)
- Realizer (off-RT): converts user gains → minimum-phase biquad coefficients
- ParameterBus (DoubleBuffer): lock-free handoff to RT kernel
- Per-buffer: apply biquad cascade to each sample (5 cascaded biquads = 10 poles)
- Pre-allocate biquad state at init (no allocations on RT)

**Wiring Checklist:**
- [ ] EQModuleCoefficients instantiated with 31 band centers
- [ ] Realizer off-RT computes biquad coefficients every parameter update
- [ ] ParameterBus publishes TargetState (EQ gains) to RT kernel
- [ ] EQ AU unit consumes TargetState, applies biquad cascade in process()
- [ ] Spectrum tap (after-DSP) reads processed audio for visualization

### 2. After-DSP Spectrum Tap

**Specification:**
- **Current State:** Before-DSP tap only (raw audio input)
- **New:** After-DSP tap (audio after EQ processing)
- **Display Layout:** 2 rows × 2 columns (before/after for L/R channels)
- **Update Rate:** ~20 Hz (same as before-DSP tap)

**Before-DSP (Row 1):**
```
Spectrum L (input)  |  Spectrum R (input)
```

**After-DSP (Row 2):**
```
Spectrum L (EQ)  |  Spectrum R (EQ)
```

**Visual Representation:**
- **Before:** Red (bass) → orange → green (mid) → blue (treble) — standard spectrum colors
- **After:** Darker/saturated version (to distinguish from before)
- **Magnitude:** Brightness by signal level (tall = bright, quiet = dark)

**RT Implementation Notes:**
- Same FFT tap architecture as before-DSP (SpectrumDoubleBuffer)
- Install tap after EQ module, before Clarity stub
- Spectrum analyzer runs on separate thread (not RT)
- Lock-free handoff (DoubleBuffer)

### 3. AutoEq Device Profiles

**Specification:**
- **Source:** Crinacle's measured headphone database (open-source, scientifically grounded)
- **Profiles to Ship:** 5 common headphones (covers ~60% of target user base)
  1. Sony WH-1000XM5 (wireless, ANC, popular)
  2. AirPods Pro (ecosystem fit, widely used)
  3. Sennheiser HD 600 (studio standard, flat baseline)
  4. Apple Studio Display (integrated audio, calibrated)
  5. Generic (fallback, mild presence peak for consumer headphones)
- **Format:** Per-profile: 31-band gain curve (dB) mapping to EQ band centers
- **Application:** Auto-detect connected device → load profile on startup (or device selection change)

**Loading Mechanism:**
- Query audio device name via Core Audio API
- Match name to profile database (fuzzy matching acceptable)
- If no match, default to Generic profile
- Load profile into EQ sliders programmatically (user doesn't see the load)
- Combine with user manual adjustments (profile is baseline, user fine-tunes on top)

**Profile Format (JSON or property list):**
```json
{
  "name": "Sony WH-1000XM5",
  "bands": [
    {"freq": 20, "gain_db": -1.2},
    {"freq": 25, "gain_db": -1.0},
    ...
    {"freq": 20000, "gain_db": 0.5}
  ]
}
```

**RT Implementation Notes:**
- Profiles loaded at app init or device selection (off-RT)
- Profile gains interpolated to 31 bands (spline if needed)
- User adjustments add to profile gains (profile + manual = total EQ)
- Arbiter composes: device profile + loudness compensation + clarity + user macros

### 4. Master Gain Relocation (Post-DSP)

**Current State:** Master gain on mixer (pre-DSP)  
**Change:** Move to after Limiter (post-DSP)

**Signal Flow:**
```
[EQ + DSP] → [Limiter] → [Master Gain] → Device Output
```

**Implication:**
- Volume slider doesn't affect spectrum visualization
- Spectrum shows magnitude of DSP effect (not total loudness)
- Volume is truly independent (user can turn down without affecting EQ curves)

**Implementation:** Relocate mainGainNode in AU graph wiring

---

## Validation Plan

### Unit Tests (Automated)

**Test Suite:** `AudioDSPTests/EQTests.swift`

#### EQ Module Tests
1. **Biquad stability:** All coefficient sets stable (poles inside unit circle)
   - Generate 1000 random gain curves
   - Compute biquad coefficients for each
   - Verify stability analytically (or via Z-plane calculation)
   - Assert: all stable

2. **Null-test (identity curve):** 0 dB on all bands = bit-identical to input
   - Input: 1-second white noise
   - Config: all 31 bands = 0 dB
   - Assert: output MD5 match to input (or ≤ −120 dB THD+N)

3. **Frequency response accuracy:** Apply single-band boost → measure magnitude at center
   - Test: boost band 10 (1 kHz) by +6 dB
   - Measure: magnitude response at 1 kHz
   - Assert: response = +6 dB ± 0.5 dB (within tolerance)

4. **Gain linearity:** ±20 dB range in both directions
   - Test: −20, −10, 0, +10, +20 dB on single band
   - Assert: measured response matches expected gains ± 0.5 dB

5. **Phase coherence (minimum-phase validation):** Group delay must be non-negative
   - Generate random gain curve → compute phase response
   - Assert: group delay monotonically increasing or constant (no pre-ringing)

6. **Parameter ramping (no zipper noise):** Smooth transition on slider change
   - Test: change one band gain from 0 → +6 dB over 50 samples
   - Analyze output: no audible spectral glitch at transition
   - Assert: smooth ramp in time domain (inspect for clicking)

#### Frequency Response Tests
1. **Log-sweep accuracy:** Feed log-sweep (20 Hz–20 kHz) → measure magnitude response
   - Config: flat (0 dB) curve
   - Assert: output magnitude ± 0.1 dB at each ERB-rate grid point (44 ERB bands)

2. **Band isolation:** Boost single band → measure neighboring bands
   - Test: boost 100 Hz by +6 dB
   - Assert: 80 Hz and 125 Hz adjacent bands show < ±1 dB bleed
   - Assert: 1 kHz and beyond show < ±0.5 dB bleed

3. **Cascade stability:** All 5 cascaded biquads remain stable
   - Apply full +20 dB boost across all bands
   - Assert: no clipping, no overflow, stable output

#### AutoEq Profile Tests
1. **Profile loading:** Load each of 5 profiles
   - Assert: no parse errors, all 31 bands present
   - Assert: gains within reasonable range (−10 to +10 dB typical)

2. **Profile application:** Load profile → apply to EQ → measure effect
   - Test: load Sony WH-1000XM5 profile → measure frequency response
   - Assert: output curve matches target within ±2 dB (allowing for biquad approximation)

### Integration Tests (Manual + Scripted)

#### Frequency Response Measurement
- **Setup:** Play log-sweep tone (20 Hz–20 kHz) through EQ
- **Config:** Apply known curve (e.g., +3 dB @ 100 Hz, +6 dB @ 1 kHz, +3 dB @ 10 kHz)
- **Measure:** Capture output, FFT analysis
- **Assert:** Response matches target ±1 dB in perceptually salient bands (500 Hz–5 kHz)

#### Before/After Spectrum Visualization
- **Setup:** Play music file → capture before/after spectrum
- **Procedure:**
  1. Capture "before" spectrum (input)
  2. Apply EQ curve (single band, e.g., +6 dB @ 1 kHz)
  3. Capture "after" spectrum
  4. Visually compare: "after" should show peak at 1 kHz relative to "before"
- **Assert:** Peak visible, magnitude ≈ +6 dB

#### Device Profile Autoload
- **Setup:** Connect different audio devices (headphones, speakers, AirPods)
- **Procedure:**
  1. Connect device A (e.g., Sony WH-1000XM5)
  2. Launch app → observe profile load (log file confirms load)
  3. Measure frequency response → should match Sony profile
  4. Switch to device B (e.g., AirPods Pro)
  5. App auto-switches profile → frequency response changes
- **Assert:** Profile loaded correctly, EQ curve changes per device

#### Slider Responsiveness (Latency Test)
- **Setup:** Move EQ slider → measure time to audio change
- **Procedure:**
  1. Set audio latency monitor
  2. Move slider from 0 dB → +6 dB
  3. Time: slider move (UI) → spectrum changes (audio effect visible)
- **Assert:** latency < 50 ms (imperceptible to user)

#### THD+N Measurement
- **Setup:** Generate 1 kHz sine @ −10 dBFS → run through EQ at various gain settings
- **Measure:** FFT analysis, sum of harmonics + noise floor
- **Configs:**
  - All bands 0 dB (baseline)
  - Single band +6 dB
  - All bands +6 dB
  - Worst-case: +20 dB on multiple bands
- **Assert:** THD+N ≤ −90 dB in all configs (professional-grade target)

#### Parameter Smoothing (Zipper Test)
- **Setup:** Play 1 kHz sine → move EQ slider at 1 slider/sec
- **Procedure:**
  1. Adjust band from 0 dB → +20 dB smoothly over 20 seconds
  2. Listen for zipper noise (digital clicking)
  3. Inspect spectrogram (should be smooth, no spectral spikes)
- **Assert:** Inaudible parameter ramp (no zipper noise)

#### 5-Minute Soak Test
- **Setup:** Play diverse 5-track playlist (vocal, acoustic, electronic, classical, orchestral)
- **Procedure:**
  1. Move EQ sliders throughout
  2. Switch device profiles mid-playback
  3. Monitor for xruns, dropouts, glitches
- **Assert:** Zero xruns, stable audio, responsive EQ

### Listening Panel (5–10 Audio Engineers)

**Protocol:** MUSHRA-style blind A/B on 5 reference tracks

**Test 1: Null-Test (0 dB EQ)**
- Candidate A: Unprocessed original
- Candidate B: Through EQ @ 0 dB (flat curve)
- Question: Do they sound identical?
- Pass: ≥90% say identical (EQ should be transparent at 0 dB)

**Test 2: Presence Peak (+3 dB @ 2–4 kHz)**
- Candidate A: Unprocessed original
- Candidate B: EQ with presence peak
- Question: Which sounds more present? (A / B / Same)
- Pass: ≥70% identify B as more present

**Test 3: Bass Boost (+6 dB @ 80–100 Hz)**
- Candidate A: Unprocessed
- Candidate B: EQ with bass boost
- Question: Which has more bass weight? (A / B / Same)
- Pass: ≥80% identify B as having more bass

**Test 4: Subjective EQ Quality**
- Play 5 diverse tracks with your chosen EQ curve (e.g., Sony WH-1000XM5 profile)
- Question: Does the EQ sound natural? (Natural / Slightly colored / Obviously EQed / Artifacts)
- Pass: ≥80% rate "Natural" or "Slightly colored"

**Test 5: Frequency-Response Accuracy**
- Play log-sweep (20 Hz–20 kHz) with known EQ applied
- Question: Can you hear the EQ curve? (Yes / Somewhat / No / Artifacts)
- Pass: ≥80% hear the intentional curve, ≤20% report artifacts

---

## Open Questions & Design Decisions

| Question | Decision | Rationale |
|----------|----------|-----------|
| **Biquad cascade depth: 5 or 10 biquads?** | Start with 5 (10 poles); measure fitting error; add more if needed | 5 is usually sufficient; avoid over-parameterization |
| **AutoEq profile source: Crinacle or generate custom?** | Ship Crinacle (open-source, credible); generate custom if user feedback suggests it | Crinacle is industry-standard, faster to ship |
| **Device matching: exact name or fuzzy?** | Fuzzy string match (e.g., "Sony WH-1000XM5" matches "Sony WH-1000XM5 (AirPlay)") | Handles device name variations |
| **Profile storage: JSON, plist, or compiled C++?** | JSON (human-readable, easy to extend with more profiles) | Maintainability wins |
| **User manual EQ + profile compositing: add or blend?** | Add (user gains + profile gains = total) | Preserves user intent on top of profile |

---

## Acceptance Criteria (Done-Done)

- [ ] EQ module vDSP biquad code compiles, passes unit tests (6/6 tests)
- [ ] Frequency response accuracy ±0.5 dB verified via log-sweep (4/4 FR tests)
- [ ] Null-test: 0 dB curve = bit-identical (−120 dB THD+N)
- [ ] THD+N ≤ −90 dB across all EQ settings
- [ ] AutoEq profiles loaded correctly (5/5 profiles parse, apply)
- [ ] Device profile auto-switch verified (3 devices tested)
- [ ] Before/after spectrum taps functional (visual change matches audio change)
- [ ] Slider responsiveness < 50 ms latency
- [ ] Parameter smoothing: no zipper noise on slider movement
- [ ] 5-minute soak test: zero xruns, stable audio
- [ ] Listening panel: ≥70% prefer curves, ≥80% rate "Natural"
- [ ] Code review: ASAN/TSan clean
- [ ] Documentation: EQ module README + AutoEq profile guide

---

## Dependencies & Blockers

**Unblocked By:**
- ✅ Sprint 4 (limiter wired, safe floor established)
- ✅ EQModuleCoefficients unit-tested code (exists from Phase 1a)

**Blocks:**
- 🟡 Sprint 6 (clarity module builds on EQ foundation)
- 🟡 Phase 1c release (EQ is headline feature)

---

## Success Story (What "Done" Looks Like)

> **User launches Adaptive Sound, connects AirPods Pro.**
>
> App auto-loads AirPods Pro profile. EQ sliders move to a subtle presence peak + slight bass lift. Spectrum shows before (flat) and after (boosted profile).
>
> **User plays lo-fi track. It sounds warmer, more present.**
>
> User adjusts the 1 kHz slider up another +3 dB. Spectrum updates in real-time. Vocal presence pops. Latency imperceptible.
>
> **Later, user switches to open-back headphones. App auto-switches profile. Spectrum shifts; EQ curve adapts.** Listening experience optimized per device.
>
> **Listening panel of 8 mastering engineers A/Bs your EQ.** None report artifacts. ≥80% rate processing as "Natural." Consensus: "Frequency response is accurate. Could use it for critical listening."

---

**Status:** Ready for implementation  
**Next:** Begin Sprint 5 coding after Sprint 4 ships
