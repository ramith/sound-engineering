# Panel P3 (BREAKER): signal path, gapless seams, Pure output, real-time infrastructure

Repo `main` @ a206107, built and run in my own worktree (`.claude/worktrees/panel-p3-breaker`). Every harness is offline: C++ links the REAL `Sources/AudioDSP` files; Swift uses AVAudioEngine in manual-rendering mode or a bare `AVAudioConverter`. No device was opened and nothing was played. Harnesses and outputs are in `scratchpad/council/exp-p3/` (`cpp/h1..h6`, `swift/enhanced.swift`, `swift/srcband*.swift`, `py/*.py`).

I formed my view first and read the earlier evidence afterwards (`docs/architecture/evidence/main-thread-stall-2026-10/rev-sota.md` M2/M5). Where I agree or disagree with it is in §3.

## 1. Verdict table

27 distinct rows. N100 is the same algorithm as D63, and N101 is the same as D82.

| Row | Algorithm | Verdict | Evidence (mine) | Missing proof |
|---|---|---|---|---|
| D37 | Enhanced streaming resampler (chain) | **DEFECT** SIGNIFICANT | A5: a seek to the end hangs. The refused seek has already bumped the generations and set the base (silent, no EOF, the position reads 9.03 s on a 3.02 s track). 93 % of `seek(to: duration)` calls are refused. Steady-state chunked streaming is transparent: the error against an analytic sine is −132.5 dB. | An engine-level manual-rendering test of the chain, and a seek-to-end test |
| D38 | SRC quality (algorithm choice + `SRCQualityMeasure`) | **DEFECT** SIGNIFICANT | Normal@.max measures −0.48 dB at 19 kHz, **−8.25 dB at 20 kHz** and −38 dB at 21 kHz (44.1→48). 96→48 aliases a 24.5 kHz tone at −56 dB. Mastering is flat to 21 kHz (23 kHz at hi-res), aliases below −160 dB, and costs 0.9–3.5 % of one core. The tool prints "tone −7.23 dBFS @ 20 kHz" and still says PASS: it has no passband criterion. | A passband-flatness criterion in the oracle, and the oracle in `make gate` |
| D39 | Enhanced gapless roll | **DEFECT** STRUCTURAL | A1: the 48 kHz seams wait for `.dataPlayedBack`, so a gap is inevitable by Apple's own definition. A3: resampler→resampler seams make a click of −18 to −26 dB re the signal, against −132 dB for one continuous conversion. A4: a change in channel count across a seam drops R, drops C/LFE/surrounds, or goes silent. | A real-code seam test. Today only mock VM tests exist. |
| D40 | Enhanced seam position re-base | **DEFECT** SIGNIFICANT | A2: on the resampler path the re-base and track B's loudness switch land **24–177 ms early** (bounded by one 8192-frame chunk + flush, about 190 ms at 44.1 kHz). The N-2 fallback is wrong whenever base ≠ 0. | A frame-counted seam test |
| D41 | Pure `GaplessSource` seam + arm contract | **DEFECT** SIGNIFICANT | The seam itself is sample-accurate (real tests, and my H3). **Lead confirmed (H3a):** `armNext(C)` while B is armed returns false, the bridge returns `kNextTrackError`, and **B plays after A while the app names C**. Calling `clearNext()` and then `armNext(C)` plays C (verified). | A re-arm test |
| D42 | Same-format seam predicate | **QUESTIONABLE** | The bit-depth and float terms do nothing technically (the decoder always gives float32 and the device format is fixed per session). They only force reconfigure gaps. Compressed sources report 0 bits. | — |
| D43 | Pure position + seek re-base | **CORRECT-UNPROVEN** | `llround` matches the decoder target (FileDecodeSource.cpp:988). The seam re-zero is tested with real code. | `pureModeEngineSeek` (hold → seek → re-base → release) is untested; it needs a fake engine |
| D61 | Triple-buffer snapshot | **PROVEN-CORRECT** | The repo's TSan tests pass. My H5 under TSan and at 5×10⁷ reads: 0 torn reads and 0 backward reads. An exhaustive interleaving model (py/triple_model.py): 0 violations. | — (single-producer / single-consumer (SPSC) is enforced by convention only, see §2) |
| D62 | `SpscRing` | **CORRECT-UNPROVEN** | My H5: 2×10⁸ elements and 195 k wrap-arounds, mixed `tryPushBlock`/`tryPushAll`, 0 sequence breaks under TSan. The indices are masked, so they cannot overflow. | There is no direct in-repo test. Adopt H5. |
| D63 / N100 | `RenderGate` | **DEFECT** LOCAL | Safety holds (0 overlaps in every run). Liveness does not: `close()` can be starved. With a busy render, **386/400 closes time out at 100 ms**; under CPU contention 149/150 do. A prototype gate that announces the close: p99 89 µs, 0 timeouts. | A liveness test with a hot render |
| D64 | `RtSwappableResource` | **DEFECT** LOCAL (dead code) | H6: with a back-to-back publisher, **785,709 of 4,000,000 resources leaked**. The claim that "coalescing prevents it" is false. | — (delete it) |
| D65 | `MultichannelView` | **PROVEN-CORRECT** | Trivial. The test checks the clamp and out-of-range channels. | — |
| D66 | `PerChannel<T>` | **QUESTIONABLE** | Dead code (comments only). | — |
| D71 | Pure decision policy | **DEFECT** SIGNIFICANT | It ignores the channel count: **a mono file (or any file whose width differs from the device's) is silent forever in Pure, never ends, and the position stays at 0** (H3b, real `GaplessSource` + `FileDecodeSource`). It ignores bit depth: a 24-bit file on a 16-bit-only device is labelled `BitPerfectInteger` and truncated without dither. | Channel and bit-depth cases in the `PureMode_*` tests |
| D72 | Device capability | **CORRECT-UNPROVEN** | Needs the HAL. Continuous rate ranges are matched only at their endpoints, which is conservative. | Factor out the flag derivation as a pure function and test it |
| D73 | Policy C-ABI marshal | **QUESTIONABLE** | The marshal is tested. But the policy is evaluated twice with different inputs: Swift sends bits=32/float for every file, while the engine start sends the decoder's real depth. | — |
| D74 | Float → native PCM | **DEFECT** LOCAL | **Bit-exact, proven exhaustively** (H1): all 2¹⁶ and 2²⁴ codes, Apple and FFmpeg decoders, into 16, 24-in-32 (high and low) and 32-bit words: 0 mismatches. Defects: 24-bit **3-byte packed** writes 4-byte words (ASan heap overflow, against its own "unsupported → silence" contract). NaN is undefined behaviour (UBSan). +Inf becomes full scale. Requantising 24→16 truncates toward zero (H3 is +12 dB against round-to-nearest, with no dither). | The exhaustive loop costs under 1 s; adopt it |
| D75 | HAL integer format selection | **QUESTIONABLE** | The integer physical format only reaches the render if the stream is non-mixable, and nothing sets `SupportsMixing=false`. The AU input format is copied from the output scope, which is the virtual (float) format. So "FullBitPerfect" in practice relies on the HAL's float→int conversion. | An on-device format log |
| D76 | HAL render callback | **DEFECT** SIGNIFICANT | It pulls at the device's channel count (the D71 silence). It does not scrub NaN/Inf: a float file with Inf plays at **full scale** (H3c), which is a hearing-safety gap that the Enhanced path closes (DSPKernel.cpp:158-166). The write clamp uses ⌈bits/8⌉ instead of `mBytesPerFrame`. Non-interleaved formats are not handled. | — |
| D77 | Nominal-rate change + poll | **CORRECT-UNPROVEN** | Needs the HAL. Apple's pattern is a property listener. | — |
| D78 | File decode source | **PROVEN-CORRECT** | Real-fixture tests. My H1 decodes 16.7 M codes bit-exactly through both backends. The partial-frame carry is exercised constantly because the ring's usable capacity, 2¹⁸−1, is odd. | — |
| D79 | Sample-accurate decoder seek | **PROVEN-CORRECT** | Tests, plus my h3b (`seek(19.9999)` → frame 959995 exactly). Notes in §2. | The failure-path semantics |
| D80 | Pure test tone | **QUESTIONABLE** | Correct (a wrapped double accumulator) but dead: it has no production users. | — |
| D81 | Enhanced reference tone | **DEFECT** LOCAL | The Float angle never wraps, so the error grows from −90 dB to **−51 dB re the tone** by the end of the 5 s buffer. | — |
| D82 / N101 | Master Gain law | **PROVEN-CORRECT** | MASTER-GAIN-01..06 use independent spec values (10^(−20/20) = 0.1, −6.0206 dB = 0.5, NaN → silent). | — |
| D83 | Enhanced master gain applied | **CORRECT-UNPROVEN** | A6: `player.volume` applies through an intermediate effect (0.2506 measured, 0.2506 expected) and the change is ramped (no zipper noise). | Adopt A6 as an engine test |
| D84 | Pure device volume | **QUESTIONABLE** | "Silent" (−∞) sets the device to its **minimum dB**, which is not silence on most devices. Devices with per-channel volume only read as fixed. | — |

**Counts:** PROVEN-CORRECT 5 · CORRECT-UNPROVEN 5 · DEFECT 11 · QUESTIONABLE 6.

## 2. Details: DEFECT and QUESTIONABLE rows

### D37: The Enhanced resampler hangs on a seek to the end (SIGNIFICANT)
- **Evidence.**
  - `AudioEngineBridge+PureMode.swift:218` sets the position base to the target **before** the seek runs.
  - `+EnhancedResampler.swift:193-202` bumps `resampleGeneration` **and** `passthroughGeneration`, and only then refuses with `frame < totalFrames`. There is no `player.stop()` and no restart.
  - The live chain abandons, because every `.dataConsumed` completion now fails `isCurrent`. EOF never fires, because `fireResamplerEOFOrEnd` only runs under a current generation. The player plays silence forever, and the position is `target + oldSampleTime/rate`.
  - **How often it happens:** the VM sends `seconds == duration` (`NowPlayingBar.swift:257,333`) with `duration = length/rate` (`AudioViewModel+Playback.swift:93-95`). `AVAudioFramePosition(seconds*rate)` equals `length` for **92.9–93.5 % of track lengths** at every common rate (py/seek_end.py), so the seek is refused.
  - **Replica:** A5: refused, 5 s later no EOF, `isPlaying = yes`, silent, position 9.03 s on a 3.02 s track.
  - On the 48 kHz passthrough path (`+PureMode.swift:329-331`) the same refusal leaves the old segment playing with a wrong position (base = target + elapsed).
  - The seek rounding differs between paths: Enhanced truncates; Pure uses `llround`. Truncation alone is benign: 1 sample off for 7 % of exact-frame targets. The root cause is that the guard treats "seek to end" as an error instead of EOF; Pure lands at the end and finishes (h3b).
- **Remedy:**
  - Clamp the target to `[0, length]`, and treat `length` as "end now" by scheduling nothing and firing the EOF path.
  - Bump the generations and set the base only after the seek is accepted.
  - Effort S, risk low.

### D38: The SRC algorithm and its oracle (SIGNIFICANT)
- **Evidence (`swift/srcband*.swift`).** A least-squares amplitude fit, so there is no FFT scalloping. The production 8192-frame chunked pull.
  - 44.1→48: Normal@.max gives 0.00 dB to 18 kHz, −0.48 dB @19k, −8.25 dB @20k, −38.2 dB @21k. Mastering is flat (±0.00 dB) through 21 kHz.
  - 96→48: Normal gives −0.61 dB @20k, −3.0 dB @21k, −8.9 dB @22k, and aliases a 24.5 kHz tone at −55.8 dB and 25 kHz at −81 dB. Mastering is flat to 23 kHz and aliases below −160 dB.
  - 192→48: Normal is already −2.3 dB at 20 kHz.
  - Cost of Mastering: 8.9 ms of CPU per second of stereo audio at 44.1→48, 17.7 ms at 96k and 35.5 ms at 192k, i.e. 0.9–3.5 % of one core on this machine.
  - The code's reason for avoiding Mastering ("offline/high-latency … would stall live playback", `+EnhancedResampler.swift:7-9, 80-82`) is **refuted** by srcchunks.swift. With the production chunking, Mastering's first chunk returns 8289 frames: it holds back 627 frames, about 13 ms, and flushes them at EOF. The totals are exact.
  - MinimumPhase is flat to 20 kHz and costs 0.4 ms/s, if pre-ringing matters (LD-13).
  - `SRCQualityMeasure` only judges imaging and aliasing. Its own run prints "tone −7.23 dBFS @ 20 kHz … [PASS]".
  - Its "tone −0.37 dBFS" at 1–10 kHz is Blackman-Harris scalloping (1000 Hz sits 1/3 bin off-centre), not SRC loss: my least-squares fit reads 0.00 dB.
- **Remedy:**
  - Set `sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering`, or MinimumPhase as a product choice.
  - Add a passband criterion to the oracle (e.g. ≤ 0.1 dB to 20 kHz) and run it in the gate.
  - Effort S, risk low. Re-run A3 after the change, because a longer filter means a longer seam transient until D39 is fixed.

### D39: The Enhanced gapless roll is timed by events, not by sample count (STRUCTURAL)
1. **Passthrough (48 kHz) seams leave a gap.**
   - `Playback.swift:210-223` and `GaplessRoll.swift:193-216` schedule B only inside A's `.dataPlayedBack` completion.
   - Apple's header (`AVAudioPlayerNode.h:45-49`) says `.dataPlayedBack` fires when "the buffer or file has finished playing … accounts for … (possibly significant) latency in the audio playback device".
   - So the player has already run dry for the whole output latency, plus the dispatch and up to one IO cycle, before B is even scheduled.
   - Offline, `.dataPlayedBack` never fires (A1). Using `.dataRendered` as a strict lower bound: a 128-frame gap paced, 640 frames free-running. Scheduling B behind A up front gives a **0-frame** gap (A1).
   - Passthrough→resampler seams take the same late trigger.
2. **Resampler→resampler seams click.**
   - Each track gets a fresh `AVAudioConverter` (`GaplessRoll.swift:248-257`). A's flush assumes zeros after A, and B's priming assumes zeros before B, so the cross terms are lost.
   - Against an analytic continuous sine, A3 measures, within ±300 frames of the seam: −17.9 dB re peak (50 Hz), −22.0 dB (1 kHz), −26.3 dB (10 kHz). Away from the seam the error is −132.5 dB. **One continuous conversion at the same spot: −132.5 dB.**
   - This is a click at every boundary of a continuous 44.1/88.2/96 kHz album (live, classical, concept) in Enhanced mode. 44.1 kHz CD rips are the most common source.
3. **Channel-count seams are unguarded (lead 2 confirmed).**
   - Neither handler checks width or reconfigures the graph. Only `playFile` → `configureGraphForSource` does.
   - A4 (no exception in any case):
     - a stereo file after a mono graph plays **channel 1 only (R dropped)**;
     - a 6-ch 48k file on a stereo graph plays **channels 1–2 only (C/LFE/surrounds dropped)**;
     - a 6-ch 44.1k file through the seam's converter is **silent** (`AVAudioConverter` channelMap `[-1,-1]` for a discrete layout).
   - The kernel's channel layout (BS.1770 weights) stays stale. Pure has an explicit predicate (D42); Enhanced has none.
- **Root cause.** The Enhanced path enqueues whole files or converted buffers into `AVAudioPlayerNode` and learns about the boundary from completion callbacks. Pure's `GaplessSource` counts samples on the render side. The Enhanced path has no single owner of the frame timeline.
- **Remedy (agrees with rev-sota M2 "long term").**
  - One app-owned source per path: an `AVAudioSourceNode`, or a ring pulled by the player, fed by a track queue through ONE converter stage that is kept across same-format seams.
  - Seams are counted in frames, as `GaplessSource` already does. Widths are checked against a predicate shared with Pure.
  - Effort L, risk medium.
  - Short-term patches: keep one converter across same-rate resampler seams (feed B into A's converter); schedule 48k B when A is a few seconds from its end; refuse a width-changing seam (treat it as a "reconfigure" advance, as Pure does).

### D40: The seam re-base lands early (SIGNIFICANT)
- **Evidence.**
  - A2 replicates the production chain: 8192-frame chunks, prime 3, `.dataConsumed`, and the EOF hook → prime B → `bumpTransitionCount`.
  - The hook ran **2495 / 1155 / 8519 frames before A's last sample** (52 / 24 / 177 ms) for three track lengths. The early amount is the unplayed remainder of A: the last data chunk plus the 52-frame flush tail.
  - `trackBecameAudible(nextURL, gaplessSeam: true)` (`Gapless.swift:186`, `TrackLoudness.swift:26-31`) switches the effects AU to B's loudness profile at that moment. **B's gain is applied to the last ≤ ~190 ms of A**, in the render domain, with no latency term. The position re-zeroes early by the same amount.
  - N-2 fallback (`Gapless.swift:196-201`): `base = −lastKnownPosition` re-zeroes only when the old base is 0. After a seek or resume (base = target) B reads `max(t − target, 0)`, so it stays at 0:00 for `target` seconds.
- **Remedy:** the frame-counted seam (D39). Or, inside the current design, record A's scheduled-frame total and re-base / switch loudness when the player's sampleTime passes it. Effort M.

### D41: Pure ignores a mid-song re-arm (SIGNIFICANT; lead confirmed)
- **Evidence.**
  - `GaplessSource::armNext` refuses while a track is armed (`GaplessSource.cpp:127-130`), and the bridge maps the refusal to `kNextTrackError` (`PureModeBridge.cpp:357-362`).
  - The VM re-arms without clearing first: `armOnDeck` → `setNextTrack(url)` → `setPureNextTrack` → arm (`Gapless.swift:94-133`). The callers are Shuffle/Repeat (`+Playlist.swift:159-166`), play-next/append (`+Queue.swift:123,184`) and removal (`+Playlist.swift:104-114`). `pendingNextIndex` moves to C.
  - **H3a (real code):** `armNext(B)=true`, `armNext(C)=false`; the track after A has B's fingerprint. Remedy check: `clearNext()` + `armNext(C)` → C plays.
- **Remedy:**
  - Make the bridge's arm "replace": `clearNext()` then `armNext()` on `engineQueue`. If the seam wins the race, the VM's existing "ended with pending → advance" path covers it.
  - Or return a distinct "busy" code and let the VM clear first.
  - Effort S.
  - Also note: a following track can't be armed until the retired one is reaped (H3e). So a middle track shorter than the poll-and-arm latency degrades to a reconfigure gap.

### D63 / N100: `RenderGate` can be starved (LOCAL)
- **The algorithm.**
  - `close()` can only succeed by catching the state at `Open`; it never stops a new `tryEnter`.
  - So the documented bound ("waiting only for a render already inside (bounded by one render pass)", `RenderGate.h:11-12`) holds only while the render has idle gaps the 50 µs poll can land in.
  - Safety is fine: Open→Rendering is a CAS, the leave store follows it, the close's acquire pairs with the render's release, and ABA is harmless because the states carry no history.
- **H4** (the real header; trials close at the production 100 ms):

  | Render load | Real gate (p50 / p99 / timeouts) | Announced-close gate |
  |---|---|---|
  | HAL-like, 100 µs per 2.67 ms | 0 / 1.7 ms / 0 | 0 / 0.18 ms / 0 |
  | Hot loop | 100 ms / 100 ms / **386 of 400** | 80 µs / 89 µs / 0 |
  | 28 CPU hogs, "heavy" load | **149 of 150** timeouts | — |
  | 28 CPU hogs, hot loop | **128 of 150** timeouts | 0 timeouts |

- **E2 input reconciled.** E2 saw at worst 123 ms on the real null test. That loop has more open time per iteration than mine. On a small TSan-slowed CI runner the open fraction shrinks, and the 1 s timeout trips. So the CI failure is this liveness gap showing, not purely a test artefact.
- **Production.** The HAL IO thread is time-constraint and has a ~1–5 % duty cycle, so the risk is low. A failed close refuses the Pure seek, and teardown proceeds anyway.
- **Remedy:** add a `Closing` state: control CAS Rendering→Closing; render `leave()` CAS Rendering→Open, else store Closed. It stays wait-free on the RT side; the prototype is in H4. Then the test can't flake. Effort S.

### D64: `RtSwappableResource` leaks (LOCAL, dead code)
- `publish()` runs `reclaim()` **before** its pending exchange. If the RT adopts the previous pending inside that window, the next adopt's `toRelease_.exchange` displaces an un-reclaimed resource, which leaks (`:105-106`).
- H6: 785,709 of 4,000,000 leaked with a fast publisher.
- It has no production users. **Delete it** (S), or reclaim after the exchange and use a 2-deep retire list.

### D71: The Pure policy ignores width and depth (SIGNIFICANT)
- **Width.**
  - `evaluatePureMode` (`PureModePolicy.cpp:85-140`) never reads `file.channels` or `file.bitsPerChannel`.
  - `HALOutputEngine` renders at the device width (`rfChannels_` = AU output-scope channels, `:772, :821, :845`).
  - `FileDecodeSource::pullFloat` returns 0 frames of silence on a width mismatch (`:1012-1016`), and `GaplessSource` holds, because the source is not exhausted.
  - H3b, real code: a mono file pulled at 2 channels gives 0 of 102,400 frames, peak 0.000, `ended()=0`, position 0, so it is **silent forever and never auto-advances**. The same happens to a stereo file on a 4/8-out interface or HDMI AVR, and to a 5.1 file on built-in speakers.
- **Depth.** A 24-bit file on a 16-bit-only integer device is labelled `BitPerfectInteger` while the converter truncates toward zero (D74). Also, Swift's viability check passes `processingFormat` bits, which are always 32/float (`+PureMode.swift:57-66`).
- **Remedy.** Fall back to Enhanced on a width mismatch, or open the AU input at the file's width with `kAudioOutputUnitProperty_ChannelMap`; mono → L/R duplication is still bit-exact per channel. Report "not bit-perfect" when device depth < source depth. Effort S–M.

### D74 / D76: Edges of the conversion and render (LOCAL / SIGNIFICANT)
- **3-byte packed 24-bit.**
  - `convertFloatToNative` takes `bits == 24` regardless of `isPacked` and writes 4-byte words (`PureModeFormat.cpp:250-253`).
  - With the HAL buffer sized at 3 bytes per sample, the render clamp `⌈24/8⌉·ch` (`HALOutputEngine.mm:866-874`) lets every frame through.
  - **ASan: heap-buffer-overflow** (h2_packed24). It is latent until a non-mixable integer virtual format reaches the AU (D75).
- **NaN.** `static_cast<int32_t>(NaN)` is undefined behaviour (UBSan, h2 `nan`).
- **+Inf.** `clampUnit` maps it to full scale (32767); a float device gets Inf/NaN via memcpy (H3c).
- The Enhanced kernel scrubs non-finite samples "on every path, the bit-perfect one included" (`DSPKernel.cpp:158-166`). The Pure HAL path doesn't.
- **Remedy.**
  - Scrub non-finite samples in `render()` before the conversion (`allFinite` is one vectorised reduction).
  - Treat packed-24 as unsupported → silence, or implement 3-byte stores.
  - Bound writes by `mBytesPerFrame`, and reject non-interleaved formats in `cacheRenderFormat`.
  - Effort S.

### D79 (note under PROVEN-CORRECT)
- `seek()` resets the ring and restarts decoding even when `seekToFrame` fails (`FileDecodeSource.cpp:984-1000`). A refused seek therefore **skips** the buffered audio (up to ~2.7 s stereo at 48k), and `pureModeEngineSeek` does not re-base. This contradicts `FileDecodeSource.h` ("playback still resumes from the prior position") and the bridge comment. This is from reading the code: I could not make a WAV seek fail to reproduce it.
- The target is not clamped. `llround` saturates at absurd targets, and the Apple backend then returns `ok` and renders 4096 frames of garbage (first sample −26624/32768) (h3b with `1e15`, `inf`). The UI can't reach this.

### D81: The reference tone loses precision (LOCAL)
- The error grows from −89.7 dB to −51.3 dB re the tone over the 5 s buffer (swift/reftone.swift).
- Remedy: wrap the phase, or generate it as `ToneSource` does (double accumulator, wrapped). Effort S.

### QUESTIONABLE rows, briefly
- **D42:** drop the bit-depth and float terms (they only cost gaps); keep rate and width.
- **D66 and D80:** dead code; delete them or give them a user.
- **D73:** one policy is evaluated with two different input sets (Swift viability vs the engine start). Make one call site.
- **D75:** decide what "FullBitPerfect" means without `SupportsMixing=false`. Log `AU output (post-set)` on a real DAC to see whether the integer branch is ever reached.
- **D84:** "Silent" should mute the device, or the knob should say "device minimum".

### The SPSC assumptions (lead 6)
- **Rings.** `SpscRing`'s producer and consumer are correct in production: decode thread → HAL render; render → loudness worker. A seek resets the ring while the decode thread is joined and the render is held behind the gate, and the gate's acquire/release supplies the ordering.
- **Snapshot.** The triple buffer has one production producer, the Realizer queue. But a second public producer exists: `publishState:` / C-ABI `publishTargetState` (`AUAudioUnit.mm:221-226, :416-421`). It is test-only today, and its own comment says the two planes are "unordered". `DSPKernel::initialize` is a second consumer on the Realizer queue (`Realizer.mm:345`), serialised with `process()` only by the AU allocate/render lifecycle. Both are kept by convention, not by type (criterion 1).
- **Counters.** Every frame counter in these rows is 64-bit or masked, so there is no 2³²/2⁶⁴ wrap hazard.
- **ABA.** Every structure uses `exchange`. The only CASes are `RenderGate`'s, which are state-only and ABA-harmless.

## 3. The other tracks' leads, and the earlier evidence

1. **The resampler re-zero lands early and B's gain lands on A's tail: CONFIRMED in kind, but the magnitude disagrees with rev-sota M2.**
   - I measure 24–177 ms, bounded by one chunk + the 52-frame flush tail (~190 ms at 44.1 kHz, ~85 ms at 96 kHz), not "2 buffers (~372 ms)".
   - The second queued buffer at EOF detection is the tiny flush tail, not a full chunk.
   - The "+L" (latency) applies to the heard-vs-render offset of every position. It does not apply to the loudness switch, which happens in the render domain.
   - **The 48 kHz gap: CONFIRMED** by Apple's header definition, plus an offline lower bound. I agree with M5 that offline `.dataPlayedBack` is invisible: it never fired in my runs.
2. **The channel-count seam is unguarded: CONFIRMED, quantified in A4.** There is no crash, but R is dropped, C/LFE/surrounds are dropped, or the output is silent.
3. **Seek rounding, and the base set before success: CONFIRMED.** Truncation by itself is harmless. Together with the `< length` guard it refuses 93 % of end-of-track seeks, which hangs the resampler path (D37).
4. **Pure bit-perfectness: PROVEN** for 16/24-bit integer sources, exhaustively and through both decoders. The exceptions are the packed-24 overflow, NaN/Inf, and the 24→16 truncation with no dither (D74/D71).
5. **`RenderGate`: safe but not starvation-free.** E2's no-repro is consistent with my numbers.
6. **The lock-free structures: sound** (D61/D62 proven by my harnesses). `RtSwappableResource` leaks.
7. **The Pure re-arm lead: CONFIRMED with real code** (D41).

## 4. Top missing proofs (in priority order)
1. A real-code Enhanced seam test in AVAudioEngine manual rendering: gap, click and early re-zero (my A1–A3 are ready to adapt).
2. A Pure re-arm test, and a Pure width-mismatch test.
3. A seek-to-end test on both Enhanced sub-paths.
4. A passband criterion for the SRC oracle, with the oracle in `make gate`.
5. A `RenderGate` liveness test with a hot render.
6. The exhaustive 2¹⁶/2²⁴ bit-exactness loop (under 1 s).
7. A direct `SpscRing` sequence test under `make tsan`.
