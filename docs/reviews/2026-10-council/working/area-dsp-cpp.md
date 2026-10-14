# Area review: C / C++ / Objective-C++ in `Sources/AudioDSP/` (council Stage 2)

Reviewer: area-dsp-cpp. Snapshot: `main` @ `a206107`. Read-only on Sources/Tests. Sources opened for state of the art are
saved under `scratchpad/council/exp-dsp-cpp/src/` (VLC `auhal.c`, SFBAudioEngine `AudioPlayer.{h,mm}`, JUCE
`juce_FloatVectorOperations.{h,cpp}` and `juce_ProcessorChain.h`, Apple TN2091, Apple `AVAudioEngine.stop()` doc JSON). The
macOS 26 SDK headers (`CoreAudio.framework/Headers/AudioHardware.h`, `AudioHardwareBase.h`) were read locally. One experiment
was run, a RenderGate close-latency probe (`exp-dsp-cpp/gate/gate_probe.cpp`). It is compiled outside the repo against the
real `RenderGate.h`.

Scope read in full: `DSPKernel`, `TargetState`, `DoubleBufferSnapshot`, `RenderGate`, `SpscRing`, `ParameterRamp`,
`MultichannelView`, `FlushToZero`, `FiniteSamples`, `RtSwappableResource`, `PerChannel`, `EQModule`, `LimiterModule`,
`CrossfeedModule`, `LoudnessModule`, `CausalLoudnessTap`, `ClarityModule`, `BRIRModule`, `Realizer.{h,mm}`, `AUAudioUnit.mm`,
`SpatialRendererAU.mm`, `SpatialRenderKernel`, `HALOutputEngine.{h,mm}`, `PureModeBridge.{h,cpp}`, `PureModePolicy.cpp`,
`PureModeFormat`, `GaplessSource`, `FileDecodeSource` (the Apple and FFmpeg backends, plus the Impl),
`CoreAudioDevice`, `DeviceListPolicy.h`, `LoudnessMeterBridge.cpp`, and the C-ABI headers. The individual algorithms
(designer, LUFS, limiter maths) got only a skim: they belong to the later panels.

**Counts:** 2 STRUCTURAL, 8 SIGNIFICANT, 7 LOCAL.

---

## STRUCTURAL

### DSP-01 Two complete playback engines: decode, seek, gapless, playhead and format coverage are each built twice, and the two copies behave differently. STRUCTURAL. Criteria: 2, 3, 5, 6
- **Evidence:**
  - Pure is C++: `FileDecodeSource.cpp:900-1152` (decode thread → `SpscRing` → `pullFloat`); `GaplessSource.cpp:229-281` (the seam); `PureModeBridge.cpp:209-243` (seek = hold render + `FileDecodeSource::seek`); position = `seekBase + renderedFrames` (`GaplessSource.cpp:197-205`).
  - Enhanced is Swift and AVFAudio: `AVAudioFile` + `scheduleFile` / a streaming `AVAudioConverter` (`AudioEngineBridge+Playback.swift`, `+EnhancedResampler*.swift`, `+Gapless.swift`, `+GaplessRoll.swift`); position = player `sampleTime` + base.
  - The decoder strategy (`DecodeBackend`: Apple `ExtAudioFile` first, then FFmpeg through dlopen, `FileDecodeSource.cpp:113-147, 914-972`) exists **only on the Pure path**. Enhanced opens files with `AVAudioFile(forReading:)` (7 sites in the app). A file that only FFmpeg can decode (Opus, Ogg) is therefore scanned into the library through the FFmpeg metadata bridge, plays in Pure, and fails in Enhanced, which is the default path.
  - The two copies already disagree on details: seek rounding (map §8A fact 5: Enhanced truncates, Pure uses `llround`), and the lossy-delay trim ("Pure/FFmpeg trim is Stage 2", `+Playback.swift:205`).
  - The Enhanced copy has no engine-level tests (map §5.3: D37 and D39 are tested only through mocks).
- **Root cause:** Pure was built as a separate engine beside AVAudioEngine, not as a second *sink* fed by one shared *source pipeline*. Everything upstream of the device (decode, ring, seek, gapless sequencing, playhead) was therefore implemented once per sink.
- **Why it matters:** every transport feature or bug fix lands twice, in two languages. Format support depends on the path. The untested Swift copy carries most of the Enhanced risk. The R2 adaptive work (per-track analysis at the seam, crossfades, ReplayGain) would need a third and fourth copy.
- **Structural remedy:** one C++ **source pipeline**: `DecodeBackend` strategy → ring → gapless sequencer → seek-as-message (see DSP-06) → optional resampler stage. It feeds **two sinks**:
  - (a) the HAL sink (today's `HALOutputEngine`);
  - (b) an `AVAudioSourceNode` render block feeding the effects AU, replacing `AVAudioPlayerNode` + `scheduleFile` + the Swift converter roll.

  This is exactly SFBAudioEngine's architecture. One decoder abstraction feeds one ring; `AVAudioSourceNode` renders from the ring (`sfb::AudioPlayer::render(BOOL &isSilence, const AudioTimeStamp&, AVAudioFrameCount, AudioBufferList&)`, `AudioPlayer.mm:1612`); decoded chunks are tagged with sequence numbers, so the playhead and the gapless boundary come from the same data (`AudioPlayer.h:40-91`). It is Apple-native at the output boundary, which keeps to the "Apple-native for playback / output" rule. Do it in steps:
  1. make Enhanced decode through `FileDecodeSource` (same ring, an `AVAudioSourceNode` sink);
  2. move gapless sequencing onto `GaplessSource` for both paths;
  3. delete the Swift roll and resampler copies.
- **Effort:** L. **Risk of the change:** high (it touches the live transport). **Depends on:** DSP-06; the architecture reviewer's bridge findings.

### DSP-02 The C-ABI boundary is type-erased and holds its ownership rules in comments, with three handle conventions, flattened errors and a dead exported surface. STRUCTURAL. Criteria: 1, 5, 6
- **Evidence:**
  - **Three handle conventions side by side:**
    - (1) `void*` holding a `__bridge` Objective-C object: `publishEQ(void* auUnit, …)` (`AUAudioUnit.mm:424-433`) and 9 sibling functions. Swift passes `Unmanaged.passUnretained(unit).toOpaque()` (`AudioEngineBridge+SharedState.swift:252-256`).
    - (2) `void*` holding a C++ object: `pureModeEngine*` (`PureModeBridge.h:118-185`), `loudnessMeter*` (`DeviceBridge.h:95-106`), `ffmpeg*Metadata` (`MetadataBridge.h:49-66`).
    - (3) typed opaque structs: `AsEqDesigner*` (`EQDesignBridge.h:25`) and `AsLoudnessProfiler*` / `AsLoudnessProfile*` (`TrackLoudnessBridge.h:43-47`).

    `pureModeEngineArmOpenedNextTrack(void* engine, void* decoder)` compiles with the arguments swapped (I.4, I.24).
  - **Ownership lives in prose:** "TAKES OWNERSHIP of `decoder` on every outcome … the caller must NOT free it afterwards" (`PureModeBridge.h:158-167`); "Do NOT call after a successful arm" (`:169-172`). Every Swift wrapper (`PureModeSession`, `LoudnessMeterHandle`, `TrackLoudnessProfileHandle`) re-implements RAII, and four of them are `@unchecked Sendable` (map §3.4). This is I.11: ownership is transferred by raw pointer.
  - **Errors are flattened:** `pureModeEngineStart` returns `0` for at least six distinct failures: open, seek-to-start, rate-match declined, unit creation, format negotiation, start (`PureModeBridge.cpp:138-205`, `HALOutputEngine.mm:413-454`). The reason exists only in a log line. Swift records just `fellBackToEnhanced = true` (`+Playback.swift`, `attemptPureStart`). This is E.27: the code is exception-free, so it should use error codes systematically.
  - **`nothrow` that is only cosmetic:** `new (std::nothrow) PureModeSession()` (`PureModeBridge.cpp:129`), but the constructor calls the throwing `make_unique` twice (`:64-68`). Under `-fno-exceptions` an out-of-memory error there aborts either way. The `nothrow` documents a guarantee the code does not have.
  - **Dead exported surface:** `createAdaptiveAudioUnit`, `destroyAdaptiveAudioUnit`, `setAUParameter`, `getAUParameter`, the `publishTargetState` C-ABI (`AUAudioUnit.mm:364-422`) and `configureSpatialChannels` (`SpatialRendererAU.mm`) have **no caller** in Swift, the harnesses or the tests. Several are not even in a Swift-visible header (`AudioUnitBridge.h` is not in the module map). They are kept "as part of the stable exported C-ABI (F6)", but this C-ABI has one consumer, compiled in the same package. No ABI-stability constraint applies.
- **Root cause:** the boundary was designed as a C ABI with `void*` erasure. That made sense for C++ objects (Swift could not import them), but it was also applied to an Objective-C class, which Swift *can* import, and it was never consolidated as the bridges multiplied.
- **Why it matters:** wrong-handle and double-free bugs compile cleanly. Every new engine feature adds another hand-written null-check + `static_cast` + Swift RAII wrapper. Pure fallbacks cannot tell the user why. Dead entry points read as supported API.
- **Structural remedy:**
  1. **Effects AU:** expose a small Objective-C protocol in a Swift-importable header (`@protocol ASEffectsControl - (BOOL)publishEQ:…`). Move the C++ ivars into the `.mm` class extension. Swift then holds the `AUAudioUnit` strongly, and ARC owns the lifetime, so the `void*`, the `__bridge` casts and the `Unmanaged` borrow all go away. Apple's own AUv3 samples talk to the AU subclass through Objective-C in exactly this way.
  2. **C++ objects:** use typed opaque structs everywhere (the newer `AsEqDesigner` style), with one create / destroy pair per type and a `[[nodiscard]]` C `enum` result code (`AS_PURE_OK`, `AS_PURE_E_OPEN`, `AS_PURE_E_RATE_LOCKED`, …). Inside C++, use `std::expected<void, PureStartError>` (C++23, available in libc++). Forward the reason into `SignalPathInfo`.
  3. **Medium term:** evaluate Swift↔C++ interop (`SWIFT_SHARED_REFERENCE` / non-copyable import from `<swift/bridging>`) for `PureModeSession`, so the Swift type system enforces the "arm takes ownership" rule.
  4. **Now:** delete the dead entry points (see DSP-12).
- **Effort:** M (steps 1, 2 and 4); L (step 3). **Risk of the change:** med. **Depends on:** none.

---

## SIGNIFICANT

### DSP-03 Pure plays silence when the file's channel count differs from the device stream's (a mono file on any stereo output, or a stereo file on an 8-channel HDMI stream). SIGNIFICANT. Criteria: 4, 6
- **Evidence:**
  - The render pulls `rfChannels_` channels, the **device** format's count (`HALOutputEngine.mm:821, 845`).
  - `FileDecodeSource::pullFloat` returns 0 and zero-fills when `channels != channels_` (`FileDecodeSource.cpp:1012-1016`). The behaviour is pinned by `FileDecode_PullChannelMismatchSilence`.
  - `GaplessSource::pullFloat` then sees a short fill that is not `exhausted()` (the decoder is alive) and holds (`GaplessSource.cpp:248-251`): silence forever, with the playhead stuck at 0.
  - The policy that should prevent this never reads `file.channels`. `evaluatePureMode` reads only `file.sampleRate` (`PureModePolicy.cpp:85-141`, lines 114/120/126/127), and `FileFormat::channels` / `bitsPerChannel` / `isFloat` are carried but unused (`DeviceCapability.h:58-64`).
  - Swift's `evaluatePureViable` trusts the decision (`+PureMode.swift`).
  - No test and no doc covers the mismatch at policy level.
- **Root cause:** channel compatibility is checked at the RT layer (a defensive `memset`) instead of being a precondition of the Pure decision. The silent fallback turns a configuration error into "playing, but nothing comes out".
- **Why it matters:** mono material (old recordings, spoken word, the founder's legacy-remaster interest) is silent in Pure on every Mac, while the UI says "Pure / bit-perfect". The HDMI case depends on the receiver's stream width.
- **Structural remedy:** make channel compatibility part of the policy's *facts → decision*:
  - (a) **now:** `evaluatePureMode` returns `FallbackEnhanced` with a new `PureModeReason::ChannelLayoutMismatch` when `file.channels` ≠ the stream channel count, and a policy test covers it;
  - (b) **later:** support it bit-perfectly with AUHAL's `kAudioOutputUnitProperty_ChannelMap`. Set the AU input format to the file's channel count and map source to device channels (mono → `[0, 0]`, stereo onto the first two of eight). This is a routing change, not a sample change, so it stays bit-perfect (Apple TN2091 §"Channel Mapping": an array of `SInt32`, one entry per destination, `-1` = no source).

  Keep the RT `memset` as the last guard only.
- **Effort:** S for (a), M for (b). **Risk of the change:** low. **Depends on:** none. (Check the panels' D71 / N98 rows.)

### DSP-04 The HAL native sample format is passed around as loose fields and `bool`s and never validated. A packed 24-bit (3-byte) stream gets 4-byte words, which corrupts the audio and overruns the device buffer on the IO thread. SIGNIFICANT. Criteria: 1, 4, 6
- **Evidence:**
  - `cacheRenderFormat` decomposes the ASBD into seven loose members (`rfChannels_ … rfIsBigEndian_`, `HALOutputEngine.mm:770-787, 996-1002`).
  - `convertFloatToNative` takes ten parameters, six of them `bool` / bit-flag soup (`PureModeFormat.h:41-50`; I.4, I.23).
  - **Nothing reads `mBytesPerFrame` or `kAudioFormatFlagIsNonInterleaved`** (grep: zero uses in the HAL path).
  - The converter sends *every* 24-bit integer format to `store24In32`, which writes 4-byte words (`PureModeFormat.cpp:250-254, 197-212`), whether `isPacked` is set or not.
  - The render's capacity clamp derives bytes per sample as `ceil(bits/8)` = 3 (`HALOutputEngine.mm:866-874`). For packed 24-bit stereo it therefore allows `frames` frames × 8 bytes into a `frames × 6`-byte buffer: an overrun of a third on the RT thread.
  - `isIntegerMatch` does not exclude packed-24 physical formats (`:251-267`), which are common on UAC1/UAC2 DACs.
  - Non-interleaved device formats would be written interleaved into `mBuffers[0]` (`:855-860`; the comment says "The AUHAL input format is interleaved (one buffer)", an assumption that is never checked).
  - The scratch is fixed at 4096 frames (`:50, 786`). `kAudioUnitProperty_MaximumFramesPerSlice` is never queried or set, so a device running bigger slices gets a full buffer of silence on *every* callback (`:824-831`).
  - Map fact #2 noticed the loose clamp. The packed-24 overrun, the non-interleaved case and the slice size are new.
- **Root cause:** there is no value type for "the device's native PCM format". Two separate derivations of bytes per sample disagree, and an unsupported format is discovered per render block (it writes silence) instead of being refused at configure time.
- **Why it matters:** the integer DAC path has never run on a USB DAC (product.md NFR-QUAL-03). This is precisely the path where packed-24 shows up, and the first failure there is a heap overrun on the HAL IO thread.
- **Structural remedy:**
  1. Add a CoreAudio-free `struct NativePcmFormat { uint32_t channels, validBits, bytesPerSample, bytesPerFrame; Encoding encoding; Endian endian; Justify justify; }`. Build it with a `static std::optional<NativePcmFormat> fromAsbd(const AudioStreamBasicDescription&)` that returns `nullopt` for anything the converter cannot write: non-interleaved, packed-24 if unsupported, unknown widths.
  2. In `configure()`, **decline Pure** (return a typed error, per DSP-02) when it is `nullopt`.
  3. Use `convertFloatToNative(span<const float>, span<std::byte> dst, const NativePcmFormat&)`. It writes exactly `dst.size() / bytesPerFrame` frames, with one source of truth for the stride.
  4. Add a `store24Packed` (3-byte) writer if packed-24 is to be supported.
  5. Size the scratch from `MaximumFramesPerSlice` (query it or set it).

  The pure `fromAsbd` and the picker (`pickIntegerPhysicalFormat`, which is pure but sits in an anonymous `.mm` namespace) then become null-test cases, following the project's own `DeviceListPolicy` / `PureModePolicy` pattern.
- **Effort:** M. **Risk of the change:** low. **Depends on:** DSP-02 (error type). (Panel rows D74, D75, D76.)

### DSP-05 The HAL device-state contract is incomplete: changes are treated as synchronous, the physical format is never restored, and hog mode is set "by value" although the HAL toggles it. SIGNIFICANT. Criteria: 4, 5, 6
- **Evidence:**
  - The SDK says "Changing the value of a property is always considered asynchronous" and "the value of the property should not be considered changed until the HAL has called the listeners" (`AudioHardware.h:33-34, 303-304`).
  - `applyBitPerfectFormat` sets `kAudioStreamPropertyPhysicalFormat` and **immediately** reads the AU output format, to which it then matches the AU input (`HALOutputEngine.mm:672-711`). No listener, no wait: a stale read makes AUHAL convert (no longer bit-perfect) without anything noticing.
  - The nominal rate *is* polled (2 s in 10 ms steps, `:895-912`), which is the dated form of the same wait.
  - The header promises "the original device nominal rate is saved … and ALWAYS restored" (`HALOutputEngine.h:14-17`), but the **physical format** that `configure` changed is never saved or restored (`teardown`, `:916-969`). The DAC stays in the integer format Pure chose.
  - Hog mode: the SDK says "when setting this property, the value passed in is ignored … If the current process owns exclusive access, it is released … If no process has exclusive access, this process gains ownership" (`AudioHardware.h:932-944`), so it is a **toggle**. `acquireHog` sets `getpid()` without reading the owner first (`:308-327`), and `releaseHog` comments "`-1 == release`" (`:336`). It works only because the call sites keep the toggle balanced. A process that already holds hog (a leaked session) would *release* it by "acquiring".
  - **State of the art, VLC `auhal.c`** (opened):
    - it reads the hog owner first and refuses if another pid holds it (`:1139-1159`);
    - it releases hog only if `i_hog_pid == getpid()` (`:1454-1466`);
    - it saves `sfmt_revert` and restores the stream format on close (`:1272-1282, 1424`);
    - it changes the physical format through a property listener and a condition wait with timeout and re-check, "because SetProperty is asynchronous" (`AudioStreamChangeFormat`, `:765-877`).
  - The HAL helpers are duplicated: `firstOutputStream` in both `HALOutputEngine.mm:147-170` and `CoreAudioDevice.cpp:361-386`, and nominal-rate getters with different scopes (Global vs Output) and types (`double` vs `uint32_t`-truncated: `CoreAudioDevice.cpp:243-265`, `HALOutputEngine.mm:279-293`). That makes 21 hand-built `AudioObjectPropertyAddress` blocks in AudioDSP, plus more in Swift.
- **Root cause:** device mutation is written as straight-line set-then-read, with no "saved device state" value and no typed property layer.
- **Why it matters:** bit-perfect correctness on real DACs depends on a race; the device is left changed after Pure; and hog handling relies on a misreading of the API.
- **Structural remedy:**
  1. Add a `DeviceStateGuard` RAII object, built at `configure`, that snapshots {nominal rate, physical format, hog owner} and restores exactly what it changed in its destructor (E.6 / R.1; VLC's `sfmt_revert` + `b_revert`).
  2. Add a tiny typed `HalProperty<T>` get / set / `setAndWait(listener, timeout)` layer, shared by `CoreAudioDevice` and `HALOutputEngine`, replacing the copied helpers and the rate poll. (sbooth's `CAAudioHardware` package is the Swift-side reference for such a typed HAL layer.)
  3. `acquireHog` reads first and toggles only when the owner is −1; `releaseHog` toggles only when the owner is us.
- **Effort:** M. **Risk of the change:** med (it touches real-device behaviour that has no automated test). **Depends on:** DSP-04. (Panel row D77.)

### DSP-06 `RenderGate` has no forward-progress guarantee for the closer (the root of the CI flake), teardown carries on past a failed close, and the gate exists only because seek mutates consumer-owned state from the control thread. SIGNIFICANT. Criteria: 1, 4, 5
- **Evidence:**
  - `close()` succeeds only if its CAS happens to land while the state is `Open` (`RenderGate.h:58-85`). A renderer that re-enters at once can starve it indefinitely: there is no "close requested" state that turns the *next* `tryEnter` away.
  - The probe (`exp-dsp-cpp/gate/gate_probe.cpp`, the real header, an idle machine): **busy renderer: p50 0.1 µs, p99 6.3 ms, max 23.5 ms (O2); p99 0.7 ms, max 4.9 ms (TSan)**. With a HAL-like 2 ms-period renderer the max was 0.1 µs. "Bounded by one render pass" (`HALOutputEngine.h:69-73`) holds only because the HAL renders periodically, and the bound is not a property of the gate.
  - The CI failure ("close() timed out at seek 1304", process.md §CI) is this starvation, made worse by a small shared runner, against the test's never-yielding renderer (`RenderGateTests.inc:173-179`).
  - `teardown()` logs a failed close and **continues** to dispose the unit and clear `source_` (`HALOutputEngine.mm:920-944`). `pureModeEngineDestroy` then deletes the `GaplessSource` (`PureModeBridge.cpp:264-266`). A render still inside after 100 ms (the case the code itself expects, "on a dying device AudioOutputUnitStop can fail or wait seconds", `RenderGate.h:9-10`) is then a use-after-free.
  - Why a gate at all: `FileDecodeSource::seek` joins the decode thread, `reset()`s the ring (consumer-owned head and carry) and **spawns a new decode thread per seek** (`FileDecodeSource.cpp:988-1002, 1086-1095`). Only a barrier makes that safe.
  - **State of the art, SFBAudioEngine** (opened): a seek is a lock-free `std::atomic<SeekRequest>` (`AudioPlayer.h:93-99, 166`) that the *decoder thread* processes. It then sets `muted | audioStale` (`AudioPlayer.mm:1225`), and the **render thread itself discards the stale ring** at its next cycle (`AudioPlayer.mm:1612-1632`). There is no barrier, no wait, no timeout, and no thread respawn.
- **Root cause:** ownership of the ring's consumer state is violated by the control plane, so a blocking barrier was added. The barrier is a polled CAS with no intent bit.
- **Why it matters:** there is a flaky gate today and a latent UAF in the failure path. Every seek pays a thread join and spawn. The R2 features that need transport changes (crossfade, A-B loop) would all route through the same blocking barrier.
- **Structural remedy:**
  1. **Seek as a message:** `FileDecodeSource` gets an atomic seek request (generation + frame). The decode thread repositions and bumps a `ringGeneration`. `pullFloat` drops data from an older generation (or sees an `audioStale` flag and discards), so the consumer remains the only party that touches its own state, and the decode thread lives for the whole file. The seek then needs no gate.
  2. **Teardown:** keep a gate, but give it four states (`Open`, `Rendering`, `Closing`, `Closed`). `close()` CASes `Rendering→Closing`; `leave()` turns `Closing→Closed`; `tryEnter` fails in `Closing`/`Closed`. The closer then waits for at most one pass whatever the renderer's cadence. The RT side stays wait-free (one CAS, at most one store).
  3. On a failed close in teardown, **do not free the source**: park it in a deferred-reclaim slot freed on the next successful quiesce, or leak it deliberately and log. Never free it under a possibly running render.
  4. Make the test's renderer periodic (it currently models no real host), and keep one adversarial busy-renderer case for the four-state gate.
- **Effort:** M. **Risk of the change:** med. **Depends on:** DSP-01 (the same source pipeline). (Panel rows D63 / N100, D79.)

### DSP-07 Kernel re-initialisation rebuilds every module and its worker threads. The channel layout bypasses the Realizer (a second, unserialised producer) and is lost on every re-allocation. SIGNIFICANT. Criteria: 1, 4
- **Evidence:**
  - `DSPKernel::initialize` does `make_unique` for all seven stages (`DSPKernel.cpp:62-76`). `LoudnessModule` and `CausalLoudnessTap` each start a new `jthread` and allocate a 1 MiB ring (`LoudnessModule.cpp:88-89`, `CausalLoudnessTap.cpp:35`, `LoudnessModule.h:58`).
  - `initialize` runs on **every** `allocateRenderResources`, routed through `Realizer::reinitializeKernel` (`AUAudioUnit.mm:152-171`). AVAudioEngine re-allocates on width / rate change and on every `stop()` / `start()` ("Stops the audio engine … and releases any previously prepared resources", the Apple `AVAudioEngine.stop()` doc). So the normaliser's measured loudness, its makeup and its slew state reset on each engine restart (device change, re-establish) and each width change.
  - The **layout weights** also reset to the stereo default (`LoudnessModule.cpp:70-84`; `CausalLoudnessTap.h:133`). The Realizer does not re-publish them (`Realizer.mm:341-361`), and Swift publishes them only at `configureGraphForSource` (`AudioEngineBridge+ChannelLayout.swift:64-75`), not after the configuration-change re-establish (`+ConfigChange.swift:60-121`). After a device change during a 5.1 track, BS.1770 measures with LFE weighted 1 and surrounds at 1.0 instead of 0 / 1.41.
  - The layout goes **around** the Realizer: `publishChannelLayoutTag` → `_kernel->publishChannelLayout` directly from `engineQueue` (`AUAudioUnit.mm:231-236, 531-537`). That races `DSPKernel::initialize` replacing `loudnessModule_` on the Realizer queue, which is driven from `configChangeQueue` (`DSPKernel.cpp:110-121`). The `AdaptiveSoundAU` header comment calls the Realizer "the sole producer of feed-forward control" (`AUAudioUnit.mm:44-50`).
  - The layout hand-off itself is a **two-slot generation-parity buffer** (`LoudnessModule.cpp:33-49, 220-231`). A producer that publishes twice while the worker is still reading `layoutWeights_[gen&1]` writes the slot being read. It is the same lapping hazard the project fixed for `TargetState` by moving to the triple buffer (`DoubleBufferSnapshot.h:15-23`). No test calls `publishChannelLayout` (map D70).
  - The claim "jthread move-assignment stops+joins any previous worker (safe to re-initialize)" (`LoudnessModule.cpp:86-87`) is false: `meter_`, `layoutWeights_` and `currentMakeupDb_` are written *before* the assignment joins the old worker. It is never exercised, only because the kernel re-creates the module instead.
- **Root cause:** "initialize" means "construct afresh", so state lives in objects with no stable lifetime. And the layout was never made part of the Realizer's canonical state.
- **Why it matters:**
  - The normaliser (the default Enhanced path) re-learns from unity after every device or width change.
  - Multichannel loudness is mis-weighted after a device change.
  - There is a real data race between two control queues.
  - Every re-allocation joins and spawns two threads and frees and allocates 2 MiB.
- **Structural remedy:**
  1. Construct modules **once** (in `DSPKernel`'s constructor or as direct members) and give each a `prepare(ProcessSpec)` that re-sizes buffers and resets only rate-dependent state, keeping workers alive (JUCE's `prepare` / `reset` split; `juce_ProcessorChain.h:83-95`, opened).
  2. Make the channel layout a **Realizer intent** (a `PendingSlot<ChannelLayoutIntent>`), stored canonically and re-applied in `reinitializeOnQueue` like the EQ and crossfeed. It reaches the workers through the same publish edge (a field of `TargetState`, or a `DoubleBufferSnapshot<LayoutWeights>`), and the parity buffer is deleted.
  3. Decide deliberately whether the normaliser's measurement should survive a device change (it probably should).
- **Effort:** M. **Risk of the change:** med (golden master and re-allocation tests apply). **Depends on:** DSP-09, DSP-10.

### DSP-08 For N source channels on an M < N device, the spatial AU drops channels M…N−1: 5.1 on headphones loses the centre (dialogue / vocals), the LFE and the surrounds. SIGNIFICANT. Criteria: 4
- **Evidence:** `SpatialRenderKernel.cpp:173-177` ("Stub: copy first numOut source channels; discard the rest") and `routeBinauralStub` (`:75-91`). The graph uses M = min(N, device) (`AudioFormatKit/MultichannelFormat.swift:89-103`; `+Graph.swift:52-90`). The only test covers `in ≥ out` (map D46).
- **Root cause:** the binaural renderer is deferred (S18), and the stub chose "keep the first M" as its interim. That choice was never treated as a product decision.
- **Why it matters:** the founder's rule is "no naive downmix". But discarding C is far worse than any downmix: speech and lead vocals vanish from every 5.1 file on headphones or laptop speakers. An L/R-only rendering is not "unprocessed"; it is wrong.
- **Structural remedy:** make the interim renderer the standard **ITU-R BS.775 Lo/Ro downmix** (C and surrounds at −3 dB into L/R, LFE excluded or optional), as a coefficient matrix applied in the spatial kernel. It is deterministic and level-safe (the limiter follows), with tests for 5.1 and 7.1 → 2. S18's HRIR renderer then replaces the matrix stage in the same slot. Alternatively, decline the reduction and let AVAudioEngine's mixer downmix. Either beats truncation. **Founder decision** (see Q2).
- **Effort:** S–M. **Risk of the change:** low. **Depends on:** none. (Panel row D46.)

### DSP-09 The "RT stream → worker analyser" tap is implemented twice. The copies use different hand-off mechanisms, and both poll forever. SIGNIFICANT. Criteria: 3, 5
- **Evidence:**
  - `LoudnessModule::process` (`LoudnessModule.cpp:92-159`) and `CausalLoudnessTap::push` (`CausalLoudnessTap.cpp:75-103`) are the same algorithm: relay the channel count by atomic, interleave into a pre-sized `pushBuf_`, `tryPushAll` into a 32768 × 8-float `SpscRing`, count drops. Both worker loops then drain frame-aligned chunks (`LoudnessModule.cpp:195-262`; `CausalLoudnessTap.cpp:197-239`).
  - The layout weights reach the two workers through **different** mechanisms: the lock-free parity buffer (`LoudnessModule.cpp:33-49`) and a mutex (`CausalLoudnessTap.cpp:57-73`), both from one call (`DSPKernel.cpp:110-121`).
  - Both workers poll with sleeps. The normaliser sleeps **5 ms when the ring is empty** (`LoudnessModule.h:65`, `.cpp:240-244`), so it wakes about 200 times a second whenever audio is paused or the kernel is on its bit-perfect P0 path (the normaliser is not fed there, `DSPKernel.cpp:208-212`). The causal tap sleeps 50 ms (`CausalLoudnessTap.cpp:17`). Both threads exist for the AU's whole life.
  - A third and a fourth loudness meter exist elsewhere: the UI meter on the mixer tap (`LoudnessMeterBridge.cpp`) and the second-decode analyser (TrackLoudnessKit). The normaliser's own telemetry getters (`LoudnessModule.h:103-107`) have no production reader.
- **Root cause:** there is no reusable "RT tap → off-RT analyser" component. Each analyser grew its own plumbing.
- **Why it matters:** two places to fix every ring, drop or alignment bug (the all-or-nothing `tryPushAll` fix had to land in both). Two hand-off designs for one datum. Idle energy cost, which matters for a music player that is often paused.
- **Structural remedy:** extract `template <class Analyser> class RtAnalysisTap`. It owns the ring, the interleave scratch, the drop counter, a worker that **parks when idle** (back off to 100 ms+ when empty, or park on a `std::binary_semaphore` released off-RT by the transport), and one layout-weights hand-off (a `DoubleBufferSnapshot<LayoutWeights>`). `Analyser` is a concept with `configure(channels, weights)` and `feed(span)`. `LufsMeter` and `TrackLoudnessProfiler` become the two policies. Delete the unused telemetry getters, or have the UI meter read the normaliser's instead of running a duplicate meter, if a pre-limiter reading is wanted.
- **Effort:** M. **Risk of the change:** low–med. **Depends on:** DSP-07.

### DSP-10 The DSP chain is hand-wired. It has no enforced stage interface, keeps its path state machine in booleans, and runs placeholder stages inside the RT path and `TargetState`. SIGNIFICANT. Criteria: 1, 2
- **Evidence:**
  - The "module interface" exists only in comments: the stubs say they match "the module interface (EQ/Loudness/Limiter)" (`ClarityModule.h:9-12`, `BRIRModule.h:9-12`). Yet the signatures differ: `EQModule::update` + `process(view)`; `LoudnessModule::process(params, view, span)`; `LimiterModule::process(params, view)` + `prime`; `CrossfeedModule::process(params, view)`. Nothing enforces the stage contract.
  - P0–P3 are implicit, in `settled`, `endpoint`, `atZero`, `atOne`, `identity`, `wantBypass`, `bypassMix_` and `firstBlock_` (`DSPKernel.cpp:176-224`). Path selection cannot be tested apart from `process()`.
  - Clarity and BRIR are pass-through stubs, called on every P2/P3 block (`DSPKernel.cpp:401-407`). Their parameter structs live in the 768 B RT snapshot (`TargetState.h:49-76, 132-142`), together with `kClarity*` constants (`AudioConstants.h:35-38`), and **nothing ever writes them** (grep).
  - Consequence for the algorithm: with both stubs at pass-through and crossfeed off, wet == dry exactly, so the equal-power blend `sin + cos` is a **+3 dB hump at Intensity 0.5** (`DSPKernel.cpp:267-275` admits it). Only the normaliser's 1 dB/s slew absorbs it (`LoudnessModule.h:51`). The same file already has the right answer: a correlation-compensated law for the P0 crossfade (`DSPKernel.cpp:350-397`). This is two crossfade laws in one class, with the safer one unused where it is needed (panel row D50).
  - `DSPKernel::process` copies the snapshot twice: `tryCopySnapshot(scratchState_)` then `currentState_ = scratchState_` (`:152-153`), a leftover from the retrying seqlock.
- **Root cause:** the chain grew stage by stage around a fixed member list, and future epics were scaffolded into the RT path ahead of their designs.
- **Why it matters:** each new stage (R2's Clarity, S18's BRIR) is hand-plumbed into four paths. Path selection, the subtlest logic in the kernel, has no unit seam. The placeholder parameters pre-commit a design that nobody has validated.
- **Structural remedy:**
  1. Add a C++20 `concept DspStage` (`prepare(const ProcessSpec&)`, `reset()`, `process(const Params&, const MultichannelView&) noexcept`) and `static_assert` it for every stage. It is zero-cost and turns the comment into a type rule (Per.11 / T.10).
  2. Model the paths as `enum class KernelPath { Bypass, EqOnly, Full, Blend }` plus a pure `PathSelector::next(const PathInputs&) -> PathDecision` that the null test calls directly.
  3. **Remove Clarity and BRIR** from the RT chain and from `TargetState` until their epics. Keep one documented insertion point (`runColorationChain`), which is YAGNI, not speculative generality.
  4. Use the correlation-compensated law (or an equal-gain law when wet ≈ dry) for the Intensity blend.
  5. Read the snapshot once.

  JUCE's `dsp::ProcessorChain` is the reference for a compile-time chain with a uniform `prepare` / `reset` / `process` (opened, `juce_ProcessorChain.h:83-110`). A full `std::tuple` chain is **not** recommended, because the dry tap and the P0 crossfade are not a linear chain. The concept and the explicit path enum are the right amount of pattern.
- **Effort:** M. **Risk of the change:** med (golden master `GoldenMaster_StereoN2_v1` must hold, or be re-baselined deliberately for item 4). **Depends on:** DSP-07.

---

## LOCAL

### DSP-11 Flush-to-zero is switched on and never restored, so it leaks into threads the app does not own. LOCAL. Criteria: 5
- **Evidence:** `enableFlushToZero()` sets FPCR.FZ and never restores it (`FlushToZero.h:32-40`). It is called per render block on AVAudioEngine's IO thread (`AUAudioUnit.mm:100`, `SpatialRendererAU.mm:187`, `DSPKernel.cpp:149`), which other Apple nodes share, and in `DSPKernel::initialize` (`DSPKernel.cpp:60`), which runs on the Realizer queue, i.e. on a libdispatch **pool** thread that later runs unrelated work.
- **Root cause:** a free "set" function instead of a scoped guard.
- **Why it matters:** a hidden, process-wide change of floating-point semantics in code that is not ours. It is rarely audible, but hard to diagnose.
- **Structural remedy:** an RAII `ScopedFlushToZero` that saves FPCR and restores it in its destructor, used at render-block and worker entry. This is JUCE's `ScopedNoDenormals` (opened: `juce_FloatVectorOperations.h:224-242`, `.cpp:1544-1563`, mask `1 << 24`). Drop the call in `initialize()`. Also settle the doubles question (map fact #1: `LufsMeter.h:123-128` says FZ does not flush doubles, while `EQModule` relies on it) in the loudness panel.
- **Effort:** S. **Risk:** low.

### DSP-12 Dead and placeholder C++ accumulates, because the dead-code gate covers Swift only. LOCAL. Criteria: 1, 6
- **Evidence:** No production user for any of these:
  - `RtSwappableResource` (`include/RtSwappableResource.h`, test-only; it documents an intentional RT-side **leak** of an orphan, `:35-41, 100-106`, and its stated purpose, "Extracted from EQModule's … vDSP_biquad_Setup swap" (`:13-14`), vanished with the SVF rewrite);
  - `PerChannel` (comments only);
  - `ToneSource` (`PureModeSource.h:46-58`, test-only);
  - the dead C-ABI listed in DSP-02;
  - both AUs' `setRequestedSampleRate`, reachable only from dead `createAdaptiveAudioUnit`;
  - `AUParameterID` and a forward-declared `class AudioEngine` that does not exist (`AudioUnitBridge.h:11-23`);
  - `SpatialRenderKernel::configure` from the control plane (`configureSpatialChannels` has no caller);
  - the `LoudnessModule` telemetry getters.

  Periphery is Swift-only (map §6.2 stage 11). clang-tidy does not report unused `extern` functions.
- **Root cause:** there is no C/C++ dead-code check, and placeholders are kept "for later".
- **Why it matters:** reviewers and agents treat dead entry points as supported API (the AU stubs carry an "F6 stable ABI" justification). The leaky `RtSwappableResource` invites reuse for BRIR kernels, the exact case its own doc warns about.
- **Structural remedy:** delete the items above, and move `ToneSource` / `PerChannel` / `RtSwappableResource` into `Tests/` if a test needs them. Add a strict-gate stage that lists every function declared in the Swift-visible bridge headers and fails when one has no caller in `Sources/` (a grep-level check, like the existing source-coverage drift guard). When BRIR lands, design its resource hand-off then (a deferred-reclaim queue, not an RT leak).
- **Effort:** S. **Risk:** low.

### DSP-13 Domain constants are copied around, and the supported-rate domain differs from module to module. LOCAL. Criteria: 1, 4
- **Evidence:**
  - The 1 Hz rate tolerance appears four times: `HALOutputEngine.mm:48` (`kRateEpsilonHz`) and `:56` (`kFormatRateEpsilonHz`), `PureModePolicy.cpp` (`kRateEpsilonHz`), and `GaplessSource.cpp:70` (`kRateToleranceHz`).
  - "8 channels" appears twice: `kMaxChannels` (`AudioConstants.h:14`) and `kMaxSourceChannels` (`FileDecodeSource.cpp:97`, "matches the engine's 7.1/8 ceiling").
  - The one-pole α formula is written three times: `ParameterRamp::initialize`, `EQModule::onePoleAlpha`, `LimiterModule::onePoleCoeff`.
  - Rates: the EQ designs to 768 kHz, while the limiter look-ahead (`kMaxLimiterLookaheadFrames = 576`, `AudioConstants.h:31-33`) and the crossfeed ITD (`kMaxCrossfeedDelayFrames = 64`, clamped silently in `Realizer.mm:99-101`) cap at 192 kHz. Above that rate the look-ahead *time* and the ITD shrink without any error (map fact 3).
- **Root cause:** there is no single "format domain" definition.
- **Remedy:**
  - one `inline constexpr` per domain fact (`kRateMatchToleranceHz`, `kMaxChannels`);
  - `onePoleAlpha(tau, fs)` in `ParameterRamp.h`;
  - a `SupportedFormat` range checked once at `initialize` / `prepare`; above it the kernel either declines (it plays the identity, as the EQ already does) or sizes the rings from fs instead of compile-time caps.
- **Effort:** S. **Risk:** low. (Panel rows D32, D45.)

### DSP-14 `AUAudioUnit.mm` is a grab-bag, and the two AU subclasses duplicate their scaffolding. LOCAL. Criteria: 1, 3
- **Evidence:**
  - The effect-AU file also hosts device enumeration, the device UID / model-UID copy, the default-device getter and `selectOutputDeviceC`, which **sets the system default output** (`AUAudioUnit.mm:290-362`).
  - The `AdaptiveSoundAU` and `SpatialRendererAU` code is the same in registration (`dispatch_once` + `registerSubclass`), `setupBussesWithSampleRate`, the bus accessors, `allocateRenderResources` re-sync of rate and max frames, `internalRenderBlock` and `setRequestedSampleRate` (`AUAudioUnit.mm:116-211` vs `SpatialRendererAU.mm:210-319`).
- **Remedy:** move the device C-ABI to a `DeviceBridge.cpp` next to `CoreAudioDevice`. Add an Objective-C base class `ASInProcessEffectAU` (or a C++ helper) for buses, registration and the allocate re-sync, which both AUs subclass.
- **Effort:** S. **Risk:** low.

### DSP-15 The decode thread is under-specified for hi-res multichannel: the ring holds a fixed number of floats, the thread polls, and it runs at default QoS with no name. LOCAL. Criteria: 5, 6
- **Evidence:**
  - The ring is `1 << 18` **floats** (`FileDecodeSource.cpp:89-91`): 1.4 s at 48 kHz stereo, but **0.17 s at 192 kHz / 8 ch**.
  - When full, the producer naps 2 ms (`:106-107, 1124-1136`).
  - The thread is a plain `std::thread` with no QoS and no name (`:1094`).
  - A seek respawns the thread (DSP-06).
  - **State of the art, SFBAudioEngine:** its ring is sized in **frames**, 16,384 (`AudioPlayer.mm:35-36`), and its decoding thread sets `QOS_CLASS_USER_INITIATED` and a name (`:1103-1104`).
- **Remedy:**
  - size the ring by time (frames × channels for N seconds at the file's rate);
  - set the thread name and QoS (`pthread_set_qos_class_self_np`), or join the device's `os_workgroup` for decode;
  - wake the producer on consumption instead of on a timer when the ring has been full.
- **Effort:** S. **Risk:** low.

### DSP-16 Vestigial shapes and stale contracts in the primitives. LOCAL. Criteria: 1
- **Evidence:**
  - `DoubleBufferSnapshot` is a triple buffer (`DoubleBufferSnapshot.h:103-105`).
  - `tryCopySnapshot` "ALWAYS returns true", and the `bool` is kept "only for API compatibility" (`:76-77, 171-197`).
  - `HALOutputEngine::achievedState()` is documented as a "lock-free snapshot" but copies a plain struct (`HALOutputEngine.h:78`; it is safe only because every caller is on `engineQueue`).
  - `PureModeBridge.h:14` names `PureModeBridge.mm` (the file is `.cpp`).
  - `LoudnessModule.h:5, 73` gives a wrong chain order and says "defined in .mm".
  - `LimiterModule.h:161-163` refers to a `PerChannel` reset on a member that is a `std::array<std::vector>`.
- **Remedy:**
  - rename to `TripleBufferSnapshot` (or `RtSnapshot`), with `const T& acquire()` returning the consumer-owned slot (no copy, no `bool`);
  - state `achievedState()`'s threading contract in its type (engine-queue-only) or make it atomic;
  - fix the stale comments in the docs pass.
- **Effort:** S. **Risk:** low.

### DSP-17 Error handling inside AudioDSP mixes "abort on OOM" with defensive per-block fallbacks, and the stance is never stated once. LOCAL. Criteria: 6
- **Evidence:**
  - `noexcept` helpers allocate `std::vector` (`HALOutputEngine.mm:147-170, 199-235`); under `-fno-exceptions` an out-of-memory error there aborts.
  - The thread-spawn stance is spelled out once (`FileDecodeSource.cpp:1090-1093`) but not as a module rule.
  - Meanwhile the RT paths hide contract breaches as silence: the channel mismatch (DSP-03), an unsupported format (DSP-04), `frames > maxFrames_` (`SpatialRenderKernel.cpp`, "silently skip"; `DSPKernel.cpp:214` `assert` only in debug).
- **Remedy:** one documented E.25–E.27 policy for AudioDSP:
  - out-of-memory and thread exhaustion fail fast (E.26);
  - contract violations are refused **at configure time** with a typed error (DSP-02 / DSP-04);
  - RT guards stay as the last line, but count their hits (an atomic counter in diagnostics), so that a silent fallback is observable in the signal-path UI or logs.
- **Effort:** S. **Risk:** low.

---

## What is GOOD (keep, and copy elsewhere)
- **`DoubleBufferSnapshot` (triple buffer):** proven in the comments, carried by named atomics with both exchanges `acq_rel`, no standalone fence, TSan-modelable, and gated by two race tests. A model for any RT parameter hand-off.
- **The Realizer as an active object:** latest-wins coalescing slots, at most one queued drain, re-allocation serialised by `dispatch_sync`, weak-posted callbacks, and one publish site (`publishCanonical`). It is the right control-plane owner. DSP-07 asks only that it own *everything*.
- **The "facts → pure policy" split:** `DeviceListPolicy` and `PureModePolicy` keep the HAL I/O at the edge and the decision in testable pure code. Use the same pattern for format negotiation (DSP-04) and device state (DSP-05).
- **The `DecodeBackend` strategy:** Apple first, FFmpeg as fallback behind a baked major-version ABI guard, with a `decltype` function table resolved once. This is the strategy pattern done right; DSP-01 wants it used by *both* paths.
- **The `GaplessSource` seam:** an exchange-based single claim against `clearNext`, retire-to-off-RT reaping, a sample-accurate straddle, and observability counters made specifically for a conformance test.
- **`PureModeSession` member order:** the referrer is destroyed before the referent, so teardown order is structural, not conventional.
- **`EQModule`:** a compile-time-specialised SVF cascade (`runBandPairs<Pairs, Ramping>`), per-band glide, rejection of bad snapshots, and a bit-exact identity bypass.
- **RT hygiene overall:** no allocation, lock or syscall on the render paths I read. `FiniteSamples` scrubs once at the boundary, with per-stage guards behind it. `SpscRing::tryPushAll` writes whole frames all-or-nothing. `AsLog` uses `consteval` format strings safe under `-fno-exceptions`. RT-allocation soak tests exist.

## Duplicated capability (for the duplication pass)
1. **Whole transport stacks**, Pure C++ vs Enhanced Swift: decode, seek, gapless, playhead, format coverage (DSP-01).
2. **RT → worker analysis tap**, ×2 (`LoudnessModule`, `CausalLoudnessTap`), with two layout-weight hand-off mechanisms (DSP-09).
3. **Four loudness measurements of the same programme:** the normaliser `LufsMeter` (post-colouration), the causal-tap profiler (kernel input), the UI `LoudnessMeterBridge` (mixer tap) and the TrackLoudnessKit second decode.
4. **Two crossfade laws in `DSPKernel`:** equal-power for Intensity and correlation-compensated for P0 (DSP-10).
5. **HAL property helpers**, ×2: `firstOutputStream`, nominal-rate get / set (DSP-05); plus the Swift HAL code in `+MasterGain` / `+OutputDeviceMonitor`.
6. **The two AU subclasses' scaffolding** (DSP-14).
7. **The one-pole α formula ×3, the 1 Hz rate tolerance ×4, the 8-channel cap ×2** (DSP-13).
8. **Two C-ABI handle conventions** (`void*` and typed opaque structs) (DSP-02).
9. **True-peak history management ×2:** the limiter (ring-indexed) and the meter bridge (shift register) around the shared `TruePeakKernel`. Minor.

## Algorithms that need a correctness panel (map row IDs)
- **D50**, the Intensity equal-power blend on correlated wet ≈ dry (+3 dB at r = 0.5 while the stubs pass through); compare with D52.
- **D46**, N→M channel discard (DSP-08).
- **D71 / N98**, the policy ignores the file's channels (DSP-03).
- **D74 / D75 / D76**, native-format conversion and the render clamp: packed-24, non-interleaved, slice size (DSP-04).
- **D77**, the rate-change poll vs the listener (DSP-05).
- **D63 / N100**, RenderGate progress (DSP-06). The probe numbers are above.
- **D70**, lapping in the parity buffer (DSP-07).
- **D20**, normaliser state reset on re-allocation (DSP-07); the slew law is still untested (map).
- **D32 / D45**, 192 kHz caps vs the 768 kHz design domain (DSP-13).
- **D17 / LufsMeter**, whether FPCR.FZ flushes doubles (map fact 1).
- **D79 / D43**, seek rounding: `llround` vs truncation (map fact 5).

## Open questions for the founder (recommendation first)
1. **Pure with a mono file, or a channel-count mismatch.**
   - **(A) Recommended:** decline Pure and play Enhanced, with a reason shown, now (S).
   - (B) Add a bit-perfect AUHAL channel map later (M).
   - Today the file plays silence.
2. **5.1 / 7.1 on stereo outputs until S18.**
   - **(A) Recommended:** a standard ITU-R BS.775 downmix in the spatial stage.
   - (B) Keep the current behaviour, which drops centre and surrounds.
3. **One source pipeline for both paths (DSP-01).**
   - **(A) Recommended:** schedule it as an R2 foundation item before the adaptive features, which would otherwise be built twice.
   - (B) Keep two engines and accept the doubled cost.
4. **Placeholders** (Clarity, BRIR, `RtSwappableResource`, dead C-ABI).
   - **(A) Recommended:** delete them now and design each when its epic starts.
   - (B) Keep them as scaffolding.
5. **FFmpeg-only formats (Opus / Ogg) in Enhanced.**
   - **(A) Recommended:** solved by DSP-01; until then, hide or mark such files as "Pure only".
   - (B) Leave them as they are: they are scanned into the library but fail on the default path.
6. **Normaliser memory across device changes.**
   - **(A) Recommended:** keep the measured loudness across re-allocation (DSP-07).
   - (B) Reset on every engine restart, as today.
