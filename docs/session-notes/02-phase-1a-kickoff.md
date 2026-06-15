# Sprint 2 Phase 1a: AUAudioUnit + Param Bus Infrastructure

**🚀 KICKOFF: 2026-06-14**  
**Duration:** 2.5 days (~1 week)  
**Goal:** Build the foundational audio engine infrastructure so DSP modules can plug in cleanly.

---

## Mission

Build a working **AUAudioUnit v3 render pipeline** with a **lock-free parameter bus** so that Phase 1a–1d can focus purely on DSP module implementation without worrying about host integration or RT-safety plumbing.

**Deliverables by end of Phase 1a:**
- ✅ Custom AUAudioUnit v3 with working render callback
- ✅ TargetState POD + DoubleBufferSnapshot param bus
- ✅ C++ DSP kernel scaffold (`process(buffer, frames)`)
- ✅ Unit test: param publish/consume cycle verified
- ✅ Audio plays through AVAudioEngine + AU at 48 kHz with zero dropouts

---

## Scope

### IN Phase 1a
1. **AUAudioUnit v3 Scaffold** (BLK-1 Resolution)
   - `Sources/AudioDSP/AudioEngine/AUAudioUnit.mm` — custom AU v3 subclass
   - Property definitions (gain, bypass, etc. — minimal; real DSP params come in Phase 1b+)
   - Render block wired to C++ kernel
   - Link AudioToolbox, AVFoundation, Accelerate

2. **DoubleBufferSnapshot Param Bus** (BLK-2 Resolution)
   - `Sources/AudioDSP/include/TargetState.h` — POD struct with all 5 module params
   - `Sources/AudioDSP/include/DoubleBufferSnapshot.h` — template wrapper
   - Integration into DSPKernel.mm (one acquire-load per buffer)
   - Unit test: publish TargetState from test thread, verify kernel receives it ≤1 buffer

3. **DSP Kernel Scaffold**
   - `Sources/AudioDSP/include/DSPKernel.h` — `void process(buffer, frames)` signature
   - Module instantiation placeholders (EQ, Clarity, Loudness, BRIR, Limiter stubs)
   - Pass-through mode (input → output, no processing yet)

4. **Swift Bridge**
   - `Sources/AdaptiveSound/AudioViewModel.swift` — initialization, parameter setters
   - `Sources/AdaptiveSound/AudioEngineBridge.swift` — AU ↔ Swift binding
   - Minimal UI: playback button, volume slider (for testing AU integration)

5. **Tests**
   - Unit test: param bus publish/consume (mock kernel)
   - Integration test: AU renders silence/reference signal without dropouts (48 kHz / 512 frames)

### OUT of Phase 1a (deferred to Phase 1b+)
- EQ, Clarity, Loudness, BRIR, Limiter DSP implementations
- Full parameter UI (presets, frequency graphs, etc.)
- Manual listening QA (covered in Phase 1e)

---

## Detailed Tasks

### Task 1: AUAudioUnit v3 Scaffold (1 day)

**Objective:** Create a minimal AU v3 that can be loaded by AVAudioEngine and has a working render callback.

**Steps:**
1. Create `Sources/AudioDSP/AudioEngine/AUAudioUnit.mm` (Obj-C++ file)
   - Subclass `AUAudioUnit`
   - Define minimal AU parameters (e.g., "Master Gain", "Bypass" — just for testing)
   - Implement `allocateRenderResources()` to initialize DSPKernel
   - Implement `deallocateRenderResources()` to cleanup
   - Wire render block: `_block = [](AudioUnitRenderActionFlags *flags, ...) { kernel_->process(...); }`

2. Create bridging header `Sources/AudioDSP/include/AudioUnitBridge.h` (extern "C" or Obj-C++ interface)
   - Expose AU creation function to Swift: `AudioUnit* createAdaptiveAudioUnit(AVAudioEngine*)`
   - Expose parameter setter: `void setAUParameter(AudioUnit*, paramID, value)`

3. Update `Package.swift`
   - Link `-framework AudioToolbox` (AUAudioUnit framework)
   - Ensure `.mm` files compile with C++17 and Obj-C++ support

4. Wire into `Sources/AdaptiveSound/AudioViewModel.swift`
   - In `initializeEngine()`, create the AU and attach to AVAudioEngine
   - Test: audio engine starts, no errors

**Acceptance Criteria:**
- AU loads without crashing
- Render callback is called at buffer rate (no exceptions logged)
- AVAudioEngine.startAndReturnError() succeeds
- No Xcode warnings or build errors

**Reference:** AudioUnitSDK example projects (Apple's `HelloInterApp`)

---

### Task 2: TargetState + DoubleBufferSnapshot (1 day)

**Objective:** Define the POD parameter struct and lock-free snapshot transport.

**Steps:**
1. Create `Sources/AudioDSP/include/TargetState.h`
   - Define `struct TargetState` with all 5 module parameter fields:
     - `EQParams eq` (biquad array, num, gain)
     - `ClarityParams clarity` (threshold, attack, release, ratio, knee, enabled)
     - `LoudnessParams loudness` (makeup gain, enabled)
     - `BRIRParams brir` (slot index, azimuth, elevation, room amount, bass mono flag)
     - `LimiterParams limiter` (ceiling, lookahead, attack, release)
     - `float intensityLinear` (0–1)
     - `uint64_t sequenceNumber` (for diagnostics)
   - Add `static_assert(std::is_trivially_copyable_v<TargetState>)`
   - Ensure cache-line alignment (POD fields, no heap pointers)

2. Create `Sources/AudioDSP/include/DoubleBufferSnapshot.h`
   - Template `DoubleBufferSnapshot<T>` with:
     - `void publish(const T&)` — off-RT writer (atomically swap active slot)
     - `const T& acquireSnapshot()` — RT reader (one acquire-load)
     - Internal: two `T slots_[2]`, `std::atomic<uint32_t> activeIndex_`
   - Memory ordering: release-store on write, acquire-load on read

3. Integrate into `Sources/AudioDSP/include/AudioEngine.h`
   - Add member: `DoubleBufferSnapshot<TargetState> targetStateSnapshot_`
   - Add method: `void publishTargetState(const TargetState&)` (for Realizer to call)

4. Integrate into `Sources/AudioDSP/DSPKernel.mm`
   - In `process()` at buffer start:
     ```cpp
     const TargetState& state = targetStateSnapshot_.acquireSnapshot();
     // Hold this reference for the entire buffer
     // Placeholder module calls: (will be filled in Phase 1b+)
     // eqModule_.rampAndProcess(state.eq, buffer, frameCount);
     ```

5. Write unit test `Tests/ParamBusTests.swift`
   - Mock kernel that records the TargetState it receives
   - Test thread publishes known TargetState with distinctive values
   - Verify kernel receives same values within 1 buffer period

**Acceptance Criteria:**
- `static_assert(trivially_copyable)` passes
- Unit test: publish/consume cycle succeeds
- No memory leaks (Instruments / ASAN validation)
- Zero compiler warnings

---

### Task 3: DSP Kernel Scaffold (0.5 day)

**Objective:** Create the process() signature and module instantiation placeholders.

**Steps:**
1. Create `Sources/AudioDSP/include/DSPKernel.h`
   - Define `class DSPKernel`
   - Method: `void process(AudioBufferList* ioData, UInt32 inNumberFrames)`
   - Members: pointers/references to 5 module stubs (EQ, Clarity, Loudness, BRIR, Limiter)
   - Member: `DoubleBufferSnapshot<TargetState> targetStateSnapshot_`

2. Create `Sources/AudioDSP/DSPKernel.mm`
   - Implement `process()`:
     ```cpp
     void DSPKernel::process(AudioBufferList* ioData, UInt32 frameCount) {
         const TargetState& state = targetStateSnapshot_.acquireSnapshot();
         // Placeholder: for now, just pass audio through unchanged
         // In Phase 1a-1d, each module will plug in here:
         // eqModule_->process(...);
         // clarityModule_->process(...);
         // ... etc
     }
     ```
   - Initialize module placeholders (stubs)
   - Test: process() is callable, produces output buffers

3. Module stubs (minimal for Phase 1a)
   - Create empty `Sources/AudioDSP/EQ/EQModule.{h,mm}` (no processing yet)
   - Create empty `Sources/AudioDSP/Clarity/ClarityModule.{h,mm}`
   - Create empty `Sources/AudioDSP/Loudness/LoudnessModule.{h,mm}`
   - Create empty `Sources/AudioDSP/Spatial/BRIRModule.{h,mm}`
   - Create empty `Sources/AudioDSP/Limiting/LimiterModule.{h,mm}`
   - Each has a `void process(const *Params&, buffer, frames)` method (no-op for now)

**Acceptance Criteria:**
- `process()` callable without crashes
- Pass-through mode produces silence or input signal unchanged
- No dropouts at 48 kHz / 512 frames

---

### Task 4: Swift Audio Bridge (1 day)

**Objective:** Connect SwiftUI to the AU so the app can initialize and play audio.

**Steps:**
1. Update `Sources/AdaptiveSound/AudioViewModel.swift`
   - In `initializeEngine()`:
     ```swift
     let engine = AVAudioEngine()
     let auUnit = createAdaptiveAudioUnit(engine)
     engine.attach(auUnit)
     // Connect AU to engine's output
     try engine.start()
     self.isEngineReady = true
     ```
   - Add parameter setter: `func setParameter(_ id: UInt32, value: Float)`

2. Create minimal UI for testing
   - Add a "Play" button that starts playback (via AVAudioEngine or load a test tone)
   - Add a "Volume" slider that calls AU parameter setter (Master Gain)
   - Add a status label showing "Engine Ready" / "Engine Error"

3. Test playback
   - Play a silent buffer through the AU (verify no dropouts)
   - Play a 1 kHz reference tone (use vDSP to generate)
   - Monitor CPU usage (should be <5% for pass-through mode)

**Acceptance Criteria:**
- App initializes AU without errors
- Audio plays (silent or reference tone) at 48 kHz
- No UI freezes during playback
- Parameter changes (volume slider) are heard in real-time

---

## Acceptance Criteria (Phase 1a Done-Done)

- [x] AUAudioUnit v3 scaffold compiles and loads
- [x] Render callback runs at buffer rate (no dropouts)
- [x] TargetState POD + DoubleBufferSnapshot unit test passes
- [x] DSP kernel placeholder process() method works
- [x] SwiftUI app can initialize AU and play audio
- [x] Zero compiler warnings
- [x] Zero ASAN violations (memory safety)
- [x] All code formatted (clang-format + swiftformat)
- [x] Documentation updated (README notes AU integration)

---

## Timeline

| Task | Duration | Owner | Start | End |
|------|----------|-------|-------|-----|
| AUAudioUnit v3 Scaffold | 1 day | Audio DSP Engineer | Day 1 | Day 2 |
| TargetState + DoubleBufferSnapshot | 1 day | Audio DSP Engineer | Day 1 | Day 2 |
| DSP Kernel Scaffold | 0.5 day | Audio DSP Engineer | Day 2 | Day 2 PM |
| Swift Bridge + UI | 1 day | Frontend Developer | Day 1 | Day 2 |
| Testing + Integration | 0.5 day | QA Lead | Day 2 PM | Day 3 |
| **Total** | **2.5 days** | — | **Day 1** | **Day 3 EOD** |

---

## Dependencies & Blockers

| Item | Status | Note |
|------|--------|------|
| AudioToolbox framework | Available | macOS SDK |
| AVAudioEngine API | Available | macOS 14+ |
| Xcode 15+ | Required | C++17 + Obj-C++ support |
| Blocker resolutions (all 4) | ✅ Locked | See `02-blocker-resolutions.md` |

**No known blockers.** All infrastructure decisions locked. Ready to build.

---

## Success Metrics

Phase 1a is **Done-Done** when:

1. ✅ AU renders audio without dropouts (48 kHz / 512 frames)
2. ✅ Param bus transport verified (unit test + integration)
3. ✅ SwiftUI app plays reference tone at button tap
4. ✅ Volume slider works (AU parameter change heard in real-time)
5. ✅ Zero compiler warnings, ASAN clean
6. ✅ Code formatted, documented, committed

This unblocks Phase 1b (EQ module) with confidence.

---

## Next Phase (1b)

Phase 1b will implement the **first real DSP module: EQ**. With Phase 1a infrastructure locked, Phase 1b is straightforward:
- Implement vDSP biquad cascade (EQ kernel)
- Fill in `EQModule::process()`
- Add UI (frequency graph + preset selector)
- Wire TargetState.eq updates from UI → param bus

---

**Kickoff Date:** 2026-06-14  
**Owner:** Audio DSP Engineer + Frontend Developer  
**Status:** 🚀 **READY TO BUILD**

Reference: [02-blocker-resolutions.md](02-blocker-resolutions.md) for implementation details.
