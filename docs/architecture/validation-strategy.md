# Audio Quality Validation Strategy

**Purpose:** Define comprehensive validation gates for Sprints 4–6 (Phase 1c MVP — the loudness/EQ/clarity DSP core)  
**Scope:** Unit tests, integration tests, listening panels, regression gates, soak tests  
**Approval:** QA Expert + Audio DSP + Project Lead  
**Maintenance:** Update per sprint

> **Sprint numbering:** canonical sprints are **4 = loudness, 5 / 5b = EQ + multichannel, 6 = adaptive clarity** (see [../sprints/00-sprint-model.md](../sprints/00-sprint-model.md)). Older drafts of this doc used 1/2/3; those map to 4/5/6 respectively.
>
> **Test-harness reality (read first):** the DSP gate is the **C++ null-test harness** (`bash scripts/build-null-test.sh`), **not** `swift test` — which is **broken** on this toolchain (macro skew). The Swift mock/view-model tests build and run under **Xcode** only. The fictional `./AdaptiveSound --input … --intensity N` CLI does **not** exist; bit-exact and frequency-response checks are C++ harness tests. Sections below have been corrected to match.

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

### Gate 1: DSP Test Harness (C++ null-test) — the primary gate

```bash
bash scripts/build-null-test.sh
```

This builds and runs the standalone C++ harness (`Tests/DSPKernelNullTest.cpp` + the `*.inc` area files). It is the **canonical DSP gate**.

**Requirements:**
- All harness tests pass (~83 tests, 0 failures) — bypass/identity, EQ, limiter, loudness/BS.1770, multichannel, spatial passthrough, Pure-Mode policy/format/decode/round-trip, gapless seams.
- Stereo **golden master** signature `0xE7267654BA01D315` (FNV-1a over the processed L+R of a deterministic chirp through +6 dB @ 1 kHz EQ + active limiter) must match. Any one-ULP change to stereo output flips it; re-baseline only on a founder-approved DSP change.
- Fixtures are written + read in `<repo>/test-data/` (never `/tmp`); generated WAV/bin are git-ignored.

**`swift test` is BROKEN** (toolchain macro skew) and is **not** a merge gate. The Swift test targets (`AudioViewModelTests`, `AudioDSPTests`) use the Swift Testing framework and run under **Xcode** only, not headless `swift test`.

**Companion offline checks (`swift run`, headless):**
- `swift run VerifyAUGraph` — proves the custom v3 AU registers, instantiates, sits in the AVAudioEngine graph, and renders.
- `swift run SRCQualityMeasure` — characterises the production `AVAudioConverter(.max)` SRC (imaging/aliasing on pure tones).

### Gate 2: Bit-Exact Bypass (intensity-0 null test)

**Purpose:** Verify that intensity 0% produces bit-identical output.

This is **not** a CLI invocation — it is the harness test `IntensityZero_BitExactPassthrough` (+ `IntensityZero_MultiChunkBitExact`) in `DspBypassTests.inc`: the kernel early-returns at `intensityLinear == 0`, and the output is compared byte-for-byte (`memcmp`) against the input. The Pure-Mode software-chain bit-exactness is covered by `RoundTripTests.inc` (decode → `convertFloatToNative`, zero tolerance, 16/24-bit).

**Acceptance:** byte-identical (zero tolerance) for both the kernel bypass and the Pure software-chain round-trip. (Run via Gate 1.)

### Gate 3: EQ Frequency Response (baseline regression)

**Purpose:** Confirm a band boost changes the signal by the right amount, with no boundary click.

Harness tests `EQ_FrequencyResponseAccuracy` and `EQ_CoefficientSwapNoClick` (`EqTests.inc`, plus the N-channel variants in `MultichannelTests.inc`): apply a known band boost, measure the settled-RMS delta vs. flat, assert within tolerance; and verify a large coefficient swap produces no audible boundary discontinuity (zipper).

**Acceptance:** measured band gain within the harness tolerance; no zipper artifact. (Run via Gate 1.)

### Gate 4: Sanitizers + clang-tidy (C++23)

The C++ modules build under **`gnu++2b` / C++23** (see `Package.swift` `cxxLanguageStandard: .gnucxx2b` and `scripts/build-null-test.sh` `-std=gnu++2b`) — **not** C++17. Run the harness translation unit under ASan/UBSan, and clang-tidy with the C++23 standard:

```bash
# ASan/UBSan: add the sanitizer flags to the build-null-test.sh clang++ invocation
#   (-fsanitize=address,undefined) and run ./Tests/DSPKernelNullTest.
# clang-tidy on the C++ modules (std must be gnu++2b / c++2b, matching production):
clang-tidy --checks=readability-*,cppcoreguidelines-* \
  Sources/AudioDSP/*.mm Sources/AudioDSP/**/*.cpp -- -std=gnu++2b -I Sources/AudioDSP/include
```

**Acceptance:** zero sanitizer errors, zero clang-tidy violations.

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

> **Aspirational — no batch CLI exists.** There is no `./AdaptiveSound --input … --intensity N` command; the app is GUI-only. This corpus pass would need a small offline driver (e.g. extend `VerifyAUGraph` / a dedicated harness) that decodes each track, runs the kernel/graph offline, and measures the metrics below against `ffmpeg ebur128`. Until that driver exists, corpus-level LUFS/BRIR/RT metrics are measured ad hoc or via the C++ harness's synthetic signals.

Planned measurements over a 20-track corpus (varied genres, dynamic range):
- LUFS accuracy (vs. `ffmpeg ebur128`)
- BRIR convolution correctness (correlation to reference) — *pending the BRIR module (Sprint 6+; currently a stub)*
- RT-safety metrics (no xruns, p99.9 render ≤ 5 ms)

**Acceptance (when the driver exists):**
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

> **Listening-panel status: NOT YET EXECUTED.** The MUSHRA listening-panel rounds below are the planned acceptance protocol; no panel has been run and no `LISTENING-PANEL-*.md` reports exist yet. Automated harness tests (Gate 1–4) are the gate that has actually run. Sprint headings use the canonical 4/5/6 numbering (Sprint 4 + 5/5b DONE; Sprint 6 not yet shipped).

### SPRINT 4: Loudness Safety & Transparent Dynamics

#### Automated Tests (see [../sprints/04-sprint-4-loudness-safety.md](../sprints/04-sprint-4-loudness-safety.md))
- [ ] Limiter null-test: bypass = bit-identical
- [ ] True-peak enforcement: output ≤ −1 dBTP
- [ ] GR response: < 2 ms
- [ ] Soak test: 1 hour, zero XRuns
- [ ] Hearing-safety clamp: proportional scaling verified

#### Manual Tests (Scripted)
- [ ] Play 5 reference tracks (vocal, acoustic, electronic, classical, orchestral)
- [ ] Listen for limiter artifacts (pumping, swelling, breathing)
- [ ] Verify no audible artifacts
- [ ] Log observations to `VALIDATION-SPRINT-4.log`

#### Listening Panel
- [ ] Recruit 5–10 audio engineers
- [ ] MUSHRA protocol: original vs. limiter-processed (30 sec clips)
- [ ] Record: "Inaudible" / "Subtle" / "Obvious" ratings + artifact reports
- [ ] Pass: ≥80% rate "Inaudible" or "Subtle"
- [ ] Generate report: `LISTENING-PANEL-SPRINT-4.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ DSP quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Ready to proceed to Sprint 5

---

### SPRINT 5 / 5b: Minimum-Phase EQ Wiring & Spectral Correction

#### Automated Tests (see [../sprints/05-sprint-5-eq-foundation.md](../sprints/05-sprint-5-eq-foundation.md))
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
- [ ] Generate report: `LISTENING-PANEL-SPRINT-5.md`

#### Sign-Off
- [ ] Audio DSP lead: ✅ EQ quality approved
- [ ] QA lead: ✅ All acceptance criteria met
- [ ] Project lead: ✅ Ready to proceed to Sprint 6

---

### SPRINT 6: Adaptive Clarity & Loudness Compensation

#### Automated Tests (see [../sprints/06-sprint-6-adaptive-clarity.md](../sprints/06-sprint-6-adaptive-clarity.md))
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
- [ ] Generate report: `LISTENING-PANEL-SPRINT-6.md`

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
# Listening Panel Report: Sprint 6

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
| C++ harness pass rate (~83 tests) | 100% (0 failures) | DONE — passing |
| Stereo golden master | `0xE7267654BA01D315` match | DONE — matching |
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

**Status:** Sprint 4 + 5/5b automated gates DONE (C++ harness passing, golden master matching); listening panels NOT YET EXECUTED.  
**Next:** Run the Sprint 4/5 listening panels; build out Sprint 6 (clarity/loudness-comp) tests as that DSP lands.
