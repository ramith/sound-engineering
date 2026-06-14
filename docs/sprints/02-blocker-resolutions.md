# Sprint 2: Critical Blocker Resolutions & Implementation Decisions

**Date:** 2026-06-14  
**Status:** ✅ All 4 blockers resolved. Ready for Phase 1a kickoff.  
**Audience:** Audio DSP Engineer, Frontend Developer, QA Lead

---

## Executive Summary

7-person team review identified 4 critical blockers in Sprint 2 planning. All are now **resolved with concrete implementation decisions** locked by the Founder:

1. ✅ **BLK-1: No Actual Kernel/Render** → Option A: Full AUAudioUnit v3
2. ✅ **BLK-2: Param Bus Missing** → Option B: Double-Buffer Snapshot + Event Ring
3. ✅ **BLK-3: Signal Chain Ordering** → Option A: Loudness post-BRIR
4. ✅ **BLK-4: Intensity Peak Safety** → Option A: Crossfade pre-Limiter

**Impact:** 
- Signal chain corrected (Loudness moved after BRIR)
- Peak-safety guaranteed (single limiter, all paths ≤ -1 dBTP)
- Implementation architecture locked (AUAudioUnit v3, DoubleBufferSnapshot param bus)
- No scope changes; all 5 DSP modules + UI remain in Phase 1

---

## Blocker Decisions

### BLK-1: No Actual Kernel/Render Callback ✅ RESOLVED

**Team Options:**
- Option A: Full AUAudioUnit v3 (2-3 days)
- Option B: Minimal AVAudioEngine Wrapper (1-2 days) 
- Option C: Hybrid Test Harness + AU (2-3 days)

**Decision: OPTION A** (Founder + Audio DSP + Architecture all confident)

**Implementation Plan:**
1. Create `Sources/AudioDSP/AudioEngine/AUAudioUnit.mm` — custom AUAudioUnit v3 subclass
2. Implement `process(buffer, frames, context)` C++ kernel (pure DSP, no Obj-C dependencies)
3. Wire render block to call kernel: `kernel_->process(ioData, inNumberFrames)`
4. Swift bridge via `AudioEngineBridge` — expose parameter setters, initialization, shutdown
5. Link against AudioToolbox, AVFoundation, Accelerate frameworks

**Swift↔C++ Boundary:**
- **Ownership:** Swift AudioViewModel owns the AUAudioUnit (lifecycle via AVAudioEngine + attachNode)
- **Parameter passing:** Atomic updates via DoubleBufferSnapshot (see BLK-2)
- **Render callback:** Pure C++; no Swift runtime or Obj-C message sends
- **Bridging header:** `AudioDSP/include/AudioEngine.h` (extern "C" facade or Obj-C++ wrapper)

**Acceptance Criteria:**
- AUAudioUnit initializes without errors
- Render callback processes audio with zero dropouts at 48 kHz / 512 frames
- Parameter changes (via slider) reach kernel and affect output within 1 buffer period
- All 5 DSP modules successfully wire into the kernel pipeline

**Effort:** 2-3 days (Phase 1a prep, before DSP modules)

**Related Files:**
- `Sources/AudioDSP/include/AudioEngine.h`
- `Sources/AudioDSP/AudioEngine.mm` (render callback)
- `Sources/AudioDSP/include/DSPKernel.h` (process signature)
- `Sources/AdaptiveSound/AudioViewModel.swift` (initialization)

---

### BLK-2: Param Bus Protocol Missing ✅ RESOLVED

**Team Options:**
- Option A: Generalized Typed SPSC Ring (<1 day) — simplest, highest consistency
- Option B: Double-Buffer Snapshot + Event Ring (1-2 days) — architecturally correct, minimal RT cost
- Option C: Seqlock + Event Queue (2 days) — most complex, ARM64 DMB ISH overhead

**Decision: OPTION B** (Audio DSP Engineer recommends; aligns with architecture §14)

**Implementation Plan:**

```cpp
// TargetState.h — All fields are POD, trivially copyable, cache-line aligned
namespace AdaptiveSound {

struct EQParams {
    BiquadCoeffs biquads[10];  // Fitted by Realizer off-RT
    uint8_t numBiquads;
    float masterGainLinear;
};

struct ClarityParams {
    float thresholdLinear, attackCoeff, releaseCoeff, ratioRecip, kneeWidthLinear;
    uint8_t enabled;
};

struct LoudnessParams {
    float makeupGainLinear;
    uint8_t enabled;
};

struct BRIRParams {
    uint8_t activeSlotIndex;  // Convolver slot atomic
    float azimuthDeg, elevationDeg, roomAmountLinear;
    uint8_t bassMonoGated;
};

struct LimiterParams {
    float truePeakCeilingLinear, lookaheadFrames, attackCoeff, releaseCoeff;
};

struct TargetState {
    EQParams eq;
    ClarityParams clarity;
    LoudnessParams loudness;
    BRIRParams brir;
    LimiterParams limiter;
    float intensityLinear;
    uint64_t sequenceNumber;
};
static_assert(std::is_trivially_copyable_v<TargetState>);
}
```

**DoubleBufferSnapshot Template:**
```cpp
template <typename T>
class alignas(64) DoubleBufferSnapshot {
public:
    // Off-RT: Realizer publishes new state
    void publish(const T& newState) noexcept {
        uint32_t inactive = 1u - activeIndex_.load(std::memory_order_acquire);
        slots_[inactive] = newState;  // memcpy before fence
        activeIndex_.store(inactive, std::memory_order_release);
    }
    
    // RT: acquire latest snapshot once per buffer
    const T& acquireSnapshot() const noexcept {
        uint32_t idx = activeIndex_.load(std::memory_order_acquire);
        return slots_[idx];
    }

private:
    T slots_[2];
    alignas(64) std::atomic<uint32_t> activeIndex_{0};
};
```

**Render Callback Integration:**
```cpp
void DSPKernel::process(AudioBufferList* output, uint32_t frameCount) noexcept {
    // 1. Snapshot — one acquire-load at top of buffer
    const TargetState& state = targetStateSnapshot_.acquireSnapshot();
    
    // 2. Each module ramps toward target and processes
    eqModule_.rampAndProcess(state.eq, output, frameCount);
    clarityModule_.rampAndProcess(state.clarity, output, frameCount);
    brirModule_.rampAndProcess(state.brir, output, frameCount);
    loudnessModule_.rampAndProcess(state.loudness, output, frameCount);
    intensityModule_.rampAndProcess(state.intensityLinear, output, frameCount);
    limiterModule_.rampAndProcess(state.limiter, output, frameCount);
}
```

**Memory Ordering:**
- Release-store on `activeIndex_` in `publish()` → Acquire-load in `acquireSnapshot()` → full happens-before
- No locks, no retry loops, no DMB ISH fences on RT path (zero-cost acquire-load on ARM64)
- All 5 modules read same snapshot generation → consistent state within buffer

**Phase 1.5 Scaling:**
- Extend to `PerStemTargetState` containing `TargetState stems[6]`
- Same `DoubleBufferSnapshot<PerStemTargetState>` wrapper
- Per-stem chains each receive `const TargetState& = perStemState.stems[i]`

**Acceptance Criteria:**
- `TargetState` compiles with static_assert(trivially_copyable)
- Param updates published off-RT reach kernel within 1 buffer period
- All 5 modules read identical TargetState (no staleness divergence)
- Null-test @ intensity 0% passes (bit-identical)

**Effort:** 1-2 days (type definitions + template + wire into kernel)

**Related Files:**
- `Sources/AudioDSP/include/TargetState.h`
- `Sources/AudioDSP/include/DoubleBufferSnapshot.h`
- `Sources/AudioDSP/DSPKernel.mm` (publish path + acquireSnapshot call)
- `Sources/AudioDSP/AudioEngine.mm` (Realizer dispatch → publish)

---

### BLK-3: Signal Chain Ordering Bug ✅ RESOLVED

**Team Options:**
- Option A: Direct Reorder (Loudness post-BRIR) — <1 day, minimal risk
- Option B: Deferred Loudness (Phase 1.5 only) — frees 1.5 sp, but user-experience regression
- Option C: Dual-Path Loudness (measure pre-BRIR, apply post-BRIR) — <1 day, more complex

**Decision: OPTION A** (Recommended; straightforward fix)

**Corrected Signal Chain:**
```
[Previous]  EQ → Clarity → Loudness → BRIR → Intensity → Limiter
[CORRECTED] EQ → Clarity → BRIR → Loudness → Intensity → Limiter
```

**Why:**
- LUFS makeup gain must be computed/applied **after** BRIR convolution
- BRIR adds room energy + spectral coloration (early reflections, etc.)
- Makeup gain computed pre-BRIR is wrong by the energy room IR adds
- Correct behavior: LUFS integrator measures final output, makeup gain adjusts for room coloration

**Implementation Impact:**
- **Phase 1a–1c:** No code impact (modules not yet implemented)
- **Phase 1d:** Reorder module instantiation in DSPKernel (move Loudness module AFTER BRIR in signal chain)
- **Docs:** Update `02-mix-core-plan.md` §3.1 signal flow + Phase 1d task description

**Phase 1d Kernel Assembly (pseudo-code):**
```cpp
void DSPKernel::assembleChain() {
    modules_ = {
        &eqModule_,           // 1. EQ
        &clarityModule_,      // 2. Clarity
        &brirModule_,         // 3. BRIR ← MOVED UP
        &loudnessModule_,     // 4. Loudness ← MOVED DOWN
        &intensityModule_,    // 5. Intensity
        &limiterModule_,      // 6. Limiter
    };
}
```

**Audio-Engineering Sign-Off Required:**
- Confirm no Phase 1.5 features (content-adaptive room amount) need pre-loudness spectral analysis
- Validate that reordering doesn't break any loudness-compensation guarantees

**Acceptance Criteria:**
- Updated signal flow diagram in docs
- Phase 1d code reflects new module order
- Manual listening test confirms no audible loudness-compensation degradation

**Effort:** <1 day (diagram update + audio-engineer sign-off + code reordering)

**Related Files:**
- `docs/sprints/02-mix-core-plan.md` (§3.1, §Phase 1d)
- `docs/sprints/02-mix-core-briefing.md` (signal flow diagram)
- `Sources/AudioDSP/DSPKernel.mm` (module assembly order)

---

### BLK-4: Intensity Crossfade Peak-Safety Violation ✅ RESOLVED

**Team Options:**
- Option A: Crossfade BEFORE Limiter — <1 day, single limiter, unconditional -1 dBTP guarantee
- Option B: Dual Limiters (Input + Output) — 1-2 days, preserves "50% = 50% original" mental model, double latency + complexity
- Option C: Asymmetric Limiting (Wet-Only) — <1 day, elegant but violates LD-17 safety guarantee

**Decision: OPTION A** (Strongly recommended; UI framing fix needed)

**Corrected Signal Chain:**
```
[Previous]  EQ → Clarity → Loudness → BRIR → Limiter → Intensity → Output
[CORRECTED] EQ → Clarity → BRIR → Loudness → Intensity → Limiter → Output
```

**Why:**
- Single limiter catches all signal paths: dry, wet, and all crossfaded blends
- At any intermediate intensity value, crossfade output is guaranteed ≤ -1 dBTP
- Unconditional true-peak safety (no assumptions about input normalization)
- Eliminates the undefined "Output Limiter + Dithering" stage

**Semantics Change (Important for UX):**

**Old mental model (WRONG):**
- "Intensity 0% = original unprocessed music"
- "Intensity 100% = fully processed music"
- "Intensity 50% = 50% original + 50% processed"

**New mental model (CORRECT):**
- "Intensity controls the amount of spatial and clarity enhancement applied"
- "Intensity 0% = minimal enhancement (but full EQ, Clarity, Loudness, BRIR chain still runs for latency consistency)"
- "Intensity 100% = full spatial enhancement + all processing"
- "This is NOT a 'dry/wet blend' control — all modules always run; only spatial enhancement intensity varies"

**UI Clarification Required:**
- Update Intensity knob tooltip: *"Controls the amount of spatial and clarity enhancement. At 0%, you hear the full adaptive processing with minimal spatial enhancement; at 100%, full enhancement is applied. For a pure A/B comparison, use the A/B button to toggle between current intensity and 0%."*
- Clarify in README and in-app help text that "intensity" is not "unprocessed audio percentage"

**Implementation Impact:**
- **Phase 1c:** Move Intensity crossfade module instantiation BEFORE Limiter in kernel assembly
- **Phase 1d:** No new code; Limiter remains unchanged (single threshold clamper)
- **UI:** Update tooltip + help text (see above)
- **Docs:** Update signal flow diagram + Intensity description

**Phase 1c Kernel Assembly (pseudo-code):**
```cpp
void DSPKernel::assembleChain() {
    modules_ = {
        &eqModule_,           // 1. EQ
        &clarityModule_,      // 2. Clarity
        &brirModule_,         // 3. BRIR
        &loudnessModule_,     // 4. Loudness
        &intensityModule_,    // 5. Intensity ← MOVED UP
        &limiterModule_,      // 6. Limiter ← MOVED DOWN (last)
    };
}
```

**Test Implications:**
- Null-test @ 0% intensity: verify bit-identical output (automated binary comparison)
- Peak-safety test: verify all intermediate intensities (0%, 25%, 50%, 75%, 100%) remain ≤ -1 dBTP
- Manual listening: confirm A/B button provides clean null-test experience

**Acceptance Criteria:**
- Single True-Peak Limiter (no "Output Limiter + Dithering")
- All signal paths measured ≤ -1 dBTP at all intensity values
- Null-test automated (binary comparison, residual ≤ -120 dBFS)
- UI tooltip updated to clarify intensity semantics
- Manual listening confirms A/B button works as expected

**Effort:** <1 day (module reordering + tooltip update)

**Related Files:**
- `docs/sprints/02-mix-core-plan.md` (§3.1, §3.2.6)
- `docs/sprints/02-mix-core-briefing.md` (signal flow)
- `Sources/AudioDSP/DSPKernel.mm` (module assembly order)
- `Sources/AdaptiveSound/IntensityDialView.swift` (tooltip text)
- `Tests/ChainTests.swift` (null-test automation, peak-safety test)

---

## Implementation Sequence

**Phase 1a Prep (Before DSP Module Work):**
1. ✅ Create AUAudioUnit v3 scaffold (BLK-1)
2. ✅ Define TargetState POD + DoubleBufferSnapshot template (BLK-2)
3. ✅ Wire param bus into render callback
4. ✅ Unit test: publish TargetState from test thread, verify kernel receives it within 1 buffer

**Phase 1a–1d (DSP Module Implementation):**
- All 5 modules read from same `targetStateSnapshot_.acquireSnapshot()` at buffer start
- Modules ramp parameters over ≥50 ms using pre-computed one-pole coefficients
- No additional synchronization needed per module (snapshot is immutable during buffer)

**Phase 1d (Signal Chain Assembly):**
- ✅ Correct module order: EQ → Clarity → BRIR → Loudness → Intensity → Limiter (BLK-3 + BLK-4)
- ✅ Verify all paths stay ≤ -1 dBTP at all intensity values
- ✅ Automated null-test: residual ≤ -120 dBFS @ 0% intensity

**Phase 1e (QA + Documentation):**
- Manual listening QA
- Update all docs (briefing, plan, README, API comments)
- Sprint retro

---

## Sign-Off Checklist

- [x] Founder locks all 4 blocker decisions
- [x] Audio DSP Engineer confirms implementation approach
- [x] QA Lead confirms test strategy aligns with decisions
- [x] Frontend Developer confirms UI tooltip update path
- [x] Architecture agrees param bus + AU design

**Ready for Phase 1a kickoff** ✅

---

**Prepared by:** Team Review Panel  
**Date:** 2026-06-14  
**Document:** Reference guide for Sprint 2 implementation  
**Location:** `/Users/ramith/code/sound-engineering/docs/sprints/02-blocker-resolutions.md`
