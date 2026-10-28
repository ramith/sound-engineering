// TrackAnalyzer.cpp — the one analysis pass. See TrackAnalyzer.h.
//
// Sources:
//   [1] ITU-R BS.1770-5 (11/2023) Annex 1 §2.3 (the gates), Table 3 and Annex 3 (the weights).
//   [2] docs/design/level-and-fold/README.md §1.2 (what is measured), §2 (P1), §3 (the histograms), §5.
//   [3] Loudness/LufsMeter.h — the K-weighting and the histogram's form (0.1 LU bins from −70 LUFS).

#include "TrackAnalyzer.h"
#include "ChannelRoles.h"
#include "LufsMeter.h"
#include <Accelerate/Accelerate.h>
#include <algorithm>
#include <cmath>
#include <limits>
#include <new>

namespace AdaptiveSound
{
    namespace
    {
        // [1]: the gates as block-energy thresholds (as TrackLoudnessProfile.cpp compares them).
        [[nodiscard]] double absoluteGateEnergy() noexcept
        {
            return std::pow(kDecibelBase, (kAbsoluteGateLufs - kLufsOffset) / kDbPowerScale);
        }

        [[nodiscard]] double relativeGateFactor() noexcept
        {
            return std::pow(kDecibelBase, kRelativeGateOffsetLu / kDbPowerScale);
        }

        [[nodiscard]] double energyLufs(double energy) noexcept
        {
            return kLufsOffset + (kDbPowerScale * std::log10(energy));
        }

        [[nodiscard]] double nanValue() noexcept
        {
            return std::numeric_limits<double>::quiet_NaN();
        }

        // A true peak in dBTP, floored where a silent stream would read −∞.
        constexpr double kSilentPeakDbtp = kSilenceLufs;
        [[nodiscard]] double peakDbtp(double linear) noexcept
        {
            return (linear > 0.0)
                       ? std::max(kSilentPeakDbtp, kDbAmplitudeScale * std::log10(linear))
                       : kSilentPeakDbtp;
        }

        // The fold's two channels each weigh 1.0 (L′ and R′ are the stereo programme heard).
        [[nodiscard]] std::array<double, kMaxChannels> stereoWeights() noexcept
        {
            std::array<double, kMaxChannels> weights{};
            weights[0] = kBs1770WeightLRC;
            weights[1] = kBs1770WeightLRC;
            return weights;
        }
        constexpr uint32_t kStereo = 2U;
    } // namespace

    double gatedLoudnessLufs(std::span<const double> blockEnergies) noexcept
    {
        const double absoluteGate = absoluteGateEnergy();
        double absoluteSum = 0.0;
        size_t absoluteCount = 0U;
        for (const double energy : blockEnergies)
        {
            if (energy > absoluteGate)
            {
                absoluteSum += energy;
                ++absoluteCount;
            }
        }
        if (absoluteCount == 0U)
        {
            return nanValue();
        }
        const double relativeGate =
            std::max(absoluteGate,
                     (absoluteSum / static_cast<double>(absoluteCount)) * relativeGateFactor());
        double gatedSum = 0.0;
        size_t gatedCount = 0U;
        for (const double energy : blockEnergies)
        {
            if (energy > relativeGate)
            {
                gatedSum += energy;
                ++gatedCount;
            }
        }
        return (gatedCount == 0U) ? nanValue()
                                  : energyLufs(gatedSum / static_cast<double>(gatedCount));
    }

    double poolHistogramsLufs(std::span<const std::span<const AsLoudnessBin>> members) noexcept
    {
        std::array<uint64_t, kHistBins> counts{};
        std::array<double, kHistBins> energies{};
        uint64_t totalCount = 0U;
        double totalEnergy = 0.0;
        for (const std::span<const AsLoudnessBin> member : members)
        {
            for (const AsLoudnessBin& bin : member)
            {
                if (bin.bin >= static_cast<uint32_t>(kHistBins) || !std::isfinite(bin.energy) ||
                    bin.energy < 0.0)
                {
                    return nanValue();
                }
                counts[bin.bin] += bin.count;
                energies[bin.bin] += bin.energy;
                totalCount += bin.count;
                totalEnergy += bin.energy;
            }
        }
        if (totalCount == 0U || !(totalEnergy > 0.0))
        {
            return nanValue();
        }
        // LufsMeter's recomputeIntegrated: the relative threshold from the absolute-gated mean, applied to
        // each bin's centre.
        const double relativeThreshold =
            energyLufs(totalEnergy / static_cast<double>(totalCount)) + kRelativeGateOffsetLu;
        uint64_t gatedCount = 0U;
        double gatedEnergy = 0.0;
        for (size_t bin = 0U; bin < counts.size(); ++bin)
        {
            const double centre =
                kHistMinLufs + ((static_cast<double>(bin) + kHistBinCenter) * kHistStepLu);
            if (centre >= relativeThreshold)
            {
                gatedCount += counts[bin];
                gatedEnergy += energies[bin];
            }
        }
        return (gatedCount == 0U) ? nanValue()
                                  : energyLufs(gatedEnergy / static_cast<double>(gatedCount));
    }

    // ---- GatedBlockMeter ------------------------------------------------------------------------------

    GatedBlockMeter::GatedBlockMeter(double sampleRate,
                                     uint32_t channels,
                                     const std::array<double, kMaxChannels>& weights)
        : channels_(channels),
          weights_(weights),
          hopFrames_(static_cast<uint32_t>(std::max(1L, std::lround(kHopSeconds * sampleRate))))
    {
        kWeight_.fill(makeKWeighting(sampleRate));
    }

    void GatedBlockMeter::process(std::span<const double* const> channels, size_t frames)
    {
        size_t done = 0U;
        while (done < frames)
        {
            const size_t run = std::min<size_t>(frames - done, hopFrames_ - hopFill_);
            for (uint32_t ch = 0U; ch < channels_; ++ch)
            {
                if (!(weights_[ch] > 0.0))
                {
                    continue; // an unweighted channel (the LFE) never reaches a block
                }
                LufsKWeight& filter = kWeight_[ch];
                const double* samples = channels[ch] + done;
                double sum = 0.0;
                for (size_t frame = 0U; frame < run; ++frame)
                {
                    const double weighted = filter.processSample(samples[frame]);
                    sum += weighted * weighted;
                }
                hopSum_[ch] += sum;
            }
            done += run;
            hopFill_ += static_cast<uint32_t>(run);
            if (hopFill_ < hopFrames_)
            {
                continue;
            }
            // A hop is complete: its weighted energy joins the ring; a block ends with every hop from the
            // fourth on.
            double hopEnergy = 0.0;
            for (uint32_t ch = 0U; ch < channels_; ++ch)
            {
                hopEnergy += weights_[ch] * hopSum_[ch];
                hopSum_[ch] = 0.0;
            }
            hopFill_ = 0U;
            hopEnergy_[hops_ % hopEnergy_.size()] = hopEnergy;
            ++hops_;
            if (hops_ >= hopEnergy_.size())
            {
                double blockSum = 0.0;
                for (const double each : hopEnergy_)
                {
                    blockSum += each;
                }
                blocks_.push_back(
                    blockSum / (static_cast<double>(hopFrames_) * static_cast<double>(kBlockHops)));
            }
        }
    }

    double GatedBlockMeter::blockLufs(size_t index) const noexcept
    {
        if (index >= blocks_.size())
        {
            return nanValue();
        }
        const double energy = blocks_[index];
        return (energy > kTinyEnergy) ? energyLufs(energy) : kSilenceLufs;
    }

    std::vector<AsLoudnessBin> GatedBlockMeter::histogram() const
    {
        std::array<uint32_t, kHistBins> counts{};
        std::array<double, kHistBins> energies{};
        const double absoluteGate = absoluteGateEnergy();
        for (const double energy : blocks_)
        {
            if (!(energy > absoluteGate))
            {
                continue;
            }
            // [3]: LufsMeter's addBlockToHistogram, the index clamped to the last bin.
            const int raw =
                static_cast<int>(std::floor((energyLufs(energy) - kHistMinLufs) / kHistStepLu));
            const auto bin = static_cast<size_t>(std::clamp(raw, 0, kHistBins - 1));
            ++counts[bin];
            energies[bin] += energy;
        }
        std::vector<AsLoudnessBin> bins;
        for (size_t bin = 0U; bin < counts.size(); ++bin)
        {
            if (counts[bin] > 0U)
            {
                bins.push_back(
                    AsLoudnessBin{static_cast<uint32_t>(bin), counts[bin], energies[bin]});
            }
        }
        return bins;
    }

    // ---- TrackAnalyzer --------------------------------------------------------------------------------

    std::unique_ptr<TrackAnalyzer> TrackAnalyzer::create(double engineRateHz,
                                                         std::span<const ChannelRole> roles)
    {
        if (roles.empty() || roles.size() > kMaxChannels ||
            TrackLoudness::bandCount(engineRateHz) == 0U)
        {
            return nullptr;
        }
        auto analyzer =
            std::unique_ptr<TrackAnalyzer>(new (std::nothrow) TrackAnalyzer(engineRateHz, roles));
        if (!analyzer || !analyzer->decodedProfiler_)
        {
            return nullptr;
        }
        for (uint8_t variant = 0U; variant < analyzer->foldVariants_; ++variant)
        {
            if (!analyzer->foldProfiler_[variant])
            {
                return nullptr;
            }
        }
        return analyzer;
    }

    TrackAnalyzer::TrackAnalyzer(double engineRateHz, std::span<const ChannelRole> roles)
        : rate_(engineRateHz),
          channels_(static_cast<uint32_t>(roles.size())),
          folds_(roles.size() > kStereo),
          hasLfe_(std::ranges::find(roles, ChannelRole::Lfe) != roles.end()),
          lfe_(engineRateHz, roles),
          input_(static_cast<size_t>(channels_) * kChunkFrames, 0.0)
    {
        std::ranges::copy(roles, roles_.begin());
        const std::array<double, kMaxChannels> weights = bs1770Weights(roles);
        decodedMeter_ = std::make_unique<GatedBlockMeter>(rate_, channels_, weights);
        decodedPeak_ = std::make_unique<AnalysisTruePeak::Detector>(channels_);
        TrackLoudnessProfiler::Format compact;
        compact.sampleRate = rate_;
        compact.channelCount = channels_;
        compact.channelWeights = weights;
        decodedProfiler_ = TrackLoudnessProfiler::create(compact, kCompactMaxBlocks);
        if (!folds_)
        {
            return;
        }
        foldVariants_ = hasLfe_ ? static_cast<uint8_t>(AS_FOLD_LFE_VARIANTS) : uint8_t{1U};
        TrackLoudnessProfiler::Format stereo = compact;
        stereo.channelCount = kStereo;
        stereo.channelWeights = stereoWeights();
        for (uint8_t variant = 0U; variant < foldVariants_; ++variant)
        {
            foldMatrix_[variant] = makeBs775Fold(roles, variant).value_or(FoldMatrix{});
            foldMeter_[variant] =
                std::make_unique<GatedBlockMeter>(rate_, kStereo, stereoWeights());
            foldPeak_[variant] = std::make_unique<AnalysisTruePeak::Detector>(kStereo);
            foldProfiler_[variant] = TrackLoudnessProfiler::create(stereo, kCompactMaxBlocks);
        }
        foldDouble_.assign(static_cast<size_t>(foldVariants_) * kStereo * kChunkFrames, 0.0);
        foldFloat_.assign(foldDouble_.size(), 0.0F);
    }

    bool TrackAnalyzer::feed(std::span<const float* const> channels, size_t frames)
    {
        if (finished_ || channels.size() != channels_)
        {
            return false;
        }
        // Validate the whole chunk before touching any state: a rejected chunk consumes nothing.
        const bool valid = std::ranges::all_of(
            channels,
            [frames](const float* samples)
            {
                return samples != nullptr &&
                       std::all_of(samples,
                                   samples + frames,
                                   [](float value) { return std::isfinite(value); });
            });
        if (!valid)
        {
            return false;
        }
        for (size_t done = 0U; done < frames; done += kChunkFrames)
        {
            processChunk(channels, done, std::min(kChunkFrames, frames - done));
        }
        frames_ += frames;
        return true;
    }

    void TrackAnalyzer::processChunk(std::span<const float* const> channels,
                                     size_t offset,
                                     size_t frames)
    {
        std::array<const double*, kMaxChannels> inputs{};
        std::array<const float*, kMaxChannels> floats{};
        for (uint32_t ch = 0U; ch < channels_; ++ch)
        {
            double* converted = input_.data() + (static_cast<size_t>(ch) * kChunkFrames);
            vDSP_vspdp(channels[ch] + offset, 1, converted, 1, static_cast<vDSP_Length>(frames));
            inputs[ch] = converted;
            floats[ch] = channels[ch] + offset;
        }
        const std::span<const double* const> decoded(inputs.data(), channels_);
        decodedMeter_->process(decoded, frames);
        decodedPeak_->process(decoded, frames);
        (void)decodedProfiler_->feed(std::span<const float* const>(floats.data(), channels_),
                                     frames);
        lfe_.process(decoded, frames);
        for (uint8_t variant = 0U; variant < foldVariants_; ++variant)
        {
            // L′ = Σ g_L[ch]·x_ch and R′ likewise, in double, through the one fold table.
            std::array<const double*, kStereo> sides{};
            std::array<const float*, kStereo> sideFloats{};
            for (uint32_t side = 0U; side < kStereo; ++side)
            {
                const size_t slot = (static_cast<size_t>(variant) * kStereo) + side;
                double* out = foldDouble_.data() + (slot * kChunkFrames);
                std::fill_n(out, frames, 0.0);
                for (uint32_t ch = 0U; ch < channels_; ++ch)
                {
                    const auto gain = static_cast<double>(foldMatrix_[variant].gain[side][ch]);
                    if (gain != 0.0)
                    {
                        vDSP_vsmaD(
                            inputs[ch], 1, &gain, out, 1, out, 1, static_cast<vDSP_Length>(frames));
                    }
                }
                float* outFloat = foldFloat_.data() + (slot * kChunkFrames);
                vDSP_vdpsp(out, 1, outFloat, 1, static_cast<vDSP_Length>(frames));
                sides[side] = out;
                sideFloats[side] = outFloat;
            }
            foldMeter_[variant]->process(sides, frames);
            foldPeak_[variant]->process(sides, frames);
            (void)foldProfiler_[variant]->feed(sideFloats, frames);
        }
    }

    bool TrackAnalyzer::finish(AsTrackAnalysis& out)
    {
        if (finished_)
        {
            return false;
        }
        finished_ = true;
        decodedPeak_->flush();
        AsTrackAnalysis result{};
        result.version = AS_TRACK_ANALYSIS_VERSION;
        result.channelCount = channels_;
        for (uint32_t ch = 0U; ch < channels_; ++ch)
        {
            result.roles[ch] = static_cast<uint8_t>(roles_[ch]);
        }
        result.sourceRateHz =
            nanValue(); // the analyzer sees only the engine-rate stream: the caller's
        result.peakRateHz = rate_;
        result.durationSeconds = static_cast<double>(frames_) / rate_;
        result.integratedLufs = decodedMeter_->integratedLufs();
        result.truePeakDbtp = (frames_ > 0U) ? peakDbtp(decodedPeak_->peakLinear()) : nanValue();
        result.headBlockLufs = decodedMeter_->blockLufs(0U);
        result.tailBlockLufs = (decodedMeter_->blockCount() > 0U)
                                   ? decodedMeter_->blockLufs(decodedMeter_->blockCount() - 1U)
                                   : nanValue();
        result.folds = folds_ ? 1U : 0U;
        histograms_[0] = decodedMeter_->histogram();
        profiles_[0] = decodedProfiler_->finish();
        for (uint8_t variant = 0U; variant < foldVariants_; ++variant)
        {
            foldPeak_[variant]->flush();
        }
        for (uint8_t variant = 0U; variant < AS_FOLD_LFE_VARIANTS; ++variant)
        {
            if (!folds_)
            {
                result.foldedLufs[variant] = nanValue();
                result.foldedTruePeakDbtp[variant] = nanValue();
                continue;
            }
            const uint8_t measured = measuredVariant(variant);
            result.foldedLufs[variant] = foldMeter_[measured]->integratedLufs();
            result.foldedTruePeakDbtp[variant] =
                (frames_ > 0U) ? peakDbtp(foldPeak_[measured]->peakLinear()) : nanValue();
            if (measured == variant)
            {
                histograms_[1U + variant] = foldMeter_[variant]->histogram();
                profiles_[1U + variant] = foldProfiler_[variant]->finish();
            }
            else
            {
                histograms_[1U + variant] = histograms_[1U + measured];
                profiles_[1U + variant] = profiles_[1U + measured];
            }
        }
        result.lfe = lfe_.finish();
        out = result;
        return true;
    }

    std::span<const AsLoudnessBin> TrackAnalyzer::histogram(uint8_t basis) const noexcept
    {
        if (!finished_ || basis >= kBases)
        {
            return {};
        }
        return histograms_[basis];
    }

    const TrackLoudnessProfile* TrackAnalyzer::profile(uint8_t basis) const noexcept
    {
        if (!finished_ || basis >= kBases)
        {
            return nullptr;
        }
        return profiles_[basis].get();
    }
} // namespace AdaptiveSound
