#pragma once

// TrackLoudnessGain — the level stage's gain, track by track: the leveling gain and the
// loudness-neutral EQ gain under the peak cap (Sprint EQ, EQ1c part 2; decision 26; R1.1-B, the
// level-and-fold design §1.3, §6 and §7).
//
// The EQ module plays the curve and then ONE broadband gain, `eq.outputGainDb` = g + G:
//   g  the LEVELING gain (levelDb_) — the planner's (Planning/TrackPlan), frozen at audibility. It
//      changes only with a plan: a track becoming audible, the listener's mode change, a protective
//      re-plan at an output change.
//   G  the NEUTRAL gain (neutralDb_) — −ΔL, how much quieter the curve must play to keep the track's
//      loudness, but never above the cap that keeps the level stage's peak under the working ceiling:
//        C_cap = C_work − (P + g + B_eff),   G = min(−ΔL, C_cap)
//      B_eff = max(B, min(20·log10‖h‖₁, 0.7 dB)): B the curve's highest played response (≥ 0), ‖h‖₁ the
//      cascade's ℓ1 norm — the cut allowance (§6). Both are fixture-dependent bounds, NOT strict ones: the
//      verify pass measured TP_H − TP up to +2.5 dB on boost curves and +1.9 dB on cut-only curves over
//      driven masters, so with the EQ on the limiter can still act on hot masters (a known issue until
//      S14-lite's measured TP_H). With the EQ Off and no leveling gain nothing is applied (P0 holds).
//   Compare plays the curve's IDENTITY at g + T, T = G + ΔL ≤ 0: the comparison is level-matched (§7).
//
// This class decides g + G, and how fast it moves, from the events that change it. It is plain state
// on the Realizer's queue: no threads, no dispatch, no kernel.
//
// WHERE ΔL COMES FROM, best first:
//   1. a SAVED profile (C2): the persisted compact profile, delivered with the request that makes the
//      track audible — so G is right at once and NEVER moves inside the track (challenger #2);
//   2. on a never-analysed first play, the analyzer's prefix (~25 s), then its whole track;
//   3. while neither has landed: the pink prior (makePinkPriorProfile, ≤ ~3.4 dB off);
//   4. when the track's analysis FAILED: the causal running estimate of the audio heard so far
//      (CausalLoudnessTap), after a 3 s warm-up on the prior, slewing at ≤ 1 dB/s.
//
// HOW FAST IT MOVES (the gain rides the EQ module's smoother; each change carries its τ):
//   a fresh start          1 ms, the EQ module's shortest glide: a snap (N4) — inside the 5 ms the GR
//                          acceptance excludes after a start (§6)
//   a gapless seam         10 ms
//   a mode change          150 ms, both units alike (§1.3; NI-4)
//   an output change       10 ms (the protective re-plan, F5)
//   an EQ edit             with the coefficients, at the τ rule's gain τ, from a decimated block set;
//                          refreshed in full (ΔL and ‖h‖₁) after ~150 ms idle (A6)
//   a profile landing      500 ms (the prior → the track's own; first play only)
//   prefix → whole track   2 s (the refine; first play only)
//   the causal estimate    ≤ 1 dB per second of audio, at 1 s
//
// GAPLESS SEAMS (amendments item 3; B3). Continuity has ONE judge: the app's (LevelingKit), from the
// persisted head and tail; its verdict travels with the decision (`continuousWithPrevious`). At a
// continuous seam the neutral gain may step by at most 0.2 dB: if the next track's own differs by more,
// the group SHARES the playing one — never above the new cap. Across silence each track keeps its own.
// A group shares g by construction (its numbers are the group's).

#include "../EQ/GraphicEQDesigner.h"
#include "../include/TrackPlanBridge.h"
#include "../Planning/TrackPlan.h"
#include "TrackLoudnessProfile.h"
#include <array>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <optional>

namespace AdaptiveSound
{
    class TrackLoudnessGain
    {
      public:
        // A gain to publish (g + G, or g + T while comparing), and the one-pole τ to glide there.
        struct Change
        {
            double gainDb = 0.0;
            float rampSeconds = 0.0F;
        };

        static constexpr float kFreshStartRampSeconds = 0.001F;
        // The plan events' glides: the spatial unit's own (planGlideSeconds), so both units move alike.
        static constexpr float kTrackChangeRampSeconds = planGlideSeconds(AsPlanEventGaplessSeam);
        static constexpr float kModeChangeRampSeconds = planGlideSeconds(AsPlanEventModeChange);
        static constexpr float kOutputChangeRampSeconds = planGlideSeconds(AsPlanEventOutputChange);
        static constexpr float kArrivalRampSeconds = 0.5F;
        static constexpr float kRefineRampSeconds = 2.0F;
        static constexpr float kRefreshRampSeconds = 0.15F;
        static constexpr float kCausalRampSeconds = 1.0F;
        static constexpr double kCausalSlewDbPerSnapshot = 1.0; // one snapshot per second
        static constexpr double kCausalWarmupSeconds = 3.0;
        static constexpr double kSeamStepDb = 0.2;
        // B_eff's cap on the ℓ1 term (§6): a cut-only curve is allowed this much over its own peak.
        static constexpr double kCutAllowanceDb = 0.7;
        // An edit's prediction uses at most this many blocks (every n-th); the refresh uses all.
        static constexpr uint32_t kEditBlockBudget = 300U;
        // Gains closer than this to the playing one are not worth a publish.
        static constexpr double kMinChangeDb = 0.005;
        // The tracks remembered at once: the current one, the next, and one spare.
        static constexpr size_t kTrackSlots = 4U;

        // `outputRate`: the rate the EQ plays at (the prior's band grid).
        explicit TrackLoudnessGain(double outputRate);

        // A new output rate (a re-allocation): the prior follows. The caller re-designs the EQ
        // (onDesign) afterwards.
        void setOutputRate(double outputRate);

        // The EQ changed to `design` — the CURVE's design whenever the EQ is on, even while Compare
        // plays its identity (Compare is level-matched against it). Returns the gain to publish WITH
        // the coefficients (a decimated estimate for a long profile — see needsRefresh). Releases a
        // shared gapless-group gain: an edit changes the level anyway.
        [[nodiscard]] double
        onDesign(const GraphicEQDesign& design, bool isOn, bool comparing = false);
        // The last onDesign's estimate was decimated, or its cut allowance not yet measured: a full
        // refresh is worth scheduling.
        [[nodiscard]] bool needsRefresh() const noexcept
        {
            return refreshNeeded_;
        }
        // The idle refresh after edits: the full-resolution ΔL and the cascade's ‖h‖₁, if the gain moved.
        [[nodiscard]] std::optional<Change> onRefresh();

        // A profile for `token`. `saved`: the persisted compact profile (C2), delivered just before the plan
        // of the play it is for — final for that play: nothing the analyzer sends later replaces it. A later
        // play of the track that brings none (another basis, N2) takes the analyzer's again. Otherwise the
        // analyzer's prefix or whole track; a whole profile is never replaced by a prefix.
        [[nodiscard]] std::optional<Change>
        onProfile(uint64_t token,
                  std::shared_ptr<const TrackLoudnessProfile> profile,
                  bool saved = false);
        // `token`'s analysis failed and produced no profile: it falls back to the causal estimate.
        void onFailure(uint64_t token);
        // The planner's plan for `token` (B1): it became audible (a fresh start or a gapless seam — the
        // same token at a seam is a new play, Repeat One), or the listener changed the mode, or the
        // output changed (the protective re-plan). `continuousWithPrevious`: the continuity judge's
        // verdict for a seam.
        [[nodiscard]] std::optional<Change> onPlan(uint64_t token,
                                                   AsPlanEvent event,
                                                   const AsTrackPlan& planned,
                                                   bool continuousWithPrevious);
        // The causal estimate's profile of the audio heard so far (one per second of audio).
        [[nodiscard]] std::optional<Change>
        onCausalSnapshot(std::shared_ptr<const TrackLoudnessProfile> profile);

        // The current track's analysis failed: the causal estimate should run.
        [[nodiscard]] bool wantsCausalEstimate() const noexcept
        {
            return causalActive_;
        }
        // The gain last returned (published): g + G, or g + T while comparing.
        [[nodiscard]] double gainDb() const noexcept
        {
            return gainDb_;
        }
        // g: the plan's leveling gain.
        [[nodiscard]] double levelDb() const noexcept
        {
            return plan_.levelGainDb;
        }
        // G: the neutral gain last published (under the cap).
        [[nodiscard]] double neutralDb() const noexcept
        {
            return neutralDb_;
        }
        // C_cap for the current design and plan.
        [[nodiscard]] double capDb() const noexcept;
        // B_eff for the current design (0 with the EQ Off or flat).
        [[nodiscard]] double peakBoundDb() const noexcept;
        // The plan in force.
        [[nodiscard]] const AsTrackPlan& plan() const noexcept
        {
            return plan_;
        }
        // Diagnostics: a continuous gapless seam made this track share the group's neutral gain.
        [[nodiscard]] bool sharesGroupGain() const noexcept
        {
            return groupLocked_;
        }
        // Diagnostics: the audio the running estimate covers so far (s; 0 without one).
        [[nodiscard]] double causalSeconds() const noexcept;

        // B: the highest played response (dB, ≥ 0) of `design` over its band (1/24 octave from 20 Hz to
        // Nyquist). 0 for an identity design.
        [[nodiscard]] static double playedBoundDb(const GraphicEQDesign& design) noexcept;
        // 20·log10‖h‖₁ of `design`'s cascade (its impulse response over 0.5 s); 0 for an identity design.
        [[nodiscard]] static double impulseL1Db(const GraphicEQDesign& design) noexcept;

      private:
        struct TrackEntry
        {
            uint64_t token = 0U;
            std::shared_ptr<const TrackLoudnessProfile> profile;
            bool saved = false; // the persisted profile: final for the play it came with (C2)
            bool savedForPlay = false; // it came after the last plan: it is the next play's
            bool failed = false;
            uint64_t lastUse = 0U;
        };

        // The slot holding `token`, or tracks_.size() (also for token 0).
        [[nodiscard]] size_t indexOf(uint64_t token) const noexcept;
        [[nodiscard]] TrackEntry* find(uint64_t token) noexcept;
        [[nodiscard]] const TrackEntry* find(uint64_t token) const noexcept;
        [[nodiscard]] TrackEntry& slotFor(uint64_t token) noexcept;
        // The profile ΔL is taken from for the current track (its own, the causal estimate once
        // warm, else the prior); nullptr only without a prior.
        [[nodiscard]] const TrackLoudnessProfile* sourceProfile() const noexcept;
        // −ΔL of the current track under the current curve, every `blockStep`-th block (0 when the EQ
        // is off or flat).
        [[nodiscard]] double ownNeutralDb(uint32_t blockStep) const noexcept;
        [[nodiscard]] uint32_t editBlockStep() const noexcept;
        // G for an own −ΔL of `own`: min(own, C_cap) — exactly 0 when the stage adds nothing (the EQ
        // off or flat and g = 0), so the bit-perfect path holds.
        [[nodiscard]] double neutralFor(double own) const noexcept;
        // What plays for a neutral gain G: g + G, or g + T (T = G − own) while comparing.
        [[nodiscard]] double publishedFor(double neutral, double own) const noexcept;
        // Settle a gapless seam once the new track's profile is known.
        [[nodiscard]] std::optional<Change> resolveSeam(float tau);
        // Move to the neutral gain `neutral` (for an own −ΔL of `own`) at `tau`, or nothing if the
        // published gain would not move.
        [[nodiscard]] std::optional<Change> moveTo(double neutral, double own, float tau);

        double outputRate_ = 0.0;
        std::shared_ptr<const TrackLoudnessProfile> prior_;
        GraphicEQDesign design_{}; // the curve's design (also while comparing)
        bool audible_ = false;     // the EQ is On and not flat
        bool comparing_ = false;   // Compare plays the identity, level-matched
        double boundDb_ = 0.0;     // B of design_
        double allowanceDb_ =
            kCutAllowanceDb; // min(20·log10‖h‖₁, 0.7): the last measured (0.7 before any)
        bool allowanceMeasured_ = false;
        double neutralDb_ = 0.0; // G last published
        double gainDb_ = 0.0;    // the gain last published
        bool refreshNeeded_ = false;

        std::array<TrackEntry, kTrackSlots> tracks_{};
        uint64_t useClock_ = 0U;
        uint64_t current_ = 0U; // 0: no track yet
        AsTrackPlan plan_{};    // the current track's plan (an Off plan before the first)

        bool groupLocked_ = false; // the current track shares the gapless group's neutral gain
        bool seamPending_ = false; // a continuous gapless seam waits for the new track's profile

        bool causalActive_ = false; // the current track failed: the running estimate is in use
        std::shared_ptr<const TrackLoudnessProfile> causal_;
    };
} // namespace AdaptiveSound
