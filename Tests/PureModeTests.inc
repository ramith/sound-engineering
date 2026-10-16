// PureModeTests.inc
//
// Pure-Mode policy tests (Phase B — B1) and format conversion tests (B2a),
// plus ToneSource and inline file-decode bootstrap tests (B2b).
// #included into Tests/DSPKernelNullTest.cpp after TestSupport.h.
//
// Tests: PureMode_HdmiBitPerfect, PureMode_HdmiRateUnsupported,
//        PureMode_BluetoothLossy, PureMode_BuiltInRateMatchedFloat,
//        PureMode_BuiltInRateUnsupported, PureMode_VirtualDevice,
//        PureMode_RateEpsilonAndMax, PureMode_ChannelCountMismatch, Convert_Int16Saturation,
//        Convert_Int32Saturation, Convert_24In32Alignment,
//        Convert_FloatPassthrough, PureFormat_FromAsbdOnlyExactLayouts,
//        PureFormat_PickerOnlyWritableFormats, Convert_Packed24_ExactBytesRoundTrip,
//        Convert_WriteBoundedByBufferBytes, Convert_NonFiniteIsSilence_FiniteUntouched,
//        Convert_BitExact_Exhaustive16And24,
//        ToneSource_FillsBuffer, PureModeBridge_TranslatesAllDecisionBranches,
//        PureModeBridge_NullArgsAreNoOp, PureModeBridge_RateArrayCopiedFaithfully.
// Helpers (area-local): makeHdmiCapability, makeBluetoothCapability,
//   makeBuiltInCapability, makeVirtualCapability, makeInterfaceCapability, makeFile, checkEval,
//   readLeInt16, readLeWord32, kBitsXx, kMonoCh, kI16PosFull, kI16NegFull,
//   kI32PosFull, kI32NegFullBits, makeAsbd, convertInto, readWord, toFlat (DeviceCapability →
//   CDeviceCapability + rates).

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
            TestConstants::kRate32k,
            TestConstants::kRate44k,
            TestConstants::kRate48k,
        };
        cap.physicalFormat = {
            TestConstants::kRate48k,
            TestConstants::kBits24,
            TestConstants::kStereo,
            /*isFloat=*/false,
            /*isPCM=*/true,
        };
        cap.virtualFormat = {
            TestConstants::kRate48k,
            TestConstants::kBits32,
            TestConstants::kStereo,
            /*isFloat=*/true,
            /*isPCM=*/true,
        };
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
        cap.physicalFormat = {
            TestConstants::kRate44k,
            TestConstants::kBits32,
            TestConstants::kStereo,
            /*isFloat=*/true,
            /*isPCM=*/true,
        };
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
        cap.availableRates = {
            TestConstants::kRate44k,
            TestConstants::kRate48k,
            TestConstants::kRate88k,
            TestConstants::kRate96k,
        };
        cap.physicalFormat = {
            TestConstants::kRate48k,
            TestConstants::kBits32,
            TestConstants::kStereo,
            /*isFloat=*/true,
            /*isPCM=*/true,
        };
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
        cap.physicalFormat = {
            TestConstants::kRate48k,
            TestConstants::kBits32,
            TestConstants::kMono,
            /*isFloat=*/true,
            /*isPCM=*/true,
        };
        cap.virtualFormat = cap.physicalFormat;
        cap.integerCapable = false;
        cap.exclusiveCapable = false;
        cap.isLossyWireless = false;
        cap.isVirtualOrAggregate = true;
        return cap;
    }

    // A 4-output USB audio interface: integer PCM, 4 channels on its one output stream.
    auto makeInterfaceCapability(uint32_t channels) -> DeviceCapability
    {
        DeviceCapability cap = makeHdmiCapability();
        cap.transportType = 0U; // USB in reality; the policy never reads it
        cap.physicalFormat.channels = channels;
        cap.virtualFormat.channels = channels;
        return cap;
    }

    auto makeFile(double sampleRate, uint32_t channels = TestConstants::kStereo) -> FileFormat
    {
        FileFormat file;
        file.sampleRate = sampleRate;
        file.bitsPerChannel = TestConstants::kBits24;
        file.channels = channels;
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

// Pure plays the file channel for channel: the device stream must carry the file's channel count.
// Before the fix the policy never read the file's channels, so a mono file on the MacBook speakers
// (2-ch float) went Pure and rendered silence that never ended (council D71 / DSP-03). Now:
//   * a mono file on a stereo output, a stereo file on a 4- or 8-channel stream → FallbackEnhanced /
//     ChannelCountMismatch, with no hog / rate change / target (Enhanced maps any width);
//   * a matching width stays Pure and names the width the engine must find (targetChannels);
//   * an unknown device width (0) or a 0-channel file never counts as a match;
//   * the virtual format stands in when the physical width is unknown;
//   * the rate is decided first (a mono 192 kHz file on the speakers is RateUnsupportedResample).
static auto testPureModeChannelCountMismatch() -> void
{
    static const char* const kName = "PureMode_ChannelCountMismatch";
    constexpr uint32_t kFourCh = 4U;
    constexpr uint32_t kEightCh = 8U;
    const DeviceCapability builtIn = makeBuiltInCapability();

    const auto expectDecline =
        [&](const char* label, const DeviceCapability& cap, const FileFormat& file) -> std::string
    {
        const PureModeEvaluation eval = evaluatePureMode(cap, file);
        std::string err = checkEval(eval,
                                    PureModeDecision::FallbackEnhanced,
                                    PureModeReason::ChannelCountMismatch,
                                    /*targetRate=*/0.0,
                                    /*requiresRateChange=*/false,
                                    /*requiresHog=*/false);
        if (err.empty() && eval.targetChannels != 0U)
        {
            err = "targetChannels " + std::to_string(eval.targetChannels) + ", expected 0";
        }
        return err.empty() ? err : std::string(label) + ": " + err;
    };
    const auto expectPure = [&](const char* label,
                                const DeviceCapability& cap,
                                const FileFormat& file,
                                PureModeDecision decision) -> std::string
    {
        const PureModeEvaluation eval = evaluatePureMode(cap, file);
        if (eval.decision != decision || eval.targetChannels != file.channels)
        {
            return std::string(label) + ": decision " +
                   std::to_string(static_cast<int>(eval.decision)) + " (" +
                   pureModeReasonString(eval.reason) + "), targetChannels " +
                   std::to_string(eval.targetChannels) + "; expected decision " +
                   std::to_string(static_cast<int>(decision)) + ", targetChannels " +
                   std::to_string(file.channels);
        }
        return {};
    };

    DeviceCapability unknownWidth = makeBuiltInCapability();
    unknownWidth.physicalFormat.channels = 0U;
    unknownWidth.virtualFormat.channels = 0U;
    DeviceCapability virtualWidthOnly = makeBuiltInCapability();
    virtualWidthOnly.physicalFormat.channels = 0U;

    const std::array<std::string, 9> errors = {
        // The founder's case: a mono file on the MacBook Pro Speakers.
        expectDecline("mono on 2-ch speakers", builtIn, makeFile(TestConstants::kRate48k, 1U)),
        expectDecline("stereo on a 4-ch interface",
                      makeInterfaceCapability(kFourCh),
                      makeFile(TestConstants::kRate48k)),
        expectDecline("stereo on 8-ch HDMI",
                      makeInterfaceCapability(kEightCh),
                      makeFile(TestConstants::kRate48k)),
        expectDecline(
            "stereo on an unknown-width device", unknownWidth, makeFile(TestConstants::kRate48k)),
        expectDecline("0-ch file on an unknown-width device",
                      unknownWidth,
                      makeFile(TestConstants::kRate48k, 0U)),
        expectPure("stereo on 2-ch speakers",
                   builtIn,
                   makeFile(TestConstants::kRate44k),
                   PureModeDecision::RateMatchedFloat),
        expectPure("4-ch file on a 4-ch interface",
                   makeInterfaceCapability(kFourCh),
                   makeFile(TestConstants::kRate48k, kFourCh),
                   PureModeDecision::FullBitPerfect),
        expectPure("stereo, physical width unknown, virtual 2-ch",
                   virtualWidthOnly,
                   makeFile(TestConstants::kRate48k),
                   PureModeDecision::RateMatchedFloat),
        checkEval(evaluatePureMode(builtIn, makeFile(TestConstants::kRate192k, 1U)),
                  PureModeDecision::FallbackEnhanced,
                  PureModeReason::RateUnsupportedResample,
                  TestConstants::kRate96k,
                  /*requiresRateChange=*/false,
                  /*requiresHog=*/false),
    };
    for (const std::string& err : errors)
    {
        if (!err.empty())
        {
            logFail(kName, err);
            return;
        }
    }
    logPass(kName);
}

// ===========================================================================
// Pure-Mode native format + conversion (Phase B — B2a; the council's D74 / D76 fixes). Pure-unit
// tests of NativePcmFormat::fromAsbd (which device formats Pure writes exactly),
// pickIntegerPhysicalFormat (the integer physical format it sets), and convertFloatToNative: float
// inputs are converted to each native PCM layout and the raw bytes inspected. Never touches the HAL.
// ===========================================================================

namespace
{
    constexpr uint32_t kBitsPerByteTest = 8U;
    constexpr uint32_t kWord16Bytes = 2U;
    constexpr uint32_t kWord32Bytes = 4U;

    // The `width`-byte word at byte `offset`: least significant byte first, or most significant
    // first when `bigEndian`. An oracle independent of the converter's own store.
    auto readWord(std::span<const std::byte> bytes, size_t offset, uint32_t width, bool bigEndian)
        -> uint32_t
    {
        uint32_t word = 0U;
        for (uint32_t idx = 0U; idx < width; ++idx)
        {
            const uint32_t byteIndex = bigEndian ? (width - 1U - idx) : idx;
            word |= std::to_integer<uint32_t>(bytes[offset + idx])
                    << (byteIndex * kBitsPerByteTest);
        }
        return word;
    }

    // Decode a little-endian int16 from a byte buffer at sample index i.
    auto readLeInt16(std::span<const std::byte> bytes, size_t i) -> int16_t
    {
        return static_cast<int16_t>(
            static_cast<uint16_t>(readWord(bytes, kWord16Bytes * i, kWord16Bytes, false)));
    }

    // Decode a little-endian uint32 word from a byte buffer at sample index i.
    auto readLeWord32(std::span<const std::byte> bytes, size_t i) -> uint32_t
    {
        return readWord(bytes, kWord32Bytes * i, kWord32Bytes, false);
    }

    // Conversion-format constants (named, no magic booleans at call sites).
    constexpr uint32_t kBits16 = 16U;
    constexpr uint32_t kBits24 = 24U;
    constexpr uint32_t kBits32 = 32U;
    constexpr uint32_t kMonoCh = 1U;
    constexpr uint32_t kStereoCh = 2U;

    constexpr int16_t kI16PosFull = 0x7FFF;
    constexpr int16_t kI16NegFull = -0x8000;
    constexpr int32_t kI32PosFull = 0x7FFFFFFF;
    constexpr uint32_t kI32NegFullBits = 0x80000000U; // -0x80000000 as a bit pattern

    constexpr std::byte kPoison{0xAA}; // marks bytes the converter must not have written

    // Every layout the converter writes, for the per-layout sweeps.
    constexpr std::array<NativeSampleLayout, 6> kAllLayouts = {
        NativeSampleLayout::Float32,
        NativeSampleLayout::Int16,
        NativeSampleLayout::Int24Packed,
        NativeSampleLayout::Int24In32High,
        NativeSampleLayout::Int24In32Low,
        NativeSampleLayout::Int32,
    };

    auto nativeFormat(NativeSampleLayout layout,
                      uint32_t channels = kMonoCh,
                      bool bigEndian = false) -> NativePcmFormat
    {
        NativePcmFormat format;
        format.layout = layout;
        format.channels = channels;
        format.bigEndian = bigEndian;
        return format;
    }

    // Convert `src` into a fresh poisoned buffer of exactly its frames' bytes.
    auto convertInto(std::span<const float> src, const NativePcmFormat& format)
        -> std::vector<std::byte>
    {
        std::vector<std::byte> dst((src.size() / format.channels) * format.bytesPerFrame(),
                                   kPoison);
        convertFloatToNative(src, dst, format);
        return dst;
    }

    // A linear-PCM description as a device reports it (48 kHz, one frame per packet).
    auto makeAsbd(AudioFormatFlags flags, uint32_t channels, uint32_t bits, uint32_t bytesPerSample)
        -> AudioStreamBasicDescription
    {
        AudioStreamBasicDescription asbd{};
        asbd.mSampleRate = TestConstants::kRate48k;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = flags;
        asbd.mFramesPerPacket = 1U;
        asbd.mChannelsPerFrame = channels;
        asbd.mBitsPerChannel = bits;
        asbd.mBytesPerFrame = channels * bytesPerSample;
        asbd.mBytesPerPacket = asbd.mBytesPerFrame;
        return asbd;
    }

    // The flag sets real output streams report (e.g. 0x9 for the MacBook speakers' float32).
    constexpr AudioFormatFlags kFlagsFloat = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    constexpr AudioFormatFlags kFlagsIntPacked =
        kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    constexpr AudioFormatFlags kFlags24In32Low = kAudioFormatFlagIsSignedInteger;
    constexpr AudioFormatFlags kFlags24In32High =
        kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsAlignedHigh;
    constexpr uint32_t kBytes24Packed = 3U;
} // namespace

// +1.0 -> 0x7FFF, -1.0 -> -0x8000, 0 -> 0, and ±1.2 saturate (no wrap) for int16 packed LE.
static auto testConvertInt16Saturation() -> void
{
    static const char* const kName = "Convert_Int16Saturation";
    const std::array<float, 5> src = {1.0F, -1.0F, 0.0F, 1.2F, -1.2F};
    const std::vector<std::byte> dst = convertInto(src, nativeFormat(NativeSampleLayout::Int16));

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
    const std::vector<std::byte> dst = convertInto(src, nativeFormat(NativeSampleLayout::Int32));

    const std::array<uint32_t, 4> expected = {
        static_cast<uint32_t>(kI32PosFull),
        kI32NegFullBits,
        0U,
        static_cast<uint32_t>(kI32PosFull),
    };
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
    const uint32_t high =
        readLeWord32(convertInto(src, nativeFormat(NativeSampleLayout::Int24In32High)), 0);
    if (high != 0x7FFFFF00U)
    {
        std::ostringstream oss;
        oss << "aligned-high: expected 0x7FFFFF00, got 0x" << std::hex << high;
        logFail(kName, oss.str());
        return;
    }
    // Low-justified: 0x007FFFFF.
    const uint32_t low =
        readLeWord32(convertInto(src, nativeFormat(NativeSampleLayout::Int24In32Low)), 0);
    if (low != 0x007FFFFFU)
    {
        std::ostringstream oss;
        oss << "low-justified: expected 0x007FFFFF, got 0x" << std::hex << low;
        logFail(kName, oss.str());
        return;
    }
    logPass(kName);
}

// float32 passthrough is bit-identical to the source floats.
static auto testConvertFloatPassthrough() -> void
{
    static const char* const kName = "Convert_FloatPassthrough";
    const std::array<float, 6> src = {0.0F, 1.0F, -1.0F, 0.5F, -0.25F, 1.7F};
    const std::vector<std::byte> dst = convertInto(src, nativeFormat(NativeSampleLayout::Float32));

    // Bit-identical (memcmp): passthrough must not even alter an out-of-range value.
    if (std::memcmp(dst.data(), src.data(), src.size() * sizeof(float)) != 0)
    {
        logFail(kName, "float32 passthrough was not bit-identical to the source");
        return;
    }
    logPass(kName);
}

// NativePcmFormat::fromAsbd admits exactly the formats the converter writes byte for byte — and
// refuses everything else, so Pure declines rather than guesses (council D74: the converter used to
// write every 24-bit format as 4-byte words, whatever mBytesPerFrame said). Accepted: float32,
// int16, packed 24 (3 bytes), 24-in-32 high and low, int32, either endianness, any width. Refused:
// non-interleaved, non-PCM, unsigned / 8-bit / 20-bit integers, 16-in-32, float64, flags that
// contradict the byte size, and a frame size the channel count does not divide.
static auto testPureFormatFromAsbdOnlyExactLayouts() -> void
{
    static const char* const kName = "PureFormat_FromAsbdOnlyExactLayouts";
    constexpr uint32_t kEightCh = 8U;
    constexpr uint32_t kBits8 = 8U;
    constexpr uint32_t kBits20 = 20U;
    constexpr uint32_t kBits64 = 64U;
    constexpr uint32_t kBytes8 = 8U;
    constexpr uint32_t kOddBytesPerFrame = 7U;

    // Admitted as `layout`, with the description's width, frame size and byte order.
    const auto admitsAs = [](const char* label,
                             const AudioStreamBasicDescription& asbd,
                             NativeSampleLayout layout) -> std::string
    {
        const std::optional<NativePcmFormat> got = NativePcmFormat::fromAsbd(asbd);
        const bool bigEndian = (asbd.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0U;
        const bool ok = got.has_value() && got->layout == layout &&
                        got->channels == asbd.mChannelsPerFrame &&
                        got->bytesPerFrame() == asbd.mBytesPerFrame && got->bigEndian == bigEndian;
        return ok ? std::string{} : std::string(label) + ": not admitted as the expected layout";
    };
    const auto refuses = [](const char* label, const AudioStreamBasicDescription& asbd)
    {
        return NativePcmFormat::fromAsbd(asbd).has_value()
                   ? std::string(label) + ": admitted, but the converter cannot write it"
                   : std::string{};
    };

    AudioStreamBasicDescription ac3 = makeAsbd(kFlagsIntPacked, kStereoCh, kBits16, 2U);
    ac3.mFormatID = kAudioFormatAC3;
    AudioStreamBasicDescription noChannels = makeAsbd(kFlagsIntPacked, kStereoCh, kBits16, 2U);
    noChannels.mChannelsPerFrame = 0U;
    AudioStreamBasicDescription oddFrame = makeAsbd(kFlagsIntPacked, kStereoCh, kBits24, 3U);
    oddFrame.mBytesPerFrame = kOddBytesPerFrame;
    AudioStreamBasicDescription noBytes = makeAsbd(kFlagsIntPacked, kStereoCh, kBits16, 2U);
    noBytes.mBytesPerFrame = 0U;
    constexpr AudioFormatFlags kNonInterleaved = kAudioFormatFlagIsNonInterleaved;

    const std::array<std::string, 23> errors = {
        admitsAs("float32 stereo (0x9)",
                 makeAsbd(kFlagsFloat, kStereoCh, kBits32, 4U),
                 NativeSampleLayout::Float32),
        admitsAs("int16 stereo",
                 makeAsbd(kFlagsIntPacked, kStereoCh, kBits16, 2U),
                 NativeSampleLayout::Int16),
        admitsAs("packed int24 stereo",
                 makeAsbd(kFlagsIntPacked, kStereoCh, kBits24, kBytes24Packed),
                 NativeSampleLayout::Int24Packed),
        admitsAs("packed int24 8-ch",
                 makeAsbd(kFlagsIntPacked, kEightCh, kBits24, kBytes24Packed),
                 NativeSampleLayout::Int24Packed),
        admitsAs("24-in-32 low",
                 makeAsbd(kFlags24In32Low, kStereoCh, kBits24, 4U),
                 NativeSampleLayout::Int24In32Low),
        admitsAs("24-in-32 high",
                 makeAsbd(kFlags24In32High, kStereoCh, kBits24, 4U),
                 NativeSampleLayout::Int24In32High),
        admitsAs("int32 stereo",
                 makeAsbd(kFlagsIntPacked, kStereoCh, kBits32, 4U),
                 NativeSampleLayout::Int32),
        admitsAs("int16 big-endian",
                 makeAsbd(kFlagsIntPacked | kAudioFormatFlagIsBigEndian, kStereoCh, kBits16, 2U),
                 NativeSampleLayout::Int16),
        refuses("non-interleaved float32 stereo (0x29)",
                makeAsbd(kFlagsFloat | kNonInterleaved, kStereoCh, kBits32, 2U)),
        refuses("non-interleaved int16 stereo",
                makeAsbd(kFlagsIntPacked | kNonInterleaved, kStereoCh, kBits16, 1U)),
        // Only the interleaving rule refuses these two: their sizes alone would pass.
        refuses("non-interleaved float32 mono",
                makeAsbd(kFlagsFloat | kNonInterleaved, kMonoCh, kBits32, 4U)),
        refuses("non-interleaved float32 stereo, interleaved stride",
                makeAsbd(kFlagsFloat | kNonInterleaved, kStereoCh, kBits32, 4U)),
        refuses("AC-3 (not linear PCM)", ac3),
        refuses("unsigned int16", makeAsbd(kAudioFormatFlagIsPacked, kStereoCh, kBits16, 2U)),
        refuses("int8", makeAsbd(kFlagsIntPacked, kStereoCh, kBits8, 1U)),
        refuses("20-bit in 3 bytes",
                makeAsbd(kAudioFormatFlagIsSignedInteger, kStereoCh, kBits20, 3U)),
        refuses("20-bit claiming packed in 3 bytes",
                makeAsbd(kFlagsIntPacked, kStereoCh, kBits20, 3U)),
        refuses("24-bit claiming packed in 4 bytes",
                makeAsbd(kFlagsIntPacked, kStereoCh, kBits24, 4U)),
        refuses("16-in-32", makeAsbd(kAudioFormatFlagIsSignedInteger, kStereoCh, kBits16, 4U)),
        refuses("float64", makeAsbd(kFlagsFloat, kStereoCh, kBits64, kBytes8)),
        refuses("0 channels", noChannels),
        refuses("7-byte stereo frame", oddFrame),
        refuses("0-byte frame", noBytes),
    };
    for (const std::string& err : errors)
    {
        if (!err.empty())
        {
            logFail(kName, err);
            return;
        }
    }
    logPass(kName);
}

// The integer physical format Pure sets on a device is one the converter writes exactly: at the
// target rate and width, the highest bit depth among the WRITABLE formats, then the device's own
// flags (council D74 (b): the picker used to take the highest depth of any integer format, packed
// 24-bit and non-interleaved included).
static auto testPureFormatPickerOnlyWritableFormats() -> void
{
    static const char* const kName = "PureFormat_PickerOnlyWritableFormats";
    constexpr uint32_t kEightCh = 8U;
    constexpr uint32_t kBits20 = 20U;

    const AudioStreamBasicDescription int16 = makeAsbd(kFlagsIntPacked, kStereoCh, kBits16, 2U);
    const AudioStreamBasicDescription packed24 =
        makeAsbd(kFlagsIntPacked, kStereoCh, kBits24, kBytes24Packed);
    const AudioStreamBasicDescription low24 = makeAsbd(kFlags24In32Low, kStereoCh, kBits24, 4U);
    const AudioStreamBasicDescription nonInterleaved32 =
        makeAsbd(kFlagsIntPacked | kAudioFormatFlagIsNonInterleaved, kStereoCh, kBits32, 2U);
    const AudioStreamBasicDescription int20 =
        makeAsbd(kAudioFormatFlagIsSignedInteger, kStereoCh, kBits20, 3U);
    AudioStreamBasicDescription packed24At44k = packed24;
    packed24At44k.mSampleRate = TestConstants::kRate44k;
    const AudioStreamBasicDescription packed24EightCh =
        makeAsbd(kFlagsIntPacked, kEightCh, kBits24, kBytes24Packed);
    const AudioStreamBasicDescription float32 = makeAsbd(kFlagsFloat, kStereoCh, kBits32, 4U);

    const auto pick = [](std::span<const AudioStreamBasicDescription> available,
                         const AudioStreamBasicDescription& current)
    { return pickIntegerPhysicalFormat(available, current, TestConstants::kRate48k, kStereoCh); };
    const auto same = [](const std::optional<AudioStreamBasicDescription>& got,
                         const AudioStreamBasicDescription& want)
    {
        return got.has_value() && got->mSampleRate == want.mSampleRate &&
               got->mFormatFlags == want.mFormatFlags &&
               got->mBitsPerChannel == want.mBitsPerChannel &&
               got->mBytesPerFrame == want.mBytesPerFrame &&
               got->mChannelsPerFrame == want.mChannelsPerFrame;
    };

    // The 32-bit non-interleaved and the 20-bit formats rank higher by depth but cannot be written;
    // the wrong-rate / wrong-width / float candidates never qualify. The packed 24-bit one wins.
    const std::array<AudioStreamBasicDescription, 7> mixed = {
        int16,
        nonInterleaved32,
        int20,
        packed24At44k,
        packed24EightCh,
        float32,
        packed24,
    };
    if (!same(pick(mixed, float32), packed24))
    {
        logFail(kName, "did not pick the writable packed 24-bit format");
        return;
    }
    const std::array<AudioStreamBasicDescription, 3> unwritable = {
        nonInterleaved32,
        int20,
        float32,
    };
    if (pick(unwritable, float32).has_value() || pick({}, float32).has_value())
    {
        logFail(kName, "picked a format from a list with no writable integer format");
        return;
    }
    // Equal depth: the device's current flags win; otherwise the first stays.
    const std::array<AudioStreamBasicDescription, 2> tie = {low24, packed24};
    if (!same(pick(tie, packed24), packed24) || !same(pick(tie, low24), low24) ||
        !same(pick(tie, float32), low24))
    {
        logFail(kName, "equal-depth tie-break does not prefer the device's current flags");
        return;
    }
    logPass(kName);
}

namespace
{
    // One endianness of the packed 24-bit round trip: "" on success, else what went wrong.
    auto packed24RoundTripError(bool bigEndian,
                                std::span<const int32_t> codes,
                                std::span<const float> src) -> std::string
    {
        constexpr size_t kGuardBytes = 64U;
        constexpr uint32_t k24Mask = 0x00FFFFFFU;
        constexpr uint32_t k24Sign = 0x00800000U;
        constexpr uint32_t k24SignExtend = 0xFF000000U;
        const std::string order = bigEndian ? "BE" : "LE";

        const AudioFormatFlags flags =
            kFlagsIntPacked | (bigEndian ? kAudioFormatFlagIsBigEndian : 0U);
        const std::optional<NativePcmFormat> format =
            NativePcmFormat::fromAsbd(makeAsbd(flags, kStereoCh, kBits24, kBytes24Packed));
        if (!format.has_value() || format->layout != NativeSampleLayout::Int24Packed ||
            format->bytesPerFrame() != kStereoCh * kBytes24Packed)
        {
            return order + ": the packed 24-bit description is not read as 3-byte samples";
        }
        const size_t frames = src.size() / kStereoCh;
        const size_t exactBytes = frames * format->bytesPerFrame();

        std::vector<std::byte> exact(exactBytes, kPoison); // an exact heap block: ASan's redzone
        const size_t written = convertFloatToNative(src, exact, *format);

        std::vector<std::byte> guarded(exactBytes + kGuardBytes, kPoison);
        convertFloatToNative(src, std::span<std::byte>(guarded.data(), exactBytes), *format);
        const bool guardIntact =
            std::ranges::all_of(std::span<const std::byte>(guarded).subspan(exactBytes),
                                [](std::byte value) { return value == kPoison; });
        if (written != frames || !guardIntact)
        {
            return order + ": wrote " + std::to_string(written) + " of " + std::to_string(frames) +
                   " frames, guard " + (guardIntact ? "intact" : "OVERWRITTEN");
        }
        for (size_t i = 0; i < codes.size(); ++i)
        {
            const uint32_t word = readWord(exact, i * kBytes24Packed, kBytes24Packed, bigEndian);
            const auto got = static_cast<int32_t>(((word & k24Sign) != 0U) ? (word | k24SignExtend)
                                                                           : (word & k24Mask));
            if (got != codes[i])
            {
                return order + " sample " + std::to_string(i) + ": expected " +
                       std::to_string(codes[i]) + ", got " + std::to_string(got);
            }
        }
        return {};
    }
} // namespace

// Packed 24-bit (3 bytes a sample, common on USB DACs) is written as 3-byte samples: exactly
// frames x mBytesPerFrame bytes, every code back bit-exact, little- and big-endian. Before the fix
// the converter wrote 4-byte words into the 3-byte buffer: a one-third heap overrun on the HAL IO
// thread and corrupt audio (council D74). The buffer is an exact heap allocation, so the gate's
// ASan stage catches a single byte past it; a guard zone catches it in the plain run.
static auto testConvertPacked24ExactBytesRoundTrip() -> void
{
    static const char* const kName = "Convert_Packed24_ExactBytesRoundTrip";
    constexpr uint32_t kFrames = 512U;
    constexpr int32_t kI24Min = -8388608;
    constexpr int32_t kI24Max = 8388607;
    constexpr uint32_t kI24Codes = 16777216U; // 2^24
    constexpr uint32_t kCodeStride = 16411U;  // odd: walks every byte pattern across the frames
    constexpr float kI24Scale = 8388608.0F;

    std::vector<int32_t> codes(static_cast<size_t>(kFrames) * kStereoCh);
    for (size_t i = 0; i < codes.size(); ++i)
    {
        codes[i] =
            static_cast<int32_t>((static_cast<uint32_t>(i) * kCodeStride) % kI24Codes) + kI24Min;
    }
    codes[0] = kI24Max; // both full scales, on both channels
    codes[1] = kI24Min;
    std::vector<float> src(codes.size());
    std::ranges::transform(
        codes, src.begin(), [](int32_t code) { return static_cast<float>(code) / kI24Scale; });

    for (const bool bigEndian : {false, true})
    {
        const std::string err = packed24RoundTripError(bigEndian, codes, src);
        if (!err.empty())
        {
            logFail(kName, err);
            return;
        }
    }
    logPass(kName);
}

// Every write is bounded by the buffer's real byte size and the format's real frame stride, never by
// a size the bit depth implies (council D74 (c) / D76: the render clamped with ceil(bits / 8), so a
// 24-in-32 or packed-24 buffer was overrun). For every layout: a buffer that holds fewer frames than
// requested gets exactly the whole frames that fit, its partial trailing frame is silence, and not
// one byte past it is touched (an exact heap block for ASan + a guard zone); a buffer longer than
// the source plays silence past it; empty spans are no-ops.
static auto testConvertWriteBoundedByBufferBytes() -> void
{
    static const char* const kName = "Convert_WriteBoundedByBufferBytes";
    constexpr size_t kRequestedFrames = 100U;
    constexpr size_t kFittingFrames = 37U;
    constexpr size_t kGuardBytes = 64U;
    constexpr float kLevel = 0.5F;

    const std::vector<float> src(kRequestedFrames * kStereoCh, kLevel);
    for (const NativeSampleLayout layout : kAllLayouts)
    {
        const NativePcmFormat format = nativeFormat(layout, kStereoCh);
        const size_t bytesPerFrame = format.bytesPerFrame();
        // Room for 37 whole frames and all but one byte of the 38th.
        const size_t bufferBytes = (kFittingFrames * bytesPerFrame) + (bytesPerFrame - 1U);

        std::vector<std::byte> exact(bufferBytes, kPoison);
        const size_t written = convertFloatToNative(src, exact, format);

        std::vector<std::byte> guarded(bufferBytes + kGuardBytes, kPoison);
        convertFloatToNative(src, std::span<std::byte>(guarded.data(), bufferBytes), format);

        const std::span<const std::byte> view(guarded);
        const bool partialSilent =
            std::ranges::all_of(view.subspan(kFittingFrames * bytesPerFrame, bytesPerFrame - 1U),
                                [](std::byte value) { return value == std::byte{0}; });
        const bool guardIntact = std::ranges::all_of(
            view.subspan(bufferBytes), [](std::byte value) { return value == kPoison; });
        if (written != kFittingFrames || !partialSilent || !guardIntact)
        {
            logFail(kName,
                    "layout " + std::to_string(static_cast<int>(layout)) + ": wrote " +
                        std::to_string(written) + " of " + std::to_string(kFittingFrames) +
                        " frames, partial frame " + (partialSilent ? "silent" : "NOT silent") +
                        ", guard " + (guardIntact ? "intact" : "OVERWRITTEN"));
            return;
        }

        // A buffer longer than the source: the source frames, then silence (no stale bytes).
        std::vector<std::byte> longer(2U * kRequestedFrames * bytesPerFrame, kPoison);
        const size_t wroteLonger = convertFloatToNative(src, longer, format);
        const bool tailSilent = std::ranges::all_of(
            std::span<const std::byte>(longer).subspan(kRequestedFrames * bytesPerFrame),
            [](std::byte value) { return value == std::byte{0}; });
        if (wroteLonger != kRequestedFrames || !tailSilent)
        {
            logFail(kName,
                    "layout " + std::to_string(static_cast<int>(layout)) +
                        ": a longer buffer was not source-then-silence");
            return;
        }
    }

    // The shape the old ceil(24 / 8) bound produced: a 24-in-32 stereo buffer sized at 3 bytes a
    // sample. Only the whole 8-byte frames that fit are written.
    const NativePcmFormat word24 = nativeFormat(NativeSampleLayout::Int24In32High, kStereoCh);
    std::vector<std::byte> undersized(kRequestedFrames * kStereoCh * kBytes24Packed, kPoison);
    if (convertFloatToNative(src, undersized, word24) != undersized.size() / word24.bytesPerFrame())
    {
        logFail(kName, "24-in-32 into a 3-byte-per-sample buffer wrote past its whole frames");
        return;
    }

    // Empty spans: nothing written, nothing read past.
    std::vector<std::byte> some(kWord32Bytes, kPoison);
    if (convertFloatToNative(src, {}, word24) != 0U ||
        convertFloatToNative({}, some, word24) != 0U ||
        !std::ranges::all_of(some, [](std::byte value) { return value == std::byte{0}; }))
    {
        logFail(kName, "an empty source or destination was not a silent no-op");
        return;
    }
    logPass(kName);
}

// A NaN or an infinity plays as silence on the Pure path too, and every finite sample converts
// exactly as it would alone — a finite float32 sample stays bit-identical (denormal and out-of-range
// values included), so bit-perfect stays bit-perfect. Before the fix +Inf played at full scale (a
// hearing-safety gap the Enhanced kernel already closed) and NaN -> int was undefined behaviour
// (council D76). Every layout, both endiannesses.
static auto testConvertNonFiniteIsSilenceFiniteUntouched() -> void
{
    static const char* const kName = "Convert_NonFiniteIsSilence_FiniteUntouched";
    constexpr float kDenormal = 1.0e-40F;
    constexpr float kOverRange = 1.7F;
    constexpr float kNearFull = 0.999F;
    const float qnan = std::numeric_limits<float>::quiet_NaN();
    const float snan = std::numeric_limits<float>::signaling_NaN();
    const float inf = std::numeric_limits<float>::infinity();
    const std::array<float, 11> src = {
        0.5F,
        qnan,
        -0.25F,
        inf,
        kDenormal,
        -inf,
        -qnan,
        kNearFull,
        snan,
        kOverRange,
        -1.0F,
    };

    for (const NativeSampleLayout layout : kAllLayouts)
    {
        for (const bool bigEndian : {false, true})
        {
            const NativePcmFormat format = nativeFormat(layout, kMonoCh, bigEndian);
            const uint32_t width = format.bytesPerSample();
            const std::vector<std::byte> out = convertInto(src, format);
            for (size_t i = 0; i < src.size(); ++i)
            {
                const uint32_t got = readWord(out, i * width, width, bigEndian);
                uint32_t want = 0U; // a non-finite sample is silence
                if (std::isfinite(src[i]))
                {
                    const std::array<float, 1> alone = {src[i]};
                    want = (layout == NativeSampleLayout::Float32)
                               ? std::bit_cast<uint32_t>(src[i])
                               : readWord(convertInto(alone, format), 0U, width, bigEndian);
                }
                if (got != want)
                {
                    std::ostringstream oss;
                    oss << "layout " << static_cast<int>(layout) << (bigEndian ? " BE" : " LE")
                        << " sample " << i << " (" << src[i] << "): expected 0x" << std::hex << want
                        << ", got 0x" << got;
                    logFail(kName, oss.str());
                    return;
                }
            }
        }
    }
    logPass(kName);
}

// Exhaustive bit-exactness (the panels' H1, adopted): every 16-bit code into every integer layout,
// and every 24-bit code into every 24- and 32-bit layout, comes out as that code exactly — the
// decoder's int -> float (divide by 2^(N-1)) and the converter compose to the identity, now packed
// 24-bit included. Streams the 2^24 codes in 64 Ki blocks to stay small.
static auto testConvertBitExactExhaustive16And24() -> void
{
    static const char* const kName = "Convert_BitExact_Exhaustive16And24";
    constexpr int32_t kI16Codes = 65536; // 2^16
    constexpr int32_t kI16Min = -32768;  // -2^15
    constexpr float kI16Scale = 32768.0F;
    constexpr int32_t kI24Min = -8388608;   // -2^23
    constexpr int32_t kI24Codes = 16777216; // 2^24
    constexpr float kI24Scale = 8388608.0F;
    constexpr int32_t kBlock = 65536; // codes per streamed block
    constexpr uint32_t k16Mask = 0x0000FFFFU;
    constexpr uint32_t k24Mask = 0x00FFFFFFU;
    constexpr uint32_t kShift8 = 8U;

    // The device word an integer `value` must become in `layout`, once shifted up by `shift` to the
    // top of the layout's significant bits (exact while the code's depth fits), then justified.
    const auto expectedWord = [](NativeSampleLayout layout, int32_t value, uint32_t shift)
    {
        const auto placed = static_cast<uint32_t>(value) << shift;
        switch (layout)
        {
            case NativeSampleLayout::Int16:
                return placed & k16Mask;
            case NativeSampleLayout::Int24Packed:
            case NativeSampleLayout::Int24In32Low:
                return placed & k24Mask;
            case NativeSampleLayout::Int24In32High:
                return (placed & k24Mask) << kShift8;
            case NativeSampleLayout::Float32:
            case NativeSampleLayout::Int32:
                return placed;
        }
        return placed;
    };

    // Every layout that holds a 16-bit code exactly, and every one that holds a 24-bit code.
    constexpr std::array<NativeSampleLayout, 5> kHold16 = {
        NativeSampleLayout::Int16,
        NativeSampleLayout::Int24Packed,
        NativeSampleLayout::Int24In32High,
        NativeSampleLayout::Int24In32Low,
        NativeSampleLayout::Int32,
    };
    constexpr std::array<NativeSampleLayout, 4> kHold24 = {
        NativeSampleLayout::Int24Packed,
        NativeSampleLayout::Int24In32High,
        NativeSampleLayout::Int24In32Low,
        NativeSampleLayout::Int32,
    };
    struct Sweep
    {
        int32_t first;
        int32_t count;
        float scale;
        uint32_t validBits;
        std::span<const NativeSampleLayout> layouts;
    };
    const std::array<Sweep, 2> sweeps = {
        Sweep{kI16Min, kI16Codes, kI16Scale, kBits16, kHold16},
        Sweep{kI24Min, kI24Codes, kI24Scale, kBits24, kHold24},
    };

    std::vector<float> src(static_cast<size_t>(kBlock));
    std::vector<std::byte> dst(static_cast<size_t>(kBlock) * kWord32Bytes);
    for (const Sweep& sweep : sweeps)
    {
        for (int32_t base = 0; base < sweep.count; base += kBlock)
        {
            for (int32_t i = 0; i < kBlock; ++i)
            {
                src[static_cast<size_t>(i)] =
                    static_cast<float>(sweep.first + base + i) / sweep.scale;
            }
            for (const NativeSampleLayout layout : sweep.layouts)
            {
                const NativePcmFormat format = nativeFormat(layout);
                const uint32_t width = format.bytesPerSample();
                const uint32_t shift = format.validBits() - sweep.validBits;
                const std::span<std::byte> out(dst.data(), static_cast<size_t>(kBlock) * width);
                convertFloatToNative(src, out, format);
                for (int32_t i = 0; i < kBlock; ++i)
                {
                    const int32_t code = sweep.first + base + i;
                    const uint32_t got =
                        readWord(out, static_cast<size_t>(i) * width, width, /*bigEndian=*/false);
                    if (got != expectedWord(layout, code, shift))
                    {
                        std::ostringstream oss;
                        oss << sweep.validBits << "-bit code " << code << " -> layout "
                            << static_cast<int>(format.layout) << ": got 0x" << std::hex << got;
                        logFail(kName, oss.str());
                        return;
                    }
                }
            }
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
// cover all six (decision, reason) pairs so the enum→uint8 ordering is fully pinned.
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

    // Each case also documents the (decision, reason) pair it exercises (all six are covered).
    struct BranchCase
    {
        const char* label = "";
        DeviceCapability cap;
        FileFormat file;
        uint8_t expectDecision = 0U; // documented expectation, also asserted directly below
        uint8_t expectReason = 0U;
    };
    const std::array<BranchCase, 6> cases = {
        {
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
            // built-in (2-ch) + a mono 48k file → FallbackEnhanced / ChannelCountMismatch.
            {
                "builtin+mono",
                makeBuiltInCapability(),
                makeFile(TestConstants::kRate48k, 1U),
                2U,
                5U,
            },
        },
    };

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
    const auto makeSentinel = [] -> CPureModeEvaluation
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
    cap.availableRates = {
        TestConstants::kRate44k,
        TestConstants::kRate48k,
        TestConstants::kRate88k,
        TestConstants::kRate96k,
    };

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

// ============================================================================
// Pure honesty (R1.1-A, council C-33, C-34): whether Pure's output carries every bit of the source,
// and every reason having a name.
// ============================================================================

// Pure decodes to float32 (24 significant bits) and writes the device's own format. A source deeper
// than what reaches the device is NOT bit-perfect — a 24-bit file on a 16-bit-only DAC used to be
// labelled BitPerfectInteger and truncated (C-33). Red on cf861d4: there was no depth check, so every
// row came back as the engaged reason.
static auto testPureModeBitExactnessDepthRule() -> void
{
    static const char* const kName = "PureMode_BitExactness_DepthRule";
    struct Case
    {
        const char* what;
        uint32_t fileBits;
        bool fileFloat;
        uint32_t outputBits;
        bool outputFloat;
        bool bitPerfect;
    };
    constexpr auto kCases = std::to_array<Case>({
        {"16-bit file, 16-bit DAC", 16U, false, 16U, false, true},
        {"24-bit file, 24-bit DAC", 24U, false, 24U, false, true},
        {"24-bit file, 16-bit-only DAC", 24U, false, 16U, false, false},
        {"24-bit file, 32-bit DAC", 24U, false, 32U, false, true},
        {"32-bit integer file, 32-bit DAC (decoded through float32)", 32U, false, 32U, false, false},
        {"24-bit file, float output", 24U, false, 32U, true, true},
        {"32-bit integer file, float output", 32U, false, 32U, true, false},
        {"float32 file, float output", 32U, true, 32U, true, true},
        {"float32 file, 24-bit DAC", 32U, true, 24U, false, false},
        {"float64 file, float output", 64U, true, 32U, true, false},
        {"a compressed file (no source depth), 16-bit DAC", 0U, false, 16U, false, true},
    });
    for (const Case& testCase : kCases)
    {
        FileFormat file = makeFile(TestConstants::kRate44k);
        file.bitsPerChannel = testCase.fileBits;
        file.isFloat = testCase.fileFloat;
        const PureModeReason engaged =
            testCase.outputFloat ? PureModeReason::RateMatchedFloatNoSRC : PureModeReason::BitPerfectInteger;
        const PureModeReason got = bitExactness(file, testCase.outputBits, testCase.outputFloat, engaged);
        const PureModeReason expected = testCase.bitPerfect ? engaged : PureModeReason::DeviceShallowerThanSource;
        if (got != expected)
        {
            logFail(kName,
                    std::format("{}: {}, expected {}", testCase.what, pureModeReasonString(got),
                                pureModeReasonString(expected)));
            return;
        }
    }
    logPass(kName);
}

// Every reason crosses the C boundary as its code, in PureModeBridge.h's documented order (the Swift
// mirror decodes the same numbers), and has a name for the log.
static auto testPureModeReasonCodesAreTheBridgeOrder() -> void
{
    static const char* const kName = "PureMode_ReasonCodes_BridgeOrder";
    struct Code
    {
        PureModeReason reason;
        uint8_t code;
        const char* name;
    };
    constexpr auto kCodes = std::to_array<Code>({
        {PureModeReason::BitPerfectInteger, 0U, "BitPerfectInteger"},
        {PureModeReason::RateMatchedFloatNoSRC, 1U, "RateMatchedFloatNoSRC"},
        {PureModeReason::LossyWirelessCodec, 2U, "LossyWirelessCodec"},
        {PureModeReason::VirtualDevice, 3U, "VirtualDevice"},
        {PureModeReason::RateUnsupportedResample, 4U, "RateUnsupportedResample"},
        {PureModeReason::ChannelCountMismatch, 5U, "ChannelCountMismatch"},
        {PureModeReason::DeviceShallowerThanSource, 6U, "DeviceShallowerThanSource"},
        {PureModeReason::DeviceWouldNotStart, 7U, "DeviceWouldNotStart"},
        {PureModeReason::FileUnreadable, 8U, "FileUnreadable"},
        {PureModeReason::FileNeedsFFmpeg, 9U, "FileNeedsFFmpeg"},
    });
    for (const Code& entry : kCodes)
    {
        if (static_cast<uint8_t>(entry.reason) != entry.code ||
            std::string_view(pureModeReasonString(entry.reason)) != entry.name)
        {
            logFail(kName, std::format("{} is not code {}", entry.name, entry.code));
            return;
        }
    }
    logPass(kName);
}
