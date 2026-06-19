// RealizerTests.inc — S6 Tier-3 (3a) Realizer multi-surface RMW contract.
//
// Drives the Realizer's synchronously-callable intent-application methods
// (applyEqGains / applyIntensity — design §1.7) directly, on the calling thread, with no
// dispatch hop. Asserts the design's two RMW invariants (design §6, "Realizer"):
//   1. multi-surface read-modify-write does NOT clobber unrelated fields: apply EQ, then
//      intensity, then EQ -> the intensity set by surface 2 survives the surface-3 EQ apply,
//      and the EQ set by surface 3 does not revert intensity to its default.
//   2. sequenceNumber is STRICTLY increasing across every apply.
//
// The Realizer lives in the ObjC++ AU layer but depends only on libdispatch + DSPKernel +
// TargetState + EQModuleCoefficients (NOT AVFoundation/the ObjC AU), so it compiles+links into
// this harness. We assert on canonicalState() (the canonical RMW result the Realizer publishes).

#include "../Sources/AudioDSP/AudioEngine/Realizer.h"

static auto testRealizerMultiSurfaceRMW() -> void
{
    static const char* const kName = "Realizer_MultiSurfaceRMW_NoClobber_SeqMonotonic";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;
    constexpr float kSRf = static_cast<float>(kSR);
    constexpr int kBands = EQModuleCoefficients::kNumBands;

    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(kSR, TestConstants::kFrames512);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel);

    const uint64_t seq0 = realizer->canonicalState().sequenceNumber;

    // Surface 1: apply an EQ boost. Intensity must keep its default (1.0).
    std::array<float, static_cast<size_t>(kBands)> gainsA{};
    gainsA[15] = 6.0F; // a single audible peak so the cascade is non-identity
    realizer->applyEqGains(gainsA, kSRf);
    const TargetState& s1 = realizer->canonicalState();
    const uint64_t seq1 = s1.sequenceNumber;
    const uint8_t eqBiquadsAfter1 = s1.eq.numBiquads;
    if (seq1 <= seq0)
    {
        logFail(kName, "sequenceNumber did not increase after applyEqGains #1");
        return;
    }
    if (s1.intensityLinear != 1.0F)
    {
        logFail(kName, "applyEqGains clobbered intensityLinear (expected default 1.0)");
        return;
    }
    if (eqBiquadsAfter1 == 0)
    {
        logFail(kName, "applyEqGains #1 produced no biquads (expected a non-identity cascade)");
        return;
    }

    // Surface 2: interleave an intensity intent. EQ must survive unchanged.
    constexpr float kIntensity = 0.5F;
    realizer->applyIntensity(kIntensity);
    const TargetState& s2 = realizer->canonicalState();
    const uint64_t seq2 = s2.sequenceNumber;
    if (seq2 <= seq1)
    {
        logFail(kName, "sequenceNumber did not increase after applyIntensity");
        return;
    }
    if (s2.intensityLinear != kIntensity)
    {
        logFail(kName, "applyIntensity did not store the requested value");
        return;
    }
    if (s2.eq.numBiquads != eqBiquadsAfter1)
    {
        logFail(kName, "applyIntensity clobbered the EQ field (numBiquads changed)");
        return;
    }

    // Surface 3: apply a DIFFERENT EQ. The intensity from surface 2 must NOT revert.
    std::array<float, static_cast<size_t>(kBands)> gainsB{};
    gainsB[5] = -4.0F;
    gainsB[25] = 3.0F;
    realizer->applyEqGains(gainsB, kSRf);
    const TargetState& s3 = realizer->canonicalState();
    const uint64_t seq3 = s3.sequenceNumber;
    if (seq3 <= seq2)
    {
        logFail(kName, "sequenceNumber did not increase after applyEqGains #2");
        return;
    }
    if (s3.intensityLinear != kIntensity)
    {
        logFail(kName,
                "applyEqGains #2 clobbered intensityLinear set by the interleaved intensity intent");
        return;
    }

    // Full monotonic chain check: strictly increasing by exactly 1 per apply.
    if (seq1 != seq0 + 1 || seq2 != seq1 + 1 || seq3 != seq2 + 1)
    {
        logFail(kName, "sequenceNumber not strictly +1 per apply across the three surfaces");
        return;
    }

    // Teardown must not UAF: drain the queue, then drop. (No async intents were posted here,
    // but exercise the documented teardown path anyway.)
    realizer->shutdown();
    realizer.reset();

    logPass(kName);
}
