# Phase B — Bit-Perfect "Pure Mode" + Enhanced-path resampling (status & learnings)

Status: **✅ SHIPPED — historical record (Phase B, shipped & merged).** **Phase B effectively complete** (2026-06-18) — all code on `feat/sprint-5-eq-wiring`,
pending only the founder's on-hardware smoke of the integer bit-perfect path (a **USB DAC** or a
48 kHz source — see "HDMI reality" below). Authoritative plan: `~/.claude/plans/functional-floating-bonbon.md`. The authoritative forward sprint schedule is now [sprint-plan.md](sprint-plan.md).

This phase came out of the deep pipeline review whose headline finding was: **`AVAudioEngine`
cannot be bit-perfect** (fixed 48 kHz Float32 graph, hidden SRC, no exclusive/hog mode, no
per-track rate switch). So we built a second, HAL-direct output path alongside the existing one,
plus the correctness/UX work around it.

---

## What we built

### Two mutually-exclusive output paths
- **Enhanced** = the existing `AVAudioEngine` two-AU graph (player → effects AU → spatial AU →
  mixer → output) at 48 kHz Float32. Carries all DSP/EQ/loudness/spatial. This is the **default**
  and the path used whenever Pure isn't applicable.
- **Pure** = `HALOutputEngine` drives `kAudioUnitSubType_HALOutput` directly, bypassing
  `AVAudioEngine`: per-track device nominal-rate match, native-format render, DSP bypassed →
  bit-exact. Selected when `pureModeEnabled ∧ deviceCapable` (DSP-bypassed by construction, so it's
  mutually exclusive with EQ). Falls back to Enhanced, never hard-fails.

### Components (commits on `feat/sprint-5-eq-wiring`)
- **B1 policy** (`DeviceCapability` / `evaluatePureMode`) — CoreAudio-free, unit-tested:
  FullBitPerfect (integer @ exact rate) / RateMatchedFloat (float @ exact rate) / FallbackEnhanced
  (lossy-wireless / virtual / rate-unsupported).
- **B2a `HALOutputEngine`** — AUHAL, RT-safe pull callback, hog + per-track rate + native format,
  safe restore on teardown. `PureModeFormat.convertFloatToNative` (scale 2^(N−1) + clamp; bit-exact
  16/24).
- **B2b `FileDecodeSource`** — off-thread decode → lock-free `SpscRing<float>` → RT `pullFloat`, at
  the file's NATIVE rate (no SRC). Runtime **FFmpeg-or-Apple** decoder (dlopen, baked major-version
  guard; Apple ExtAudioFile fallback). **Sample-accurate `seek`** (both backends; FFmpeg via
  seek-backward + decode-and-discard).
- **B3 C-ABI `PureModeBridge`** + Swift wiring (`AudioEngineBridge+PureMode*.swift`): path
  selection, transport routing, capability/eval/engine lifecycle, achieved-state, device monitoring.
- **B4 Enhanced resampler** (`AudioEngineBridge+EnhancedResampler.swift`) — replaced
  `AVAudioEngine`'s hidden default SRC with an explicit `AVAudioConverter` at `quality = .max`
  (streamed `scheduleBuffer`, generation-token cancellation, seek-restart). **Engaged only for
  rate-mismatched files**; 48 kHz files keep the byte-identical `scheduleFile` passthrough.
- **A2 UI** — a transport scrubber above the play buttons (drag → seek), reliable `duration`
  (computed from `AVAudioFile`), and a live **signal-path badge** (Pure/Enhanced · rate · bits ·
  decoder). Settings shows a compact signal-path card.
- **`[UX]` interaction logging** (`logUX`) — every user action + system outcome, one line each (for
  the run-and-screenshot debugging loop).
- **B5 verification** — `RoundTrip_BitExact_16/24bit` (decode → convert → byte-identical, both
  backends) in the C++ harness; **`swift run SRCQualityMeasure`** characterizes the B4 converter.

---

## Key learnings (the important part)

1. **`AVAudioEngine` is not a bit-perfect transport.** Fixed 48 kHz Float32, undocumented hidden
   SRC, no exclusive mode. Bit-perfect requires driving the **CoreAudio HAL** directly. (This is why
   Roon/Audirvana bypass `AVAudioEngine`, and why Apple Music isn't bit-perfect on macOS.)

2. **Hog (exclusive) mode is required to set an INTEGER device format.** In shared mode the HAL
   refuses `kAudioStreamPropertyPhysicalFormat`/output-format changes. So: keep hog for the integer
   **FullBitPerfect** path (USB/HDMI DACs, where the DAC/TV owns volume); run **shared/no-hog** for
   **RateMatchedFloat** (built-in/Bluetooth, where the macOS system volume must keep working). A
   blanket no-hog (our first volume fix) silently broke the integer path.

3. **macOS locks HDMI audio to 48 kHz on Apple Silicon** (44.1 + hi-res blocked by design). So
   **bit-perfect over HDMI is impossible for 44.1 kHz content** — macOS itself resamples 44.1→48 for
   HDMI. A soundbar (e.g. Samsung HW-Q6T) over HDMI is a 48 kHz PCM sink; it is *not* a bit-perfect
   target. **True bit-perfect requires a USB DAC** (native 44.1/88.2/176.4 + integer formats). Our
   engine now correctly **declines Pure when it can't reach the file's rate** (rate-match gate →
   Enhanced resamples at 48 kHz, honestly labelled), instead of rendering wrong-speed.

4. **Set the DEVICE's physical format, don't force the AU output scope.** The right way to make the
   wire integer: enumerate the stream's *advertised* `AvailablePhysicalFormats`, set
   `kAudioStreamPropertyPhysicalFormat` on the device stream, then match the AU **input** scope to
   the result. Forcing a constructed ASBD on the AU output scope is rejected by the device.

5. **Apple's `AVAudioConverter(.max)` is measurably excellent — no soxr needed.** `SRCQualityMeasure`
   (Blackman-Harris FFT) measured the B4 converter at **imaging ≤ −83.7 dBFS and aliasing ≤ −108.7
   dBFS** (vs the −60 / −80 bars), both 44.1↔48 directions. This validated choosing Apple-native over
   adding the soxr dependency.

6. **44.1 vs 48 kHz is not a quality ranking — matching the source rate is.** Both exceed human
   hearing (Nyquist ≈ 22.05 / 24 kHz; music is band-limited to ~20 kHz). The fidelity win is
   **avoiding unnecessary resampling** (play the source at its native rate), not the number itself.
   A 44.1→48 resample through a good converter (ours) is audibly transparent. Higher rates
   (96/192) give no audible playback benefit. See `docs/product/audiophile_dsp_apple_silicon_report.md`.

7. **Device-selection model: app-selected device is authoritative.** Picking a device in the app
   sets the macOS default output, so both paths target it. On the active device disappearing,
   playback **pauses** (no surprise auto-jump).

---

## Verification

- C++ harness **82/0** (83 registered, 1 pending; golden master `0xE7267654BA01D315` unchanged), incl. the round-trip bit-exact
  + sample-accurate-seek tests; runnable `--parallel`. Fixtures live in `<repo>/test-data/` (not
  `/tmp`).
- `swift run SRCQualityMeasure` — re-runnable SRC characterization (see learning #5).
- `swift build` links; strict clang-tidy + swiftlint gates green.
- **Founder-verified by ear:** Pure on float devices (built-in/BT), Enhanced 44.1→48 resample, seek
  on both paths, device handling, volume.

## Open items
- **Founder hardware smoke (Phase-B sign-off):** a **USB DAC** (or a 48 kHz source) to exercise the
  true `FullBitPerfect` integer path end-to-end (HDMI can't, per learning #3).
- **Known bug:** Enhanced is *intermittently silent on a device switched-to mid-session* (an
  `AVAudioEngine` device-rebind race). To fix next.
- **Phase C:** limiter headroom-on-DSP-only; libebur128 loudness oracle; QA gaps (EQ 31-band sweep,
  THD+N, ISP-detector); `AudioEngineBridge` cross-thread property-access hardening; split the now-
  large `AudioEngineBridge.swift`.

## Key commits (`feat/sprint-5-eq-wiring`)
`0f6897d` B3 C++ foundation · `58070c7` B3 Swift wiring · `9d164af` B4 resampler · `79c92b5` B5 tests +
`SRCQualityMeasure` + test-data · `94b263c` no-hog + app-selected + pause-on-disconnect · `deb764d`
keep hog for FullBitPerfect · `3a59a4c` set device physical format + rate-match gate + diagnostics ·
A2 `16e4076` (+ `20baaff` scrubber fix) · `[UX]` logging `93c89a6`/`866808d`.
