# 📋 Code Review Findings: Comprehensive Fixing Plan

> **📦 ARCHIVED — historical session note (2026-06-16).** These code-review fixes shipped in Phase 0/1; retained for provenance, not a current plan.

**Status:** Ready for parallel execution  
**Effort:** 3-5 days (all agents working in parallel)  
**Impact:** Production-quality code before Phase 1 DSP shipping

---

## Organization by Domain & Owner

### **1. Swift/UI Fixes (SwiftUI Pro) — 2-3 days**

#### **1.1 Deprecated API Migrations**

| API | Old | New | Count | Files | Effort |
|-----|-----|-----|-------|-------|--------|
| cornerRadius | `.cornerRadius(6)` | `.clipShape(.rect(cornerRadius: 6))` | 5+ | EQView, EQTabView, NowPlayingTabView | 0.5d |
| Task.detached | `Task.detached { [weak self] in ... await MainActor.run { } }` | `Task { }` (on @MainActor) | 6+ | AudioViewModel | 1d |
| Task.sleep | `Task.sleep(nanoseconds: 100_000_000)` | `Task.sleep(for: .milliseconds(100))` | 1+ | AudioViewModel | 0.25d |
| String.format | `String(format: "%.2f", value)` | `Text(value, format: .number.precision(.fractionLength(2)))` | 3+ | EQView, NowPlayingTabView | 0.5d |
| GeometryReader | Use for just getting size | Use `.onGeometryChange()` instead | 1 | FrequencyResponseCanvas | 0.5d |

**Total Effort:** 2.75 days

#### **1.2 Accessibility Fixes**

| Issue | Location | Fix | Effort |
|-------|----------|-----|--------|
| Icon-only shuffle button | PlaylistView line 317 | Add `.accessibilityLabel("Shuffle")` | 0.25d |
| Icon-only repeat button | PlaylistView line 326 | Add `.accessibilityLabel("Repeat")` | 0.25d |
| Icon-only jump-to-now-playing | PlaylistView line 343 | Add `.accessibilityLabel("Jump to Now Playing")` | 0.25d |
| `.caption2` font too small | EQView axis labels (lines 116–151) | Change to `.caption` minimum | 0.5d |

**Total Effort:** 1.25 days

#### **1.3 File Structure Reorganization**

| File | Types Contained | Split Into | Effort |
|------|-----------------|------------|--------|
| AdaptiveSound.swift | AdaptiveSound, ContentView, TabSelection | 3 files | 0.5d |
| AudioViewModel.swift | AudioViewModel, AudioEngineBridge, AudioDeviceModel, AudioBridgeError | 4 files | 1d |
| EQView.swift | 8 types + functions | 8 files | 1d |
| EQTabView.swift | EQTabView, FrequencyResponseCanvas, EQPreset | 3 files | 0.5d |
| NowPlayingTabView.swift | 8 types | 8 files | 1.5d |
| SpectrumAnalyzer.swift | SpectrumAnalyzer, SpectrumDoubleBuffer | 2 files | 0.5d |

**Total Effort:** 4.5 days

#### **1.4 Data Flow Issues (Already Fixed in Phase 0, but verify)**

- ✅ `@ObservableObject/@Published` → `@Observable` (DONE)
- ✅ EQ dispatch to DSP kernel (DONE)
- ⬜ `Binding(get:set:)` in BandSliderCardView → pass real @Binding (0.5d)

**Total Effort:** 0.5 days

#### **1.5 Animation & Transitions**

| Issue | Location | Fix | Effort |
|-------|----------|-----|--------|
| Bare `.transition()` without animation | EQView line 33 | Add `.animation(value: selectedTab)` | 0.25d |

**Total Effort:** 0.25 days

---

### **2. C++ Code Quality (Modern C++ Expert) — 1.5 days**

#### **2.1 Type Safety: Opaque Pointers**

| File | Line | Issue | Fix | Effort |
|------|------|-------|-----|--------|
| AudioEngine.h | 88-89 | `void*` for AVAudioEngine, AUAudioUnitBus | Use forward-declared opaque handle class | 1d |

**Implementation:**
```cpp
// Before
void* outputUnit_ = nullptr;  // AVAudioEngine*
void* outputBus_ = nullptr;   // AUAudioUnitBus*

// After
class AVAudioEngineImpl;  // Opaque handle
std::unique_ptr<AVAudioEngineImpl> outputUnit_;
```

#### **2.2 Memory Ordering Clarity**

| File | Line | Issue | Fix | Effort |
|------|------|-------|-----|--------|
| DoubleBufferSnapshot.h | 22 | Acquire load is unnecessary (off-RT producer) | Use `relaxed` instead of `acquire` | 0.25d |

**Implementation:**
```cpp
// Before
const uint32_t inactive = 1U - activeIndex_.load(std::memory_order_acquire);

// After
const uint32_t inactive = 1U - activeIndex_.load(std::memory_order_relaxed);
```

#### **2.3 Encapsulation: vDSP Setup Lifecycle**

| File | Line | Issue | Fix | Effort |
|------|------|-------|-----|--------|
| EQModule.h | 57-59 | Three independent atomic slots managing setup | Encapsulate in `SetupLifecycle` helper class | 0.5d |

**Implementation:**
```cpp
class SetupLifecycle {
 public:
  void publishSetup(void* newSetup) noexcept;
  void adoptPendingOnRT() noexcept;
  void cleanupOffRT() noexcept;
  void* load() const noexcept;
 
 private:
  std::atomic<void*> active, pending, toRelease;
};
```

#### **2.4 Error Handling: Silent Failures**

| File | Line | Issue | Fix | Effort |
|------|------|-------|-----|--------|
| EQModule.mm | 81-82 | Silent failure if `vDSP_biquad_CreateSetup` returns nullptr | Log warning or return status | 0.5d |

**Implementation:**
```cpp
// Before
vDSP_biquad_Setup newSetup = vDSP_biquad_CreateSetup(...);
if (newSetup == nullptr) {
  return;  // Silent failure
}

// After
vDSP_biquad_Setup newSetup = vDSP_biquad_CreateSetup(...);
if (newSetup == nullptr) {
  // Log diagnostic + optionally return status
  // so caller knows update failed
}
```

#### **2.5 Code Hygiene: Magic Numbers & Constants**

| File | Issue | Fix | Effort |
|------|-------|-----|--------|
| EQModuleCoefficients.h | Magic `40.0F` without explanation | Add comment referencing RBJ cookbook | 0.25d |
| AudioEngine.mm | Manual ASBD construction | Extract into `makeStreamFormat()` helper | 0.5d |
| Throughout | Scattered numeric casts | Use `gsl::narrow_cast` or helpers | 0.25d |

**Total Effort:** 1.5 days

---

### **3. Architecture: Device & Testability (Refactoring Specialist) — 1-1.5 days**

#### **3.1 Device Enumeration Wiring**

| Issue | Impact | Fix | Effort |
|-------|--------|-----|--------|
| `getOutputDeviceNames()` returns hardcoded fake data | Blocks US-DEVICE-08 | Wire to real `CoreAudioDevice::enumerateOutputDevices()` | 1.5d |
| `AudioDeviceModel` has synthetic IDs, fixed 48 kHz | Device changes not reflected | Return real IDs, sample rates, types from C++ | 1.5d |

**Total Effort:** 1.5 days (already queued for Phase 1, but high impact)

#### **3.2 AudioViewModel Testability**

| Issue | Impact | Fix | Effort |
|-------|--------|-----|--------|
| AudioViewModel untestable (no protocol boundary) | Can't unit test playlist logic | Extract `AudioEngineBridge` behind protocol | 1d |

**Total Effort:** 1d (already queued for Phase 1)

---

### **4. Testing: End-to-End Verification (QA Expert) — 1 day**

#### **4.1 EQ Tests Exercise Real Code**

| Issue | Impact | Fix | Effort |
|-------|--------|-----|--------|
| `EQTests.swift` reimplements biquad, doesn't test actual `EQModule` | Real integration path untested | Wire test to call `EQModule` via bridging header | 0.5d |
| `EQModuleCoefficientsTests.cpp` uses standalone `main()` (invisible to CI) | Can't run in CI | Migrate to XCTest-compatible framework | 0.5d |

**Total Effort:** 1d

---

## Priority & Parallel Execution

### **Critical Path (Do First)**

1. **Type Safety Fixes (C++)** — 0.5d
   - Opaque pointer replacement (prevents future bugs)

2. **Swift Deprecated APIs** — 1.5d
   - `.cornerRadius()`, `Task.detached`, `Task.sleep`
   - Required for iOS 26+ compliance

3. **Accessibility Fixes** — 0.75d
   - Icon labels, font sizes
   - Required for app store compliance

### **Can Run in Parallel**

- File structure reorganization (4.5d) — SwiftUI Pro
- C++ quality (1.5d) — C++ Expert
- Device enumeration (1.5d) — Refactoring Specialist (Phase 1 work)
- Test refactoring (1d) — QA Expert

---

## Timeline for Comprehensive Fix

| Team | Tasks | Effort | Duration | Start | End |
|------|-------|--------|----------|-------|-----|
| **SwiftUI Pro** | Deprecated APIs + A11y + file split | 6.5d | 3-4d (parallel) | Mon | Wed |
| **C++ Expert** | Type safety, memory order, encapsulation | 1.5d | 1.5d | Mon | Tue |
| **Refactoring Specialist** | Device enum, bridge extraction | 1.5d | 1.5d | Mon | Tue |
| **QA Expert** | End-to-end test refactoring | 1d | 1d | Tue | Wed |

**Total Wall Time:** 3-4 days (parallel execution)  
**Total Effort:** 10.5 days (sequential equivalent)

---

## Acceptance Criteria

- ✅ Zero compiler warnings (Swift + C++)
- ✅ All deprecated APIs migrated
- ✅ All accessibility labels added
- ✅ All type safety issues resolved
- ✅ All code compiles with no -Werror violations
- ✅ ASAN/TSan clean (no data races, no leaks)
- ✅ All tests pass (including end-to-end EQ tests)
- ✅ Pre-commit hook passes for all changes
- ✅ Ready for Phase 1 DSP module shipping

---

## Next Steps

1. ✅ Approve this plan
2. ⬜ Kick off 4 agents in parallel (SwiftUI, C++, Refactor, QA)
3. ⬜ Target completion: **Wed 06/25** (3-4 days)
4. ⬜ Then resume Phase 1 DSP (Limiter, Loudness, Clarity, BRIR)

---

**Status:** Ready to execute. All agents briefed on their domains.

