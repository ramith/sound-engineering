// TrackLoudnessTests.inc
//
// Sprint EQ, EQ1c part 1 — the track loudness profiler (Loudness/TrackLoudnessProfiler.h), the
// gated loudness-change predictor (Loudness/TrackLoudnessProfile.h) and their C-ABI
// (TrackLoudnessBridge.h). #included into Tests/DSPKernelNullTest.cpp AFTER
// LoudnessOracleTests.inc (it brings in the libebur128 header) and EqDesignerTests.inc (the
// built-in preset curves, the Tone macro, eqFlatCurveWith and eqMakeDesigner).
//
// THE MEASURED ΔL (the oracle). The programme runs offline through the EQ1a design — a
// double-precision vDSP biquad cascade built from the finished (g, k, m1) of each band, a path
// independent of the designer's read-back — and libebur128 (the BS.1770 reference, test-only)
// measures its integrated loudness before and after. The predictor never sees the filtered audio:
// it predicts from the profile and the played response alone.
//
// THE PROGRAMMES are synthesised here, deterministically (research/*.wav is not in git):
//   pink        stereo pink noise (JOS's 1/f filter), partially correlated, in 1–3 s sections at
//               0 / −6 / −14 / 0 / −30 / −3 / −90 dB, so both BS.1770 gates act; −18 LUFS
//   tonal 808   a sub-bass line of decaying, gliding, lightly saturated sines (58–98 Hz) with
//               clicks and quiet hats, gaps between notes; −16 LUFS
//   orchestral  sustained 4-note chords (harmonics to 30, h^−0.7, vibrato, swells) plus bright
//               5 kHz+ "air"; −20 LUFS
//   loud master the three mixed and soft-clipped (tanh) up to −9 LUFS
// The curves: the six built-in presets, +12 dB at 100 Hz and a Tone setting (B+6 Bo−3 P+4 A+6).
//
// Tests:
//   Loudness_Profile_MatchesEbur128     — the profile's own gated loudness == libebur128's
//                                         integrated loudness of the same PCM (≤ 0.01 LU)
//   Loudness_Predictor_Pink / _Tonal808 / _Orchestral / _LoudMaster
//                                       — predicted vs measured ΔL, 8 curves each: ≤ 0.15 dB
//   Loudness_Predictor_RatesAndLayouts  — 5.1 at 44.1 kHz through the C-ABI (layout tag → BS.1770
//                                         weights, LFE excluded), stereo at 96 and 192 kHz: ≤ 0.15
//   Loudness_Profile_NoWindow_ParsevalAndTonal
//                                       — THE PORT RULE: every block's bands sum to its time-domain
//                                         BS.1770 energy (Parseval, so no window); the production
//                                         bands == an independent double-precision rectangular
//                                         reference; on the tonal 808 with +12 @ 100 Hz the
//                                         production predictor is within 0.15 dB where the same
//                                         predictor on Hann-windowed blocks is not
//   Loudness_Profile_PrefixVsFull       — a prefix's blocks are the whole profile's first blocks,
//                                         bit for bit; 25 s prefix vs 60 s track ≤ 0.15 dB on
//                                         programmes whose arrangement does not change (an
//                                         arrangement change is logged — that is the refine's job)
//   Loudness_Profile_DecimationAndMemory
//                                       — the cap: stride doubling, kept blocks exact, the 6000-
//                                         block default cap on a 12-minute track, memory bounds
//   Loudness_Predictor_Properties       — flat = 0 dB exactly; uniform +6 dB = +6 dB; bands above
//                                         the output's Nyquist leave the sums; blockStep 4 ≈ 1
//   Loudness_Profiler_RejectsBadInput   — formats, non-finite PCM (consumes nothing), the
//                                         predictor's guards
//   Loudness_Abi_LifecycleAndGuards     — the C-ABI: NULLs, counts, non-finite, the life cycle,
//                                         and bit-equality with the C++ path
//   Loudness_Profile_SharedAcrossThreads — one profile, two predicting threads (tsan)
//   Profiler_Timing                     — 192 kHz × 8 channels (the worst format) and the
//                                         predictor on a 6000-block profile, against budgets
//                                         (serial)

namespace
{
    using TlChannels = std::vector<std::vector<float>>;
    using TlWeights = std::array<double, kMaxChannels>;

    constexpr double kTlRate44k = 44100.0;
    constexpr double kTlRate48k = 48000.0;
    constexpr double kTlRate96k = 96000.0;
    constexpr double kTlRate192k = 192000.0;
    constexpr double kTlAccuracyBoundDb = 0.15; // the brief's bound (corpus: 0.112)
    constexpr double kTlSourceLufsTolLu = 0.01; // profile vs libebur128, same PCM
    constexpr double kTlGateSeconds = 20.0;     // each accuracy programme
    constexpr uint32_t kTlEqBands = 31U;

    struct TlProgramme
    {
        double sampleRate = 0.0;
        TlChannels channels;

        [[nodiscard]] auto frames() const -> size_t
        {
            return channels.empty() ? 0U : channels.front().size();
        }
    };

    // ---------------------------------------------------------------------------------------
    // Signal building blocks
    // ---------------------------------------------------------------------------------------

    // A direct-form-I biquad in double (the programmes' fixed filters).
    struct TlBiquad
    {
        double b0 = 1.0;
        double b1 = 0.0;
        double b2 = 0.0;
        double a1 = 0.0;
        double a2 = 0.0;
        double x1 = 0.0;
        double x2 = 0.0;
        double y1 = 0.0;
        double y2 = 0.0;

        auto process(double input) -> double
        {
            const double output = (b0 * input) + (b1 * x1) + (b2 * x2) - (a1 * y1) - (a2 * y2);
            x2 = x1;
            x1 = input;
            y2 = y1;
            y1 = output;
            return output;
        }
    };

    // The RBJ cookbook 2nd-order Butterworth high-pass (Q = 1/√2).
    auto tlHighPass(double cutoffHz, double sampleRate) -> TlBiquad
    {
        const double w0 = 2.0 * std::numbers::pi * cutoffHz / sampleRate;
        const double alpha = std::sin(w0) / (2.0 * std::numbers::sqrt2 / 2.0);
        const double cosW0 = std::cos(w0);
        const double a0 = 1.0 + alpha;
        TlBiquad filter;
        filter.b0 = (1.0 + cosW0) / 2.0 / a0;
        filter.b1 = -(1.0 + cosW0) / a0;
        filter.b2 = filter.b0;
        filter.a1 = -2.0 * cosW0 / a0;
        filter.a2 = (1.0 - alpha) / a0;
        return filter;
    }

    // White Gaussian noise through J. O. Smith's 1/f ("pink") filter, −3 dB/octave within
    // ±0.5 dB over the audio band (Spectral Audio Signal Processing, "Synthesis of 1/f noise").
    auto tlPinkNoise(size_t frames, std::mt19937& rng) -> std::vector<double>
    {
        constexpr std::array<double, 4> kB = {0.049922035, -0.095993537, 0.050612699, -0.004408786};
        constexpr std::array<double, 4> kA = {1.0, -2.494956002, 2.017265875, -0.522189400};
        std::normal_distribution<double> white(0.0, 1.0);
        std::array<double, 4> input{};
        std::array<double, 4> output{};
        std::vector<double> pink(frames);
        for (double& sample : pink)
        {
            input = {white(rng), input[0], input[1], input[2]};
            const double value = (kB[0] * input[0]) + (kB[1] * input[1]) + (kB[2] * input[2]) +
                                 (kB[3] * input[3]) - (kA[1] * output[0]) - (kA[2] * output[1]) -
                                 (kA[3] * output[2]);
            output = {value, output[0], output[1], output[2]};
            sample = value;
        }
        return pink;
    }

    // Piecewise-constant section gains (each section 1–3 s, levels cycled), smoothed by a 20 ms
    // one-pole so the steps are not clicks.
    auto tlSectionEnvelope(size_t frames,
                           double sampleRate,
                           std::mt19937& rng,
                           std::span<const double> levelsDb) -> std::vector<double>
    {
        constexpr double kShortestSeconds = 1.0;
        constexpr double kLongestSeconds = 3.0;
        constexpr double kSmoothingSeconds = 0.02;
        std::uniform_real_distribution<double> length(kShortestSeconds, kLongestSeconds);
        std::vector<double> envelope(frames);
        const double pole = std::exp(-1.0 / (kSmoothingSeconds * sampleRate));
        double smoothed = 0.0;
        size_t frame = 0U;
        for (size_t section = 0U; frame < frames; ++section)
        {
            const double gain = std::pow(10.0, levelsDb[section % levelsDb.size()] / 20.0);
            const auto end =
                std::min(frames, frame + static_cast<size_t>(length(rng) * sampleRate));
            for (; frame < end; ++frame)
            {
                smoothed = gain + (pole * (smoothed - gain));
                envelope[frame] = smoothed;
            }
        }
        return envelope;
    }

    // libebur128's integrated loudness (LUFS) of planar audio, its default channel map (stereo
    // L R; six channels L R C LFE(unused) Ls Rs). NaN on any libebur128 error.
    template <class Sample>
    auto tlEbur128Lufs(const std::vector<std::vector<Sample>>& channels, double sampleRate)
        -> double
    {
        const auto count = static_cast<unsigned>(channels.size());
        ebur128_state* state =
            ebur128_init(count, static_cast<unsigned long>(sampleRate), EBUR128_MODE_I);
        if (state == nullptr)
        {
            return std::numeric_limits<double>::quiet_NaN();
        }
        constexpr size_t kChunk = 4096U;
        std::vector<double> interleaved(kChunk * count);
        const size_t frames = channels.front().size();
        bool ok = true;
        for (size_t start = 0U; start < frames && ok; start += kChunk)
        {
            const size_t chunk = std::min(kChunk, frames - start);
            for (size_t frame = 0U; frame < chunk; ++frame)
            {
                for (size_t ch = 0U; ch < count; ++ch)
                {
                    interleaved[(frame * count) + ch] =
                        static_cast<double>(channels[ch][start + frame]);
                }
            }
            ok = ebur128_add_frames_double(state, interleaved.data(), chunk) == EBUR128_SUCCESS;
        }
        double lufs = std::numeric_limits<double>::quiet_NaN();
        if (!ok || ebur128_loudness_global(state, &lufs) != EBUR128_SUCCESS)
        {
            lufs = std::numeric_limits<double>::quiet_NaN();
        }
        ebur128_destroy(&state);
        return lufs;
    }

    // Scale every channel so the programme measures `targetLufs` (libebur128).
    auto tlNormalise(TlProgramme& programme, double targetLufs) -> void
    {
        const double measured = tlEbur128Lufs(programme.channels, programme.sampleRate);
        const auto gain = static_cast<float>(std::pow(10.0, (targetLufs - measured) / 20.0));
        for (std::vector<float>& channel : programme.channels)
        {
            for (float& sample : channel)
            {
                sample *= gain;
            }
        }
    }

    // ---------------------------------------------------------------------------------------
    // The four programmes
    // ---------------------------------------------------------------------------------------

    auto tlPinkProgramme(double sampleRate, double seconds, uint32_t seed) -> TlProgramme
    {
        constexpr std::array<double, 7> kLevelsDb = {0.0, -6.0, -14.0, 0.0, -30.0, -3.0, -90.0};
        constexpr double kRightFromLeft = 0.7; // inter-channel correlation ≈ 0.7
        constexpr double kRightOwn = 0.714;
        constexpr double kTargetLufs = -18.0;
        std::mt19937 rng(seed);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        const std::vector<double> left = tlPinkNoise(frames, rng);
        const std::vector<double> right = tlPinkNoise(frames, rng);
        const std::vector<double> envelope = tlSectionEnvelope(frames, sampleRate, rng, kLevelsDb);
        TlProgramme programme{sampleRate, TlChannels(2U, std::vector<float>(frames))};
        for (size_t frame = 0U; frame < frames; ++frame)
        {
            programme.channels[0][frame] = static_cast<float>(left[frame] * envelope[frame]);
            programme.channels[1][frame] = static_cast<float>(
                ((kRightFromLeft * left[frame]) + (kRightOwn * right[frame])) * envelope[frame]);
        }
        tlNormalise(programme, kTargetLufs);
        return programme;
    }

    // A sub-bass line in the 808 idiom: each note a sine whose pitch drops from (1 + glide)·f0 to
    // f0 within ~30 ms, decays exponentially, is soft-saturated, and starts with a noise click;
    // quiet hats every half beat. The note pattern sits on the slopes and the centre of a +12 dB
    // bell at 100 Hz, where a windowed block spectrum goes wrong (verify-breaker M2).
    auto tl808Programme(double sampleRate, double seconds, uint32_t seed) -> TlProgramme
    {
        constexpr double kBeatSeconds = 60.0 / 100.0; // 100 bpm
        constexpr std::array<double, 6> kNotesHz = {97.71, 92.23, 58.10, 92.23, 87.05, 87.05};
        constexpr std::array<double, 4> kGapBeats = {3.0, 2.0, 1.0, 1.5};
        constexpr double kNoteBeats = 1.032;
        constexpr double kDecaySeconds = 0.678;
        constexpr double kGlide = 0.918;
        constexpr double kGlideSeconds = 0.03;
        constexpr double kDrive = 0.77;
        constexpr double kClickLevel = 0.3;
        constexpr double kClickSeconds = 0.004;
        constexpr double kHatCutoffHz = 7000.0;
        constexpr double kHatSeconds = 0.06;
        constexpr double kHatDecaySeconds = 0.015;
        constexpr double kHatLevelDb = -30.2;
        constexpr size_t kHatRightDelay = 53U;
        constexpr double kBassLevel = 0.3;
        constexpr double kTargetLufs = -16.0;
        std::mt19937 rng(seed);
        std::normal_distribution<double> noise(0.0, 1.0);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<double> bass(frames, 0.0);
        double start = 0.0;
        const double driveNorm = std::tanh(kDrive);
        for (size_t note = 0U; start < seconds; ++note)
        {
            const double baseHz = kNotesHz[note % kNotesHz.size()];
            const auto first = static_cast<size_t>(start * sampleRate);
            const size_t length = std::min(
                frames - first, static_cast<size_t>(kNoteBeats * kBeatSeconds * sampleRate));
            double phase = 0.0;
            for (size_t offset = 0U; offset < length; ++offset)
            {
                const double time = static_cast<double>(offset) / sampleRate;
                const double hz = baseHz * (1.0 + (kGlide * std::exp(-time / kGlideSeconds)));
                phase += 2.0 * std::numbers::pi * hz / sampleRate;
                const double tone = std::exp(-time / kDecaySeconds) * std::sin(phase);
                const double click = kClickLevel * std::exp(-time / kClickSeconds) * noise(rng);
                bass[first + offset] += (std::tanh(kDrive * tone) / driveNorm) + click;
            }
            start += kGapBeats[note % kGapBeats.size()] * kBeatSeconds;
        }
        std::vector<double> hats(frames, 0.0);
        TlBiquad hatFilter = tlHighPass(kHatCutoffHz, sampleRate);
        std::vector<double> hiss(frames);
        for (double& sample : hiss)
        {
            sample = hatFilter.process(noise(rng));
        }
        constexpr double kHatSpacingSeconds = kBeatSeconds / 2.0;
        for (size_t hit = 0U; static_cast<double>(hit) * kHatSpacingSeconds < seconds; ++hit)
        {
            const auto first =
                static_cast<size_t>(static_cast<double>(hit) * kHatSpacingSeconds * sampleRate);
            const size_t length =
                std::min(frames - first, static_cast<size_t>(kHatSeconds * sampleRate));
            for (size_t offset = 0U; offset < length; ++offset)
            {
                const double time = static_cast<double>(offset) / sampleRate;
                hats[first + offset] = hiss[first + offset] * std::exp(-time / kHatDecaySeconds);
            }
        }
        const double hatLevel = std::pow(10.0, kHatLevelDb / 20.0);
        TlProgramme programme{sampleRate, TlChannels(2U, std::vector<float>(frames))};
        for (size_t frame = 0U; frame < frames; ++frame)
        {
            const double delayedHat =
                (frame >= kHatRightDelay) ? hats[frame - kHatRightDelay] : 0.0;
            programme.channels[0][frame] =
                static_cast<float>((kBassLevel * bass[frame]) + (hatLevel * hats[frame]));
            programme.channels[1][frame] =
                static_cast<float>((kBassLevel * bass[frame]) + (hatLevel * delayedHat));
        }
        tlNormalise(programme, kTargetLufs);
        return programme;
    }

    // Sustained chords: four notes per chord, a new chord every 2.5 s held 3 s with a swell; each
    // note's harmonics h ≤ 29 (below 0.45·fs) at h^−0.7, even ones left, odd ones right, with a
    // 5.5 Hz vibrato. Each note is a wavetable (one period, linear interpolation). Plus bright
    // high-passed pink "air" at 0.4 × the tonal level.
    auto tlOrchestralProgramme(double sampleRate, double seconds, uint32_t seed) -> TlProgramme
    {
        using Chord = std::array<double, 4>;
        constexpr std::array<Chord, 4> kChordsHz = {
            {
                {196.0, 247.0, 294.0, 392.0},
                {220.0, 262.0, 330.0, 440.0},
                {175.0, 220.0, 262.0, 349.0},
                {247.0, 294.0, 370.0, 494.0},
            },
        };
        constexpr double kChordSeconds = 2.5;
        constexpr double kNoteSeconds = 3.0;
        constexpr double kSwellExponent = 1.5;
        constexpr int kMaxHarmonic = 29;
        constexpr double kHarmonicLimit = 0.45; // × fs
        constexpr double kHarmonicSlope = -0.7;
        constexpr double kVibratoHz = 5.5;
        constexpr double kVibratoDepth = 0.004;
        constexpr size_t kTableSize = 4096U;
        constexpr double kAirCutoffHz = 5000.0;
        constexpr double kAirShare = 0.4;
        constexpr double kTargetLufs = -20.0;
        std::mt19937 rng(seed);
        std::uniform_real_distribution<double> anyPhase(0.0, 2.0 * std::numbers::pi);
        const auto frames = static_cast<size_t>(seconds * sampleRate);
        std::vector<double> left(frames, 0.0);
        std::vector<double> right(frames, 0.0);
        std::vector<double> leftTable(kTableSize + 1U);
        std::vector<double> rightTable(kTableSize + 1U);
        for (size_t chord = 0U; static_cast<double>(chord) * kChordSeconds < seconds; ++chord)
        {
            const auto first =
                static_cast<size_t>(static_cast<double>(chord) * kChordSeconds * sampleRate);
            const size_t length =
                std::min(frames - first, static_cast<size_t>(kNoteSeconds * sampleRate));
            for (const double noteHz : kChordsHz[chord % kChordsHz.size()])
            {
                std::ranges::fill(leftTable, 0.0);
                std::ranges::fill(rightTable, 0.0);
                for (int harmonic = 1;
                     harmonic <= kMaxHarmonic && noteHz * harmonic < kHarmonicLimit * sampleRate;
                     ++harmonic)
                {
                    const double amplitude =
                        std::pow(static_cast<double>(harmonic), kHarmonicSlope);
                    const double offsetPhase = anyPhase(rng);
                    std::vector<double>& table = (harmonic % 2 == 0) ? leftTable : rightTable;
                    for (size_t index = 0U; index <= kTableSize; ++index)
                    {
                        table[index] +=
                            amplitude * std::sin((2.0 * std::numbers::pi * harmonic *
                                                  static_cast<double>(index) / kTableSize) +
                                                 offsetPhase);
                    }
                }
                const double vibratoPhase = anyPhase(rng);
                double cycle = 0.0; // position within the period, [0, 1)
                for (size_t offset = 0U; offset < length; ++offset)
                {
                    const double time = static_cast<double>(offset) / sampleRate;
                    const double swell =
                        std::pow(std::sin(std::numbers::pi * std::min(time / kNoteSeconds, 1.0)),
                                 kSwellExponent);
                    const double vibrato =
                        1.0 +
                        (kVibratoDepth *
                         std::sin((2.0 * std::numbers::pi * kVibratoHz * time) + vibratoPhase));
                    cycle += noteHz * vibrato / sampleRate;
                    cycle -= std::floor(cycle);
                    const double position = cycle * kTableSize;
                    const auto index = static_cast<size_t>(position);
                    const double fraction = position - static_cast<double>(index);
                    const auto lookup = [index, fraction](const std::vector<double>& table)
                    { return table[index] + (fraction * (table[index + 1U] - table[index])); };
                    left[first + offset] += swell * lookup(leftTable);
                    right[first + offset] += swell * lookup(rightTable);
                }
            }
        }
        // Bright "air": pink noise above ~5 kHz at kAirShare × the tonal RMS.
        std::vector<std::vector<double>> air = {tlPinkNoise(frames, rng), tlPinkNoise(frames, rng)};
        double tonalPower = 0.0;
        double airPower = 0.0;
        for (std::vector<double>& channel : air)
        {
            TlBiquad filter = tlHighPass(kAirCutoffHz, sampleRate);
            for (double& sample : channel)
            {
                sample = filter.process(sample);
                airPower += sample * sample;
            }
        }
        for (size_t frame = 0U; frame < frames; ++frame)
        {
            tonalPower += (left[frame] * left[frame]) + (right[frame] * right[frame]);
        }
        const double airGain = kAirShare * std::sqrt(tonalPower / airPower);
        TlProgramme programme{sampleRate, TlChannels(2U, std::vector<float>(frames))};
        for (size_t frame = 0U; frame < frames; ++frame)
        {
            programme.channels[0][frame] =
                static_cast<float>(left[frame] + (airGain * air[0][frame]));
            programme.channels[1][frame] =
                static_cast<float>(right[frame] + (airGain * air[1][frame]));
        }
        tlNormalise(programme, kTargetLufs);
        return programme;
    }

    // The three programmes mixed (808 + ½ pink + ½ orchestral) and driven into a tanh soft clip
    // until the master measures −9 LUFS — a loud, dense, saturated master.
    auto tlLoudMasterProgramme(double sampleRate, double seconds, uint32_t seed) -> TlProgramme
    {
        constexpr double kTargetLufs = -9.0;
        constexpr double kCeiling = 0.95;
        constexpr double kOtherShare = 0.5;
        constexpr int kGainIterations = 8;
        const TlProgramme bass = tl808Programme(sampleRate, seconds, seed);
        const TlProgramme pink = tlPinkProgramme(sampleRate, seconds, seed + 1U);
        const TlProgramme orchestra = tlOrchestralProgramme(sampleRate, seconds, seed + 2U);
        const size_t frames = bass.frames();
        TlChannels mix(2U, std::vector<float>(frames));
        for (size_t ch = 0U; ch < 2U; ++ch)
        {
            for (size_t frame = 0U; frame < frames; ++frame)
            {
                mix[ch][frame] = bass.channels[ch][frame] +
                                 static_cast<float>(kOtherShare) *
                                     (pink.channels[ch][frame] + orchestra.channels[ch][frame]);
            }
        }
        TlProgramme programme{sampleRate, mix};
        double drive = 1.0;
        for (int iteration = 0; iteration < kGainIterations; ++iteration)
        {
            for (size_t ch = 0U; ch < 2U; ++ch)
            {
                for (size_t frame = 0U; frame < frames; ++frame)
                {
                    programme.channels[ch][frame] = static_cast<float>(
                        kCeiling *
                        std::tanh(drive * static_cast<double>(mix[ch][frame]) / kCeiling));
                }
            }
            const double measured = tlEbur128Lufs(programme.channels, sampleRate);
            drive *= std::pow(10.0, (kTargetLufs - measured) / 20.0);
        }
        return programme;
    }

    // The 20 s, 48 kHz accuracy programmes, built once per process (thread-safe statics).
    auto tlGatePink() -> const TlProgramme&
    {
        static const TlProgramme programme = tlPinkProgramme(kTlRate48k, kTlGateSeconds, 11U);
        return programme;
    }
    auto tlGate808() -> const TlProgramme&
    {
        static const TlProgramme programme = tl808Programme(kTlRate48k, kTlGateSeconds, 12U);
        return programme;
    }
    auto tlGateOrchestral() -> const TlProgramme&
    {
        static const TlProgramme programme = tlOrchestralProgramme(kTlRate48k, kTlGateSeconds, 13U);
        return programme;
    }
    auto tlGateLoudMaster() -> const TlProgramme&
    {
        static const TlProgramme programme = tlLoudMasterProgramme(kTlRate48k, kTlGateSeconds, 14U);
        return programme;
    }

    // ---------------------------------------------------------------------------------------
    // Profiling, the EQ oracle and the curves
    // ---------------------------------------------------------------------------------------

    auto tlStereoWeights() -> TlWeights
    {
        TlWeights weights{};
        weights[0] = 1.0;
        weights[1] = 1.0;
        return weights;
    }

    auto tlFormat(const TlProgramme& programme, const TlWeights& weights)
        -> TrackLoudnessProfiler::Format
    {
        return {programme.sampleRate, static_cast<uint32_t>(programme.channels.size()), weights};
    }

    struct TlProfiles
    {
        std::shared_ptr<const TrackLoudnessProfile> prefix;
        std::shared_ptr<const TrackLoudnessProfile> whole;
    };

    // Feed a programme in irregular chunks (so hops and blocks straddle chunk edges), taking a
    // prefix snapshot exactly at `prefixFrames` when it is non-zero.
    auto tlProfile(const TlProgramme& programme,
                   const TlWeights& weights,
                   size_t prefixFrames = 0U,
                   uint32_t maxBlocks = TrackLoudnessProfiler::kDefaultMaxBlocks) -> TlProfiles
    {
        constexpr std::array<size_t, 5> kChunkPattern = {4096U, 1000U, 7777U, 333U, 16384U};
        TlProfiles result;
        auto profiler = TrackLoudnessProfiler::create(tlFormat(programme, weights), maxBlocks);
        if (!profiler)
        {
            return result;
        }
        std::vector<const float*> pointers(programme.channels.size());
        const size_t frames = programme.frames();
        size_t done = 0U;
        for (size_t step = 0U; done < frames; ++step)
        {
            size_t chunk = std::min(kChunkPattern[step % kChunkPattern.size()], frames - done);
            if (prefixFrames > done && prefixFrames < done + chunk)
            {
                chunk = prefixFrames - done;
            }
            for (size_t ch = 0U; ch < pointers.size(); ++ch)
            {
                pointers[ch] = programme.channels[ch].data() + done;
            }
            if (!profiler->feed(pointers, chunk))
            {
                return {};
            }
            done += chunk;
            if (done == prefixFrames)
            {
                result.prefix = profiler->snapshot();
            }
        }
        result.whole = profiler->finish();
        return result;
    }

    // The design's bells as one double-precision vDSP biquad cascade. Each bell is the bilinear
    // image of H(s) = 1 + m1·s / (s² + k·s + 1) with s = (1 − z⁻¹)/((1 + z⁻¹)·g), expanded from
    // the finished (g, k, m1) — independent of the designer's read-back formula.
    auto tlApplyDesign(const TlProgramme& programme, const GraphicEQDesign& design)
        -> std::vector<std::vector<double>>
    {
        constexpr size_t kCoefficients = 5U;
        std::vector<double> sections(kCoefficients * kTlEqBands);
        for (size_t band = 0U; band < kTlEqBands; ++band)
        {
            const double g = design.svfG[band];
            const double damping = design.bells[band].k;
            const double boosted = damping + design.bells[band].m1;
            const double a0 = 1.0 + (g * damping) + (g * g);
            double* section = sections.data() + (band * kCoefficients);
            section[0] = (1.0 + (g * boosted) + (g * g)) / a0;
            section[1] = ((2.0 * g * g) - 2.0) / a0;
            section[2] = (1.0 - (g * boosted) + (g * g)) / a0;
            section[3] = ((2.0 * g * g) - 2.0) / a0;
            section[4] = (1.0 - (g * damping) + (g * g)) / a0;
        }
        vDSP_biquad_SetupD setup = vDSP_biquad_CreateSetupD(sections.data(), kTlEqBands);
        const size_t frames = programme.frames();
        std::vector<std::vector<double>> output(programme.channels.size(),
                                                std::vector<double>(frames));
        std::vector<double> input(frames);
        std::vector<double> delay((2U * kTlEqBands) + 2U);
        for (size_t ch = 0U; ch < programme.channels.size(); ++ch)
        {
            std::ranges::transform(programme.channels[ch],
                                   input.begin(),
                                   [](float sample) { return static_cast<double>(sample); });
            std::ranges::fill(delay, 0.0);
            vDSP_biquadD(setup, delay.data(), input.data(), 1, output[ch].data(), 1, frames);
        }
        vDSP_biquad_DestroySetupD(setup);
        return output;
    }

    struct TlCurve
    {
        std::string name;
        EqCurve points;
    };

    auto tlGateCurves() -> std::vector<TlCurve>
    {
        constexpr std::array<const char*, 6> kPresetNames = {
            "Presence",
            "Clarity",
            "Warm",
            "Bass & Treble",
            "Vocal",
            "Bass Boost",
        };
        constexpr size_t kExtraCurves = 2U;
        std::vector<TlCurve> curves;
        curves.reserve(kPresetNames.size() + kExtraCurves);
        for (size_t preset = 0U; preset < kPresetNames.size(); ++preset)
        {
            curves.push_back({kPresetNames[preset], kEqPresetCurves[preset]});
        }
        curves.push_back({"+12 @ 100 Hz", eqFlatCurveWith(7U, 12.0F)});
        curves.push_back({"Tone B+6 Bo-3 P+4 A+6", eqToneCurve({6.0, -3.0, 0.0, 4.0, 6.0})});
        return curves;
    }

    // Measured ΔL (libebur128, EQ applied offline) for one curve; NaN on failure.
    auto tlMeasuredChangeDb(const TlProgramme& programme,
                            const GraphicEQDesign& design,
                            double sourceLufs) -> double
    {
        return tlEbur128Lufs(tlApplyDesign(programme, design), programme.sampleRate) - sourceLufs;
    }

    struct TlAccuracy
    {
        double worstDb = 0.0;
        double sourceDeltaLu = 0.0;
        double sourceLufs = 0.0;
        std::string table;
        std::string failure;
    };

    // Predicted vs measured ΔL for every curve on one programme (profiled by `profile`).
    auto tlAccuracy(const TlProgramme& programme,
                    const TrackLoudnessProfile& profile,
                    const std::vector<TlCurve>& curves) -> TlAccuracy
    {
        TlAccuracy result;
        result.sourceLufs = tlEbur128Lufs(programme.channels, programme.sampleRate);
        result.sourceDeltaLu = profile.sourceLoudnessLufs - result.sourceLufs;
        if (!std::isfinite(result.sourceLufs))
        {
            result.failure = "libebur128 failed on the source";
            return result;
        }
        auto designer = eqMakeDesigner();
        for (const TlCurve& curve : curves)
        {
            GraphicEQDesign design{};
            double predicted = 0.0;
            if (!designer->design(curve.points, programme.sampleRate, design) ||
                !predictLoudnessChangeDb(profile, design, 1U, predicted))
            {
                result.failure = std::format("{}: design or prediction failed", curve.name);
                return result;
            }
            const double measured = tlMeasuredChangeDb(programme, design, result.sourceLufs);
            const double error = predicted - measured;
            if (!std::isfinite(error))
            {
                result.failure = std::format("{}: non-finite error", curve.name);
                return result;
            }
            result.worstDb = std::max(result.worstDb, std::abs(error));
            result.table += std::format(
                "[info]     {:24} measured {:+7.3f}  predicted {:+7.3f}  "
                "error {:+.4f} dB\n",
                curve.name,
                measured,
                predicted,
                error);
        }
        return result;
    }

    auto tlRunAccuracyTest(const char* name, const char* label, const TlProgramme& programme)
        -> void
    {
        const TlProfiles profiles = tlProfile(programme, tlStereoWeights());
        if (!profiles.whole)
        {
            logFail(name, "the profiler produced no profile");
            return;
        }
        const TlAccuracy result = tlAccuracy(programme, *profiles.whole, tlGateCurves());
        if (!result.failure.empty())
        {
            logFail(name, result.failure);
            return;
        }
        logInfo(
            std::format("[info] {}: {} @ {:.1f} kHz, {:.2f} LUFS, {} blocks; worst |predicted "
                        "− measured| {:.4f} dB (bound {})\n{}",
                        name,
                        label,
                        programme.sampleRate / 1000.0,
                        result.sourceLufs,
                        profiles.whole->blockCount,
                        result.worstDb,
                        kTlAccuracyBoundDb,
                        result.table));
        if (!(std::abs(result.sourceDeltaLu) <= kTlSourceLufsTolLu))
        {
            logFail(name,
                    std::format("profile loudness differs from libebur128 by {:+.4f} LU",
                                result.sourceDeltaLu));
            return;
        }
        if (!(result.worstDb <= kTlAccuracyBoundDb))
        {
            logFail(name,
                    std::format("worst prediction error {:.4f} dB exceeds {} dB",
                                result.worstDb,
                                kTlAccuracyBoundDb));
            return;
        }
        logPass(name);
    }

    // ---------------------------------------------------------------------------------------
    // An independent block-spectral reference (double precision, optional Hann window)
    // ---------------------------------------------------------------------------------------

    struct TlReference
    {
        TrackLoudnessProfile profile;         // its band powers, ready for the predictor
        std::vector<double> timeDomainEnergy; // per block: Σ_ch G·Σ y² / L, no FFT at all
    };

    // Every channel of the programme through its own K-weighting filter, in double.
    auto tlKWeighted(const TlProgramme& programme) -> std::vector<std::vector<double>>
    {
        std::vector<std::vector<double>> weighted;
        weighted.reserve(programme.channels.size());
        for (const std::vector<float>& channel : programme.channels)
        {
            LufsKWeight filter = makeKWeighting(programme.sampleRate);
            std::vector<double>& out = weighted.emplace_back(channel.size());
            std::ranges::transform(channel,
                                   out.begin(),
                                   [&filter](float sample)
                                   { return filter.processSample(static_cast<double>(sample)); });
        }
        return weighted;
    }

    // The block window: rectangular, or the symmetric Hann (numpy's hanning) scaled to unit mean
    // square so that only its SHAPE differs from the rectangle.
    auto tlAnalysisWindow(size_t length, bool hann) -> std::vector<double>
    {
        std::vector<double> window(length, 1.0);
        if (!hann)
        {
            return window;
        }
        double meanSquare = 0.0;
        for (size_t n = 0U; n < length; ++n)
        {
            window[n] = 0.5 - (0.5 * std::cos(2.0 * std::numbers::pi * static_cast<double>(n) /
                                              static_cast<double>(length - 1U)));
            meanSquare += window[n] * window[n];
        }
        const double scale = 1.0 / std::sqrt(meanSquare / static_cast<double>(length));
        for (double& value : window)
        {
            value *= scale;
        }
        return window;
    }

    // Bin k (at k·fs/N, k = 0 … N/2) belongs to the band whose index is the number of grid edges
    // at or below its frequency — numpy.digitize, as the oracle bins.
    auto tlBinBands(size_t fftLength, double rate) -> std::vector<uint32_t>
    {
        const uint32_t bands = TrackLoudness::bandCount(rate);
        std::vector<uint32_t> binBand((fftLength / 2U) + 1U);
        for (size_t bin = 0U; bin < binBand.size(); ++bin)
        {
            const double hz = static_cast<double>(bin) * rate / static_cast<double>(fftLength);
            uint32_t band = 0U;
            while (band + 1U < bands && TrackLoudness::edgeHz(band) <= hz)
            {
                ++band;
            }
            binBand[bin] = band;
        }
        return binBand;
    }

    // One double-precision real FFT and its scratch.
    struct TlDoubleFft
    {
        explicit TlDoubleFft(size_t length)
            : fftLength(length),
              setup(vDSP_DFT_zrop_CreateSetupD(
                  nullptr, static_cast<vDSP_Length>(length), vDSP_DFT_FORWARD)),
              block(length, 0.0),
              evenIn(length / 2U),
              oddIn(length / 2U),
              realOut(length / 2U),
              imagOut(length / 2U)
        {
        }
        ~TlDoubleFft()
        {
            vDSP_DFT_DestroySetupD(setup);
        }
        TlDoubleFft(const TlDoubleFft&) = delete;
        TlDoubleFft& operator=(const TlDoubleFft&) = delete;
        TlDoubleFft(TlDoubleFft&&) = delete;
        TlDoubleFft& operator=(TlDoubleFft&&) = delete;

        // Add G·(the one-sided power of `samples` × `window`, zero-padded) into `bandSum`.
        // vDSP's output is 2·X: an interior bin carries 2|X|² = |out|²/2, DC and Nyquist
        // |X|² = |out|²/4.
        auto accumulate(const double* samples,
                        const std::vector<double>& window,
                        double weight,
                        const std::vector<uint32_t>& binBand,
                        std::vector<double>& bandSum) -> void
        {
            const size_t half = fftLength / 2U;
            for (size_t n = 0U; n < window.size(); ++n)
            {
                block[n] = samples[n] * window[n];
            }
            for (size_t n = 0U; n < half; ++n)
            {
                evenIn[n] = block[2U * n];
                oddIn[n] = block[(2U * n) + 1U];
            }
            vDSP_DFT_ExecuteD(setup, evenIn.data(), oddIn.data(), realOut.data(), imagOut.data());
            bandSum[binBand[0]] += weight * realOut[0] * realOut[0] / 4.0;
            bandSum[binBand[half]] += weight * imagOut[0] * imagOut[0] / 4.0;
            for (size_t bin = 1U; bin < half; ++bin)
            {
                bandSum[binBand[bin]] +=
                    weight * ((realOut[bin] * realOut[bin]) + (imagOut[bin] * imagOut[bin])) / 2.0;
            }
        }

        size_t fftLength;
        vDSP_DFT_SetupD setup;
        std::vector<double> block; // [window.size(), fftLength) stays zero
        std::vector<double> evenIn;
        std::vector<double> oddIn;
        std::vector<double> realOut;
        std::vector<double> imagOut;
    };

    // Every 100 ms block of the K-weighted programme, (Hann-)windowed, zero-padded, through a
    // double-precision real FFT, binned on the same 1/24-octave grid; plus each block's
    // time-domain energy, which needs no FFT at all.
    auto tlReferenceProfile(const TlProgramme& programme, const TlWeights& weights, bool hann)
        -> TlReference
    {
        const double rate = programme.sampleRate;
        const auto hop = static_cast<size_t>(std::lround(0.1 * rate));
        const size_t length = 4U * hop;
        const uint32_t bands = TrackLoudness::bandCount(rate);
        const size_t frames = programme.frames();
        const size_t blocks = (frames < length) ? 0U : 1U + ((frames - length) / hop);
        const std::vector<std::vector<double>> weighted = tlKWeighted(programme);
        const std::vector<double> window = tlAnalysisWindow(length, hann);
        TlDoubleFft fft(std::bit_ceil(length));
        const std::vector<uint32_t> binBand = tlBinBands(fft.fftLength, rate);
        const double normaliser = static_cast<double>(length) * static_cast<double>(fft.fftLength);

        std::vector<double> bandSum(bands);
        TlReference reference;
        reference.timeDomainEnergy.resize(blocks);
        reference.profile.bandPower.resize(blocks * bands);
        for (size_t index = 0U; index < blocks; ++index)
        {
            std::ranges::fill(bandSum, 0.0);
            double energy = 0.0;
            for (size_t ch = 0U; ch < weighted.size(); ++ch)
            {
                if (!(weights[ch] > 0.0))
                {
                    continue;
                }
                const double* samples = weighted[ch].data() + (index * hop);
                for (size_t n = 0U; n < length; ++n)
                {
                    energy += weights[ch] * samples[n] * samples[n];
                }
                fft.accumulate(samples, window, weights[ch], binBand, bandSum);
            }
            reference.timeDomainEnergy[index] = energy / static_cast<double>(length);
            std::ranges::transform(
                bandSum,
                reference.profile.bandPower.begin() + static_cast<std::ptrdiff_t>(index * bands),
                [normaliser](double sum) { return static_cast<float>(sum / normaliser); });
        }
        reference.profile.sampleRate = rate;
        reference.profile.channelCount = static_cast<uint32_t>(weighted.size());
        reference.profile.bandCount = bands;
        reference.profile.blockCount = static_cast<uint32_t>(blocks);
        reference.profile.analysedFrames = frames;
        reference.profile.wholeTrack = true;
        reference.profile.sourceLoudnessLufs = profileLoudnessLufs(reference.profile);
        return reference;
    }

    // Σ_b P_j(b) in double.
    auto tlBlockEnergy(const TrackLoudnessProfile& profile, uint32_t index) -> double
    {
        double energy = 0.0;
        for (const float power : profile.block(index))
        {
            energy += static_cast<double>(power);
        }
        return energy;
    }

    // Predicted ΔL for one curve, or NaN.
    auto tlPredict(const TrackLoudnessProfile& profile,
                   GraphicEQDesigner& designer,
                   const EqCurve& curve,
                   double outputRate,
                   uint32_t blockStep = 1U) -> double
    {
        GraphicEQDesign design{};
        double change = std::numeric_limits<double>::quiet_NaN();
        if (!designer.design(curve, outputRate, design) ||
            !predictLoudnessChangeDb(profile, design, blockStep, change))
        {
            return std::numeric_limits<double>::quiet_NaN();
        }
        return change;
    }
} // namespace

// ---------------------------------------------------------------------------
// Loudness_Profile_MatchesEbur128 — the profile's gated loudness (from its band sums) equals
// libebur128's integrated loudness of the same PCM, on all four programmes.
// ---------------------------------------------------------------------------
static auto testLoudnessProfileMatchesEbur128() -> void
{
    static const char* const kName = "Loudness_Profile_MatchesEbur128";
    const std::array<std::pair<const char*, const TlProgramme*>, 4> programmes = {
        {
            {"pink", &tlGatePink()},
            {"tonal 808", &tlGate808()},
            {"orchestral", &tlGateOrchestral()},
            {"loud master", &tlGateLoudMaster()},
        },
    };
    std::string report = std::format("[info] {}:", kName);
    for (const auto& [label, programme] : programmes)
    {
        const TlProfiles profiles = tlProfile(*programme, tlStereoWeights());
        const double reference = tlEbur128Lufs(programme->channels, programme->sampleRate);
        if (!profiles.whole || !std::isfinite(reference))
        {
            logFail(kName, std::format("{}: no profile or no libebur128 reading", label));
            return;
        }
        const double delta = profiles.whole->sourceLoudnessLufs - reference;
        report += std::format(" {} {:.3f} LUFS ({:+.5f})", label, reference, delta);
        if (!(std::abs(delta) <= kTlSourceLufsTolLu))
        {
            logFail(kName,
                    std::format("{}: profile {:.4f} vs libebur128 {:.4f} LUFS",
                                label,
                                profiles.whole->sourceLoudnessLufs,
                                reference));
            return;
        }
    }
    logInfo(report + std::format(" (≤ {} LU)\n", kTlSourceLufsTolLu));
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Predictor_* — predicted vs measured ΔL, 8 curves per programme, ≤ 0.15 dB.
// ---------------------------------------------------------------------------
static auto testLoudnessPredictorPink() -> void
{
    tlRunAccuracyTest("Loudness_Predictor_Pink", "gated pink noise", tlGatePink());
}

static auto testLoudnessPredictorTonal808() -> void
{
    tlRunAccuracyTest("Loudness_Predictor_Tonal808", "tonal 808 bass line", tlGate808());
}

static auto testLoudnessPredictorOrchestral() -> void
{
    tlRunAccuracyTest("Loudness_Predictor_Orchestral", "bright orchestral", tlGateOrchestral());
}

static auto testLoudnessPredictorLoudMaster() -> void
{
    tlRunAccuracyTest("Loudness_Predictor_LoudMaster", "loud −9 LUFS master", tlGateLoudMaster());
}

namespace
{
    // One accuracy sweep's outcome: the worst |predicted − measured| and the report lines.
    struct TlSweep
    {
        double worstDb = 0.0;
        std::string report;
        std::string failure;
    };

    // 5.1 in MPEG_5_1_A order (L R C LFE Ls Rs): gated pink on L/R, the 808 line on C, a loud
    // 40 Hz tone on the LFE (weight 0 — it must not count), the orchestral pair on Ls/Rs.
    auto tlSurroundProgramme(double seconds) -> TlProgramme
    {
        constexpr double kLfeHz = 40.0;
        constexpr double kLfeLevel = 0.5;
        const TlProgramme pink = tlPinkProgramme(kTlRate44k, seconds, 21U);
        const TlProgramme bass = tl808Programme(kTlRate44k, seconds, 22U);
        const TlProgramme strings = tlOrchestralProgramme(kTlRate44k, seconds, 23U);
        std::vector<float> lfe(pink.frames());
        for (size_t frame = 0U; frame < lfe.size(); ++frame)
        {
            lfe[frame] =
                static_cast<float>(kLfeLevel * std::sin(2.0 * std::numbers::pi * kLfeHz *
                                                        static_cast<double>(frame) / kTlRate44k));
        }
        return {
            kTlRate44k,
            {
                pink.channels[0],
                pink.channels[1],
                bass.channels[0],
                lfe,
                strings.channels[0],
                strings.channels[1],
            },
        };
    }

    // Profile a programme end to end through the C-ABI (create with `layoutTag`, feed in 100 ms
    // chunks, finish full). NULL on any failure.
    auto tlAbiProfile(const TlProgramme& programme, AudioChannelLayoutTag layoutTag)
        -> AsLoudnessProfile*
    {
        const auto channels = static_cast<uint32_t>(programme.channels.size());
        AsLoudnessProfiler* profiler =
            asLoudnessProfilerCreate(programme.sampleRate, channels, layoutTag);
        if (profiler == nullptr)
        {
            return nullptr;
        }
        const auto chunk = static_cast<size_t>(std::lround(0.1 * programme.sampleRate));
        std::vector<const float*> pointers(channels);
        bool fed = true;
        for (size_t done = 0U; done < programme.frames() && fed; done += chunk)
        {
            for (size_t ch = 0U; ch < channels; ++ch)
            {
                pointers[ch] = programme.channels[ch].data() + done;
            }
            fed = asLoudnessProfilerFeed(
                profiler,
                pointers.data(),
                channels,
                static_cast<uint32_t>(std::min(chunk, programme.frames() - done)));
        }
        AsLoudnessProfile* whole = fed ? asLoudnessProfilerFinishFull(profiler) : nullptr;
        asLoudnessProfilerDestroy(profiler);
        return whole;
    }

    // The 5.1 case: the profile's loudness and each curve's predicted ΔL (via the C-ABI) against
    // libebur128 with its default 5.1 map (LFE unused, surrounds +1.5 dB).
    auto tlSurroundSweep(const std::vector<TlCurve>& curves) -> TlSweep
    {
        constexpr double kSeconds = 12.0;
        TlSweep sweep;
        const TlProgramme surround = tlSurroundProgramme(kSeconds);
        AsLoudnessProfile* whole = tlAbiProfile(surround, kAudioChannelLayoutTag_MPEG_5_1_A);
        AsEqDesigner* designer = asEqDesignerCreate();
        AsLoudnessProfileInfo info{};
        const double sourceLufs = tlEbur128Lufs(surround.channels, kTlRate44k);
        if (designer == nullptr || !asLoudnessProfileGetInfo(whole, &info))
        {
            sweep.failure = "the 5.1 C-ABI profile failed";
        }
        const double delta = info.sourceLoudnessLufs - sourceLufs;
        sweep.report = std::format(
            "[info]   5.1 @ 44.1 kHz: {:.3f} LUFS (profile {:+.4f} LU; "
            "LFE excluded by the MPEG_5_1_A weights)\n",
            sourceLufs,
            delta);
        if (sweep.failure.empty() && !(std::abs(delta) <= kTlSourceLufsTolLu))
        {
            sweep.failure = std::format("5.1 profile loudness off libebur128 by {:+.4f}", delta);
        }
        auto cppDesigner = eqMakeDesigner();
        for (size_t index = 0U; index < curves.size() && sweep.failure.empty(); ++index)
        {
            const TlCurve& curve = curves[index];
            double predicted = 0.0;
            GraphicEQDesign design{};
            if (!asLoudnessPredictChangeDb(
                    whole, designer, curve.points.data(), kTlEqBands, kTlRate44k, &predicted) ||
                !cppDesigner->design(curve.points, kTlRate44k, design))
            {
                sweep.failure = std::format("5.1 {}: prediction failed", curve.name);
                break;
            }
            const double measured = tlMeasuredChangeDb(surround, design, sourceLufs);
            sweep.worstDb = std::max(sweep.worstDb, std::abs(predicted - measured));
            sweep.report += std::format(
                "[info]     {:24} measured {:+7.3f}  predicted {:+7.3f}  "
                "error {:+.4f}\n",
                curve.name,
                measured,
                predicted,
                predicted - measured);
        }
        asLoudnessProfileDestroy(whole);
        asEqDesignerDestroy(designer);
        return sweep;
    }

    // A stereo pink programme at a high rate, through the C++ path.
    auto tlHiResSweep(double rate, const std::vector<TlCurve>& curves) -> TlSweep
    {
        constexpr double kSeconds = 8.0;
        TlSweep sweep;
        const TlProgramme hiRes = tlPinkProgramme(rate, kSeconds, 24U);
        const TlProfiles profiles = tlProfile(hiRes, tlStereoWeights());
        if (!profiles.whole)
        {
            sweep.failure = std::format("no profile at {} Hz", rate);
            return sweep;
        }
        const TlAccuracy result = tlAccuracy(hiRes, *profiles.whole, curves);
        sweep.failure = result.failure;
        sweep.worstDb = result.worstDb;
        sweep.report =
            std::format("[info]   stereo pink @ {:.0f} kHz, {} bands (profile {:+.4f} LU):\n{}",
                        rate / 1000.0,
                        profiles.whole->bandCount,
                        result.sourceDeltaLu,
                        result.table);
        if (sweep.failure.empty() && !(std::abs(result.sourceDeltaLu) <= kTlSourceLufsTolLu))
        {
            sweep.failure = std::format("profile loudness off libebur128 at {} Hz", rate);
        }
        return sweep;
    }
} // namespace

// ---------------------------------------------------------------------------
// Loudness_Predictor_RatesAndLayouts — 5.1 at 44.1 kHz end to end through the C-ABI (the layout
// tag sets the BS.1770 weights; a loud LFE must not count), and stereo at 96 and 192 kHz.
// ---------------------------------------------------------------------------
static auto testLoudnessPredictorRatesAndLayouts() -> void
{
    static const char* const kName = "Loudness_Predictor_RatesAndLayouts";
    const std::vector<TlCurve> allCurves = tlGateCurves();
    const std::vector<TlCurve> curves = {allCurves[2], allCurves[3], allCurves[6], allCurves[7]};
    const std::array<TlSweep, 3> sweeps = {
        tlSurroundSweep(curves),
        tlHiResSweep(kTlRate96k, curves),
        tlHiResSweep(kTlRate192k, curves),
    };
    std::string report = std::format("[info] {}:\n", kName);
    double worst = 0.0;
    for (const TlSweep& sweep : sweeps)
    {
        if (!sweep.failure.empty())
        {
            logFail(kName, sweep.failure);
            return;
        }
        report += sweep.report;
        worst = std::max(worst, sweep.worstDb);
    }
    logInfo(report + std::format("[info]   worst |predicted − measured| {:.4f} dB (bound {})\n",
                                 worst,
                                 kTlAccuracyBoundDb));
    if (!(worst <= kTlAccuracyBoundDb))
    {
        logFail(kName, std::format("worst error {:.4f} dB exceeds {}", worst, kTlAccuracyBoundDb));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Profile_NoWindow_ParsevalAndTonal — the port rule (amendments item 3): the block FFT
// uses NO window.
// ---------------------------------------------------------------------------
static auto testLoudnessProfileNoWindow() -> void
{
    static const char* const kName = "Loudness_Profile_NoWindow_ParsevalAndTonal";
    constexpr double kParsevalTolerance = 1e-5; // float FFT vs the double time-domain sum
    constexpr double kBandTolerance = 1e-5;     // per band, relative to the block's energy
    const TlProgramme& programme = tlGate808();
    const TlWeights weights = tlStereoWeights();
    const TlProfiles profiles = tlProfile(programme, weights);
    const TlReference rectangular = tlReferenceProfile(programme, weights, false);
    const TlReference hann = tlReferenceProfile(programme, weights, true);
    if (!profiles.whole || profiles.whole->blockCount != rectangular.profile.blockCount)
    {
        logFail(kName, "the profile's block count differs from BS.1770's");
        return;
    }
    const TrackLoudnessProfile& profile = *profiles.whole;
    // (1) Parseval: each block's bands add up to its time-domain BS.1770 energy — true only of
    // the rectangular window. (2) The bands match an independent double-precision reference.
    double worstParseval = 0.0;
    double worstHannParseval = 0.0;
    double worstBand = 0.0;
    for (uint32_t index = 0U; index < profile.blockCount; ++index)
    {
        const double timeDomain = rectangular.timeDomainEnergy[index];
        if (!(timeDomain > 0.0))
        {
            continue;
        }
        worstParseval = std::max(worstParseval,
                                 std::abs(tlBlockEnergy(profile, index) - timeDomain) / timeDomain);
        worstHannParseval =
            std::max(worstHannParseval,
                     std::abs(tlBlockEnergy(hann.profile, index) - timeDomain) / timeDomain);
        const std::span<const float> mine = profile.block(index);
        const std::span<const float> theirs = rectangular.profile.block(index);
        for (size_t band = 0U; band < mine.size(); ++band)
        {
            worstBand = std::max(
                worstBand,
                std::abs(static_cast<double>(mine[band]) - static_cast<double>(theirs[band])) /
                    timeDomain);
        }
    }
    // (3) The tonal case: +12 dB at 100 Hz on the 808 line, the production predictor vs the same
    // predictor on Hann-windowed blocks, both against the measured change.
    auto designer = eqMakeDesigner();
    const EqCurve bell = eqFlatCurveWith(7U, 12.0F);
    GraphicEQDesign design{};
    double mineDb = 0.0;
    double hannDb = 0.0;
    if (!designer->design(bell, programme.sampleRate, design) ||
        !predictLoudnessChangeDb(profile, design, 1U, mineDb) ||
        !predictLoudnessChangeDb(hann.profile, design, 1U, hannDb))
    {
        logFail(kName, "the tonal prediction failed");
        return;
    }
    const double sourceLufs = tlEbur128Lufs(programme.channels, programme.sampleRate);
    const double measured = tlMeasuredChangeDb(programme, design, sourceLufs);
    const double mineError = mineDb - measured;
    const double hannError = hannDb - measured;
    logInfo(
        std::format("[info] {}: Parseval worst {:.2e} (≤ {:.0e}; a Hann-windowed block is off "
                    "by up to {:.1f} %); bands vs the double reference {:.2e} (≤ {:.0e}); "
                    "tonal 808, +12 @ 100 Hz: measured {:+.3f}, no window {:+.4f} (error "
                    "{:+.4f}), Hann {:+.4f} (error {:+.4f}) dB\n",
                    kName,
                    worstParseval,
                    kParsevalTolerance,
                    100.0 * worstHannParseval,
                    worstBand,
                    kBandTolerance,
                    measured,
                    mineDb,
                    mineError,
                    hannDb,
                    hannError));
    if (!(worstParseval <= kParsevalTolerance) || !(worstBand <= kBandTolerance))
    {
        logFail(kName, "the block bands do not add up to the block energy: a window is applied");
        return;
    }
    if (!(std::abs(mineError) <= kTlAccuracyBoundDb))
    {
        logFail(kName, std::format("the no-window prediction errs {:+.4f} dB", mineError));
        return;
    }
    if (!(std::abs(hannError) > kTlAccuracyBoundDb))
    {
        logFail(kName,
                std::format("the Hann control errs only {:+.4f} dB: the tonal case no longer "
                            "discriminates the window",
                            hannError));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Profile_PrefixVsFull — the prefix is the whole profile's start, bit for bit, and a
// 25 s prefix predicts a 60 s track within the predictor's own 0.15 dB budget when the
// arrangement does not change. How far a prefix strays is a property of the music, not of the
// code: the 808 line repeats only every 13.5 s, so 25 s holds < 2 periods (0.103 dB); on the real
// corpus a 30 s running estimate strayed up to 0.37 dB (engine-plan §4.3, s4) — which is why the
// prefix is refined to the whole track.
// ---------------------------------------------------------------------------
static auto testLoudnessProfilePrefixVsFull() -> void
{
    static const char* const kName = "Loudness_Profile_PrefixVsFull";
    constexpr double kTrackSeconds = 60.0;
    constexpr double kPrefixSeconds = 25.0;
    constexpr double kPrefixToleranceDb = kTlAccuracyBoundDb;
    const auto prefixFrames = static_cast<size_t>(kPrefixSeconds * kTlRate48k);
    const std::vector<TlCurve> curves = tlGateCurves();
    auto designer = eqMakeDesigner();
    const std::array<std::pair<const char*, TlProgramme>, 3> programmes = {
        {
            {"pink", tlPinkProgramme(kTlRate48k, kTrackSeconds, 31U)},
            {"tonal 808", tl808Programme(kTlRate48k, kTrackSeconds, 32U)},
            {"orchestral", tlOrchestralProgramme(kTlRate48k, kTrackSeconds, 33U)},
        },
    };
    std::string report = std::format("[info] {}: 25 s prefix vs the 60 s track, worst |Δ|:", kName);
    double worst = 0.0;
    for (const auto& [label, programme] : programmes)
    {
        const TlProfiles profiles = tlProfile(programme, tlStereoWeights(), prefixFrames);
        if (!profiles.prefix || !profiles.whole)
        {
            logFail(kName, std::format("{}: no prefix or whole profile", label));
            return;
        }
        const TrackLoudnessProfile& prefix = *profiles.prefix;
        const TrackLoudnessProfile& whole = *profiles.whole;
        const bool sameStart =
            prefix.bandCount == whole.bandCount && prefix.blockCount < whole.blockCount &&
            std::equal(
                prefix.bandPower.begin(),
                prefix.bandPower.end(),
                whole.bandPower.begin(),
                [](float lhs, float rhs)
                { return std::bit_cast<uint32_t>(lhs) == std::bit_cast<uint32_t>(rhs); });
        if (!sameStart || prefix.wholeTrack || !whole.wholeTrack ||
            prefix.analysedFrames != prefixFrames || whole.analysedFrames != programme.frames() ||
            prefix.blockStrideHops != 1U)
        {
            logFail(kName, std::format("{}: the prefix is not the whole profile's start", label));
            return;
        }
        double programmeWorst = 0.0;
        for (const TlCurve& curve : curves)
        {
            const double fromPrefix = tlPredict(prefix, *designer, curve.points, kTlRate48k);
            const double fromWhole = tlPredict(whole, *designer, curve.points, kTlRate48k);
            programmeWorst = std::max(programmeWorst, std::abs(fromPrefix - fromWhole));
        }
        report += std::format(" {} {:.4f} ({} of {} blocks)",
                              label,
                              programmeWorst,
                              prefix.blockCount,
                              whole.blockCount);
        worst = std::max(worst, programmeWorst);
    }
    // An arrangement change — a quiet orchestral intro, then the loud master — is what the
    // whole-track refine is for. Logged, not bounded.
    const TlProgramme intro = tlOrchestralProgramme(kTlRate48k, kTrackSeconds / 2.0, 34U);
    const TlProgramme drop = tlLoudMasterProgramme(kTlRate48k, kTrackSeconds / 2.0, 35U);
    TlProgramme changing{kTlRate48k, intro.channels};
    for (size_t ch = 0U; ch < 2U; ++ch)
    {
        changing.channels[ch].insert(
            changing.channels[ch].end(), drop.channels[ch].begin(), drop.channels[ch].end());
    }
    const TlProfiles changed = tlProfile(changing, tlStereoWeights(), prefixFrames);
    double changeWorst = 0.0;
    for (const TlCurve& curve : curves)
    {
        if (changed.prefix && changed.whole)
        {
            changeWorst =
                std::max(changeWorst,
                         std::abs(tlPredict(*changed.prefix, *designer, curve.points, kTlRate48k) -
                                  tlPredict(*changed.whole, *designer, curve.points, kTlRate48k)));
        }
    }
    logInfo(report + std::format(" dB (≤ {}); an intro → drop arrangement change: {:.3f} dB "
                                 "(logged: the refine's job)\n",
                                 kPrefixToleranceDb,
                                 changeWorst));
    if (!(worst <= kPrefixToleranceDb))
    {
        logFail(
            kName,
            std::format("prefix vs whole differs by {:.4f} dB (> {})", worst, kPrefixToleranceDb));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Profile_DecimationAndMemory — memory and cost bounded by duration.
// ---------------------------------------------------------------------------
static auto testLoudnessProfileDecimationAndMemory() -> void
{
    static const char* const kName = "Loudness_Profile_DecimationAndMemory";
    // (1) A 64-block cap on the 20 s pink programme (197 blocks: k = 0 … 196). The cap is full at
    // k = 64 (→ stride 2, 32 blocks) and again at k = 128 (→ stride 4, 32 blocks); then k = 128,
    // 132, …, 196 follow: kept k = 0, 4, …, 196 = 50 blocks, each bit-identical to the uncapped
    // profile's block k.
    constexpr uint32_t kSmallCap = 64U;
    constexpr uint32_t kExpectedStride = 4U;
    constexpr double kDecimatedToleranceDb = 0.25;
    const TlProgramme& programme = tlGatePink();
    const TlProfiles full = tlProfile(programme, tlStereoWeights());
    const TlProfiles capped = tlProfile(programme, tlStereoWeights(), 0U, kSmallCap);
    if (!full.whole || !capped.whole)
    {
        logFail(kName, "no profile");
        return;
    }
    const uint32_t expectedBlocks = ((full.whole->blockCount - 1U) / kExpectedStride) + 1U;
    if (capped.whole->blockStrideHops != kExpectedStride ||
        capped.whole->blockCount != expectedBlocks ||
        capped.whole->bandPower.capacity() >
            static_cast<size_t>(kSmallCap) * capped.whole->bandCount)
    {
        logFail(kName,
                std::format("cap {}: stride {} (want {}), {} blocks (want {})",
                            kSmallCap,
                            capped.whole->blockStrideHops,
                            kExpectedStride,
                            capped.whole->blockCount,
                            expectedBlocks));
        return;
    }
    for (uint32_t index = 0U; index < capped.whole->blockCount; ++index)
    {
        const std::span<const float> kept = capped.whole->block(index);
        const std::span<const float> original = full.whole->block(index * kExpectedStride);
        if (!std::ranges::equal(
                kept,
                original,
                [](float lhs, float rhs)
                { return std::bit_cast<uint32_t>(lhs) == std::bit_cast<uint32_t>(rhs); }))
        {
            logFail(kName, std::format("kept block {} is not the original block", index));
            return;
        }
    }
    auto designer = eqMakeDesigner();
    double decimatedWorst = 0.0;
    for (const TlCurve& curve : tlGateCurves())
    {
        decimatedWorst =
            std::max(decimatedWorst,
                     std::abs(tlPredict(*capped.whole, *designer, curve.points, kTlRate48k) -
                              tlPredict(*full.whole, *designer, curve.points, kTlRate48k)));
    }

    // (2) The default 6000-block cap, in practice: 12 minutes of mono 8 kHz noise (7197 blocks)
    // crosses it once → stride 2, 3000 + 599 = 3599 blocks.
    constexpr double kLongRate = 8000.0;
    constexpr double kLongSeconds = 12.0 * 60.0;
    constexpr uint32_t kLongExpectedBlocks = 3599U;
    TrackLoudnessProfiler::Format mono{kLongRate, 1U, {}};
    mono.channelWeights[0] = 1.0;
    auto profiler = TrackLoudnessProfiler::create(mono);
    if (!profiler)
    {
        logFail(kName, "8 kHz mono profiler create failed");
        return;
    }
    constexpr size_t kChunk = 8000U;
    std::vector<float> chunk(kChunk);
    std::minstd_rand cheap(41U);
    std::uniform_real_distribution<float> uniform(-0.5F, 0.5F);
    const auto longFrames = static_cast<size_t>(kLongSeconds * kLongRate);
    size_t peakBytes = 0U;
    for (size_t done = 0U; done < longFrames; done += kChunk)
    {
        for (float& sample : chunk)
        {
            sample = uniform(cheap);
        }
        const float* channel = chunk.data();
        if (!profiler->feed(std::span<const float* const>(&channel, 1U), kChunk))
        {
            logFail(kName, "the long feed was rejected");
            return;
        }
        peakBytes = std::max(peakBytes, profiler->memoryBytes());
    }
    const std::shared_ptr<const TrackLoudnessProfile> longProfile = profiler->finish();
    const uint32_t longBands = TrackLoudness::bandCount(kLongRate);
    const size_t capBytes =
        static_cast<size_t>(TrackLoudnessProfiler::kDefaultMaxBlocks) * longBands * sizeof(float);
    if (!longProfile || longProfile->blockCount != kLongExpectedBlocks ||
        longProfile->blockStrideHops != 2U ||
        longProfile->memoryBytes() > capBytes + sizeof(TrackLoudnessProfile))
    {
        logFail(kName, "the default cap did not decimate a 12-minute track as specified");
        return;
    }

    // (3) The stated bounds at the worst format: the profile's cap at 192 kHz, and the fixed
    // working set of a 192 kHz × 8-channel profiler (rings + one 131072-point FFT's buffers).
    constexpr double kCapMegabytesBound = 7.1;
    constexpr double kWorkingSetMegabytesBound = 4.5;
    constexpr double kMegabyte = 1e6; // decimal MB, as TrackLoudnessProfiler.h states the bounds
    TrackLoudnessProfiler::Format worst{kTlRate192k, kMaxChannels, {}};
    worst.channelWeights.fill(1.0);
    auto worstProfiler = TrackLoudnessProfiler::create(worst);
    const double capMegabytes = static_cast<double>(TrackLoudnessProfiler::kDefaultMaxBlocks) *
                                TrackLoudness::bandCount(kTlRate192k) * sizeof(float) / kMegabyte;
    const double workingMegabytes =
        worstProfiler ? static_cast<double>(worstProfiler->memoryBytes()) / kMegabyte : 1e9;
    logInfo(
        std::format("[info] {}: cap {} → stride {}, {} of {} blocks, kept blocks exact, "
                    "prediction vs undecimated worst {:.4f} dB (≤ {}); 12 min @ 8 kHz → {} "
                    "blocks at stride {}, profile {:.2f} MB (peak profiler {:.2f} MB); bounds "
                    "@ 192 kHz × 8: profile cap {:.2f} MB (≤ {}), working set {:.2f} MB "
                    "(≤ {})\n",
                    kName,
                    kSmallCap,
                    capped.whole->blockStrideHops,
                    capped.whole->blockCount,
                    full.whole->blockCount,
                    decimatedWorst,
                    kDecimatedToleranceDb,
                    longProfile->blockCount,
                    longProfile->blockStrideHops,
                    static_cast<double>(longProfile->memoryBytes()) / kMegabyte,
                    static_cast<double>(peakBytes) / kMegabyte,
                    capMegabytes,
                    kCapMegabytesBound,
                    workingMegabytes,
                    kWorkingSetMegabytesBound));
    if (!(decimatedWorst <= kDecimatedToleranceDb) || !(capMegabytes <= kCapMegabytesBound) ||
        !(workingMegabytes <= kWorkingSetMegabytesBound))
    {
        logFail(kName, "a decimation or memory bound is exceeded");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Predictor_Properties — exact identities of the gated predictor.
// ---------------------------------------------------------------------------
static auto testLoudnessPredictorProperties() -> void
{
    static const char* const kName = "Loudness_Predictor_Properties";
    constexpr double kUniformDb = 6.0;
    constexpr double kUniformTolerance = 1e-9;
    constexpr double kStepToleranceDb = 0.1;
    constexpr uint32_t kCoarseStep = 4U;
    const TlProgramme& programme = tlGatePink();
    const TlProfiles profiles = tlProfile(programme, tlStereoWeights());
    if (!profiles.whole)
    {
        logFail(kName, "no profile");
        return;
    }
    const TrackLoudnessProfile& profile = *profiles.whole;
    auto designer = eqMakeDesigner();
    // (1) Flat is exactly 0 dB, through the response API and through a flat design.
    const std::vector<double> flat(profile.bandCount, 0.0);
    double flatChange = 1.0;
    double flatDesignChange = 1.0;
    GraphicEQDesign flatDesign{};
    if (!predictLoudnessChangeDb(profile, flat, 1U, flatChange) ||
        !designer->design(EqCurve{}, kTlRate48k, flatDesign) ||
        !predictLoudnessChangeDb(profile, flatDesign, 1U, flatDesignChange) || flatChange != 0.0 ||
        flatDesignChange != 0.0)
    {
        logFail(kName, "a flat curve does not predict exactly 0 dB");
        return;
    }
    // (2) A uniform +6 dB response moves every block and both gates by 6 dB: ΔL = +6 dB. (The
    // pink programme's quiet sections sit far below both gates either way.)
    const std::vector<double> uniform(profile.bandCount, kUniformDb);
    double uniformChange = 0.0;
    if (!predictLoudnessChangeDb(profile, uniform, 1U, uniformChange) ||
        !(std::abs(uniformChange - kUniformDb) <= kUniformTolerance))
    {
        logFail(kName, std::format("a uniform +6 dB predicts {:+.12f} dB", uniformChange));
        return;
    }
    // (3) A 96 kHz track played at 48 kHz: only the bands whose centre is below 24 kHz are played,
    // and the design overload equals the response overload on exactly those bands.
    const TlProgramme hiRes = tlPinkProgramme(kTlRate96k, 6.0, 51U);
    const TlProfiles hiResProfiles = tlProfile(hiRes, tlStereoWeights());
    GraphicEQDesign warm{};
    if (!hiResProfiles.whole || !designer->design(kEqPresetCurves[kEqPresetWarm], kTlRate48k, warm))
    {
        logFail(kName, "no 96 kHz profile or Warm design");
        return;
    }
    std::vector<double> playedDb;
    for (uint32_t band = 0U; band < hiResProfiles.whole->bandCount; ++band)
    {
        const double centre = TrackLoudness::bandCentreHz(band, kTlRate96k);
        if (!(centre < kTlRate48k / 2.0))
        {
            break;
        }
        playedDb.push_back(GraphicEQDesigner::playedDb(warm, centre));
    }
    double viaDesign = 0.0;
    double viaResponse = 1.0;
    if (playedDb.size() >= hiResProfiles.whole->bandCount ||
        !predictLoudnessChangeDb(*hiResProfiles.whole, warm, 1U, viaDesign) ||
        !predictLoudnessChangeDb(*hiResProfiles.whole, playedDb, 1U, viaResponse) ||
        viaDesign != viaResponse)
    {
        logFail(kName, "bands above the output's Nyquist were not left out");
        return;
    }
    // (4) Every 4th block (the drag estimate) stays close to every block.
    double stepWorst = 0.0;
    for (const TlCurve& curve : tlGateCurves())
    {
        stepWorst =
            std::max(stepWorst,
                     std::abs(tlPredict(profile, *designer, curve.points, kTlRate48k, kCoarseStep) -
                              tlPredict(profile, *designer, curve.points, kTlRate48k)));
    }
    logInfo(
        std::format("[info] {}: flat 0 dB exactly; uniform +6 → {:+.12f} dB; 96 kHz track at "
                    "48 kHz plays {} of {} bands; blockStep 4 vs 1 worst {:.4f} dB (≤ {})\n",
                    kName,
                    uniformChange,
                    playedDb.size(),
                    hiResProfiles.whole->bandCount,
                    stepWorst,
                    kStepToleranceDb));
    if (!(stepWorst <= kStepToleranceDb))
    {
        logFail(kName, std::format("blockStep 4 differs by {:.4f} dB", stepWorst));
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Profiler_RejectsBadInput — the C++ guards: formats, non-finite PCM (consuming
// nothing), and the predictor's.
// ---------------------------------------------------------------------------
static auto testLoudnessProfilerRejectsBadInput() -> void
{
    static const char* const kName = "Loudness_Profiler_RejectsBadInput";
    constexpr double kNan = std::numeric_limits<double>::quiet_NaN();
    constexpr double kInf = std::numeric_limits<double>::infinity();
    const TlWeights stereo = tlStereoWeights();
    // Formats.
    const auto rejected = [](const TrackLoudnessProfiler::Format& format, uint32_t maxBlocks)
    { return TrackLoudnessProfiler::create(format, maxBlocks) == nullptr; };
    constexpr uint32_t kCap = TrackLoudnessProfiler::kDefaultMaxBlocks;
    for (const double rate : {kNan, kInf, -kInf, 0.0, -48000.0, 7999.0, 192001.0, 1e9})
    {
        if (!rejected({rate, 2U, stereo}, kCap))
        {
            logFail(kName, std::format("sample rate {} was accepted", rate));
            return;
        }
    }
    TlWeights badWeight = stereo;
    badWeight[1] = kNan;
    TlWeights negative = stereo;
    negative[0] = -1.0;
    TlWeights infinite = stereo;
    infinite[0] = kInf;
    if (!rejected({kTlRate48k, 0U, stereo}, kCap) || !rejected({kTlRate48k, 9U, stereo}, kCap) ||
        !rejected({kTlRate48k, 2U, badWeight}, kCap) ||
        !rejected({kTlRate48k, 2U, negative}, kCap) ||
        !rejected({kTlRate48k, 2U, infinite}, kCap) || !rejected({kTlRate48k, 2U, {}}, kCap) ||
        !rejected({kTlRate48k, 2U, stereo}, 0U) || !rejected({kTlRate48k, 2U, stereo}, 1U) ||
        !rejected({kTlRate48k, 2U, stereo}, 63U) ||
        rejected({TrackLoudness::kMinSampleRateHz, 1U, stereo}, 2U) ||
        rejected({TrackLoudness::kMaxSampleRateHz, kMaxChannels, stereo}, kCap))
    {
        logFail(kName, "a bad format was accepted, or a good one rejected");
        return;
    }
    // A rejected feed consumes nothing: A, bad, B ≡ A, B, bit for bit.
    const TlProgramme& programme = tlGatePink();
    constexpr size_t kPart = 48000U; // 1 s
    const auto run = [&](bool withBad, size_t badChannel, float badValue)
    {
        auto profiler = TrackLoudnessProfiler::create(tlFormat(programme, stereo));
        std::array<const float*, 2> first = {
            programme.channels[0].data(),
            programme.channels[1].data(),
        };
        std::array<const float*, 2> second = {
            programme.channels[0].data() + kPart,
            programme.channels[1].data() + kPart,
        };
        bool accepted = profiler->feed(first, kPart);
        if (withBad)
        {
            const float* original = programme.channels[badChannel].data();
            std::vector<float> poisoned(original + kPart, original + (2U * kPart));
            poisoned[kPart - 1U] = badValue; // the very last sample of the chunk
            std::array<const float*, 2> bad = second;
            bad[badChannel] = poisoned.data();
            accepted = accepted && !profiler->feed(bad, kPart);
        }
        accepted = accepted && profiler->feed(second, kPart);
        const auto profile = profiler->finish();
        return std::make_pair(accepted, profile);
    };
    const auto [cleanOk, clean] = run(false, 0U, 0.0F);
    for (const auto& [channel, value] : {
             std::pair<size_t, float>{0U, std::numeric_limits<float>::quiet_NaN()},
             std::pair<size_t, float>{1U, std::numeric_limits<float>::infinity()},
             std::pair<size_t, float>{1U, -std::numeric_limits<float>::infinity()},
         })
    {
        const auto [ok, poisoned] = run(true, channel, value);
        if (!cleanOk || !ok || !clean || !poisoned || poisoned->bandPower != clean->bandPower ||
            poisoned->analysedFrames != clean->analysedFrames)
        {
            logFail(kName, "a non-finite chunk was not rejected cleanly");
            return;
        }
    }
    // Wrong channel counts, NULL channel pointers, feeding after finish, a second finish.
    {
        auto profiler = TrackLoudnessProfiler::create(tlFormat(programme, stereo));
        const std::array<const float*, 1> one = {programme.channels[0].data()};
        const std::array<const float*, 3> three = {
            programme.channels[0].data(),
            programme.channels[1].data(),
            programme.channels[1].data(),
        };
        const std::array<const float*, 2> withNull = {programme.channels[0].data(), nullptr};
        const std::array<const float*, 2> good = {
            programme.channels[0].data(),
            programme.channels[1].data(),
        };
        const bool guarded = !profiler->feed(one, kPart) && !profiler->feed(three, kPart) &&
                             !profiler->feed(withNull, kPart) && profiler->feed(good, 0U) &&
                             profiler->snapshot() == nullptr && profiler->feed(good, kPart) &&
                             profiler->snapshot() != nullptr && profiler->finish() != nullptr &&
                             !profiler->feed(good, kPart) && profiler->finish() == nullptr &&
                             profiler->snapshot() == nullptr;
        if (!guarded)
        {
            logFail(kName, "a count, NULL or after-finish guard failed");
            return;
        }
    }
    // The predictor's guards leave the output untouched.
    const TlProfiles profiles = tlProfile(programme, stereo);
    const TrackLoudnessProfile& profile = *profiles.whole;
    constexpr double kSentinel = 123.25;
    double out = kSentinel;
    std::vector<double> response(profile.bandCount, 1.0);
    std::vector<double> nanResponse = response;
    nanResponse[profile.bandCount / 2U] = kNan;
    std::vector<double> infResponse = response;
    infResponse[0] = kInf;
    std::vector<double> tooLong(profile.bandCount + 1U, 0.0);
    TrackLoudnessProfile empty = profile;
    empty.blockCount = 0U;
    empty.bandPower.clear();
    TrackLoudnessProfile malformed = profile;
    malformed.bandPower.pop_back();
    TrackLoudnessProfile silent = profile;
    std::ranges::fill(silent.bandPower, 0.0F);
    GraphicEQDesign noRate{};
    const bool predictorGuarded =
        !predictLoudnessChangeDb(profile, nanResponse, 1U, out) &&
        !predictLoudnessChangeDb(profile, infResponse, 1U, out) &&
        !predictLoudnessChangeDb(profile, tooLong, 1U, out) &&
        !predictLoudnessChangeDb(profile, std::span<const double>(), 1U, out) &&
        !predictLoudnessChangeDb(profile, response, 0U, out) &&
        !predictLoudnessChangeDb(empty, response, 1U, out) &&
        !predictLoudnessChangeDb(malformed, response, 1U, out) &&
        !predictLoudnessChangeDb(silent, response, 1U, out) &&
        !predictLoudnessChangeDb(profile, noRate, 1U, out) && out == kSentinel &&
        profileLoudnessLufs(silent) == kSilenceLufs && profileLoudnessLufs(empty) == kSilenceLufs;
    if (!predictorGuarded)
    {
        logFail(kName, "a predictor guard failed or wrote its output");
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Abi_LifecycleAndGuards — the C-ABI trust boundary and life cycle; its results equal
// the C++ path's bit for bit.
// ---------------------------------------------------------------------------
static auto testLoudnessAbiLifecycleAndGuards() -> void
{
    static const char* const kName = "Loudness_Abi_LifecycleAndGuards";
    constexpr double kNan = std::numeric_limits<double>::quiet_NaN();
    constexpr uint32_t kHalfSecond = 24000U;
    const TlProgramme& programme = tlGateOrchestral();
    // Create guards.
    if (asLoudnessProfilerCreate(kNan, 2U, kAudioChannelLayoutTag_Stereo) != nullptr ||
        asLoudnessProfilerCreate(0.0, 2U, kAudioChannelLayoutTag_Stereo) != nullptr ||
        asLoudnessProfilerCreate(7999.0, 2U, kAudioChannelLayoutTag_Stereo) != nullptr ||
        asLoudnessProfilerCreate(192001.0, 2U, kAudioChannelLayoutTag_Stereo) != nullptr ||
        asLoudnessProfilerCreate(kTlRate48k, 0U, kAudioChannelLayoutTag_Stereo) != nullptr ||
        asLoudnessProfilerCreate(kTlRate48k, 9U, kAudioChannelLayoutTag_Stereo) != nullptr)
    {
        logFail(kName, "a bad create was accepted");
        return;
    }
    AsLoudnessProfiler* profiler =
        asLoudnessProfilerCreate(kTlRate48k, 2U, kAudioChannelLayoutTag_Stereo);
    AsEqDesigner* designer = asEqDesignerCreate();
    if (profiler == nullptr || designer == nullptr)
    {
        asLoudnessProfilerDestroy(profiler);
        asEqDesignerDestroy(designer);
        logFail(kName, "create failed");
        return;
    }
    std::string failure;
    const auto expect = [&failure](bool condition, const char* what)
    {
        if (failure.empty() && !condition)
        {
            failure = what;
        }
    };
    std::array<const float*, 2> channels = {
        programme.channels[0].data(),
        programme.channels[1].data(),
    };
    std::array<const float*, 2> withNull = {programme.channels[0].data(), nullptr};
    std::vector<float> poisoned(programme.channels[1].data(),
                                programme.channels[1].data() + kHalfSecond);
    poisoned[kHalfSecond / 2U] = std::numeric_limits<float>::quiet_NaN();
    std::array<const float*, 2> withNan = {programme.channels[0].data(), poisoned.data()};
    expect(!asLoudnessProfilerFeed(nullptr, channels.data(), 2U, kHalfSecond),
           "feed NULL profiler");
    expect(!asLoudnessProfilerFeed(profiler, nullptr, 2U, kHalfSecond), "feed NULL channels");
    expect(!asLoudnessProfilerFeed(profiler, withNull.data(), 2U, kHalfSecond),
           "feed NULL channel");
    expect(!asLoudnessProfilerFeed(profiler, channels.data(), 1U, kHalfSecond), "feed count 1");
    expect(!asLoudnessProfilerFeed(profiler, channels.data(), 3U, kHalfSecond), "feed count 3");
    expect(!asLoudnessProfilerFeed(profiler, withNan.data(), 2U, kHalfSecond), "feed NaN");
    expect(asLoudnessProfilerFeed(profiler, channels.data(), 2U, 0U), "feed 0 frames");
    expect(asLoudnessProfilerFinishPrefix(nullptr) == nullptr, "prefix NULL");
    expect(asLoudnessProfilerFinishPrefix(profiler) == nullptr, "prefix before any block");
    // Feed the whole programme in half-second chunks, taking a prefix after 5 s.
    AsLoudnessProfile* prefix = nullptr;
    const size_t frames = programme.frames();
    constexpr size_t kPrefixChunks = 10U;
    size_t chunkIndex = 0U;
    for (size_t done = 0U; done < frames; done += kHalfSecond, ++chunkIndex)
    {
        channels = {programme.channels[0].data() + done, programme.channels[1].data() + done};
        expect(asLoudnessProfilerFeed(
                   profiler,
                   channels.data(),
                   2U,
                   static_cast<uint32_t>(std::min<size_t>(kHalfSecond, frames - done))),
               "feed");
        if (chunkIndex + 1U == kPrefixChunks)
        {
            prefix = asLoudnessProfilerFinishPrefix(profiler);
        }
    }
    AsLoudnessProfile* whole = asLoudnessProfilerFinishFull(profiler);
    expect(prefix != nullptr && whole != nullptr, "prefix / full returned NULL");
    expect(asLoudnessProfilerFinishFull(profiler) == nullptr, "a second finish");
    expect(asLoudnessProfilerFinishPrefix(profiler) == nullptr, "prefix after finish");
    expect(!asLoudnessProfilerFeed(profiler, channels.data(), 2U, 1U), "feed after finish");
    expect(asLoudnessProfilerFinishFull(nullptr) == nullptr, "finish NULL");
    asLoudnessProfilerDestroy(profiler); // the profiles outlive their profiler
    asLoudnessProfilerDestroy(nullptr);
    asLoudnessProfileDestroy(nullptr);

    AsLoudnessProfileInfo info{};
    AsLoudnessProfileInfo prefixInfo{};
    expect(!asLoudnessProfileGetInfo(nullptr, &info) && !asLoudnessProfileGetInfo(whole, nullptr),
           "info guards");
    expect(asLoudnessProfileGetInfo(whole, &info) && asLoudnessProfileGetInfo(prefix, &prefixInfo),
           "info");
    const TlProfiles cpp = tlProfile(programme, tlStereoWeights(), kPrefixChunks * kHalfSecond);
    if (failure.empty() && cpp.whole && cpp.prefix)
    {
        expect(info.wholeTrack && !prefixInfo.wholeTrack && info.sampleRate == kTlRate48k &&
                   info.channelCount == 2U && info.blockCount == cpp.whole->blockCount &&
                   info.bandCount == cpp.whole->bandCount && info.blockStrideHops == 1U &&
                   prefixInfo.blockCount == cpp.prefix->blockCount &&
                   info.analysedSeconds == static_cast<double>(frames) / kTlRate48k &&
                   info.sourceLoudnessLufs == cpp.whole->sourceLoudnessLufs,
               "info fields");
        // Predict: the guards write nothing; a good call equals the C++ path bit for bit.
        const EqCurve warm = kEqPresetCurves[kEqPresetWarm];
        EqCurve nanCurve = warm;
        nanCurve[4] = std::numeric_limits<float>::quiet_NaN();
        constexpr double kSentinel = -77.5;
        double out = kSentinel;
        expect(
            !asLoudnessPredictChangeDb(nullptr, designer, warm.data(), 31U, kTlRate48k, &out) &&
                !asLoudnessPredictChangeDb(whole, nullptr, warm.data(), 31U, kTlRate48k, &out) &&
                !asLoudnessPredictChangeDb(whole, designer, nullptr, 31U, kTlRate48k, &out) &&
                !asLoudnessPredictChangeDb(
                    whole, designer, warm.data(), 31U, kTlRate48k, nullptr) &&
                !asLoudnessPredictChangeDb(whole, designer, warm.data(), 30U, kTlRate48k, &out) &&
                !asLoudnessPredictChangeDb(whole, designer, warm.data(), 32U, kTlRate48k, &out) &&
                !asLoudnessPredictChangeDb(
                    whole, designer, nanCurve.data(), 31U, kTlRate48k, &out) &&
                !asLoudnessPredictChangeDb(whole, designer, warm.data(), 31U, kNan, &out) &&
                !asLoudnessPredictChangeDb(whole, designer, warm.data(), 31U, 43999.0, &out) &&
                out == kSentinel,
            "predict guards");
        double viaAbi = 0.0;
        double viaPrefixAbi = 0.0;
        auto cppDesigner = eqMakeDesigner();
        const double viaCpp = tlPredict(*cpp.whole, *cppDesigner, warm, kTlRate48k);
        const double viaPrefixCpp = tlPredict(*cpp.prefix, *cppDesigner, warm, kTlRate48k);
        expect(asLoudnessPredictChangeDb(whole, designer, warm.data(), 31U, kTlRate48k, &viaAbi) &&
                   asLoudnessPredictChangeDb(
                       prefix, designer, warm.data(), 31U, kTlRate48k, &viaPrefixAbi) &&
                   viaAbi == viaCpp && viaPrefixAbi == viaPrefixCpp,
               "the C-ABI prediction differs from the C++ one");
    }
    // A silent track profiles (its blocks exist) but predicts nothing: no block passes the gates.
    AsLoudnessProfiler* silentProfiler =
        asLoudnessProfilerCreate(kTlRate48k, 2U, kAudioChannelLayoutTag_Stereo);
    const std::vector<float> silence(static_cast<size_t>(kHalfSecond) * 2U, 0.0F);
    const std::array<const float*, 2> quiet = {silence.data(), silence.data()};
    expect(asLoudnessProfilerFeed(silentProfiler, quiet.data(), 2U, kHalfSecond * 2U),
           "silent feed");
    AsLoudnessProfile* silent = asLoudnessProfilerFinishFull(silentProfiler);
    AsLoudnessProfileInfo silentInfo{};
    double silentChange = 0.0;
    expect(silent != nullptr && asLoudnessProfileGetInfo(silent, &silentInfo) &&
               silentInfo.sourceLoudnessLufs == kSilenceLufs &&
               !asLoudnessPredictChangeDb(silent,
                                          designer,
                                          kEqPresetCurves[kEqPresetWarm].data(),
                                          31U,
                                          kTlRate48k,
                                          &silentChange),
           "silence");
    // Shorter than one 400 ms block: no profile at all.
    AsLoudnessProfiler* shortProfiler =
        asLoudnessProfilerCreate(kTlRate48k, 2U, kAudioChannelLayoutTag_Stereo);
    constexpr uint32_t kUnderOneBlock = 19199U;
    expect(asLoudnessProfilerFeed(shortProfiler, quiet.data(), 2U, kUnderOneBlock) &&
               asLoudnessProfilerFinishFull(shortProfiler) == nullptr,
           "a track under 400 ms");
    // A mono file with the Stereo tag (the bridge's fallback tag) weights its one channel 1.0.
    channels = {programme.channels[0].data(), programme.channels[1].data()};
    AsLoudnessProfiler* monoProfiler =
        asLoudnessProfilerCreate(kTlRate48k, 1U, kAudioChannelLayoutTag_Stereo);
    expect(monoProfiler != nullptr &&
               asLoudnessProfilerFeed(monoProfiler, channels.data(), 1U, kHalfSecond),
           "mono with the Stereo tag");
    asLoudnessProfilerDestroy(monoProfiler);
    asLoudnessProfilerDestroy(shortProfiler);
    asLoudnessProfilerDestroy(silentProfiler);
    asLoudnessProfileDestroy(silent);
    asLoudnessProfileDestroy(prefix);
    asLoudnessProfileDestroy(whole);
    asEqDesignerDestroy(designer);
    if (!failure.empty())
    {
        logFail(kName, failure);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// Loudness_Profile_SharedAcrossThreads — one immutable profile, two threads predicting with
// their own designers, equal to the serial results bit for bit (race-free under tsan).
// ---------------------------------------------------------------------------
static auto testLoudnessProfileSharedAcrossThreads() -> void
{
    static const char* const kName = "Loudness_Profile_SharedAcrossThreads";
    constexpr int kRounds = 3;
    const TlProfiles profiles = tlProfile(tlGatePink(), tlStereoWeights());
    if (!profiles.whole)
    {
        logFail(kName, "no profile");
        return;
    }
    const std::shared_ptr<const TrackLoudnessProfile> shared = profiles.whole;
    const std::vector<TlCurve> curves = tlGateCurves();
    const auto predictAll =
        [&curves](const TrackLoudnessProfile& profile, double outputRate, std::vector<double>& out)
    {
        auto designer = eqMakeDesigner();
        out.clear();
        for (int round = 0; round < kRounds; ++round)
        {
            for (const TlCurve& curve : curves)
            {
                out.push_back(tlPredict(profile, *designer, curve.points, outputRate));
            }
        }
    };
    std::vector<double> serialA;
    std::vector<double> serialB;
    predictAll(*shared, kTlRate48k, serialA);
    predictAll(*shared, kTlRate96k, serialB);
    std::vector<double> threadA;
    std::vector<double> threadB;
    // Each worker holds its own reference, as the analyzer and the Realizer will.
    std::thread workerA([&, held = shared] { predictAll(*held, kTlRate48k, threadA); });
    std::thread workerB([&, held = shared] { predictAll(*held, kTlRate96k, threadB); });
    workerA.join();
    workerB.join();
    const auto same = [](const std::vector<double>& lhs, const std::vector<double>& rhs)
    {
        return std::ranges::equal(lhs,
                                  rhs,
                                  [](double left, double right)
                                  { return std::isfinite(left) && left == right; });
    };
    if (!same(serialA, threadA) || !same(serialB, threadB))
    {
        logFail(kName, "a threaded prediction differs from the serial one");
        return;
    }
    logPass(kName);
}

namespace
{
    // Profiler_Timing's feed: CPU ms per second of audio to profile `seconds` of noise in
    // `format` — the profiling thread's own CPU time, the least of rig::kTimingRuns fresh
    // profilers — and the profile's block count (0 on failure). One second of noise per channel is
    // generated first and looped, and each profiler is made before its clock starts.
    auto tlTimeFeed(const TrackLoudnessProfiler::Format& format,
                    double seconds,
                    std::minstd_rand& cheap) -> std::pair<double, uint32_t>
    {
        constexpr size_t kChunk = 4096U;
        const auto second = static_cast<size_t>(format.sampleRate);
        std::uniform_real_distribution<float> uniform(-0.5F, 0.5F);
        std::vector<std::vector<float>> noise(format.channelCount,
                                              std::vector<float>(second + kChunk));
        for (std::vector<float>& channel : noise)
        {
            for (float& sample : channel)
            {
                sample = uniform(cheap);
            }
        }
        std::vector<const float*> pointers(format.channelCount);
        const auto total = static_cast<size_t>(seconds * format.sampleRate);
        auto best = std::chrono::nanoseconds::max();
        uint32_t blocks = 0U;
        for (int run = 0; run < rig::kTimingRuns; ++run)
        {
            auto profiler = TrackLoudnessProfiler::create(format);
            if (!profiler)
            {
                return {0.0, 0U};
            }
            const std::chrono::nanoseconds start = rig::threadCpuTime();
            for (size_t done = 0U; done < total; done += kChunk)
            {
                for (size_t ch = 0U; ch < pointers.size(); ++ch)
                {
                    pointers[ch] = noise[ch].data() + (done % second);
                }
                if (!profiler->feed(pointers, std::min(kChunk, total - done)))
                {
                    return {0.0, 0U};
                }
            }
            const std::shared_ptr<const TrackLoudnessProfile> profile = profiler->finish();
            best = std::min(best, rig::threadCpuTime() - start);
            blocks = profile ? profile->blockCount : 0U;
        }
        return {std::chrono::duration<double, std::milli>(best).count() / seconds, blocks};
    }
} // namespace

// ---------------------------------------------------------------------------
// Profiler_Timing — the worst supported format, 192 kHz × 8 channels (every channel weighted, so
// every channel costs an FFT per block), and the predictor on a full 6000-block profile.
// Measured optimised on an M4 Pro: 16.5 ms of CPU per second of audio (≈ 60× real time) and
// 1.37 ms per prediction (0.44 ms on every 4th block). Budgets, with the M1 Pro floor's ×1.4–1.8
// in hand: ≤ 40 ms per second of audio (≥ 25× real time: a 25 s prefix of the worst format in
// ≤ 1 s) and ≤ 4 ms per prediction. Measured as the working thread's own CPU time, the least of
// rig::kTimingRuns runs; the budgets hold in the -O2 timing run, and the debug and sanitizer builds
// only trip a catastrophic regression (≥ 10× what they measure — debug: 38 ms/s and 11 ms here, 85
// and 21 ms wall on CI). The common 44.1 kHz stereo case is logged.
// ---------------------------------------------------------------------------
static auto testProfilerTiming() -> void
{
    static const char* const kName = "Profiler_Timing";
    constexpr rig::Budget kFeedBudgetMsPerSecond{
        .strict = 40.0,
        .debug = 1000.0,
        .asan = 1000.0,
        .tsan = 4000.0,
    };
    constexpr rig::Budget kPredictBudgetMs{
        .strict = 4.0,
        .debug = 250.0,
        .asan = 400.0,
        .tsan = 2000.0,
    };
    constexpr double kAudioSeconds = 6.0;
    constexpr int kPredictions = 20;
    std::minstd_rand cheap(61U);
    TrackLoudnessProfiler::Format worstFormat{kTlRate192k, kMaxChannels, {}};
    worstFormat.channelWeights.fill(1.0);
    const auto [feedMsPerSecond, worstBlocks] = tlTimeFeed(worstFormat, kAudioSeconds, cheap);
    const auto [commonMsPerSecond, commonBlocks] =
        tlTimeFeed({kTlRate44k, 2U, tlStereoWeights()}, kAudioSeconds, cheap);
    if (worstBlocks == 0U || commonBlocks == 0U)
    {
        logFail(kName, "a timed profile failed");
        return;
    }

    // A full-cap profile at 48 kHz (6000 blocks × 247 bands) of random powers.
    TrackLoudnessProfile capped;
    capped.sampleRate = kTlRate48k;
    capped.channelCount = 2U;
    capped.bandCount = TrackLoudness::bandCount(kTlRate48k);
    capped.blockCount = TrackLoudnessProfiler::kDefaultMaxBlocks;
    capped.wholeTrack = true;
    capped.bandPower.resize(static_cast<size_t>(capped.blockCount) * capped.bandCount);
    std::uniform_real_distribution<float> power(1e-6F, 1e-2F);
    for (float& value : capped.bandPower)
    {
        value = power(cheap);
    }
    auto designer = eqMakeDesigner();
    GraphicEQDesign warm{};
    (void)designer->design(kEqPresetCurves[kEqPresetWarm], kTlRate48k, warm);
    double sink = 0.0;
    const auto timePredictions = [&](uint32_t blockStep)
    {
        const std::chrono::nanoseconds cpu = rig::minThreadCpu(
            rig::kTimingRuns,
            [&]
            {
                for (int round = 0; round < kPredictions; ++round)
                {
                    double change = 0.0;
                    (void)predictLoudnessChangeDb(capped, warm, blockStep, change);
                    sink += change;
                }
            });
        return std::chrono::duration<double, std::milli>(cpu).count() / kPredictions;
    };
    const double predictMs = timePredictions(1U);
    const double steppedMs = timePredictions(4U);
    const double feedBound = rig::limit(kFeedBudgetMsPerSecond);
    const double predictBound = rig::limit(kPredictBudgetMs);
    logInfo(
        std::format("[info] {} ({} build, thread CPU, least of {}): 192 kHz × 8 ch {:.1f} ms per "
                    "second of audio ({:.0f}× real time; bound {:.0f}; {} blocks); 44.1 kHz stereo "
                    "{:.2f} ms per second ({:.0f}× real time); predict 6000 × {} bands {:.3f} ms, "
                    "every 4th block {:.3f} ms (bound {:.1f}) [{:.1f}]\n",
                    kName,
                    rig::kBuild,
                    rig::kTimingRuns,
                    feedMsPerSecond,
                    1000.0 / feedMsPerSecond,
                    feedBound,
                    worstBlocks,
                    commonMsPerSecond,
                    1000.0 / commonMsPerSecond,
                    capped.bandCount,
                    predictMs,
                    steppedMs,
                    predictBound,
                    sink));
    if (!(feedMsPerSecond <= feedBound) || !(predictMs <= predictBound))
    {
        logFail(kName,
                std::format("over budget: feed {:.1f} ms/s (≤ {:.0f}), predict {:.3f} ms (≤ {:.1f})",
                            feedMsPerSecond,
                            feedBound,
                            predictMs,
                            predictBound));
        return;
    }
    logPass(kName);
}
