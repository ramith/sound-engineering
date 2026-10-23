// P2 breaker harness: drives the REAL AdaptiveSound DSP code (main @ 7d7c2cd) with adversarial
// inputs and dumps raw float32 outputs for the independent Python oracles (p2oracle.py).
// Read-only use of Sources/. Built by build.sh into this scratch directory only.
#include "DSPKernel.h"
#include "Limiting/LimiterModule.h"
#include "Loudness/ChannelLayoutDecoder.h"
#include "Loudness/LoudnessModule.h"
#include "Loudness/LufsMeter.h"
#include "Spatial/CrossfeedModule.h"
#include "Spatial/SpatialRenderKernel.h"
#include "TruePeakKernel.h"
#include "ParameterRamp.h"
#include "FlushToZero.h"
extern "C" {
#include "ebur128.h"
}
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <numbers>
#include <random>
#include <string>
#include <thread>
#include <vector>

using namespace AdaptiveSound;

namespace
{
    // ---------------------------------------------------------------- planar buffers
    struct Planar
    {
        uint32_t ch;
        uint32_t frames;
        std::vector<std::vector<float>> data;
        std::vector<uint8_t> ablStore;
        Planar(uint32_t c, uint32_t f) : ch(c), frames(f), data(c, std::vector<float>(f, 0.0F))
        {
            ablStore.resize(sizeof(AudioBufferList) + sizeof(AudioBuffer) * (c > 0 ? c - 1 : 0));
        }
        AudioBufferList* abl(uint32_t offset, uint32_t n)
        {
            auto* a = reinterpret_cast<AudioBufferList*>(ablStore.data());
            a->mNumberBuffers = ch;
            for (uint32_t c = 0; c < ch; ++c)
            {
                a->mBuffers[c].mNumberChannels = 1;
                a->mBuffers[c].mDataByteSize = n * sizeof(float);
                a->mBuffers[c].mData = data[c].data() + offset;
            }
            return a;
        }
    };

    void dumpPlanar(const char* path, const Planar& p)
    {
        FILE* f = std::fopen(path, "wb");
        if (!f) return;
        // interleaved float32
        std::vector<float> row(p.ch);
        for (uint32_t i = 0; i < p.frames; ++i)
        {
            for (uint32_t c = 0; c < p.ch; ++c) row[c] = p.data[c][i];
            std::fwrite(row.data(), sizeof(float), p.ch, f);
        }
        std::fclose(f);
    }

    // pink noise (Voss-McCartney-ish via Paul Kellet filter), unit-ish RMS
    struct Pink
    {
        double b0 = 0, b1 = 0, b2 = 0, b3 = 0, b4 = 0, b5 = 0, b6 = 0;
        std::mt19937 rng;
        std::normal_distribution<double> nd{0.0, 1.0};
        explicit Pink(uint32_t seed) : rng(seed) {}
        double next()
        {
            const double w = nd(rng);
            b0 = 0.99886 * b0 + w * 0.0555179;
            b1 = 0.99332 * b1 + w * 0.0750759;
            b2 = 0.96900 * b2 + w * 0.1538520;
            b3 = 0.86650 * b3 + w * 0.3104856;
            b4 = 0.55000 * b4 + w * 0.5329522;
            b5 = -0.7616 * b5 - w * 0.0168980;
            const double y = b0 + b1 + b2 + b3 + b4 + b5 + b6 + w * 0.5362;
            b6 = w * 0.115926;
            return y * 0.11;
        }
    };

    double ebur128Integrated(const std::vector<float>& inter, uint32_t ch, uint32_t fs,
                             const std::vector<int>& chmap, double* mom = nullptr,
                             double* st = nullptr)
    {
        ebur128_state* s = ebur128_init(ch, fs, EBUR128_MODE_I | EBUR128_MODE_S | EBUR128_MODE_M);
        for (uint32_t c = 0; c < ch && c < chmap.size(); ++c)
            ebur128_set_channel(s, c, chmap[c]);
        ebur128_add_frames_float(s, inter.data(), inter.size() / ch);
        double out = 0;
        ebur128_loudness_global(s, &out);
        if (mom) ebur128_loudness_momentary(s, mom);
        if (st) ebur128_loudness_shortterm(s, st);
        ebur128_destroy(&s);
        return out;
    }

    double ebur128TruePeakLin(const std::vector<float>& inter, uint32_t ch, uint32_t fs)
    {
        ebur128_state* s = ebur128_init(ch, fs, EBUR128_MODE_TRUE_PEAK);
        ebur128_add_frames_float(s, inter.data(), inter.size() / ch);
        double mx = 0;
        for (uint32_t c = 0; c < ch; ++c)
        {
            double v = 0;
            ebur128_true_peak(s, c, &v);
            mx = std::max(mx, v);
        }
        ebur128_destroy(&s);
        return mx;
    }

    // ===================================================================== MODE: meter
    // LufsMeter (the shipping header) vs libebur128 on adversarial gating signals and rates.
    int modeMeter()
    {
        const uint32_t rates[] = {8000, 11025, 22050, 32000, 44100, 48000, 88200, 96000, 176400, 192000, 384000};
        std::printf("rate,signal,lufsmeter_I,ebur128_I,diff_LU,lufsmeter_M,ebur_M,lufsmeter_S,ebur_S\n");
        for (uint32_t fs : rates)
        {
            struct Sig { const char* name; std::vector<float> x; };
            std::vector<Sig> sigs;
            auto gen = [&](const char* name, double seconds, auto fn) {
                const size_t n = static_cast<size_t>(seconds * fs);
                std::vector<float> x(n * 2);
                for (size_t i = 0; i < n; ++i)
                {
                    const auto [l, r] = fn(i);
                    x[2 * i] = static_cast<float>(l);
                    x[2 * i + 1] = static_cast<float>(r);
                }
                sigs.push_back({name, std::move(x)});
            };
            const double pi2 = 2.0 * std::numbers::pi;
            gen("sine1k_-23", 20.0, [&](size_t i) { double s = std::pow(10.0, -23.0 / 20) * std::sin(pi2 * 1000.0 * i / fs); return std::pair{s, s}; });
            gen("sine997_-20_Lonly", 10.0, [&](size_t i) { double s = 0.1 * std::sin(pi2 * 997.0 * i / fs); return std::pair{s, 0.0}; });
            {
                Pink p(1);
                // relative-gate stress: 3 s at A, 3 s at A-9.95 dB / alternate; and a level 10.05 below
                gen("pink_relgate_9.95", 30.0, [&](size_t i) { double g = ((i / (3 * fs)) % 2 == 0) ? 0.1 : 0.1 * std::pow(10.0, -9.95 / 20); double v = g * p.next(); return std::pair{v, v}; });
            }
            {
                Pink p(2);
                gen("pink_relgate_10.05", 30.0, [&](size_t i) { double g = ((i / (3 * fs)) % 2 == 0) ? 0.1 : 0.1 * std::pow(10.0, -10.05 / 20); double v = g * p.next(); return std::pair{v, v}; });
            }
            // absolute-gate straddle: a 1 kHz sine whose block loudness sits ~ -70 LUFS
            gen("sine_absgate_-69.97", 10.0, [&](size_t i) { double a = std::pow(10.0, (-69.97 + 0.691 - 3.0103 + 3.0103 - 0.0) / 20.0) * std::sqrt(2.0) / std::sqrt(2.0); double s = a * std::sin(pi2 * 1000.0 * i / fs); return std::pair{s, s}; });
            gen("short_0.35s", 0.35, [&](size_t i) { double s = 0.5 * std::sin(pi2 * 440.0 * i / fs); return std::pair{s, s}; });
            {
                Pink p(3);
                gen("hot_noise_+12LUFS", 5.0, [&](size_t i) { double v = 8.0 * p.next(); return std::pair{v, v}; });
            }
            {
                Pink p(4);
                // fade-in / fade-out over 60 s: dynamic program (classical-like)
                gen("pink_ramp_60s", 60.0, [&](size_t i) { double t = double(i) / fs; double db = -50.0 + 40.0 * std::sin(std::numbers::pi * t / 60.0); double v = std::pow(10.0, db / 20.0) * p.next(); return std::pair{v, v * 0.7}; });
            }
            for (auto& s : sigs)
            {
                LufsMeter m;
                m.prepare(fs);
                m.addInterleavedStereo(s.x.data(), s.x.size() / 2);
                double em = 0, es = 0;
                const double e = ebur128Integrated(s.x, 2, fs, {EBUR128_LEFT, EBUR128_RIGHT}, &em, &es);
                std::printf("%u,%s,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f\n", fs, s.name, m.integratedLufs(), e,
                            m.integratedLufs() - e, m.momentaryLufs(), em, m.shortTermLufs(), es);
            }
        }
        // 5.1 weighting (A order L R C LFE Ls Rs) via the shipping decoder → meter vs libebur128
        {
            const uint32_t fs = 48000;
            const size_t n = 10 * fs;
            std::vector<float> x(n * 6);
            Pink p0(10), p1(11), p2(12), p3(13), p4(14), p5(15);
            Pink* ps[6] = {&p0, &p1, &p2, &p3, &p4, &p5};
            for (size_t i = 0; i < n; ++i)
                for (int c = 0; c < 6; ++c) x[i * 6 + c] = static_cast<float>(0.05 * ps[c]->next());
            const ChannelLayout lay = decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_A);
            std::array<double, kMaxChannels> w{};
            for (uint32_t c = 0; c < kMaxChannels; ++c) w[c] = lay.lufsWeight[c];
            LufsMeter m;
            m.prepare(fs);
            m.configureChannels(6, w);
            m.addInterleaved(x.data(), n, 6);
            const double e = ebur128Integrated(x, 6, fs, {EBUR128_LEFT, EBUR128_RIGHT, EBUR128_CENTER, EBUR128_UNUSED, EBUR128_LEFT_SURROUND, EBUR128_RIGHT_SURROUND});
            std::printf("48000,5.1A_weighted,%.4f,%.4f,%.4f,,,,\n", m.integratedLufs(), e, m.integratedLufs() - e);
            // stereo-seed weights {1,1,0,0,...} (what LoudnessModule::initialize seeds) on the same 5.1 program
            const ChannelLayout st = decodeChannelLayout(kAudioChannelLayoutTag_Stereo);
            for (uint32_t c = 0; c < kMaxChannels; ++c) w[c] = st.lufsWeight[c];
            LufsMeter m2;
            m2.prepare(fs);
            m2.configureChannels(6, w);
            m2.addInterleaved(x.data(), n, 6);
            std::printf("48000,5.1_with_stereo_seed_weights,%.4f,%.4f,%.4f,,,,\n", m2.integratedLufs(), e, m2.integratedLufs() - e);
            // AAC_5_1 (= MPEG_5_1_D, C L R Ls Rs LFE) and UseChannelBitmap → decoder fallback weights
            const AudioChannelLayoutTag tags[] = {kAudioChannelLayoutTag_AAC_5_1, kAudioChannelLayoutTag_UseChannelBitmap,
                                                  kAudioChannelLayoutTag_UseChannelDescriptions, kAudioChannelLayoutTag_WAVE_5_1_B,
                                                  kAudioChannelLayoutTag_MPEG_5_1_C, (kAudioChannelLayoutTag_Unknown | 6U)};
            for (auto t : tags)
            {
                const ChannelLayout l2 = decodeChannelLayout(t);
                std::printf("decode tag 0x%08X -> numCh=%u weights=", t, l2.numChannels);
                for (uint32_t c = 0; c < 8; ++c) std::printf("%.3f ", l2.lufsWeight[c]);
                std::printf("\n");
            }
        }
        return 0;
    }

    // ===================================================================== MODE: tpk
    // TruePeakKernel: magnitude response of each phase and the max under-read of a unit sine vs
    // frequency (independent truth: the continuous sine's peak is exactly 1.0).
    int modeTpk()
    {
        TruePeakKernel::Coefficients co{};
        TruePeakKernel::computeCoefficients(co);
        // dump coefficients for the python oracle
        FILE* f = std::fopen("tpk_coeffs.bin", "wb");
        std::fwrite(co.data(), sizeof(double), co.size(), f);
        std::fclose(f);
        std::printf("f_over_fs,kernel_read_dB_worst_phase,ebur128_read_dB_48k\n");
        const uint32_t fs = 48000;
        for (double r = 0.30; r < 0.4999; r += 0.01)
        {
            const double fr = r;
            double worst = 1e9;
            double ebWorst = 1e9;
            for (int ph = 0; ph < 16; ++ph)
            {
                const double phase = ph * std::numbers::pi / 16.0;
                const size_t n = 4800;
                TruePeakKernel::History h{};
                double mx = 0;
                std::vector<float> inter(n * 2);
                for (size_t i = 0; i < n; ++i)
                {
                    const double s = std::sin(2.0 * std::numbers::pi * fr * static_cast<double>(i) + phase);
                    for (uint32_t k = TruePeakKernel::kNumTaps - 1; k > 0; --k) h[k] = h[k - 1];
                    h[0] = static_cast<float>(s);
                    if (i > 48) mx = std::max(mx, TruePeakKernel::phasePeak(h, co));
                    inter[2 * i] = inter[2 * i + 1] = static_cast<float>(s);
                }
                worst = std::min(worst, mx);
                ebWorst = std::min(ebWorst, ebur128TruePeakLin(inter, 2, fs));
            }
            std::printf("%.3f,%.4f,%.4f\n", fr, 20 * std::log10(worst), 20 * std::log10(ebWorst));
        }
        return 0;
    }

    // ===================================================================== MODE: limiter
    // Real LimiterModule on adversarial signals at the shipping 48 kHz (and other rates); dumps
    // input/output for the python ideal-reconstruction oracle.
    int modeLimiter(uint32_t fs, float ceiling, const char* tag, uint32_t block)
    {
        struct Sig { std::string name; Planar p; };
        std::vector<Sig> sigs;
        const double pi2 = 2.0 * std::numbers::pi;
        const uint32_t n = 2 * fs;
        auto add = [&](std::string name, auto fn) {
            Sig s{name, Planar(2, n)};
            for (uint32_t i = 0; i < n; ++i)
            {
                const auto [l, r] = fn(i);
                s.p.data[0][i] = static_cast<float>(l);
                s.p.data[1][i] = static_cast<float>(r);
            }
            sigs.push_back(std::move(s));
        };
        for (double fHz : {1000.0, 12000.0, 16000.0, 18000.0, 19000.0, 20000.0, 21000.0, 22000.0, 23000.0, 23500.0})
        {
            if (fHz >= fs / 2.0) continue;
            for (double ampDb : {0.0, 6.0})
            {
                const double a = std::pow(10.0, ampDb / 20.0);
                char nm[64];
                std::snprintf(nm, sizeof nm, "sine%.0f_%+.0fdBFS", fHz, ampDb);
                add(nm, [&, a, fHz](uint32_t i) { double s = a * std::sin(pi2 * fHz * i / fs + 0.3); return std::pair{s, s}; });
            }
        }
        add("fs4_45deg_0dBFS", [&](uint32_t i) { double s = std::sin(pi2 * 0.25 * i + std::numbers::pi / 4); return std::pair{s, s}; });
        // deep-GR step: silence → +24 dB over full scale, burst of 1 kHz
        add("step_+24dB_1k", [&](uint32_t i) { double s = (i > fs / 2 && (i % (fs / 4)) < fs / 20) ? 15.85 * std::sin(pi2 * 1000.0 * i / fs) : 0.0; return std::pair{s, s}; });
        add("step_+12dB_19k", [&](uint32_t i) { double s = (i > fs / 2 && (i % (fs / 4)) < fs / 20) ? 3.98 * std::sin(pi2 * 19000.0 * i / fs) : 0.0; return std::pair{s, s}; });
        // alternating worst-case ISP sequence (+1,+1,-1,-1 pattern shifted) — classic +3 dB
        add("isp_pattern_1100", [&](uint32_t i) { static const double pat[4] = {1, 1, -1, -1}; double s = pat[i % 4]; return std::pair{s, s}; });
        {
            Pink pk(77);
            add("pink_+6dBFS_hot", [&](uint32_t) { double v = 2.0 * 4.0 * pk.next(); return std::pair{v, v * 0.9}; });
        }
        {
            std::mt19937 rng(5);
            std::uniform_real_distribution<double> u(-1, 1);
            // brickwall "modern master": clipped noise HP'd → many consecutive full-scale samples with HF
            double prev = 0;
            add("clipped_hp_noise", [&](uint32_t) { double v = std::clamp(3.0 * u(rng), -1.0, 1.0); double hp = v - 0.5 * prev; prev = v; double s = std::clamp(hp, -1.0, 1.0); return std::pair{s, -s}; });
        }
        {
            Pink pk(78);
            add("clipped_pink_x4", [&](uint32_t) { double v = std::clamp(4.0 * 4.0 * pk.next(), -1.0, 1.0); return std::pair{v, v}; });
        }
        {
            std::mt19937 rng(6);
            std::normal_distribution<double> nd(0, 1);
            add("clipped_white_x3", [&](uint32_t) { double v = std::clamp(0.33 * 3.0 * nd(rng), -1.0, 1.0); return std::pair{v, v}; });
        }
        {
            // soft-clipped (tanh) pink: a "loudness-war" master
            Pink pk(79);
            add("tanh_pink_drive8", [&](uint32_t) { double v = std::tanh(8.0 * 4.0 * pk.next() * 0.25); return std::pair{v, v}; });
        }
        std::printf("signal,in_sample_peak_dB,out_sample_peak_dB\n");
        for (auto& s : sigs)
        {
            LimiterModule lim;
            lim.initialize(fs, block);
            LimiterParams prm{};
            prm.truePeakCeilingLinear = ceiling;
            Planar out = s.p;
            for (uint32_t off = 0; off < n; off += block)
            {
                const uint32_t len = std::min(block, n - off);
                const MultichannelView v = MultichannelView::fromABL(out.abl(off, len), len);
                lim.process(prm, v);
            }
            double ip = 0, op = 0;
            for (uint32_t i = 0; i < n; ++i)
            {
                ip = std::max(ip, (double)std::abs(s.p.data[0][i]));
                op = std::max(op, (double)std::abs(out.data[0][i]));
            }
            std::printf("%s,%.3f,%.3f\n", s.name.c_str(), 20 * std::log10(ip), 20 * std::log10(op));
            std::string path = std::string("lim_") + tag + "_" + s.name + ".f32";
            dumpPlanar(path.c_str(), out);
        }
        return 0;
    }

    // ===================================================================== MODE: blend
    // Real DSPKernel: output level vs Intensity, stubs as shipped, crossfeed off/on, loudness off
    // (isolates the blend law) and limiter bypassed.
    int modeBlend()
    {
        const uint32_t fs = 48000, block = 512;
        std::printf("crossfeed,intensity,out_rel_dB_vs_intensity1,corr_LR\n");
        for (int cf = 0; cf < 2; ++cf)
        {
            double ref = 0;
            for (float r : {1.0F, 0.0F, 0.05F, 0.1F, 0.2F, 0.3F, 0.5F, 0.7F, 0.9F, 0.99F})
            {
                DSPKernel k;
                k.initialize(fs, block);
                TargetState st{};
                st.intensityLinear = r;
                st.clarity.enabled = 0;
                st.loudness.enabled = 0;
                st.limiter.truePeakCeilingLinear = 2.0F;
                st.limiter.eqOnlyCeilingLinear = 2.0F;
                if (cf)
                {
                    st.crossfeed.enabled = 1;
                    const float alpha = 0.501F;
                    st.crossfeed.gDirect = 1.0F / (1.0F + alpha);
                    st.crossfeed.gCross = alpha / (1.0F + alpha);
                    const float pole = std::exp(-(2.0F * std::numbers::pi_v<float> * 700.0F) / fs);
                    st.crossfeed.lpfPole = pole;
                    st.crossfeed.lpfB0 = 1.0F - pole;
                    st.crossfeed.delayFrames = 15;
                }
                k.publishTargetState(st);
                Pink pl(1), pr(2);
                const uint32_t n = 6 * fs;
                Planar p(2, n);
                for (uint32_t i = 0; i < n; ++i)
                {
                    const double c = pl.next(), d = pr.next();
                    p.data[0][i] = static_cast<float>(0.1 * (c + 0.3 * d));
                    p.data[1][i] = static_cast<float>(0.1 * (d + 0.3 * c));
                }
                Planar in = p;
                for (uint32_t off = 0; off < n; off += block)
                    k.process(p.abl(off, block), block);
                double eo = 0, ei = 0, lr = 0, ll = 0, rr = 0;
                for (uint32_t i = 2 * fs; i < n; ++i)
                {
                    eo += double(p.data[0][i]) * p.data[0][i] + double(p.data[1][i]) * p.data[1][i];
                    ei += double(in.data[0][i]) * in.data[0][i] + double(in.data[1][i]) * in.data[1][i];
                    lr += double(p.data[0][i]) * p.data[1][i];
                    ll += double(p.data[0][i]) * p.data[0][i];
                    rr += double(p.data[1][i]) * p.data[1][i];
                }
                const double db = 10 * std::log10(eo / ei);
                if (r == 1.0F) ref = db;
                std::printf("%d,%.2f,%.3f,%.3f\n", cf, r, db - ref, lr / std::sqrt(ll * rr));
            }
        }
        return 0;
    }

    // ===================================================================== MODE: norm
    // The REAL LoudnessModule (its own worker thread) + REAL LimiterModule = the P2 chain with
    // identity EQ and the stub wet stages, paced at `speed`× real time. Scenarios:
    //   A loud→quiet, user-initiated change (publishChannelLayout = configureGraphForSource)
    //   B loud→quiet, gapless roll (no publish)
    //   C classical crescendo (pp 60 s → ff 25 s), single track
    // Writes a CSV trace every 100 ms of audio: t, input short-term, makeup dB, output short-term,
    // limiter GR (dB, min over the 100 ms).
    struct Segment { double seconds; double lufsTarget; bool publishAtStart; double crestBoost; };

    int runNorm(const char* name, const std::vector<Segment>& segs, double speed, uint32_t fs = 48000)
    {
        const uint32_t block = 512;
        auto lm = std::make_unique<LoudnessModule>();
        lm->initialize(fs, block);
        LimiterModule lim;
        lim.initialize(fs, block);
        LoudnessParams lp{};
        LimiterParams lip{};
        LufsMeter inMeter, outMeter;
        inMeter.prepare(fs);
        outMeter.prepare(fs);
        // per-segment pink gain calibrated so the segment's K-weighted loudness ≈ target
        // (calibrate once: unit pink → measure)
        double unitLufs;
        {
            Pink p(9);
            LufsMeter m;
            m.prepare(fs);
            std::vector<float> x(20 * fs * 2);
            for (size_t i = 0; i < x.size() / 2; ++i) { const float v = static_cast<float>(p.next()); x[2 * i] = v; x[2 * i + 1] = v; }
            m.addInterleavedStereo(x.data(), x.size() / 2);
            unitLufs = m.integratedLufs();
        }
        std::string path = std::string("norm_") + name + ".csv";
        FILE* f = std::fopen(path.c_str(), "w");
        std::fprintf(f, "t,seg_target,in_ST,makeup_dB,out_ST,out_M,limiter_GR_min_dB,out_peak_dB\n");
        Pink pk(123);
        const uint32_t look = static_cast<uint32_t>(std::lround(0.003 * fs));
        std::vector<float> hist(look, 0.0F);
        size_t histPos = 0;
        double t = 0;
        double grMin = 0, pk100 = 0;
        uint64_t grN = 0, gr1 = 0, gr3 = 0;
        uint32_t frames100 = 0;
        Planar p(2, block);
        const auto wallStart = std::chrono::steady_clock::now();
        uint64_t framesDone = 0;
        for (const auto& s : segs)
        {
            if (s.publishAtStart)
                lm->publishChannelLayout(decodeChannelLayout(kAudioChannelLayoutTag_Stereo));
            const double g = std::pow(10.0, (s.lufsTarget - unitLufs) / 20.0);
            const uint64_t segFrames = static_cast<uint64_t>(s.seconds * fs);
            for (uint64_t done = 0; done < segFrames; done += block)
            {
                for (uint32_t i = 0; i < block; ++i)
                {
                    double v = g * pk.next();
                    // occasional transients (drum-like) raising crest factor by crestBoost
                    if (s.crestBoost > 0 && ((framesDone + i) % (fs / 2)) < 64)
                        v *= s.crestBoost;
                    p.data[0][i] = static_cast<float>(v);
                    p.data[1][i] = static_cast<float>(0.95 * v);
                }
                inMeter.addNonInterleavedStereo(p.data[0].data(), p.data[1].data(), block);
                const MultichannelView view = MultichannelView::fromABL(p.abl(0, block), block);
                lm->process(lp, view);
                // remember the pre-limiter samples to compute the applied GR after the 3 ms delay
                std::vector<float> pre(p.data[0]);
                lim.process(lip, view);
                for (uint32_t i = 0; i < block; ++i)
                {
                    const float delayed = hist[histPos];
                    hist[histPos] = pre[i];
                    histPos = (histPos + 1) % hist.size();
                    if (std::abs(delayed) > 0.05F)
                    {
                        const double gr = 20 * std::log10(std::abs(p.data[0][i]) / std::abs(delayed));
                        grMin = std::min(grMin, gr);
                        ++grN; if (gr < -1.0) ++gr1; if (gr < -3.0) ++gr3;
                    }
                    pk100 = std::max(pk100, (double)std::abs(p.data[0][i]));
                }
                outMeter.addNonInterleavedStereo(p.data[0].data(), p.data[1].data(), block);
                framesDone += block;
                frames100 += block;
                if (frames100 >= fs / 10)
                {
                    frames100 = 0;
                    t = double(framesDone) / fs;
                    std::fprintf(f, "%.2f,%.1f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f\n", t, s.lufsTarget, inMeter.shortTermLufs(),
                                 20 * std::log10(lm->currentMakeupGainLinear()), outMeter.shortTermLufs(),
                                 outMeter.momentaryLufs(), grMin, 20 * std::log10(std::max(pk100, 1e-9)));
                    grMin = 0;
                    pk100 = 0;
                }
                // pace: audio time / speed
                const double audioSec = double(framesDone) / fs;
                const auto target = wallStart + std::chrono::duration<double>(audioSec / speed);
                std::this_thread::sleep_until(target);
            }
        }
        std::fclose(f);
        std::printf("%s: GR>1dB fraction of evaluated samples = %.4f, GR>3dB = %.4f\n", name, (double)gr1 / std::max<uint64_t>(1, grN), (double)gr3 / std::max<uint64_t>(1, grN));
        std::printf("%s: dropped frames = %llu, final makeup %.2f dB\n", name,
                    (unsigned long long)lm->droppedFrameCount(), 20 * std::log10(lm->currentMakeupGainLinear()));
        return 0;
    }

    // ===================================================================== MODE: layout
    // LoudnessModule (real worker) fed 5.1 with NO publish (the state after initialize() — i.e.
    // after every AU re-allocation) vs with the MPEG_5_1_A publish: what does the normaliser measure?
    int modeLayout()
    {
        const uint32_t fs = 48000, block = 512, n = 8 * fs;
        for (int publish = 0; publish < 2; ++publish)
        {
            auto lm = std::make_unique<LoudnessModule>();
            lm->initialize(fs, block);
            if (publish) lm->publishChannelLayout(decodeChannelLayout(kAudioChannelLayoutTag_MPEG_5_1_A));
            LoudnessParams lp{};
            Planar p(6, block);
            Pink ps[6] = {Pink(1), Pink(2), Pink(3), Pink(4), Pink(5), Pink(6)};
            for (uint32_t off = 0; off < n; off += block)
            {
                for (uint32_t i = 0; i < block; ++i)
                    for (int c = 0; c < 6; ++c)
                        p.data[c][i] = static_cast<float>((c < 2 ? 0.02 : 0.1) * ps[c].next()); // centre/surround-heavy mix
                lm->process(lp, MultichannelView::fromABL(p.abl(0, block), block));
                std::this_thread::sleep_for(std::chrono::microseconds(500));
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(200));
            std::printf("publish=%d measured integrated = %.2f LUFS, makeup = %.2f dB\n", publish,
                        lm->measuredLufsIntegrated(), 20 * std::log10(lm->currentMakeupGainLinear()));
        }
        return 0;
    }

    // ===================================================================== MODE: spatial
    // SpatialRenderKernel 6→2 (stereo device) on a 5.1 programme: energy kept vs BS.775 fold-down.
    int modeSpatial()
    {
        const uint32_t fs = 48000, n = fs;
        SpatialRenderKernel k;
        k.initialize(fs, n);
        k.configure(6, 2);
        Planar in(6, n), out(2, n);
        Pink ps[6] = {Pink(1), Pink(2), Pink(3), Pink(4), Pink(5), Pink(6)};
        for (uint32_t i = 0; i < n; ++i)
            for (int c = 0; c < 6; ++c) in.data[c][i] = static_cast<float>(0.05 * ps[c].next());
        k.process(MultichannelView::fromABL(in.abl(0, n), n), MultichannelView::fromABL(out.abl(0, n), n));
        bool lIsL = std::memcmp(out.data[0].data(), in.data[0].data(), n * 4) == 0;
        bool rIsR = std::memcmp(out.data[1].data(), in.data[1].data(), n * 4) == 0;
        std::printf("6->2: out0==in0 %d, out1==in1 %d (C, LFE, Ls, Rs discarded)\n", lIsL, rIsR);
        dumpPlanar("spatial_in6.f32", in);
        dumpPlanar("spatial_out2.f32", out);
        return 0;
    }

    // ===================================================================== MODE: ramp / ftz
    int modeRamp()
    {
        ParameterRamp r;
        r.initialize(0.050F, 48000.0F);
        r.target = std::pow(10.0F, 6.0F / 20.0F);
        r.snap();
        r.target = 1.0F;
        for (int i = 0; i < 48000 * 10; ++i) (void)r.tick();
        std::printf("makeup ramp 50ms from +6 dB to unity after 10 s: current=%.9f diff=%.3g (settle eps in applyMakeup = 1e-6)\n",
                    r.current, r.current - r.target);
        ParameterRamp q;
        q.initialize(0.050F, 48000.0F);
        q.target = std::pow(10.0F, -6.0F / 20.0F);
        q.snap();
        q.target = 1.0F;
        for (int i = 0; i < 48000 * 10; ++i) (void)q.tick();
        std::printf("makeup ramp 50ms from -6 dB to unity after 10 s: current=%.9f diff=%.3g\n", q.current, q.current - q.target);
        ParameterRamp it;
        it.initialize(0.032F, 48000.0F);
        it.target = 0.0F;
        it.current = 1.0F;
        int n = 0;
        while (it.current >= 1e-4F && n < 48000 * 60) { (void)it.tick(); ++n; }
        std::printf("intensity ramp 1→0 reaches the 1e-4 settle eps after %.3f s\n", n / 48000.0);
        return 0;
    }

    int modeFtz()
    {
        volatile double a = 1e-300, b = 1e-10;
        volatile float fa = 1e-30F, fb = 1e-10F;
        double before = a * b;
        float fbefore = fa * fb;
        enableFlushToZero();
        double after = a * b;
        float fafter = fa * fb;
        std::printf("double subnormal product: before FZ=%g after FZ=%g ; float: before=%g after=%g\n", before, after,
                    (double)fbefore, (double)fafter);
        return 0;
    }
    // ===================================================================== MODE: xfeed
    // REAL CrossfeedModule, coefficients by the Realizer's formula (alpha, fc per preset; D=round(0.0003178 fs)).
    int modeXfeed()
    {
        const uint32_t fs = 48000;
        struct P { const char* n; float a; float fc; };
        const P ps[] = {{"Relaxed", 0.335F, 650.F}, {"Default", 0.355F, 700.F}, {"Strong", 0.501F, 700.F}};
        std::printf("preset,freq,centre_dB,hardL_ipsi_dB,hardL_contra_dB\n");
        for (const auto& pr : ps)
        {
            CrossfeedParams cp{};
            cp.enabled = 1;
            cp.gDirect = 1.0F / (1.0F + pr.a);
            cp.gCross = pr.a / (1.0F + pr.a);
            const float pole = std::exp(-(6.28318530717958647692F * pr.fc) / fs);
            cp.lpfPole = pole;
            cp.lpfB0 = 1.0F - pole;
            cp.delayFrames = roundToNearestInt(kCrossfeedItdSeconds * fs);
            for (double f : {100.0, 300.0, 500.0, 700.0, 850.0, 1000.0, 1200.0, 1500.0, 2000.0, 3000.0, 5000.0, 10000.0})
            {
                double res[3];
                for (int mode = 0; mode < 2; ++mode)
                {
                    CrossfeedModule m;
                    const uint32_t n = fs;
                    m.initialize(fs, n);
                    Planar p(2, n);
                    for (uint32_t i = 0; i < n; ++i)
                    {
                        const float s = static_cast<float>(0.25 * std::sin(2 * std::numbers::pi * f * i / fs));
                        p.data[0][i] = s;
                        p.data[1][i] = mode == 0 ? s : 0.0F;
                    }
                    m.process(cp, MultichannelView::fromABL(p.abl(0, n), n)); // warm ramp
                    for (uint32_t i = 0; i < n; ++i)
                    {
                        const float s = static_cast<float>(0.25 * std::sin(2 * std::numbers::pi * f * (i + n) / fs));
                        p.data[0][i] = s;
                        p.data[1][i] = mode == 0 ? s : 0.0F;
                    }
                    m.process(cp, MultichannelView::fromABL(p.abl(0, n), n));
                    double el = 0, er = 0;
                    for (uint32_t i = n / 2; i < n; ++i) { el += double(p.data[0][i]) * p.data[0][i]; er += double(p.data[1][i]) * p.data[1][i]; }
                    const double ref = 0.25 * 0.25 / 2 * (n / 2);
                    if (mode == 0) res[0] = 10 * std::log10(el / ref);
                    else { res[1] = 10 * std::log10(el / ref); res[2] = 10 * std::log10(er / ref); }
                }
                std::printf("%s,%.0f,%.2f,%.2f,%.2f\n", pr.n, f, res[0], res[1], res[2]);
            }
        }
        return 0;
    }
    // ===================================================================== MODE: release
    // Real LimiterModule: one short over-ceiling transient on a quiet steady tone. Measures the GR
    // still applied N ms after the transient (dual-release "fast 100 ms / slow 500 ms, deeper wins").
    int modeRelease()
    {
        const uint32_t fs = 48000, block = 512, n = 3 * fs;
        LimiterModule lim;
        lim.initialize(fs, block);
        LimiterParams prm{};
        Planar p(2, n), in(2, n);
        const uint32_t t0 = fs / 2; // transient at 0.5 s
        for (uint32_t i = 0; i < n; ++i)
        {
            double s = 0.1 * std::sin(2 * std::numbers::pi * 1000.0 * i / fs);
            if (i >= t0 && i < t0 + 48) s = 1.8 * std::sin(2 * std::numbers::pi * 3000.0 * i / fs); // 1 ms, ~6 dB over
            p.data[0][i] = p.data[1][i] = in.data[0][i] = in.data[1][i] = static_cast<float>(s);
        }
        for (uint32_t off = 0; off < n; off += block)
            lim.process(prm, MultichannelView::fromABL(p.abl(off, std::min(block, n - off)), std::min(block, n - off)));
        const uint32_t look = 144;
        std::printf("ms_after_transient,GR_dB (|out|/|in delayed| over a 1 ms window peak)\n");
        for (int ms : {2, 5, 10, 20, 50, 60, 80, 100, 150, 200, 300, 500, 700, 1000, 1500, 2000})
        {
            const uint32_t c = t0 + 48 + static_cast<uint32_t>(ms) * fs / 1000 + look;
            double po = 0, pi = 0;
            for (uint32_t i = c; i < c + 48 && i < n; ++i) { po = std::max(po, (double)std::abs(p.data[0][i])); pi = std::max(pi, (double)std::abs(in.data[0][i - look])); }
            std::printf("%d,%.3f\n", ms, 20 * std::log10(po / pi));
        }
        return 0;
    }
} // namespace

int main(int argc, char** argv)
{
    if (argc < 2) return 1;
    const std::string m = argv[1];
    if (m == "meter") return modeMeter();
    if (m == "tpk") return modeTpk();
    if (m == "limiter")
        return modeLimiter(static_cast<uint32_t>(std::atoi(argv[2])), static_cast<float>(std::atof(argv[3])), argv[4],
                           argc > 5 ? static_cast<uint32_t>(std::atoi(argv[5])) : 512U);
    if (m == "blend") return modeBlend();
    if (m == "layout") return modeLayout();
    if (m == "spatial") return modeSpatial();
    if (m == "ramp") return modeRamp();
    if (m == "ftz") return modeFtz();
    if (m == "xfeed") return modeXfeed();
    if (m == "release") return modeRelease();
    if (m == "normE")
    {
        const double speed = argc > 2 ? std::atof(argv[2]) : 10.0;
        runNorm("E_quiet_then_loud_userchange", {{40, -24, false, 0}, {30, -8, true, 0}}, speed);
        return 0;
    }
    if (m == "norm")
    {
        const double speed = argc > 2 ? std::atof(argv[2]) : 10.0;
        // A: loud (-8 LUFS) 40 s → user-initiated next track quiet (-24 LUFS) 40 s
        runNorm("A_loud_then_quiet_userchange", {{40, -8, false, 0}, {40, -24, true, 0}}, speed);
        // B: same, gapless roll (no publish → meter keeps integrating across tracks)
        runNorm("B_loud_then_quiet_gapless", {{40, -8, false, 0}, {40, -24, false, 0}}, speed);
        // C: classical: pp -38 LUFS 60 s then ff -14 LUFS 25 s with transients (single track)
        runNorm("C_classical_crescendo", {{60, -38, false, 0}, {25, -14, false, 3.0}}, speed);
        // D: quiet master (-24 LUFS, dynamic, peaks via transients) — steady-state limiting at default target
        runNorm("D_quiet_dynamic_master", {{60, -24, false, 4.0}}, speed);
        runNorm("E_quiet_then_loud_userchange", {{40, -24, false, 0}, {30, -8, true, 0}}, speed);
        return 0;
    }
    return 1;
}
