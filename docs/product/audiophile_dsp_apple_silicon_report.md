# Audiophile-grade DSP processing on Apple Silicon

**Prepared for:** C++23 + Swift music player design  
**Verified on:** 2026-06-17  
**Scope:** macOS music playback, digital signal processing, Apple Silicon acceleration, open-source audio projects, and AI-based enhancement.

---

## 1. Executive conclusion

The best architecture is a hybrid stack.

```text
Swift / SwiftUI
→ AVAudioEngine / Core Audio output
→ C++23 real-time DSP kernel
→ Accelerate / vDSP for filters, FFT, convolution
→ optional libebur128, soxr, FFmpeg
→ optional Core ML / MLX for offline AI features
```

Use Apple-native APIs for playback, output routing, device negotiation, and app integration.

Use C++23 for the real-time digital signal processing kernel.

Use selected open-source libraries only where they provide measurable value.

Do not make AI enhancement the default path.

Use AI for offline restoration, stem separation, denoise preview, tagging, and low-quality recording enhancement.

Use classical digital signal processing for equalizer, loudness normalization, limiter, sample-rate conversion, room correction, crossfeed, and true-peak control.

---

## 2. Definitions

**DSP** means digital signal processing. It is math applied to audio samples.

**PCM** means pulse-code modulation. It is the common raw digital audio format.

**FFT** means Fast Fourier Transform. It converts audio from time view to frequency view.

**FIR** means finite impulse response. It is a filter without feedback.

**IIR** means infinite impulse response. It is a filter with feedback.

**dBFS** means decibels relative to full digital scale. `0 dBFS` is the digital clipping point.

**dBTP** means decibels true peak. It estimates peaks between digital samples.

**LUFS** means loudness units relative to full scale. It measures perceived loudness.

**Core ML** is Apple’s machine learning framework.

**MLX** is Apple’s open-source array framework for machine learning on Apple Silicon.

---

## 3. What “audiophile-grade” should mean

“Audiophile-grade” is not a formal engineering standard.

Use measurable transparency instead.

| Requirement | Target |
|---|---:|
| DSP bypass | Bit-identical where possible |
| Internal processing | Float32 minimum |
| Offline analysis | Float64 recommended |
| Output clipping | 0 clipped samples |
| True-peak ceiling | `-1.0 dBTP` for lossy output paths |
| Loudness measurement | ITU-R BS.1770 / EBU R128 compatible |
| Sample-rate conversion | One conversion maximum per playback path |
| Real-time callback | No locks, allocation, file I/O, network I/O, or logging |
| User control | Pure Mode and Enhanced Mode |
| Regression tests | Null test, sweep test, clipping test, loudness test |

ITU-R BS.1770-5 defines algorithms for programme loudness and true-peak audio measurement.

AES loudness resources list ITU-R BS.1770-5 and AES streaming loudness recommendations.

---

## 4. Recommended Apple-native plus C++23 architecture

```text
Input file
→ Apple decoder or FFmpeg fallback
→ Float32 PCM buffer
→ optional sample-rate conversion
→ pre-gain
→ parametric EQ
→ loudness gain
→ true-peak-aware limiter
→ Core Audio output
```

For analysis:

```text
Input file
→ decode to analysis buffer
→ loudness scan
→ peak scan
→ true-peak scan
→ waveform cache
→ spectrum cache
→ metadata database
```

Do all analysis outside the real-time render callback.

---

## 5. Apple-native stack versus open-source stack

| Layer | Apple-native choice | Open-source choice | Recommendation |
|---|---|---|---|
| Audio output | Core Audio / AVAudioEngine | JUCE, miniaudio, PortAudio | Use Apple native. |
| Audio graph | AVAudioEngine | JUCE graph | Use Apple native for macOS-only apps. |
| Custom effect | Audio Unit version 3 | JUCE plug-in wrapper | Use AUv3 if Apple-only. |
| Real-time DSP | C++23 kernel | JUCE DSP, custom C++ | Use custom C++23. |
| Vector DSP | Accelerate / vDSP | Eigen, FFTW, custom SIMD | Use vDSP first. |
| Loudness scan | Custom code | libebur128 | Use libebur128. |
| Resampling | AVAudioConverter | soxr, libsamplerate, SSRC | Native first. Use soxr or SSRC for expert offline mode. |
| Codec expansion | AVFoundation | FFmpeg | Add FFmpeg only when needed. |
| AI inference | Core ML / MLX | PyTorch, ONNX Runtime | Use Core ML for shipping. Use MLX for research. |

---

## 6. Hardware acceleration on Apple Silicon

| Apple Silicon feature | Use for music rendering | Practical recommendation |
|---|---|---|
| CPU performance cores | Real-time DSP | Use for EQ, limiter, gain, routing, crossfeed. |
| CPU efficiency cores | Background work | Use for scanning, metadata, waveform cache. |
| Accelerate / vDSP | Filters, FFT, convolution | Use for math-heavy DSP before writing custom SIMD. |
| Metal GPU | Visualizers, long convolution, batch analysis | Use outside the real-time callback first. |
| Neural Engine | Core ML inference | Use for offline or buffered AI features. |
| Unified memory | Shared CPU/GPU/ML data | Useful for large waveforms and ML models. |
| M5 GPU Neural Accelerators | GPU-backed AI paths | Useful for AI, not needed for normal playback. |
| Media engine | Video codecs | Not relevant to normal music playback. |

Apple’s M1 MacBook Air has an 8-core CPU, 7-core or 8-core GPU, and 16-core Neural Engine.

Apple says the M1 Neural Engine supports 11 trillion operations per second.

Apple announced M5 with a 10-core CPU, GPU Neural Accelerators, 16-core Neural Engine, and 153 GB/s unified memory bandwidth.

For EQ, limiter, and loudness gain, M1 is enough.

For AI stem separation and large local models, M5 gives more headroom.

---

## 7. DSP features that improve rendering quality

| Feature | Use it? | Why it matters | Implementation tip |
|---|---:|---|---|
| Pure Mode | Yes | Gives reference playback. | Bypass all DSP. |
| Float32 pipeline | Yes | Prevents internal clipping during gain and EQ. | Keep the live path in floating point. |
| Float64 analysis | Yes | Improves offline measurement precision. | Use for loudness and test tools. |
| Pre-gain | Yes | Creates headroom before EQ boosts. | Reduce gain before positive bands. |
| Parametric EQ | Yes | More controlled than fixed-band EQ. | Use stable biquad filters. |
| Limiter | Yes | Prevents clipping after EQ and gain. | Put it last. |
| True-peak meter | Yes | Finds inter-sample peaks. | Oversample the meter path. |
| Loudness normalization | Yes | Reduces volume jumps between tracks. | Use ITU-R BS.1770 / EBU R128. |
| Dither | Export only | Reduces quantization distortion. | Use only when reducing bit depth. |
| Oversampling | Selective | Reduces nonlinear artifacts. | Use around saturation or clipping only. |
| Room correction | Optional | Corrects speaker-room response. | Require measurements. Avoid blind boosts. |
| Crossfeed | Optional | Helps headphone listening. | Make it headphone-only. |
| Stereo widening | Risky | Can damage mono compatibility. | Keep bass mostly mono below 120 Hz. |
| AI enhancement | Optional | Can restore or invent content. | Make it offline and reversible. |

---

## 8. Resampling and format conversion

Resampling affects quality when input sample rate differs from output device rate.

| Path | Recommendation |
|---|---|
| Live playback | Prefer device-native rate or one Apple conversion. |
| Offline export | Use highest-quality converter settings. |
| Audiophile mode | Avoid unnecessary conversion. |
| Crossfade between rates | Convert once into the session rate. |
| AI model input | Convert a copy, not the live stream. |

Use `AVAudioConverter` first for live playback.

Use `soxr` or SSRC when you need more offline control.

`soxr` exposes phase response, preserved bandwidth, aliasing, and rejection parameters.

SSRC describes itself as an audiophile-grade sample-rate converter for PCM WAV files.

Treat project descriptions as claims until you test them in your own harness.

---

## 9. Loudness normalization and true peak

Use ITU-R BS.1770-compatible measurement.

Do not normalize by sample peak only.

Peak normalization does not track perceived loudness.

Recommended metadata:

| Field | Purpose |
|---|---|
| Integrated loudness | Overall perceived loudness. |
| Loudness range | Dynamic range estimate. |
| Sample peak | Highest sample value. |
| True peak | Reconstructed peak estimate. |
| Track gain | Gain for shuffled playback. |
| Album gain | Gain preserving album balance. |

Playback rule:

```text
decoded audio
→ track or album gain
→ limiter
→ output
```

Use album gain for albums.

Use track gain for shuffled playlists.

Target a true-peak ceiling around `-1.0 dBTP` when the output path includes lossy encoding or device conversion.

---

## 10. Equalizer design

For version 1, use a parametric EQ.

A parametric EQ gives frequency, gain, and Q control.

Q means filter sharpness.

Recommended EQ path:

```text
pre-gain
→ high-pass filter if needed
→ low-shelf
→ parametric bands
→ high-shelf
→ limiter
```

Implementation tips:

| Issue | Fix |
|---|---|
| Clicks during slider movement | Smooth parameters over 5–50 ms. |
| Clipping after boosts | Add pre-gain. |
| Filter instability | Clamp frequency, gain, and Q. |
| Poor stereo image | Apply matched filters to left and right. |
| CPU spikes | Precompute coefficients outside callback. |

Use `vDSP` or a proven C++ biquad implementation.

Add sweep tests and impulse tests.

---

## 11. Limiter design

The limiter protects output quality after EQ and loudness gain.

Recommended first version:

| Parameter | Value |
|---|---:|
| Ceiling | `-1.0 dBFS` or `-1.0 dBTP` |
| Lookahead | 1–5 ms |
| Release | 50–200 ms |
| Oversampling | 2x or 4x for true-peak mode |
| Position | Last DSP stage |

Avoid aggressive compression in default mode.

Add a separate “Gym Mode” for noisy rooms.

Gym Mode can use compression because fidelity is not the main goal.

---

## 12. Room correction

Room correction can improve speaker playback more than changing the player engine.

It also carries higher risk than EQ.

| Technique | Benefit | Risk |
|---|---|---|
| Minimum-phase EQ | Low latency | Does not fix all time-domain problems. |
| Linear-phase FIR | Corrects phase and magnitude | Adds latency and pre-ringing. |
| Mixed-phase correction | Balances both | More complex design. |
| Partitioned convolution | Runs long filters efficiently | More complex buffering. |
| Multi-position correction | Better listening area | Needs multiple measurements. |

Practical rule:

```text
measurement import
→ target curve
→ correction filter
→ limiter
→ output
```

Do not boost deep nulls.

Deep nulls are often caused by cancellation.

Boosting them wastes headroom and can stress speakers.

Use cuts before boosts.

---

## 13. AI-based audio enhancement

AI can improve poor recordings.

AI can also invent content that was not in the source.

That conflicts with audiophile transparency.

| AI approach | Usefulness | Production recommendation |
|---|---|---|
| Music source separation | Remix, karaoke, analysis | Offline feature. |
| Audio super-resolution | Low-bandwidth sources | Offline preview only. |
| AI denoise | User recordings | Not default for mastered music. |
| Differentiable DSP | Controllable neural effects | Research path. |
| Neural audio codecs | Compression research | Not v1 playback. |
| Audio tagging | Library intelligence | Good background feature. |

Open-Unmix is a peer-reviewed open-source reference implementation.

Hybrid Transformer Demucs reports stronger separation results than older Demucs variants.

AudioSR is a diffusion-based audio super-resolution model.

DDSP combines classical DSP blocks with neural networks.

For your product, put these under “AI Lab Mode.”

Do not put them in default playback.

---

## 14. Apple-specific AI deployment

| Option | Best use | Notes |
|---|---|---|
| Core ML | Shipping models inside macOS app | Uses CPU, GPU, and Neural Engine. |
| coremltools | Convert PyTorch/TensorFlow models | Use during build or research flow. |
| MLX | Apple Silicon research and prototypes | Supports Python, C++, C, and Swift APIs. |
| PyTorch MPS | Training and experiments | Good for research, not final app runtime. |
| Metal Performance Shaders Graph | Custom graph compute | Use when Core ML is not enough. |

Use Core ML when you ship.

Use MLX when you experiment locally.

Do not run Core ML inference inside the real-time callback.

---

## 15. Real-time safety rules

| Rule | Reason |
|---|---|
| No heap allocation | Allocation can block. |
| No locks | Lock contention causes dropouts. |
| No file I/O | Disk latency is not bounded. |
| No network I/O | Network latency is not bounded. |
| No logging | Logging can lock or allocate. |
| No Core ML inside callback | Inference latency is not guaranteed. |
| No Swift object churn | Reference counting adds unpredictable work. |
| Use preallocated buffers | Keeps render time bounded. |
| Use lock-free parameter exchange | Keeps UI updates safe. |

RealtimeWatchdog checks for unsafe Core Audio thread activity.

It flags locks, memory allocation, Objective-C use, file I/O, and network I/O.

Use it as a development guardrail.

---

## 16. Testing plan

| Test | Method | Pass condition |
|---|---|---|
| Bypass null test | Output minus input | Near-zero residual where no conversion occurs. |
| Frequency response | Sweep or impulse | Matches target curve. |
| EQ stability | Parameter sweep | No clicks or unstable filters. |
| Clipping test | Full-scale sine and music | 0 clipped samples. |
| True-peak test | Oversampled meter | Peak below ceiling. |
| Loudness test | ITU-R BS.1770 vectors | Matches reference library. |
| Resampler test | Sweep conversion | No obvious aliasing or passband ripple. |
| CPU test | 128-frame buffer | No underruns under UI load. |
| Latency test | Loopback measurement | Document measured latency by device. |
| AI test | A/B comparison | AI must be optional and reversible. |

Use objective tests first.

Then run listening tests.

Do not rely on listening alone.

---

## 17. Recommended product modes

| Mode | Processing | User promise |
|---|---|---|
| Pure Mode | Decode → output | We do not change the sound. |
| Enhanced Mode | EQ → loudness gain → limiter | We improve consistency and prevent clipping. |
| Room Mode | Room correction → limiter | We correct speaker-room response from measurements. |
| Headphone Mode | Crossfeed → EQ → limiter | We reduce hard stereo separation. |
| AI Lab Mode | Offline AI tools | Experimental restoration and separation. |

For version 1, build:

```text
Pure Mode
Enhanced Mode
Analysis Mode
```

Add Room Mode after measurement import works.

Add AI Lab Mode after you build A/B comparison and rollback.

---

## 18. Implementation roadmap

| Phase | Build |
|---:|---|
| 1 | SwiftUI app, playlist, playback, AVAudioEngine output |
| 2 | C++23 DSP kernel with bypass, gain, limiter |
| 3 | Parametric EQ using biquad filters |
| 4 | Offline loudness scan using libebur128 |
| 5 | Waveform and spectrum cache using vDSP FFT |
| 6 | True-peak scan and clipping reports |
| 7 | Optional soxr or SSRC offline resampling |
| 8 | Room correction import using FIR filters |
| 9 | Core ML or MLX offline AI experiments |
| 10 | AUv3 plug-in version for Logic Pro or GarageBand support |

---

## 19. Recommended v1 dependency list

| Component | Choice | Reason |
|---|---|---|
| UI | SwiftUI | Native macOS UI. |
| Audio graph | AVAudioEngine | Native graph and output path. |
| Output | Core Audio through Apple APIs | Best Apple platform integration. |
| DSP core | C++23 | Predictable real-time code. |
| Math acceleration | Accelerate / vDSP | Apple-optimized vector DSP. |
| Loudness | libebur128 | Implements EBU R128 style measurement. |
| Codec fallback | FFmpeg | Use only when Apple APIs miss a format. |
| Resampling expert mode | soxr or SSRC | Better control for offline conversion. |
| AI shipping | Core ML | Best Apple app deployment path. |
| AI research | MLX | Apple Silicon research framework. |

---

## 20. Actively maintained C/C++ audio libraries with release and community signals

This section was added on 2026-06-17.

Maintenance was judged using recent releases, visible repository activity, package-manager updates, security response, and project adoption.

Community signal was judged using GitHub visibility, ecosystem use, packaging availability, and use by other audio projects.

### 20.1 Strong maintenance signals

| Library | Category | Maintenance signal | Community signal | Recommendation for your player |
|---|---|---|---|---|
| JUCE | C++ audio app and plug-in framework | GitHub releases show JUCE 8.x releases, including 8.0.12 in the current release feed. | Used across commercial and open-source audio plug-ins. Supports VST3, AU, AUv3, AAX, and LV2. | Use only if cross-platform release or plug-in hosting is a product goal. |
| miniaudio | C/C++ playback, capture, decoding, and mixing | Latest release page showed v0.11.25 on 2026-03-04. | Single-file design, no external dependencies, and broad desktop/mobile platform support. | Good fallback for tools or cross-platform experiments. For Apple-only output, use AVAudioEngine/Core Audio. |
| FFmpeg | Codec, container, conversion, and filter stack | Official FFmpeg page announced 8.1 “Hoare” on 2026-03-16. Download page also showed maintained release branches. | Industry-standard multimedia stack with broad codec/container support. | Use as a fallback for formats not covered by Apple APIs. Check LGPL/GPL build configuration. |
| Faust | DSP language and C++ code generation | GitHub release page showed recent 2.8x releases. Faust-to-CLAP work appeared in current research and tooling. | Used for DSP prototyping, code generation, and audio research. | Use to prototype EQ, filters, and effects, then port or generate C++ for the DSP kernel. |
| Rubber Band Library | Time-stretching and pitch-shifting | Official page announced v4.0 on 2024-10-25. | Used by audio/video tools for tempo and pitch changes. | Use for optional tempo and pitch features. Keep it out of default hi-fi playback. |
| KissFFT | Fast Fourier Transform | GitHub and distribution metadata show 131.x packaging, including 131.2.0 in Fedora/Arch metadata. | Small, portable, BSD-licensed FFT library. | Use as a portable FFT fallback. On Apple Silicon, prefer Accelerate/vDSP first. |
| PFFFT | FFT and fast convolution | Repository and package metadata show active packaging updates in 2026. | Small FFT library with ARM NEON support, including Apple Silicon. | Good portable FFT/convolution fallback if you do not want to depend only on vDSP. |
| r8brain-free-src | Sample-rate conversion | Repository and documentation were current enough to be useful; project had 2026 issue activity. | Known in audio-development communities for high-quality resampling. MIT license helps commercial apps. | Use for offline or expert-mode sample-rate conversion. For live playback, start with AVAudioConverter. |
| dr_libs | WAV, FLAC, MP3 single-file decoders | vcpkg listed 2026 package versions. Security issues were discussed publicly in 2026, with fix guidance to update to latest master. | Common in games, tools, and lightweight C/C++ projects. | Use for test tools or simple import paths. Avoid old versions for untrusted files. |
| Essentia | C++ audio and music information retrieval | PyPI showed a 2026 release for the Python package backed by the C++ library. | Used in MIR research and music-analysis tooling. MIR means music information retrieval. | Useful for offline analysis. AGPLv3 license can be incompatible with closed-source commercial apps. |

### 20.2 Useful but not “actively maintained” by release cadence

| Library | Category | Maintenance signal | Why still useful | Recommendation |
|---|---|---|---|---|
| libebur128 | Loudness and true-peak measurement | Latest GitHub release was older, around 2021. | EBU R128 and ITU-R BS.1770 are stable standards. | Use with regression tests against known loudness vectors. |
| libsamplerate | Sample-rate conversion | Latest GitHub release shown was 0.2.2 from 2021. | Mature library with BSD-style licensing. | Fine for tooling. Prefer r8brain, soxr, or AVAudioConverter for production decisions. |
| soxr | Sample-rate conversion | Upstream release cadence is old, but it remains packaged and downloaded. | Exposes phase, bandwidth, aliasing, and rejection controls. | Good for offline expert conversion after you test it. |
| libsndfile | WAV, AIFF, and sampled audio file I/O | Latest GitHub release shown was 1.2.2 from 2023-08-13. | Mature and widely packaged. | Use for test tools and offline exports. |
| RtAudio | Cross-platform real-time audio I/O | Official latest release was 6.0.1 from 2023-08-01. | Stable cross-platform API for ALSA, JACK, PulseAudio, OSS, macOS, and Windows APIs. | Use only if you need cross-platform audio I/O. Do not use for Apple-only output. |
| zita-convolver | Convolution | Older cadence and GPL license. | Useful technical design for partitioned convolution. | Use as reference or in GPL-compatible products. |

### 20.3 My current shortlist

For your Apple Silicon C++23 + Swift player:

| Need | Pick | Why |
|---|---|---|
| macOS output | AVAudioEngine / Core Audio | Native device integration and routing. |
| Real-time DSP | Your C++23 engine | Keeps the render path predictable. |
| Vector math / FFT | Accelerate / vDSP | Apple-optimized path for Apple Silicon. |
| Portable FFT fallback | PFFFT or KissFFT | Small and portable. |
| EQ/filter prototyping | Faust | Fast DSP iteration and C++ generation. |
| Loudness scan | libebur128 | Implements the standard workflow. |
| Offline resampling | r8brain-free-src | MIT-licensed C++ resampler. |
| Codec fallback | FFmpeg | Broadest codec/container support. |
| Simple test decoders | dr_libs | Single-file WAV/FLAC/MP3 tooling. |
| Time-stretch/pitch | Rubber Band | Specialist library for tempo and pitch. |
| Offline music analysis | Essentia | Strong analysis coverage, but check AGPLv3. |
| Cross-platform app future | JUCE | Full app and plug-in ecosystem. |

### 20.4 Decision

Do not replace Apple’s audio output path with a cross-platform library unless cross-platform release is required.

Use this stack first:

```text
SwiftUI
→ AVAudioEngine / Core Audio
→ C++23 DSP kernel
→ Accelerate / vDSP
→ libebur128
→ r8brain-free-src
→ FFmpeg fallback only when needed
```

Use JUCE later only if you decide to ship Windows/Linux builds or plug-in formats.

---

## 21. Final recommendation

For an Apple-only music player:

```text
Apple native output
+ C++23 real-time DSP
+ Accelerate / vDSP
+ selected open-source libraries
+ optional offline AI
```

This gives the best balance between fidelity, control, latency, power efficiency, and maintenance.

Do not enhance every track by default.

Make every processing step measurable, visible, and reversible.

---

# Verified references

The links below were checked against official pages, standards pages, paper pages, or original repositories on 2026-06-17.

## Apple official documentation and platform material

1. Apple AVAudioEngine documentation  
   https://developer.apple.com/documentation/avfaudio/avaudioengine

2. Apple AVAudioConverter documentation  
   https://developer.apple.com/documentation/avfaudio/avaudioconverter

3. Apple Technical Note TN3136: AVAudioConverter sample-rate conversion  
   https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions

4. Apple Core ML documentation  
   https://developer.apple.com/documentation/coreml

5. Apple Core ML overview  
   https://developer.apple.com/machine-learning/core-ml/

6. Apple Accelerate framework  
   https://developer.apple.com/documentation/accelerate

7. Apple vDSP audio unit sample  
   https://developer.apple.com/documentation/accelerate/creating-an-audio-unit-extension-using-the-vdsp-library

8. Apple FFT documentation  
   https://developer.apple.com/documentation/accelerate/fast-fourier-transforms

9. Apple Metal overview  
   https://developer.apple.com/metal/

10. Apple Metal Performance Shaders  
    https://developer.apple.com/documentation/metalperformanceshaders

11. Apple Metal Performance Shaders Graph  
    https://developer.apple.com/documentation/metalperformanceshadersgraph

12. Apple PyTorch MPS backend page  
    https://developer.apple.com/metal/pytorch/

13. Apple AUv3 custom audio effects sample  
    https://developer.apple.com/documentation/avfaudio/creating-custom-audio-effects

14. Apple signal generator sample  
    https://developer.apple.com/documentation/avfaudio/building-a-signal-generator

15. Swift C++ interoperability  
    https://www.swift.org/documentation/cxx-interop/

16. Apple M1 announcement  
    https://www.apple.com/newsroom/2020/11/apple-unleashes-m1/

17. Apple M1 MacBook Air technical specification  
    https://support.apple.com/en-lk/111883

18. Apple M5 announcement  
    https://www.apple.com/newsroom/2025/10/apple-unleashes-m5-the-next-big-leap-in-ai-performance-for-apple-silicon/

19. Apple M5 MacBook Air technical specification  
    https://support.apple.com/en-lk/126320

## Standards and engineering references

20. ITU-R BS.1770-5: loudness and true-peak measurement  
    https://www.itu.int/rec/R-REC-BS.1770

21. ITU-R BS.1770-5 PDF  
    https://www.itu.int/dms_pubrec/itu-r/rec/bs/R-REC-BS.1770-5-202311-I!!PDF-E.pdf

22. AES loudness references and standards list  
    https://aes.org/resources/audio-topics/loudness-project/resources-and-references/

23. EBU R128 publication page  
    https://tech.ebu.ch/publications/r128/

## Open-source DSP and audio libraries

24. libebur128  
    https://github.com/jiixyj/libebur128

25. soxr / SoX Resampler library  
    https://sourceforge.net/projects/soxr/

26. libsamplerate / Secret Rabbit Code  
    https://github.com/libsndfile/libsamplerate

27. Shibatch Sample Rate Converter  
    https://github.com/shibatch/ssrc

28. FFmpeg codecs documentation  
    https://ffmpeg.org/ffmpeg-codecs.html

29. FFmpeg legal and license information  
    https://www.ffmpeg.org/legal.html

30. JUCE framework  
    https://github.com/juce-framework/JUCE

31. AudioKit  
    https://github.com/AudioKit/AudioKit

32. RealtimeWatchdog  
    https://github.com/TheAmazingAudioEngine/RealtimeWatchdog

## Apple Silicon machine learning projects

33. MLX official repository  
    https://github.com/ml-explore/mlx

34. MLX official project page  
    https://opensource.apple.com/projects/mlx

35. MLX unified memory documentation  
    https://ml-explore.github.io/mlx/build/html/usage/unified_memory.html

36. coremltools  
    https://github.com/apple/coremltools

37. coremltools PyTorch conversion workflow  
    https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html

38. PyTorch MPS backend documentation  
    https://docs.pytorch.org/docs/stable/notes/mps.html

## Peer-reviewed or research material

39. Open-Unmix JOSS paper  
    https://joss.theoj.org/papers/10.21105/joss.01667

40. Open-Unmix PyTorch repository  
    https://github.com/sigsep/open-unmix-pytorch

41. Open-Unmix project page  
    https://sigsep.github.io/open-unmix/

42. Hybrid Transformer Demucs paper  
    https://arxiv.org/abs/2211.08553

43. Demucs repository  
    https://github.com/facebookresearch/demucs

44. AudioSR paper  
    https://arxiv.org/abs/2309.07314

45. AudioSR project page  
    https://audioldm.github.io/audiosr/

46. AudioSR repository  
    https://github.com/haoheliu/versatile_audio_super_resolution

47. DDSP OpenReview paper  
    https://openreview.net/forum?id=B1x1ma4tDr

48. DDSP repository  
    https://github.com/magenta/ddsp

49. Review of differentiable DSP for music and speech synthesis  
    https://doi.org/10.3389/frsip.2023.1284100

50. Room Response Equalization — A Review  
    https://www.mdpi.com/2076-3417/8/1/16

51. Real-time low-latency music source separation using Hybrid Spectrogram-TasNet  
    https://arxiv.org/abs/2402.17701

52. PEAQ reassessment paper  
    https://arxiv.org/abs/2212.01467

## Additional references for actively maintained C/C++ libraries

53. JUCE GitHub releases  
    https://github.com/juce-framework/JUCE/releases

54. JUCE project repository  
    https://github.com/juce-framework/JUCE

55. miniaudio GitHub releases  
    https://github.com/mackron/miniaudio/releases

56. miniaudio official project page  
    https://miniaud.io/

57. FFmpeg official website  
    https://www.ffmpeg.org/

58. FFmpeg official download page  
    https://ffmpeg.org/download.html

59. Faust GitHub releases  
    https://github.com/grame-cncm/faust/releases

60. Faust project repository  
    https://github.com/grame-cncm/faust

61. Rubber Band Library official page  
    https://breakfastquay.com/rubberband/

62. Rubber Band GitHub mirror  
    https://github.com/breakfastquay/rubberband

63. KissFFT repository  
    https://github.com/mborgerding/kissfft

64. KissFFT Fedora package metadata  
    https://rpmfind.net/linux/RPM/fedora/44/s390x/k/kiss-fft-131.2.0-1.fc44.s390x.html

65. PFFFT repository  
    https://github.com/marton78/pffft

66. PFFFT FreeBSD package metadata  
    https://www.freshports.org/math/pffft

67. r8brain-free-src repository  
    https://github.com/avaneev/r8brain-free-src

68. r8brain-free-src documentation  
    https://www.voxengo.com/public/r8brain-free-src/Documentation/

69. dr_libs repository  
    https://github.com/mackron/dr_libs

70. drlibs vcpkg package metadata  
    https://vcpkg.io/en/package/drlibs.html

71. dr_libs 2026 security advisory reference  
    https://github.com/marlinkcyber/advisories/blob/main/advisories/MCSAID-2026-001-dr-libs-heap-overflow.md

72. RtAudio official page  
    https://caml.music.mcgill.ca/~gary/rtaudio/

73. Essentia repository  
    https://github.com/MTG/essentia

74. Essentia PyPI release page  
    https://pypi.org/project/essentia/

75. libsndfile GitHub releases  
    https://github.com/libsndfile/libsndfile/releases/

## Verification notes

- Apple sources were checked against Apple Developer, Apple Support, or Apple Newsroom pages.
- ITU and AES loudness references were checked against ITU and AES pages.
- Open-source projects were checked against original GitHub or SourceForge repositories.
- Peer-reviewed entries were checked against JOSS, Frontiers, MDPI, or OpenReview pages.
- arXiv papers were treated as research preprints unless a reviewed venue was also linked.
- Repository claims were not treated as proof of audio quality without independent testing.
