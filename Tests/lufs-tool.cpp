// lufs-tool.cpp — LUFS oracle cross-check helper (not part of the unit harness).
//
// Generates a 20 s, 1 kHz, in-phase stereo sine at a given peak dBFS, writes it
// as a 32-bit float WAV, and measures THOSE EXACT SAMPLES with LufsMeter. The
// companion script (scripts/validate-lufs.sh) then measures the same WAV with
// `ffmpeg ebur128` and asserts the two integrated-LUFS values agree to ±0.1 LU.
//
// Build:  see scripts/validate-lufs.sh
// Usage:  lufs-tool <out.wav> [peakDbfs=-23]

#include "Loudness/LufsMeter.h"
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <numbers>
#include <vector>

using namespace AdaptiveSound;

namespace
{
    constexpr uint32_t kSampleRate = 48000U;
    constexpr double kSeconds = 20.0;
    constexpr double kFreqHz = 1000.0;

    void writeU32(std::FILE* f, uint32_t v)
    {
        std::fwrite(&v, sizeof(v), 1, f);
    }
    void writeU16(std::FILE* f, uint16_t v)
    {
        std::fwrite(&v, sizeof(v), 1, f);
    }

    // Minimal IEEE-float (format 3) stereo WAV writer.
    void writeFloatWav(const char* path, const std::vector<float>& interleaved, uint32_t sampleRate)
    {
        std::FILE* f = std::fopen(path, "wb");
        if (f == nullptr)
        {
            std::perror("fopen");
            std::exit(2);
        }
        const uint16_t channels = 2;
        const uint16_t bits = 32;
        const uint32_t dataBytes = static_cast<uint32_t>(interleaved.size() * sizeof(float));
        const uint32_t blockAlign = channels * (bits / 8U);
        const uint32_t byteRate = sampleRate * blockAlign;

        std::fwrite("RIFF", 1, 4, f);
        writeU32(f, 36U + dataBytes);
        std::fwrite("WAVE", 1, 4, f);
        std::fwrite("fmt ", 1, 4, f);
        writeU32(f, 16U);
        writeU16(f, 3U); // IEEE float
        writeU16(f, channels);
        writeU32(f, sampleRate);
        writeU32(f, byteRate);
        writeU16(f, static_cast<uint16_t>(blockAlign));
        writeU16(f, bits);
        std::fwrite("data", 1, 4, f);
        writeU32(f, dataBytes);
        std::fwrite(interleaved.data(), sizeof(float), interleaved.size(), f);
        std::fclose(f);
    }
} // namespace

int main(int argc, char** argv)
{
    if (argc < 2)
    {
        std::fprintf(stderr, "usage: %s <out.wav> [peakDbfs]\n", argv[0]);
        return 1;
    }
    const char* outPath = argv[1];
    const double peakDbfs = (argc >= 3) ? std::atof(argv[2]) : -23.0;
    const double amp = std::pow(10.0, peakDbfs / 20.0);

    const auto frames = static_cast<size_t>(kSeconds * kSampleRate);
    std::vector<float> buf(frames * 2U);
    for (size_t n = 0; n < frames; ++n)
    {
        const double s =
            amp * std::sin(2.0 * std::numbers::pi * kFreqHz * static_cast<double>(n) / kSampleRate);
        buf[2 * n] = static_cast<float>(s);
        buf[(2 * n) + 1] = static_cast<float>(s);
    }

    writeFloatWav(outPath, buf, kSampleRate);

    LufsMeter meter;
    meter.prepare(kSampleRate);
    meter.addInterleavedStereo(buf.data(), frames);

    std::printf("meter_integrated_lufs: %.3f\n", meter.integratedLufs());
    return 0;
}
