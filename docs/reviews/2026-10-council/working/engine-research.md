# Engine research: what should run the Enhanced (default) playback path?

**Question (founder):** "Do a research on anything we can use that is mainstream and reputed" for the default
Enhanced engine, instead of building our own. The founder decides afterwards.

**Date:** 2026-10-14. **Repo state read:** `main` @ 7d7c2cd (read-only; nothing in `Sources/` or `Tests/` touched).
**Evidence location:** everything is under `scratchpad/engine-research/`:
- `ref-sfb/` SFBAudioEngine @ 9ed712d4 (0.14.0 + 4 commits); `ref-cog/` Cog @ fb2ed48d; `ref-mpv/` mpv @ 270367e8;
  `ref-miniaudio/` @ 9634bedb (0.11.25); `ref-audiokit/` @ c358c15f (5.7.2 + fixes); `ref-vlc/` (sparse) @ ce4af2f7;
  `ref-gstreamer/` (sparse) @ 90abc341; `ref-juce/` (licence + resampler header via `gh api`). Each repo is in its own
  directory, read as data. No build script of any cloned repo was run.
- `probes/`: my own offline probes (AVAudioEngine manual rendering, no device opened, nothing played):
  `mixer_src.swift`, `mixer_src_linear.swift`, `srcnode_src.swift`, `conv_transparency.swift` and their `.out` files.
- `players/notes.md`: a helper's evidence log for "what leading macOS players use" (local `otool`/`nm` on installed
  bundles, repo files, developer pages). `proprietary/`: a helper's log for BASS / FMOD / Superpowered (headers and
  vendor docs only; no binary run).
- SDK headers: macOS 26.5 SDK (`MacOSX26.5.sdk`).

---

## 0. Bottom line

1. **Shortlist:**
   - **A. SFBAudioEngine's `SFBAudioPlayer`** (MIT): an AVAudioEngine graph pulled by an `AVAudioSourceNode` from a ring.
     It has decode-ahead gapless, async seek and a broad decoder set, and `modifyProcessingGraph:` puts our two AUs
     in the live graph.
   - **B. Our own pull engine** on `AVAudioSourceNode`, reusing Pure's proven C++ `FileDecodeSource` + `GaplessSource`
     (the council's BR-2 / DSP-01). This is the fallback if A fails.
   - **C. BASS** (un4seen; proprietary). It is the only *mainstream* engine that meets the DSP-latency requirement.
2. **Recommendation:** run the 1-week SFB spike (§5), with one new hard requirement: **insert an `AUConverter`
   node at Mastering complexity** after SFB's source node. Adopt SFB if the spike passes. Otherwise build B, reusing
   the same converter node. Do not adopt C unless the founder wants a proprietary engine (§6).
3. **New measured finding (this report, §1).** Every *implicit* sample-rate conversion inside AVAudioEngine fails our
   SRC bar badly:
   - −6.9 dB at 20 kHz;
   - aliasing as high as −10 dB at 192→48 kHz.

   This is exactly the path SFB uses by default, because it runs the graph at the file's rate and lets the mixer
   convert. An explicit `AUConverter` node at Mastering complexity is flat to 21 kHz, keeps aliasing at or below
   −160 dB, and is **bit-transparent when the rates are equal**. That makes SFB (and B) viable.
4. **Q4 answer (§6):** no *open-source* option is both mainstream and able to run our DSP with low control latency.
   - The mainstream open-source engines fail requirement 2: mpv has no DSP hook and a 200 ms buffer, VLC 3.x has no
     gapless, GStreamer's sink buffer defaults to 200 ms.
   - So does Apple's mainstream path: `AVSampleBufferAudioRenderer` reads about 2 s ahead, and `AVQueuePlayer` gives
     a per-item tap with no SRC control.
   - **BASS** is mainstream among reputable Mac players (VOX, Colibri, Plexamp) and meets requirement 2 on its
     documentation. But it is proprietary, its output is not Apple-native, and it needs a GPL linking exception.
   - **SFB** meets requirement 2 and removes the decode/scheduling engine from our maintenance. It is *reputable*
     (MIT, since 2006, very active) but *not mainstream* (no verified big-name adopter).

---

## 1. New measurements: AVAudioEngine's own sample-rate conversion (offline probes)

**Why this matters.** SFB converts each decoder only to "deinterleaved native-endian float, preserving the channel
count" at the **file's** rate (`AudioPlayer.mm:393-394`), and connects the source node to the main mixer at that
rate (`AudioPlayer.mm:2819-2836`). When the device rate differs, **AVAudioEngine converts implicitly**. Stage-5
§4.5 asked for this SRC to be measured against C-26's gate (≤ 0.1 dB to 20 kHz, ≤ −100 dB stopband).

**Method** (`probes/mixer_src.swift`):
- AVAudioEngine in offline manual rendering at the destination rate.
- An `AVAudioSourceNode` generates double-precision sines at the source rate.
- Level is read with a least-squares sinusoid fit, so there is no FFT scalloping.
- Cross-check: the AUConverter at Normal complexity reproduces the panels' independent `AVAudioConverter` Normal
  numbers exactly (−0.48 / −8.25 / −38.2 dB at 19/20/21 kHz, 44.1→48), so the harness is calibrated.

**Passband** (gain in dB re input):

| Conversion | Path | 18 kHz | 19 kHz | 20 kHz | 21 kHz |
|---|---|---|---|---|---|
| 44.1→48 | **implicit (mixer input, or source-node block format)** | −0.70 | −2.64 | **−6.86** | −14.40 |
| 44.1→48 | AUConverter, Normal | 0.00 | −0.48 | −8.25 | −38.24 |
| 44.1→48 | **AUConverter, Mastering** | 0.00 | 0.00 | **0.00** | 0.00 |
| 96→48 | implicit | −1.09 | −1.92 | −3.12 | −4.78 |
| 96→48 | AUConverter, Mastering | 0.00 | 0.00 | 0.00 | 0.00 |
| 192→48 | implicit | −2.85 | −3.57 | −4.41 | −5.37 |
| 192→48 | AUConverter, Mastering | 0.00 | 0.00 | 0.00 | 0.00 |
| 48→44.1 | implicit | −0.88 | −2.84 | −6.79 | −13.52 |
| 48→44.1 | AUConverter, Mastering | 0.00 | 0.00 | 0.00 | 0.00 |

**Stopband** (an out-of-band tone read at its alias, dB re tone):

| Conversion | Path | 24.5 kHz | 25 kHz | 26 kHz | 30 kHz |
|---|---|---|---|---|---|
| 96→48 | implicit | **−15.3** | −17.6 | −23.0 | −64.7 |
| 192→48 | implicit | **−9.9** | −10.7 | −12.5 | −21.8 |
| 88.2→48 | implicit | −17.4 | −20.4 | −27.5 | −90.1 |
| 96 / 192 / 88.2→48 | **AUConverter, Mastering** | ≤ −163 | ≤ −166 | ≤ −162 | ≤ −164 |

**Other results:**
- `probes/srcnode_src.out`: an `AVAudioSourceNode` whose block format differs from its connection format gives
  **byte-identical numbers** to the mixer. It is the same implicit converter, despite the header's "supports
  different audio formats for the block and output" (`AVAudioSourceNode.h:86-87`).
- `mixer_src_linear.out`: the implicit converter is neither AUConverter Linear nor Normal. It is its own low-order
  filter.
- `conv_transparency.out`: an AUConverter (Mastering) at **equal** in/out rates is **bit-exact** (max |out − in| =
  0, lag 0) at 44.1, 48 and 96 kHz. It can therefore stay in the graph permanently: when the file rate equals the
  device rate, there is no SRC at all.
- `mixer_src.out`: the main mixer at equal rates and unity gain is also bit-exact.
- Cost of Mastering, from the P3 panels: about 0.3–0.6 s of CPU per minute per channel, about 13 ms of filter
  delay. Fine for one stream.

**Caveats:**
- These numbers are from offline manual rendering. Real-time mode uses the same mixer node, but the spike must
  confirm it in the live graph (§5, P1).
- AUHAL's own output-side conversion, which today's 48 kHz graph hits on a 44.1 kHz Bluetooth device, cannot be
  probed without a device and is **unmeasured**.

**Implications:**
- (a) An SFB adoption **must** insert a Mastering AUConverter via `modifyProcessingGraph:`.
- (b) Any home-built AVAudioEngine design must avoid implicit conversion too.
- (c) R1.1-A's C-26 could be satisfied by this one node instead of tuning the Swift resampler chain.

---

## 2. Comparison table

**Legend:**
- Y = meets the requirement. P = partial or conditional. N = does not meet it. ? = unverified.
- Requirement numbers follow the brief:
  - 1 sample-accurate gapless, with an honest gap on a format change;
  - 2 our C++ DSP in path with tens-of-ms control latency;
  - 3 up to 7.1;
  - 4 accurate seek;
  - 5 robust device changes;
  - 6 no engine calls on the main thread;
  - 7 SRC ≤ 0.1 dB / ≤ −100 dB, or none;
  - 8 formats;
  - 9 CUE / regions.
- "Pure" = can it feed decoded PCM to our HAL bit-perfect path.

### 2a. Requirements matrix

| Candidate | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | Pure |
|---|---|---|---|---|---|---|---|---|---|---|
| **SFBAudioEngine `SFBAudioPlayer`** | Y¹ | Y² | Y | Y³ | P⁴ | Y⁵ | N→Y⁶ | Y++ | P⁷ | Y⁸ |
| **Own pull engine** (`AVAudioSourceNode` + Pure C++) | Y | Y | Y | Y | Y | Y | Y⁶ | P | build | native |
| Own AUHAL engine (extend `HALOutputEngine`, the Cog-2026 model) | Y | Y | Y | Y | Y (build) | Y | Y (build) | P | build | native |
| Today's `AVAudioPlayerNode` + R1.1 fixes (baseline) | P | Y | P | P | Y | Y | Y (fix) | P | N | separate |
| `AVSampleBufferAudioRenderer` + synchronizer | P | **N**⁹ | Y | P | P | Y | ?(system) | P | app | N |
| `AVQueuePlayer` + `MTAudioProcessingTap` | P¹⁰ | P/? | Y | P | Y | Y | N (no control) | P | P | N |
| **BASS** + BASSmix + add-ons (proprietary) | Y | Y¹¹ | Y | Y | Y | Y | ?¹² | Y++ | P | Y |
| FMOD Core (proprietary) | Y | Y | Y | Y | P | P | **N** | **N** (macOS: no AAC/ALAC/Opus) | P | Y |
| libmpv (IINA) | P¹³ | **N**¹⁴ | Y | Y | Y | Y | ? | Y++ | ? | N |
| libVLC / VLCKit 3.x | **N**¹⁵ | **N** | Y | Y | Y | Y | ? | Y++ | P | via callbacks |
| GStreamer (`playbin3`) | P | P¹⁶ | Y | Y | P | Y | ? | Y (plugins) | P | P |
| JUCE | build | Y | Y | build | Y | Y | N (Lagrange) | P | build | P |
| miniaudio | P¹⁷ | Y | Y | Y | Y | Y | **N** (linear) | **N** (WAV/MP3/FLAC) | P | P |
| AudioKit `AudioPlayer` | **N**¹⁸ | Y | Y | P | P | P | as today | Apple | N | N |
| PortAudio / RtAudio | output only: no decode, no gapless, no seek | | | | | | | | | |
| Cog's 2026 engine (as a dependency) | Y | P¹⁹ | Y | Y | Y | Y | Y (soxr) | Y++ | Y | N/A (app-internal) |

**Notes to 2a** (evidence opened by me unless marked "helper"):
1. Same rate, channels **and layout** are gapless: `formatWillBeGaplessIfEnqueued`, `AudioPlayer.mm:688-696`; the
   public contract is in `SFBAudioPlayer.h:39-40`. Any other change is a "Non-gapless join": the decoder waits until
   all earlier decoders finish, then the graph is stopped, reconnected and restarted (`AudioPlayer.mm:1427-1486`,
   `2769-2856`). That is the honest short gap we want. Its length is unmeasured (spike P4).
2. Our AUs sit **after** the 16,384-frame ring (`AudioPlayer.mm:35`), inside the engine's render pull, inserted with
   `modifyProcessingGraph:` (`SFBAudioPlayer.h:297-302`; segment "between `sourceNode` and `engine.mainMixerNode`").
   A parameter change is heard on the next render cycle, the same as today. Compare Cog, whose DSP runs **before** a
   0.2 s ring, "the delay before a DSP setting change is heard" (`Cog/Audio/Engine/Pump/Pump.swift:132-138`).
3. Seek is asynchronous: an atomic `pendingSeek_` executed on the decoding thread, with stale ring audio discarded
   in `render()` (`AudioPlayer.mm:954-972, 1612-1625`). The target is **clamped to `[0, length−1]`**, so seek-to-end
   plays one frame and ends instead of hanging (our D37 / C-25). Accuracy is the decoder's: mpg123 with
   `MPG123_GAPLESS` (`SFBMPEGDecoder.m:260`), opusfile, libFLAC, `ExtAudioFile` (`SFBCoreAudioDecoder.mm:283-294`).
   An inexact seek is logged (`AudioPlayer.mm:509-511`).
4. It handles `AVAudioEngineConfigurationChange` by reconnecting mixer→output at the new hardware format and
   restarting (`AudioPlayer.mm:2559-2650`). It does **not** re-run the delegate's graph segment on a hardware-rate
   change. With our inserted converter, its output would stay at the old rate and the mixer would convert
   implicitly (§1). This needs our own handling or an upstream patch (spike P7). `setOutputDeviceID:` is
   `AUAudioUnit.setDeviceID` (`AudioPlayer.mm:1016-1028`).
5. Engine start/stop run **on the caller's thread** under `engineMutex_` (`play` `AudioPlayer.mm:700-731`), on the
   decoding thread (format change) and on AVAudioEngine's notification queue. Pause is only a render flag, with no
   engine call (`:733-750`). State getters are lock-free: atomic flags and a seqlock snapshot. **Rule for us:** call
   SFB only from our non-main engine queue, and never read `engineIsRunning` / `outputDeviceID` on main (they touch
   `engine_`).
6. By default it fails (implicit SRC, §1). It passes with an inserted `AUConverter` at Mastering complexity, which is
   also bit-transparent at equal rates.
7. `SFBAudioRegionDecoder` plays a frame range with repeat (`SFBAudioRegionDecoder.h:21-72`). There is **no `.cue`
   parser** in SFB (no "cue" anywhere in `Sources/CSFBAudioEngine`).
8. Decoders are usable standalone (`SFBPCMDecoding.h:31,41`). FLAC, ALAC and WavPack integer sources decode to their
   **native integer** format (`SFBFLACDecoder.mm:360`, `SFBCoreAudioDecoder.mm:357-386`), so they could back Pure's
   `DecodeBackend` bit-exactly.
9. The renderer "read[s] ahead aggressively": mpv sizes its device buffer at **2 s** for it
   (`mpv/audio/out/ao_avfoundation.m:301-302`). DSP must run before `enqueueSampleBuffer`, so the control latency is
   about the read-ahead. Cog moved to it in 2022 (commit dccb7f8b) and **reverted in 2023**: "Fixes several issues
   with playback and seeking latency" (commit 7ab2a830). A route change auto-flushes the queue
   (`AVSampleBufferAudioRenderer.h:133-140`).
10. "It plays these items as gaplessly as possible … depending on the timely availability of media data"
    (`AVPlayer.h:840-842`): a best effort, not a contract. The tap is attached **per `AVPlayerItem`** through
    `AVAudioMix`, so DSP state does not span the seam. The tap format is chosen by AVFoundation (Apple forum thread
    30383, 2016, no Apple answer). Apple Music.app does use `AVQueuePlayer` behind the private `MediaPlaybackCore`
    (helper: local `otool -L` / `dyld_info` on Music.app 1.6.6).
11. Helper, vendor docs:
    - `BASS_ChannelSetDSP` runs our C++ kernel directly.
    - With `BASS_ATTRIB_BUFFER` = 0, "no data will be buffered … This allows the lowest latency to be achieved"
      (https://www.un4seen.com/doc/bass/BASS_ATTRIB_BUFFER.html, re-fetched by me).
    - The device buffer is about 20 ms on macOS (twice the 10 ms update period). That is computed, not measured.
12. Windowed sinc up to 64 points (BASS) or 256 points (BASSmix). No published response, so it needs our SRC gate.
    Running at the file rate (`BASS_DEVICE_FREQ`) avoids SRC.
13. `--gapless-audio=weak` (default) reopens the device when the format changes. Gapless "relies on audio output
    device buffering" (`mpv/DOCS/man/options.rst:2373-2406`).
14. libmpv has no audio-callback API ("there is no such thing as audio output embedding", `include/mpv/client.h`
    at `MPV_EVENT_AUDIO_RECONFIG`). DSP is limited to lavfi filters before the AO buffer: "Default: 0.2 (200 ms)
    … Making this larger may make soft-volume and other filters react slower" (`options.rst:2452-2465`).
15. Gapless next-media exists only in unreleased 4.0-dev: `libvlc_media_player_set_next_media`
    (`include/vlc/libvlc_media_player.h:728-741`). The latest release is 3.0.24 (2026-09-22). There is no 4.0 tag.
16. `playbin3` "about-to-finish … set the uri … to make sure that playback continues"
    (`gstplaybin3.c:841-847`). A custom element sits upstream of the sink buffer, whose
    `DEFAULT_BUFFER_TIME` is 200 ms (`gstaudiobasesink.c:88, 186-190`). It is tunable.
17. `ma_data_source_set_next` chains sources, but "setting up chaining is not thread safe" (`miniaudio.h:930`).
    The only built-in resampler is linear (`miniaudio.h:5403`). Built-in decoding covers WAV, MP3 and FLAC only
    (`:2500-2510`).
18. It wraps `AVAudioPlayerNode` (`AudioPlayer.swift:5-15`) with `.dataPlayedBack` completions by default
    (`AudioPlayer+Playback.swift:16`), and completions hop to the main queue (`AudioPlayer.swift:245-255`). It has the
    same structural defects as today's path (P3 D39/D40).
19. DSP runs on a DSP thread before a 0.2 s shallow ring (note 2). Cog is GPL-2.0 and app-internal, not a package.

### 2b. Licence, health, adoption, effort, risk

| Candidate | Licence (implications) | Maintenance health | Adoption (reputable macOS players) | Effort | Risk |
|---|---|---|---|---|---|
| **SFBAudioEngine** | **MIT.** Dependencies: BSD-3 (FLAC, Ogg, Vorbis, Opus, Speex, WavPack, Monkey's Audio, Musepack); **LGPL-2.1** (mpg123, libsndfile), **LGPL-3.0** (tta-cpp) and LGPL-2 (lame), with "dynamic linking is required" (`README.md:153`); TagLib MPL-1.1 / LGPL-2.1. Fine for GPL-3.0, App Store and commercial use, provided the LGPL frameworks stay dynamic and are bundled and signed. | 0.14.0 on 2026-09-14, 0.13.0 on 2026-06-08, 0.12.x Feb 2026. **357 commits in 12 months, 354 by the single maintainer** (S. Booth). Issues answered in days (#982: 17→28 Aug; #994: 30 Aug→19 Sep). **0.x API**: breaking changes in 0.11 and 0.12 (release notes). 2026 regressions in the player core (#982 position stall, #994 jthread self-join). macOS 11+; C++20 / Objective-C++ core | **Low.** No verified big-name shipping player: Decibel unconfirmed, Sonora dead, about 19 hobby repos (helper). 710 stars. Reputable author and long history (copyright 2006–2026) | **M** | **Med:** one maintainer, a young player core, the SRC trap (§1) |
| **Own pull engine** | ours | ours | the same pattern as SFB and Cog | **L** | **High:** we own seams, seek and events in two languages (PM-2) |
| Own AUHAL engine | ours | ours | Cog 2026, DeaDBeeF, Audirvana, Roon drive the HAL directly (helper) | **L+** | **High:** loses AVAudioEngine hosting and taps |
| Today + R1.1 fixes | ours | ours | — | **S–M** | Low now; RC-2 persists |
| `AVSampleBufferAudioRenderer` | Apple | Apple (macOS 10.13+) | opt-in only in mpv and IINA; Cog reverted it (2023) | M | **High** (latency) |
| `AVQueuePlayer` + tap | Apple | Apple | Apple Music.app (helper, verified locally) | M | High (gapless best-effort, per-item tap) |
| **BASS** | **Proprietary.** Free only for non-commercial use. Shareware €125, Single Commercial €950, Unlimited €3,450, **per platform** (https://www.un4seen.com/bass.html, re-fetched by me). A GPL-3.0 app needs a **linking exception** from every copyright holder. Closed source | 2.4.18.3 on 2025-12-15; BASSmix 2.4.13 on 2026-09-09 (helper). A small closed vendor | **High:** VOX, Colibri, Plexamp's TREBLE (BASS decoder plug-ins), HiFidelity (helper, vendor and developer pages) | **L** | **Med–High:** closed core, licence, not Apple-native output |
| FMOD | Proprietary; free tier is games-only; non-game use is "contact us" | 2.04.00 on 2026-09-29 (DSP plug-in API break) | none found | L | High (fails requirements 7 and 8) |
| libmpv | GPLv2+, or LGPLv2.1+ with `-Dgpl=false` (`mpv/Copyright`) | v0.41.0 on 2025-12-21; about 1,280 commits a year | IINA, Musique (helper) | L | High (fails requirement 2) |
| libVLC / VLCKit | LGPL-2.1+ (libVLC) | 3.0.24 on 2026-09-22; 4.0 unreleased | VLC itself | L | High |
| GStreamer | LGPL-2.1+ | 1.28.8 on 2026-10-08 | Strawberry, Clementine, Quod Libet (Linux-first ports, helper) | L | High (large runtime to bundle) |
| JUCE | **AGPLv3** or commercial (JUCE 9 EULA) (`LICENSE.md:6-8`) | 9.0.4 on 2026-10-12 | none found among Mac players | L | High (a framework, not an engine) |
| miniaudio | Public domain or MIT-0 | 0.11.25 on 2026-03-04; one maintainer | none found | L | High (a toolkit; we'd build the engine) |
| AudioKit | MIT | 5.7.2 on 2026-03-31 | none found | M | High (same defects) |
| PortAudio / RtAudio | MIT-style | last release 2021 (PortAudio) / 2023 (RtAudio) | — | — | not a player |
| Cog engine | **GPL-2.0** (`COPYING`) | very active (about 451 commits a year) | Cog | n/a | reference design only |

**Dropped, with the deciding reason:**
- **FMOD:** on macOS it decodes no AAC, ALAC or Opus. Its resampler is interpolation-only (linear, cubic, spline).
  The licence is games-first (helper; FMOD 2.04 docs).
- **Superpowered:** stereo DJ toolkit, linear or 6-point resampler, remote licence kill-switch (helper; SDK headers).
- **irrKlang, Wwise:** unobtainable or game middleware (helper).
- **libmpv, VLCKit 3.x, GStreamer:** requirement 2 (and requirement 1 for VLC 3.x).
- **`AVSampleBufferAudioRenderer`:** requirement 2. Cog's own history is the precedent.
- **`AVQueuePlayer` + tap:** best-effort gapless, a per-item tap, no SRC control, no frame accounting.
- **JUCE, miniaudio, PortAudio, RtAudio:** they would make us build the engine anyway, and add a framework. JUCE also
  brings AGPL.
- **AudioKit:** it *is* the `AVAudioPlayerNode` design we are leaving.
- **AudioStreaming** (dimitris-c, MIT): output fixed at 44.1 kHz stereo (`AudioPlayer.swift:149`). Streaming-first.
- **StreamingKit, SwiftAudioPlayer, OrigamiEngine:** unmaintained since 2022 or earlier (`gh api`).
- **Cog's engine:** GPL-2.0, app-internal, DSP behind 0.2 s. Kept as a reference.

---

## 3. What leading macOS players actually use (adoption evidence)

From the helper's report (`players/notes.md`). Confidence labels are the helper's. I re-checked the Cog rows in git.

| Player | Engine | Evidence | Confidence |
|---|---|---|---|
| Apple Music.app | `AVQueuePlayer` via private `MediaPlaybackCore` | local `otool -L`, `nm -u`, `dyld_info` | VERIFIED |
| Cog | own engine, AUHAL via the C API, IOProc in hog mode, AUSpatialMixer | `Audio/Engine/PLAN.md`, `Output/DeviceOutput.swift`, commits dccb7f8b, 7ab2a830, 9c05d60d (I re-read these) | VERIFIED |
| IINA, Musique | libmpv (CoreAudio AO by default; AVFoundation AO opt-in) | IINA `MPVController.swift`, `Preference.swift`; Musique `musique.pro:41` | VERIFIED |
| VOX, Colibri, HiFidelity | **BASS** | vendor and App Store pages, repo description | VERIFIED |
| Plexamp | TREBLE "on top of a low-level commercial audio engine"; staff name BASS decoder plug-ins | Plex forum post by the developer (2026-09-18); AppImage contents | VERIFIED / PARTIAL |
| foobar2000 Mac | closed engine, internal FFmpeg 8.0, libFLAC, Vorbis, Opus | official changelog | VERIFIED (libraries) |
| Roon | .NET app, RAAT; CoreAudio/ASIO output | Roon help pages | VERIFIED |
| Audirvana | own engine; SoX / r8brain SRC; CoreAudio exclusive + integer | help pages; user debug dump | PARTIAL |
| Swinsian | FFmpeg, libFLAC (third-party binary scan); hog mode | site, changelog, third-party scan | PARTIAL |
| Doppler | **not determined** | — | UNVERIFIED |
| Decibel (sbooth) | SFB? | no developer statement | UNVERIFIED |
| Strawberry, Clementine, Quod Libet | GStreamer `osxaudiosink` | source files | VERIFIED |
| DeaDBeeF | own engine, HAL IOProc | `plugins/coreaudio/coreaudio.c:301` | VERIFIED |

**Takeaways:**
- Serious players either own a HAL engine or buy BASS.
- Apple's own player uses AVQueuePlayer, which has no device control.
- **No reputable shipping player is verified on AVAudioEngine.** That is a real adoption gap for SFB, and for our
  current design.
- One more piece of Cog evidence that applies to *any* AVAudioEngine design (SFB, B, and today), from commit 9c05d60d
  (2026-09-30): `AUAudioUnit` "runs Objective-C on the device's I/O thread … the first load of a bundle … holds the
  Objective-C runtime's lock long enough for the device to miss its deadline: … 55–68 ms device-side gaps". Our
  effects and spatial units are `AUAudioUnit` subclasses hosted by AVAudioEngine. **Unverified for our graph**; it is
  added as spike check P11.

---

## 4. Shortlist and how each fits our architecture

### A. SFBAudioEngine `SFBAudioPlayer` (recommended to spike)

**Graph** (set once in `modifyProcessingGraph:`):

```
SFB sourceNode (file rate, reads SFB's ring)
  → AUConverter [Mastering, RenderQuality max]   file rate → device hardware rate; bit-exact when equal
  → our effectsAU (EQ / dynamics / loudness)     always at the device rate: one rate domain, no per-track
                                                 coefficient redesign
  → our spatialAU (N → M)
  → mainMixer (equal rate: transparent)
  → outputNode
```

**Format and device changes:**
- On a file-format change, implement `audioPlayer:reconfigureProcessingGraph:withFormat:`
  (`SFBAudioPlayer.h:437-440`). Reconnect source→converter at the new file format and return the converter. The
  converter's output, our AUs and the mixer keep the device rate.
- On a hardware rate or width change, `audioPlayer:audioEngineConfigurationChange:` (`:447`) fires *after* SFB has
  restarted the engine. We must reconnect converter-out → AUs → mixer at the new hardware format. The header says
  "the audio engine must not be started or stopped directly" (`:299-300`), so either:
  - land a small upstream PR (SFB merged an external PR, #979, on this exact handler), or
  - carry a one-function patch.

  Spike P7 decides which.

**Threading:**
- Our existing serial `engineQueue` (non-main) is the only caller of `play`, `pause`, `seek`, `enqueue`,
  `clearQueue` and `setOutputDeviceID`.
- SFB's delegate events arrive on unspecified queues (`SFBAudioPlayer.h:63`). They feed our transport state, then
  hop to main for the UI.
- The UI reads only SFB's lock-free getters: `playbackState`, `isPlaying`, `playbackPosition` and `currentTime`
  (flags plus a seqlock snapshot).
- The real-time path is SFB's render block (no locks, no allocation), then our AUs, which are unchanged.

**Gapless and queue:**
- Arm = `enqueueURL:` / `enqueueDecoder:`. Re-arm = `clearQueue` + enqueue, which fixes D41's class by construction.
  Play-now = `enqueue…forImmediatePlayback:YES`.
- `formatWillBeGaplessIfEnqueued:` gives the UI an honest "gap here" label.
- Events: `renderingWillStart` / `renderingWillComplete` at a host time, and `nowPlayingChanged`. They are host-time
  stamped in the render domain (`AudioPlayer.mm:224-233`). Add `outputNode.presentationLatency`
  (`AVAudioIONode.h:106-114`) for the heard time; that is about 215 ms on Bluetooth here (P3 SOTA).

**Per-track loudness:** wrap each decoder in our own `SFBPCMDecoding` adapter that applies the static per-track or
album gain inside the stream. It is sample-accurate at the seam by construction, which removes D40's early switch
and the event-timed switch altogether.

**Seek:** `seekToFrame:` is asynchronous, clamped, and mutes during the seek (0.14.0 notes, #946). The ~13 ms
history in the converter could leak a sliver of pre-seek audio; spike P5 checks for that.

**Device:** keep `OutputDeviceMonitor` (our listeners). Pick a device with `setOutputDeviceID:` on `engineQueue`.
AVAudioEngine follows the system default when no device is set.

**Pure:** keep `HALOutputEngine`, `GaplessSource` and `RenderGate`. Optionally add an `SfbDecodeBackend` (`.mm`) in
`FileDecodeSource`, giving one decoder set for both paths, and **delete FFmpeg** (C-99) without losing FLAC, Opus,
Vorbis, WavPack, APE or DSD.

**Deleted:**
- `AudioEngineBridge+EnhancedResampler.swift` (316 LOC), `+EnhancedResamplerSeam` (164), `+GaplessRoll` (278).
- Most of `+Gapless` (229) and `+TransportClock` (126).
- The Enhanced halves of `+Playback`, `+PureMode`, `+ConfigChange` and `+Reconfigure`.
- The two epochs, `onDeckURL`, `base` and `lastKnown`.
- About 1,100–1,500 LOC in total, which matches BR-2's estimate.

**Added:**
- 1 package plus about 20 transitive packages.
- About 10 **dynamic** xcframeworks to embed, sign and notarize from a SwiftPM-built bundle (`make dist` work).

### B. Own pull engine (BR-2 / DSP-01): the fallback

- **Graph:** the same as A, but the source node's render block calls `GaplessSource::pullFloat` (C++, already
  real-time clean, seam proven: D41).
- **Decoding:** a decode thread runs `FileDecodeSource` (Apple `ExtAudioFile`; optionally SFB decoders as a
  backend).
- **Seek:** consumer-honoured flush (the SFB and Cog pattern) instead of the `RenderGate` hold.
- **One format predicate:** rate, width and layout, shared with Pure.
- **Converter:** the same AUConverter node, so there is no decode-thread SRC to build.
- **Deleted:** the same Swift code as A.
- **Added:** about 500–900 LOC of C++ and Swift glue, events and tests (my estimate). We maintain it forever, in two
  languages; that is PM-2's risk.

### C. BASS (only if the founder wants a proprietary mainstream engine)

**Option C1: BASS as decoder, queue and seek layer under our Apple-native output.** This is the helper's advice and
mine.
- A BASSmix queued mixer (`BASS_MIXER_QUEUE` + `BASS_MIXER_CHAN_NORAMPIN`, float) runs in decode mode
  (`BASS_STREAM_DECODE`).
- It is pulled on our decode thread into our ring, which feeds the same `AVAudioSourceNode` → AUConverter → our AUs
  graph.
- Our DSP stays in the AVAudioEngine graph, so the "Apple-native output" rule holds.

**Option C2: full BASS output.** `BASS_ChannelSetDSP` calls our `DSPKernel` directly, with `BASS_ATTRIB_BUFFER` = 0.
This loses AU hosting, mixer taps and AUSpatialMixer, so it breaks the founder's Apple-native rule.

**Cost:**
- A GPL linking exception, and €950–3,450 per platform if the app is ever sold.
- The resampler is unmeasured.
- C1 still leaves us owning the ring and render glue.

---

## 5. Recommendation and spike plan (refines stage5-architect §4.5)

**Recommendation:**
1. Keep R1.1-A's in-place fixes (they are small and needed whatever happens).
2. Run a **1-week SFB spike** outside the main checkout, pinned to SFB 0.14.0.
3. Adopt SFB for Enhanced at S11 time if it passes, behind a flag, under the finish-or-revert rule.
4. If it fails on P1, P3, P5 or P7 and the failure cannot be fixed through public API or an accepted upstream PR
   inside the week, build B with the same converter node.

The AUConverter finding (§1) is useful on every branch; it could even close C-26 now.

**Harness:**
- Offline first: inside `modifyProcessingGraph:` (engine stopped), call `enableManualRenderingMode(.offline…)`, then
  `play`, and pull `renderOffline` paced from the harness thread. This reuses P3's replicas
  (`seam_split_profile.swift`, `src_dump.swift`).
- If SFB's internals reject manual rendering, fall back to a real-time run that the founder does by ear. Agents never
  play audio.

**Pass/fail criteria (all automated, except where marked "founder"):**

| # | Check | Pass | Fail |
|---|---|---|---|
| P1 | SRC in SFB's live graph, with the AUConverter (Mastering) inserted | ≤ 0.1 dB to 20 kHz; ≤ −100 dB aliases for 44.1 / 88.2 / 96 / 176.4 / 192 → 48 and 48 → 44.1. Equal rates bit-exact (reproduces §1 inside SFB) | The converter cannot be kept in the segment, or numbers differ from §1 |
| P2 | Our AUs in SFB's graph | Bit-exact against today's kernel for a 48 kHz file on a 48 kHz graph. A parameter change is visible in the next rendered buffer (control latency = 1 render cycle) | Any extra buffering ahead of our AUs |
| P3 | Gapless, same format (44.1, 48, 96; 16↔24-bit mixed) | Join error ≤ 1e-6 against one continuous file, 0 frames inserted. With conversion (44.1 file on a 48 graph): ≤ 1e-4 against one continuous conversion (P3 oracle) | Any inserted frame, or a click above the oracle |
| P4 | Format-change join (44.1→96, 2.0→5.1→2.0) | Honest gap, measured and reported (target ≤ 150 ms); every channel present; correct layout | Dropped channels, or a hang |
| P5 | Seek | `seek(to: duration)` ends and advances 100/100. Exact landing frame for WAV, FLAC, ALAC, AAC, MP3 (LAME), Opus against decode-from-open. Call-to-first-new-sample ≤ 100 ms p95. No pre-seek audio after the converter (or our fade masks it) | Hang, inexact lossless seek, or a stale tail above −60 dB |
| P6 | Threads | No SFB or engine call on main: instrumented wrapper plus Main Thread Checker. TSan clean. UI responsive during a forced engine stop | Any main-thread engine call needed |
| P7 | Device / hardware-rate change (built-in 48 ↔ Bluetooth 44.1; founder plugs and unplugs) | Our segment re-connects at the new rate (graph log shows no implicit SRC). Playback resumes ≤ 1 s. Follows the system default | Needs an unsupported engine stop/start, and upstream won't take a fix |
| P8 | Formats and corpus | Everything `AVAudioFile` opens also opens in SFB. FLAC 32-bit, multichannel FLAC, ID3-prefixed FLAC, Opus, WavPack, APE, DSF all decode. Lossless decode sample-exact against `ExtAudioFile` | Regressions on the founder's library |
| P9 | Pure (optional) | The SFB FLAC/WavPack decoder as a `DecodeBackend` is bit-exact and seek-exact against today's `FileDecodeSource` | — (keep `ExtAudioFile`) |
| P10 | Supply chain | SFB and its dependencies build inside `make dist`. Dynamic frameworks embedded and signed (`codesign --verify --deep`). Licences listed in NOTICE. App size delta recorded | It cannot be bundled and signed from SwiftPM |
| P11 | Real-time robustness | 8-hour soak with random seek / skip / queue edits: no crash, no stuck state. Loading a bundle during playback causes no underrun (Cog's 9c05d60d case) | Repeatable underruns |

**Outcome:** pass P1–P8 and P10 → adopt. P9 decides whether there is one decode layer. P11 failures that also hit
today's graph are not SFB-specific; log them.

---

## 6. Explicit answer: mainstream and reputable, *and* our DSP with low control latency, *and* no engine to maintain?

**Not in open source.**
- Every mainstream open-source engine fails requirement 2:
  - mpv: no DSP hook, 200 ms buffer (`options.rst:2452-2465`; `client.h`);
  - VLC 3.x: no gapless, and DSP only as a module or by taking over output;
  - GStreamer: 200 ms default sink buffer; Linux-first.
- Apple's mainstream paths fail too:
  - `AVSampleBufferAudioRenderer`: about 2 s read-ahead (`ao_avfoundation.m:301-302`; Cog's revert 7ab2a830);
  - `AVQueuePlayer`: per-item tap, best-effort gapless, no SRC control.

**Only BASS ticks all three:**
- it is mainstream among reputable Mac players (VOX, Colibri, Plexamp);
- it meets requirement 2 per its own docs (`BASS_ATTRIB_BUFFER` = 0);
- it removes decode and scheduling from our maintenance.

It is proprietary and closed, needs a GPL linking exception, costs €950+ per platform if ever sold, and is not
Apple-native output.

**SFBAudioEngine meets requirement 2** (DSP after its ring, the same latency as today) and removes the
decode/scheduling engine from our maintenance. It is reputable (MIT, since 2006, very active) but **not mainstream**:
there is no verified big-name adopter, and one person maintains it. It is the best fit to the founder's own
per-layer rule ("Apple-native for playback/output; established libraries for decoders; custom C++ for EQ/limiter").

---

## 7. The one question for the founder

**For the default engine, what counts as "established"?**
- **(A, recommended)** "Reputable open source, Apple-native": **SFBAudioEngine**. MIT, one long-time maintainer,
  little big-name adoption. It is gated by the 1-week spike in §5, with our own pull engine (B) as the fallback.
- **(B)** "Mainstream, meaning used by well-known players": that is only **BASS**. It is proprietary and closed, needs
  a GPL linking exception, costs €950–3,450 per platform if the app is ever sold, and is not Apple-native output.

---

### Appendix: key sources (opened)
- **SFB:**
  - `SFBAudioPlayer.h:37-40, 63, 287, 297-311, 437-447`;
  - `AudioPlayer.h:122-180`;
  - `AudioPlayer.mm:35-38, 224-233, 393-394, 688-696, 700-750, 954-972, 1016-1028, 1427-1486, 1488-1560, 1612-1660,
    2296-2330, 2559-2650, 2769-2856`;
  - `README.md:113, 147-153`; `Package.swift:26-58`;
  - releases via `gh api repos/sbooth/SFBAudioEngine/releases`; issues via `gh api …/issues?state=all`.
- **Apple SDK 26.5:**
  - `AVSampleBufferAudioRenderer.h:120-150`; `AVPlayer.h:836-846`; `MTAudioProcessingTap.h:185-215`;
  - `AVAudioSourceNode.h:44-89`; `AVAudioIONode.h:106-114`;
  - `AudioUnitProperties.h:2410-2416` (`kAudioUnitSampleRateConverterComplexity_Mastering`);
  - `CMSampleBuffer.h:1252-1274` (trim attachments).
- **mpv:** `DOCS/man/options.rst:2373-2406, 2452-2465`; `include/mpv/client.h` (`MPV_EVENT_AUDIO_RECONFIG`);
  `audio/out/ao_avfoundation.m:301-302`; `Copyright`.
- **Cog:**
  - `Audio/Engine/PLAN.md:44-80, 120-300`; `Audio/Engine/Pump/Pump.swift:126-138`; `COPYING`;
  - commits dccb7f8b (2022-06-23), 7ab2a830 (2023-10-02), 9c05d60d (2026-09-30).
- **miniaudio:** `miniaudio.h:896-930, 2500-2510, 2958-2966, 3731, 5403`; `LICENSE`.
- **AudioKit:** `Sources/AudioKit/Nodes/Playback/AudioPlayer/AudioPlayer.swift:5-15, 245-255`;
  `AudioPlayer+Playback.swift:16`.
- **VLC:** `include/vlc/libvlc_media_player.h:728-741`; `include/vlc_player.h:202-205, 395-405`; tags (3.0.24 latest;
  4.0-dev only).
- **GStreamer:** `subprojects/gst-plugins-base/gst-libs/gst/audio/gstaudiobasesink.c:88-89, 186-197`;
  `gst/playback/gstplaybin3.c:841-847`; tag 1.28.8.
- **JUCE:** `LICENSE.md:1-20`; `modules/juce_audio_basics/sources/juce_ResamplingAudioSource.h:39-44`; release 9.0.4.
- **BASS:** https://www.un4seen.com/doc/bass/BASS_ATTRIB_BUFFER.html and https://www.un4seen.com/bass.html (both
  re-fetched by me). Other BASS and FMOD citations are in the helper's log `engine-research/proprietary/`.
- **Probes:** `engine-research/probes/*.swift` and `*.out` (§1).
