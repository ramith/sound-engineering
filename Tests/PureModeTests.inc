// PureModeTests.inc
//
// Pure-Mode policy tests (Phase B — B1) and format conversion tests (B2a),
// plus ToneSource and inline file-decode bootstrap tests (B2b).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: PureMode_HdmiBitPerfect, PureMode_HdmiRateUnsupported,
//        PureMode_BluetoothLossy, PureMode_BuiltInRateMatchedFloat,
//        PureMode_BuiltInRateUnsupported, PureMode_VirtualDevice,
//        PureMode_RateEpsilonAndMax, Convert_Int16Saturation,
//        Convert_Int32Saturation, Convert_24In32Alignment,
//        Convert_FloatPassthrough, Convert_UnsupportedWritesSilence,
//        ToneSource_FillsBuffer, PureModeBridge_TranslatesAllDecisionBranches,
//        PureModeBridge_NullArgsAreNoOp, PureModeBridge_RateArrayCopiedFaithfully.
// Helpers (area-local): makeHdmiCapability, makeBluetoothCapability,
//   makeBuiltInCapability, makeVirtualCapability, makeFile, checkEval,
//   readLeInt16, readLeWord32, kBitsXx, kMonoCh, kI16PosFull, kI16NegFull,
//   kI32PosFull, kI32NegFullBits, toFlat (DeviceCapability → CDeviceCapability + rates).

// The flat C-ABI Pure-Mode policy bridge (pureModeEvaluate). TestSupport.h already pulls in
// DeviceCapability.h (the C++ evaluatePureMode); this adds the C struct + function declarations.
// Reachable via the harness -Iinclude flag.
#include "PureModeBridge.h"

// ===========================================================================
// Pure-Mode policy (Phase B — B1). Pure-unit tests of evaluatePureMode(): hand-built
// DeviceCapability fixtures mirror the four real devices measured on the founder's Mac.
// No CoreAudio is touched — the policy is keyed off the semantic booleans + advertised rates.
// ===========================================================================

namespace
{
    // Build the four real-device fixtures (table in the B1 brief). Only the fields the policy
    // reads are load-bearing; the rest are filled for documentary fidelity.

    // HDMI monitor: HDMI transport, 24-bit integer PCM → bit-perfect candidate.
    auto makeHdmiCapability() -> DeviceCapability
    {
        DeviceCapability cap;
        cap.transportType = TestConstants::kTransportHDMI;
        cap.currentRate = TestConstants::kRate48k;
        cap.availableRates = {
            TestConstants::kRate32k, TestConstants::kRate44k, TestConstants::kRate48k};
        cap.physicalFormat = {TestConstants::kRate48k,
                              TestConstants::kBits24,
                              TestConstants::kStereo,
                              /*isFloat=*/false,
                              /*isPCM=*/true};
        cap.virtualFormat = {TestConstants::kRate48k,
                             TestConstants::kBits32,
                             TestConstants::kStereo,
                             /*isFloat=*/true,
                             /*isPCM=*/true};
        cap.integerCapable = true;
        cap.exclusiveCapable = true;
        cap.isLossyWireless = false;
        cap.isVirtualOrAggregate = false;
        return cap;
    }

    // WH-1000XM4: Bluetooth → lossy wireless, codec below the HAL.
    auto makeBluetoothCapability() -> DeviceCapability
    {
        DeviceCapability cap;
        cap.transportType = TestConstants::kTransportBluetooth;
        cap.currentRate = TestConstants::kRate44k;
        cap.availableRates = {TestConstants::kRate16k, TestConstants::kRate44k};
        cap.physicalFormat = {TestConstants::kRate44k,
                              TestConstants::kBits32,
                              TestConstants::kStereo,
                              /*isFloat=*/true,
                              /*isPCM=*/true};
        cap.virtualFormat = cap.physicalFormat;
        cap.integerCapable = false;
        cap.exclusiveCapable = true; // hoggable in principle, but lossy wireless gates it out first
        cap.isLossyWireless = true;
        cap.isVirtualOrAggregate = false;
        return cap;
    }

    // MacBook Pro Speakers: built-in, 32-bit float → float HAL render, no SRC.
    auto makeBuiltInCapability() -> DeviceCapability
    {
        DeviceCapability cap;
        cap.transportType = TestConstants::kTransportBuiltIn;
        cap.currentRate = TestConstants::kRate48k;
        cap.availableRates = {TestConstants::kRate44k,
                              TestConstants::kRate48k,
                              TestConstants::kRate88k,
                              TestConstants::kRate96k};
        cap.physicalFormat = {TestConstants::kRate48k,
                              TestConstants::kBits32,
                              TestConstants::kStereo,
                              /*isFloat=*/true,
                              /*isPCM=*/true};
        cap.virtualFormat = cap.physicalFormat;
        cap.integerCapable = false;
        cap.exclusiveCapable = true;
        cap.isLossyWireless = false;
        cap.isVirtualOrAggregate = false;
        return cap;
    }

    // Teams Audio: virtual device → no real exclusive hardware path.
    auto makeVirtualCapability() -> DeviceCapability
    {
        DeviceCapability cap;
        cap.transportType = TestConstants::kTransportVirtual;
        cap.currentRate = TestConstants::kRate48k;
        cap.availableRates = {TestConstants::kRate48k};
        cap.physicalFormat = {TestConstants::kRate48k,
                              TestConstants::kBits32,
                              TestConstants::kMono,
                              /*isFloat=*/true,
                              /*isPCM=*/true};
        cap.virtualFormat = cap.physicalFormat;
        cap.integerCapable = false;
        cap.exclusiveCapable = false;
        cap.isLossyWireless = false;
        cap.isVirtualOrAggregate = true;
        return cap;
    }

    auto makeFile(double sampleRate) -> FileFormat
    {
        FileFormat file;
        file.sampleRate = sampleRate;
        file.bitsPerChannel = TestConstants::kBits24;
        file.channels = TestConstants::kStereo;
        file.isFloat = false;
        return file;
    }

    // Assert one evaluatePureMode() outcome. Compares decision + reason + the booleans, and the
    // target rate within 1 Hz. Returns "" on success or a human-readable mismatch description.
    auto checkEval(const PureModeEvaluation& eval,
                   PureModeDecision decision,
                   PureModeReason reason,
                   double targetRate,
                   bool requiresRateChange,
                   bool requiresHog) -> std::string
    {
        std::ostringstream oss;
        if (eval.decision != decision)
        {
            oss << "decision: expected " << static_cast<int>(decision) << ", got "
                << static_cast<int>(eval.decision) << "; ";
        }
        if (eval.reason != reason)
        {
            oss << "reason: expected " << pureModeReasonString(reason) << ", got "
                << pureModeReasonString(eval.reason) << "; ";
        }
        if (std::abs(eval.targetDeviceRate - targetRate) > 1.0)
        {
            oss << "targetDeviceRate: expected " << targetRate << ", got " << eval.targetDeviceRate
                << "; ";
        }
        if (eval.requiresRateChange != requiresRateChange)
        {
            oss << "requiresRateChange: expected " << requiresRateChange << ", got "
                << eval.requiresRateChange << "; ";
        }
        if (eval.requiresHog != requiresHog)
        {
            oss << "requiresHog: expected " << requiresHog << ", got " << eval.requiresHog << "; ";
        }
        return oss.str();
    }

    // Marshal a C++ DeviceCapability into the flat C-ABI CDeviceCapability. The flat struct carries
    // NO physicalIsFloat field — the policy .cpp derives physicalFormat.isFloat = (integerCapable ==
    // 0). The advertised rates are returned SEPARATELY (the flat ABI passes them as ptr + count).
    auto toFlat(const DeviceCapability& cap, std::vector<double>& outRates) -> CDeviceCapability
    {
        CDeviceCapability flat{};
        flat.deviceID = cap.id;
        flat.transportType = cap.transportType;
        flat.currentRate = cap.currentRate;
        flat.physicalBitsPerChannel = cap.physicalFormat.bitsPerChannel;
        flat.physicalChannels = cap.physicalFormat.channels;
        flat.integerCapable = cap.integerCapable ? 1U : 0U;
        flat.exclusiveCapable = cap.exclusiveCapable ? 1U : 0U;
        flat.isLossyWireless = cap.isLossyWireless ? 1U : 0U;
        flat.isVirtualOrAggregate = cap.isVirtualOrAggregate ? 1U : 0U;
        outRates = cap.availableRates;
        return flat;
    }

    auto toFlatFile(const FileFormat& file) -> CFileFormat
    {
        CFileFormat flat{};
        flat.sampleRate = file.sampleRate;
        flat.bitsPerChannel = file.bitsPerChannel;
        flat.channels = file.channels;
        flat.isFloat = file.isFloat ? 1U : 0U;
        return flat;
    }
} // namespace

// HDMI (integer-capable) + a supported rate → FullBitPerfect, hog required; rate change iff the
// device's current rate differs from the file rate.
static auto testPureModeHdmiBitPerfect() -> void
{
    static const char* const kName = "PureMode_HdmiBitPerfect";
    const DeviceCapability hdmi = makeHdmiCapability();

    // 44100 file: device is at 48000 → must change rate.
    const std::string err44 = checkEval(evaluatePureMode(hdmi, makeFile(TestConstants::kRate44k)),
                                        PureModeDecision::FullBitPerfect,
                                        PureModeReason::BitPerfectInteger,
                                        TestConstants::kRate44k,
                                        /*requiresRateChange=*/true,
                                        /*requiresHog=*/true);
    if (!err44.empty())
    {
        logFail(kName, "44100 file: " + err44);
        return;
    }

    // 48000 file: device already at 48000 → no rate change.
    const std::string err48 = checkEval(evaluatePureMode(hdmi, makeFile(TestConstants::kRate48k)),
                                        PureModeDecision::FullBitPerfect,
                                        PureModeReason::BitPerfectInteger,
                                        TestConstants::kRate48k,
                                        /*requiresRateChange=*/false,
                                        /*requiresHog=*/true);
    if (!err48.empty())
    {
        logFail(kName, "48000 file: " + err48);
        return;
    }
    logPass(kName);
}

// HDMI + 96000 file (unsupported; max advertised 48000, none >= 96000) → FallbackEnhanced,
// RateUnsupportedResample, target hint = maxRate() = 48000.
static auto testPureModeHdmiRateUnsupported() -> void
{
    static const char* const kName = "PureMode_HdmiRateUnsupported";
    const DeviceCapability hdmi = makeHdmiCapability();

    const std::string err = checkEval(evaluatePureMode(hdmi, makeFile(TestConstants::kRate96k)),
                                      PureModeDecision::FallbackEnhanced,
                                      PureModeReason::RateUnsupportedResample,
                                      TestConstants::kRate48k,
                                      /*requiresRateChange=*/false,
                                      /*requiresHog=*/false);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// Bluetooth (lossy wireless) + any file → FallbackEnhanced, LossyWirelessCodec, no hog, target 0.
// Even at a rate the device advertises (44100), lossy-wireless gates out before rate support.
static auto testPureModeBluetoothLossy() -> void
{
    static const char* const kName = "PureMode_BluetoothLossy";
    const DeviceCapability bt = makeBluetoothCapability();

    const std::string err44 = checkEval(evaluatePureMode(bt, makeFile(TestConstants::kRate44k)),
                                        PureModeDecision::FallbackEnhanced,
                                        PureModeReason::LossyWirelessCodec,
                                        /*targetRate=*/0.0,
                                        /*requiresRateChange=*/false,
                                        /*requiresHog=*/false);
    if (!err44.empty())
    {
        logFail(kName, "44100 file: " + err44);
        return;
    }

    const std::string err96 = checkEval(evaluatePureMode(bt, makeFile(TestConstants::kRate96k)),
                                        PureModeDecision::FallbackEnhanced,
                                        PureModeReason::LossyWirelessCodec,
                                        /*targetRate=*/0.0,
                                        /*requiresRateChange=*/false,
                                        /*requiresHog=*/false);
    if (!err96.empty())
    {
        logFail(kName, "96000 file: " + err96);
        return;
    }
    logPass(kName);
}

// Built-in (float, not integer-capable) + supported rates → RateMatchedFloat, hog required.
static auto testPureModeBuiltInRateMatchedFloat() -> void
{
    static const char* const kName = "PureMode_BuiltInRateMatchedFloat";
    const DeviceCapability builtIn = makeBuiltInCapability();

    // 44100 file: device at 48000 → rate change.
    const std::string err44 =
        checkEval(evaluatePureMode(builtIn, makeFile(TestConstants::kRate44k)),
                  PureModeDecision::RateMatchedFloat,
                  PureModeReason::RateMatchedFloatNoSRC,
                  TestConstants::kRate44k,
                  /*requiresRateChange=*/true,
                  /*requiresHog=*/true);
    if (!err44.empty())
    {
        logFail(kName, "44100 file: " + err44);
        return;
    }

    // 96000 file: supported, device at 48000 → rate change.
    const std::string err96 =
        checkEval(evaluatePureMode(builtIn, makeFile(TestConstants::kRate96k)),
                  PureModeDecision::RateMatchedFloat,
                  PureModeReason::RateMatchedFloatNoSRC,
                  TestConstants::kRate96k,
                  /*requiresRateChange=*/true,
                  /*requiresHog=*/true);
    if (!err96.empty())
    {
        logFail(kName, "96000 file: " + err96);
        return;
    }
    logPass(kName);
}

// Built-in + 192000 file (unsupported; max advertised 96000, none >= 192000) → FallbackEnhanced,
// RateUnsupportedResample, target hint = maxRate() = 96000.
static auto testPureModeBuiltInRateUnsupported() -> void
{
    static const char* const kName = "PureMode_BuiltInRateUnsupported";
    const DeviceCapability builtIn = makeBuiltInCapability();

    const std::string err = checkEval(evaluatePureMode(builtIn, makeFile(TestConstants::kRate192k)),
                                      PureModeDecision::FallbackEnhanced,
                                      PureModeReason::RateUnsupportedResample,
                                      TestConstants::kRate96k,
                                      /*requiresRateChange=*/false,
                                      /*requiresHog=*/false);
    if (!err.empty())
    {
        logFail(kName, err);
        return;
    }
    logPass(kName);
}

// Virtual (Teams) + any file → FallbackEnhanced, VirtualDevice, no hog, target 0. Virtual is
// checked before lossy-wireless and rate support, so even its one supported rate (48000) still
// falls back.
static auto testPureModeVirtualDevice() -> void
{
    static const char* const kName = "PureMode_VirtualDevice";
    const DeviceCapability virt = makeVirtualCapability();

    const std::string err48 = checkEval(evaluatePureMode(virt, makeFile(TestConstants::kRate48k)),
                                        PureModeDecision::FallbackEnhanced,
                                        PureModeReason::VirtualDevice,
                                        /*targetRate=*/0.0,
                                        /*requiresRateChange=*/false,
                                        /*requiresHog=*/false);
    if (!err48.empty())
    {
        logFail(kName, "48000 file: " + err48);
        return;
    }

    const std::string err44 = checkEval(evaluatePureMode(virt, makeFile(TestConstants::kRate44k)),
                                        PureModeDecision::FallbackEnhanced,
                                        PureModeReason::VirtualDevice,
                                        /*targetRate=*/0.0,
                                        /*requiresRateChange=*/false,
                                        /*requiresHog=*/false);
    if (!err44.empty())
    {
        logFail(kName, "44100 file: " + err44);
        return;
    }
    logPass(kName);
}

// supportsRate() epsilon + maxRate(): a rate within 1.0 Hz of an advertised rate counts as
// supported; an off-grid rate does not; maxRate() returns the largest advertised rate.
static auto testPureModeRateEpsilonAndMax() -> void
{
    static const char* const kName = "PureMode_RateEpsilonAndMax";
    const DeviceCapability hdmi = makeHdmiCapability();

    if (!hdmi.supportsRate(TestConstants::kRateEpsilonProbe))
    {
        logFail(kName, "44099.5 Hz should count as 44100 supported (1.0 Hz epsilon)");
        return;
    }
    if (hdmi.supportsRate(TestConstants::kRate96k))
    {
        logFail(kName, "96000 Hz should NOT be supported by the HDMI fixture");
        return;
    }
    if (std::abs(hdmi.maxRate() - TestConstants::kRate48k) > 1.0)
    {
        std::ostringstream oss;
        oss << "maxRate() expected 48000, got " << hdmi.maxRate();
        logFail(kName, oss.str());
        return;
    }

    DeviceCapability empty;
    if (empty.maxRate() != 0.0)
    {
        logFail(kName, "maxRate() of an empty rate list should be 0");
        return;
    }

    // An epsilon-near file rate must still resolve to FullBitPerfect (treated as the exact rate).
    const std::string err =
        checkEval(evaluatePureMode(hdmi, makeFile(TestConstants::kRateEpsilonProbe)),
                  PureModeDecision::FullBitPerfect,
                  PureModeReason::BitPerfectInteger,
                  TestConstants::kRateEpsilonProbe,
                  /*requiresRateChange=*/true,
                  /*requiresHog=*/true);
    if (!err.empty())
    {
        logFail(kName, "44099.5 file: " + err);
        return;
    }
    logPass(kName);
}

// ===========================================================================
// Pure-Mode format conversion (Phase B — B2a). Pure-unit tests of convertFloatToNative():
// hand-built float inputs are converted to each native PCM layout and the raw bytes inspected.
// All little-endian (the Mac norm); these never touch CoreAudio.
// ===========================================================================

namespace
{
    // Decode a little-endian int16 from a byte buffer at sample index i.
    auto readLeInt16(const std::vector<uint8_t>& bytes, size_t i) -> int16_t
    {
        const auto lo = static_cast<uint16_t>(bytes[(2U * i)]);
        const auto hi = static_cast<uint16_t>(bytes[(2U * i) + 1U]);
        return static_cast<int16_t>(static_cast<uint16_t>(lo | (hi << 8U)));
    }

    // Decode a little-endian uint32 word from a byte buffer at sample index i.
    auto readLeWord32(const std::vector<uint8_t>& bytes, size_t i) -> uint32_t
    {
        const size_t base = 4U * i;
        return static_cast<uint32_t>(bytes[base]) |
               (static_cast<uint32_t>(bytes[base + 1U]) << 8U) |
               (static_cast<uint32_t>(bytes[base + 2U]) << 16U) |
               (static_cast<uint32_t>(bytes[base + 3U]) << 24U);
    }

    // Conversion-format flag bundles (named, no magic booleans at call sites).
    constexpr uint32_t kBits16 = 16U;
    constexpr uint32_t kBits24 = 24U;
    constexpr uint32_t kBits32 = 32U;
    constexpr uint32_t kMonoCh = 1U;

    constexpr int16_t kI16PosFull = 0x7FFF;
    constexpr int16_t kI16NegFull = -0x8000;
    constexpr int32_t kI32PosFull = 0x7FFFFFFF;
    constexpr uint32_t kI32NegFullBits = 0x80000000U; // -0x80000000 as a bit pattern
} // namespace

// +1.0 -> 0x7FFF, -1.0 -> -0x8000, 0 -> 0, and ±1.2 saturate (no wrap) for int16 packed LE.
static auto testConvertInt16Saturation() -> void
{
    static const char* const kName = "Convert_Int16Saturation";
    const std::array<float, 5> src = {1.0F, -1.0F, 0.0F, 1.2F, -1.2F};
    std::vector<uint8_t> dst(src.size() * 2U, 0xAAU); // poison to catch unwritten bytes

    convertFloatToNative(src.data(),
                         dst.data(),
                         static_cast<uint32_t>(src.size()),
                         kMonoCh,
                         kBits16,
                         /*isFloat=*/false,
                         /*isSignedInt=*/true,
                         /*isPacked=*/true,
                         /*isAlignedHigh=*/false,
                         /*isBigEndian=*/false);

    const std::array<int16_t, 5> expected = {kI16PosFull, kI16NegFull, 0, kI16PosFull, kI16NegFull};
    for (size_t i = 0; i < src.size(); ++i)
    {
        const int16_t got = readLeInt16(dst, i);
        if (got != expected[i])
        {
            std::ostringstream oss;
            oss << "sample " << i << ": expected " << expected[i] << ", got " << got;
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// +1.0 -> 0x7FFFFFFF, -1.0 -> 0x80000000, 0 -> 0, +1.5 saturates for int32 packed LE.
static auto testConvertInt32Saturation() -> void
{
    static const char* const kName = "Convert_Int32Saturation";
    const std::array<float, 4> src = {1.0F, -1.0F, 0.0F, 1.5F};
    std::vector<uint8_t> dst(src.size() * 4U, 0xAAU);

    convertFloatToNative(src.data(),
                         dst.data(),
                         static_cast<uint32_t>(src.size()),
                         kMonoCh,
                         kBits32,
                         /*isFloat=*/false,
                         /*isSignedInt=*/true,
                         /*isPacked=*/true,
                         /*isAlignedHigh=*/false,
                         /*isBigEndian=*/false);

    const std::array<uint32_t, 4> expected = {static_cast<uint32_t>(kI32PosFull),
                                              kI32NegFullBits,
                                              0U,
                                              static_cast<uint32_t>(kI32PosFull)};
    for (size_t i = 0; i < src.size(); ++i)
    {
        const uint32_t got = readLeWord32(dst, i);
        if (got != expected[i])
        {
            std::ostringstream oss;
            oss << "sample " << i << ": expected 0x" << std::hex << expected[i] << ", got 0x"
                << got;
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// 24-in-32: aligned-high left-justifies the 24-bit value (top 24 bits, low byte 0); low-justified
// places it in the bottom 24 bits. +1.0 -> 0x7FFFFF (24-bit full scale).
static auto testConvert24In32Alignment() -> void
{
    static const char* const kName = "Convert_24In32Alignment";
    const std::array<float, 1> src = {1.0F};

    // Aligned-high: 0x7FFFFF << 8 == 0x7FFFFF00.
    {
        std::vector<uint8_t> dst(4U, 0xAAU);
        convertFloatToNative(src.data(),
                             dst.data(),
                             1U,
                             kMonoCh,
                             kBits24,
                             /*isFloat=*/false,
                             /*isSignedInt=*/true,
                             /*isPacked=*/false,
                             /*isAlignedHigh=*/true,
                             /*isBigEndian=*/false);
        const uint32_t got = readLeWord32(dst, 0);
        if (got != 0x7FFFFF00U)
        {
            std::ostringstream oss;
            oss << "aligned-high: expected 0x7FFFFF00, got 0x" << std::hex << got;
            logFail(kName, oss.str());
            return;
        }
    }
    // Low-justified: 0x007FFFFF.
    {
        std::vector<uint8_t> dst(4U, 0xAAU);
        convertFloatToNative(src.data(),
                             dst.data(),
                             1U,
                             kMonoCh,
                             kBits24,
                             /*isFloat=*/false,
                             /*isSignedInt=*/true,
                             /*isPacked=*/false,
                             /*isAlignedHigh=*/false,
                             /*isBigEndian=*/false);
        const uint32_t got = readLeWord32(dst, 0);
        if (got != 0x007FFFFFU)
        {
            std::ostringstream oss;
            oss << "low-justified: expected 0x007FFFFF, got 0x" << std::hex << got;
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// float32 passthrough is bit-identical to the source floats.
static auto testConvertFloatPassthrough() -> void
{
    static const char* const kName = "Convert_FloatPassthrough";
    const std::array<float, 6> src = {0.0F, 1.0F, -1.0F, 0.5F, -0.25F, 1.7F};
    std::vector<float> dst(src.size(), -999.0F);

    convertFloatToNative(src.data(),
                         dst.data(),
                         static_cast<uint32_t>(src.size()),
                         kMonoCh,
                         kBits32,
                         /*isFloat=*/true,
                         /*isSignedInt=*/false,
                         /*isPacked=*/true,
                         /*isAlignedHigh=*/false,
                         /*isBigEndian=*/false);

    // Bit-identical (memcmp): passthrough must not even alter an out-of-range value.
    if (std::memcmp(dst.data(), src.data(), src.size() * sizeof(float)) != 0)
    {
        logFail(kName, "float32 passthrough was not bit-identical to the source");
        return;
    }
    logPass(kName);
}

// An unsupported flag combination must write silence (zeros), never garbage / UB.
static auto testConvertUnsupportedWritesSilence() -> void
{
    static const char* const kName = "Convert_UnsupportedWritesSilence";
    const std::array<float, 4> src = {1.0F, -1.0F, 0.5F, -0.5F};
    std::vector<uint8_t> dst(src.size() * 4U, 0xAAU);

    // 20-bit signed is not a case we handle -> silence.
    constexpr uint32_t kBits20 = 20U;
    convertFloatToNative(src.data(),
                         dst.data(),
                         static_cast<uint32_t>(src.size()),
                         kMonoCh,
                         kBits20,
                         /*isFloat=*/false,
                         /*isSignedInt=*/true,
                         /*isPacked=*/true,
                         /*isAlignedHigh=*/false,
                         /*isBigEndian=*/false);

    for (size_t i = 0; i < dst.size(); ++i)
    {
        if (dst[i] != 0U)
        {
            std::ostringstream oss;
            oss << "byte " << i << " not zeroed (got 0x" << std::hex << static_cast<int>(dst[i])
                << ")";
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// ToneSource fills the requested frames on every channel, in [-amp, amp], identical across
// channels, and returns the full frame count.
static auto testToneSourceFillsBuffer() -> void
{
    static const char* const kName = "ToneSource_FillsBuffer";
    constexpr double kFreq = 1000.0;
    constexpr float kAmp = 0.5F;
    constexpr uint32_t kFrames = 256U;
    constexpr uint32_t kChannels = 2U;

    ToneSource tone(kFreq, kAmp, static_cast<double>(TestConstants::kSampleRate48k));
    std::vector<float> out(static_cast<size_t>(kFrames) * kChannels, -999.0F);
    const uint32_t produced = tone.pullFloat(out.data(), kFrames, kChannels);

    if (produced != kFrames)
    {
        logFail(kName,
                "pullFloat returned " + std::to_string(produced) + ", expected " +
                    std::to_string(kFrames));
        return;
    }
    for (uint32_t f = 0U; f < kFrames; ++f)
    {
        const float left = out[(static_cast<size_t>(f) * kChannels)];
        const float right = out[(static_cast<size_t>(f) * kChannels) + 1U];
        if (left != right)
        {
            logFail(kName, "channels differ at frame " + std::to_string(f));
            return;
        }
        if (left > kAmp + 1e-6F || left < -kAmp - 1e-6F)
        {
            std::ostringstream oss;
            oss << "frame " << f << " sample " << left << " outside [-" << kAmp << ", " << kAmp
                << "]";
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// ===========================================================================
// Pure-Mode C-ABI bridge (pureModeEvaluate). These tests pin the flat-ABI marshalling + the
// enum→uint8 ordering contract between the C++ policy and the Swift-facing C struct. They do NOT
// re-test the policy table itself (that is PureMode_* above) — instead they cross-check the bridge
// against the C++ evaluatePureMode() for the same inputs.
// ===========================================================================

// Bridge T1: every decision/reason branch translates faithfully. For each (device, file) the flat
// pureModeEvaluate() result must match the C++ evaluatePureMode() result field-for-field (decision
// + reason as uint8 of the enum, target rate within 1 Hz, the two boolean flags). The cases below
// cover all five (decision, reason) pairs so the enum→uint8 ordering is fully pinned.
static auto testPureModeBridgeTranslatesAllDecisionBranches() -> void
{
    static const char* const kName = "PureModeBridge_TranslatesAllDecisionBranches";

    // One (device, file) case: run both the flat bridge and the C++ policy; compare. The device
    // fixtures satisfy physicalFormat.isFloat == !integerCapable, matching the bridge's derivation.
    const auto checkCase = [&](const char* label,
                               const DeviceCapability& cap,
                               const FileFormat& file) -> std::string
    {
        std::vector<double> rates;
        const CDeviceCapability flatCap = toFlat(cap, rates);
        const CFileFormat flatFile = toFlatFile(file);
        const auto rateCount = static_cast<uint32_t>(rates.size());

        CPureModeEvaluation out{};
        pureModeEvaluate(&flatCap, rates.data(), rateCount, &flatFile, &out);

        const PureModeEvaluation eval = evaluatePureMode(cap, file);

        std::ostringstream oss;
        if (out.decision != static_cast<uint8_t>(eval.decision))
        {
            oss << label << " decision: bridge " << static_cast<int>(out.decision) << " vs C++ "
                << static_cast<int>(eval.decision) << "; ";
        }
        if (out.reason != static_cast<uint8_t>(eval.reason))
        {
            oss << label << " reason: bridge " << static_cast<int>(out.reason) << " vs C++ "
                << static_cast<int>(eval.reason) << "; ";
        }
        if (std::abs(out.targetDeviceRate - eval.targetDeviceRate) > 1.0)
        {
            oss << label << " targetDeviceRate: bridge " << out.targetDeviceRate << " vs C++ "
                << eval.targetDeviceRate << "; ";
        }
        if (out.requiresRateChange != (eval.requiresRateChange ? 1U : 0U))
        {
            oss << label << " requiresRateChange: bridge "
                << static_cast<int>(out.requiresRateChange) << " vs C++ " << eval.requiresRateChange
                << "; ";
        }
        if (out.requiresHog != (eval.requiresHog ? 1U : 0U))
        {
            oss << label << " requiresHog: bridge " << static_cast<int>(out.requiresHog)
                << " vs C++ " << eval.requiresHog << "; ";
        }
        return oss.str();
    };

    // Each case also documents the (decision, reason) pair it exercises (all five are covered).
    struct BranchCase
    {
        const char* label = "";
        DeviceCapability cap;
        FileFormat file;
        uint8_t expectDecision = 0U; // documented expectation, also asserted directly below
        uint8_t expectReason = 0U;
    };
    const std::array<BranchCase, 5> cases = {{
        // HDMI + 44.1k → FullBitPerfect / BitPerfectInteger.
        {"hdmi+44.1k", makeHdmiCapability(), makeFile(TestConstants::kRate44k), 0U, 0U},
        // built-in + 96k → RateMatchedFloat / RateMatchedFloatNoSRC.
        {"builtin+96k", makeBuiltInCapability(), makeFile(TestConstants::kRate96k), 1U, 1U},
        // Bluetooth + 44.1k → FallbackEnhanced / LossyWirelessCodec.
        {"bt+44.1k", makeBluetoothCapability(), makeFile(TestConstants::kRate44k), 2U, 2U},
        // Virtual + 48k → FallbackEnhanced / VirtualDevice.
        {"virtual+48k", makeVirtualCapability(), makeFile(TestConstants::kRate48k), 2U, 3U},
        // HDMI + 96k (unsupported) → FallbackEnhanced / RateUnsupportedResample.
        {"hdmi+96k", makeHdmiCapability(), makeFile(TestConstants::kRate96k), 2U, 4U},
    }};

    for (const BranchCase& bc : cases)
    {
        // First, cross-check the bridge against the C++ policy.
        const std::string err = checkCase(bc.label, bc.cap, bc.file);
        if (!err.empty())
        {
            logFail(kName, err);
            return;
        }
        // Then pin the absolute (decision, reason) uint8 values the contract promises.
        std::vector<double> rates;
        const CDeviceCapability flatCap = toFlat(bc.cap, rates);
        const CFileFormat flatFile = toFlatFile(bc.file);
        CPureModeEvaluation out{};
        pureModeEvaluate(
            &flatCap, rates.data(), static_cast<uint32_t>(rates.size()), &flatFile, &out);
        if (out.decision != bc.expectDecision || out.reason != bc.expectReason)
        {
            std::ostringstream oss;
            oss << bc.label << ": expected (decision " << static_cast<int>(bc.expectDecision)
                << ", reason " << static_cast<int>(bc.expectReason) << "), got (decision "
                << static_cast<int>(out.decision) << ", reason " << static_cast<int>(out.reason)
                << ")";
            logFail(kName, oss.str());
            return;
        }
    }
    logPass(kName);
}

// Bridge T2: NULL args are a safe no-op. pureModeEvaluate with cap/file/out NULL must not crash and
// must leave a non-null `out` untouched. Also: a rate-independent fallback device with NULL rates
// (rateCount 0) still resolves to the correct decision.
static auto testPureModeBridgeNullArgsAreNoOp() -> void
{
    static const char* const kName = "PureModeBridge_NullArgsAreNoOp";

    const DeviceCapability hdmi = makeHdmiCapability();
    std::vector<double> rates;
    const CDeviceCapability flatCap = toFlat(hdmi, rates);
    const CFileFormat flatFile = toFlatFile(makeFile(TestConstants::kRate48k));
    const auto rateCount = static_cast<uint32_t>(rates.size());

    // Pre-poison `out` with a sentinel; a no-op call must leave every field unchanged.
    constexpr uint8_t kSentinelDecision = 0xEEU;
    constexpr double kSentinelRate = -12345.0;
    constexpr uint8_t kSentinelRateChange = 0xCCU;
    constexpr uint8_t kSentinelHog = 0xDDU;
    constexpr uint8_t kSentinelReason = 0xBBU;
    const auto makeSentinel = []() -> CPureModeEvaluation
    {
        CPureModeEvaluation out{};
        out.decision = kSentinelDecision;
        out.targetDeviceRate = kSentinelRate;
        out.requiresRateChange = kSentinelRateChange;
        out.requiresHog = kSentinelHog;
        out.reason = kSentinelReason;
        return out;
    };

    const auto isSentinel = [&](const CPureModeEvaluation& out) -> bool
    {
        return out.decision == kSentinelDecision && out.targetDeviceRate == kSentinelRate &&
               out.requiresRateChange == kSentinelRateChange && out.requiresHog == kSentinelHog &&
               out.reason == kSentinelReason;
    };

    // (a) cap == NULL → no-op (must not touch `out`, must not crash).
    {
        CPureModeEvaluation out = makeSentinel();
        pureModeEvaluate(nullptr, rates.data(), rateCount, &flatFile, &out);
        if (!isSentinel(out))
        {
            logFail(kName, "cap==NULL: out was modified");
            return;
        }
    }

    // (b) file == NULL → no-op.
    {
        CPureModeEvaluation out = makeSentinel();
        pureModeEvaluate(&flatCap, rates.data(), rateCount, nullptr, &out);
        if (!isSentinel(out))
        {
            logFail(kName, "file==NULL: out was modified");
            return;
        }
    }

    // (c) out == NULL → no-op (just must not crash; nothing to inspect).
    pureModeEvaluate(&flatCap, rates.data(), rateCount, &flatFile, nullptr);

    // (d) availableRates == NULL with rateCount == 0 on a rate-INDEPENDENT device (Bluetooth: lossy
    //     wireless gates out before any rate lookup) → the correct fallback decision still results.
    {
        const DeviceCapability bt = makeBluetoothCapability();
        std::vector<double> btRates;
        const CDeviceCapability flatBt = toFlat(bt, btRates);
        const CFileFormat btFile = toFlatFile(makeFile(TestConstants::kRate44k));
        CPureModeEvaluation out{};
        pureModeEvaluate(&flatBt, nullptr, 0U, &btFile, &out);

        const PureModeEvaluation eval = evaluatePureMode(bt, makeFile(TestConstants::kRate44k));
        // Lossy wireless → FallbackEnhanced (2) / LossyWirelessCodec (2); rate list is irrelevant.
        if (out.decision != static_cast<uint8_t>(eval.decision) ||
            out.reason != static_cast<uint8_t>(eval.reason))
        {
            std::ostringstream oss;
            oss << "NULL rates fallback: bridge (decision " << static_cast<int>(out.decision)
                << ", reason " << static_cast<int>(out.reason) << ") vs C++ (decision "
                << static_cast<int>(eval.decision) << ", reason "
                << static_cast<int>(eval.reason) << ")";
            logFail(kName, oss.str());
            return;
        }
    }

    logPass(kName);
}

// Bridge T3: the rate array is copied faithfully across the flat ABI. A built-in-like device with
// explicit rates {44100, 48000, 88200, 96000} passed by ptr+count: an 88200 file resolves to
// RateMatchedFloat at 88200; a 192000 file (unsupported) resolves to RateUnsupportedResample at
// the copied maximum (96000). Cross-checked against C++ evaluatePureMode() with the same rates.
static auto testPureModeBridgeRateArrayCopiedFaithfully() -> void
{
    static const char* const kName = "PureModeBridge_RateArrayCopiedFaithfully";

    // Built-in-like (float, not integer-capable) device with an EXPLICIT advertised-rate list.
    DeviceCapability cap = makeBuiltInCapability();
    cap.availableRates = {TestConstants::kRate44k,
                          TestConstants::kRate48k,
                          TestConstants::kRate88k,
                          TestConstants::kRate96k};

    std::vector<double> rates;
    const CDeviceCapability flatCap = toFlat(cap, rates);
    const auto rateCount = static_cast<uint32_t>(rates.size());

    // (a) 88200 file → RateMatchedFloat (1) / RateMatchedFloatNoSRC (1), target 88200.
    {
        const FileFormat file = makeFile(TestConstants::kRate88k);
        const CFileFormat flatFile = toFlatFile(file);
        CPureModeEvaluation out{};
        pureModeEvaluate(&flatCap, rates.data(), rateCount, &flatFile, &out);

        const PureModeEvaluation eval = evaluatePureMode(cap, file);
        if (out.decision != static_cast<uint8_t>(PureModeDecision::RateMatchedFloat) ||
            out.reason != static_cast<uint8_t>(PureModeReason::RateMatchedFloatNoSRC) ||
            std::abs(out.targetDeviceRate - TestConstants::kRate88k) > 1.0 ||
            out.decision != static_cast<uint8_t>(eval.decision) ||
            out.reason != static_cast<uint8_t>(eval.reason) ||
            std::abs(out.targetDeviceRate - eval.targetDeviceRate) > 1.0)
        {
            std::ostringstream oss;
            oss << "88200 file: bridge (decision " << static_cast<int>(out.decision) << ", reason "
                << static_cast<int>(out.reason) << ", target " << out.targetDeviceRate
                << ") vs C++ (decision " << static_cast<int>(eval.decision) << ", reason "
                << static_cast<int>(eval.reason) << ", target " << eval.targetDeviceRate << ")";
            logFail(kName, oss.str());
            return;
        }
    }

    // (b) 192000 file (unsupported) → RateUnsupportedResample (4), target = copied max (96000).
    {
        const FileFormat file = makeFile(TestConstants::kRate192k);
        const CFileFormat flatFile = toFlatFile(file);
        CPureModeEvaluation out{};
        pureModeEvaluate(&flatCap, rates.data(), rateCount, &flatFile, &out);

        const PureModeEvaluation eval = evaluatePureMode(cap, file);
        if (out.decision != static_cast<uint8_t>(PureModeDecision::FallbackEnhanced) ||
            out.reason != static_cast<uint8_t>(PureModeReason::RateUnsupportedResample) ||
            std::abs(out.targetDeviceRate - TestConstants::kRate96k) > 1.0 ||
            out.decision != static_cast<uint8_t>(eval.decision) ||
            out.reason != static_cast<uint8_t>(eval.reason) ||
            std::abs(out.targetDeviceRate - eval.targetDeviceRate) > 1.0)
        {
            std::ostringstream oss;
            oss << "192000 file: bridge (decision " << static_cast<int>(out.decision) << ", reason "
                << static_cast<int>(out.reason) << ", target " << out.targetDeviceRate
                << ") vs C++ (decision " << static_cast<int>(eval.decision) << ", reason "
                << static_cast<int>(eval.reason) << ", target " << eval.targetDeviceRate << ")";
            logFail(kName, oss.str());
            return;
        }
    }

    logPass(kName);
}
