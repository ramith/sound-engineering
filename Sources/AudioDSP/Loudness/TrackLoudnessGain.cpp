// TrackLoudnessGain.cpp — the level stage's gain. See TrackLoudnessGain.h.

#include "TrackLoudnessGain.h"
#include "../EQ/GraphicEQBands.h"
#include "../include/AudioConstants.h"
#include "../Planning/TrackPlan.h"
#include <algorithm>
#include <cmath>
#include <numeric>
#include <utility>
#include <vector>

namespace AdaptiveSound
{
    namespace
    {
        // −ΔL stays inside ±12 dB for every ±12 dB curve; the clamp only guards the impossible.
        constexpr auto kMaxGainDb = static_cast<double>(kEQMaxGainDb);
        constexpr double kDbAmplitudeScale = 20.0;
        // B's frequency grid: 1/24 octave from 10 Hz (below the EQ's lowest band, for its skirt) to just
        // under Nyquist.
        constexpr double kBoundLowestHz = 10.0;
        constexpr double kBoundStepsPerOctave = 24.0;
        constexpr double kBoundNyquistFraction = 0.999;
        // ‖h‖₁ is taken over this much of the impulse response: it only matters for curves whose B is
        // under the 0.7 dB allowance (cuts and near-flat curves), and their bells decay within it.
        constexpr double kImpulseSeconds = 0.5;
        constexpr double kHalf = 0.5;

        [[nodiscard]] bool isIdentity(const GraphicEQDesign& design) noexcept
        {
            return std::ranges::all_of(
                design.bells, [](const GraphicEQ::SvfBell& bell) { return bell.m1 == 0.0; });
        }

        [[nodiscard]] double analysedSeconds(const TrackLoudnessProfile& profile) noexcept
        {
            return (profile.sampleRate > 0.0)
                       ? static_cast<double>(profile.analysedFrames) / profile.sampleRate
                       : 0.0;
        }
    } // namespace

    TrackLoudnessGain::TrackLoudnessGain(double outputRate)
        : plan_(planTrack(nullptr, nullptr, nullptr))
    {
        setOutputRate(outputRate);
    }

    void TrackLoudnessGain::setOutputRate(double outputRate)
    {
        outputRate_ = outputRate;
        prior_ = makePinkPriorProfile(outputRate);
    }

    double TrackLoudnessGain::playedBoundDb(const GraphicEQDesign& design) noexcept
    {
        if (isIdentity(design) || !(design.sampleRate > 0.0))
        {
            return 0.0;
        }
        const double top = kHalf * design.sampleRate * kBoundNyquistFraction;
        double bound = 0.0;
        for (double step = 0.0;; step += 1.0)
        {
            const double frequency = kBoundLowestHz * std::exp2(step / kBoundStepsPerOctave);
            if (frequency >= top)
            {
                break;
            }
            bound = std::max(bound, GraphicEQDesigner::playedDb(design, frequency));
        }
        return bound;
    }

    double TrackLoudnessGain::impulseL1Db(const GraphicEQDesign& design) noexcept
    {
        if (isIdentity(design) || !(design.sampleRate > 0.0))
        {
            return 0.0;
        }
        // The cascade's impulse response, band by band (Simper's SVF bell, as EQModule runs it).
        std::vector<double> response(
            static_cast<size_t>(std::llround(kImpulseSeconds * design.sampleRate)), 0.0);
        response.front() = 1.0;
        for (size_t band = 0U; band < design.bells.size(); ++band)
        {
            const GraphicEQ::SvfBell& bell = design.bells[band];
            if (bell.m1 == 0.0)
            {
                continue;
            }
            const GraphicEQ::SvfDamping tick = GraphicEQ::svfDamping(design.svfG[band], bell.k);
            double ic1 = 0.0;
            double ic2 = 0.0;
            for (double& sample : response)
            {
                const double v0 = sample;
                const double v3 = v0 - ic2;
                const double v1 = (tick.a1 * ic1) + (tick.a2 * v3);
                const double v2 = ic2 + (tick.a2 * ic1) + (tick.a3 * v3);
                ic1 = (2.0 * v1) - ic1;
                ic2 = (2.0 * v2) - ic2;
                sample = v0 + (bell.m1 * v1);
            }
        }
        const double norm =
            std::accumulate(response.begin(),
                            response.end(),
                            0.0,
                            [](double sum, double sample) { return sum + std::abs(sample); });
        return (norm > 0.0) ? kDbAmplitudeScale * std::log10(norm) : 0.0;
    }

    size_t TrackLoudnessGain::indexOf(uint64_t token) const noexcept
    {
        if (token == 0U)
        {
            return tracks_.size();
        }
        return static_cast<size_t>(std::ranges::find_if(tracks_,
                                                        [token](const TrackEntry& entry)
                                                        { return entry.token == token; }) -
                                   tracks_.begin());
    }

    TrackLoudnessGain::TrackEntry* TrackLoudnessGain::find(uint64_t token) noexcept
    {
        const size_t index = indexOf(token);
        return (index < tracks_.size()) ? &tracks_[index] : nullptr;
    }

    const TrackLoudnessGain::TrackEntry* TrackLoudnessGain::find(uint64_t token) const noexcept
    {
        const size_t index = indexOf(token);
        return (index < tracks_.size()) ? &tracks_[index] : nullptr;
    }

    TrackLoudnessGain::TrackEntry& TrackLoudnessGain::slotFor(uint64_t token) noexcept
    {
        TrackEntry* entry = find(token);
        if (entry == nullptr)
        {
            // The least recently used slot that is not the current track's.
            TrackEntry* victim = nullptr;
            for (TrackEntry& candidate : tracks_)
            {
                if (candidate.token == current_ && current_ != 0U)
                {
                    continue;
                }
                if (victim == nullptr || candidate.lastUse < victim->lastUse)
                {
                    victim = &candidate;
                }
            }
            *victim = TrackEntry{};
            victim->token = token;
            entry = victim;
        }
        entry->lastUse = ++useClock_;
        return *entry;
    }

    const TrackLoudnessProfile* TrackLoudnessGain::sourceProfile() const noexcept
    {
        if (const TrackEntry* current = find(current_); current != nullptr && current->profile)
        {
            return current->profile.get();
        }
        if (causalActive_ && causal_ && analysedSeconds(*causal_) >= kCausalWarmupSeconds)
        {
            return causal_.get();
        }
        return prior_.get();
    }

    double TrackLoudnessGain::ownNeutralDb(uint32_t blockStep) const noexcept
    {
        if (!audible_)
        {
            return 0.0; // the EQ is Off or flat: it changes nothing, exactly
        }
        double changeDb = 0.0;
        const TrackLoudnessProfile* source = sourceProfile();
        const bool predicted =
            (source != nullptr) && predictLoudnessChangeDb(*source, design_, blockStep, changeDb);
        // A source with nothing above the gates (a silent prefix) says nothing: use the prior.
        if (!predicted &&
            (prior_ == nullptr || !predictLoudnessChangeDb(*prior_, design_, 1U, changeDb)))
        {
            return 0.0;
        }
        return std::clamp(-changeDb, -kMaxGainDb, kMaxGainDb);
    }

    uint32_t TrackLoudnessGain::editBlockStep() const noexcept
    {
        const TrackLoudnessProfile* source = sourceProfile();
        const uint32_t blocks = (source != nullptr) ? source->blockCount : 0U;
        return std::max(1U, (blocks + kEditBlockBudget - 1U) / kEditBlockBudget);
    }

    double TrackLoudnessGain::peakBoundDb() const noexcept
    {
        return audible_ ? std::max(boundDb_, allowanceDb_) : 0.0;
    }

    double TrackLoudnessGain::capDb() const noexcept
    {
        return plan_.workingCeilingDbtp - (plan_.peakDbtp + plan_.levelGainDb + peakBoundDb());
    }

    double TrackLoudnessGain::neutralFor(double own) const noexcept
    {
        if (!audible_ && plan_.levelGainDb == 0.0)
        {
            return 0.0; // the stage adds nothing: the source plays as recorded (P0)
        }
        return std::min(own, capDb());
    }

    double TrackLoudnessGain::publishedFor(double neutral, double own) const noexcept
    {
        return plan_.levelGainDb + (comparing_ ? neutral - own : neutral);
    }

    std::optional<TrackLoudnessGain::Change>
    TrackLoudnessGain::moveTo(double neutral, double own, float tau)
    {
        neutralDb_ = neutral;
        const double target = publishedFor(neutral, own);
        if (std::abs(target - gainDb_) < kMinChangeDb)
        {
            return std::nullopt;
        }
        gainDb_ = target;
        return Change{.gainDb = target, .rampSeconds = tau};
    }

    double TrackLoudnessGain::onDesign(const GraphicEQDesign& design, bool isOn, bool comparing)
    {
        design_ = design;
        audible_ = isOn && !isIdentity(design);
        comparing_ = comparing && audible_;
        boundDb_ = audible_ ? playedBoundDb(design) : 0.0;
        // The cut allowance is re-measured on the idle refresh; meanwhile the last one stands (in full,
        // 0.7 dB, before the first measurement).
        allowanceMeasured_ = false;
        groupLocked_ = false;
        seamPending_ = false;
        const uint32_t step = editBlockStep();
        const double own = ownNeutralDb(step);
        neutralDb_ = neutralFor(own);
        gainDb_ = publishedFor(neutralDb_, own);
        refreshNeeded_ = audible_ && (step > 1U || boundDb_ < kCutAllowanceDb);
        return gainDb_;
    }

    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::onRefresh()
    {
        if (!refreshNeeded_)
        {
            return std::nullopt;
        }
        refreshNeeded_ = false;
        if (audible_ && boundDb_ < kCutAllowanceDb && !allowanceMeasured_)
        {
            allowanceDb_ = std::min(impulseL1Db(design_), kCutAllowanceDb);
            allowanceMeasured_ = true;
        }
        if (groupLocked_)
        {
            return std::nullopt;
        }
        const double own = ownNeutralDb(1U);
        return moveTo(neutralFor(own), own, kRefreshRampSeconds);
    }

    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::onProfile(
        uint64_t token, std::shared_ptr<const TrackLoudnessProfile> profile, bool saved)
    {
        if (token == 0U || !profile)
        {
            return std::nullopt;
        }
        TrackEntry& entry = slotFor(token);
        if (entry.saved && !saved)
        {
            return std::nullopt; // the saved profile is final: G never moves inside the track (C2)
        }
        if (!saved && entry.profile && entry.profile->wholeTrack && !profile->wholeTrack)
        {
            return std::nullopt; // a late prefix never replaces the whole track
        }
        const bool first = !entry.profile;
        entry.profile = std::move(profile);
        entry.saved = saved;
        entry.failed = false;
        if (token != current_)
        {
            return std::nullopt; // the next track's: kept for its audibility
        }
        causalActive_ = false; // the track's own profile beats any running estimate
        causal_.reset();
        if (seamPending_)
        {
            return resolveSeam(kArrivalRampSeconds);
        }
        if (groupLocked_)
        {
            return std::nullopt;
        }
        const double own = ownNeutralDb(1U);
        return moveTo(neutralFor(own), own, first ? kArrivalRampSeconds : kRefineRampSeconds);
    }

    void TrackLoudnessGain::onFailure(uint64_t token)
    {
        if (token == 0U)
        {
            return;
        }
        TrackEntry& entry = slotFor(token);
        entry.failed = true;
        if (token == current_ && !entry.profile)
        {
            causalActive_ = true; // the prior holds through the estimate's warm-up
            causal_.reset();
        }
    }

    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::onPlan(uint64_t token,
                                                                       AsPlanEvent event,
                                                                       const AsTrackPlan& planned,
                                                                       bool continuousWithPrevious)
    {
        if (event == AsPlanEventModeChange || event == AsPlanEventOutputChange)
        {
            if (token != current_)
            {
                return std::nullopt; // for a track that is no longer audible
            }
            plan_ = planned;
            const double own = ownNeutralDb(1U);
            if (event == AsPlanEventModeChange)
            {
                // The listener's act: the level moves anyway, so a shared group gain is released.
                groupLocked_ = false;
                seamPending_ = false;
                return moveTo(neutralFor(own), own, kModeChangeRampSeconds);
            }
            // The protective re-plan (F5): never above the new cap, a shared group gain included.
            const double neutral =
                (groupLocked_ || seamPending_) ? std::min(neutralDb_, capDb()) : neutralFor(own);
            return moveTo(neutral, own, kOutputChangeRampSeconds);
        }

        // A new play: a new token, or the same one again at a real seam (Repeat One — architect N3).
        current_ = token;
        plan_ = planned;
        const TrackEntry* entry = (token != 0U) ? &slotFor(token) : nullptr;
        causalActive_ = (entry != nullptr) && entry->failed && !entry->profile;
        causal_.reset();
        groupLocked_ = false;
        seamPending_ = false;
        const double own = ownNeutralDb(1U);
        if (event != AsPlanEventGaplessSeam)
        {
            return moveTo(neutralFor(own), own, kFreshStartRampSeconds); // a fresh start snaps (N4)
        }
        if (!continuousWithPrevious)
        {
            return moveTo(neutralFor(own), own, kTrackChangeRampSeconds); // across silence: its own
        }
        if (entry != nullptr && entry->profile)
        {
            return resolveSeam(kTrackChangeRampSeconds);
        }
        // A continuous seam before the new track's profile: the neutral gain holds (under the new cap)
        // until it says more.
        seamPending_ = true;
        return moveTo(std::min(neutralDb_, capDb()), own, kTrackChangeRampSeconds);
    }

    // THE GAPLESS-GROUP RULE (amendments item 3; B3): at a CONTINUOUS seam — the continuity judge's
    // verdict — the neutral gain may step by ≤ 0.2 dB; if the next track's own is further away, the group
    // shares the gain that is playing (no step at all), never above the new track's cap.
    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::resolveSeam(float tau)
    {
        seamPending_ = false;
        const double own = ownNeutralDb(1U);
        const double target = neutralFor(own);
        if (std::abs(target - neutralDb_) > kSeamStepDb)
        {
            groupLocked_ = true;
            return moveTo(std::min(neutralDb_, capDb()), own, tau);
        }
        return moveTo(target, own, tau);
    }

    double TrackLoudnessGain::causalSeconds() const noexcept
    {
        return (causalActive_ && causal_) ? analysedSeconds(*causal_) : 0.0;
    }

    std::optional<TrackLoudnessGain::Change>
    TrackLoudnessGain::onCausalSnapshot(std::shared_ptr<const TrackLoudnessProfile> profile)
    {
        if (!causalActive_ || !profile)
        {
            return std::nullopt;
        }
        causal_ = std::move(profile);
        if (analysedSeconds(*causal_) < kCausalWarmupSeconds || groupLocked_)
        {
            return std::nullopt;
        }
        seamPending_ = false;
        const double own = ownNeutralDb(1U);
        const double step = std::clamp(
            neutralFor(own) - neutralDb_, -kCausalSlewDbPerSnapshot, kCausalSlewDbPerSnapshot);
        return moveTo(neutralDb_ + step, own, kCausalRampSeconds);
    }
} // namespace AdaptiveSound
