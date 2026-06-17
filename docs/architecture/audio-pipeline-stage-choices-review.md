# Audio Pipeline — Per-Stage Technology Choices (Expert Panel Review)

**Status:** For review · **Date:** 2026-06-17 · **Source:** founder-provided matrix

## Purpose

A founder-provided, stage-by-stage matrix of the **better choice** — Apple-native vs custom
C++23/Accelerate vs established open-source library — for each stage of the AdaptiveSound audio
pipeline, with the quality rationale and implementation tips for each. It is submitted to the expert
panel for **validation, dissent, gap-finding, and reconciliation with the current implementation**.

It operationalizes the founder's posture (see memory `feedback-prefer-established-libs`): Apple-native
for the OS/playback/output layer; **custom C++ for the core enhancement DSP where control is the
product** (EQ, limiter, dynamics); **established libraries for standardized algorithms** (libebur128
loudness, soxr SRC); and mind the Apple-Silicon **M1→M5** capability profile for anything we build.

---

## The matrix

| Stage                    | Better choice                                                | Why it affects quality                                                                                                                                                                                                       | Implementation tips                                                                                                               |
| ------------------------ | ------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| File decoding            | Apple native first. Add FFmpeg only for unsupported formats. | Bad decoding breaks everything after it. Native decoding is safer for AAC, ALAC, MP3, and Apple formats. FFmpeg adds wider codec coverage through `libavcodec`. ([FFmpeg][1])                                                | Start with `AVAudioFile` / `AVAudioConverter`. Add FFmpeg later for FLAC, Opus, unusual containers, or cross-platform plans.      |
| Internal audio format    | Custom C++23 DSP                                             | Processing in integer format can clip during EQ boosts. Floating point gives headroom before final output conversion.                                                                                                        | Use `Float32` for real-time playback. Use `Float64` for offline analysis where CPU cost is acceptable.                            |
| Audio graph              | Apple native                                                 | `AVAudioEngine` connects player nodes, mixers, effects, and output nodes in Apple's audio stack. ([Apple Developer][2])                                                                                                      | Use Swift for graph setup. Keep the actual DSP engine in C++23.                                                                   |
| Mixing                   | Apple native                                                 | `AVAudioMixerNode` accepts different sample rates and channel counts, then mixes to one output. ([Apple Developer][3])                                                                                                       | Use it for playlists, preview audio, crossfade, and output routing. Avoid too many hidden conversions.                            |
| Sample-rate conversion   | Apple native first. Use `soxr` when you need control.        | Resampling can add aliasing, ringing, or phase shift. `AVAudioConverter` supports pulse-code modulation (PCM) sample-rate conversion. ([Apple Developer][4]) `libsoxr` is made for PCM sample-rate conversion. ([GitHub][5]) | Avoid resampling unless needed. If needed, use one conversion only. For offline export, use `soxr` very-high-quality settings.    |
| Bit-depth conversion     | Apple native                                                 | Bit-depth conversion can add quantization noise. `AVAudioConverter` supports PCM bit-depth conversion. ([Apple Developer][4])                                                                                                | Keep internal processing in floating point. Convert to integer only at the final output or export stage.                          |
| Dither                   | Custom C++23 DSP                                             | Dither hides quantization distortion when reducing bit depth, such as 24-bit to 16-bit.                                                                                                                                      | Apply dither only when exporting to fixed-point formats. Do not dither during live Float32 playback.                              |
| Equalizer                | Custom C++23 DSP or Accelerate / `vDSP`                      | EQ changes frequency balance. Bad filters can ring, distort, or cause clipping.                                                                                                                                              | Use biquad filters for parametric EQ. Smooth parameter changes over several milliseconds. Add pre-gain before positive EQ boosts. |
| Loudness normalization   | `libebur128` or custom implementation                        | Normalization prevents volume jumps between tracks. `libebur128` implements the EBU R128 loudness normalization standard. ([GitHub][6])                                                                                      | Scan files offline. Store loudness metadata. Apply gain during playback. Do not normalize by peak only.                           |
| ReplayGain-style gain    | Custom C++23 DSP                                             | Track gain changes perceived volume without changing the source file.                                                                                                                                                        | Store track gain and album gain separately. Use album gain for albums. Use track gain for shuffled playlists.                     |
| Limiter                  | Custom C++23 DSP                                             | EQ and normalization can exceed `0 dBFS`. A limiter prevents digital clipping.                                                                                                                                               | Put limiter last. Target ceiling: `-1.0 dBFS`. Add lookahead if latency is acceptable.                                            |
| Clipping detection       | Custom C++23 DSP                                             | Clipping creates harsh distortion. It is not recoverable after output.                                                                                                                                                       | Count samples above `0 dBFS`. Show a warning in debug mode. Reduce pre-gain automatically if needed.                              |
| Oversampling             | Custom C++23 DSP                                             | Saturation, soft clipping, and limiters can create inter-sample peaks. Oversampling reduces that risk.                                                                                                                       | Use 2x or 4x oversampling only around nonlinear processors. Do not oversample the whole pipeline by default.                      |
| Compressor               | Custom C++23 DSP                                             | Compression changes dynamics. Bad attack and release settings can cause pumping.                                                                                                                                             | Make it optional. Use it for "gym mode" or noisy environments, not pure hi-fi mode.                                               |
| Crossfeed                | Custom C++23 DSP                                             | Crossfeed reduces hard left/right headphone separation.                                                                                                                                                                      | Add this as a headphone mode only. Do not enable it for speakers by default.                                                      |
| Stereo widening          | Custom C++23 DSP                                             | Widening can damage mono compatibility and bass imaging.                                                                                                                                                                      | Keep bass below 120 Hz mostly mono. Add a mono-compatibility meter.                                                               |
| Room correction          | Custom C++23 DSP + optional `vDSP`                           | Speaker and room response can affect sound more than the player.                                                                                                                                                             | Use measured correction, not random presets. Keep correction cuts safer than boosts.                                              |
| Convolution              | `vDSP`, Metal, or custom C++                                 | Long impulse responses can improve room correction or reverb. They also increase CPU use and latency.                                                                                                                        | Use partitioned convolution. Keep short filters for live playback. Use longer filters for offline rendering.                      |
| Spectrum analyzer        | Accelerate / `vDSP`                                          | It does not improve sound, but helps debug EQ and clipping behavior. Accelerate provides Fast Fourier Transform (FFT) functions. ([Apple Developer][7])                                                                      | Run analyzer outside the real-time callback. Use copied buffers from a lock-free ring buffer.                                     |
| AI denoise / enhancement | Core ML, offline first                                       | Machine learning can remove noise, but it can also invent artifacts. Core ML can use CPU, GPU, and Neural Engine. ([Apple Developer][8])                                                                                     | Do not run models inside the real-time callback. Use offline preview, cached output, or large buffered processing.                |
| Stem separation          | Core ML or external model, offline first                     | Separating vocals, drums, and instruments can reduce fidelity. It is model-dependent.                                                                                                                                        | Treat it as a tool, not default playback. Save output separately. Keep original playback available.                               |
| Output device handling   | Apple native                                                 | macOS output still goes through Apple's audio stack. Native APIs reduce integration risk.                                                                                                                                    | Use Apple APIs for device selection, route changes, and sample-rate negotiation.                                                  |
| Bit-perfect mode         | Apple native + DSP bypass                                    | This proves your player can avoid changing the signal.                                                                                                                                                                       | Add a visible "Pure Mode." Bypass EQ, normalization, limiter, crossfeed, and AI.                                                  |
| Quality testing          | Custom test suite                                            | You cannot manage quality by listening only.                                                                                                                                                                                 | Add null tests, peak tests, clipping counters, frequency response tests, and latency measurements.                               |

### References

- [1]: FFmpeg Codecs Documentation — https://ffmpeg.org/ffmpeg-codecs.html
- [2]: AVAudioEngine | Apple Developer Documentation — https://developer.apple.com/documentation/avfaudio/avaudioengine
- [3]: AVAudioMixerNode | Apple Developer Documentation — https://developer.apple.com/documentation/avfaudio/avaudiomixernode
- [4]: AVAudioConverter | Apple Developer Documentation — https://developer.apple.com/documentation/avfaudio/avaudioconverter
- [5]: chirlu/soxr: The SoX resampler library — https://github.com/chirlu/soxr
- [6]: jiixyj/libebur128: EBU R128 implementation — https://github.com/jiixyj/libebur128
- [7]: Fast Fourier transforms | Apple Developer Documentation — https://developer.apple.com/documentation/accelerate/fast-fourier-transforms
- [8]: Core ML | Apple Developer Documentation — https://developer.apple.com/documentation/coreml

---

## Review brief for the expert panel

Reviewers: **audio-dsp**, **modern-C++**, **swiftui-pro / Swift-Apple-platform**, **qa-expert**. For
each stage, return a verdict — **Confirm / Adjust / Reject** — with rationale (cite where useful), and:

1. **Correctness of the "Better choice"** and of the "Why it affects quality" rationale; flag anything
   wrong, oversimplified, or missing.
2. **RT-safety / latency / Apple-Silicon (M1 floor)** implications of the implementation tip.
3. **Cross-stage / ordering interactions** the per-row view misses — e.g. gain-staging (pre-gain
   before EQ boosts), the order of EQ → normalization gain → limiter, dither **after** limiting and
   only at fixed-point export, oversampling **around** nonlinearities only, and where true-peak (ISP)
   detection sits relative to the limiter.
4. **Missing stages** (e.g. **binaural / spatial render** is absent here — note that S4 decided
   Apple-native `AVAudioEnvironmentNode`/`AUSpatialMixer`; channel-layout handling; crossfade; gapless;
   device sample-rate negotiation; declip/declick are out of scope per LD-11).

### Reconciliation with the current implementation (so the panel grounds its verdicts)

- **Equalizer → Custom C++/Accelerate:** ✅ implemented (31-band, off-RT biquad cascade, `vDSP_biquad`,
  ramped). Matches the matrix.
- **Limiter → Custom C++:** ✅ implemented (true-peak/ISP lookahead, dual-stage release, −1 dBTP). Matches.
- **Loudness normalization → libebur128 or custom:** ⚠️ we hand-rolled `LufsMeter` (BS.1770-5) + an
  independent in-test oracle. Matrix lists **libebur128**. Open question: adopt libebur128 (at least as
  the verification oracle; possibly the runtime meter) vs keep the custom meter.
- **Internal format → Float32 RT / Float64 offline:** ✅ matches (RT kernel is Float32).
- **Audio graph / mixing / output / SRC / bit-depth → Apple-native:** ✅ AVAudioEngine + AVAudioFile +
  AVAudioConverter. SRC `soxr` for offline export is not yet adopted.
- **Spectrum analyzer → Accelerate, outside RT, lock-free ring:** ✅ matches (Swift tap on mixer).
- **Bit-perfect "Pure Mode" → Apple-native + DSP bypass:** partially — the kernel has an intensity-0
  bit-exact passthrough (golden-master `0xE7267654BA01D315`); a user-visible "Pure Mode" toggle is not
  yet surfaced.
- **Convolution / room correction / crossfeed / stereo widening / compressor / dither / oversampling /
  ReplayGain / clipping detection:** not yet implemented — future scope; validate the recommended
  approach + the M1→M5 gating.
- **AI denoise / stem separation → Core ML, offline first:** aligns with the Phase-1.5 offline stem
  engine; confirm the offline-only RT boundary.

### Per-discipline focus
- **audio-dsp:** filter design + ringing/pre-gain, dither algorithm + when, oversampling/ISP, loudness
  (R128 vs custom), convolution (partitioned), crossfeed/widening mono-compat, room correction.
- **modern-C++:** where custom C++ is genuinely warranted vs over-build; RT-safety of each custom stage;
  correct Accelerate use; Float32/Float64 boundaries.
- **Swift / Apple platform:** correctness of AVAudioEngine/AVAudioConverter/AVAudioMixerNode/device-
  handling claims; the bit-perfect path; where Apple-native is truly "safer."
- **qa-expert:** make the **Quality testing** row concrete — null tests (incl. intensity-0 bit-exact),
  peak/true-peak, clipping counters, frequency-response sweeps, latency — and tie to the existing C++
  harness + `VerifyAUGraph`.

### Deliverable
A per-stage verdict table (Confirm/Adjust/Reject + rationale), a list of cross-stage/ordering
corrections, any missing stages, and a **prioritized list of deltas vs the current implementation**
(what to change, add, or adopt — e.g. the libebur128 decision).

---

## Panel findings

_(to be completed by the expert panel review)_
