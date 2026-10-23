# P3a breaker: `fix/pure-safety` @ 672fc0a ("Pure Mode declines what it cannot play exactly")

**Verdict: SHIP.** I found no defect in scope. Every earlier reproduction (D71, D74, D76) is closed by the real code. The exhaustive bit-exactness still gives 0 mismatches, for more layouts than before. The ASan/UBSan runs are clean, and the new conversion code is safe to run on the real-time thread.

There are four notes; none blocks the release (§3).

**Setup.**
- Checked out in my own worktree (`.claude/worktrees/panel-p3-breaker`, detached at 672fc0a). I did not touch the owner's worktree.
- Harness: `scratchpad/council/exp-p3/cpp/h7_purefix.cpp`. It links the REAL `PureModeFormat.cpp`, `PureModePolicy.cpp`, `GaplessSource.cpp` and `FileDecodeSource.cpp`, and is built at `-O2` and with ASan+UBSan.
- Every check uses an independent reference encoder and spec of my own, not the code's.
- Offline only: no device was opened and no audio played.

## 1. The earlier reproductions, re-run
| Earlier finding | Before (7d7c2cd) | Now (672fc0a) |
|---|---|---|
| D71: mono file, 2-channel device | silent forever, never ends (H3b) | The policy gives `ChannelCountMismatch`, so the track plays Enhanced. The engine start re-checks the policy (`PureModeBridge.cpp`), and the HAL re-checks the stream it really pulls (`HALOutputEngine.mm` gate 4b). |
| D74: packed 3-byte 24-bit | heap-buffer-overflow (ASan) | Exact-size buffers at 1/2/6/8 channels, LE and BE: no ASan report. All 2²⁴ codes are exact. |
| D74: NaN cast | undefined behaviour (UBSan) | No UBSan report; NaN becomes 0 |
| D76: +Inf | full scale (32767) | 0 on every layout and endianness, including NaN payloads, signalling NaN and negative NaN |
| D76: write bound | ⌈bits/8⌉ | The buffer's own `mDataByteSize` and the format's real frame stride |

## 2. The attacks
1. **Exhaustive bit-exactness**, all 2¹⁶ and 2²⁴ codes through the new span API, into Int16, Int24Packed, Int24In32High, Int24In32Low and Int32, each little- and big-endian: **0 mismatches** in every combination.
2. **Real decoders (Apple and FFmpeg) → converter → packed-24 device:** every 16- and 24-bit code, 0 mismatches.
3. **Non-finite values, denormals, ±0, edges:**
   - 15 special values (qNaN, sNaN, NaN with payload, negative NaN, ±Inf, min and max denormals, ±0, ±1, just over 1, FLT_MAX), placed first, last or mid-buffer, in 6 layouts × 2 endiannesses, with FPCR.FZ both off and **on**. All match the reference.
   - Float32 LE: a block containing one NaN takes the per-sample path, and its finite samples stay **bit-identical**, including −0 (`80000000`) and denormals (`00000001`, `807fffff`), even with flush-to-zero set.
4. **Buffer bounds**, with exact-size heap buffers under ASan:
   - Destination sizes 0, 1, one frame −1, one frame, one frame +1, a partial last frame, an exact fit, larger than needed, and 4096 frames, × 5 layouts × 1/2/6/8 channels.
   - Every case converts the correct number of frames and zero-fills the tail. Source buffers that end mid-frame are cut to whole frames. A 0-channel format converts nothing.
   - **No ASan or UBSan report.**
5. **`fromAsbd` against my own spec** over 204,288 descriptions:
   - The grid: format ID; all 2⁷ combinations of the Float, BigEndian, SignedInteger, Packed, AlignedHigh, NonInterleaved and NonMixable flags; bits ∈ {0,8,16,20,24,32,64}; channels ∈ {0,1,2,3,6,8,24}; bytes per sample ∈ {0,1,2,3,4,8}, with the frame size skewed by −1, 0, +1.
   - Result: 648 accepted, **0 disagreements, and 0 accepted formats whose stride, channel count or endianness differs from the description**. Non-interleaved, unsigned, 8/20-bit, float64 and self-contradictory "packed" descriptions are all rejected.
6. **Format picker:** given a list containing non-interleaved, 20-in-24, 20-in-32, packed-24 non-interleaved, float and wrong-rate/wrong-width formats, it chose 24-in-32 aligned-high (the device's current flags). With only unwritable formats on offer it returns `nullopt`.
7. **Policy:**
   - mono→2, 2→4 and 6→2 go to Enhanced; 1→1, 2→2 and 8→8 stay Pure, with `targetChannels` = the file's.
   - An unknown physical width falls back to the virtual width.
   - An unknown width, or a file with 0 channels, goes to Enhanced.
8. **The gapless successor mid-album** (real `GaplessSource`, A = stereo 48 kHz 16-bit):
   - mono, 6-ch, 44.1 kHz and 24-bit successors are **refused** (`armNext = 0`). A then plays to a clean end (`ended = 1`, 0 transitions), and the VM's existing "advance with reconfigure" path takes the next track.
   - A compatible successor arms and plays (transitions = 1).
9. **Real-time safety:** `PureModeFormat.o` has only two external symbols, `_memcpy` and `_bzero`. There is no allocation, lock or logging on the IO path. The render change is span construction plus the conversion.
10. **Repo suite:** all 59 Pure/Convert/PureFormat/PureGapless/GaplessContract/RoundTrip/FileDecode/RenderGate null tests **pass under ASan+UBSan** in my worktree. The branch adds `Convert_BitExact_Exhaustive16And24`, which is an independent identity oracle, and the arm-refusal and channel-mismatch tests.
11. **"Reason shown" reuses the existing path, not a duplicate.** A decline sets `fellBackToEnhanced` (`AudioEngineBridge+Playback.swift:56-71`), and the existing notice renders it ("Pure Mode can't play this track on this device, so it's playing Enhanced.", `SignalPathStatus.swift:26-33`; "— Pure mode unavailable", `HeroBand.swift:242`). No new UI surface was added.

## 3. Notes (none blocking)
- **(a) The specific reason is only logged.** The UI shows the generic notice. "Channel count" appears only in the log: `NSLog … policy reason 5` in Swift, and the C++ log line. If the founder's "with the reason shown" meant the specific reason, it needs a reason field on `SignalPathInfo`; otherwise this is done.
- **(b) The hog/float rule (as P3b flagged; noted only).**
  - The policy sets `requiresHog = true` for RateMatchedFloat (`PureModePolicy.cpp:139`), and the tests pin that (e.g. `PureMode_BuiltInRateMatchedFloat`, `requiresHog=true`).
  - Production overrides it to `false` in `pureModeEngineStart`. So the tested value is never the one used.
- **(c) A late decline leaves the device's physical format changed (pre-existing).** Gate 4b runs after `applyBitPerfectFormat` may have set the device's physical stream format, and `teardown()` restores the rate and the hog but not the physical format. A late decline on a multi-stream device therefore leaves that format changed while Enhanced plays. This is harmless to the audio and the behaviour existed before.
- **(d) The stricter acceptance could change a device that worked before.** A device whose AU reports a self-contradictory description (e.g. "Packed" on 24-in-32) now declines Pure instead of guessing. One look at the founder's earlier HDMI `logASBD` output would confirm the HDMI device isn't one of them.
- **Out of scope, still open:** the Pure mid-song re-arm refusal (panel D41) is unchanged by this commit.
