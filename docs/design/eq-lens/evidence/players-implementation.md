# How players and EQ tools implement their equalizers (algorithms and code)

*2026-10-09 · input to the AdaptiveSound EQ rebuild (Sprint EQ) · companion to `docs/product/eq-market-research.md`, which covers UX. This file covers implementation only.*

**Rules used here**
- Every row cites a page I opened in this session.
- **Confidence labels:**
  - **src**: I read the source file.
  - **doc**: official documentation, a vendor page or an app-store listing.
  - **paper**: a published paper, or the authors' own code.
  - **sec**: secondary (a forum, a search-result snippet of a page I could not open, or a third-party write-up).
- **"not found"** means I looked and found nothing documented. It is not a guess.
- "(my arithmetic)" marks numbers I derived from the cited constants.
- Several vendor pages returned HTTP 403 to the fetcher: Poweramp forum and FAQ, JRiver wiki and forum, Hydrogenaudio, Audirvana community, Sonarworks KB. Claims that rely on them are marked **sec**.

## TL;DR
1. **Most music players run a plain, uncompensated filter bank.**
   - Cascades: GStreamer `equalizer-nbands` (Strawberry, Clementine), Rockbox, eqMac/AVAudioUnitEQ, Audacious.
   - Parallel sum of band-pass filters: VLC.
   - None corrects band interaction. Rane's own measurement: two adjacent +6 dB sliders play **+9 dB** in a proportional-Q design.
2. **The accurate 31-band designs are of three kinds.**
   - **Compensated cascades:** Aalto's ACGE uses an interaction matrix plus a least-squares (LS) solve, ≤1 dB with 31 biquads. MathWorks uses an Oliver–Jot correction. Rane Perfect-Q computes each band's Q.
   - **FIR frequency-sampling:** Equalizer APO's GraphicEQ is a 16,384-tap minimum-phase FIR. FFmpeg `firequalizer` works the same way.
   - **Steep band-split filters:** LSP's 48–96 dB/oct "ladder-pass" bands, and the 4th-order bands in Calf's `orfanidis_eq` and FFmpeg's `anequalizer`.
3. **Near-Nyquist handling is crude in players.**
   - GStreamer clamps ω to π, Audacious drops the band, VLC zeroes it, and FFmpeg rejects it.
   - Only pro tools address cramping: FabFilter's analog-matched modes, and LSP's matched-Z versus bilinear choice.
   - ACGE had to **hand-tune the bandwidths of its top 6 bands** at 44.1 kHz.
4. **Automatic headroom comes in two forms.**
   - **From the control values:** eqMac `globalGain = −max(band gains)`, Rockbox `prescale = max(bass, treble, eq gains)`, Equalizer APO "Normalize response", foobar2000 "Auto level" (**sec**).
   - **From the realized response:** AutoEq takes `−(max of summed filter response)` plus 0.2 dB, and the Equalizer APO Editor pushes an impulse through the real engine and reads the peak.
   - The control-value form under-estimates the peak whenever bands overlap.
5. **De-zippering is almost absent in players.** No smoothing at all in GStreamer, VLC, Audacious, FFmpeg, Rockbox, DeaDBeeF or Android DynamicsProcessing. The good patterns:
   - Equalizer APO: **10 ms raised-cosine crossfade** between the old and new filter chains.
   - x42 fil4: per-sample ramps of lattice coefficients with a per-block rate limit.
   - Apple `vDSP_biquadm_SetTargets*`: per-sample coefficient stepping toward targets.
   - TPT/SVF topologies built "for fast modulation".
6. **"Draw what plays" is standard in pro and DSP tools.** LSP, FFmpeg `anequalizer`, FabFilter and the Equalizer APO analysis all draw from the real filters. Players show sliders. Audacity draws its interpolated target.
7. **Level-matched A/B exists only in pro tools.**
   - Pro-Q Auto Gain is a static estimate from the curve, not measured.
   - Ozone Gain Match matches levels on bypass and recommends lowering the processed side.
   - No consumer player documents it. Peak-based headroom is **not** a level match.
8. **Per-device memory has two strong precedents.**
   - EasyEffects keys on **device name + route**, matched exactly, with an optional fallback preset.
   - Equalizer APO pattern-matches device name, connection name and GUID.
   - On macOS the native keys are `kAudioDevicePropertyDeviceUID`, which is per machine and persistent, and `ModelUID`, which is the same across machines.
9. **"Neighbours follow" is not in any music player I found.** The closest precedents:
   - darktable's tone equalizer: "moving a single control point will also affect control points on either side", using an LS fit of Gaussian basis functions with a smoothing control that oscillates above about 0.6.
   - Drawing (Swinsian Ctrl-drag) and multi-select moves (Pro-Q, Ableton, Equalizer APO arrow keys).
10. **Tone macros mapped into bands:** eqMac uses naive plateaus, where Bass sets bands 0–2 to the same gain. AutoEq, ACGE and darktable all fit the bands to a target by optimisation.

---

# Part 1 — Findings by topic

## 1. Graphic EQ filter structure and band interaction

| Product | What it does | Evidence | Conf. |
|---|---|---|---|
| **GStreamer `equalizer-nbands`** (used by Strawberry, Clementine) | 1–64 bands (default 10). **Cascade**: each band filters the previous band's output. Band 0 is a low shelf, the last band a high shelf, the rest peaking. Peak uses `alpha=tan(bw/2)` with gain `10^(dB/40)` (bilinear, RBJ-style). Edges are log-spaced; `freq` = arithmetic midpoint of the edges; `width` = edge difference in Hz. Gain range −24…+12 dB. **No interaction compensation.** | [gstiirequalizer.c](https://github.com/GStreamer/gstreamer/blob/main/subprojects/gst-plugins-good/gst/equalizer/gstiirequalizer.c) (`setup_peak_filter`, `gst_iir_equalizer_compute_frequencies`); [nbands.c](https://github.com/GStreamer/gstreamer/blob/main/subprojects/gst-plugins-good/gst/equalizer/gstiirequalizernbands.c) | src |
| **Strawberry** | Configures GStreamer with `num-bands = 10 + 2`. The two **dummy bands at 20 Hz and 20 kHz have zero width**, so the real end bands are peaks, not shelves. Bands: {60, 170, 310, 600, 1k, 3k, 6k, 12k, 14k, 16k}. Bandwidth = this band's frequency minus the previous band's. UI value −100…100 maps to dB as ×0.12 if positive (max +12) and ×0.24 if negative (max −24). | [gstenginepipeline.cpp](https://github.com/strawberrymusicplayer/strawberry/blob/master/src/engine/gstenginepipeline.cpp) (`InitAudioBin`, `UpdateEqualizer`) | src |
| **EasyEffects** | LSP `para_equalizer_x32_lr`. Auto-spaced bands from 20 Hz to 20 kHz; `q = freq/width` from geometric edges. That is **Q ≈ 4.65 at 32 bands** (my arithmetic). | [equalizer.cpp](https://github.com/wwmm/easyeffects/blob/master/src/equalizer.cpp) (`calculateFrequencies`) | src |
| **Audacious** | 10 octave bands at 31.25·2^k Hz; Q = √1.5 ≈ 1.22 ("4 dB suppression at Fc·2 and Fc/2"). Each stage adds `g·bandpass(running signal)`, so it is a **cascade of (1 + g·BP) stages**. Bands too close to Nyquist are dropped. | [equalizer.cc](https://github.com/audacious-media-player/audacious/blob/master/src/libaudcore/equalizer.cc) (`bp2`, `eq_filter`) | src |
| **VLC** | 10 band-pass filters, one octave wide, **in parallel**: `out = gamp·(0.25·x + Σ amp_j·BP_j)` with `amp = 0.25·(10^(dB/20)−1)`, clamped to ±20 dB. An optional "2-pass" runs the bank twice. | [equalizer.c](https://github.com/videolan/vlc/blob/master/modules/audio_filter/equalizer.c) (`EqzCoeffs`, `EqzFilter`) | src |
| **Rockbox** | 10 bands: low shelf + 8 peaks + high shelf, each with its own cutoff and Q. Coefficients "taken from Audio-EQ-Cookbook" (RBJ), fixed-point s3.28/s5.26, max 24 dB. **Cascade**, uncompensated. | [eq.c](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/eq.c); [dsp_filter.c](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/dsp_filter.c) | src |
| **eqMac** (public v1.3.2 code) | `AVAudioUnitEQ` with 10 bands at 32…16k Hz, all `.parametric`, `bandwidth = 0.5` (Apple: in **octaves**, 0.05–5). Cascade, uncompensated. | [Equalizer.swift](https://github.com/bitgapp/eqmac/blob/master/native/app/Source/Audio/Effects/Equalizers/Equalizer.swift); [Apple bandwidth](https://developer.apple.com/documentation/avfaudio/avaudiouniteqfilterparameters/bandwidth) | src + doc |
| **Apple AUGraphicEQ** (Core Audio) | `kGraphicEQParam_NumberOfBands`: "currently either 10 or 31". Algorithm: **not found**. | [AudioUnitParameters.h (SDK mirror)](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.15.sdk/System/Library/Frameworks/AudioToolbox.framework/Versions/A/Headers/AudioUnitParameters.h) | doc |
| **Equalizer APO GraphicEQ** | **Minimum-phase FIR by frequency sampling.** Nodes are interpolated **linearly in dB against log-frequency**, and the gain is held flat beyond the first and last node. The spectrum is sampled at `i·fs/(2·16384)`. Minimum phase comes from a cepstral fold; the 16,384 taps get a half-Hann window. Any number of nodes; the Editor offers 15, 31 or variable. **No band interaction by construction.** | [GraphicEQFilter.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/filters/GraphicEQFilter.cpp) (`mps`); [Factory](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/filters/GraphicEQFilterFactory.cpp) (`GraphicEQFilter(nodes, 16384)`); [GainIterator.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/helpers/GainIterator.cpp); [config ref](https://sourceforge.net/p/equalizerapo/wiki/Configuration%20reference/) | src (port of upstream 1.4.2) + doc |
| **SuperEQ** (FFmpeg `superequalizer`; DeaDBeeF; foobar2000 "based on the SuperEQ library") | 18 bands. FIR = Σ gain_i × (difference of windowed-sinc low-passes) at fixed band edges, which gives **step-like transitions with no interpolation**. Kaiser window (A = 96). In FFmpeg: 8,191 taps, 16k FFT overlap-add. Gains are linear (0–20). | [af_superequalizer.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_superequalizer.c) (`make_fir`, `hn`); [DeaDBeeF supereq.c](https://github.com/DeaDBeeF-Player/deadbeef/blob/master/plugins/supereq/supereq.c); [foobar2000](https://www.foobar2000.org/equalizer) | src + doc |
| **FFmpeg `firequalizer`** | Arbitrary `gain_entry` points (up to 4,096), with `gain_interpolate` (linear) or `cubic_interpolate` (slope-limited). The FIR is windowed (Hann by default), with optional `min_phase`, `zero_phase`, and dB or log-frequency scaling. | [af_firequalizer.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_firequalizer.c) (`generate_kernel`) | src |
| **FFmpeg `anequalizer`**, **Calf EQ30** (`orfanidis_eq`) | **High-order band filters**, which reduce overlap. FFmpeg uses `FILTER_ORDER 4` (Butterworth / Cheb-I / Cheb-II). Calf offers Butterworth / Cheb1 / Cheb2 / elliptic, default order 4, 30 third-octave bands from 31.25 Hz, in cascade. | [af_anequalizer.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_anequalizer.c); [orfanidis_eq.h](https://github.com/calf-studio-gear/calf/blob/master/src/calf/orfanidis_eq.h) | src |
| **LSP Graphic Equalizer** (16/32 bands) | First band LRX low-shelf, last LRX high-shelf, middle bands `LRX_LADDERPASS`. Corners sit at the **geometric means of neighbouring centres**. Slopes 48/72/96 dB/oct. Modes IIR / FIR / FFT / SPM; transforms BLT or MT. My reading: steep band-split bands meet like a crossover, so interaction stays low. | [graph_equalizer.cpp](https://github.com/lsp-plugins/lsp-plugins-graph-equalizer/blob/master/src/main/plug/graph_equalizer.cpp) (`update_settings`); [manual](https://lsp-plug.in/?page=manuals&section=graph_equalizer_x32_stereo) | src + doc |
| **AutoEq** (fitting into a fixed graphic EQ) | Configs: `10_BAND_GRAPHIC_EQ` (Q √2, 31.25·2^i Hz) and `31_BAND_GRAPHIC_EQ` (**Q 4.318473, fc = 20·2^(i/3)**, ±12 dB). The fixed fc/Q filters are **gain-optimised against the summed dB response**, so interaction is compensated. Biquads follow the RBJ form. | [constants.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/constants.py); [peq.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/peq.py) | src |
| **ACGE** (Aalto: Liski & Välimäki, DAFx-17; Välimäki & Liski, IEEE SPL 2017) | **31 Orfanidis peak/notch biquads in cascade.** The interaction matrix is **61×31**: 31 centres plus 30 geometric midpoints. Prototype gain is 17 dB, and the band edge is set at c = 0.4 × peak-dB. Bandwidth `B=(2^(1/6)−2^(−1/6))ω_c ≈ 0.466ω_c`. Gains come from the pseudoinverse LS solve `g = B⁺t` **plus one iteration**. Max error **0.41 dB** (zigzag) and **0.98 dB** (hard case), against 0.65/0.66 dB for the parallel PGE. **279 vs 496 ops/sample.** The paper's code uses `fs = 44.1e3`. | [DAFx-17 paper](http://www.dafx17.eca.ed.ac.uk/papers/DAFx17_paper_94.pdf) §4–5, Tables 1–3; [acge3.m](http://research.spa.aalto.fi/publications/papers/dafx17-geq/acge3.m) | paper |
| **Rämö, Liski, Välimäki 2020** | Third-octave GEQ with **symmetric band filters** and iterative weighted LS: **0.81 dB** max error. A neural-net gain predictor computes gains about 100× faster, with slightly larger error. | [Aalto abstract](https://research.aalto.fi/fi/publications/third-octave-and-bark-graphic-equalizer-design-with-symmetric-ban/) | paper (abstract only; full text 403) |
| **MathWorks Audio Toolbox `graphicEQ`** | `Cascade` (default; multibandParametricEQ) or `Parallel`. For 1/3-octave: **30 bands, 25 Hz–19,953 Hz**. The cascade with order 2 gets an **Oliver–Jot gain correction**, which is recomputed only when the sample rate changes. | [graphicEQ doc](https://au.mathworks.com/help/audio/ref/graphiceq-system-object.html) | doc |
| **Rane Perfect-Q** (DEQ 60, 30-band ⅓-oct) | "Calculates the perfect Q required to create the exact response dictated by the front panel slider positions." Proportional-Q: two adjacent sliders at +6 dB **play +9 dB**. | [RaneNote 154](https://www.ranecommercial.com/legacy/note154.html) | doc |
| **Android DynamicsProcessing** (AOSP; Wavelet/Poweramp reportedly use it) | FFT processing. Block ≤16,384, sqrt Hann-flat-top analysis and synthesis windows. Pre- and post-EQ apply **one constant factor per bin across each band, a stepwise response** with no interpolation between bands. | [DPFrequency.cpp](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/libeffects/dynamicsproc/dsp/DPFrequency.cpp); "same API that Poweramp EQ & Wavelet both use" [codekk](https://p.codekk.com/detail/6a0208c45b02fc5c75bba04c) | src; sec (the attribution) |
| **Poweramp** | Graphic mode, 5–32 bands. **"Bands Overlap: Envelope (default) / Cascade"**: in Cascade, overlapping gains sum; in Envelope they don't. Staff say a larger "block size" raises the FFT resolution. | search snippets of [forum 23937](https://forum.powerampapp.com/topic/23937-eq-parameter-ranges-parametric-equalizer/) and [27216](https://forum.powerampapp.com/topic/27216-bass-boost-with-greater-precision/) (403 on fetch) | sec |
| Wavelet · Neutron · Audirvana · Waves GEQ | Wavelet: "9 bands". Neutron: "Parametric Equalizer (4–130 band, per channel)" plus "Graphic EQ mode". Audirvana: 10 parametric bands. Waves GEQ: "30 ISO bands", "two filter designs". Their algorithms: **not found**. | [Wavelet](https://pittvandewitt.github.io/Wavelet/Features/); [Neutron listing](https://apps.apple.com/app/id766858884); [Audirvana](https://help.audirvana.com/support/solutions/articles/202000096012-how-to-use-the-integrated-studio-equalizer-eq-); [Waves](https://www.waves.com/plugins/geq-graphic-equalizer) | doc |
| Apple Music · Spotify | Fader EQ with presets. Algorithm: **not found**. | [Apple](https://support.apple.com/en-nz/guide/music/museb684a3de/mac); [Spotify](https://support.spotify.com/us/article/equalizer/) | doc |

**Takeaways**
- The DAFx-17 paper states the field's own consensus:
  - Parallel banks "often led to notches in the transition region".
  - FIR designs suffer because "the impulse response associated with a sharp change in a low-frequency band becomes very long".
  - Its conclusion: "the best graphic EQ design must be based on the cascading of second-order band filters", with LS gain compensation (§2).
- In practice, three shipping families reach accuracy:
  - compensated cascades (ACGE, MathWorks, Rane);
  - FIR frequency sampling (Equalizer APO, firequalizer);
  - steep band-split filters (LSP, Calf, anequalizer).
- Every mainstream player listed uses none of the three.

## 2. Near-Nyquist handling of the top bands (16–20 kHz at 44.1/48 kHz)

| Product | What it does | Evidence | Conf. |
|---|---|---|---|
| GStreamer | `calculate_omega`: if `freq/rate ≥ 0.5` then ω = π. `calculate_bw`: bandwidth clamped to "π − 1e-8", and zero width means passthrough. The design is bilinear (`tan(bw/2)`); **cramping is not compensated**. | [gstiirequalizer.c](https://github.com/GStreamer/gstreamer/blob/main/subprojects/gst-plugins-good/gst/equalizer/gstiirequalizer.c) | src |
| Audacious | **Drops bands**: `while (K > 0 && CF[K-1] > rate / (2.005f * Q)) K--`. | [equalizer.cc](https://github.com/audacious-media-player/audacious/blob/master/src/libaudcore/equalizer.cc) | src |
| VLC | "Any frequency beyond the Nyquist frequency is no good": alpha, beta and gamma are set to 0, so the band goes silent. | [equalizer.c](https://github.com/videolan/vlc/blob/master/modules/audio_filter/equalizer.c) | src |
| FFmpeg `equalizer` (af_biquads) | RBJ peaking `A=10^(dB/40)`. If `w0 > π`, it returns EINVAL, or bypasses at init. No decramping. | [af_biquads.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_biquads.c) | src |
| Rockbox | Cutoff is normalised so that 0x80000000 = Nyquist. "No Nyquist-specific guard." RBJ. | [dsp_filter.c](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/dsp_filter.c) | src |
| Equalizer APO GraphicEQ | FIR sampled at bins up to just below Nyquist, so the magnitude is exact at bin resolution and there is **no cramping**. Above the last node the gain is **held flat to Nyquist**. | [GraphicEQFilter.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/filters/GraphicEQFilter.cpp); [GainIterator.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/helpers/GainIterator.cpp) | src |
| AutoEq GraphicEQ export | 127 points with step 1.0563, ending at **19,871 Hz**. The first point is clamped to ≤ 0 dB ("Prevent bass boost below lowest frequency"). | [constants.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/constants.py); [frequency_response.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/frequency_response.py) (`eqapo_graphic_eq`) | src |
| LSP | Documents the trade-off. BLT "distorts the curve and can cause cramping at Nyquist" (oversampling helps). MT gives "identical to the analog filters frequency and phase graph" but "can alias at high frequencies". | [graph EQ manual](https://lsp-plug.in/?page=manuals&section=graph_equalizer_x32_stereo) | doc |
| FabFilter Pro-Q | Zero Latency "matches the magnitude response of analog EQing as closely as possible". For a 15 kHz bell it is "nearly perfect, except for a small deviation above 18 kHz". Natural Phase "matches the theoretical analog magnitude response precisely". | [processing mode](https://www.fabfilter.com/help/pro-q/using/processingmode) | doc |
| ACGE | Because band filters become asymmetric near Nyquist, "the bandwidths of the six uppermost filters are tuned by hand" at 44.1 kHz: 6.35k→2846, 8k→3502, 10.08k→4253, 12.7k→5038, 16k→5689, 20.16k→5573 Hz. | [DAFx-17](http://www.dafx17.eca.ed.ac.uk/papers/DAFx17_paper_94.pdf) §5, Table 1 | paper |
| MathWorks `graphicEQ` | Parallel: when the top band edge exceeds Nyquist, "the final filter is implemented as a highpass". Cascade: the correction is recomputed on a sample-rate change. | [graphicEQ doc](https://au.mathworks.com/help/audio/ref/graphiceq-system-object.html) | doc |
| Vicanek, "Matched Second Order Digital Filters" | BLT causes "frequency warping towards the Nyquist frequency … a narrowing of the resonant peak". The paper gives closed-form matched biquads, including a peaking EQ, "so the filter characteristic may be modulated with near sample rate updating". | [BiquadFits.pdf](https://www.vicanek.de/articles/BiquadFits.pdf) §1, §3.1 | paper |

**Takeaway.** No consumer player compensates cramping: they clamp, drop or zero the band. A 31-band design at 44.1 kHz needs a per-sample-rate decision for the 16, 20 and 20.16 kHz bands. That is either hand-tuned bandwidths (ACGE) or matched or prescribed-Nyquist-gain band filters (Vicanek; Rämö 2020's "symmetric band filters", whose Nyquist-gain detail I saw only in the abstract via search, so **sec**).

## 3. Clipping and headroom

### 3a. Preamp: manual or automatic, and how the automatic one is computed

| Product | What it does | Evidence | Conf. |
|---|---|---|---|
| **eqMac Basic** | **Auto, from the control values**: `let highestGain = gains.max()!; globalGain = -highestGain`, applied when `peakLimiter` is on and the maximum is above 0. | [BasicEqualizer.swift](https://github.com/bitgapp/eqmac/blob/master/native/app/Source/Audio/Effects/Equalizers/Basic/BasicEqualizer.swift) | src |
| **Rockbox** | **Auto, from the control values**: `prescale = MAX(bass, treble)`, then `MAX(eq_gain[i], prescale)`, clamped to ≥ 0. The **analog volume is raised by the same amount** (`volume += prescale`), which keeps loudness while gaining headroom. A separate manual "EQ precut" goes through the PGA stage. | [firmware/sound.c](https://github.com/Rockbox/rockbox/blob/master/firmware/sound.c) (`set_prescaled_volume`); [eq.c](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/eq.c) | src |
| **AutoEq** | **Auto, from the realized response.** PEQ: `Preamp: -compound.max_gain`, where `max_gain = np.max(Σ filter dB responses)` over the frequency grid (the README adds −0.1 dB). GraphicEQ export: `fr.raw -= max(fr.raw) + PREAMP_HEADROOM` with **PREAMP_HEADROOM = 0.2 dB**. | [frequency_response.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/frequency_response.py); [peq.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/peq.py); [constants.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/constants.py) | src |
| **Equalizer APO** | `Preamp:` is manual ("to make sure that no clipping occurs"), and multiple preamps add in dB. Editor "Normalize response": `node.dbGain -= maxGain` on the nodes. Editor analysis: `peakGain` (dB) taken from the **FFT of the real engine's impulse response**. | [config ref](https://sourceforge.net/p/equalizerapo/wiki/Configuration%20reference/); [GraphicEQFilterGUI.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/Editor/guis/GraphicEQFilterGUI.cpp); [AnalysisThread.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/Editor/AnalysisThread.cpp) | doc + src |
| **Wavelet** | Attenuator, automatic mode: "calculates the highest gain of all features in Wavelet combined" "to prevent clipping or distortion". The limiter has manual post-gain. | [Features](https://pittvandewitt.github.io/Wavelet/Features/) | doc |
| **Audirvana Studio EQ** | Output Gain "Auto" "automatically reduces the Output Gain". Example: a +24 dB boost lowers it by "−24 dB". No formula is given. A red "Clipping Output" label appears, with per-channel overs above 0 dBFS that stay until clicked. | [Audirvana help](https://help.audirvana.com/support/solutions/articles/202000096012-how-to-use-the-integrated-studio-equalizer-eq-) | doc |
| **Neutron** | "Normalization by Peak, RMS (**Preamp gain calculation after DSP effects**)", so the gain is computed from the signal after the EQ. | [App Store listing](https://apps.apple.com/app/id766858884) | doc |
| **FabFilter Pro-Q** | "Unlimited internal headroom and will never clip itself". Meters warn only about clipping downstream. | [output options](https://www.fabfilter.com/help/pro-q/using/output) | doc |
| **Roon** | **Manual** Headroom Management ("Start by setting the Headroom adjustment to −3dB"). A Clipping Indicator turns the signal-path light red and "is always at maximum sensitivity". | [headroom](https://help.roonlabs.com/portal/en/kb/articles/dsp-engine-headroom-management) | doc |
| **SoundID Reference** | "Safe Headroom": lowers the output by **the maximum peak of the correction curve** (12.4 dB peak → −12.4 dB). When several profiles are loaded, all adopt the lowest headroom "to avoid sudden gain jumps". | search snippet of the [Sonarworks KB](https://soundid-reference.support.sonarworks.com/hc/en-us/articles/7739576591506-Safe-Headroom) (redirect/403) | sec |
| **foobar2000** | EQ panel has an "**Auto level**" button described as lowering the curve so the highest band sits at 0 dB. Advanced Limiter is a separate DSP. | search snippet of [Hydrogenaudio](https://hydrogenaudio.org/index.php?msg=794751) (403) | sec |
| **Poweramp** | Has a preamp and a limiter (official). With DVC (Direct Volume Control) off, a "No DVC Headroom Gain" (default **−6 dB**) applies. With DVC on, the system volume carries the gain, so negative gain is usually not needed. Per-output and per-device overrides exist. | [powerampapp.com](https://powerampapp.com/?p=966) (doc); snippet of the [DVC FAQ](https://forum.powerampapp.com/kb/en_us/faq/using-direct-volume-control-dvc-r42/) (403) | doc + sec |
| **JRiver** | "Clip Protection" (default Overflow Handling): lowers the overall gain instead of flat-lining, i.e. a **signal-driven** gain reduction. | snippet of the [JRiver wiki](https://wiki.jriver.com/index.php/Overflow_Handling) (403) | sec |
| Manual-only | Apple Music (preamp: "adjust the overall volume of frequencies"); VLC (preamp default +12 dB offsets the 0.25 input factor); Audacious (preamp dB added to every band); DeaDBeeF (preamp folded into the FIR band gains); Strawberry (`(preamp+100)·0.01`, a linear 0–2× multiplier); SoundSource 6 ("10-Band EQ now features a preamp"). | [iTunes](https://support.apple.com/en-ca/guide/itunes/itns2991/mac); [VLC](https://github.com/videolan/vlc/blob/master/modules/audio_filter/equalizer.c); [Audacious](https://github.com/audacious-media-player/audacious/blob/master/src/libaudcore/equalizer.cc); [DeaDBeeF](https://github.com/DeaDBeeF-Player/deadbeef/blob/master/plugins/supereq/supereq.c); [Strawberry](https://github.com/strawberrymusicplayer/strawberry/blob/master/src/engine/gstenginepipeline.cpp); [SoundSource RN](https://rogueamoeba.com/support/releasenotes/?product=SoundSource) | doc + src |

### 3b. Order relative to ReplayGain or loudness normalisation, and limiters

| Product | Chain order and protection | Evidence | Conf. |
|---|---|---|---|
| Strawberry | queue → **ReplayGain (rgvolume → rglimiter)** → **EBU R128 volume** → **EQ preamp → EQ** → balance → software volume → fader → bs2b → sink. The RG limiter sits *before* the EQ, so it cannot catch EQ boosts. | [gstenginepipeline.cpp](https://github.com/strawberrymusicplayer/strawberry/blob/master/src/engine/gstenginepipeline.cpp) (`InitAudioBin`) | src |
| Audacious | `apply_replay_gain` → effect plugins → `eq_filter` → software volume → optional `audio_soft_clip` → integer conversion. | [output.cc](https://github.com/audacious-media-player/audacious/blob/master/src/libaudcore/output.cc) | src |
| Rockbox | PGA "pre-gain amp" **multiplies ReplayGain and EQ precut** into one gain. The EQ and tone controls are separate stages. | [pga.c](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/pga.c); [dsp_proc_database.h](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/dsp_proc_database.h) | src |
| Roon | Headroom Management is first and fixed ("cannot be removed … cannot appear more than once"), then SRC, then the reorderable PEQ/Procedural EQ/Crossfeed/Convolution, then Speaker Setup. Where volume leveling sits relative to these: **not found**. | [MUSE](https://help.roonlabs.com/portal/en/kb/articles/muse) | doc |
| FFmpeg `af_biquads` | For integer formats, counts clipped samples per channel and logs "Channel %d clipping %d times. Please reduce gain." | [af_biquads.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_biquads.c) | src |
| Equalizer APO | No clamp and no limiter in the engine (a plain `static_cast<float>`). | [FilterEngine.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/FilterEngine.cpp) | src |
| Apple Music · Spotify | Order of Sound Check or normalisation versus the EQ: **not found**. | [Apple](https://support.apple.com/en-nz/guide/music/museb684a3de/mac); [Spotify](https://support.spotify.com/us/article/equalizer/) | doc |

**Takeaways**
- Automatic headroom comes in two forms.
  - From **control values**: eqMac, Rockbox, Equalizer APO Normalize, foobar2000 Auto level.
  - From the **realized response**: AutoEq, and the Equalizer APO analysis.
- Control values under-state the peak when bands overlap (Rane: +6/+6 plays +9).
- Players that normalise put the gain **before** the EQ, and the EQ preamp sits next to the EQ.
- Rockbox and Poweramp DVC **win the loudness back on a downstream volume stage**.

## 4. Parameter changes while the user drags

| Product | What it does | Evidence | Conf. |
|---|---|---|---|
| **Equalizer APO** | A new configuration goes to `nextConfig`, and **both chains process the input**. A per-sample raised cosine `factor = 0.5·(1−cos(π·n/L))` blends them over `L = sampleRate/100` (**10 ms**), then the chains swap. | [FilterEngine.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/FilterEngine.cpp); [FilterConfiguration.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/FilterConfiguration.cpp) (`doTransition`) | src |
| **x42 fil4** (Fons Adriaensen's section) | **Per-block rate limit**: each parameter may move only within ×0.5…×2 of its current value per block. **Per-sample linear ramps** of the section coefficients (`s1 += d1`, `a += da`) over the block. The section is an allpass-based form (`_a = 0.5(g−1)`, `_s2 = (1−b)/(1+b)`). | [filters.h](https://github.com/x42/fil4.lv2/blob/master/src/filters.h) (`Fil4Paramsect::proc`) | src |
| **Apple vDSP** `vDSP_biquadm_SetTargets{Single,Double}` | "Sets up a ramped change … at each sample, each coefficient's value is incremented until the difference between its value and target is less than the specified threshold". `rate` is 0…1 and `threshold` > 0. macOS 13+. | [SetTargets doc](https://developer.apple.com/documentation/accelerate/vdsp_biquadm_settargetsdoubled); [vDSP guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingBiquadraticFilterFunctions/UsingBiquadraticFilterFunctions.html) | doc |
| **TPT / SVF** | JUCE `StateVariableTPTFilter`: "using a TPT structure, designed for fast modulation". Cytomic's trapezoidal SVF: `g = tan(π·fc/fs)`, `k = 1/Q`, peak/notch/all-pass taps. FFmpeg exposes `transform=svf|zdf` for its biquads. | [JUCE](https://docs.juce.com/master/classjuce_1_1dsp_1_1StateVariableTPTFilter.html); [Cytomic](https://cytomic.com/files/dsp/SvfLinearTrapOptimised2.pdf); [af_biquads.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_biquads.c) | doc + paper + src |
| **Vicanek matched biquads** | Closed-form coefficients "so the filter characteristic may be modulated with near sample rate updating". | [BiquadFits.pdf](https://www.vicanek.de/articles/BiquadFits.pdf) §1 | paper |
| **FabFilter Pro-Q** | Global bypass "also applies soft bypassing to avoid clicks" and is latency-compensated. Smoothing of parameter drags: **not found**. | [output](https://www.fabfilter.com/help/pro-q/using/output) | doc |
| **eqMac** | Preset switches call `Transition.perform(from:to:)` to step `globalGain`. Transition's implementation: **not found** (file not located). | [AdvancedEqualizer.swift](https://github.com/bitgapp/eqmac/blob/master/native/app/Source/Audio/Effects/Equalizers/Advanced/AdvancedEqualizer.swift) | src |
| **No smoothing** | GStreamer (lazy `need_new_coefficients`, history kept); VLC and Audacious (new gains on the next block); FFmpeg biquads, anequalizer and firequalizer (kernel replaced in place, old overlap tail still added); Rockbox (new coefficients, history kept; flushed only when a band comes online); DeaDBeeF (`recalc_table`, no crossfade); AOSP DynamicsProcessing (EQ factors stepped; only the MBC and limiter envelopes are smoothed). | [GStreamer](https://github.com/GStreamer/gstreamer/blob/main/subprojects/gst-plugins-good/gst/equalizer/gstiirequalizer.c); [VLC](https://github.com/videolan/vlc/blob/master/modules/audio_filter/equalizer.c); [Audacious](https://github.com/audacious-media-player/audacious/blob/master/src/libaudcore/equalizer.cc); [firequalizer](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_firequalizer.c); [Rockbox eq.c](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/eq.c); [DeaDBeeF](https://github.com/DeaDBeeF-Player/deadbeef/blob/master/plugins/supereq/supereq.c); [DPFrequency.cpp](https://android.googlesource.com/platform/frameworks/av/+/refs/heads/main/media/libeffects/dynamicsproc/dsp/DPFrequency.cpp) | src |
| **Gain-recompute cost of a compensated GEQ** | ACGE: average **6.0 ms** per command-gain update in MATLAB (PGE: 24 ms), covering interpolation, matrix inversion and multiplications. The authors want "frequency-dependent c and g_p" so that "the interaction matrix and its pseudoinverse would not have to be calculated with each command gain change". | [DAFx-17](http://www.dafx17.eca.ed.ac.uk/papers/DAFx17_paper_94.pdf) §5.1, §6 | paper |

**Takeaway.**
- The only shipped crossfade I found is Equalizer APO's 10 ms raised cosine over two complete chains.
- The only shipped per-sample coefficient ramp in this set is x42.
- Apple ships ramping in Accelerate.
- Note on the parallel design (VLC, Audacious-style): there the gain is an *output multiplier*, so a gain change never disturbs filter state.

## 5. What the curve display shows

| Product | Display | Evidence | Conf. |
|---|---|---|---|
| LSP Graphic EQ | **The true response**: per-band `freq_chart` complex responses multiplied together (`complex_mul2`) and the magnitude taken (`complex_mod`). The same data feeds the inline display. | [graph_equalizer.cpp](https://github.com/lsp-plugins/lsp-plugins-graph-equalizer/blob/master/src/main/plug/graph_equalizer.cpp) (`process`) | src |
| FFmpeg `anequalizer` | **The true response**: `draw_curves` evaluates each section's transfer function on the unit circle for every pixel. | [af_anequalizer.c](https://github.com/FFmpeg/FFmpeg/blob/master/libavfilter/af_anequalizer.c) | src |
| Equalizer APO Editor | **The true response of the whole chain**: an impulse is pushed through the real `FilterEngine` (up to 10·fs frames), FFT'd, and its `peakGain` reported. The node editor uses the same nodes the FIR is built from. | [AnalysisThread.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/Editor/AnalysisThread.cpp) | src |
| FabFilter Pro-Q | Thick curve = "the overall frequency response"; the selected bands' shapes are highlighted. The range auto-expands (±3/6/12/30 dB). | [EQ display](https://www.fabfilter.com/help/pro-q/using/eqdisplay) | doc |
| Audacity Graphic EQ | 31 ⅓-octave sliders (20 Hz–20 kHz) are **interpolated** (B-spline `0.75−s²`, raised cosine, or natural cubic `spline`/`splint`) into an envelope of `NUM_PTS` points. That envelope is realized by an overlap-add FIR of length M. A display of the *realized* response: **not found**. | [EqualizationBandSliders.cpp](https://doxy.audacityteam.org/_equalization_band_sliders_8cpp_source.html) (`GraphicEQ`); [EqualizationBase.cpp](https://doxy.audacityteam.org/_equalization_base_8cpp_source.html) | src |
| Audirvana · Logic · Ableton | Audirvana: the EQ curve plus white input and blue output spectra. Logic: "Shows the current curve of each EQ band" plus a pre/post analyzer. Ableton: filter curves plus output spectrum; a combined curve is not described. | [Audirvana](https://help.audirvana.com/support/solutions/articles/202000096012-how-to-use-the-integrated-studio-equalizer-eq-); [Logic/FCP](https://support.apple.com/en-mz/guide/final-cut-pro-logic-effects/lgex92fd757d/mac); [Ableton](https://www.ableton.com/en/manual/live-audio-effect-reference/) | doc |
| Slider players | Apple Music (faders), VLC, Audacious, Strawberry and GStreamer apps expose band values only; none draws a summed curve. | [Apple](https://support.apple.com/en-nz/guide/music/museb684a3de/mac); sources above | doc + src |
| SoundSource (picture-vs-sound drift) | 6.1.1 fixed "a parameter scaling issue which led presets in the 10-band Lagutin Equalizer to only apply half their intended boost or cut". | [release notes](https://rogueamoeba.com/support/releasenotes/?product=SoundSource) | doc |

## 6. Bass/treble or tone controls alongside a graphic EQ

| Product | Mechanism | Evidence | Conf. |
|---|---|---|---|
| Rockbox | **Separate shelves**: `filter_bishelf_coefs` with fixed corners, bass 200 Hz and treble 3,500 Hz ("not adjustable for now"), as their own DSP stage beside the 10-band EQ. They share the automatic prescale (`MAX(bass, treble, eq gains)`). | [tone_controls.c](https://github.com/Rockbox/rockbox/blob/master/lib/rbcodec/dsp/tone_controls.c); [sound.c](https://github.com/Rockbox/rockbox/blob/master/firmware/sound.c) | src |
| eqMac Basic | **Mapped into the bands as plateaus**: Bass sets bands 0–2 (32/64/125 Hz), Mids sets 3–6, Treble sets 7–9, all to the **same gain**, with no weighting. | [BasicEqualizer.swift](https://github.com/bitgapp/eqmac/blob/master/native/app/Source/Audio/Effects/Equalizers/Basic/BasicEqualizer.swift) | src |
| Poweramp | "Parametric & graphic modes … Bass & treble controls" are a separate feature. Algorithm: **not found**. | [powerampapp.com](https://powerampapp.com/?p=966) | doc |
| Wavelet | Separate "Bass tuner" (bass type, cutoff, post-gain) beside the 9-band GEQ. | [Features](https://pittvandewitt.github.io/Wavelet/Features/) | doc |
| AutoEq | **A target curve fitted into fixed bands** by optimising only the gains of fixed-fc/Q filters (10-band Q √2; 31-band Q 4.318). | [peq.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/peq.py); [constants.py](https://github.com/jaakkopasanen/AutoEq/blob/master/autoeq/constants.py) | src |
| ACGE | Target dB values at 61 points (centres plus linearly interpolated midpoints), solved by LS for 31 band gains. | [DAFx-17](http://www.dafx17.eca.ed.ac.uk/papers/DAFx17_paper_94.pdf) §4–5 | paper |
| darktable tone equalizer (cross-domain, image) | 9 user sliders → **least-squares fit of 8 Gaussian radial basis functions**: `gaussian_func(r, 2σ²)`, with σ from the "smoothing" control (`√2^(1+s)`). The file calls it "an approximation rather than an interpolation". | [toneequal.c](https://github.com/darktable-org/darktable/blob/master/src/iop/toneequal.c) (`build_interpolation_matrix`, `pseudo_solve`) | src |
| Sonos · Bose · Apple Music | Bass/treble or presets only. How they are realized: **not found**. | — | — |

## 7. A/B and bypass level matching

| Product | Mechanism | Evidence | Conf. |
|---|---|---|---|
| FabFilter Pro-Q Auto Gain | "An educated guess based on the current EQ settings" that "is **not** a dynamic process based on actually measured levels". Gain Scale scales every curve's gain. | [output](https://www.fabfilter.com/help/pro-q/using/output) | doc |
| iZotope Ozone Gain Match | On bypass, "automatically level-match the unprocessed and processed material". Mode 1 raises the unprocessed signal ("might blow past 0 dBFS"). **Mode 2 lowers the processed signal and is recommended.** How it measures: **not found**. | [iZotope article](https://www.izotope.com/en/learn/how-to-use-ozone-utilities.html) | doc |
| Ableton EQ Eight | "Adaptive Q": Q rises with boost or cut "to keep output volume more consistent". Audition solos one filter. | [Ableton manual](https://www.ableton.com/en/manual/live-audio-effect-reference/) | doc |
| Logic Channel EQ | Gain-Q Couple "preserves the perceived bandwidth" (Strong / Light / Medium / Asymmetric). | [Logic/FCP doc](https://support.apple.com/en-mz/guide/final-cut-pro-logic-effects/lgex92fd757d/mac) | doc |
| Audirvana · Wavelet · SoundID | Each offsets by the **peak** boost: Audirvana Auto; Wavelet Attenuator ("highest gain of all features combined"); SoundID Safe Headroom (**sec**). None of these is a loudness match. | §3a rows | doc / sec |
| Consumer players (Apple Music, Spotify, VLC, Audacious, Strawberry, Roon, foobar2000, Poweramp) | Level-matched compare: **not found**. | sources above | — |

## 8. Per-device or per-output EQ memory

| Product | Device identity and what is stored | Evidence | Conf. |
|---|---|---|---|
| **EasyEffects** | Autoload JSON `{device, device-description, device-profile (=route), preset-name}` stored as **`<device>:<route>.json`**. `load()` is an **exact** filename lookup; an optional **fallback preset** applies when nothing matches. The route lets one sound card keep different presets for headphones and speakers. | [presets_autoload_manager.cpp](https://github.com/wwmm/easyeffects/blob/master/src/presets_autoload_manager.cpp) (`add`, `find`, `load`) | src |
| **Equalizer APO** | `Device: <pattern>` is matched against "the connection name, device name and GUID of the current output device". Every word must appear, `;` separates alternatives, and `all` always matches. Commands after a non-matching Device line are ignored. | [config ref](https://sourceforge.net/p/equalizerapo/wiki/Configuration%20reference/) | doc |
| Roon | "Each zone has its own, independently configurable DSP Engine." | [MUSE](https://help.roonlabs.com/portal/en/kb/articles/muse) | doc |
| Poweramp | "Save presets per device, output, or headphone"; "Per-output presets". The ID scheme: **not found**. | [powerampapp.com](https://powerampapp.com/?p=966) | doc |
| eqMac | Super Presets "Automatically Switch presets … Output Device or Main Audio App changes" (Pro and Free). The public v1.3.2 code keeps EQ state app-wide. | [eqmac.app](https://eqmac.app/); [AdvancedEqualizer.swift](https://github.com/bitgapp/eqmac/blob/master/native/app/Source/Audio/Effects/Equalizers/Advanced/AdvancedEqualizer.swift) | doc + src |
| Apple Music | **Per-song** preset ("applies to the song whenever you play it"), not per device. | [iTunes doc](https://support.apple.com/en-ca/guide/itunes/itns2991/mac) | doc |
| Audirvana · SoundSource · Wavelet | Audirvana: per-device auto-save is claimed by the prior survey's release note, which returned 403 this session. SoundSource manual: per-device persistence **not found**. Wavelet docs: **not found**. | [SoundSource devices](https://rogueamoeba.com/support/manuals/soundsource?page=system-devices) | — |
| **macOS Core Audio keys** (for us) | `kAudioDevicePropertyDeviceUID`: "persistent across boots" but "not suitable … for identifying similar models of hardware". `kAudioDevicePropertyModelUID`: equal iff "the exact same model from the same manufacturer", "the same no matter on what machine". `kAudioDevicePropertyTransportType` gives the connection type. | [AudioHardwareBase.h (SDK mirror)](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.15.sdk/System/Library/Frameworks/CoreAudio.framework/Versions/A/Headers/AudioHardwareBase.h) | doc |

## 9. Point-drag behaviour and keyboard access

| Product | Behaviour | Evidence | Conf. |
|---|---|---|---|
| darktable tone EQ | "**Moving a single control point will also affect control points on either side** to ensure the curve remains smooth"; adjustable through "curve smoothing". "Going past about 0.6 can introduce some instability (**oscillations**)". | [manual](https://docs.darktable.org/usermanual/development/en/module-reference/processing-modules/tone-equalizer/) | doc |
| Equalizer APO Editor | A drag moves **only that node**; neighbours just re-order if it crosses them. **Arrow keys act on all selected nodes**: ↑/↓ ±1 dB, ←/→ ±1 Hz. Ctrl+A selects all; Delete removes a node (variable mode only). | [GraphicEQFilterGUIScene.cpp](https://github.com/TheFireKahuna/equalizerAPO64/blob/main/Editor/guis/GraphicEQFilterGUIScene.cpp) (`itemMoved`, `keyPressEvent`) | src |
| Swinsian | "Hold down the control key and click and drag … across the bands to draw curves"; 10 or 31 bands. | [Swinsian blog](https://swinsian.com/blog/2017/11/21/whats-new-in-swinsian-2) | doc |
| FabFilter Pro-Q | Dragging a selected dot moves the frequency and gain of every selected band, and with several bands their gains scale relative to each other. Ctrl-drag sets Q; the wheel sets Q; Shift fine-tunes; Tab cycles Freq/Gain/Q. No arrow keys are documented. | [EQ display](https://www.fabfilter.com/help/pro-q/using/eqdisplay) | doc |
| Ableton EQ Eight | Rubber-band select, then move selected dots "with the mouse or with your computer keyboard's arrow keys". | [Ableton manual](https://www.ableton.com/en/manual/live-audio-effect-reference/) | doc |
| Audacity Graphic EQ | Sliders stay independent, but the **curve** between sliders follows the B-spline, cosine or cubic interpolation. | [EqualizationBandSliders.cpp](https://doxy.audacityteam.org/_equalization_band_sliders_8cpp_source.html) | src |
| eqMac Basic | One control moves 3–4 bands equally (a plateau). | [BasicEqualizer.swift](https://github.com/bitgapp/eqmac/blob/master/native/app/Source/Audio/Effects/Equalizers/Basic/BasicEqualizer.swift) | src |
| SoundSource | 6.0.3: "Keyboard entry once again works as expected with sliders in the 10-Band EQ". | [release notes](https://rogueamoeba.com/support/releasenotes/?product=SoundSource) | doc |
| Apple Music, Spotify, VLC, Audacious, Strawberry | Independent sliders. Any falloff, follow or smoothing: **not found**. | sources above | — |

---

# Part 2 — Patterns and lessons for us

### What the best implementations agree on
1. **A dense graphic EQ is a design problem, not 31 independent knobs.** Accurate tools do one of three things:
   - **compensate** the interaction: ACGE LS solve, MathWorks Oliver–Jot, Rane Perfect-Q, AutoEq gain optimisation;
   - **remove** it with FIR frequency sampling (Equalizer APO, firequalizer);
   - **steepen** the bands (LSP ladder-pass, Calf and anequalizer 4th order).

   Our "accurate cascade GEQ" is the ACGE family. Of the three it costs the least per sample (279 ops/sample for 31 bands) and adds no latency.
2. **Draw from the realized filters.** LSP multiplies the band responses, anequalizer evaluates H(e^jω), Equalizer APO measures an impulse through the real engine, and Pro-Q draws the "overall frequency response". This confirms our "graph draws what plays".
3. **Headroom comes from the realized response, and a hard safety net stays at the end.** AutoEq uses `max(summed response) + 0.2 dB`; the Equalizer APO analysis reads `peakGain`. Roon, Audirvana and FFmpeg add clip indicators, and Pro-Q works in float and never clips. Our −1 dBTP limiter stays last.
4. **Changes are de-clicked at the DSP level**, by a crossfade (Equalizer APO, 10 ms raised cosine) or per-sample ramps (x42, vDSP targets). Pro tools use modulation-safe topologies (TPT/SVF, matched biquads).
5. **Level matching for A/B is a loudness problem**, solved by Pro-Q's curve-based estimate or Ozone's Gain Match, which recommends lowering the louder side.
6. **Per-device memory keys on a stable device ID plus a route, with a fallback** (EasyEffects; Equalizer APO's name/connection/GUID).

### Where common players are naive
- **Uncompensated filter banks:**
  - Cascades: GStreamer (Strawberry, Clementine), Rockbox, eqMac (AVAudioUnitEQ 0.5-oct bells), Audacious.
  - Parallel band-pass sum: VLC.
  - Rane's +6 & +6 → +9 dB example is exactly the error such banks hide. DAFx-17 notes that parallel banks notch between bands.
- **Headroom:**
  - A manual preamp only: Apple Music, VLC, Audacious, DeaDBeeF, Strawberry, SoundSource.
  - Or automatic, but from the **control values**: eqMac, Rockbox, Equalizer APO Normalize, foobar2000 Auto level. That misses peaks where bands overlap.
- **Zipper risk:** none of the players smooths parameter changes (§4). Several keep filter state through a coefficient jump or add the old FIR's overlap tail.
- **Near Nyquist:** clamp, drop or zero the band; none compensates cramping (§2).
- **Tone mapping:** eqMac's plateau mapping makes stair-steps (equal gains on 3 adjacent bands), which an uncompensated cascade then over-sums.

### What challenges or sharpens our plan
1. **Peak headroom is not Compare's level match. They need two different gains.**
   - With peak-based headroom, the EQ'd path is usually *quieter* than bypass. Example: a +6 dB bass shelf gets a −6 dB preamp while adding much less than 6 dB of broadband loudness. A/B is then biased toward bypass.
   - Recommend: compute Compare's offset from **loudness**, either a K-weighted estimate from the played curve (Pro-Q's "educated guess" model) or measured BS.1770 short-term on both paths. Lower the louder side, as in Ozone's recommended mode.
2. **Peak headroom makes "EQ on" sound quieter.**
   - Rockbox (`volume += prescale`) and Poweramp DVC (**sec**) recover it on a downstream volume stage.
   - If our output volume has spare gain (volume below 100%), consider the same compensation. If not, say so in the UI.
3. **The ACGE design is tied to 44.1 kHz, with hand-tuned top bands.**
   - We must design and verify per sample rate (44.1/48/88.2/96/176.4/192), as MathWorks recomputes on rate change.
   - We must decide what the 20 kHz band means at 44.1 kHz (about 0.91·Nyquist). Two options: Equalizer APO's "hold flat to Nyquist", or a prescribed-Nyquist-gain band filter.
   - Our S7 sweep oracle should test the 1 dB criterion at every rate, including the "hard" ±12 dB patterns from DAFx-17 §3.2.
4. **The LS solve runs per edit.** It took about 6 ms in MATLAB and needs a pseudoinverse whenever the iteration step is used.
   - Run it off the audio thread, at UI rate, and publish coefficient targets.
   - **Ramp the auto-preamp in lockstep with the curve.** Otherwise a boost can arrive before its cut and spike.
5. **Pick the de-zipper method deliberately.**
   - Option A: a 10 ms raised-cosine crossfade of the whole cascade (Equalizer APO). Simple and robust; costs 2× CPU only during fades.
   - Option B: per-sample coefficient ramps (vDSP targets or our own). Interpolated direct-form denominators stay stable, because the stability region `|a1|<2, |a1|−1<a2<1` (Vicanek eq. 3) is convex; that is my inference. But direct-form state can still produce transients.
   - Option C: TPT/SVF sections, "designed for fast modulation" (JUCE/Cytomic).
6. **Tone macros should feed the same solver.**
   - Model Bass/Body/Mids/Presence/Air as analytic shelves and bells, sample them at the 61 design points, and run the ACGE solve. This follows AutoEq, ACGE and darktable, not eqMac's plateaus.
   - Expect more than 1 dB error only on steep transitions, which DAFx-17 §5 accepts.
7. **"Neighbours follow" has no music-player precedent.**
   - darktable shows that a strong smoothing radius **oscillates**. Swinsian, Pro-Q, Ableton and Equalizer APO solve the same need with draw gestures, multi-select and arrow keys.
   - With Tone macros present, a wide falloff duplicates them. Keep the falloff narrow, or tie it to a modifier, and draw the realized curve so any overshoot is visible.
8. **An FIR alternative deserves one benchmark.**
   - Equalizer APO's minimum-phase FIR (16k taps) is exact and free of interaction, at the cost of convolution CPU and longer low-frequency ringing.
   - Recommend keeping the ACGE plan, and running a single S7 sweep comparison so we have evidence for the choice.
9. **S12 AutoEq import must replicate RBJ biquads exactly.**
   - AutoEq optimises its PEQ against RBJ/BLT biquads. LSP even ships an "APO" filter mode, described as textbook bilinear biquads implemented as Equalizer APO does, for that reason. A decramped engine would play AutoEq presets differently from how they were fitted.
   - For the GraphicEQ (127-point) format, fit to our 31 bands. AutoEq's own 31-band config is Q 4.318 at 20·2^(i/3) Hz.
10. **Per-device memory design.**
    - Key on `DeviceUID`, with `ModelUID` as the fallback (same model on another Mac), and optionally the transport type.
    - Store a *reference* to a preset plus the EQ on/off state.
    - Add a user-chosen fallback preset (EasyEffects pattern).
11. **Chain order.** Every player that normalises does it *before* the EQ (Strawberry, Audacious, Rockbox). Recommended order:
    1. normalisation gain (ReplayGain or R128);
    2. EQ auto-preamp, then EQ;
    3. volume;
    4. true-peak limiter last.

    Strawberry's ReplayGain limiter sits before its EQ, so it cannot catch EQ boosts. We should not repeat that.

### Not found (looked, undocumented)
- The internal algorithms of Apple Music, Spotify, AUGraphicEQ, Audirvana, Roon PEQ, SoundSource Lagutin, Neutron and Waves GEQ.
- How Ozone measures its Gain Match.
- Per-device persistence in SoundSource and Wavelet.
- Where Roon's volume leveling sits relative to its DSP.
- Parameter smoothing in Pro-Q or AVAudioUnitEQ.
