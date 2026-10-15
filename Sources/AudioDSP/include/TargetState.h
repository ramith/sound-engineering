#pragma once

#include "AudioConstants.h"
#include <array>
#include <cstdint>
#include <type_traits>

namespace AdaptiveSound
{

    // The default one-pole time constant toward a new EQ target (engine-plan §3.2: every preset,
    // Tone, drag and Off toggle of a normal curve).
    inline constexpr float kEqDefaultRampSeconds = 0.010F;

    // The same glide time for every band.
    [[nodiscard]] constexpr std::array<float, kEqBandCount> eqUniformRamp(float seconds) noexcept
    {
        std::array<float, kEqBandCount> ramp{};
        ramp.fill(seconds);
        return ramp;
    }

    // The graphic EQ's FINISHED state (Sprint EQ, EQ1b): one Simper SVF bell per band, designed by
    // GraphicEQDesigner on the Realizer's queue. The RT module (EQModule) runs these coefficients
    // directly and glides each band to its new pair on a one-pole per sample ("S2", engine-plan
    // §3) — it never designs. A default-constructed EQParams (designSampleRate 0, every m1 0) is
    // the identity.
    struct EQParams
    {
        std::array<double, kEqBandCount> k{};  // per-band SVF damping (> 0 for a design)
        std::array<double, kEqBandCount> m1{}; // per-band band-pass mix; all 0 = identity
        // Broadband gain (dB) after the cascade — the loudness-neutral gain (EQ1c).
        double outputGainDb = 0.0;
        // Each band's one-pole τ toward ITS target (amendment 15), chosen by the Realizer's τ rule
        // (EQTargets::rampsFor) from the band's own bell. Read only for a band whose target moved.
        std::array<float, kEqBandCount> bandRampSeconds = eqUniformRamp(kEqDefaultRampSeconds);
        // The output gain's own τ. Read only when outputGainDb moved.
        float gainRampSeconds = kEqDefaultRampSeconds;
        // The rate (k, m1) were designed for; 0 = no design (identity). The RT module holds its last
        // good target when this differs from its own rate (re-allocation, engine-plan §6).
        float designSampleRate = 0.0F;

        // Member-wise value equality: the RT module adopts a snapshot only when it differs from the
        // last one it evaluated. A NaN member never compares equal, so such a snapshot is simply
        // re-evaluated (and rejected) each block.
        friend bool operator==(const EQParams&, const EQParams&) = default;
    };

    struct ClarityParams
    {
        float thresholdLinear = kClarityDefaultThresholdLinear;
        float attackCoeff = 0.F;
        float releaseCoeff = 0.F;
        float ratioRecip = kClarityDefaultRatioRecip;
        float kneeWidthLinear = kClarityDefaultKneeWidthLinear;
        uint8_t enabled = 1;
        std::array<uint8_t, 3> pad_ = {};
    };

    struct LoudnessParams
    {
        float makeupGainLinear = 1.0F;
        float lufsTarget = kDefaultLufsTarget;
        uint8_t enabled = 1;
        std::array<uint8_t, 3> pad_ = {};
    };

    struct BRIRParams
    {
        uint8_t activeSlotIndex = 0;
        float azimuthDeg = 0.F;
        float elevationDeg = 0.F;
        float roomAmountLinear = 1.0F;
        uint8_t bassMonoGated = 1;
        std::array<uint8_t, 3> pad_ = {};
    };

    // The crossfeed strengths (QW1 §5; R1.1-A, council C-42): bs2b's own levels, as libbs2b's
    // bs2b.h defines them (cut frequency, feed). The stored value — SettingsKit's CrossfeedStrength
    // raw value — is the index; the Swift labels are Relaxed / Default / Strong. bs2b's own default
    // is its strongest level, so it is the "Strong" rung, and Cmoy the "Default" (council P2-3).
    enum class CrossfeedPreset : uint8_t
    {
        Jmeier = 0,      // "Relaxed": BS2B_JMEIER_CLEVEL — 650 Hz, 9.5 dB feed (the subtlest)
        Cmoy = 1,        // "Default": BS2B_CMOY_CLEVEL — 700 Hz, 6.0 dB
        Bs2bDefault = 2, // "Strong": BS2B_DEFAULT_CLEVEL — 700 Hz, 4.5 dB (the strongest)
    };

    // Crossfeed (QW1; R1.1-A): headphone crossfeed, bs2b (CrossfeedModule), an output stage of the
    // kernel of its own — after the normaliser, before the limiter — at its preset's full strength
    // whatever Intensity is (founder decision 2026-10-14). The coefficients are bs2b's init()
    // (libbs2b bs2b.c) at the owned rate, its output gain folded into the numerators:
    //   direct path (high-boost shelf):  y = directB0·x + directB1·x[n−1] + directPole·y[n−1]
    //   cross path (low-pass):           y = crossB0·x + crossPole·y[n−1]
    // Concrete layout (F2 — protects the golden master): intent bytes first, then the off-RT-derived
    // coefficients; EVERY field explicitly defaulted so canonical_{} zero/identity-inits to "off"
    // (enabled = 0, unity direct, no cross) → bit-exact pass-through → golden master unchanged.
    //
    // Invariant (record now; enforce at S18 — QW1 §2/§9): crossfeed and a future binaural BRIR
    // are MUTUALLY EXCLUSIVE output-rendering modes (both synthesize the head-related cross-path;
    // running both would double-apply). The control layer (Realizer/VM) must never enable both.
    // No arbitration code yet (BRIRModule is an empty stub — nothing to arbitrate). When S18
    // BRIR ships, treat `crossfeed.enabled && brir.active` as a control-layer bug and
    // deterministically prefer one (document which then).
    struct CrossfeedParams
    {
        // --- Intent (set by the control layer / UI) ---
        uint8_t enabled = 0;              // 0 = off (bit-exact once its glide out ends); 1 = on
        uint8_t preset = 0;               // CrossfeedPreset value (Jmeier = 0)
        std::array<uint8_t, 2> pad_ = {}; // explicit pad → trivial, deterministic layout
        // --- Derived (computed off-RT in the Realizer from {preset, fs}) ---
        float directB0 = 1.0F;   // gain·a0_hi (off: unity)
        float directB1 = 0.0F;   // gain·a1_hi
        float directPole = 0.0F; // b1_hi
        float crossB0 = 0.0F;    // gain·a0_lo (off: no cross path)
        float crossPole = 0.0F;  // b1_lo
    };

    struct LimiterParams
    {
        // The control-facing parameters. Set ≥ 1.0 to bypass (zero-latency identity).
        // Attack/release time constants and the look-ahead window are fixed design
        // constants of LimiterModule (computed off-RT in initialize()), not runtime
        // parameters — a runtime look-ahead can't resize the module's fixed ring anyway.
        float truePeakCeilingLinear = kTruePeakCeilingLinear;
        // The ceiling of the EQ-only path (P1: Intensity 0 with the EQ on; founder decision 29):
        // −0.1 dBTP on a wired or built-in output, −1 dBTP on a lossy wireless link or an unknown
        // one. Set by the Realizer from the output's transport; P1 plays at the HIGHER of the two
        // ceilings (a bypassed limiter stays bypassed); every other path uses
        // truePeakCeilingLinear.
        float eqOnlyCeilingLinear = kTruePeakCeilingLinear;
    };

    struct alignas(kCacheLineBytes) TargetState
    {
        EQParams eq;
        ClarityParams clarity;
        LoudnessParams loudness;
        BRIRParams brir;
        CrossfeedParams crossfeed; // headphone crossfeed: the output stage ahead of the limiter
        LimiterParams limiter;
        float intensityLinear = 1.0F;
        uint64_t sequenceNumber = 0;
    };

    // Verify trivially copyable + standard layout at compile time.
    static_assert(std::is_trivially_copyable_v<TargetState>,
                  "TargetState must be trivially copyable");
    static_assert(std::is_standard_layout_v<TargetState>, "TargetState must have standard layout");

    // Lock the layout (QW1 §3 F2) — N is the MEASURED size, NOT an assumption. History: 320 B
    // through QW1 (CrossfeedParams fit the alignas(64) slack); 640 B since Sprint EQ's EQ1b, whose
    // finished (k, m1) EQParams (512 B) replaced the 10-biquad float cascade (engine-plan §7
    // estimated ~520 B for EQParams; measured with the compiler's record layout); 768 B since the
    // EQ engine's fix round, whose per-band glide times (amendment 15: 31 floats + the gain's) grew
    // EQParams to 640 B. The size itself is golden-master-NEUTRAL (the hash is over audio output):
    // EQ1b re-baselined the golden master because the EQ's audio changed; the fix round left it
    // untouched. If a FUTURE change trips this assert: re-MEASURE N, then re-confirm the
    // golden-master hash (CF-1) still holds — never silently bump N.
    constexpr size_t kMeasuredTargetStateBytes = 768;
    static_assert(
        sizeof(TargetState) == kMeasuredTargetStateBytes,
        "TargetState size changed — re-measure N and re-confirm the golden master (CF-1)");

} // namespace AdaptiveSound
