// Minimal WAV writer for the P3 breaker harnesses (independent of the repo's test helpers).
#pragma once
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>
#include <string>

inline void putLE(std::vector<uint8_t>& b, uint64_t v, int n) {
    for (int i = 0; i < n; ++i) b.push_back(static_cast<uint8_t>((v >> (8 * i)) & 0xFF));
}

// bits: 16 or 24 (signed int PCM, packed) or 32 with isFloat.
inline bool writeWav(const std::string& path, const std::vector<int32_t>& ints, const std::vector<float>& floats,
                     uint32_t channels, uint32_t rate, uint32_t bits, bool isFloat) {
    const size_t samples = isFloat ? floats.size() : ints.size();
    const uint32_t bps = bits / 8;
    const uint64_t dataBytes = samples * bps;
    std::vector<uint8_t> h;
    h.insert(h.end(), {'R', 'I', 'F', 'F'});
    putLE(h, 36 + dataBytes, 4);
    h.insert(h.end(), {'W', 'A', 'V', 'E', 'f', 'm', 't', ' '});
    putLE(h, 16, 4);
    putLE(h, isFloat ? 3 : 1, 2);
    putLE(h, channels, 2);
    putLE(h, rate, 4);
    putLE(h, rate * channels * bps, 4);
    putLE(h, channels * bps, 2);
    putLE(h, bits, 2);
    h.insert(h.end(), {'d', 'a', 't', 'a'});
    putLE(h, dataBytes, 4);
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) return false;
    std::fwrite(h.data(), 1, h.size(), f);
    std::vector<uint8_t> body;
    body.reserve(dataBytes);
    for (size_t i = 0; i < samples; ++i) {
        if (isFloat) {
            uint32_t u;
            static_assert(sizeof(float) == 4);
            std::memcpy(&u, &floats[i], 4);
            putLE(body, u, 4);
        } else {
            putLE(body, static_cast<uint32_t>(ints[i]), static_cast<int>(bps));
        }
    }
    std::fwrite(body.data(), 1, body.size(), f);
    std::fclose(f);
    return true;
}
