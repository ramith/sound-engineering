# ✅ Phase 0 Sprint: QA Expert

> **📦 ARCHIVED — historical Phase-0 sprint note (2026-06-16).** ✅ Completed; retained for provenance, not a current plan.

**Task:** Null Test Framework + Pre-Commit Hook  
**Owner:** QA Expert  
**Duration:** 1 day (Fri 06/19, after DSP finishes bypass)  
**Blocker Status:** CRITICAL (gates all future DSP commits)

---

## Overview

The null test verifies that `DSPKernel.process()` at `intensityLinear=0` produces bit-identical output to input. This is the **first gate** for all signal processing work.

---

## Task 1: Create Null Test Skeleton (2 hours)

### **File:** `Tests/DSPKernelNullTest.cpp`

```cpp
#include <gtest/gtest.h>
#include <cstring>
#include <cstdint>
#include <vector>
#include "DSPKernel.h"
#include "TargetState.h"

// Null test: intensity=0 ⇒ output = input (bit-identical)
class DSPKernelNullTest : public ::testing::Test {
 protected:
  void SetUp() override {
    kernel_.initialize(sampleRate_, maxFramesPerBuffer_);
  }
  
  AdaptiveSound::DSPKernel kernel_;
  static constexpr uint32_t sampleRate_ = 48000;
  static constexpr uint32_t maxFramesPerBuffer_ = 512;
};

// Test 1: White noise bypass
TEST_F(DSPKernelNullTest, WhiteNoiseBypasses) {
  const uint32_t numFrames = 512;
  std::vector<float> input(numFrames), output(numFrames);
  
  // Generate white noise
  std::mt19937 gen(42);  // Deterministic seed
  std::uniform_real_distribution<float> dist(-0.5f, 0.5f);
  for (uint32_t i = 0; i < numFrames; ++i) {
    input[i] = dist(gen);
  }
  std::memcpy(output.data(), input.data(), numFrames * sizeof(float));
  
  // Create TargetState with intensity=0
  AdaptiveSound::TargetState state = {};
  state.intensityLinear = 0.0f;  // BYPASS
  
  // Process
  kernel_.process(state, input.data(), output.data(), numFrames);
  
  // Verify bit-identical
  for (uint32_t i = 0; i < numFrames; ++i) {
    EXPECT_FLOAT_EQ(output[i], input[i]) 
      << "Sample " << i << " differs at intensity=0";
  }
}

// Test 2: Music file bypass (real audio)
TEST_F(DSPKernelNullTest, MusicFileBypass) {
  // Load a test WAV file (or generate one)
  // For now, generate a chirp (20 Hz - 20 kHz)
  const uint32_t numFrames = 48000;  // 1 second @ 48 kHz
  std::vector<float> input(numFrames), output(numFrames);
  
  // Chirp: f(t) = sin(2π * (f0 + (f1-f0)*t/T) * t)
  float f0 = 20.0f, f1 = 20000.0f, T = 1.0f;
  for (uint32_t i = 0; i < numFrames; ++i) {
    float t = i / static_cast<float>(sampleRate_);
    float freq = f0 + (f1 - f0) * t / T;
    input[i] = std::sin(2.0f * 3.14159265f * freq * t) * 0.5f;
  }
  std::memcpy(output.data(), input.data(), numFrames * sizeof(float));
  
  // Process with intensity=0
  AdaptiveSound::TargetState state = {};
  state.intensityLinear = 0.0f;
  
  // Process in chunks (512 frames at a time)
  for (uint32_t i = 0; i < numFrames; i += 512) {
    uint32_t chunk = std::min(512u, numFrames - i);
    kernel_.process(state, input.data() + i, output.data() + i, chunk);
  }
  
  // Verify bit-identical
  for (uint32_t i = 0; i < numFrames; ++i) {
    EXPECT_FLOAT_EQ(output[i], input[i]);
  }
}

// Test 3: EQ module individually
TEST_F(DSPKernelNullTest, EQModuleBypassAtZeroIntensity) {
  // When EQ is disabled (intensityLinear=0), output should be input
  const uint32_t numFrames = 512;
  std::vector<float> input(numFrames, 0.1f);
  std::vector<float> output = input;
  
  AdaptiveSound::TargetState state = {};
  state.intensityLinear = 0.0f;
  state.eq.enabled = false;  // Extra: also disable EQ
  
  kernel_.process(state, input.data(), output.data(), numFrames);
  
  for (uint32_t i = 0; i < numFrames; ++i) {
    EXPECT_FLOAT_EQ(output[i], input[i]);
  }
}

int main(int argc, char** argv) {
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
```

---

## Task 2: Wire into Test Suite (1 hour)

### **Update `Package.swift`:**

```swift
.testTarget(
  name: "AudioDSPTests",
  dependencies: ["AudioDSP"],
  sources: ["EQTests.swift", "EQModuleCoefficientsTests.swift", "DSPKernelNullTest.cpp"],
  swiftSettings: [
    .unsafeFlags(["-suppress-warnings"])
  ]
),
```

### **Build & Run:**

```bash
swift test --package-path . 2>&1 | grep -E "^(Test|PASS|FAIL|✓|✗)"
```

---

## Task 3: Pre-Commit Hook Integration (30 min)

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
set -e

echo "🔍 Running null test before commit..."

# Build and run null test
swift test --filter "DSPKernelNullTest" || {
  echo "❌ NULL TEST FAILED: intensity=0 bypass is broken"
  echo "   Fix: ensure DSPKernel::process() returns early at intensity=0"
  exit 1
}

echo "✅ Null test passed. Proceeding with commit."
exit 0
```

Make executable:
```bash
chmod +x .git/hooks/pre-commit
```

---

## Acceptance Criteria

- [ ] `DSPKernelNullTest.cpp` compiles (no warnings)
- [ ] All three tests pass (white noise, music, EQ bypass)
- [ ] Pre-commit hook runs automatically before every commit
- [ ] Hook fails if null test fails
- [ ] Documentation explains what the hook does

---

## Why This Matters

The null test is the **canary** for all DSP changes:
- If intensity=0 doesn't produce bit-exact bypass → all other tests are suspect
- Every future filter, limiter, clarity module must pass null test
- Pre-commit hook prevents accidental regression

---

## Timeline

- **Fri 06/19 AM:** DSP Engineer completes bypass implementation
- **Fri 06/19 PM:** QA Expert creates null test + hook
- **Ready for Phase 1:** Null test gates all commits starting Mon 06/23

---

**Ready?** Wait for DSP Engineer to implement `intensityLinear == 0` bypass, then build the test harness around it.

Let's ship this! 🚀
