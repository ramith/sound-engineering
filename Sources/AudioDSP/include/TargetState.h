#ifndef ADAPTIVE_SOUND_TARGET_STATE_H
#define ADAPTIVE_SOUND_TARGET_STATE_H

#include "AudioConstants.h"
#include <array>
#include <cstdint>
#include <type_traits>

namespace AdaptiveSound
{

    static constexpr int kMaxBiquads = 10;

    struct EQParams
    {
        struct BiquadCoeffs
        {
            float b0, b1, b2, a1, a2;
        };
        std::array<BiquadCoeffs, kMaxBiquads> biquads{};
        uint8_t numBiquads = 0;
        float masterGainLinear = 1.0F;
        std::array<uint8_t, 3> _pad = {};
    };

    struct ClarityParams
    {
        float thresholdLinear = kClarityDefaultThresholdLinear;
        float attackCoeff = 0.F;
        float releaseCoeff = 0.F;
        float ratioRecip = kClarityDefaultRatioRecip;
        float kneeWidthLinear = kClarityDefaultKneeWidthLinear;
        uint8_t enabled = 1;
        std::array<uint8_t, 3> _pad = {};
    };

    struct LoudnessParams
    {
        float makeupGainLinear = 1.0F;
        float lufsTarget = kDefaultLufsTarget;
        uint8_t enabled = 1;
        std::array<uint8_t, 3> _pad = {};
    };

    struct BRIRParams
    {
        uint8_t activeSlotIndex = 0;
        float azimuthDeg = 0.F;
        float elevationDeg = 0.F;
        float roomAmountLinear = 1.0F;
        uint8_t bassMonoGated = 1;
        std::array<uint8_t, 3> _pad = {};
    };

    // User-facing crossfeed strength presets (QW1 §5). The middle case is `Bauer` (NOT
    // `Default`) to avoid the `default:` keyword clash in switch statements (refactoring F8);
    // the Swift-facing label for `Bauer` stays "Default". Underlying type is uint8_t so it can
    // packs alongside the other intent bytes in CrossfeedParams without padding surprises.
    // NOLINTNEXTLINE(performance-enum-size)
    enum class CrossfeedPreset : uint8_t
    {
        Relaxed = 0, // bs2b "Jmeier": fc 650 Hz, cross -9.5 dB (alpha 0.335) — subtlest
        Bauer = 1,   // bs2b "Default": fc 700 Hz, cross -9.0 dB (alpha 0.355) — safe default
        Strong = 2,  // bs2b "Cmoy": fc 700 Hz, cross -6.0 dB (alpha 0.501) — most spacious
    };

    // Crossfeed (QW1 §2/§3): a wet-region headphone-soundstage stage between BRIR and the
    // Limiter. Symmetrical stereo crossfeed (Bauer/bs2b): cross path = one-pole LPF + ITD delay
    // + attenuation; direct path unfiltered/undelayed. Concrete layout (F2 — protects the golden
    // master): intent bytes first, then off-RT-derived coefficients; EVERY field explicitly
    // defaulted so canonical_{} zero/identity-inits to "off" (enabled=0, unity direct, zero
    // cross) → bit-exact pass-through → golden master unchanged.
    //
    // Invariant (record now; enforce at S18 — QW1 §2/§9): crossfeed and a future binaural BRIR
    // are MUTUALLY EXCLUSIVE output-rendering modes (both synthesize the head-related cross-path;
    // running both would double-apply). The control layer (Realizer/VM) must never enable both.
    // No arbitration code in QW1 (BRIRModule is an empty stub — nothing to arbitrate). When S18
    // BRIR ships, treat `crossfeed.enabled && brir.active` as a control-layer bug and
    // deterministically prefer one (document which then).
    struct CrossfeedParams
    {
        // --- Intent (set by the control layer / UI) ---
        uint8_t enabled = 0;             // 0 = bypass (bit-exact pass-through); 1 = active
        uint8_t preset = 0;              // CrossfeedPreset value (Relaxed=0 default)
        std::array<uint8_t, 2> _pad = {}; // explicit pad → trivial, deterministic layout
        // --- Derived (computed off-RT in the Realizer from {preset, level, fs}) ---
        float gDirect = 1.0F;    // direct-path gain = 1/(1+alpha)  (off: unity)
        float gCross = 0.0F;     // cross-path gain  = alpha/(1+alpha) (off: zero → no cross)
        float lpfB0 = 0.0F;      // one-pole cross LPF input coeff (1-p) (off: zero)
        float lpfPole = 0.0F;    // one-pole cross LPF pole coeff p = exp(-2π·fc/fs) (off: zero)
        int32_t delayFrames = 0; // ITD delay in frames = round(0.0003178·fs) (off: zero)
    };

    struct LimiterParams
    {
        // Only user/control-facing parameter. Set ≥ 1.0 to bypass (zero-latency identity).
        // Attack/release time constants and the look-ahead window are fixed design
        // constants of LimiterModule (computed off-RT in initialize()), not runtime
        // parameters — a runtime look-ahead can't resize the module's fixed ring anyway.
        float truePeakCeilingLinear = kTruePeakCeilingLinear;
    };

    struct alignas(kCacheLineBytes) TargetState
    {
        EQParams eq;
        ClarityParams clarity;
        LoudnessParams loudness;
        BRIRParams brir;
        CrossfeedParams crossfeed; // QW1: wet-region crossfeed, between brir and limiter
        LimiterParams limiter;
        float intensityLinear = 1.0F;
        uint64_t sequenceNumber = 0;
    };

    // Verify trivially copyable at compile time (C++11 compatible)
    static_assert(std::is_trivially_copyable<TargetState>::value,
                  "TargetState must be trivially copyable");
    static_assert(std::is_standard_layout<TargetState>::value,
                  "TargetState must have standard layout");

    // Lock the layout (QW1 §3 F2) — N is the MEASURED post-insertion size, NOT an assumption.
    // Inserting the 24-byte CrossfeedParams fit inside the slack of the alignas(64) struct (the
    // members already occupy < 320 B; they end at offset 312, padded to 320 for the 64-byte
    // alignment), so sizeof stayed 320 (the design's "very likely 320→384" was an estimate; the
    // measured value is what we assert). This size is golden-master-NEUTRAL: the hash is over audio
    // output + default field values, not sizeof. If a FUTURE change trips this assert: re-MEASURE
    // N, then re-confirm the golden-master hash (CF-1) still holds — never silently bump N.
    constexpr size_t kMeasuredTargetStateBytes = 320;
    static_assert(sizeof(TargetState) == kMeasuredTargetStateBytes,
                  "TargetState size changed — re-measure N and re-confirm the golden master (CF-1)");

} // namespace AdaptiveSound

#endif
