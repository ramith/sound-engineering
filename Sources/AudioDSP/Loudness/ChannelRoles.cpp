// ChannelRoles.cpp — the one channel-role resolver (asResolveChannelRoles) and the BS.1770-5 weights of a set
// of roles. See ChannelRoles.h.
//
// Sources:
//   [1] Apple CoreAudioBaseTypes.h — the channel labels (kAudioChannelLabel_*) and layout tags.
//   [2] Apple AudioToolbox AudioFormat.h — kAudioFormatProperty_ChannelLayoutForTag / ForBitmap, Apple's
//       own expansion of a tag or a bitmap into one labelled description per channel.
//   [3] RFC 9639 (FLAC) §8.6.2 — the channel order a file without a layout carries (WAV order).
//   [4] ITU-R BS.1770-5 (11/2023) Annex 1 Table 3; Annex 3 Tables 4 and 5 — the channel weights.

#include "ChannelRoles.h"
#include "../include/TrackPlanBridge.h"
#include "ChannelLayoutDecoder.h"
#include <algorithm>
#include <array>
#include <AudioToolbox/AudioFormat.h>
#include <cstddef>
#include <cstdint>
#include <span>

namespace AdaptiveSound
{
    namespace
    {
        using Role = ChannelRole;

        // [3]: the count fallbacks, WAV order, one row per count 1 … 8.
        constexpr std::array<Role, 1U> kFallback1 = {Role::Mono};
        constexpr std::array<Role, 2U> kFallback2 = {Role::L, Role::R};
        constexpr std::array<Role, 3U> kFallback3 = {Role::L, Role::R, Role::C};
        constexpr std::array<Role, 4U> kFallback4 = {Role::L, Role::R, Role::Lb, Role::Rb};
        constexpr std::array<Role, 5U> kFallback5 = {Role::L, Role::R, Role::C, Role::Lb, Role::Rb};
        constexpr std::array<Role, 6U> kFallback6 = {
            Role::L,
            Role::R,
            Role::C,
            Role::Lfe,
            Role::Lb,
            Role::Rb,
        };
        constexpr std::array<Role, 7U> kFallback7 = {
            Role::L,
            Role::R,
            Role::C,
            Role::Lfe,
            Role::Cs,
            Role::Ls,
            Role::Rs,
        };
        constexpr std::array<Role, 8U> kFallback8 = {
            Role::L,
            Role::R,
            Role::C,
            Role::Lfe,
            Role::Lb,
            Role::Rb,
            Role::Ls,
            Role::Rs,
        };
        constexpr std::array<std::span<const Role>, kMaxChannels> kFallbacks = {
            kFallback1,
            kFallback2,
            kFallback3,
            kFallback4,
            kFallback5,
            kFallback6,
            kFallback7,
            kFallback8,
        };

        // Room for Apple's expansion of any tag or bitmap we accept: its descriptions, one per channel, for
        // up to kMaxDescriptions channels (a wider expansion cannot describe a stream we play anyway).
        constexpr size_t kMaxDescriptions = 64U;
        constexpr size_t kExpandedLayoutBytes =
            offsetof(AudioChannelLayout, mChannelDescriptions) +
            (kMaxDescriptions * sizeof(AudioChannelDescription));

        // A layout's labels, one per channel, when it describes exactly `channels` channels.
        using Labels = std::array<AudioChannelLabel, kMaxChannels>;

        [[nodiscard]] bool labelsOfDescriptions(const AudioChannelLayout& layout,
                                                uint32_t channels,
                                                Labels& labels) noexcept
        {
            if (layout.mNumberChannelDescriptions != channels)
            {
                return false;
            }
            // mChannelDescriptions is a variable-length array of mNumberChannelDescriptions entries.
            const AudioChannelDescription* descriptions = &layout.mChannelDescriptions[0];
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                labels[ch] = descriptions[ch].mChannelLabel;
            }
            return true;
        }

        // Apple's expansion of a tag or a bitmap ([2]) into per-channel descriptions.
        [[nodiscard]] bool labelsOfExpansion(AudioFormatPropertyID property,
                                             const void* specifier,
                                             UInt32 specifierSize,
                                             uint32_t channels,
                                             Labels& labels) noexcept
        {
            UInt32 size = 0U;
            if (AudioFormatGetPropertyInfo(property, specifierSize, specifier, &size) != noErr ||
                size < sizeof(AudioChannelLayout) || size > kExpandedLayoutBytes)
            {
                return false;
            }
            alignas(AudioChannelLayout) std::array<std::byte, kExpandedLayoutBytes> storage{};
            if (AudioFormatGetProperty(property, specifierSize, specifier, &size, storage.data()) !=
                noErr)
            {
                return false;
            }
            // The expansion keeps the tag it was asked about and fills one description per channel.
            const auto* expanded = reinterpret_cast<const AudioChannelLayout*>(storage.data());
            return labelsOfDescriptions(*expanded, channels, labels);
        }

        [[nodiscard]] bool
        labelsOf(const AudioChannelLayout& layout, uint32_t channels, Labels& labels) noexcept
        {
            const AudioChannelLayoutTag tag = layout.mChannelLayoutTag;
            if (tag == kAudioChannelLayoutTag_UseChannelDescriptions)
            {
                return labelsOfDescriptions(layout, channels, labels);
            }
            if (tag == kAudioChannelLayoutTag_UseChannelBitmap)
            {
                const AudioChannelBitmap bitmap = layout.mChannelBitmap;
                return labelsOfExpansion(kAudioFormatProperty_ChannelLayoutForBitmap,
                                         &bitmap,
                                         static_cast<UInt32>(sizeof(bitmap)),
                                         channels,
                                         labels);
            }
            // A tag carries its channel count in its low 16 bits [1]. DiscreteInOrder and Unknown name no
            // speaker; a tag for another count does not describe this stream.
            constexpr AudioChannelLayoutTag kCountMask = 0x0000FFFFU;
            const AudioChannelLayoutTag family = tag & ~kCountMask;
            if ((tag & kCountMask) != channels ||
                family == kAudioChannelLayoutTag_DiscreteInOrder ||
                family == kAudioChannelLayoutTag_Unknown)
            {
                return false;
            }
            return labelsOfExpansion(kAudioFormatProperty_ChannelLayoutForTag,
                                     &tag,
                                     static_cast<UInt32>(sizeof(tag)),
                                     channels,
                                     labels);
        }

        [[nodiscard]] bool hasRole(std::span<const Role> roles, Role wanted) noexcept
        {
            return std::ranges::find(roles, wanted) != roles.end();
        }
    } // namespace

    ChannelRole roleForLabel(AudioChannelLabel label) noexcept
    {
        switch (label)
        {
            case kAudioChannelLabel_Left:
            case kAudioChannelLabel_LeftTotal:
            case kAudioChannelLabel_HeadphonesLeft:
            case kAudioChannelLabel_BinauralLeft:
                return Role::L;
            case kAudioChannelLabel_Right:
            case kAudioChannelLabel_RightTotal:
            case kAudioChannelLabel_HeadphonesRight:
            case kAudioChannelLabel_BinauralRight:
                return Role::R;
            case kAudioChannelLabel_Center:
                return Role::C;
            case kAudioChannelLabel_Mono:
                return Role::Mono;
            case kAudioChannelLabel_LFEScreen:
            case kAudioChannelLabel_LFE2:
            case kAudioChannelLabel_LFE3:
                return Role::Lfe;
            case kAudioChannelLabel_LeftSurround:
            case kAudioChannelLabel_LeftSurroundDirect:
            case kAudioChannelLabel_LeftSideSurround:
                return Role::Ls;
            case kAudioChannelLabel_RightSurround:
            case kAudioChannelLabel_RightSurroundDirect:
            case kAudioChannelLabel_RightSideSurround:
                return Role::Rs;
            case kAudioChannelLabel_RearSurroundLeft:
            case kAudioChannelLabel_LeftBackSurround:
                return Role::Lb;
            case kAudioChannelLabel_RearSurroundRight:
            case kAudioChannelLabel_RightBackSurround:
                return Role::Rb;
            case kAudioChannelLabel_CenterSurround:
            case kAudioChannelLabel_CenterSurroundDirect:
                return Role::Cs;
            case kAudioChannelLabel_LeftCenter:
                return Role::Lc;
            case kAudioChannelLabel_RightCenter:
                return Role::Rc;
            case kAudioChannelLabel_LeftWide:
                return Role::Lw;
            case kAudioChannelLabel_RightWide:
                return Role::Rw;
            default:
                return Role::Unknown;
        }
    }

    bool countFallbackRoles(uint32_t channels, std::span<ChannelRole> roles) noexcept
    {
        if (channels == 0U || channels > kMaxChannels || roles.size() < channels)
        {
            return false;
        }
        const std::span<const Role> row = kFallbacks[channels - 1U];
        std::ranges::copy(row, roles.begin());
        return true;
    }

    bool resolveChannelRoles(const AudioChannelLayout* layout,
                             uint32_t channels,
                             std::span<ChannelRole> roles) noexcept
    {
        if (channels == 0U || channels > kMaxChannels || roles.size() < channels)
        {
            return false;
        }
        Labels labels{};
        if (layout != nullptr && labelsOf(*layout, channels, labels))
        {
            std::array<Role, kMaxChannels> named{};
            bool namesASpeaker = false;
            for (uint32_t ch = 0U; ch < channels; ++ch)
            {
                named[ch] = roleForLabel(labels[ch]);
                namesASpeaker = namesASpeaker || named[ch] != Role::Unknown;
            }
            if (namesASpeaker)
            {
                std::copy_n(named.begin(), channels, roles.begin());
                return true;
            }
        }
        return countFallbackRoles(channels, roles);
    }

    std::array<double, kMaxChannels> bs1770Weights(std::span<const ChannelRole> roles) noexcept
    {
        std::array<double, kMaxChannels> weights{};
        const std::span<const Role> used =
            roles.first(std::min<size_t>(roles.size(), kMaxChannels));
        // A back pair is the surround pair of a 4.0 / 5.x layout (M±110: +1.5 dB) unless a side pair sits
        // beside it (7.x: the backs are at M±135, 0 dB) — [4] Annex 3 Table 5.
        const bool sidePair = hasRole(used, Role::Ls) || hasRole(used, Role::Rs);
        const auto surround = static_cast<double>(kBs1770SurroundWeight);
        const auto unity = static_cast<double>(kBs1770WeightLRCf);
        for (size_t ch = 0U; ch < used.size(); ++ch)
        {
            switch (used[ch])
            {
                case Role::Lfe:
                    weights[ch] = static_cast<double>(kBs1770WeightLFEf);
                    break;
                case Role::Ls:
                case Role::Rs:
                case Role::Lw:
                case Role::Rw:
                    weights[ch] = surround;
                    break;
                case Role::Lb:
                case Role::Rb:
                    weights[ch] = sidePair ? unity : surround;
                    break;
                case Role::Unknown:
                case Role::L:
                case Role::R:
                case Role::C:
                case Role::Cs:
                case Role::Lc:
                case Role::Rc:
                case Role::Mono:
                    weights[ch] = unity;
                    break;
            }
        }
        return weights;
    }
} // namespace AdaptiveSound

bool asResolveChannelRoles(const AudioChannelLayout* layout,
                           uint32_t channels,
                           uint8_t* roles) AUDIODSP_C_NOEXCEPT
{
    if (roles == nullptr)
    {
        return false;
    }
    std::array<AdaptiveSound::ChannelRole, AdaptiveSound::kMaxChannels> resolved{};
    if (!AdaptiveSound::resolveChannelRoles(layout, channels, resolved))
    {
        return false;
    }
    for (uint32_t ch = 0U; ch < channels; ++ch)
    {
        roles[ch] = static_cast<uint8_t>(resolved[ch]);
    }
    return true;
}
