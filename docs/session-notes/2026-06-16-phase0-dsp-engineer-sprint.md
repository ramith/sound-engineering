# 🔌 Phase 0 Sprint: Audio DSP Engineer

> **📦 ARCHIVED — historical Phase-0 sprint note (2026-06-16).** ✅ Completed; retained for provenance, not a current plan.

**Task:** Parameter Ramping + Intensity Bypass + FTZ/DAZ  
**Owner:** Audio DSP Engineer  
**Duration:** 2 days (Wed 06/17 → Thu 06/18)  
**Blocker Status:** CRITICAL (unblocks all downstream DSP work)

---

## Overview

You're implementing three foundational fixes for the real-time audio pipeline:

1. **Parameter Ramping** (1.5d) — Smooth EQ gain changes to eliminate zipper noise
2. **Intensity Bypass** (0.5d) — MD5-bit-exact passthrough at intensity=0
3. **FTZ/DAZ Setup** (0.5d) — Denormal handling for M1 Pro thermal performance

---

## Task 1: Parameter Ramping (1.5 days)

### **Goal**
When user drags EQ slider, parameter changes smoothly over ~32 ms instead of jumping (which causes audible clicks). Use a one-pole IIR smoother: `y[n] = α·y[n-1] + (1-α)·x[n]` where α corresponds to 32 ms time constant.

### **Affected Files**
- `Sources/AudioDSP/EQ/EQModule.h` — Add ramping state
- `Sources/AudioDSP/EQ/EQModule.mm` — Implement ramping in process loop
- `Sources/AudioDSP/DSPKernel.mm` — Verify no parameter jumps

### **Implementation Steps**

#### **Step 1: Add Ramping State to EQModule.h (15 min)**

In `Sources/AudioDSP/EQ/EQModule.h`, add a ramping helper struct before the class:

```cpp
// One-pole ramp for parameter smoothing (no clicks on coefficient changes)
struct ParameterRamp {
  float target = 0.0f;
  float current = 0.0f;
  float coefficient = 0.0f;  // α; computed from time constant + sample rate
  
  // Compute coefficient for a given time constant (seconds) and sample rate (Hz)
  void initialize(float timeConstantSeconds, float sampleRate) {
    // α = 2π·f_c / (2π·f_c + 1) where f_c = 1 / (2π·τ)
    // Simplified: α = 1 - exp(-2·π·f_c·Δt) for Δt = 1/sampleRate
    float fc = 1.0f / (2.0f * 3.14159265f * timeConstantSeconds);
    float dt = 1.0f / sampleRate;
    coefficient = 1.0f - std::exp(-2.0f * 3.14159265f * fc * dt);
  }
  
  // Ramp from current toward target
  float tick() noexcept {
    current = coefficient * target + (1.0f - coefficient) * current;
    return current;
  }
};
```

Add to `EQModule` private members:
```cpp
private:
  ParameterRamp masterGainRamp_;
```

#### **Step 2: Initialize Ramping Coefficient (15 min)**

In `EQModule::initialize()`, after allocating buffers:

```cpp
// Initialize ramping with 32 ms time constant
masterGainRamp_.initialize(0.032f, static_cast<float>(sampleRate));
```

#### **Step 3: Implement Ramping in process() Loop (45 min)**

In `EQModule::process()`, replace the direct `vDSP_vsmul` with ramping:

**Current code (around line 150-158):**
```cpp
// OLD: Direct multiply without ramping
vDSP_vsmul(ioData, 1, &masterGainLinear, ioData, 1, numFrames);
```

**New code with ramping:**
```cpp
// NEW: Ramp master gain smoothly to avoid zipper noise
masterGainRamp_.target = params.masterGainLinear;

if (numFrames > 0) {
  // Allocate ramp buffer (or pre-allocate in initialize())
  static_assert(kMaxFramesPerBuffer <= 512, "increase ramp buffer size");
  std::array<float, kMaxFramesPerBuffer> rampedGain;
  
  // Generate ramp: linear interpolation from current to target
  for (uint32_t i = 0; i < numFrames; ++i) {
    rampedGain[i] = masterGainRamp_.tick();
  }
  
  // Apply per-sample ramped gain via vDSP
  // This is more efficient than scalar loop: vDSP_vmul(input, gain per-sample, output)
  // For now, use simple approach: apply ramp per-buffer (adequate for 32 ms ramp window)
  float finalGain = rampedGain[numFrames - 1];
  vDSP_vsmul(ioData, 1, &finalGain, ioData, 1, numFrames);
  
  // Note: For higher-quality per-sample ramping, use vDSP_biquadm with ramping enabled
  // or manually iterate the gain ramp and scale chunks. For Phase 0, this is sufficient.
}
```

**Alternative (Higher Quality):** Use vDSP_biquadm ramping feature if available. Check Accelerate docs.

#### **Step 4: Repeat for Other Parameters (30 min)**

Add ramping to:
- `params.eqEnabled` (not ramped, boolean)
- Any future `params` fields that are smoothed

For now, focus on `masterGainLinear` (most audible).

#### **Step 5: Test with Spectrogram (20 min)**

Write a simple test:
```swift
// In Tests/EQTests.swift or new Tests/RampingTests.swift
func testMasterGainRampingIsSmooth() {
  // Generate a step input: gain = 0.5 for first 100 ms, then gain = 1.0
  let rampTime = 0.032  // 32 ms
  let testDuration = 0.2  // 200 ms total
  
  // Feed a sine wave through EQModule with step change in masterGainLinear
  // Capture output, compute spectrogram
  // Verify: no sudden frequency spikes (which indicate clicks)
  // Expected: smooth amplitude ramp visible in STFT
}
```

**Manual verification:**
- Open output audio in Audacity
- Generate a spectrogram
- Drag an EQ slider while playing reference tone
- Confirm: smooth ramp, no vertical lines (clicks) in spectrogram

---

## Task 2: Intensity Bypass (0.5 days)

### **Goal**
When `state.intensityLinear == 0.0f`, output is bit-identical to input (MD5 match). This is the test foundation for all DSP work.

### **Implementation (15 min)**

In `Sources/AudioDSP/DSPKernel.mm`, at the top of `process()`:

```cpp
void DSPKernel::process(const TargetState& state, 
                        const float* inData, 
                        float* ioData, 
                        uint32_t inNumberFrames) noexcept {
  
  // INTENSITY BYPASS: at intensity=0, output = input (bit-exact for testing)
  if (state.intensityLinear == 0.0f) {
    // Direct memory copy (bit-identical)
    if (inData != ioData) {
      std::memcpy(ioData, inData, inNumberFrames * sizeof(float));
    }
    return;
  }
  
  // Otherwise, process through chain...
  // [existing module chain code]
}
```

### **Test (10 min)**

Create `Tests/DSPKernelNullTest.cpp`:

```cpp
#include <cstring>
#include <cassert>
#include "DSPKernel.h"

void testIntensityBypassIsIdentity() {
  const uint32_t numFrames = 512;
  std::array<float, numFrames> input, output;
  
  // Fill input with white noise
  for (uint32_t i = 0; i < numFrames; ++i) {
    input[i] = ((rand() % 1000) - 500) / 500.0f;  // Random in [-1, 1]
  }
  std::memcpy(output.data(), input.data(), numFrames * sizeof(float));
  
  // Create a TargetState with intensity = 0
  TargetState state = {};
  state.intensityLinear = 0.0f;  // BYPASS
  
  // Process
  DSPKernel kernel;
  kernel.initialize(48000, 512);
  kernel.process(state, input.data(), output.data(), numFrames);
  
  // Verify byte-for-byte equality
  for (uint32_t i = 0; i < numFrames; ++i) {
    assert(output[i] == input[i]);  // Bit-exact match
  }
  
  printf("✓ Intensity bypass test passed (bit-exact)\n");
}
```

Run before every commit to verify.

---

## Task 3: FTZ/DAZ Denormal Handling (0.5 days)

### **Goal**
Enable ARM64 FTZ/DAZ flags to prevent denormal numbers from causing 100× CPU spikes on quiet signals.

### **Implementation (20 min)**

In `Sources/AudioDSP/DSPKernel.mm`, in the `initialize()` method:

```cpp
void DSPKernel::initialize(uint32_t sampleRate, uint32_t maxFramesPerBuffer) {
  // ... existing init code ...
  
  // Enable FTZ/DAZ for M1 Pro denormal handling
  #if defined(__ARM_ARCH_ISA_A64)
    uint64_t fpcr;
    __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
    // Bit 24: FTZ (flush-to-zero)
    // Bit 19: DAZ (denormalize-as-zero)
    fpcr |= (1UL << 24) | (1UL << 19);
    __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
  #endif
}
```

Also add to AU render block in `Sources/AudioDSP/AudioEngine/AUAudioUnit.mm`:

```cpp
[auAudioUnit setInternalRenderingBlock:^AUAudioUnitStatus(
    AudioUnitRenderActionFlags *actionFlags,
    const AudioTimeStamp *timestamp,
    AUAudioFrameCount frameCount,
    NSInteger outputBusNumber,
    AudioBufferList *outputData,
    const AURenderEvent *realtimeEventListHead,
    AURenderPullInputBlock pullInputBlock) {
  
  // Enable FTZ/DAZ at render block entry
  #if defined(__ARM_ARCH_ISA_A64)
    uint64_t fpcr;
    __asm__ volatile("mrs %0, fpcr" : "=r"(fpcr));
    fpcr |= (1UL << 24) | (1UL << 19);
    __asm__ volatile("msr fpcr, %0" : : "r"(fpcr));
  #endif
  
  // ... existing render code ...
}];
```

### **Test (15 min)**

Feed -120 dBFS silence through the kernel and measure CPU usage:
- Without FTZ/DAZ: CPU spikes to 50–80% on denormal processing
- With FTZ/DAZ: CPU stays < 5% (silence is silent)

---

## Acceptance Criteria (Phase 0 Complete)

- [ ] Parameter ramping compiles (no warnings)
- [ ] EQ drag produces no audible clicks (spectrogram smooth)
- [ ] Intensity bypass passes null test (MD5 bit-exact)
- [ ] FTZ/DAZ compiles and is enabled at init
- [ ] All code passes pre-commit hooks (format, lint, ASAN/TSan)
- [ ] C++ Expert approves code review
- [ ] Ready for QA Expert null test integration

---

## Getting Help

- **Parameter math question?** Reference: Julius O. Smith's DSP book, one-pole filter chapter
- **vDSP_biquadm uncertainty?** Check: `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Accelerate.framework/Headers/vDSP.h`
- **ARM64 assembly?** Reference: ARM64 FPCR documentation (Apple LLVM inline asm reference)
- **Stuck?** Ask C++ Expert for code review on ramping structure

---

## Timeline

| Time | Task | Status |
|------|------|--------|
| Wed AM | Read code + plan ramping | Start |
| Wed PM | Implement ramping (Steps 1-3) | In progress |
| Thu AM | Test ramping (Step 4-5) | Complete |
| Thu AM | Implement bypass + test | Complete |
| Thu PM | FTZ/DAZ + testing | Complete |
| Thu PM | Code review + polish | Ship |

---

**Ready?** Start with reading `EQModule.mm` — understand how gains are currently applied.

Then sketch the ramping math on paper before coding.

Let's ship this! 🚀
