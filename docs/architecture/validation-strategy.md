# Audio Quality Validation Strategy

**Purpose:** Define comprehensive validation gates for Sprints 1–3 (Phase 1c MVP)  
**Scope:** Unit tests, integration tests, listening panels, regression gates, soak tests  
**Approval:** QA Expert + Audio DSP + Project Lead  
**Maintenance:** Update per sprint

---

## Validation Philosophy

**Three Pillars:**
1. **Automated Testing** — Catch regressions quickly (null-test, THD+N, frequency response)
2. **Integration Testing** — Verify end-to-end behavior (soak tests, device switching, parameter automation)
3. **Listening Panel** — Validate perceptual quality (professional audio engineers, MUSHRA-style)

**Principle:** Automated tests verify code correctness. Listening panel validates that DSP actually sounds good.

---

## Per-Merge Gates (Automated, < 15 Minutes)

**Runs on every PR to `main`.** Must pass before merge.

### Gate 1: Unit Test Suite
```bash
swift test --configuration release
```

**Requirements:**
- All unit tests pass (0 failures)
- Code coverage ≥ 80% for signal-path code (EQ, clarity, limiter, loudness)
- No timeouts (signal tests must complete < 5 sec each)

**Test Suites:**
- `AudioDSPTests/EQTests.swift` — Biquad stability, frequency response, null-test
- `AudioDSPTests/LimiterTests.swift` — Peak enforcement, GR response, oversampling
- `AudioDSPTests/LoudnessTests.swift` — LUFS accuracy, makeup gain, gating
- `AudioDSPTests/ClarityTests.swift` — Masking model, gain limits, intensity
- `AudioDSPTests/ArbiterTests.swift` — Composition, lock-free handoff
- `SwiftUITests/AudioEngineTests.swift` — Playback control, parameter automation

### Gate 2: Null-Test (Bit-Exact Bypass)

**Purpose:** Verify that intensity 0% produces bit-identical output

```bash
# Generate test signal (1 sec white noise @ 48 kHz)
sox -n -r 48000 -c 2 test_input.wav synth 1 white gain -n

# Run through app @ intensity 0%
./AdaptiveSound --input test_input.wav --output test_output.wav --intensity 0

# Compare
md5sum test_input.wav test_output.wav  # Should match OR...
ffmpeg -i test_input.wav -i test_output.wav -af "spectraldiff" -f null - 2>&1 | grep "THD+N"
# Assert: THD+N ≤ −120 dB
```

**Acceptance:** MD5 match OR THD+N ≤ −120 dB

### Gate 3: Frequency Sweep (Baseline Regression)

**Purpose:** Quick sanity check that EQ response is reasonable

```bash
# Generate log-sweep (20 Hz–20 kHz)
sox -n -r 48000 -c 1 sweep_input.wav synth 1 sine 20 20000 gain -n -10

# Run through app @ flat EQ (0 dB all bands)
./AdaptiveSound --input sweep_input.wav --output sweep_output.wav --intensity 50 --eq "flat"

# Measure magnitude response
ffmpeg -i sweep_output.wav -af "spectrogram" -f image2 spectrum.png

# Assert: No 20+ dB spikes (indicates DSP bug)
```

**Acceptance:** Spectrum smooth, no anomalies

### Gate 4: ASAN + TSan + clang-tidy

```bash
swiftc -sanitize=address -sanitize=undefined [sources] -o app
./app --test-signal "1khz_sine" # Run for 10 sec

# Assert: No address sanitizer errors, no undefined behavior
# Also run clang-tidy for C++ modules
clang-tidy --checks=readability-*,cppcore* [sources] -- -I... -std=c++17
```

**Acceptance:** Zero violations

---

## Nightly Regression Suite (Full, ~30 Minutes)

**Runs every night.** Designed to catch subtle regressions.

### Test 1: Biquad Fitting Stress
```cpp
// Generate 1000 random gain curves
for (int i = 0; i < 1000; i++) {
  std::vector<float> gains(31);
  for (int j = 0; j < 31; j++) {
    gains[j] = (float)(rand() % 41 - 20) / 10.0f; // ±20 dB
  }
  
  // Compute biquad coefficients
  auto coeff = eqModule.realizer(gains);
  
  // Assert stability (poles inside unit circle)
  assert(coeff.isStable());
  
  // Assert gain accuracy
  float measured = frequencyResponseAt(coeff, 1000.0f);
  assert(abs(measured - expectedGain) < 0.5f); // ±0.5 dB tolerance
}
```

**Acceptance:** All 1000 curves stable, gains within tolerance

### Test 2: 20-Track Corpus End-to-End
```bash
# Play 20-track test corpus (varied genres, dynamic range)
for track in corpus/*.wav; do
  ./AdaptiveSound --input "$track" \
                  --output "${track%.wav}_processed.wav" \
                  --duration 30sec \
                  --intensity 50 \
                  --simulate-loudness-changes yes
done

# Measure:
# - LUFS accuracy (vs. ffmpeg ebur128)
# - BRIR convolution correctness (correlation to reference)
# - RT-safety metrics (no xruns, p99.9 render ≤ 5 ms)
```

**Acceptance:**
- LUFS accuracy ±0.1 LUFS
- BRIR correlation ≥ 0.95
- p99.9 render ≤ 5 ms
- xruns = 0

### Test 3: Parameter Sweep (Zipper Noise Detection)
```cpp
// Sweep single EQ band from −20 to +20 dB over 10 sec
for (int frame = 0; frame < 480000; frame += 2400) { // 50 ms steps
  float gain = -20.0f + (frame / 480000.0f) * 40.0f;
  eqModule.setGain(band, gain);
}

// Analyze output for spectral glitches
// Assert: no 20 kHz spikes (zipper noise indicator)
```

**Acceptance:** No spectral artifacts detected

### Test 4: Clarity Masking Model (Reference Check)
```cpp
// Synthetic masking test: 1 kHz (loud) + 4 kHz (soft)
auto signal = generate1kHz_loudPeak() + generate4kHz_soft();

// Compute masking threshold at 2 kHz
float threshold = clarityModule.maskingThresholdAt(2000.0f);

// Compare to Moore-Glasberg reference (lookup table)
float reference = mooreGlasbergReference(2000.0f);

assert(abs(threshold - reference) < 1.0f); // ±1 dB
```

**Acceptance:** Threshold ≤ ±1 dB of reference

---

## Per-Sprint Final Validation (Manual + Scripted)

### SPRINT 1: Loudness Safety & Transparent Dynamics

#### Automated Tests (from SPRINT-1-LOUDNESS-SAFETY.md)
- [ ] Limiter null-test: bypass = bit-identical
- [ ] True-peak enforcement: output ≤ −1 dBTP
- [ ] GR response: < 2 ms
- [ ] Soak test: 1 hour, zero XRuns
- [ ] Hearing-safety clamp: proportional scaling verified

#### Manual Tests (Scripted)
- [ ] Play 5 reference tracks (vocal, acoustic, electronic, classical, orchestral)
- [ ] Listen for limiter artifacts (pumping, swelling, breathing)
- [ ] Verify no audible artifacts
- [ ] Log observations to `VALIDATION-SPRINT-1.log`

#### Listening Panel
- [ ] Recruit 5–10 audio engineers
- [ ] MUSHRA protocol: original vs. limiter-processed (30 sec clips)
- [ ] Record: "Inaudible" / "Subtle" / "Obvious" ratings + artifact reports
- [ ] Pass: ≥80% rate "Inaudible" or "Subtle"
- [ ] Generate report: `LISTENING-PANEL-SPRINT-1.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ DSP quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Ready to proceed to Sprint 2

---

### SPRINT 2: Minimum-Phase EQ Wiring & Spectral Correction

#### Automated Tests (from SPRINT-2-EQ-FOUNDATION.md)
- [ ] Biquad stability: all random curves stable
- [ ] Null-test: 0 dB = bit-identical
- [ ] Frequency response: ±0.5 dB per band center
- [ ] Gain linearity: ±20 dB range both directions
- [ ] Phase coherence (min-phase): no pre-ringing
- [ ] Parameter ramping: no zipper noise
- [ ] AutoEq profile loading: 5/5 profiles parse, apply

#### Manual Tests (Scripted)
- [ ] Log-sweep test: apply known curve → measure response
- [ ] Before/after spectrum: visual comparison (screenshot evidence)
- [ ] Device profile switching: 3 devices tested
- [ ] Slider responsiveness: latency < 50 ms measured
- [ ] THD+N: ≤ −90 dB across all settings
- [ ] 5-minute soak: zero xruns, stable audio

#### Listening Panel
- [ ] MUSHRA protocol: 5 reference tracks × 3 tests (null, presence peak, bass boost)
- [ ] Blind A/B: original vs. EQ-processed
- [ ] Record: "Identical" / "Prefers B" / "Artifacts" ratings
- [ ] Pass: ≥70% detect intended EQ, ≤20% report artifacts
- [ ] Generate report: `LISTENING-PANEL-SPRINT-2.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ EQ quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Ready to proceed to Sprint 3

---

### SPRINT 3: Adaptive Clarity & Loudness Compensation

#### Automated Tests (from SPRINT-3-ADAPTIVE-CLARITY.md)
- [ ] Masking threshold: ±1 dB vs. reference
- [ ] Clarity gain limits: ≤ +3 dB/band, < +2 dB cumulative
- [ ] Loudness compensation: ±1 dB contour accuracy
- [ ] Arbiter composition: multi-contributor integration
- [ ] Conversational tuning: 90%+ phrase parsing success
- [ ] Content-aware: genre detection + EQ adaptation working
- [ ] 2-hour soak: zero XRuns, no perceptual glitching

#### Manual Tests (Scripted)
- [ ] Clarity perceptual: orchestral passage, can you hear more detail?
- [ ] Loudness compensation A/B: soft level with comp vs. without
- [ ] Conversational tuning: 20 diverse requests, ≥18/20 sound intended
- [ ] Arbiter end-to-end: device + loudness + clarity + content compositing
- [ ] Content-aware transition: 2-song skip (genre change), smooth or jarring?
- [ ] Parameter automation: Reimagine knob sweep, smooth ramping

#### Listening Panel
- [ ] MUSHRA protocol: 5 reference tracks × 5 tests
  - Test 1: Clarity unmask (no clarity vs. clarity)
  - Test 2: Loudness compensation transparency
  - Test 3: Conversational tuning naturalness
  - Test 4: Arbiter composition coherence
  - Test 5: Overall adaptive experience
- [ ] Blind A/B + subjective ratings
- [ ] Pass: ≥75% rate "Highly adaptive" or "Natural"
- [ ] Generate report: `LISTENING-PANEL-SPRINT-3.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ Adaptive DSP quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Phase 1c MVP ready for release

---

## Listening Panel Protocol

### Panel Composition
- **Size:** 5–10 audio professionals (mixing engineers, mastering engineers, audio researchers)
- **Qualification:** ≥3 years professional audio work + familiarity with DAWs/EQ
- **Recruitment:** Contact local studios, universities, audio communities
- **Incentive:** Free copy of final product + acknowledgment in credits

### Test Environment
- **Room:** Quiet (≤ 30 dB ambient)
- **Hardware:** Neumann NDH20 headphones (reference, matched pairs)
- **Calibration:** SPL meter (85 dB @ 1 kHz reference)
- **Session Duration:** ~90 min per panelist
- **Fatigue:** 10-min breaks every 30 min

### MUSHRA Test Format

**Per test:**
1. Listen to reference anchor (original, unprocessed) — 30 sec
2. Listen to hidden candidates (A, B, C, ...) — 30 sec each
3. Rate each candidate on 5-point scale:
   - 5: Excellent (identical to anchor / very natural)
   - 4: Good (minor differences / slightly colored)
   - 3: Fair (noticeable differences / obvious EQ)
   - 2: Poor (significant artifacts / unnatural)
   - 1: Bad (severe artifacts / unusable)
4. Force-choice preference (if candidates differ)
5. Open-ended comments (artifacts, unexpected changes, etc.)

### Data Collection
- Record ratings in spreadsheet (panelist × candidate × test)
- Audio-record or video-record comments (optional)
- Save waveforms + spectrograms of test signals

### Data Analysis
- **Consensus:** ≥80% of panelists rate ≥ 4 (good/excellent)
- **Artifacts:** Count reports of clicking, zipper, pumping, etc. (≤20% max)
- **Preference:** Aggregate force-choice votes (>50% indicates clear preference)
- **Confidence Intervals:** Report 95% CI on mean ratings

### Report Format
```markdown
# Listening Panel Report: Sprint 3

**Date:** 2026-06-XX  
**Panelists:** 8 audio professionals (5 mixing engineers, 2 mastering, 1 researcher)  
**Duration:** 90 min per panelist

## Test 1: Clarity Unmask (Orchestral Passage)

### Results
- Candidate A (no clarity): 3.6 ± 0.9 (avg rating ± SE)
- Candidate B (clarity 50%): 4.3 ± 0.8
- Preference: 75% prefer B

### Comments
- "Violins clearer in B, without sibilance spike"
- "B reveals more bow noise detail"
- "No artifacts detected"

### Consensus
✅ Pass: ≥80% rated B ≥ 4, <10% reported artifacts

...
```

---

## Regression Gates (Post-Release)

**Ongoing:** After Phase 1c MVP ships, run these weekly to catch degradations.

### Weekly Regression Tests
1. Biquad fitting stress (1000 curves) — < 30 sec
2. 20-track corpus end-to-end — < 15 min
3. LUFS measurement accuracy (vs. ffmpeg) — < 5 min
4. True-peak ceiling enforcement — < 5 min

### Monthly Deep Dive
- Full listening panel (subset: 3–5 panelists)
- New music corpus (update test set)
- Real device testing (Bluetooth, new headphones)

---

## Success Metrics (Phase 1c MVP)

| Metric | Target | Status |
|--------|--------|--------|
| Unit test pass rate | 100% | TBD |
| Code coverage (signal path) | ≥80% | TBD |
| Null-test accuracy (THD+N) | ≤ −120 dB | TBD |
| LUFS measurement accuracy | ±0.1 LUFS | TBD |
| True-peak enforcement | ≤ −1 dBTP | TBD |
| EQ frequency response | ±1 dB | TBD |
| Listening panel consensus | ≥80% ≥4 rating | TBD |
| Artifact reports | ≤10% of panelists | TBD |
| Soak test (2 hr) | Zero XRuns | TBD |
| Code quality (ASAN/TSan) | Zero violations | TBD |

---

**Status:** Ready for execution  
**Next:** Execute Sprint 1 validation, generate reports
