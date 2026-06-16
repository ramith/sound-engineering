// ChannelLayoutDecoder.mm
// OFF-RT decoder: CoreAudio AudioChannelLayoutTag → ChannelLayout.
//
// Control-thread only.  Allocation-free, noexcept, pure.
//
// Sources:
//   [1] ITU-R BS.1770-5 (2023), Annex 1, Table 1  — per-channel loudness weights
//   [2] ITU-R BS.775-4  (2022), §3                — nominal speaker azimuths
//   [3] Apple CoreAudioBaseTypes.h (macOS SDK)    — tag enum + per-tag channel-order
//       comments, verified 2026:
//         kAudioChannelLayoutTag_MPEG_5_1_A = (121U<<16)|6  // L R C LFE Ls Rs
//         kAudioChannelLayoutTag_MPEG_5_1_B = (122U<<16)|6  // L R Ls Rs C LFE
//         kAudioChannelLayoutTag_MPEG_7_1_A = (126U<<16)|8  // L R C LFE Ls Rs Lc Rc
//         kAudioChannelLayoutTag_MPEG_7_1_C = (128U<<16)|8  // L R C LFE Ls Rs Rls Rrs

#include "ChannelLayoutDecoder.h"
#include <cstdint>

namespace AdaptiveSound
{

// ---------------------------------------------------------------------------
// Named weight constants — BS.1770-5 Annex 1 Table 1 [1]
// ---------------------------------------------------------------------------

// L / R / C weight: G = 1.0 (0 dB).
inline constexpr float kBs1770WeightLRCf = 1.0F;

// LFE weight: G = 0.0 — excluded from the loudness measurement entirely.
inline constexpr float kBs1770WeightLFEf = 0.0F;

// Surround weight: G = 10^(1.5/10) ≈ 1.41253754 (+1.5 dB in power).
// Applied to Ls, Rs, side surrounds, and back surrounds.
// Source: ITU-R BS.1770-5, Annex 1, Table 1.
inline constexpr float kBs1770SurroundWeight = 1.41253754F;

// ---------------------------------------------------------------------------
// Named azimuth constants — BS.775-4 nominal positions [2]
//
// Sign convention: + = left of centre / counter-clockwise (CCW) from above.
//   +30° = front left (L),    −30°  = front right (R)
//   +110° = left surround (Ls), −110° = right surround (Rs)
//   +135° = rear-left back (Rls), −135° = rear-right back (Rrs)
//   +60°  = front-wide left (Lc),  −60°  = front-wide right (Rc)
//   0°   = centre front (C)
//   All ear-level layouts → elevation = 0°.
// ---------------------------------------------------------------------------

inline constexpr float kAzimCentre = 0.0F;          // C
inline constexpr float kAzimFrontL = 30.0F;         // L  (+ = left/CCW)
inline constexpr float kAzimFrontR = -30.0F;        // R
inline constexpr float kAzimSurrL = 110.0F;         // Ls
inline constexpr float kAzimSurrR = -110.0F;        // Rs
inline constexpr float kAzimBackL = 135.0F;         // Rls (rear-left surround)
inline constexpr float kAzimBackR = -135.0F;        // Rrs (rear-right surround)
inline constexpr float kAzimFrontCentreL = 60.0F;   // Lc (front-wide left)
inline constexpr float kAzimFrontCentreR = -60.0F;  // Rc (front-wide right)
inline constexpr float kElevEarLevel = 0.0F;        // all ear-level layouts

// ---------------------------------------------------------------------------
// Named slot-index constants — document which slot holds which channel for
// each format variant.  These are the authoritative mapping constants; using
// them in the array accesses below keeps the numeric literals out of the
// body and makes the "ordering trap" explicit at the constant-definition site.
// ---------------------------------------------------------------------------

// Stereo (2-channel)
inline constexpr uint32_t kNumChStereo = 2U;
inline constexpr uint32_t kStereoSlotL = 0U;
inline constexpr uint32_t kStereoSlotR = 1U;

// MPEG 5.1 A: L R C LFE Ls Rs  (also AudioUnit_5_1, DVD_12, WAVE_5_1_A)
inline constexpr uint32_t kNumCh51 = 6U;
inline constexpr uint32_t k51ASlotL   = 0U;
inline constexpr uint32_t k51ASlotR   = 1U;
inline constexpr uint32_t k51ASlotC   = 2U;
inline constexpr uint32_t k51ASlotLfe = 3U; // <-- LFE at index 3 in variant A
inline constexpr uint32_t k51ASlotLs  = 4U;
inline constexpr uint32_t k51ASlotRs  = 5U;

// MPEG 5.1 B: L R Ls Rs C LFE  (also DVD_20, Logic_5_1_B)
inline constexpr uint32_t k51BSlotL   = 0U;
inline constexpr uint32_t k51BSlotR   = 1U;
inline constexpr uint32_t k51BSlotLs  = 2U; // <-- surround at index 2 in variant B
inline constexpr uint32_t k51BSlotRs  = 3U; // <-- surround at index 3 in variant B
inline constexpr uint32_t k51BSlotC   = 4U;
inline constexpr uint32_t k51BSlotLfe = 5U; // <-- LFE at index 5 in variant B

// MPEG 7.1 A: L R C LFE Ls Rs Lc Rc  (also AudioUnit_7_1_Front)
inline constexpr uint32_t kNumCh71 = 8U;
inline constexpr uint32_t k71ASlotL   = 0U;
inline constexpr uint32_t k71ASlotR   = 1U;
inline constexpr uint32_t k71ASlotC   = 2U;
inline constexpr uint32_t k71ASlotLfe = 3U;
inline constexpr uint32_t k71ASlotLs  = 4U;
inline constexpr uint32_t k71ASlotRs  = 5U;
inline constexpr uint32_t k71ASlotLc  = 6U; // front-wide left
inline constexpr uint32_t k71ASlotRc  = 7U; // front-wide right

// MPEG 7.1 C: L R C LFE Ls Rs Rls Rrs  (also AudioUnit_7_1, ITU_3_4_1)
inline constexpr uint32_t k71CSlotL   = 0U;
inline constexpr uint32_t k71CSlotR   = 1U;
inline constexpr uint32_t k71CSlotC   = 2U;
inline constexpr uint32_t k71CSlotLfe = 3U;
inline constexpr uint32_t k71CSlotLs  = 4U;
inline constexpr uint32_t k71CSlotRs  = 5U;
inline constexpr uint32_t k71CSlotRls = 6U; // rear-left surround
inline constexpr uint32_t k71CSlotRrs = 7U; // rear-right surround

// ---------------------------------------------------------------------------
// Helper — write a single slot (avoids repetition in the body below)
// ---------------------------------------------------------------------------
static void writeSlot(ChannelLayout& lay,
                      uint32_t slot,
                      float weight,
                      float azimuth,
                      uint8_t lfe) noexcept
{
    lay.lufsWeight[slot] = weight;
    lay.brirAzimuthDeg[slot] = azimuth;
    lay.brirElevationDeg[slot] = kElevEarLevel;
    lay.isLfe[slot] = lfe;
}

// ---------------------------------------------------------------------------
// Helper — build the safe neutral fallback for unknown tags
// ---------------------------------------------------------------------------
// CoreAudio convention: lower 16 bits of the tag encode the channel count.
static auto neutralFallback(AudioChannelLayoutTag tag) noexcept -> ChannelLayout
{
    const uint32_t chCount = static_cast<uint32_t>(tag & 0x0000FFFFU);
    const uint32_t numCh = (chCount >= 1U && chCount <= kMaxChannels) ? chCount : 2U;

    ChannelLayout lay{};
    lay.numChannels = numCh;
    for (uint32_t ch = 0U; ch < numCh; ++ch)
    {
        writeSlot(lay, ch, kBs1770WeightLRCf, kAzimCentre, 0U);
    }
    return lay;
}

// ---------------------------------------------------------------------------
// decodeChannelLayout
// ---------------------------------------------------------------------------
auto decodeChannelLayout(AudioChannelLayoutTag tag) noexcept -> ChannelLayout
{
    // -----------------------------------------------------------------------
    // Stereo — slot 0: L (+30°), slot 1: R (−30°)
    // Source: CoreAudioBaseTypes.h; angles per BS.775-4.
    // -----------------------------------------------------------------------
    if (tag == kAudioChannelLayoutTag_Stereo)
    {
        ChannelLayout lay{};
        lay.numChannels = kNumChStereo;
        writeSlot(lay, kStereoSlotL, kBs1770WeightLRCf, kAzimFrontL, 0U);
        writeSlot(lay, kStereoSlotR, kBs1770WeightLRCf, kAzimFrontR, 0U);
        return lay;
    }

    // -----------------------------------------------------------------------
    // MPEG 5.1 A — slot order: L R C LFE Ls Rs    (THE ORDERING TRAP)
    // SDK comment: kAudioChannelLayoutTag_MPEG_5_1_A  L R C LFE Ls Rs
    // Also aliased as: kAudioChannelLayoutTag_AudioUnit_5_1, DVD_12, WAVE_5_1_A
    // LFE lives at index 3 in this variant.
    // -----------------------------------------------------------------------
    if (tag == kAudioChannelLayoutTag_MPEG_5_1_A)
    {
        ChannelLayout lay{};
        lay.numChannels = kNumCh51;
        writeSlot(lay, k51ASlotL,   kBs1770WeightLRCf,     kAzimFrontL,  0U);
        writeSlot(lay, k51ASlotR,   kBs1770WeightLRCf,     kAzimFrontR,  0U);
        writeSlot(lay, k51ASlotC,   kBs1770WeightLRCf,     kAzimCentre,  0U);
        writeSlot(lay, k51ASlotLfe, kBs1770WeightLFEf,     kAzimCentre,  1U); // LFE at slot 3
        writeSlot(lay, k51ASlotLs,  kBs1770SurroundWeight, kAzimSurrL,   0U);
        writeSlot(lay, k51ASlotRs,  kBs1770SurroundWeight, kAzimSurrR,   0U);
        return lay;
    }

    // -----------------------------------------------------------------------
    // MPEG 5.1 B — slot order: L R Ls Rs C LFE    (THE ORDERING TRAP)
    // SDK comment: kAudioChannelLayoutTag_MPEG_5_1_B  L R Ls Rs C LFE
    // Also aliased as: kAudioChannelLayoutTag_DVD_20, Logic_5_1_B
    // LFE lives at index 5 in this variant — DIFFERENT from variant A.
    // Surround channels land at indices 2 and 3 — DIFFERENT from variant A.
    // -----------------------------------------------------------------------
    if (tag == kAudioChannelLayoutTag_MPEG_5_1_B)
    {
        ChannelLayout lay{};
        lay.numChannels = kNumCh51;
        writeSlot(lay, k51BSlotL,   kBs1770WeightLRCf,     kAzimFrontL,  0U);
        writeSlot(lay, k51BSlotR,   kBs1770WeightLRCf,     kAzimFrontR,  0U);
        writeSlot(lay, k51BSlotLs,  kBs1770SurroundWeight, kAzimSurrL,   0U); // surround at slot 2
        writeSlot(lay, k51BSlotRs,  kBs1770SurroundWeight, kAzimSurrR,   0U); // surround at slot 3
        writeSlot(lay, k51BSlotC,   kBs1770WeightLRCf,     kAzimCentre,  0U);
        writeSlot(lay, k51BSlotLfe, kBs1770WeightLFEf,     kAzimCentre,  1U); // LFE at slot 5
        return lay;
    }

    // -----------------------------------------------------------------------
    // MPEG 7.1 A — slot order: L R C LFE Ls Rs Lc Rc
    // SDK: kAudioChannelLayoutTag_MPEG_7_1_A
    // Also aliased as: kAudioChannelLayoutTag_AudioUnit_7_1_Front
    // Lc/Rc are front-wide speakers; BS.775-4 places them at ±60°.
    // -----------------------------------------------------------------------
    if (tag == kAudioChannelLayoutTag_MPEG_7_1_A)
    {
        ChannelLayout lay{};
        lay.numChannels = kNumCh71;
        writeSlot(lay, k71ASlotL,   kBs1770WeightLRCf,     kAzimFrontL,        0U);
        writeSlot(lay, k71ASlotR,   kBs1770WeightLRCf,     kAzimFrontR,        0U);
        writeSlot(lay, k71ASlotC,   kBs1770WeightLRCf,     kAzimCentre,        0U);
        writeSlot(lay, k71ASlotLfe, kBs1770WeightLFEf,     kAzimCentre,        1U);
        writeSlot(lay, k71ASlotLs,  kBs1770SurroundWeight, kAzimSurrL,         0U);
        writeSlot(lay, k71ASlotRs,  kBs1770SurroundWeight, kAzimSurrR,         0U);
        writeSlot(lay, k71ASlotLc,  kBs1770WeightLRCf,     kAzimFrontCentreL,  0U); // Lc ≈ +60°
        writeSlot(lay, k71ASlotRc,  kBs1770WeightLRCf,     kAzimFrontCentreR,  0U); // Rc ≈ −60°
        return lay;
    }

    // -----------------------------------------------------------------------
    // MPEG 7.1 C — slot order: L R C LFE Ls Rs Rls Rrs
    // SDK: kAudioChannelLayoutTag_MPEG_7_1_C
    // Also aliased as: kAudioChannelLayoutTag_AudioUnit_7_1, ITU_3_4_1
    // Rls/Rrs are rear back surrounds; BS.775-4 places them at ±135°.
    // -----------------------------------------------------------------------
    if (tag == kAudioChannelLayoutTag_MPEG_7_1_C)
    {
        ChannelLayout lay{};
        lay.numChannels = kNumCh71;
        writeSlot(lay, k71CSlotL,   kBs1770WeightLRCf,     kAzimFrontL,  0U);
        writeSlot(lay, k71CSlotR,   kBs1770WeightLRCf,     kAzimFrontR,  0U);
        writeSlot(lay, k71CSlotC,   kBs1770WeightLRCf,     kAzimCentre,  0U);
        writeSlot(lay, k71CSlotLfe, kBs1770WeightLFEf,     kAzimCentre,  1U);
        writeSlot(lay, k71CSlotLs,  kBs1770SurroundWeight, kAzimSurrL,   0U);
        writeSlot(lay, k71CSlotRs,  kBs1770SurroundWeight, kAzimSurrR,   0U);
        writeSlot(lay, k71CSlotRls, kBs1770SurroundWeight, kAzimBackL,   0U); // Rls ≈ +135°
        writeSlot(lay, k71CSlotRrs, kBs1770SurroundWeight, kAzimBackR,   0U); // Rrs ≈ −135°
        return lay;
    }

    // -----------------------------------------------------------------------
    // Unknown / custom tag: safe neutral fallback.
    // numChannels is derived from the tag's embedded channel count;
    // all slots get weight 1.0, isLfe=0, azimuth/elevation 0.
    // Documented as the correct safe default for unrecognised formats.
    // -----------------------------------------------------------------------
    return neutralFallback(tag);
}

} // namespace AdaptiveSound
