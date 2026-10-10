// RealizerTests.inc — S6 Tier-3 (3a) Realizer multi-surface RMW contract.
//
// Drives the Realizer's synchronously-callable intent-application methods (applyEq /
// applyIntensity / applyCrossfeed — design §1.7) directly, on the calling thread, with no
// dispatch hop. Asserts the design's two RMW invariants (design §6, "Realizer"):
//   1. multi-surface read-modify-write does NOT clobber unrelated fields: apply EQ, then
//      intensity, then EQ -> the intensity set by surface 2 survives the surface-3 EQ apply,
//      and the EQ set by surface 3 does not revert intensity to its default.
//   2. sequenceNumber is STRICTLY increasing across every apply.
//
// The Realizer lives in the ObjC++ AU layer but depends only on libdispatch + DSPKernel +
// TargetState + the EQ designer (NOT AVFoundation/the ObjC AU), so it compiles+links into this
// harness. We assert on canonicalState() (the canonical RMW result the Realizer publishes).

#include "../Sources/AudioDSP/AudioEngine/Realizer.h"

namespace
{
    // An EQ intent with `gainDb` at `band`, On.
    auto realizerEqIntent(size_t band, float gainDb) -> AdaptiveSound::Realizer::EqIntent
    {
        AdaptiveSound::Realizer::EqIntent intent{};
        intent.points[band] = gainDb;
        intent.isOn = true;
        return intent;
    }

    auto eqIsDesigned(const EQParams& eq) -> bool
    {
        return eq.designSampleRate > 0.0F &&
               std::ranges::any_of(eq.m1, [](double mix) { return mix != 0.0; });
    }
} // namespace

static auto testRealizerMultiSurfaceRMW() -> void
{
    static const char* const kName = "Realizer_MultiSurfaceRMW_NoClobber_SeqMonotonic";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;

    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(kSR, TestConstants::kFrames512);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, static_cast<double>(kSR));

    const uint64_t seq0 = realizer->canonicalState().sequenceNumber;

    // Surface 1: apply an EQ boost. Intensity must keep its default (1.0).
    realizer->applyEq(realizerEqIntent(15U, 6.0F));
    const TargetState s1 = realizer->canonicalState();
    if (s1.sequenceNumber <= seq0)
    {
        logFail(kName, "sequenceNumber did not increase after applyEq #1");
        return;
    }
    if (s1.intensityLinear != 1.0F)
    {
        logFail(kName, "applyEq clobbered intensityLinear (expected default 1.0)");
        return;
    }
    if (!eqIsDesigned(s1.eq) || s1.eq.designSampleRate != static_cast<float>(kSR))
    {
        logFail(kName, "applyEq #1 did not publish a design at the Realizer's rate");
        return;
    }

    // Surface 2: interleave an intensity intent. EQ must survive unchanged.
    constexpr float kIntensity = 0.5F;
    realizer->applyIntensity(kIntensity);
    const TargetState s2 = realizer->canonicalState();
    if (s2.sequenceNumber <= s1.sequenceNumber)
    {
        logFail(kName, "sequenceNumber did not increase after applyIntensity");
        return;
    }
    if (s2.intensityLinear != kIntensity)
    {
        logFail(kName, "applyIntensity did not store the requested value");
        return;
    }
    if (std::memcmp(&s2.eq, &s1.eq, sizeof(EQParams)) != 0)
    {
        logFail(kName, "applyIntensity clobbered the EQ field");
        return;
    }

    // Surface 3: apply a DIFFERENT EQ. The intensity from surface 2 must NOT revert.
    AdaptiveSound::Realizer::EqIntent intentB = realizerEqIntent(5U, -4.0F);
    intentB.points[25] = 3.0F;
    realizer->applyEq(intentB);
    const TargetState s3 = realizer->canonicalState();
    if (s3.sequenceNumber <= s2.sequenceNumber)
    {
        logFail(kName, "sequenceNumber did not increase after applyEq #2");
        return;
    }
    if (s3.intensityLinear != kIntensity)
    {
        logFail(kName,
                "applyEq #2 clobbered intensityLinear set by the interleaved intensity intent");
        return;
    }

    // Full monotonic chain check: strictly increasing by exactly 1 per apply.
    if (s1.sequenceNumber != seq0 + 1 || s2.sequenceNumber != s1.sequenceNumber + 1 ||
        s3.sequenceNumber != s2.sequenceNumber + 1)
    {
        logFail(kName, "sequenceNumber not strictly +1 per apply across the three surfaces");
        return;
    }

    realizer->shutdown();
    realizer.reset();
    logPass(kName);
}

// ---------------------------------------------------------------------------
// CF-11 (QW1 §6): the FOURTH Realizer surface — crossfeed. Drives applyEq / applyIntensity /
// applyCrossfeed and asserts the same two RMW invariants extended to crossfeed:
//   1. multi-surface RMW does NOT clobber unrelated fields: EQ, then intensity, then crossfeed,
//      then EQ again → the intensity AND the crossfeed survive the final EQ apply.
//   2. sequenceNumber is STRICTLY +1 per apply across all four applies.
// Plus the clamp check: setPendingCrossfeed clamps level to [0,1] and preset to the valid enum
// range. (The Realizer owns the design rate, so there is no rate to reject.)
// ---------------------------------------------------------------------------
static auto testRealizerCrossfeedSurfaceRMW() -> void
{
    static const char* const kName = "Realizer_Crossfeed_4SurfaceRMW_Clamp";
    constexpr uint32_t kSR = TestConstants::kSampleRate48k;

    auto kernel = std::make_shared<DSPKernel>();
    kernel->initialize(kSR, TestConstants::kFrames512);
    auto realizer = std::make_shared<AdaptiveSound::Realizer>(kernel, static_cast<double>(kSR));

    const uint64_t seq0 = realizer->canonicalState().sequenceNumber;

    // Surface 1: EQ boost.
    realizer->applyEq(realizerEqIntent(15U, 6.0F));
    const EQParams eq1 = realizer->canonicalState().eq;
    const uint64_t seq1 = realizer->canonicalState().sequenceNumber;
    if (!eqIsDesigned(eq1))
    {
        logFail(kName, "applyEq published no design");
        return;
    }

    // Surface 2: intensity.
    constexpr float kIntensity = 0.5F;
    realizer->applyIntensity(kIntensity);
    const uint64_t seq2 = realizer->canonicalState().sequenceNumber;

    // Surface 3: crossfeed (Strong, full level). Coeffs derived off-RT; EQ + intensity must survive.
    constexpr uint32_t kStrongPreset = 2U; // CrossfeedPreset::Strong
    realizer->applyCrossfeed({.enabled = 1U, .level = 1.0F, .preset = kStrongPreset});
    const TargetState s3 = realizer->canonicalState();
    const uint64_t seq3 = s3.sequenceNumber;
    if (s3.crossfeed.enabled != 1U)
    {
        logFail(kName, "applyCrossfeed did not enable crossfeed");
        return;
    }
    if (s3.crossfeed.gCross <= 0.0F || s3.crossfeed.gDirect <= 0.0F)
    {
        logFail(kName, "applyCrossfeed did not derive active gains (gCross/gDirect)");
        return;
    }
    if (s3.crossfeed.delayFrames <= 0 || s3.crossfeed.delayFrames >= kMaxCrossfeedDelayFrames)
    {
        logFail(kName, "applyCrossfeed delayFrames out of the fixed-line range");
        return;
    }
    if (s3.intensityLinear != kIntensity)
    {
        logFail(kName, "applyCrossfeed clobbered intensityLinear");
        return;
    }
    if (std::memcmp(&s3.eq, &eq1, sizeof(EQParams)) != 0)
    {
        logFail(kName, "applyCrossfeed clobbered the EQ field");
        return;
    }

    // Surface 4: a DIFFERENT EQ. Intensity AND crossfeed must NOT revert.
    realizer->applyEq(realizerEqIntent(5U, -4.0F));
    const TargetState s4 = realizer->canonicalState();
    const uint64_t seq4 = s4.sequenceNumber;
    if (s4.intensityLinear != kIntensity)
    {
        logFail(kName, "final applyEq clobbered intensityLinear");
        return;
    }
    if (s4.crossfeed.enabled != 1U || s4.crossfeed.gCross != s3.crossfeed.gCross)
    {
        logFail(kName, "final applyEq clobbered the crossfeed field");
        return;
    }

    // sequenceNumber strictly +1 across all four applies.
    if (seq1 != seq0 + 1 || seq2 != seq1 + 1 || seq3 != seq2 + 1 || seq4 != seq3 + 1)
    {
        logFail(kName, "sequenceNumber not strictly +1 per apply across the four surfaces");
        return;
    }

    // --- Clamp check on setPendingCrossfeed (the surface that clamps). ---
    realizer->setPendingCrossfeed(1U, 5.0F, 99U);
    realizer->shutdown(); // dispatch_sync barrier flushes the pending drain
    const TargetState& sc = realizer->canonicalState();
    // Clamped level 5.0 → 1.0 (full alpha) and preset 99 → Strong (2): the gains must match the
    // surface-3 (level=1, Strong) derivation exactly.
    if (sc.crossfeed.preset != kStrongPreset)
    {
        logFail(kName, "setPendingCrossfeed did not clamp preset 99 → Strong");
        return;
    }
    if (std::abs(sc.crossfeed.gCross - s3.crossfeed.gCross) > 1e-6F)
    {
        logFail(kName, "setPendingCrossfeed did not clamp level 5.0 → 1.0 (gCross diverged)");
        return;
    }

    realizer.reset();
    logPass(kName);
}
