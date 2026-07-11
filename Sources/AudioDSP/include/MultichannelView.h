#pragma once

#include "AudioConstants.h"
#include <array>
#include <AudioToolbox/AudioToolbox.h>
#include <cstdint>

namespace AdaptiveSound
{

    // Non-owning, RT-safe view over a planar (non-interleaved) multichannel audio block.
    //
    // fromABL() is the SINGLE place an AudioBufferList is decoded — the one read of
    // mNumberBuffers, the clamp to kMaxChannels, and the mData casts all live here, so DSP
    // modules receive a MultichannelView and never touch the raw ABL. Trivially copyable and
    // pointer-small — pass BY VALUE. The channel pointers are valid only for the duration of the
    // process() call that produced the view. Rule of zero (C.20): all members are trivial.
    class MultichannelView
    {
      public:
        // Build from the AU's in-place ABL. Clamps the channel count to kMaxChannels.
        [[nodiscard]] static auto fromABL(AudioBufferList* abl, uint32_t frames) noexcept
            -> MultichannelView
        {
            MultichannelView view{};
            if (abl == nullptr)
            {
                return view;
            }
            const uint32_t count =
                abl->mNumberBuffers < kMaxChannels ? abl->mNumberBuffers : kMaxChannels;
            for (uint32_t ch = 0U; ch < count; ++ch)
            {
                // CoreAudio
                // flexible-array idiom: the ABL is allocated with `count` AudioBuffers.
                view.data_[ch] = static_cast<float*>(abl->mBuffers[ch].mData);
            }
            view.channels_ = count;
            view.frames_ = frames;
            return view;
        }

        [[nodiscard]] auto channels() const noexcept -> uint32_t
        {
            return channels_;
        }
        [[nodiscard]] auto frames() const noexcept -> uint32_t
        {
            return frames_;
        }

        // Per-channel sample pointer, or nullptr if `index` is out of range.
        [[nodiscard]] auto channel(uint32_t index) const noexcept -> float*
        {
            return (index < channels_) ? data_[index] : nullptr;
        }

      private:
        std::array<float*, kMaxChannels> data_{};
        uint32_t channels_ = 0U;
        uint32_t frames_ = 0U;
    };

} // namespace AdaptiveSound
