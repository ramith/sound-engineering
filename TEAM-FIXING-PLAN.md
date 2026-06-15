# 🎯 Adaptive Sound: Comprehensive Team Fixing Plan
**Status:** In synthesis (5 domain experts coordinating)  
**Generated:** 2026-06-16  
**Target Release:** Phase 1b Part B (2026-06-21)

---

## Executive Summary

Based on the comprehensive code review, the team has identified **3 critical blockers** (Phase 0), **11 high-priority fixes** (Phase 1), and **medium-term improvements** (Phase 2). The plan is organized by:

- **Phase 0 (Critical, 2–3 days):** Must fix before shipping Phase 1b
- **Phase 1 (High, 5–8 days):** Before Phase 1c DSP features ship
- **Phase 2 (Medium, 1–2 weeks):** Refactoring & technical debt

---

## Phase 0: Critical Blockers (Ship-Blocking)

### 🔴 **1. Two Incompatible EQ Implementations**
**Owner:** SwiftUI Pro + Refactoring Specialist  
**Effort:** 2 days  
**Blocks:** Phase 1.5 (ML presets, auto-EQ, device correction)  

**Problem:**
- `EQView.swift` + `EQViewModel` (31-band sliders, preset data in `EQPresetDefinition`)
- `EQTabView.swift` + `FrequencyResponseCanvas` (drag canvas, preset formulas in trigonometric functions)
- No single source of truth → preset values disagree (Presence: 4 dB vs. 7 dB)
- No end-to-end dispatch from UI to DSP kernel

**Solution:**
1. Keep `FrequencyResponseCanvas` (richer interactive UI)
2. Wire it to `EQViewModel` as the dispatch layer
3. Move canonical preset data to `EQPreset` enum as computed property
4. Delete `EQView.swift` (or reduce to stub)
5. Delete `EQPresetDefinition` struct
6. Add computed `gains: [Float]` property derived from trigonometric formulas

**Files to Touch:**
- Delete: `Sources/AdaptiveSound/EQView.swift`, `Sources/AdaptiveSound/UI/Tabs/EQTabView.swift` (keep canvas logic)
- Modify: `Sources/AdaptiveSound/EQViewModel.swift` (centralize presets), `Sources/AdaptiveSound/EQTabView.swift` (wire to ViewModel)

**Testing:** End-to-end: drag slider → ViewModel receives gain → DSP kernel applies EQ → audio changes

---

### 🔴 **2. Parameter Ramping Missing (Zipper Noise)**
**Owner:** Audio DSP Engineer  
**Effort:** 1.5 days  
**Blocks:** Phase 1b playback (EQ dragging sounds like clicks/pops)  

**Problem:**
- `EQModule.process()` applies gain changes immediately without smoothing
- `masterGainLinear` jumps between buffers → audible zipper-noise clicks
- vDSP_biquadm has ramping support but not used

**Solution:**
```cpp
// In EQModule.h: add per-parameter ramping state
struct RampingState {
  float target, current;
  float coefficient;  // α for one-pole smoother
};

// In EQModule.process():
// Linear or one-pole ramp over 32 ms window
// new_gain = α * current + (1 - α) * target
// Apply to vDSP_vsmul before output
```

**Files to Touch:**
- `Sources/AudioDSP/EQ/EQModule.h` (add ramping fields)
- `Sources/AudioDSP/EQ/EQModule.mm` (implement ramping in process loop)
- `Sources/AudioDSP/DSPKernel.mm` (verify no sudden parameter jumps)

**Testing:** Spectrogram of EQ drag shows smooth transition, no frequency spikes

---

### 🔴 **3. No `intensityLinear == 0` Bypass (Violates MD5-Bit-Exact Guarantee)**
**Owner:** Audio DSP Engineer  
**Effort:** 0.5 days  
**Blocks:** Phase 1b verification (null test cannot pass)  

**Problem:**
- `TargetState::intensityLinear` is defined but never read in `DSPKernel::process()`
- At intensity 0, output must be bit-identical to input (fidelity guarantee)
- Currently processes through stubs even when intensity = 0

**Solution:**
```cpp
// In DSPKernel::process(), line ~50:
if (state.intensityLinear == 0.0F) {
  // Copy input to output directly (bypass)
  memcpy(ioData, input, inNumberFrames * sizeof(float));
  return;
}
// Otherwise, process through chain and apply intensity scaling at end
```

**Files to Touch:**
- `Sources/AudioDSP/DSPKernel.mm` (add bypass check, dry/wet crossfade at end)

**Testing:** Null test: feed audio at intensity=0, verify MD5 matches input byte-for-byte

---

### 🟡 **4. Silent Correctness Bug: `playTrack(at:)` Ignores Parameter**
**Owner:** Refactoring Specialist + SwiftUI Pro  
**Effort:** 0.25 days  
**Blocks:** Phase 1.5 shuffle/auto-advance (would play wrong track)  

**Problem:**
```swift
func playTrack(at index: Int) {
  guard index < playlist.count else { return }
  startPlayback()  // plays whatever selectedTrackIndex already is, not the passed index!
}
```

**Solution:**
```swift
func playTrack(at index: Int) {
  guard index < playlist.count else { return }
  selectedTrackIndex = index  // ← ADD THIS
  startPlayback()
}
```

**Files to Touch:**
- `Sources/AdaptiveSound/AudioViewModel.swift` (line ~200)

---

## Phase 1: High-Priority Fixes (Before Phase 1c DSP)

### **5. FTZ/DAZ Denormal Handling**
**Owner:** Audio DSP Engineer  
**Effort:** 0.5 days  
**Blocks:** Phase 1b battery/thermal (quiet signals cause CPU spike)  

Set ARM64 floating-point flags at render callback entry:
```cpp
// DSPKernel::initialize() or AU render block
// Enable flush-to-zero (FTZ) and denormalize-as-zero (DAZ)
#ifdef __ARM_ARCH_ISA_A64
  uint64_t fpcr;
  asm volatile("mrs %0, fpcr" : "=r"(fpcr));
  fpcr |= (1UL << 24) | (1UL << 19);  // FTZ | DAZ
  asm volatile("msr fpcr, %0" : : "r"(fpcr));
#endif
```

**Files:** `Sources/AudioDSP/DSPKernel.mm`, `Sources/AudioDSP/AudioEngine/AUAudioUnit.mm`

---

### **6. Limiter Module Implementation (TRUE-PEAK SAFETY)**
**Owner:** Audio DSP Engineer  
**Effort:** 2 days  
**Blocks:** Phase 1b (loudness safety is non-negotiable)  

**Spec:** True-peak limiter with ≥4× oversampling, −1 dBTP ceiling, ~1 ms lookahead

**Implementation:**
- Ring-buffer lookahead (1 ms = 48 frames @ 48 kHz)
- Peak detection with oversampling (catch intersample peaks)
- Gain reduction sidechain (attack/release smoothing)
- Parameter ramping on threshold/lookahead

**Testing:** Null test (ceiling=1.0), sweep (−3 dBTP input → ≤ −1 dBTP output)

---

### **7. Loudness Module (LUFS Normalization)**
**Owner:** Audio DSP Engineer  
**Effort:** 2.5 days  
**Blocks:** Phase 1c (loudness feature)  

**Spec:** ITU-R BS.1770-5 LUFS metering + transparent makeup gain

---

### **8. Clarity Module (Dynamic EQ)**
**Owner:** Audio DSP Engineer  
**Effort:** 2 days  
**Blocks:** Phase 1c (clarity/unmasking feature)  

---

### **9. BRIR Module (Spatial Audio)**
**Owner:** Audio DSP Engineer  
**Effort:** 3 days  
**Blocks:** Phase 1c (spatial immersion)  

---

### **10. Extract `AudioEngineBridge` to Separate File Behind Protocol**
**Owner:** Refactoring Specialist  
**Effort:** 1 day  
**Blocks:** Phase 1.5 testing (AudioViewModel untestable today)  

**Solution:**
```swift
protocol AudioPlaybackEngine {
  func initialize() async throws
  func startPlayback() async throws
  func stopPlayback() async
  func setParameter(_ id: UInt32, value: Float) async throws
  // ...
}

// AudioViewModel receives `any AudioPlaybackEngine` via dependency injection
// Tests can inject a mock without touching AVAudioEngine
```

**Benefit:** Unit tests can now test playlist/playback logic without live audio

---

### **11. Wire Device Enumeration to Real CoreAudio Data**
**Owner:** SwiftUI Pro + Refactoring Specialist  
**Effort:** 1.5 days  
**Blocks:** US-DEVICE-08 (Bluetooth sample-rate negotiation)  

**Problem:**
- `getOutputDeviceNames()` returns hardcoded `["Built-in Speaker", "AirPods Pro", ...]`
- Real device data exists in C++ (`CoreAudioDevice`) but is never surfaced
- Device ID, sample rate, type are permanently stale

**Solution:**
- Wire `CoreAudioDevice::enumerateOutputDevices()` through bridge
- `AudioViewModel` populates real `AudioDeviceModel` with real IDs, sample rates, types
- Settings panel can now react to actual device changes

---

### **12. Null Test Framework**
**Owner:** QA Expert + Audio DSP Engineer  
**Effort:** 1 day  
**Blocks:** Phase 1b verification (all tests depend on this)  

**Create:** `Tests/DSPKernelNullTest.cpp`
- Feed white noise / music at intensity=0
- Verify output is bit-identical to input (MD5 checksum or byte-compare)
- Repeat for each module individually

**Gate:** Pre-commit hook runs this test before any DSP change

---

### **13. Frequency Sweep & Impulse Response Tests**
**Owner:** QA Expert  
**Effort:** 1.5 days  
**Blocks:** Phase 1c module acceptance  

---

## Phase 2: Medium-Priority Refactoring (1–2 weeks)

### **Deprecated API Migrations**
- `.cornerRadius()` → `.clipShape(.rect(cornerRadius:))` (5+ sites)
- `@ObservableObject/@Published` → `@Observable` (1 class, 6 usages)
- `String(format:)` → `FormatStyle` (3+ sites)
- `Task.detached` + `await MainActor.run` → plain `Task { }` (6+ methods)
- `Task.sleep(nanoseconds:)` → `Task.sleep(for:)` (1+ site)

### **Accessibility Fixes**
- Icon-only buttons (shuffle, repeat, jump) need `.accessibilityLabel`
- `.caption2` font → `.caption` for readability

### **File Structure Cleanup**
Break multi-type files into single-type files:
- `AdaptiveSound.swift` (3 types) → 3 files
- `AudioViewModel.swift` (5 types) → 5 files
- `EQView.swift` (8 types) → 8 files
- `EQTabView.swift` (3 types) → 3 files
- `NowPlayingTabView.swift` (8 types) → 8 files
- `SpectrumAnalyzer.swift` (2 types) → 2 files

### **C++ Code Quality**
- Replace `void*` opaque pointers with forward-declared handle classes
- Fix memory ordering in `DoubleBufferSnapshot::publish()` (use `relaxed` load)
- Encapsulate vDSP setup lifecycle in `EQModule`
- Log vDSP setup creation failures (don't silently swallow)
- Extract ASBD construction into helper function

---

## Timeline & Team Assignments

### **Phase 0 (2–3 days) — Critical Path**

| Task | Owner | Effort | Start | Finish |
|------|-------|--------|-------|--------|
| Consolidate EQ implementations | SwiftUI Pro | 2d | Wed (06/17) | Thu (06/18) |
| Parameter ramping | DSP Engineer | 1.5d | Wed (06/17) | Thu (06/18) |
| Add intensityLinear bypass + null test | DSP Engineer | 1d | Fri (06/19) | Fri (06/19) |
| Fix playTrack(at:) bug | Refactoring Specialist | 0.25d | Fri (06/19) | Fri (06/19) |

**Dependency:** Ramping & bypass must complete before any other DSP work.

### **Phase 1 (5–8 days) — High-Priority**

| Task | Owner | Effort | Start | Finish |
|------|-------|--------|-------|--------|
| FTZ/DAZ setup | DSP Engineer | 0.5d | Mon (06/23) | Mon (06/23) |
| Limiter module | DSP Engineer | 2d | Mon (06/23) | Tue (06/24) |
| Loudness module | DSP Engineer | 2.5d | Wed (06/25) | Thu (06/26) |
| Clarity module | DSP Engineer | 2d | Fri (06/27) | Mon (06/30) |
| BRIR module | DSP Engineer | 3d | Mon (06/30) | Wed (07/02) |
| Extract AudioEngineBridge | Refactoring Specialist | 1d | Mon (06/23) | Mon (06/23) |
| Wire device enumeration | SwiftUI Pro | 1.5d | Tue (06/24) | Tue (06/24) |
| Frequency sweep tests | QA Expert | 1.5d | Wed (06/25) | Thu (06/26) |

---

## Risk Assessment

| Issue | Risk | Mitigation |
|-------|------|-----------|
| EQ consolidation changes UI/dispatch | Medium | End-to-end test on familiar music; A/B against old implementation |
| Parameter ramping introduces latency | Low | Ramping window is 32 ms (imperceptible); test with fast EQ drags |
| Limiter peaking algorithm | Medium | Unit tests with synthetic peaks; libebur128 oracle for true-peak |
| Module stubs → full implementations | High | Incremental by module; null test gates each; soak test (1 hour playback) |
| Device enumeration refactor | Medium | Test with real devices (AirPods, USB); fallback to hardcoded if real enum fails |

---

## Success Criteria

### **Phase 0 (By 2026-06-21)**
- ✅ EQ consolidation complete (single source of truth)
- ✅ Parameter ramping implemented (no zipper noise on EQ drag)
- ✅ Intensitylinear bypass working (null test passes)
- ✅ playTrack(at:) bug fixed

### **Phase 1 (By 2026-07-07)**
- ✅ All 4 module stubs implemented + tested
- ✅ Null test gates all commits (pre-commit hook)
- ✅ Frequency sweep test validates filter response
- ✅ AudioEngineBridge extracted (ViewModel testable)
- ✅ Device enumeration wired to real CoreAudio data

### **Phase 2 (By 2026-07-14)**
- ✅ All deprecated APIs migrated
- ✅ All accessibility labels added
- ✅ File structure split into single-type files
- ✅ C++ code quality improved (no void* pointers, proper error handling)

---

## Integration with Existing Docs

- **Architecture rationale:** See [docs/architecture/architecture.md](docs/architecture/architecture.md) §9–14
- **Sprint execution:** See [docs/sprints/07-phase-1b-part-b-kickoff.md](docs/sprints/07-phase-1b-part-b-kickoff.md)
- **Validation strategy:** See [docs/architecture/validation-strategy.md](docs/architecture/validation-strategy.md)
- **Product roadmap:** See [docs/product/roadmap.md](docs/product/roadmap.md)

---

## Next Steps

1. **Today:** Review this plan with team; confirm ownership assignments
2. **Tomorrow (Wed 06/17):** Begin Phase 0 work in parallel (EQ consolidation + ramping)
3. **Friday (06/19):** Verify null test passes; Phase 0 complete
4. **Mon 06/23:** Start Phase 1 module implementations (Limiter first for 1b safety)

---

**Last Updated:** 2026-06-16 (team review in progress)  
**Compiled By:** Audio DSP Agent, Modern C++ Expert, SwiftUI Pro, Refactoring Specialist, QA Expert

