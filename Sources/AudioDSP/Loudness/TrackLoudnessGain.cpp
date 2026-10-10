// TrackLoudnessGain.cpp — the loudness-neutral EQ output gain. See TrackLoudnessGain.h.

#include "TrackLoudnessGain.h"
#include "../include/AudioConstants.h"
#include <algorithm>
#include <cmath>
#include <utility>

namespace AdaptiveSound
{
    namespace
    {
        // −ΔL stays inside ±12 dB for every ±12 dB curve; the clamp only guards the impossible.
        constexpr auto kMaxGainDb = static_cast<double>(kEQMaxGainDb);

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
    {
        setOutputRate(outputRate);
    }

    void TrackLoudnessGain::setOutputRate(double outputRate)
    {
        outputRate_ = outputRate;
        prior_ = makePinkPriorProfile(outputRate);
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

    double TrackLoudnessGain::ownGainDb(uint32_t blockStep) const noexcept
    {
        if (!audible_ || isIdentity(design_))
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

    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::moveTo(double target, float tau)
    {
        if (std::abs(target - gainDb_) < kMinChangeDb)
        {
            return std::nullopt;
        }
        gainDb_ = target;
        return Change{.gainDb = target, .rampSeconds = tau};
    }

    double TrackLoudnessGain::onDesign(const GraphicEQDesign& design, bool audible)
    {
        design_ = design;
        audible_ = audible;
        groupLocked_ = false;
        seamPending_ = false;
        const uint32_t step = editBlockStep();
        gainDb_ = ownGainDb(step);
        refreshNeeded_ = audible_ && step > 1U;
        return gainDb_;
    }

    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::onRefresh()
    {
        if (!refreshNeeded_)
        {
            return std::nullopt;
        }
        refreshNeeded_ = false;
        if (groupLocked_)
        {
            return std::nullopt;
        }
        return moveTo(ownGainDb(1U), kRefreshRampSeconds);
    }

    std::optional<TrackLoudnessGain::Change>
    TrackLoudnessGain::onProfile(uint64_t token,
                                 std::shared_ptr<const TrackLoudnessProfile> profile)
    {
        if (token == 0U || !profile)
        {
            return std::nullopt;
        }
        TrackEntry& entry = slotFor(token);
        if (entry.profile && entry.profile->wholeTrack && !profile->wholeTrack)
        {
            return std::nullopt; // a late prefix never replaces the whole track
        }
        const bool first = !entry.profile;
        entry.profile = std::move(profile);
        entry.failed = false;
        if (token != current_)
        {
            return std::nullopt; // the next track's: kept for its seam
        }
        causalActive_ = false; // the track's own profile beats any running estimate
        causal_.reset();
        if (seamPending_)
        {
            return resolveSeam(false);
        }
        if (groupLocked_)
        {
            return std::nullopt;
        }
        return moveTo(ownGainDb(1U), first ? kArrivalRampSeconds : kRefineRampSeconds);
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

    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::onCurrentTrack(uint64_t token,
                                                                               bool gaplessSeam)
    {
        if (token == current_)
        {
            return std::nullopt; // the same file again (a re-establish): nothing changes
        }
        // The previous track's last block, if its whole profile says it.
        seamTail_.reset();
        if (const TrackEntry* previous = find(current_);
            previous != nullptr && previous->profile && previous->profile->wholeTrack)
        {
            seamTail_ = blockLoudnessLufs(*previous->profile, previous->profile->blockCount - 1U);
        }
        current_ = token;
        const TrackEntry* entry = (token != 0U) ? &slotFor(token) : nullptr;
        causalActive_ = (entry != nullptr) && entry->failed && !entry->profile;
        causal_.reset();
        groupLocked_ = false;
        seamPending_ = false;
        refreshNeeded_ = false;
        if (!gaplessSeam)
        {
            return moveTo(ownGainDb(1U), kTrackChangeRampSeconds);
        }
        if (entry != nullptr && entry->profile)
        {
            return resolveSeam(true);
        }
        seamPending_ = true; // the gain holds until the new track's profile says more
        return std::nullopt;
    }

    std::optional<TrackLoudnessGain::Change> TrackLoudnessGain::resolveSeam(bool atSeam)
    {
        seamPending_ = false;
        const double own = ownGainDb(1U);
        const TrackLoudnessProfile* source = sourceProfile();
        const bool headSounds = (source == nullptr) || source == prior_.get() ||
                                blockLoudnessLufs(*source, 0U) > kSeamSilenceLufs;
        const bool tailSounds = !seamTail_.has_value() || *seamTail_ > kSeamSilenceLufs;
        if (headSounds && tailSounds && std::abs(own - gainDb_) > kSeamStepDb)
        {
            groupLocked_ = true; // a continuous seam: the group keeps one gain
            return std::nullopt;
        }
        return moveTo(own, atSeam ? kTrackChangeRampSeconds : kArrivalRampSeconds);
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
        const double target = ownGainDb(1U);
        const double step =
            std::clamp(target - gainDb_, -kCausalSlewDbPerSnapshot, kCausalSlewDbPerSnapshot);
        return moveTo(gainDb_ + step, kCausalRampSeconds);
    }
} // namespace AdaptiveSound
