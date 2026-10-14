// H7: adversarial checks of fix/pure-safety (672fc0a) against the REAL code in my worktree:
// NativePcmFormat::fromAsbd, pickIntegerPhysicalFormat, convertFloatToNative (new span API),
// evaluatePureMode, GaplessSource::armNext, FileDecodeSource. Independent oracles throughout.
#include "DeviceCapability.h"
#include "FileDecodeSource.h"
#include "FlushToZero.h"
#include "GaplessSource.h"
#include "PureModeFormat.h"
#include "wav.h"

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <optional>
#include <string>
#include <thread>
#include <vector>

using namespace AdaptiveSound;
static int fails = 0;
#define CHECK(c, ...) do { if (!(c)) { ++fails; std::printf("  FAIL: " __VA_ARGS__); std::printf("\n"); } } while (0)

// ---------------- independent reference encoder (my spec, not the code's) ----------------
static uint32_t refBits(NativeSampleLayout l, float x) {
    double v = std::isfinite(x) ? std::fmin(1.0, std::fmax(-1.0, double(x))) : 0.0;
    auto q = [&](double scale, int64_t lo, int64_t hi) { int64_t s = int64_t(v * scale); return s < lo ? lo : s > hi ? hi : s; };
    switch (l) {
        case NativeSampleLayout::Float32: { float f = std::isfinite(x) ? x : 0.0f; uint32_t u; std::memcpy(&u, &f, 4); return u; }
        case NativeSampleLayout::Int16: return uint32_t(q(32768.0, -32768, 32767)) & 0xFFFFu;
        case NativeSampleLayout::Int24Packed: case NativeSampleLayout::Int24In32Low: return uint32_t(q(8388608.0, -8388608, 8388607)) & 0xFFFFFFu;
        case NativeSampleLayout::Int24In32High: return (uint32_t(q(8388608.0, -8388608, 8388607)) & 0xFFFFFFu) << 8;
        case NativeSampleLayout::Int32: return uint32_t(q(2147483648.0, INT32_MIN, INT32_MAX));
    }
    return 0;
}
static uint32_t refWidth(NativeSampleLayout l) { return l == NativeSampleLayout::Int16 ? 2 : l == NativeSampleLayout::Int24Packed ? 3 : 4; }
static void refStore(std::vector<uint8_t>& out, uint32_t bits, uint32_t w, bool be) {
    for (uint32_t i = 0; i < w; ++i) out.push_back(uint8_t(bits >> (8 * (be ? (w - 1 - i) : i))));
}
static const char* lname(NativeSampleLayout l) {
    switch (l) { case NativeSampleLayout::Float32: return "Float32"; case NativeSampleLayout::Int16: return "Int16";
        case NativeSampleLayout::Int24Packed: return "Int24Packed"; case NativeSampleLayout::Int24In32High: return "Int24In32High";
        case NativeSampleLayout::Int24In32Low: return "Int24In32Low"; case NativeSampleLayout::Int32: return "Int32"; }
    return "?";
}

// Convert with an EXACT-size heap destination (so ASan sees any overrun).
static std::vector<uint8_t> convExact(const std::vector<float>& src, const NativePcmFormat& f, size_t dstBytes, size_t* framesOut = nullptr) {
    auto* d = static_cast<std::byte*>(std::malloc(dstBytes ? dstBytes : 1));
    std::memset(d, 0xAB, dstBytes);
    size_t fr = convertFloatToNative(std::span<const float>(src.data(), src.size()), std::span<std::byte>(d, dstBytes), f);
    if (framesOut) *framesOut = fr;
    std::vector<uint8_t> out(reinterpret_cast<uint8_t*>(d), reinterpret_cast<uint8_t*>(d) + dstBytes);
    std::free(d);
    return out;
}

static void exhaustive() {
    std::printf("\n[1] exhaustive bit-exactness, every layout x endianness (new span API)\n");
    struct L { NativeSampleLayout l; } layouts[] = {{NativeSampleLayout::Int16}, {NativeSampleLayout::Int24Packed}, {NativeSampleLayout::Int24In32High},
                                                    {NativeSampleLayout::Int24In32Low}, {NativeSampleLayout::Int32}};
    for (int bits : {16, 24}) {
        const int n = 1 << bits;
        std::vector<float> f(static_cast<size_t>(n));
        for (int v = -(n / 2); v < n / 2; ++v) f[size_t(v + n / 2)] = float(v) / float(n / 2);
        for (auto [l] : layouts) {
            if (bits == 24 && l == NativeSampleLayout::Int16) continue;   // requantisation, not identity
            for (bool be : {false, true}) {
                NativePcmFormat fmt; fmt.layout = l; fmt.channels = 1; fmt.bigEndian = be;
                const uint32_t w = refWidth(l);
                auto out = convExact(f, fmt, size_t(n) * w);
                long bad = 0;
                for (int v = -(n / 2); v < n / 2; ++v) {
                    size_t i = size_t(v + n / 2);
                    // identity oracle: the source integer left-justified to the device word
                    int64_t expectInt = (l == NativeSampleLayout::Int16) ? v << (16 - bits) * 0 : 0;
                    uint32_t expect;
                    if (l == NativeSampleLayout::Int16) expect = uint32_t(v) & 0xFFFF;
                    else if (l == NativeSampleLayout::Int24Packed || l == NativeSampleLayout::Int24In32Low) expect = uint32_t(v << (24 - bits)) & 0xFFFFFF;
                    else if (l == NativeSampleLayout::Int24In32High) expect = (uint32_t(v << (24 - bits)) & 0xFFFFFF) << 8;
                    else expect = uint32_t(int32_t(v) << (32 - bits));
                    (void)expectInt;
                    uint32_t got = 0;
                    for (uint32_t b = 0; b < w; ++b) got |= uint32_t(out[i * w + b]) << (8 * (be ? (w - 1 - b) : b));
                    bad += got != expect;
                }
                std::printf("  %2d-bit codes -> %-14s %s: %ld mismatches of %d\n", bits, lname(l), be ? "BE" : "LE", bad, n);
                CHECK(bad == 0, "exhaustive %d-bit %s", bits, lname(l));
            }
        }
    }
}

static void decoderEndToEnd(const std::string& dir) {
    std::printf("\n[2] real decoders (Apple, FFmpeg) -> real converter, every 16/24-bit code, packed-24 device\n");
    std::vector<int32_t> s16, s24;
    for (int v = -32768; v < 32768; ++v) { s16.push_back(v); s16.push_back(-1 - v); }
    for (int v = -(1 << 23); v < (1 << 23); ++v) s24.push_back(v);
    writeWav(dir + "/p16.wav", s16, {}, 2, 44100, 16, false);
    writeWav(dir + "/p24.wav", s24, {}, 2, 96000, 24, false);
    for (const char* be : {"apple", "ffmpeg"}) {
        for (int bits : {16, 24}) {
            setenv("ADAPTIVESOUND_DECODER", be, 1);
            FileDecodeSource src;
            if (!src.open((dir + (bits == 16 ? "/p16.wav" : "/p24.wav")).c_str())) { std::printf("  open failed\n"); continue; }
            std::vector<float> all, buf(4096 * 2);
            for (;;) {
                uint32_t got = src.pullFloat(buf.data(), 4096, 2);
                all.insert(all.end(), buf.begin(), buf.begin() + long(got) * 2);
                if (got < 4096) { if (src.exhausted()) break; std::this_thread::sleep_for(std::chrono::microseconds(200)); }
            }
            const auto& s = bits == 16 ? s16 : s24;
            NativePcmFormat fmt; fmt.layout = NativeSampleLayout::Int24Packed; fmt.channels = 2;
            auto out = convExact(all, fmt, all.size() * 3);
            long bad = all.size() != s.size();
            for (size_t i = 0; i < std::min(all.size(), s.size()); ++i) {
                uint32_t got = out[3 * i] | (out[3 * i + 1] << 8) | (uint32_t(out[3 * i + 2]) << 16);
                bad += got != (uint32_t(s[i] << (24 - bits)) & 0xFFFFFF);
            }
            std::printf("  [%s] %d-bit file -> Int24Packed LE device: %ld mismatches of %zu\n", be, bits, bad, s.size());
            CHECK(bad == 0, "decoder %s %d", be, bits);
        }
    }
    unsetenv("ADAPTIVESOUND_DECODER");
}

static void nonFinite(bool ftz) {
    std::printf("\n[3] non-finite / denormal / signed-zero / edges (FPCR.FZ %s)\n", ftz ? "ON" : "off");
    if (ftz) enableFlushToZero();
    auto fbits = [](uint32_t u) { float f; std::memcpy(&f, &u, 4); return f; };
    const std::vector<uint32_t> specials = {
        0x7FC00000u, 0xFFC00000u, 0x7F800001u /*sNaN*/, 0x7FFFFFFFu /*NaN max payload*/, 0xFFBADBADu /*neg NaN payload*/,
        0x7F800000u /*+Inf*/, 0xFF800000u /*-Inf*/, 0x00000001u /*min denormal*/, 0x807FFFFFu /*-max denormal*/,
        0x00000000u, 0x80000000u /*-0*/, 0x3F800000u /*+1*/, 0xBF800000u /*-1*/, 0x3F800001u /*just over 1*/, 0x7F7FFFFFu /*FLT_MAX*/};
    for (auto l : {NativeSampleLayout::Float32, NativeSampleLayout::Int16, NativeSampleLayout::Int24Packed, NativeSampleLayout::Int24In32High,
                   NativeSampleLayout::Int24In32Low, NativeSampleLayout::Int32}) {
        for (bool be : {false, true}) {
            for (int placement = 0; placement < 3; ++placement) {   // special at first / last / middle, rest finite noise
                NativePcmFormat fmt; fmt.layout = l; fmt.channels = 2; fmt.bigEndian = be;
                long bad = 0;
                for (uint32_t sp : specials) {
                    const size_t frames = 257;   // odd, so a 2-ch block is 514 samples
                    std::vector<float> src(frames * 2);
                    for (size_t i = 0; i < src.size(); ++i) src[i] = float(std::sin(double(i) * 0.37) * 0.9);
                    size_t at = placement == 0 ? 0 : placement == 1 ? src.size() - 1 : src.size() / 2;
                    src[at] = fbits(sp);
                    const uint32_t w = refWidth(l);
                    auto out = convExact(src, fmt, frames * 2 * w);
                    std::vector<uint8_t> ref;
                    for (float x : src) refStore(ref, refBits(l, x), w, be);
                    bad += out != ref;
                }
                CHECK(bad == 0, "%s %s placement %d: %ld vectors differ from the reference", lname(l), be ? "BE" : "LE", placement, bad);
            }
        }
    }
    // Float32 LE finite block: bit-identical memcpy path incl. -0 and denormals; a block with ONE NaN takes
    // the per-sample path — are its finite samples still bit-identical (denormals under FZ!)?
    {
        NativePcmFormat fmt; fmt.layout = NativeSampleLayout::Float32; fmt.channels = 2;
        std::vector<float> src = {fbits(0x80000000u), fbits(0x00000001u), fbits(0x807FFFFFu), 0.5f, fbits(0x7FC00000u), fbits(0x00400000u)};
        auto out = convExact(src, fmt, src.size() * 4);
        uint32_t u[6]; std::memcpy(u, out.data(), 24);
        std::printf("  float32 LE block with a NaN: -0 -> %08x, min denormal -> %08x, -max denormal -> %08x, NaN -> %08x, denormal -> %08x\n",
                    u[0], u[1], u[2], u[4], u[5]);
        CHECK(u[0] == 0x80000000u && u[1] == 1u && u[2] == 0x807FFFFFu && u[4] == 0u && u[5] == 0x00400000u, "float32 per-sample path not bit-identical");
    }
}

static void bounds() {
    std::printf("\n[4] buffer bounds (exact-size heap buffers; run under ASan+UBSan)\n");
    for (auto l : {NativeSampleLayout::Float32, NativeSampleLayout::Int16, NativeSampleLayout::Int24Packed, NativeSampleLayout::Int24In32High, NativeSampleLayout::Int32}) {
        for (uint32_t ch : {1u, 2u, 6u, 8u}) {
            NativePcmFormat fmt; fmt.layout = l; fmt.channels = ch;
            const uint32_t bpf = ch * refWidth(l);
            std::vector<float> src(512 * ch, 0.25f);
            for (size_t dst : {size_t(0), size_t(1), size_t(bpf - 1), size_t(bpf), size_t(bpf + 1), size_t(511) * bpf + bpf / 2, size_t(512) * bpf,
                               size_t(512) * bpf + 7, size_t(4096) * bpf}) {
                size_t fr = 0;
                auto out = convExact(src, fmt, dst, &fr);
                size_t expectFr = std::min<size_t>(512, dst / bpf);
                bool tailZero = true;
                for (size_t i = fr * bpf; i < out.size(); ++i) tailZero &= out[i] == 0;
                CHECK(fr == expectFr && tailZero, "%s ch=%u dst=%zu: frames %zu (expect %zu), tail zero %d", lname(l), ch, dst, fr, expectFr, tailZero);
            }
            // a src that is not whole frames
            std::vector<float> ragged(511 * ch + (ch > 1 ? 1 : 0), 0.25f);
            size_t fr = 0;
            convExact(ragged, fmt, size_t(512) * bpf, &fr);
            CHECK(fr == 511, "ragged src %s ch=%u: %zu frames", lname(l), ch, fr);
        }
    }
    NativePcmFormat zero; zero.channels = 0;
    size_t fr = 9;
    convExact(std::vector<float>(16, 0.5f), zero, 64, &fr);
    CHECK(fr == 0, "0-channel format converted %zu frames", fr);
    std::printf("  done\n");
}

// fromAsbd vs my own spec over a large grid of descriptions.
static void asbdGrid() {
    std::printf("\n[5] fromAsbd vs an independent spec over a grid of descriptions\n");
    const AudioFormatFlags all[] = {kAudioFormatFlagIsFloat, kAudioFormatFlagIsBigEndian, kAudioFormatFlagIsSignedInteger, kAudioFormatFlagIsPacked,
                                    kAudioFormatFlagIsAlignedHigh, kAudioFormatFlagIsNonInterleaved, kAudioFormatFlagIsNonMixable};
    long checked = 0, accepted = 0, disagree = 0, strideMismatch = 0;
    for (AudioFormatID id : {kAudioFormatLinearPCM, kAudioFormatAC3}) {
        for (uint32_t mask = 0; mask < (1u << 7); ++mask) {
            AudioFormatFlags flags = 0;
            for (int b = 0; b < 7; ++b) if (mask & (1u << b)) flags |= all[b];
            for (uint32_t bits : {0u, 8u, 16u, 20u, 24u, 32u, 64u}) {
                for (uint32_t ch : {0u, 1u, 2u, 3u, 6u, 8u, 24u}) {
                    for (int bps : {0, 1, 2, 3, 4, 8}) {
                        for (int skew : {0, 1, -1}) {
                            AudioStreamBasicDescription a{};
                            a.mFormatID = id; a.mFormatFlags = flags; a.mBitsPerChannel = bits; a.mChannelsPerFrame = ch;
                            int64_t bpf = int64_t(ch) * bps + skew;
                            if (bpf < 0) continue;
                            a.mBytesPerFrame = uint32_t(bpf); a.mFramesPerPacket = 1; a.mBytesPerPacket = a.mBytesPerFrame; a.mSampleRate = 48000;
                            auto got = NativePcmFormat::fromAsbd(a);
                            // my spec
                            std::optional<NativeSampleLayout> want;
                            bool ok = id == kAudioFormatLinearPCM && !(flags & kAudioFormatFlagIsNonInterleaved) && ch > 0 && a.mBytesPerFrame % ch == 0;
                            uint32_t bytes = ch ? a.mBytesPerFrame / ch : 0;
                            if (ok && (flags & kAudioFormatFlagIsPacked) && bits != bytes * 8) ok = false;
                            if (ok) {
                                if (flags & kAudioFormatFlagIsFloat) { if (bits == 32 && bytes == 4) want = NativeSampleLayout::Float32; }
                                else if (flags & kAudioFormatFlagIsSignedInteger) {
                                    if (bits == 16 && bytes == 2) want = NativeSampleLayout::Int16;
                                    else if (bits == 32 && bytes == 4) want = NativeSampleLayout::Int32;
                                    else if (bits == 24 && bytes == 3) want = NativeSampleLayout::Int24Packed;
                                    else if (bits == 24 && bytes == 4) want = (flags & kAudioFormatFlagIsAlignedHigh) ? NativeSampleLayout::Int24In32High : NativeSampleLayout::Int24In32Low;
                                }
                            }
                            ++checked;
                            if (got.has_value() != want.has_value() || (got && got->layout != *want)) ++disagree;
                            if (got) { ++accepted; if (got->bytesPerFrame() != a.mBytesPerFrame || got->channels != ch || got->bigEndian != bool(flags & kAudioFormatFlagIsBigEndian)) ++strideMismatch; }
                        }
                    }
                }
            }
        }
    }
    std::printf("  %ld descriptions, %ld accepted; disagreements with my spec %ld; accepted with a stride/channels/endianness != the description %ld\n",
                checked, accepted, disagree, strideMismatch);
    CHECK(disagree == 0 && strideMismatch == 0, "fromAsbd grid");
}

static void picker() {
    std::printf("\n[6] pickIntegerPhysicalFormat never returns a format the converter cannot write\n");
    auto mk = [](AudioFormatFlags f, uint32_t ch, uint32_t bits, uint32_t bytesPerSample, double rate = 48000) {
        AudioStreamBasicDescription a{}; a.mFormatID = kAudioFormatLinearPCM; a.mFormatFlags = f; a.mChannelsPerFrame = ch;
        a.mBitsPerChannel = bits; a.mBytesPerFrame = ch * bytesPerSample; a.mFramesPerPacket = 1; a.mBytesPerPacket = a.mBytesPerFrame; a.mSampleRate = rate; return a; };
    const AudioFormatFlags SI = kAudioFormatFlagIsSignedInteger, P = kAudioFormatFlagIsPacked, AH = kAudioFormatFlagIsAlignedHigh, NI = kAudioFormatFlagIsNonInterleaved;
    std::vector<AudioStreamBasicDescription> avail = {
        mk(SI | P, 2, 16, 2), mk(SI | NI, 2, 32, 4), mk(SI | P, 2, 20, 3) /*20-in-24*/, mk(SI | AH, 2, 20, 4) /*20 in 32*/, mk(SI | P | NI, 2, 24, 3),
        mk(kAudioFormatFlagIsFloat | P, 2, 32, 4), mk(SI | P, 2, 24, 3), mk(SI | AH, 2, 24, 4), mk(SI | P, 2, 24, 3, 44100), mk(SI | P, 8, 24, 3)};
    AudioStreamBasicDescription current = mk(SI | AH, 2, 24, 4);
    auto p = pickIntegerPhysicalFormat(avail, current, 48000, 2);
    CHECK(p.has_value() && NativePcmFormat::fromAsbd(*p).has_value(), "picker returned an unwritable or no format");
    if (p) std::printf("  picked bits=%u bytes/frame=%u flags=0x%x (24-in-32 aligned-high = the current flags expected)\n", p->mBitsPerChannel, p->mBytesPerFrame, p->mFormatFlags);
    // only unwritable integer formats on offer -> nullopt
    std::vector<AudioStreamBasicDescription> bad = {mk(SI | NI, 2, 32, 4), mk(SI | P, 2, 20, 3), mk(SI | P | NI, 2, 24, 3)};
    CHECK(!pickIntegerPhysicalFormat(bad, current, 48000, 2).has_value(), "picker accepted an unwritable format");
}

static void policy() {
    std::printf("\n[7] evaluatePureMode: file width vs device stream width\n");
    auto cap = [](uint32_t physCh, uint32_t virtCh) {
        DeviceCapability c; c.id = 1; c.currentRate = 48000; c.availableRates = {44100, 48000, 96000};
        c.physicalFormat.channels = physCh; c.virtualFormat.channels = virtCh; c.integerCapable = true; c.exclusiveCapable = true; return c; };
    struct Case { uint32_t file, phys, virt; bool pure; } cases[] = {{1, 2, 2, false}, {2, 4, 4, false}, {6, 2, 2, false}, {1, 1, 1, true}, {2, 2, 2, true},
                                                                     {8, 8, 8, true}, {2, 0, 2, true}, {2, 0, 0, false}, {0, 2, 2, false}, {2, 2, 8, true}};
    for (auto c : cases) {
        FileFormat f; f.sampleRate = 44100; f.channels = c.file; f.bitsPerChannel = 16;
        auto e = evaluatePureMode(cap(c.phys, c.virt), f);
        bool pure = e.decision != PureModeDecision::FallbackEnhanced;
        std::printf("  file %u ch, device phys %u / virt %u -> %s (%s)%s\n", c.file, c.phys, c.virt, pure ? "Pure" : "Enhanced",
                    pureModeReasonString(e.reason), pure != c.pure ? "  <-- unexpected" : "");
        CHECK(pure == c.pure, "policy case");
        if (pure) CHECK(e.targetChannels == c.file, "targetChannels");
    }
}

static void gaplessWidth(const std::string& dir) {
    std::printf("\n[8] mid-album gapless successor of another width / rate / depth (real GaplessSource)\n");
    auto make = [&](const char* n, int code, int frames, int ch, int rate, int bits) {
        std::vector<int32_t> v(size_t(frames) * size_t(ch), code); std::string p = dir + "/" + n; writeWav(p, v, {}, uint32_t(ch), uint32_t(rate), uint32_t(bits), false); return p; };
    auto open = [](const std::string& p) { auto s = std::make_unique<FileDecodeSource>(); return s->open(p.c_str()) ? std::move(s) : nullptr; };
    auto A = make("gA.wav", 1000, 4800, 2, 48000, 16);
    struct C { const char* name; std::string path; bool expectArm; } cs[] = {
        {"mono 48k 16-bit", make("gMono.wav", 2000, 48000, 1, 48000, 16), false},
        {"6-ch 48k 16-bit", make("g6.wav", 2000, 48000, 6, 48000, 16), false},
        {"stereo 44.1k", make("g441.wav", 2000, 48000, 2, 44100, 16), false},
        {"stereo 48k 24-bit", make("g24.wav", 2000, 48000, 2, 48000, 24), false},
        {"stereo 48k 16-bit", make("gOK.wav", 2000, 48000, 2, 48000, 16), true}};
    for (auto& c : cs) {
        GaplessSource g;
        g.setCurrent(open(A));
        std::this_thread::sleep_for(std::chrono::milliseconds(30));
        bool armed = g.armNext(open(c.path));
        std::vector<float> buf(512 * 2);
        uint64_t produced = 0;
        int firstNext = 0;
        for (int b = 0; b < 30; ++b) {
            uint32_t got = g.pullFloat(buf.data(), 512, 2);
            for (uint32_t i = 0; i < got; ++i) { int code = int(std::lround(buf[2 * i] * 32768)); if (code != 1000 && !firstNext) firstNext = code; }
            produced += got;
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            g.reapRetired();
        }
        std::printf("  A stereo 48k/16 then %-18s: armNext=%d (expect %d), transitions=%llu, ended=%d, next heard=%d\n", c.name, armed, c.expectArm,
                    (unsigned long long)g.transitionCount(), g.ended(), firstNext);
        CHECK(armed == c.expectArm, "armNext %s", c.name);
        if (!c.expectArm) CHECK(g.ended() && g.transitionCount() == 0, "unarmed successor: A must end cleanly (ended=%d)", g.ended());
    }
}

int main(int argc, char** argv) {
    const std::string dir = argc > 1 ? argv[1] : ".";
    const bool quick = argc > 2 && std::string(argv[2]) == "quick";
    if (!quick) exhaustive();
    if (!quick) decoderEndToEnd(dir);
    nonFinite(false);
    bounds();
    asbdGrid();
    picker();
    policy();
    gaplessWidth(dir);
    nonFinite(true);   // last: FZ stays set on this thread
    std::printf("\nH7 done: %d failure(s)\n", fails);
    return fails ? 1 : 0;
}
