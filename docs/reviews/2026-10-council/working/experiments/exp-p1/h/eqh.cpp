// Panel P1 breaker harness: drives the REAL GraphicEQDesigner / EQTargets / EQModule.
#include "EQ/GraphicEQDesigner.h"
#include "EQ/EQModule.h"
#include "EQ/EQTargets.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <cmath>
#include <fenv.h>
using namespace AdaptiveSound;

static std::vector<float> readF32(const char* path) {
    FILE* f = fopen(path, "rb"); if (!f) { perror(path); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<float> v(n / 4); fread(v.data(), 4, v.size(), f); fclose(f); return v;
}
static std::vector<double> readF64(const char* path) {
    FILE* f = fopen(path, "rb"); if (!f) { perror(path); exit(2); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    std::vector<double> v(n / 8); fread(v.data(), 8, v.size(), f); fclose(f); return v;
}

int main(int argc, char** argv) {
    if (argc < 2) return 2;
    std::string mode = argv[1];
    if (mode == "design") {
        // design <rate> <cmds.f32 (N x 31)> <grid.f64> <out.f64>
        double rate = atof(argv[2]);
        auto cmds = readF32(argv[3]);
        auto grid = readF64(argv[4]);
        FILE* out = fopen(argv[5], "wb");
        auto* d = new GraphicEQDesigner();
        size_t n = cmds.size() / 31;
        std::vector<float> resp(grid.size());
        for (size_t r = 0; r < n; ++r) {
            GraphicEQDesign des{};
            bool ok = d->design(std::span<const float, 31>(cmds.data() + r * 31, 31), rate, des);
            double okd = ok ? 1.0 : 0.0;
            fwrite(&okd, 8, 1, out);
            fwrite(des.filterGainDb.data(), 8, 31, out);
            for (int b = 0; b < 31; ++b) fwrite(&des.bells[b].k, 8, 1, out);
            for (int b = 0; b < 31; ++b) fwrite(&des.bells[b].m1, 8, 1, out);
            fwrite(des.svfG.data(), 8, 31, out);
            for (size_t i = 0; i < grid.size(); ++i) {
                double v = ok ? GraphicEQDesigner::playedDb(des, grid[i]) : NAN;
                fwrite(&v, 8, 1, out);
            }
            // tau rule vs flat->this
            GraphicEQDesign flat{};
            auto ramps = EQTargets::rampsFor(flat, des);
            for (int b = 0; b < 31; ++b) { double t = ramps.band[b]; fwrite(&t, 8, 1, out); }
            double gt = ramps.gain; fwrite(&gt, 8, 1, out);
        }
        fclose(out);
        return 0;
    }
    if (mode == "ir") {
        // ir <rate> <channels> <block> <len> <cmd row f32 31> <out.f32 interleaved per channel>
        // Impulse response of EQModule (snapped) per channel; channel c gets impulse scaled (c+1).
        double rate = atof(argv[2]); int ch = atoi(argv[3]); int block = atoi(argv[4]); long len = atol(argv[5]);
        auto cmd = readF32(argv[6]);
        auto* d = new GraphicEQDesigner(); GraphicEQDesign des{};
        if (!d->design(std::span<const float, 31>(cmd.data(), 31), rate, des)) { fprintf(stderr, "design failed\n"); return 3; }
        auto params = EQTargets::toParams(des, 0.01f);
        EQModule m; m.initialize((uint32_t)rate, (uint32_t)block);
        std::vector<std::vector<float>> buf(ch, std::vector<float>(block));
        FILE* out = fopen(argv[7], "wb");
        fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
        for (long pos = 0; pos < len; pos += block) {
            int fr = (int)std::min<long>(block, len - pos);
            AudioBufferList* abl = (AudioBufferList*)calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer) * 8);
            abl->mNumberBuffers = ch;
            for (int c = 0; c < ch; ++c) {
                std::fill(buf[c].begin(), buf[c].end(), 0.f);
                if (pos == 0) buf[c][0] = 0.1f * (c + 1);
                abl->mBuffers[c].mData = buf[c].data(); abl->mBuffers[c].mNumberChannels = 1;
                abl->mBuffers[c].mDataByteSize = fr * 4;
            }
            m.update(params);
            m.process(MultichannelView::fromABL(abl, fr));
            for (int c = 0; c < ch; ++c) fwrite(buf[c].data(), 4, fr, out);
            free(abl);
        }
        fclose(out);
        return 0;
    }
    if (mode == "glide") {
        // glide <rate> <block> <len> <cmdA f32> <cmdB f32> <switchAt> <in.f32 mono> <out.f32>  (stereo: same in both)
        double rate = atof(argv[2]); int block = atoi(argv[3]); long len = atol(argv[4]);
        auto a = readF32(argv[5]); auto b = readF32(argv[6]); long sw = atol(argv[7]);
        auto x = readF32(argv[8]);
        auto* d = new GraphicEQDesigner(); GraphicEQDesign da{}, db{};
        if (!d->design(std::span<const float, 31>(a.data(), 31), rate, da)) return 3;
        if (!d->design(std::span<const float, 31>(b.data(), 31), rate, db)) return 3;
        auto pa = EQTargets::toParams(da, EQTargets::rampsFor(GraphicEQDesign{}, da));
        auto pb = EQTargets::toParams(db, EQTargets::rampsFor(da, db));
        EQModule m; m.initialize((uint32_t)rate, (uint32_t)block);
        std::vector<float> L(block), R(block);
        FILE* out = fopen(argv[9], "wb");
        fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
        for (long pos = 0; pos < len; pos += block) {
            int fr = (int)std::min<long>(block, len - pos);
            for (int i = 0; i < fr; ++i) { L[i] = x[pos + i]; R[i] = x[pos + i]; }
            AudioBufferList* abl = (AudioBufferList*)calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer) * 2);
            abl->mNumberBuffers = 2;
            abl->mBuffers[0].mData = L.data(); abl->mBuffers[1].mData = R.data();
            m.update(pos < sw ? pa : pb);
            m.process(MultichannelView::fromABL(abl, fr));
            fwrite(L.data(), 4, fr, out);
            free(abl);
        }
        fclose(out);
        return 0;
    }
        if (mode == "apply") {
        // apply <rate> <ch> <planar.f32> <cmd.f32> <out.f32>
        double rate = atof(argv[2]); int ch = atoi(argv[3]); auto x = readF32(argv[4]); auto cmd = readF32(argv[5]);
        size_t n = x.size() / ch; auto* d = new GraphicEQDesigner(); GraphicEQDesign des{};
        if (!d->design(std::span<const float, 31>(cmd.data(), 31), rate, des)) return 3;
        auto params = EQTargets::toParams(des, 0.01f);
        EQModule m; m.initialize((uint32_t)rate, 512); fesetenv(FE_DFL_DISABLE_DENORMS_ENV);
        std::vector<std::vector<float>> buf(ch, std::vector<float>(512));
        for (size_t pos = 0; pos < n; pos += 512) {
            int fr = (int)std::min<size_t>(512, n - pos);
            AudioBufferList* abl = (AudioBufferList*)calloc(1, sizeof(AudioBufferList) + sizeof(AudioBuffer) * 8);
            abl->mNumberBuffers = ch;
            for (int c = 0; c < ch; ++c) { std::copy_n(x.data() + c * n + pos, fr, buf[c].data()); abl->mBuffers[c].mData = buf[c].data(); }
            m.update(params); m.process(MultichannelView::fromABL(abl, fr));
            for (int c = 0; c < ch; ++c) std::copy_n(buf[c].data(), fr, x.data() + c * n + pos);
            free(abl);
        }
        FILE* out = fopen(argv[6], "wb"); fwrite(x.data(), 4, x.size(), out); fclose(out); return 0;
    }
    return 2;
}
