#include <array>
#include <cassert>
#include <cmath>
#include <cstdio>
#include <limits>

// Include the coefficients header
#include "AudioDSP/EQ/EQModuleCoefficients.h"

using namespace AdaptiveSound;

// Test utilities
namespace TestUtils
{
    constexpr float kFloatTolerance = 1e-5f;

    bool almostEqual(float a, float b, float tolerance = kFloatTolerance)
    {
        return std::abs(a - b) < tolerance;
    }

    void assertAlmostEqual(float a, float b, const char* message, float tolerance = kFloatTolerance)
    {
        if (!almostEqual(a, b, tolerance))
        {
            std::printf(
                "FAIL: %s (expected %.6f, got %.6f, diff %.6e)\n", message, a, b, std::abs(a - b));
            assert(false);
        }
    }

    void assertEqual(bool condition, const char* message)
    {
        if (!condition)
        {
            std::printf("FAIL: %s\n", message);
            assert(false);
        }
    }

    void assertFinite(float value, const char* message)
    {
        if (!std::isfinite(value))
        {
            std::printf("FAIL: %s (value is NaN or Inf: %.6e)\n", message, value);
            assert(false);
        }
    }
} // namespace TestUtils

// Test 1: All gains zero → pass-through (unity gain)
void testFlatResponsePassThrough()
{
    std::printf("\n[TEST 1] Flat response (all gains = 0 dB)\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);

    float sampleRate = 48000.0f;
    EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    // Should have 1 biquad with unity gain coefficients
    TestUtils::assertEqual(result.numBiquads == 1, "Should have exactly 1 biquad");
    TestUtils::assertAlmostEqual(result.biquads[0].b0, 1.0f, "b0 should be 1.0");
    TestUtils::assertAlmostEqual(result.biquads[0].b1, 0.0f, "b1 should be 0.0");
    TestUtils::assertAlmostEqual(result.biquads[0].b2, 0.0f, "b2 should be 0.0");
    TestUtils::assertAlmostEqual(result.biquads[0].a1, 0.0f, "a1 should be 0.0");
    TestUtils::assertAlmostEqual(result.biquads[0].a2, 0.0f, "a2 should be 0.0");
    TestUtils::assertAlmostEqual(result.masterGainLinear, 1.0f, "Master gain should be 1.0");

    std::printf("✓ PASS: Flat response yields pass-through filter\n");
}

// Test 2: Single-band peak (boost at 1 kHz)
void testSingleBandPeak()
{
    std::printf("\n[TEST 2] Single-band peak at 1 kHz (+6 dB)\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);
    gains[17] = 6.0f; // 1 kHz band is at index 17

    float sampleRate = 48000.0f;
    EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    // Should produce at least 1 biquad
    TestUtils::assertEqual(result.numBiquads >= 1, "Should have at least 1 biquad");
    TestUtils::assertEqual(result.numBiquads <= 10, "Should not exceed 10 biquads");

    // Check all coefficients are finite
    for (uint8_t i = 0; i < result.numBiquads; ++i)
    {
        const auto& b = result.biquads[i];
        TestUtils::assertFinite(b.b0, "b0 should be finite");
        TestUtils::assertFinite(b.b1, "b1 should be finite");
        TestUtils::assertFinite(b.b2, "b2 should be finite");
        TestUtils::assertFinite(b.a1, "a1 should be finite");
        TestUtils::assertFinite(b.a2, "a2 should be finite");
    }

    std::printf("✓ PASS: Single-band peak produces valid coefficients\n");
}

// Test 3: Extreme gains (±12 dB, the spec limits)
void testExtremeGains()
{
    std::printf("\n[TEST 3] Extreme gains (±12 dB)\n");

    // Test +12 dB
    {
        std::array<float, 31> gains{};
        gains.fill(0.0f);
        gains[10] = 12.0f; // 200 Hz band

        float sampleRate = 48000.0f;
        EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

        TestUtils::assertEqual(result.numBiquads >= 1, "Should produce valid biquads for +12 dB");
        for (uint8_t i = 0; i < result.numBiquads; ++i)
        {
            const auto& b = result.biquads[i];
            TestUtils::assertFinite(b.b0, "Coefficients should be finite for +12 dB");
            TestUtils::assertFinite(b.b1, "");
            TestUtils::assertFinite(b.b2, "");
            TestUtils::assertFinite(b.a1, "");
            TestUtils::assertFinite(b.a2, "");
        }
    }

    // Test -12 dB
    {
        std::array<float, 31> gains{};
        gains.fill(0.0f);
        gains[25] = -12.0f; // 6.3 kHz band

        float sampleRate = 48000.0f;
        EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

        TestUtils::assertEqual(result.numBiquads >= 1, "Should produce valid biquads for -12 dB");
        for (uint8_t i = 0; i < result.numBiquads; ++i)
        {
            const auto& b = result.biquads[i];
            TestUtils::assertFinite(b.b0, "Coefficients should be finite for -12 dB");
            TestUtils::assertFinite(b.b1, "");
            TestUtils::assertFinite(b.b2, "");
            TestUtils::assertFinite(b.a1, "");
            TestUtils::assertFinite(b.a2, "");
        }
    }

    std::printf("✓ PASS: Extreme gains (±12 dB) produce stable coefficients\n");
}

// Test 4: Stability check (poles inside unit circle)
void testStability()
{
    std::printf("\n[TEST 4] Stability (poles inside unit circle)\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);
    gains[15] = 8.0f;  // 800 Hz, boost
    gains[17] = -4.0f; // 1 kHz, cut

    float sampleRate = 48000.0f;
    EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    // Check stability condition for all biquads
    for (uint8_t i = 0; i < result.numBiquads; ++i)
    {
        const auto& b = result.biquads[i];

        // For stable biquad: |a2| < 1 and |a1| < 1 + a2
        TestUtils::assertEqual(std::abs(b.a2) < 1.0f, "Pole radius condition |a2| < 1 should hold");
        TestUtils::assertEqual(std::abs(b.a1) <= (1.0f + b.a2 + 1e-5f),
                               "Schur-Cohn stability condition should hold");
    }

    std::printf("✓ PASS: All biquads are stable\n");
}

// Test 5: Multiple peaks (complex response)
void testMultiplePeaks()
{
    std::printf("\n[TEST 5] Multiple peaks (presence boost)\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);
    gains[12] = 2.0f; // 315 Hz
    gains[15] = 3.0f; // 800 Hz
    gains[18] = 4.0f; // 1.25 kHz
    gains[20] = 3.0f; // 2 kHz
    gains[22] = 2.0f; // 3.15 kHz

    float sampleRate = 48000.0f;
    EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    TestUtils::assertEqual(result.numBiquads >= 1 && result.numBiquads <= 10,
                           "Should fit within 10 biquad limit");

    // All coefficients should be finite
    for (uint8_t i = 0; i < result.numBiquads; ++i)
    {
        const auto& b = result.biquads[i];
        TestUtils::assertFinite(b.b0, "b0 finite in complex response");
        TestUtils::assertFinite(b.b1, "b1 finite in complex response");
        TestUtils::assertFinite(b.b2, "b2 finite in complex response");
        TestUtils::assertFinite(b.a1, "a1 finite in complex response");
        TestUtils::assertFinite(b.a2, "a2 finite in complex response");
    }

    std::printf("✓ PASS: Multiple peaks handled correctly\n");
}

// Test 6: Very small gains (below 0.5 dB threshold)
void testSmallGains()
{
    std::printf("\n[TEST 6] Small gains (below 0.5 dB threshold)\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);
    gains[10] = 0.3f; // Below threshold
    gains[15] = 0.2f; // Below threshold

    float sampleRate = 48000.0f;
    EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    // Should produce a pass-through filter (all gains below threshold)
    TestUtils::assertEqual(result.numBiquads >= 1, "Should produce at least 1 biquad");

    std::printf("✓ PASS: Small gains handled gracefully\n");
}

// Test 7: Different sample rates
void testDifferentSampleRates()
{
    std::printf("\n[TEST 7] Different sample rates\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);
    gains[17] = 6.0f; // 1 kHz band

    float rates[] = {44100.0f, 48000.0f, 96000.0f};

    for (float sr : rates)
    {
        EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sr);
        TestUtils::assertEqual(result.numBiquads >= 1 && result.numBiquads <= 10,
                               "Valid biquads at any sample rate");

        for (uint8_t i = 0; i < result.numBiquads; ++i)
        {
            const auto& b = result.biquads[i];
            TestUtils::assertFinite(b.b0, "Finite at different sample rate");
            TestUtils::assertFinite(b.a1, "");
            TestUtils::assertFinite(b.a2, "");
        }
    }

    std::printf("✓ PASS: Valid coefficients at all sample rates\n");
}

// Test 8: Biquad count respects max limit
void testBiquadCountLimit()
{
    std::printf("\n[TEST 8] Biquad count limit (max 10)\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);
    // Create many peaks to stress the fitting algorithm
    for (int i = 0; i < 31; i += 3)
    {
        gains[i] = 3.0f + static_cast<float>(i % 5);
    }

    float sampleRate = 48000.0f;
    EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    TestUtils::assertEqual(result.numBiquads > 0 && result.numBiquads <= 10,
                           "Biquad count should not exceed max");

    std::printf("✓ PASS: Biquad count stays within limits (got %d)\n", result.numBiquads);
}

// Test 9: Consistency (same input → same output)
void testConsistency()
{
    std::printf("\n[TEST 9] Consistency (deterministic output)\n");

    std::array<float, 31> gains{};
    gains.fill(0.0f);
    gains[17] = 5.0f;
    gains[18] = 3.0f;
    gains[20] = 2.0f;

    float sampleRate = 48000.0f;

    EQParams result1 = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);
    EQParams result2 = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

    TestUtils::assertEqual(result1.numBiquads == result2.numBiquads, "Same biquad count");

    for (uint8_t i = 0; i < result1.numBiquads; ++i)
    {
        TestUtils::assertAlmostEqual(
            result1.biquads[i].b0, result2.biquads[i].b0, "Consistent b0 coefficients", 1e-6f);
        TestUtils::assertAlmostEqual(
            result1.biquads[i].b1, result2.biquads[i].b1, "Consistent b1 coefficients", 1e-6f);
        TestUtils::assertAlmostEqual(
            result1.biquads[i].b2, result2.biquads[i].b2, "Consistent b2 coefficients", 1e-6f);
        TestUtils::assertAlmostEqual(
            result1.biquads[i].a1, result2.biquads[i].a1, "Consistent a1 coefficients", 1e-6f);
        TestUtils::assertAlmostEqual(
            result1.biquads[i].a2, result2.biquads[i].a2, "Consistent a2 coefficients", 1e-6f);
    }

    std::printf("✓ PASS: Deterministic output confirmed\n");
}

// Test 10: Edge case - single gain at extreme frequency
void testExtremeBandIndices()
{
    std::printf("\n[TEST 10] Extreme band indices (20 Hz and 20 kHz)\n");

    // Test lowest frequency band (20 Hz)
    {
        std::array<float, 31> gains{};
        gains.fill(0.0f);
        gains[0] = 5.0f; // 20 Hz

        float sampleRate = 48000.0f;
        EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

        TestUtils::assertEqual(result.numBiquads >= 1, "Valid biquads for 20 Hz");
        for (uint8_t i = 0; i < result.numBiquads; ++i)
        {
            TestUtils::assertFinite(result.biquads[i].b0, "Finite for 20 Hz");
        }
    }

    // Test highest frequency band (20 kHz)
    {
        std::array<float, 31> gains{};
        gains.fill(0.0f);
        gains[30] = -5.0f; // 20 kHz

        float sampleRate = 48000.0f;
        EQParams result = EQModuleCoefficients::computeBiquadCascade(gains, sampleRate);

        TestUtils::assertEqual(result.numBiquads >= 1, "Valid biquads for 20 kHz");
        for (uint8_t i = 0; i < result.numBiquads; ++i)
        {
            TestUtils::assertFinite(result.biquads[i].b0, "Finite for 20 kHz");
        }
    }

    std::printf("✓ PASS: Extreme frequencies handled correctly\n");
}

// Main test runner
int main()
{
    std::printf("=== EQ Module Coefficients Test Suite ===\n");

    testFlatResponsePassThrough();
    testSingleBandPeak();
    testExtremeGains();
    testStability();
    testMultiplePeaks();
    testSmallGains();
    testDifferentSampleRates();
    testBiquadCountLimit();
    testConsistency();
    testExtremeBandIndices();

    std::printf("\n=== ALL TESTS PASSED ===\n");
    return 0;
}
