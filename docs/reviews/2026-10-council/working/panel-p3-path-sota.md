# Panel P3: state of the art and correctness by reference (signal path, gapless, Pure)

**Role:** state-of-the-art / correctness-by-reference panelist. Independent of the P3 breaker; I did not read that file.
**Code:** `main` @ 7d7c2cd, read-only. Experiments were built in my worktree `.claude/worktrees/panel-p3-sota` and in
`scratchpad/council/exp-p3-sota/`. Machine: Apple M4 Pro, macOS 26 SDK, Swift 6.3.2. I never launched the app and never
played audio to a device. Device facts come from read-only HAL property queries.

**References opened** (cloned or fetched; line numbers are at the fetched revision):
- SFBAudioEngine @ 9ed712d4: `Sources/CSFBAudioEngine/Player/AudioPlayer.mm`
- Cog @ fb2ed48d: `Audio/Engine/PLAN.md`, `Core/CogRender.c`, `Output/DeviceOutput.swift`
- rigtorp/SPSCQueue @ 59a6a938: `include/rigtorp/SPSCQueue.h`
- HadrienG2/triple-buffer `src/lib.rs` (master)
- JUCE develop: `juce_AudioProcessor.cpp`, `juce_AudioProcessorPlayer.cpp`
- FFmpeg master: `fftools/ffplay.c`
- SDK headers: `AVAudioPlayerNode.h`, `AVAudioConverter.h`, `AVAudioMixing.h`, `AudioHardware.h`, `AudioHardwareBase.h`,
  `AudioHardwareService.h`
- Dr. Lex, "Programming Volume Controls"; J. O. Smith, *Digital Audio Resampling* (ccrma.stanford.edu/~jos/resample);
  src.infinitewave.ca (measurement method); RFC 7845 §4.6

## Summary table (29 rows)

| Row | Verdict | Evidence (short) | Missing proof |
|---|---|---|---|
| **D37** Enhanced streaming resampler | **DEFECT** (SIGNIFICANT) | `.max` with the Normal algorithm measures −0.48 dB at 19 kHz, −2.6 dB at 19.5 kHz and **−8.3 dB at 20 kHz** for 44.1→48 kHz. 192→48 kHz content at 24.5 kHz aliases at **−21 dB**. The stated reason to avoid Mastering ("offline, would stall") is false: Mastering streams in the production pattern at 100–190× real time per channel, is flat to 20 kHz and reaches ≤ −150 dB. A new converter per seam (see D39). | An automated passband + stopband gate on the production converter configuration |
| **D38** SRC quality measurement | **DEFECT** (SIGNIFICANT, of proof) | The tool prints `tone=-7.23 dBFS` at 20 kHz (and −0.37 at 1 kHz), yet passes, because `pass` checks only imaging and aliasing (`main.swift:286`). It measures 48→44.1 (not a production path) and skips every tone at or above the destination Nyquist (`:311`), so no down-conversion stopband is tested. It does not cover 88.2/96/176.4/192→48. It is not in `make gate`. | Passband flatness gate, a stopband sweep for the real ratios, in the gate |
| **D39** Enhanced gapless roll | **DEFECT** (STRUCTURAL root) | (a) Known (rev-sota M5): the 48 kHz seam gap. Measured lower bound is the block remainder (155 frames), and the device adds L (27 ms on built-in speakers, 215 ms on BT here). (b) **New:** the resampler seam races. When A's last chunk is short, B is scheduled after A has drained: **279 frames (5.8 ms) of silence** in a replica of the real code. (c) **New:** per-track converters zero-pad both sides of the join. Join error peaks at **0.050** (sine) and 0.033 (noise) over ±32 frames, versus 7.7e-4 for Cog's old per-track LPC approach and 5.7e-7 for a persistent converter. (d) B lands up to 1 frame early or late plus a sub-sample shift. | An engine-level seam test with an offline replica and a ramp/continuity oracle |
| **D40** Enhanced seam re-base | **DEFECT** (known: rev-sota M2) | Correction to M2: when the hook fires, the A audio still queued is A's last partial chunk plus a 52-frame flush (0–186 ms), not "2 buffers (~372 ms)". It can also be negative (late, after a gap). | Same as D39 |
| **D41** Pure `GaplessSource` seam | **PROVEN-CORRECT** | Ramp-continuity oracle across the seam, exactly-once exchange, off-RT reap. Same design as SFB/Cog (decode-ahead, render-side swap). | Lossy-codec seams (priming) on the Pure path |
| **D42** same-format predicate | **QUESTIONABLE** (LOCAL) | Requires equal source bit depth and float flag, but the device format is fixed at configure (highest depth), so 16↔24-bit album joins force a gap. SFB checks rate + channels + **layout** (`AudioPlayer.mm:1435`). Cog: "tracks of other depths … stay gapless" (PLAN.md 8). The channel *layout* is not compared. | – |
| **D43** Pure position and seek re-base | **CORRECT-UNPROVEN** | Arithmetic is right: `llround(s·rate)` base plus rendered frames. It is the render position, not the heard one (known). `pureModeEngineSeek` is untested because the HAL engine is not injectable. | Hold → seek → re-base → release through a fake output |
| **D61** triple buffer | **PROVEN-CORRECT** | Same algorithm as HadrienG2 `triple-buffer` (index + dirty bit 0b100 in one atomic, `AcqRel` swaps, `lib.rs:342,544`). Whole-payload tear stress under TSan. | (A model checker would be stronger; not required) |
| **D62** `SpscRing` | **CORRECT-UNPROVEN** | Matches rigtorp (`SPSCQueue.h:109-118,169-190`: relaxed own index, acquire on a cache miss, release on publish). No direct two-thread lossless/ordering test. `tryPushBlock` splits frames when full, and that causes the decoder's carry workaround. | A two-thread sequence-number stress test under TSan (Cog has `CogRingTests`) |
| **D63** `RenderGate` | **PROVEN-CORRECT** (safety) | Wait-free on the RT side. It improves on JUCE, whose audio thread takes `callbackLock` (`juce_AudioProcessorPlayer.cpp:235,258`; `suspendProcessing` `juce_AudioProcessor.cpp:583-587`). Mutual exclusion is stress-tested under TSan. The liveness weakness (close starves on back-to-back passes) is known and being fixed on `fix/render-gate-liveness` (1ee11dd). | – (liveness fix in flight) |
| **D64** `RtSwappableResource` | **QUESTIONABLE** (LOCAL) | No production users (EQModule no longer has setups), yet `backlog.md:246` lists it as part of the shipped spine. It has a reachable orphan leak in `adopt()` (`:107-112`). | – (delete, or replace with a retire queue / farbot `RealtimeObject`) |
| **D65** `MultichannelView` | **PROVEN-CORRECT** (narrow) | Planar decode and clamp, tested. Does not check `mNumberChannels==1` or `mDataByteSize`. | – |
| **D66** `PerChannel<T>` | **QUESTIONABLE** (LOCAL) | Dead code (comments only). | – |
| **D71** Pure decision policy | **DEFECT** (SIGNIFICANT) | The policy has **no channel dimension**. A **mono file on the built-in speakers (RateMatchedFloat) plays permanent silence**: 0 frames, position frozen at 0, never ends. Driven through the real `GaplessSource`/`FileDecodeSource`. The same happens for stereo on a 4-ch device. The tested table also says `requiresHog=true` for RateMatchedFloat, which production overrides (`PureModeBridge.cpp:183`). | Channel-mismatch cases; tests of what actually runs |
| **D72** device capability | **DEFECT** (LOCAL) | Continuous `AudioValueRange`s are reduced to their two endpoints (`CoreAudioDevice.cpp:427-431`). The header says these are "valid **ranges**". `integerCapable` reads only the *current* physical format of the *first* stream. The picker uses the available list: two derivations of one fact. | – (needs HAL; a fake property source would make it testable) |
| **D73** policy C-ABI marshal | **PROVEN-CORRECT** | Cross-checked against the C++ policy. The Swift caller passes `processingFormat` bits (always 32, float), so the file bits it sends are meaningless. Unused by the policy today. | – |
| **D74** Float → native PCM | **DEFECT** (SIGNIFICANT, latent) | Real code driven: a **packed 24-bit** format writes 4-byte words and overruns a 512-frame stereo buffer by **1024 bytes**, with the wrong layout. It **truncates** (rms error 0.664 LSB vs 0.289 when rounding; ±0.75 LSB → 0). NaN is UB (UBSan: `PureModeFormat.cpp:72,88`). No TPDF when requantizing off-grid samples to 16 bit. Cog: round to nearest, clip first, packed-24, TPDF only off-grid (`CogRender.c:567-575,657-663`). | Packed-24, rounding and NaN tests |
| **D75** HAL integer format selection | **QUESTIONABLE** (SIGNIFICANT) | Ignores `kAudioStreamAnyRate` ranged descriptions (`AudioHardwareBase.h:992-997`). Does not restore the physical format or mixability on teardown (only the rate). Does not handle non-mixable streams that AUHAL will not drive (Cog: −10851, so it uses an IOProc). Sets the nominal rate, then the format: two reconfigurations, which Cog saw fail on an SMSL DAC. Hogs the default output in place, where Cog/Pine Player first move the system default away. The integer path is still unverified on hardware (sprint-09 doc). | A USB-DAC smoke; a fake HAL |
| **D76** HAL render callback | **DEFECT** (SIGNIFICANT) | Pulls `rfChannels_` (device width, `:821,845`), so any file whose width differs from the device renders silence (D71). The write bound uses `ceil(bits/8)` (`:866`), not `mBytesPerFrame`, so it is lax for 24-in-32 and does not stop the packed-24 overrun. `frames > 4096` renders silence where Cog loops. | A render test through a fake ABL |
| **D77** nominal-rate change | **QUESTIONABLE** (LOCAL) | Polling is accepted practice (Cog polls too, `DeviceOutput.swift:1068-1083`). But Pure installs no nominal-rate or stream-format listener (Cog does, `:1196-1201`), so in shared RateMatchedFloat another app can change the rate silently. Teardown restores the rate unconditionally. | – |
| **D78** file decode source | **PROVEN-CORRECT** (core) | Bit-exact against WAV fixtures on both back ends. The ring is sized in samples (170 ms at 192 kHz/8 ch; Cog sizes in seconds). The partial-frame carry is a workaround for frame-splitting pushes. | A partial-frame carry test; a 192 kHz/8 ch underrun soak |
| **D79** sample-accurate seek | **DEFECT** (LOCAL) | The FFmpeg back end ignores `AVStream.start_time` (ffplay adds it: `ffplay.c:3771-3774,4520-4521`). Real code driven: MP3 forced through FFmpeg lands **1282 frames early** and is not bit-exact (max\|e\| 0.095). WAV, FLAC, Opus via FFmpeg and everything via Apple land on +0. The tests use WAV only. | Seek tests on lossy/start-time formats per back end |
| **D80** Pure test tone | **CORRECT-UNPROVEN** | Textbook double-precision accumulator with wrap. Used only by tests. The test checks bounds, not frequency. | – |
| **D81** Enhanced reference tone | **DEFECT** (LOCAL, latent crash) | Builds a **mono** buffer and schedules it on the **stereo** player. Reproduced: `NSException 'required condition is false: _outputFormat.channelCount == buffer.format.channelCount'`. Unreachable today (the view model always passes a URL). The float angle has no wrap (−60 dB phase noise by 5 s). | – (delete it) |
| **D82** Master Gain law | **PROVEN-CORRECT** | Matches Dr. Lex: exponential (dB-linear) over 60 dB, forced silence at the bottom, steps of 1–3 dB. Tests compute from the formula. | – |
| **D83** Enhanced master gain applied | **CORRECT-UNPROVEN** | Probe: `player.volume` *does* apply through two effect nodes to the mixer bus (0.5 → 0.05), and the mixer ramps the change linearly over ~22 ms (no zipper). | Engine-level test |
| **D84** Pure device volume | **QUESTIONABLE** (LOCAL) | Main element only. Devices with only per-channel volume (common on USB DACs) read as `.fixed`. Apple's `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` handles exactly this (`AudioHardwareService.h:49-57`), and Cog does "main control, else each channel's". | – |
| **N100** render gate | = D63 | | |
| **N101** Master Gain law | = D82 | | |

**Counts:** PROVEN-CORRECT 9 (D41, D61, D63, D65, D73, D78, D82, N100, N101) · CORRECT-UNPROVEN 4 (D43, D62, D80, D83) ·
**DEFECT 10** (D37, D38, D39, D40 [known], D71, D72, D74, D76, D79, D81) · QUESTIONABLE 6 (D42, D64, D66, D75, D77, D84).

---

## DEFECT and QUESTIONABLE details

### D37: the Enhanced resampler uses the weakest Apple SRC algorithm on a false premise. SIGNIFICANT

- **Evidence.**
  - `+EnhancedResampler.swift:80-82`: `sampleRateConverterQuality = .max`; "Deliberately leave the algorithm at the default (Normal), the `.mastering` algorithm is offline/high-latency and would stall live playback."
  - Same at `+Gapless.swift:223`.
  - Measured with `exp-p3-sota/out/src_dump`, an exact replica of the production pull pattern (8192-frame chunks, `.noDataNow` between chunks). It is bit-identical to a one-shot conversion (`stream_vs_oneshot`: max\|diff\| = 0). Analysis: Kaiser β = 24, N = 2^17, `scripts/src_quality.py` and `src_passband.py`.

  | 44.1→48 kHz passband | 18 k | 19 k | 19.5 k | 20 k | 21 k |
  |---|---|---|---|---|---|
  | AVAC `.max` Normal (prod) | −0.00 | **−0.48** | **−2.62** | **−8.25** | −38 |
  | AVAC `.max` Mastering | 0.00 | 0.00 | 0.00 | 0.00 | 0.00 |
  | soxr VHQ | 0.00 | 0.00 | 0.00 | −0.01 | −4.1 |

  | Worst alias of an out-of-band tone (dB re tone) | 24.5 k | 25 k | 26 k |
  |---|---|---|---|
  | 96→48, Normal (prod) | −56 | −81 | −126 |
  | 192→48, Normal (prod) | **−21** | **−25** | **−35** |
  | 88.2/96/192→48, Mastering | −153…−166 | −155…−161 | −159…−164 |
  | soxr VHQ | −153…−167 | −163…−170 | −160…−169 |

  - Spurs in band: Normal −102…−154 dBc. Mastering and soxr −155…−167 dBc.
  - **CPU per 60 s per channel** (production pattern, M4 Pro):

    | Conversion | Normal | Mastering | soxr VHQ | libsamplerate BEST |
    |---|---|---|---|---|
    | 44.1→48 | 0.023 s | 0.315 s | 0.026 s | 0.68 s |
    | 96→48 | 0.030 s | 0.612 s | 0.019 s | 1.38 s |

    The converter runs on `resampleQueue` with about 0.5 s of lead, so Mastering costs about 1% of one core for stereo. Nothing stalls.
- **Root cause.**
  - The algorithm was chosen on an assumed latency/CPU cost and never measured. The D38 oracle could not catch the result (it does not gate passband).
  - Also: the graph is fixed at 48 kHz (`+Lifecycle.swift:46`; `AudioFormatKit.deviceWidthFormat` keeps the source rate). A device at 44.1 kHz (the BT headphones here run at 44100) therefore gets a **second, hidden** SRC inside the output node: 44.1 file → 48 (Normal) → 44.1 (AUHAL default).
- **SOTA.** Bandlimited interpolation (JOS, *Digital Audio Resampling*) should keep the passband flat to about 20 kHz with ≥ 100 dB stopband. Infinite Wave's method (passband, sweep aliasing, impulse) is how players are compared. soxr VHQ is the project's stated "established library" preference.
- **Remedy.**
  1. Now (S, one line in two places): `converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering`. Fix the comment.
  2. With BR-2: one persistent SRC on the decode worker (AVAudioConverter Mastering, or libsoxr VHQ: same quality, ~15× cheaper), and run the graph at the device's nominal rate so there is exactly one conversion.
- **Effort / risk.** S / low. Mastering's longer filter (±238-frame join transient vs ±32) makes D39(c) longer, so ship it together with the persistent converter.

### D38: the SRC oracle passes a −7 dB passband error and does not test the production ratios. SIGNIFICANT (proof)

- **Evidence.** I ran the repo's own tool in my worktree (`swift build -c release --product SRCQualityMeasure`):
  - `f=19000 Hz tone=-3.00 dBFS … [PASS]` and `f=20000 Hz tone=-7.23 dBFS … [PASS]`, against `-0.37 dBFS` at 1 kHz.
  - `pass` ignores `toneDb` (`main.swift:286`).
  - The directions are 44.1→48 and **48→44.1** (`:353-355`). The second is not an Enhanced path.
  - `guard frequency < destRate/2 - 100` (`:311`) skips every tone above the destination Nyquist, so the down-conversion stopband (where aliasing happens) is never excited.
  - It is manual, not in `make gate`.
- **Root cause.** The pass criterion was written for imaging/aliasing only. The ratios were chosen symmetrically instead of from the production set (file rate → 48 k).
- **Remedy (S).**
  - Gate passband: |gain| ≤ 0.1 dB up to 20 kHz.
  - Gate stopband with tones up to the source Nyquist: ≤ −100 dB.
  - Cover 44.1/88.2/96/176.4/192 → 48 (and → the device rate if the graph moves).
  - Run it in `make gate`; it is headless and AVAudioConverter needs no device.
  - `scripts/src_quality.py` is a ready oracle, with soxr VHQ as the cross-reference.

### D39: Enhanced gapless is not gapless on either sub-path. STRUCTURAL root

- **Evidence.**
  - **(a) Passthrough** (known: rev-sota M5; `area-bridge` BR-2).
    - `seam_probe_cb`: in manual rendering, `.dataPlayedBack` never fires; `.dataRendered` fires at the block after the last frame (72192 for a 72037-frame file).
    - `seam_passthrough` (`.dataRendered`, paced): B starts 155 frames late in 3/3 trials. On device, `.dataPlayedBack` adds L, which is 1310 frames (27.3 ms) on the MacBook speakers and 9473 frames (215 ms) on WH-1000XM4 (`hal_latency`, Cog's formula).
    - **New insight for the fix:** for `scheduleFile`, `.dataConsumed` fires **~54,000 frames (1.1 s) before the end** (player read-ahead: fired at rendered frame 17920 of 72037). Scheduling B from A's `.dataConsumed` gave **0 frames of gap in 3/3 trials**.
  - **(b) Resampler race (new).** `seam_resampler` is a faithful replica of `readConvertSchedule` / prime 3 / `.dataConsumed` / EOF hook → new file + new converter + prime 3:

    | A ends this far into its last chunk | Silence inserted at the seam |
    |---|---|
    | 64 frames | **279 frames** |
    | 4096 frames | −1 frame |
    | 8100 frames | 0 frames |

    The hook fires only after A's last read returned 0 and its flush was scheduled. The lead is therefore A's last partial chunk plus a 52-frame tail. Any roll that takes longer (file open on a slow volume, converter creation, the first read and convert) underruns. With lead uniform on 0–186 ms, P(gap) ≈ roll time / 186 ms.
  - **(c) Join transient (new).** `seam_split_profile`: one continuous conversion versus two per-track conversions at a phase-aligned split (49098 = 147·334):

    | Signal, algorithm | Peak join error | Span | Error energy (±2000 frames) |
    |---|---|---|---|
    | 60 Hz + 3 kHz sine, peak 0.65, Normal | **0.050** | ±32 frames | −47 dB |
    | Noise, Normal | 0.033 | ±32 frames | – |
    | Sine, Mastering | 0.030 | ±238 frames | – |

    - Cause: AVAudioConverter's default `PrimeMethod_Normal`. "Leading frames are assumed to be silence", and at the end "zero (silent) trailing frames will be synthesized" (`AVAudioConverter.h:21,78-80`). Each track is resampled as if bordered by zeros.
    - Cog measured the same flaw in its old per-track converter at 7.7e-4 (44.1→48, with LPC extrapolation), and 5.7e-7 after making soxr persistent (`PLAN.md` stage 1 and stage 3, principle 2). AdaptiveSound has no extrapolation. Its error is roughly 40× Cog's old one; the test signals are comparable but not identical.
  - **(d)** At an unaligned split (49073), B is 1 frame short (`a+b = whole − 1`) and shifted by a fraction of a sample. Per-track output lengths are floored independently. Cog uses exact GCD-reduced positions (147:160).
- **Root cause.**
  - The Enhanced transport infers "schedule the next track" from `AVAudioPlayerNode` completions: `.dataPlayedBack` (after L) and the last buffer's `.dataConsumed` (after a 0-frame read).
  - It treats each track as an independent SRC stream.
  - Neither reference player does either. SFB pre-decodes the next decoder into the same ring and accounts per chunk on the render side (`AudioPlayer.mm:1435-1486, 1612-1745`). Cog: "Nothing is torn down at a track boundary … The resampler persists" (`PLAN.md:56-70`).
- **Remedy.**
  1. Interim (S each, inside AVAudioPlayerNode):
     - Arm B when `setNextTrack` arrives, or from A's file `.dataConsumed`, never from `.dataPlayedBack` or the EOF of the last buffer. Keep `.dataPlayedBack` only for the seam notification and the loudness switch.
     - Keep **one** `AVAudioConverter` across same-rate seams: the input block moves on to B's frames instead of reporting `.endOfStream`. Compute the seam's output frame exactly with integer arithmetic (44.1→48 kHz is 147:160).
  2. Structural: BR-2 (below).
- **Effort / risk.** Interim S–M, low–medium. Structural L, medium.
- **Missing proof.** The offline replica in `scripts/seam_resampler.swift` already shows how to test seams without a device. Port it as a contract test with a continuity oracle (|join error| ≤ 1e-4 against one continuous conversion, and zero inserted frames).

### D40: seam re-base timing. DEFECT (known: rev-sota M2; magnitude corrected)

- At the hook, the remaining A audio is measured as the last partial chunk plus the flush. The hook fired at rendered frame 71680 in all three runs, with A ending at 71401, 75790 and 80148.
- So `bumpTransitionCount` (and `trackBecameAudible`) runs between −6 ms (late, after a gap) and +186 ms early, plus L. It is not "≈ 0.4 s + L" as M2 says.
- Same remedy as M2 and D39: seam keyed by output frame position, minus the cached presentation latency.

### D42: same-format predicate is stricter than the device needs. QUESTIONABLE, LOCAL

- **Evidence.**
  - `GaplessSource.cpp:67-76` requires equal `sourceBitsPerChannel` and `sourceIsFloat`.
  - The HAL format is chosen once (highest depth: `HALOutputEngine.mm:515-557`), and every source is float in the ring. So a 16→24-bit join (or an int → float WAV join) at the same rate refuses to arm and takes the reconfigure gap.
  - SFB checks rate, channel count and **layout**. Cog checks "the same plan" and states that tracks of other depths stay gapless.
- **Remedy (S).** Compare rate, channel count and layout. Drop bits and float.

### D64 / D66: dead primitives. QUESTIONABLE, LOCAL

- `RtSwappableResource` has no users. Its `adopt()` orphan-leak window is reachable:
  1. publish → reclaim runs before the RT adopt of the previous resource;
  2. the next adopt displaces an un-reclaimed `toRelease_`.
- `backlog.md:246` still advertises it as part of the shipped spine.
- `PerChannel` is unused.
- Delete both, or replace the swap with a retire queue (Timur Doumler's RCU-style reclaim, farbot `RealtimeObject`) when BRIR kernels need it.

### D71 + D76: Pure renders permanent silence when the file's channel count differs from the device's. SIGNIFICANT

- **Evidence.**
  - The policy (`PureModePolicy.cpp:85-140`) never compares channels. Neither does the Swift pre-check (`+PureMode.swift:24-79`).
  - `HALOutputEngine` sets the AU input format = the AU output format (device width, `:693-713`, `:733-752`) and pulls `rfChannels_` frames (`:821,845`).
  - `FileDecodeSource::pullFloat` returns silence and 0 frames on any mismatch (`FileDecodeSource.cpp:1012-1016`), so `GaplessSource` holds forever (`exhausted()` stays false).
  - Driven through the real code (`scripts/chan_probe.cpp`):

    | File → device | Frames over 200 render calls | Position |
    |---|---|---|
    | mono → 2 ch | **0** | 0.000 s |
    | stereo → 2 ch | 102400 | 2.133 s |
    | stereo → 4 ch | **0** | 0.000 s |

  - The MacBook Pro Speakers are float, 2 ch, 44.1/48/88.2/96 kHz (read-only `hal_query`). That is the RateMatchedFloat target, so **any mono file in Pure mode on a Mac's own speakers is silent and never ends.**
  - Separately, `PureMode_BuiltInRateMatchedFloat` asserts `requiresHog=true`, which production flips to `false` (`PureModeBridge.cpp:183`). The tested policy is not the one that runs.
- **Root cause.**
  - The Pure path has no channel reconciliation, and the policy is not the single source of truth: the hog rule lives in the bridge, and the channel rule lives nowhere.
  - SOTA: bit-perfect players map rather than mix. AUHAL's `kAudioOutputUnitProperty_ChannelMap` routes without sample math. Cog's feeder does a "channel fit" (`PLAN.md` stage 3).
- **Remedy (S).**
  - Set the AU input format to the file's width and install a channel map: mono `[0,0]`; stereo on 4 ch `[0,1,-1,-1]`.
  - Or, at minimum, make the policy fall back to Enhanced when the widths differ.
  - Move the hog-for-float rule into `evaluatePureMode`, so the table test pins what runs.
- **Effort / risk.** S / low. Add `PureMode_ChannelMismatch*` cases.

### D72: capability derivation reads ranges as points and capability from the current format. LOCAL

- **Evidence.**
  - `getAvailableSampleRates` turns a continuous range into its two endpoints (`CoreAudioDevice.cpp:419-432`), and `supportsRate` tests ±1 Hz against those points (`PureModePolicy.cpp:25-30`). A device advertising 8000–192000 "supports" only 8000 and 192000. Header: "an array of AudioValueRange structs that indicates the valid **ranges**" (`AudioHardwareBase.h:710-712`).
  - `integerCapable = physicalFormat.isPCM && !isFloat` uses the current physical format of the first output stream (`:497`). A DAC currently set to float, or a multi-stream device, is misclassified. The HAL picker re-derives the same fact from the available formats.
- **Remedy (S).**
  - Keep `AudioValueRange` in `DeviceCapability` and test `min−1 ≤ r ≤ max+1` (as Cog does, `DeviceOutput.swift:757-758`).
  - Derive "integer-capable at rate r" from the available physical formats once, and share it with the picker.

### D74: float → native PCM: packed-24 overrun, truncation, NaN UB, no dither. SIGNIFICANT (latent memory safety)

- **Evidence** (`scripts/fmt_probe.cpp`, `nan_probe.cpp`, real `PureModeFormat.cpp`):
  - `bits=24, isPacked=true` dispatches to `store24In32` (`:250-254`), which writes 4 bytes per sample. A 512-frame stereo buffer (3072 B) gets 4096 B: **1024-byte overrun**, and sample[1] reads back as 0 instead of 2097152.
  - `toInt16/24/32` truncate toward zero (`:69-113`). ±0.75 LSB → 0, 1.6 → 1. On a 3-LSB sine: rms error 0.664 LSB vs 0.289 when rounding, and 22% of samples are 0 (a dead zone).
  - NaN: `runtime error: nan is outside the range of representable values of type 'int'` (`:72`, `:88`).
- **SOTA.** Cog `sample_to_int` scales by 2^(bits−1), clips *before* rounding, uses `llrint`, and maps NaN to 0. It has explicit Int24Packed/High/Low writers (`CogRender.c:567-626`). It applies TPDF (±1 LSB) only to samples **off** the 16-bit grid, so an untouched 16-bit track stays exact and silence stays silent (`:652-663`).
- **When is no dither correct?** When every sample is already on the target grid (integer sources at unity, which is Pure's normal case), dither would destroy bit-perfection. Dither (TPDF) is needed only when off-grid values (float or lossy sources, any gain) are requantized to 16 bits. At 24 bits and above, rounding alone is below any DAC's noise.
- **Reachability.**
  - The integer writer runs only when AUHAL's input format is integer, which happens when a non-mixable physical format is chosen.
  - `pickIntegerPhysicalFormat` breaks depth ties by "flags equal the current format", and otherwise keeps list order. A non-mixable packed-24 variant can win when neither variant's flags match the current format.
  - With the D76 bound (`ceil(24/8)=3` bytes, so `writableFrames == frames`), the RT thread then corrupts the heap.
- **Remedy (S).**
  - Derive one sample-format enum (`float32 | int16 | int24High | int24Low | int24Packed | int32`) from the ASBD, including `mBytesPerFrame`, at configure time.
  - Write with Cog's rounding and clipping.
  - Bound by `mBytesPerFrame`.
  - TPDF only for 16-bit output of off-grid samples.
  - Add packed-24, rounding, NaN and dither tests.

### D75: HAL format selection and device ownership. QUESTIONABLE, SIGNIFICANT

- **Evidence and SOTA delta** (Cog `DeviceOutput.swift`, `PLAN.md` stage 8):
  1. `isIntegerMatch` compares `mFormat.mSampleRate` only. It ignores `mSampleRateRange` and `kAudioStreamAnyRate` (`AudioHardwareBase.h:992-997`). Cog handles both (`:757-758`).
  2. Teardown restores only the nominal rate (`:946-959`). The physical format, and any non-mixable state, stay changed. Cog saves and restores the physical format and `SupportsMixing`, and recovers abandoned sessions at the next launch (`:665-697`, `:972-1010`).
  3. `releaseHog` writes −1 unconditionally. Per the header, a set **toggles** ("If no process has exclusive access … this process gains ownership", `AudioHardware.h:932-944`), so a lost hold would be re-taken and never released. Cog toggles off "only if still held" (`:685-689`) and takes it only while the owner is −1 (`:647-662`).
  4. It sets the nominal rate and then the physical format: two reconfigurations. Cog sets the rate through the format, and keeps the nominal rate only as a fallback, after an SMSL DAC failed to start I/O 3 times in 4 (`:621-630`).
  5. It drives held devices through AUHAL. Cog: "AUHAL will not drive such a device (… −10851)", so it uses an IOProc (`PLAN.md:456-458`).
  6. Cog and Pine Player move the system default output off the device before taking hog (`PLAN.md:395-398`, `moveSystemDefaultsAway` `:875`). AdaptiveSound hogs the app's device, which is usually the default.
- The integer path's on-hardware smoke is still owed (`docs/sprints/09-phase-b-bit-perfect-pure-mode.md:3`). In practice the mixable tie-break usually wins, so the AU stays float and the HAL's own float→int (exact at unity for ≤ 24-bit sources) does the work. That is fine, but it is not what the code's comments describe.
- **Remedy (M).** Port Cog's candidate ranking and ownership protocol (save, restore, recover, toggle-safe hog, format-first rate), and test it with a fake property store.

### D77: rate change and the device staying matched. QUESTIONABLE, LOCAL

- Polling the nominal rate (`HALOutputEngine.mm:895-912`) matches Cog's practice (`:1068-1083`), so it is acceptable.
- The gaps:
  - No `kAudioDevicePropertyNominalSampleRate` or `StreamFormat` listener while Pure runs (Cog `:1196-1201`). In RateMatchedFloat (shared, no hog), Audio MIDI Setup or another app can change the rate. AUHAL then converts silently while the UI still says rate-matched.
  - `teardown` writes back `originalRate_` even if the user changed it meanwhile.
- **Remedy (S).** A listener that triggers re-evaluation. Restore only if the current rate is still the one this session set.

### D79: FFmpeg-backend seek ignores `start_time`. LOCAL

- **Evidence** (`scripts/seek_probe.cpp`, real `FileDecodeSource`):
  - With `ADAPTIVESOUND_DECODER=ffmpeg`, `seek(1.234)` on an MP3 (stream `start_time` 0.025057 s) lands 1282 frames early relative to `llround(s·rate)` of the from-open stream, with max\|e\| 0.095 at best alignment.
  - WAV, FLAC and Opus via FFmpeg, and every format via Apple, land on +0.
  - Cause: `ts = frame/rate/timeBase` (`:643`) and `startFrame = pts·tb·rate` (`:780`) omit `stream->start_time`. ffplay adds it (`ffplay.c:3771-3774, 4520-4521`).
  - The FFmpeg back end is the fallback for formats Apple cannot open, so real exposure is to start-time-offset formats only. Today's tests (`FileDecode_Seek_*`, `BackendEquivalenceAfterSeek`) use WAV only.
- **Side note.** Opus via Apple seeks to +0, but the first samples differ from a continuous decode (max\|e\| 0.034). RFC 7845 §4.6 asks for an 80 ms pre-roll.
- **Remedy (S).** Subtract `start_time` (when not `AV_NOPTS_VALUE`) in both places. Add seek tests on MP3/AAC/Opus/Vorbis per back end against decode-from-open.

### D81: the reference tone crashes if ever reached. LOCAL

- **Evidence.**
  - `generateReferenceTone` builds a 1-channel buffer (`+ReferenceTone.swift:19`). `playReferenceTone` schedules it on the stereo player (`+Playback.swift:283-297`).
  - `scripts/mono_probe.swift` reproduces: `*** Terminating app due to uncaught exception … '_outputFormat.channelCount == buffer.format.channelCount'`. This matches `AVAudioPlayerNode.h` "ERRORS 1".
  - It is reached only by `startAudio(fileURL: nil)`. The view model never passes nil (`AudioViewModel+Playback.swift:60`).
  - The float angle without a wrap (`:37-42`) leaves −60 dB of phase noise by 5 s.
- **Remedy (S).** Delete the path and make `fileURL` non-optional.

### D84: Pure device volume ignores per-channel-only devices. QUESTIONABLE, LOCAL

- **Evidence.** `DeviceHardwareVolume` uses the main element only (`+MasterGain.swift:140-170`).
- **SOTA.** `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` "applies to [individual channel volume controls] identified by the device's preferred … stereo pair" and keeps balance (`AudioHardwareService.h:49-57`). For dB-linear control, set `VolumeDecibels` on each element of the preferred stereo pair. Cog does "main control, else each channel's".
- **Remedy (S).**

---

## BR-2 (app-owned ring + `AVAudioSourceNode` for Enhanced): my independent assessment

**Agree, on measured evidence, with one correction and a sequencing.**

- **The completion-driven `AVAudioPlayerNode` schedule is the common root of the D39/D40 defects.** That covers (a) the passthrough gap, (b) the resampler race gap, and (d) the seam timing. It also covers the two epochs and the "nil hook under a live epoch" inference that `stop()` firing completions forced (known from memory and BR-2).
- **Both reference players converged on the alternative.**
  - SFB: an `AVAudioSourceNode` reads an SPSC ring. The decoder queue pre-decodes the next track into the same ring. Joins are gapless only on rate, channels and layout. Seek is a consumer-honoured `audioStale` discard, with no blocking barrier. Seam events are host-time stamped from the render timestamp (`AudioPlayer.mm:224-232, 1612-1745`).
  - Cog (2026 rewrite): feeder → deep ring → DSP pump → shallow ring → C render. A persistent soxr. Positional seam markers. A flush epoch. A heard position equal to the read position minus a latency cached at configure time (`PLAN.md:56-80`, `DeviceOutput.swift:1269-1287`).
- **The ring alone does not fix the audible seam.** D39(c) is an SRC property. The persistent converter (Cog principle 2) is the part that removes the click, so put it in the decode worker that feeds the ring.
- **Correction to BR-2's open question.** "SRC quality and CPU must be measured against `AVAudioConverter(.max)`" is answered above. `.max` Normal is the weak option. Mastering and soxr VHQ both reach ≤ −150 dB and are flat to 20 kHz, at 0.02–0.6 s of CPU per minute per channel. SRC is not a blocker for BR-2.
- **Reuse.** Pure already owns the pieces (`FileDecodeSource` + `SpscRing` + `GaplessSource` with render-side accounting; D41 is PROVEN-CORRECT). The Enhanced source node can pull from a `GaplessSource` whose decode thread also resamples to the graph rate. The seam/position contract tests then cover both paths.
- **Costs.**
  - Seek needs a consumer-honoured flush. RenderGate also works, but SFB/Cog avoid the barrier.
  - Channel-count changes still need a graph reconfigure (a non-gapless join, as SFB does).
  - The ring must be sized in seconds (Cog principle 4; D78).
- **Sequencing I recommend.**
  1. Interim fixes, each S: arm ahead, persistent converter, Mastering.
  2. Then BR-2, which is L and deletes about 1,500 LOC of epoch/hook machinery.

## Where I agree or disagree with earlier evidence
- **rev-sota M5** (passthrough gap): agree. I add the `.dataConsumed` lead measurement that gives a one-callback fix, and the device L values.
- **rev-sota M2** (resampler seam early by "~0.4 s + L"): disagree on magnitude. It is 0–186 ms + L, and can be late. Agree on the cause.
- **SRCQualityMeasure / B5** ("ALL TONES PASS … meets the bar"): disagree. Its own output shows −6.9 dB relative at 20 kHz, and the bar omits passband and stopband.
- **sprint-09 doc** ("FullBitPerfect … the real bit-perfect route the spike proved"): it is unproven on a USB DAC (the doc says so), and D74/D75 show it is fragile.
- **area-bridge BR-2**: agree (above).

## Reproduction (all under `scratchpad/council/exp-p3-sota/`)
- **Seam timing:**
  - `scripts/seam_probe_cb.swift`: when each completion type fires.
  - `seam_passthrough.swift`: production versus pre-scheduled seam.
  - `seam_resampler.swift`: replica of the resampler chain and roll.
  - `seam_split_profile.swift <sine|noise> <split>`: join transient.
- **SRC:** `src_dump.swift` (production pattern), `src_quality.py`, `src_passband.py` (soxr VHQ and libsamplerate as references), `stream_vs_oneshot.swift`.
- **Real C++ under probes** (built from the worktree):
  - `fmt_probe.cpp`, `nan_probe.cpp` (D74);
  - `chan_probe.cpp` (D71/D76);
  - `seek_probe.cpp` (D79).
- **Other probes:** `volume_probe.swift` (D83), `mono_probe.swift` (D81).
- **Read-only HAL:** `hal_query.swift`, `hal_latency.swift`.
