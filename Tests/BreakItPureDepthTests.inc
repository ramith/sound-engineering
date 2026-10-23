// R1.1-A close-out break-it (P3a, audio side), kept as a regression test (red on b1cc33c). #included
// after PureModeTests.inc (makeFile, the policy).
//
// A 24-bit ALAC (and FLAC) file read by the Apple decoder — the default decoder since FFmpeg became
// opt-in — reports a source depth of 0 (FileDecodeSource::sourceBitsPerChannel: ExtAudioFile's
// FileDataFormat has mBitsPerChannel 0 for every compressed format; the depth is in mFormatFlags,
// kAppleLosslessFormatFlag_24BitSourceData). So on a 16-bit integer word ditherWhenConverting says
// "no dither" (the 24 → 16 step truncates) and bitExactness says BitPerfectInteger (no "Not
// bit-perfect" note). Expected: 24 bits, dither on, DeviceShallowerThanSource — for ALAC (m4a) and FLAC,
// both written here through Apple's own encoders.

#include <AudioToolbox/ExtendedAudioFile.h>

namespace
{
    // Write `frames` of a −20 dBFS 1 kHz sine as a 24-bit-source lossless file (`formatID` ALAC or FLAC, in
    // `fileType`) at 48 kHz stereo.
    auto writeLossless24(const char* path, AudioFileTypeID fileType, AudioFormatID formatID, uint32_t frames) -> bool
    {
        CFURLRef url = CFURLCreateFromFileSystemRepresentation(
            nullptr, reinterpret_cast<const UInt8*>(path), static_cast<CFIndex>(std::strlen(path)),
            static_cast<Boolean>(false));
        AudioStreamBasicDescription fileFormat{};
        fileFormat.mSampleRate = 48000.0;
        fileFormat.mFormatID = formatID;
        fileFormat.mFormatFlags = kAppleLosslessFormatFlag_24BitSourceData; // FLAC states its depth the same way
        fileFormat.mChannelsPerFrame = 2;
        fileFormat.mFramesPerPacket = (formatID == kAudioFormatFLAC) ? 4608U : 4096U;
        ExtAudioFileRef file = nullptr;
        const OSStatus created =
            ExtAudioFileCreateWithURL(url, fileType, &fileFormat, nullptr, kAudioFileFlags_EraseFile, &file);
        CFRelease(url);
        if (created != noErr || file == nullptr)
        {
            return false;
        }
        AudioStreamBasicDescription client{};
        client.mSampleRate = 48000.0;
        client.mFormatID = kAudioFormatLinearPCM;
        client.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        client.mChannelsPerFrame = 2;
        client.mBitsPerChannel = 32;
        client.mFramesPerPacket = 1;
        client.mBytesPerFrame = 8;
        client.mBytesPerPacket = 8;
        ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client);
        std::vector<float> samples(static_cast<size_t>(frames) * 2U);
        for (uint32_t i = 0U; i < frames; ++i)
        {
            const auto v = static_cast<float>(0.1 * std::sin(2.0 * std::numbers::pi * 1000.0 * i / 48000.0));
            samples[static_cast<std::size_t>(i) * 2U] = v;
            samples[(static_cast<std::size_t>(i) * 2U) + 1U] = v;
        }
        AudioBufferList abl{};
        abl.mNumberBuffers = 1;
        abl.mBuffers[0] = {2, static_cast<UInt32>(samples.size() * sizeof(float)), samples.data()};
        const OSStatus wrote = ExtAudioFileWrite(file, frames, &abl);
        ExtAudioFileDispose(file);
        return wrote == noErr;
    }
} // namespace

static auto testBreakItPureDepthLosslessSourceBits() -> void
{
    static const char* const kName = "BreakIt_PureDepth_LosslessSourceBits";
    struct Kind
    {
        const char* name;
        const char* file;
        AudioFileTypeID type;
        AudioFormatID format;
    };
    const auto kinds = std::to_array<Kind>({
        {"ALAC", "/breakit_alac24.m4a", kAudioFileM4AType, kAudioFormatAppleLossless},
        {"FLAC", "/breakit_flac24.flac", kAudioFileFLACType, kAudioFormatFLAC},
    });
    std::string err;
    for (const Kind& kind : kinds)
    {
        const std::string path = std::string(ADAPTIVESOUND_TEST_DATA_DIR) + kind.file;
        if (!writeLossless24(path.c_str(), kind.type, kind.format, 48000U))
        {
            err += std::format("{}: could not write the 24-bit fixture; ", kind.name);
            continue;
        }
        FileDecodeSource source;
        if (!source.open(path.c_str()))
        {
            err += std::format("{}: could not open the fixture; ", kind.name);
            std::remove(path.c_str());
            continue;
        }
        FileFormat file;
        file.sampleRate = source.sampleRate();
        file.channels = source.channels();
        file.bitsPerChannel = source.sourceBitsPerChannel();
        file.isFloat = source.sourceIsFloat();
        source.close();
        std::remove(path.c_str());
        if (file.bitsPerChannel != 24U)
        {
            err += std::format("{}: the decoder reports {} source bits for a 24-bit file; ", kind.name,
                               file.bitsPerChannel);
        }
        if (!ditherWhenConverting(file, 16U, false))
        {
            err += std::format("{}: on a 16-bit integer word it is not dithered (it truncates); ", kind.name);
        }
        if (bitExactness(file, 16U, false, PureModeReason::BitPerfectInteger) !=
            PureModeReason::DeviceShallowerThanSource)
        {
            err += std::format("{}: and it is called bit-perfect; ", kind.name);
        }
    }
    if (err.empty())
    {
        logPass(kName);
    }
    else
    {
        logFail(kName, err);
    }
}
