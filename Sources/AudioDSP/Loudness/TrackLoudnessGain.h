#pragma once

// TrackLoudnessGain — the loudness-neutral EQ output gain, track by track (Sprint EQ, EQ1c part 2;
// decision 26, engine-plan §4, amendments items 3 and 4).
//
// The EQ module plays the curve and then a broadband gain of −ΔL, where ΔL is how much louder the
// curve makes the CURRENT track (TrackLoudnessProfile.h). This class decides that gain, and how
// fast it moves, from the events that change it. It is plain state on the Realizer's queue: no
// threads, no dispatch, no kernel — the Realizer feeds it events and publishes what it returns.
//
// WHERE ΔL COMES FROM, best first:
//   1. the track's profile: the analyzer's prefix (~25 s) at once, then the whole track;
//   2. while it has not landed: the pink prior (makePinkPriorProfile, ≤ ~3.4 dB off);
//   3. when the track's analysis FAILED: the causal running estimate of the audio heard so far
//      (CausalLoudnessTap), after a 3 s warm-up on the prior, slewing at ≤ 1 dB/s.
//
// HOW FAST IT MOVES (the gain rides the EQ module's smoother; each change carries its τ):
//   an EQ edit           with the coefficients, at the τ rule's gain τ (the bands' τ weighted
//                        by their change, EQTargets::rampsFor); computed on a decimated block
//                        set, refreshed in full after ~150 ms idle (A6)
//   a new track          10 ms (a fresh start, or a gapless seam that allows it — below)
//   a profile landing    500 ms (the prior → the track's own; "profile late")
//   prefix → whole track 2 s (the refine)
//   the causal estimate  ≤ 1 dB per second of audio, at 1 s
//
// GAPLESS SEAMS (amendments item 3). At a gapless seam the gain may step by at most 0.2 dB where
// the music is continuous: if the next track's own gain differs by more, the gapless group SHARES
// ONE GAIN — the next track keeps the gain that is playing (until the EQ is edited or the track
// changes again). A seam is continuous when the music sounds on both sides of it: the previous
// track's last block and the next one's first block are both above −50 LUFS (an unknown side
// counts as sounding). Across silence a step is inaudible, so each track keeps its own gain —
// otherwise, in an ordinary queue (every queue advance is gapless here), one track's gain would
// stick to every following track.

#include "../EQ/GraphicEQDesigner.h"
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
        // A gain to publish, and the one-pole τ to glide there.
        struct Change
        {
            double gainDb = 0.0;
            float rampSeconds = 0.0F;
        };

        static constexpr float kTrackChangeRampSeconds = 0.010F;
        static constexpr float kArrivalRampSeconds = 0.5F;
        static constexpr float kRefineRampSeconds = 2.0F;
        static constexpr float kRefreshRampSeconds = 0.15F;
        static constexpr float kCausalRampSeconds = 1.0F;
        static constexpr double kCausalSlewDbPerSnapshot = 1.0; // one snapshot per second
        static constexpr double kCausalWarmupSeconds = 3.0;
        static constexpr double kSeamStepDb = 0.2;
        static constexpr double kSeamSilenceLufs = -50.0;
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

        // The EQ changed to `design`; `audible` is false when the EQ is Off. Returns the gain to
        // publish WITH the coefficients (a decimated estimate for a long profile — see
        // needsRefresh). Releases a shared gapless-group gain: an edit changes the level anyway.
        [[nodiscard]] double onDesign(const GraphicEQDesign& design, bool audible);
        // The last onDesign's estimate was decimated: a full refresh is worth scheduling.
        [[nodiscard]] bool needsRefresh() const noexcept
        {
            return refreshNeeded_;
        }
        // The idle refresh after edits: the full-resolution gain, if it moved.
        [[nodiscard]] std::optional<Change> onRefresh();

        // A profile (prefix or whole) for `token`. A whole profile is never replaced by a prefix.
        [[nodiscard]] std::optional<Change>
        onProfile(uint64_t token, std::shared_ptr<const TrackLoudnessProfile> profile);
        // `token`'s analysis failed and produced no profile: it falls back to the causal estimate.
        void onFailure(uint64_t token);
        // `token` became the audible track — at a gapless seam, or by a fresh start.
        [[nodiscard]] std::optional<Change> onCurrentTrack(uint64_t token, bool gaplessSeam);
        // The causal estimate's profile of the audio heard so far (one per second of audio).
        [[nodiscard]] std::optional<Change>
        onCausalSnapshot(std::shared_ptr<const TrackLoudnessProfile> profile);

        // The current track's analysis failed: the causal estimate should run.
        [[nodiscard]] bool wantsCausalEstimate() const noexcept
        {
            return causalActive_;
        }
        // The gain last returned (published).
        [[nodiscard]] double gainDb() const noexcept
        {
            return gainDb_;
        }
        // Diagnostics: a continuous gapless seam made this track share the group's gain.
        [[nodiscard]] bool sharesGroupGain() const noexcept
        {
            return groupLocked_;
        }
        // Diagnostics: the audio the running estimate covers so far (s; 0 without one).
        [[nodiscard]] double causalSeconds() const noexcept;

      private:
        struct TrackEntry
        {
            uint64_t token = 0U;
            std::shared_ptr<const TrackLoudnessProfile> profile;
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
        // The current track's own gain, every `blockStep`-th block.
        [[nodiscard]] double ownGainDb(uint32_t blockStep) const noexcept;
        [[nodiscard]] uint32_t editBlockStep() const noexcept;
        // Settle a gapless seam once the new track's profile is known.
        [[nodiscard]] std::optional<Change> resolveSeam(bool atSeam);
        // A Change to `target` (dB) at `tau`, or nothing if the gain would not move.
        [[nodiscard]] std::optional<Change> moveTo(double target, float tau);

        double outputRate_ = 0.0;
        std::shared_ptr<const TrackLoudnessProfile> prior_;
        GraphicEQDesign design_{};
        bool audible_ = false; // the EQ is On and not flat
        double gainDb_ = 0.0;  // the gain last published
        bool refreshNeeded_ = false;

        std::array<TrackEntry, kTrackSlots> tracks_{};
        uint64_t useClock_ = 0U;
        uint64_t current_ = 0U; // 0: no track yet

        bool groupLocked_ = false;       // the current track shares the gapless group's gain
        bool seamPending_ = false;       // a gapless seam waits for the new track's profile
        std::optional<double> seamTail_; // the previous track's last block (LUFS), if known

        bool causalActive_ = false; // the current track failed: the running estimate is in use
        std::shared_ptr<const TrackLoudnessProfile> causal_;
    };
} // namespace AdaptiveSound
