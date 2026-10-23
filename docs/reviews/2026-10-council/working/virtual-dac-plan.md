# Virtual DAC plan: verifying Pure Mode without a USB DAC

- **Date:** 2026-10-14.
- **Base:** `docs/council-reconcile` @ c95e2c6. Pure code read at that commit.
- **Status:** research and plan only.
  - Nothing was installed, no `sudo` was run, `coreaudiod` was not restarted and no audio was played.
  - The only thing run on this Mac was a read-only device lister: `scratchpad/virtual-dac/probe/listfmt.c`. Its output is in `probe/listfmt-2026-10-14.txt`.
- **Scratch material** (all treated as untrusted, nothing built or run from it):
  - `scratchpad/virtual-dac/blackhole/`: BlackHole @ 561d934 (v0.7.1).
  - `libaspl/`: libASPL @ 633e0f7 (v3.1.2).
  - `apple-nullaudio/`: Apple's NullAudio sample.
  - `eqmac-src/` and `rocvad-src/`: excerpts.

---

## 0. Recommendation (short)

**Build our own small test driver, "AS Test DAC", on libASPL, and start today with a no-install tier on the real HDMI monitor and the built-in speakers.**

**Tier 0: today, no install, no admin.**
- A read-only HAL observer watches the device while the founder plays Pure on:
  - the HDMI monitor (a real integer device with a real Apple driver);
  - the MacBook speakers (float).
- Both are muted.
- It answers these on real Apple drivers:
  - C-100 (how many rate switches per pause/resume);
  - hog take and release;
  - rate and format restore;
  - whether Pure really renders float on an integer device (D75);
  - a real hot-unplug (pull the HDMI cable).
- It cannot read the bytes.

**Tier 1: one admin install.**
- "AS Test DAC" is an AudioServerPlugIn built on libASPL (MIT, C++17). It does four things.
- **It creates fake DACs on demand.** Each has the exact format list, rates and channel count of a real DAC, cloned from real DAC dumps. Each reports a **USB** transport, so Pure's policy treats it as a real DAC.
- **It captures the bytes** the HAL hands the "hardware" (`WriteMix`, the device's native format) and the float mix before conversion. These are streamed to a test harness over a localhost socket.
- **It logs every event:** client attach and IO start, nominal-rate and physical-format requests, config changes, device add and remove.
- **It has fault knobs:** a slow rate change, refused rates, a stalled stop, device removal mid-play, and a large IO buffer.
- A Python comparison tool checks each capture bit for bit against generated test signals with a known answer, and checks the event log for the expected switch counts.
- Everything plays into silent virtual devices, so nothing is ever heard.

**Why not BlackHole** (or any off-the-shelf loopback):
- Pure refuses it outright: it reports `kAudioDeviceTransportTypeVirtual`, which the policy turns into `FallbackEnhanced/VirtualDevice`.
- It is float-only, and its format list and transport type are hard-coded.
- Making it act like a USB DAC means forking 4,626 lines of GPL C. The same job takes about 1,000 lines on libASPL. Details are in §2.2.

---

## 1. What has to be proven, and where it lives in the code

| Claim / risk | Code | Test (§7) |
|---|---|---|
| The integer layouts are written bit-exactly: Int16, Int24Packed, Int24In32High and Low, Int32, Float32 | `PureModeFormat.cpp:166-208` (`sampleLayout`), `:322-364` (`convertFloatToNative`), `HALOutputEngine.mm:793-801` | T1 |
| The picker chooses the highest writable integer format at the rate and rejects the rest (R1) | `PureModeFormat.cpp:210-232, 304-320`; `HALOutputEngine.mm:601-625` | T1, T14 |
| Mono or channel mismatch, unsupported rate, or a virtual device fall back to Enhanced | `PureModePolicy.cpp:105-135`; gate 4b `HALOutputEngine.mm:421-434`; `PureModeBridge.cpp:206-215` | T2 |
| A rate change that didn't take declines Pure (HDMI "lock") | gate 2b `HALOutputEngine.mm:385-404` | T0.5, T2 |
| **C-100**: pause = `stopAudio` → `tearDownPure` → the original rate is restored and hog released; resume = a fresh start that switches rate again | `AudioViewModel+Transport.swift:45-53` → `AudioViewModel+Lifecycle.swift:158-167` → `AudioEngineBridge+Playback.swift:245-255` → `HALOutputEngine.mm:875-888` | T0.1, T3 |
| **C-31 / DSP-05**: the physical format is never restored; set-then-read with no listener; rate and format set in two steps | `HALOutputEngine.mm:369-383, 618-638, 875-888` | T3, T9 |
| Hog: taken for FullBitPerfect, not for RateMatchedFloat; toggle semantics | `HALOutputEngine.mm:287-317, 353-367`; `PureModeBridge.cpp:217-230`; `AudioHardware.h:932-944` | T0.2, T4 |
| Gapless at the same rate is sample-accurate; a different rate or bit depth does not seam | `GaplessSource.cpp:83-92` | T5 |
| **D41**: newest request wins, "heard == shown" at the seam on Pure | `PureModeBridge.cpp:381-433`; `d41-design.md` §2 | T6 |
| Device loss mid-play: pause, no freeze, nothing leaked | `AudioEngineBridge+OutputDeviceMonitor.swift:207-230` | T0.3, T7 |
| **D75**: does "FullBitPerfect" really render integers, or float32 that the driver converts? | `HALOutputEngine.mm:627-660` (the AU input is copied from the output scope) | T0.4, T1 (mode B) |
| **DSP-04**: a slice larger than 4,096 frames renders silence | `HALOutputEngine.mm:52, 719, 758-765` | T11 |

---

## 2. Research findings

### 2.1 This Mac's real devices: read-only dump, 2026-10-14

From `probe/listfmt-2026-10-14.txt` (M4 Pro, macOS 26.6 25G72):

**HDMI, ASUS VA279HG** (`transport='hdmi'`):
- Nominal rates are 32 000, 44 100 and 48 000.
- Available physical formats, each at 32 k, 44.1 k and 48 k, all mixable:
  - 24-bit in 8 bytes/frame, signed int, no Packed or AlignedHigh flag. That is **24-in-32 aligned low**, i.e. `Int24In32Low`.
  - 20-bit in 8 bytes/frame (20-in-32), which `fromAsbd` rejects.
  - 16-bit packed.
- **Available virtual formats: float32 only.** The current physical format is 24-in-32-low at 48 k.

**MacBook Pro Speakers** (`'bltn'`): float32 physical and virtual only, at 44.1 / 48 / 88.2 / 96 kHz.

Third-party HAL plug-ins already load on this Mac (all read-only checks):
- `MSTeamsAudioDevice.driver`, which shows up as a device;
- `ParrotAudioPlugin.driver`;
- Rogue Amoeba's `ACE.driver` 11.9.2.

What this tells us:
1. **D75 is confirmed on real data.**
   - Pure's FullBitPerfect path copies the AU input from the AU output scope (`HALOutputEngine.mm:627-660`). On this real integer device that scope can only be **float32**, because only float virtual formats exist.
   - So on HDMI, and very likely on AppleUSBAudio DACs, Pure renders float32 and Apple's driver converts it to integers.
   - The integer converters in `PureModeFormat.cpp` are **not reached** on such devices. The virtual DAC must mimic this ("mode B", §5), and must *also* reach the integer converters ("mode A").
2. **`Int24In32Low` is a real, current layout** (this HDMI). It is not just a theoretical case.
3. The engine comment "macOS LOCKS HDMI output to 48 kHz" (`HALOutputEngine.mm:387`) is **not true of this monitor**: it advertises 44.1 kHz. Whether the change *takes* is test T0.5.
4. The built-in speakers switch between 44.1 and 96 kHz, so C-100 can be counted today on real hardware (T0.1).

### 2.2 BlackHole (ExistentialAudio), v0.7.1 @ 561d934

- **Licence:** GPL-3.0 (`LICENSE:3`). Official binaries are © Existential Audio.
- **Formats:** float32 only.
  - `kBits_Per_Channel 32` is fixed (`BlackHole.c:334-336`).
  - Every current and available format is `kAudioFormatFlagIsFloat | NativeEndian | Packed` (`:3180, :3211`).
  - The physical-format setter rejects anything else (`:3294-3300`).
  - The ring buffer and IO are `Float32` / vDSP (`:4344, :4554-4605`).
  - **No integer formats.**
- **Rates:** 8 k, 16 k, 24 k, 44.1 k, 48 k, 88.2 k, 96 k, 176.4 k, 192 k, 352.8 k, 384 k, 705.6 k and 768 k (`:326-327`). They are configurable at build time through `kSampleRates`.
- **Channels:** 2 by default (`:239-240`). The project ships 2, 16, 64, 128 and 256 ch builds (README:38). The count is configurable through `kNumber_Of_Channels`.
- **Customisation:** only names, channels, latency, rates and mirror or hidden flags, via `GCC_PREPROCESSOR_DEFINITIONS` (README:138-204). **The format list and the transport type cannot be set** without editing the source. The transport is hard-coded `kAudioDeviceTransportTypeVirtual` at `:1966` (box) and `:2548` (device).
- **Hog mode:** there is no hog code (0 hits for `HogMode`). Hog is implemented by the HAL above every driver: `kAudioDevicePropertyHogMode` is declared only in the client API (`AudioHardware.h:932-944, 1003`), while plug-ins implement the `AudioHardwareBase.h` model (`AudioServerPlugIn.h:59-62`). So BlackHole is hoggable like any device.
- **Rate change:** asynchronous through `RequestDeviceConfigurationChange` dispatched on a global queue (`:2898`). This is the pattern our driver copies for its "slow DAC" knob.
- **Install:**
  - a `.pkg` whose postinstall does `chown root:wheel` and `chmod` under `/Library/Audio/Plug-Ins/HAL` (`Installer/scripts/postinstall`);
  - or `brew install blackhole-2ch` (README:58-62);
  - then a restart.
  - From source: copy the `.driver` there, then `sudo killall -9 coreaudiod` (README:132-136; wiki "Build with Xcode").
- **Uninstall:** `rm -R /Library/Audio/Plug-Ins/HAL/BlackHoleXch.driver`, then `sudo killall -9 coreaudiod` (README:72-84). The uninstaller pkg does the same (`Uninstaller/Scripts/postinstall`).
- **Verdict for Pure:**
  - Pure refuses it: `CoreAudioDevice.cpp:508-510` sets `isVirtualOrAggregate`, and `PureModePolicy.cpp:106-109` returns `FallbackEnhanced/VirtualDevice`.
  - Even unrefused, it is float-only, so it would only ever show RateMatchedFloat.
  - It is useful only for capturing **Enhanced** output, not Pure.

### 2.3 Apple's samples

- **"Creating an Audio Server Driver Plug-in"** (NullAudio; MIT-style licence © 2024 Apple):
  - C, 4,220 lines.
  - Float32 only at 44.1 and 48 kHz (`NullAudio.c:85, 2867, 2896-2918`).
  - Transport Virtual (`:1603, :2229`).
  - Apple's page: "Install the sample's `.driver` bundle to `/Library/Audio/Plug-Ins/HAL` and reboot your computer."
  - A good reference, but every property is hand-written. Adding formats, rates and devices is the same amount of work as on BlackHole.
- **"Building an Audio Server Plug-in and Driver Extension"** (SimpleAudio, DriverKit):
  - Needs the `com.apple.developer.driverkit` and `…driverkit.transport.usb` entitlements, i.e. an Apple-provisioned App ID.
  - The alternative is to **disable SIP** so the system accepts ad-hoc DriverKit extensions, then reboot.
  - **Rejected:** it touches system security, and DriverKit is meant for real hardware.
- **Plug-in facts that shape the design** (`AudioServerPlugIn.h`, SDK 26.5):
  - The plug-in runs in **its own sandboxed process**, separate from `coreaudiod` (`:34-41`). A driver crash takes down only its helper process.
  - It may write only to cache and temp directories, so captures cannot simply be written to the user's disk.
  - It may use Mach services, if listed in `AudioServerPlugIn_MachServices`, and the network, if `AudioServerPlugIn_Network` is true (`:44-57`).
  - The HAL mixes clients in a canonical float format. **ConvertMix** then converts the mix to the device's native format, and **WriteMix** hands the native bytes to the driver (`:326-343`). WriteMix is therefore exactly the "bytes on the wire" point.
  - "For devices that don't override the mix operation, the virtual format has to be the same as the physical format" (NullAudio comment, `BlackHole.c:3173-3174`; `libASPL Stream.hpp:181-186`). To present **float virtual over an integer physical format**, as this Mac's HDMI does, the driver must do the mix itself. libASPL has a switch for that: `EnableMixing=false`, `Device.hpp:110-121`.
  - Changing a property is asynchronous (`AudioHardware.h:33-34, 300-304`).

### 2.4 libASPL (gavv/libASPL), v3.1.2 @ 633e0f7

- MIT licence, C++17, CMake.
- Typed overrides instead of a hand-written property switch:
  - `GetTransportType` (`Device.hpp:246`; default Virtual, `Device.cpp:76-79`);
  - per-stream physical and virtual formats plus their available lists (`Stream.hpp:150-215`); the default physical format is **Int16** (`:45-55`);
  - available rates (`Device.hpp:353-367`);
  - **runtime** `AddDevice` / `RemoveDevice` (`Plugin.hpp:109, 113`);
  - custom properties (`Object.hpp:165-232`);
  - client hooks carrying the client pid (`ControlRequestHandler.hpp:39-66`, `Client.hpp:26`).
- IO hooks:
  - `OnProcessMixedOutput`: the canonical float mix (`IORequestHandler.hpp:153-174`).
  - `OnWriteMixedOutput`: "already in device's stream native format" (`:176-196`).
- **Integer physical formats work through the HAL's ConvertMix.** The NetcatDevice example ships the HAL's mix as **s16** over UDP and records it with `sox -e signed -b 16` (README:155-158).
- **Gaps we must fill:**
  - a rate change does not update the stream formats (`Device.cpp:161-166`);
  - a physical-format change does not update the virtual format (`Stream.cpp:98-103`).
  - Both take about 50 lines of overrides.
- **Production precedent, roc-vad** (MPL-2.0):
  - a libASPL driver that **listens on TCP `127.0.0.1:9712`** inside the plug-in sandbox (`CMakeLists.txt:28`; `driver/driver.cpp:83-89`);
  - it adds and removes devices on the fly over gRPC;
  - it supports arm64.
  - Its Info.plist does not even declare `AudioServerPlugIn_Network`. We will declare it anyway, as the header requires.

### 2.5 Other options

| Option | What it is | Use for Pure? |
|---|---|---|
| **Rogue Amoeba Loopback** | Commercial; trial "limitations are applied"; macOS 14.5–27 (rogueamoeba.com/loopback). Already partly here: `ACE.driver` 11.9.2 is installed | **No.** Closed. Virtual loopback devices whose formats and transport we cannot set |
| **Soundflower** | A kext; its README says "DEPRECATED Silicon Macs are not supported" | **No.** Dead on Apple Silicon |
| **eqMac driver** | Apache-2.0 Swift plug-in: float32 (`EQMDevice.swift:43`), Virtual transport (`:229`) | **No.** Same limits as BlackHole |
| **Background Music** | GPL-2.0 BGMDriver, float loopback | **No** |
| **Aggregate / multi-output device** | Built from real devices in Audio MIDI Setup | **No.** Transport Aggregate → `VirtualDevice` decline, and the HAL mixes in float |
| **HDMI monitor (have it)** | A real integer device (§2.1) with a real Apple driver | **Behaviour yes, bytes no.** HDMI audio leaves over TMDS. macOS has no loopback. Capturing needs an HDMI capture or extractor box (hardware again, and possibly not transparent). Used in Tier 0 |
| **Core Audio process tap** (`AudioHardwareCreateProcessTap`, macOS 14.2+) | Captures a process's output for one device stream; "the format of the tap will match the format of this stream" (`CATapDescription.h:85-97`) | **Partial.** It sees the client's float before conversion (the RateMatchedFloat case). It cannot see integer bytes. Unknown whether it sees a hogged device. Needs a TCC prompt. Optional Tier-0 spike only |

No open-source "bit-perfect test DAC" exists; the searches found none. This has to be built.

### 2.6 Real DAC format lists (what we clone)

| DAC | What it advertises | Source |
|---|---|---|
| **Apple USB-C to 3.5 mm adapter (A2049)**, UAC1 | Altset 1 `S24_3LE` (3-byte packed 24-bit), altset 2 `S16_LE`, 2 ch, sync endpoint. "the only two rates it supports": 44.1 k and 48 k | Linux kernel bug 217501 (LKML mirror) |
| **AudioQuest DragonFly Black** | 96 kHz / 24-bit max; 44.1, 48, 88.2, 96 kHz (LED colours); no driver needed | avstore.in product spec |
| UAC1 in general | Full-speed only ("Audio Class 1.0 mode is not supported at high-speed"); ≤ 96 kHz when output only; 2 ch at FS. UAC2 supported on macOS since 10.6.4 | XMOS USB Audio guide |
| **Topping E30**, UAC2 | `S32_LE` ×2 altsets (+ DSD), 2 ch, 44.1 k … 768 k (10 rates), 125 µs packets | Volumio forum `/proc/asound/E30/stream0` |
| macOS view of 4-byte 24-bit | "24 little endian Signed Integer aligned low in 32bit 44.1kHz". This Mac's HDMI reports the same layout | Audirvana forum debug log (search snippet; page behind Cloudflare) |
| **RME ADI-2 Pro** | "2ch Non-mixable linear PCM Interleaved 32bits little endian Signed Integer, 8 bytes per frame 44.1kHz" (Audirvana integer mode); AMS shows "24-bit Integer" | RME forum, viewtopic 25573 |
| **Benchmark DAC2** | 2 ch, mixable **and** non-mixable 24-bit LE signed int at 44.1 / 48 / 88.2 / 96 | Audirvana forum (search snippet; page blocked) |
| macOS 26 caveat | "Integer mode not working on MacOS Tahoe (no sound during playback)" (Audirvana integer = non-mixable + hog) | Audirvana forum title/snippet |
| Plug-in caveat | 24-bit **big-endian** WriteMix "doesn't seem to be supported" on Sonoma 14.2.1 (no reply) | Apple forum 745835 |

---

## 3. The recommended rig, and why

**Tier 0 (start today).**
- `vdac-observe`, a ~250-line C tool, is a **read-only** HAL listener, grown from `probe/listfmt.c`. It records in JSONL with timestamps:
  - nominal rate and physical and virtual format;
  - hog owner;
  - `IsRunningSomewhere`;
  - buffer size;
  - default devices.
- The founder plays Pure on HDMI and on the built-in speakers with both **muted**: the monitor's own volume at 0, the Mac at 0. The app's logs (`logASBD`) give the AU formats.
- It proves real-driver behaviour: C-100, hog, restore, unplug, D75. It cannot read bytes.

**Tier 1 (one admin install).** "AS Test DAC" on libASPL plus the tools in §5 and §8.

Why this rig:
- **It uses the real HAL path.** Pure runs unchanged: AUHAL, hog, rate and format sets, the HAL mix and ConvertMix. Only the "hardware" at the bottom is ours.
- **No product-code change is needed to pass the policy.** The fake device reports a USB transport. The alternative, a DEBUG switch in the app that ignores `VirtualDevice`, would test a policy that never ships.
- **The format lists are data.** Any real DAC can be cloned from a `listfmt` dump, including the founder's DAC when it arrives. From then on, regression runs on its exact formats need no hardware.
- **Deterministic adversarial knobs:**
  - a slow DAC relock;
  - a device that lies about rates;
  - a stalled stop on a dying device;
  - unplug at any moment.
- A real DAC cannot do these on demand.
- **No SIP change, no kext, no system extension, no Apple entitlement and no notarization.** It is ad-hoc signed and runs in Apple's sandboxed driver host.
- **Silent by construction.** The devices are null sinks. An interlock (§8.5) refuses to run if a real speaker could play.

**Rejected:**
- stock BlackHole (refused by the policy, float-only);
- a BlackHole fork (GPL C, hard-coded formats everywhere);
- NullAudio (the same amount of work, in C);
- DriverKit (SIP or entitlements);
- Loopback and Soundflower (closed or dead);
- aggregates (refused);
- an HDMI capture box (hardware, transparency unknown);
- process taps as the main tool (float only).

---

## 4. Personalities (what the fake DACs advertise)

Each personality is a JSON document sent to the driver at runtime. Nothing is compiled in.

There are two modes:
- **B (default, faithful):** virtual float32 over integer physical, the driver doing the mix and conversion. This is what the HDMI here and AppleUSBAudio present.
- **A (coverage):** virtual = physical, with the HAL's ConvertMix doing the conversion. This makes AUHAL hand Pure the integer format, so `convertFloatToNative`'s integer layouts run through the real HAL.

| ID | Mimics | Transport | Ch | Rates (Hz) | Physical formats (every rate) | Current at creation |
|---|---|---|---|---|---|---|
| P1 `apple-dongle` | Apple A2049 | USB | 2 | 44 100, 48 000 | Int24 **packed** (24 bits, 6 B/frame, SInt\|Packed); Int16 (4 B/frame) | Int24p @ 48 k |
| P2 `uac1-dac` | DragonFly Black / UAC1 | USB | 2 | 44.1 k, 48 k, 88.2 k, 96 k | Int24 packed; Int16 | Int24p @ 44.1 k |
| P3 `uac2-int32` | Topping E30 | USB | 2 | 44.1 k … 768 k (10) | Int32 (32 bits, 8 B/frame) | Int32 @ 48 k |
| P4 `uac2-24in32lo` | macOS "aligned low in 32"; HDMI layout | USB | 2 | 44.1, 48, 88.2, 96, 176.4, 192 k | Int24-in-32 **low** (24 bits, 8 B/frame, SInt only); Int16 | 24in32lo @ 48 k |
| P5 `uac2-24in32hi` | converter coverage | USB | 2 | as P4 | Int24-in-32 **high** (SInt\|AlignedHigh) | 24in32hi @ 48 k |
| P6 `pro-nonmix` | RME ADI-2 Pro / Benchmark DAC2 | USB | 2 | 44.1 … 192 k | mixable 24in32lo + **non-mixable** Int32 and 24in32lo | mixable 24in32lo |
| P7 `hdmi-clone` | this Mac's VA279HG | HDMI | 2 | 32 k, 44.1 k, 48 k | 24in32lo; 20-in-32; Int16 packed | 24in32lo @ 48 k |
| P7x `hdmi-liar` | "HDMI 48 k lock" | HDMI | 2 | advertises 32 / 44.1 / 48 k, **never leaves 48 k** | as P7 | as P7 |
| P8 `float-only` | MacBook speakers (clone) | USB | 2 | 44.1, 48, 88.2, 96 k | Float32 only | F32 @ 48 k |
| P9 `8ch-iface` | multichannel interface | USB | 8 | 44.1 … 192 k | 24in32lo | @ 48 k |
| P10 `virtual-xport` | P4 with Virtual transport | Virtual | 2 | as P4 | as P4 | as P4 |
| P11 `ranged-rate` | ranged descriptions (`kAudioStreamAnyRate`, `AudioHardwareBase.h:984-997`) | USB | 2 | 44.1–192 k as a range | 24in32lo with mSampleRate = AnyRate | — |
| P12 `current-float` | integer DAC currently in float | USB | 2 | as P4 | 24in32lo + Float32 | **Float32** |
| P13 `two-mono` | stereo DAC as 2 × 1-ch streams | USB | 1 + 1 | as P4 | 24in32lo per stream | — |
| P14 `rejects-only` | the R1 picker rejections | USB | 2 | 48 k | 20-in-24 packed, 20-in-32, UInt16, Float64, non-interleaved, "Packed" 24-in-32 (self-contradictory) | first |
| P15 `be24` | BE 24 packed (Apple forum 745835) | USB | 2 | 48 k | Int24 packed **BigEndian** | — |
| P16 `clone` | any `listfmt` dump (the DAC on arrival) | as dumped | | | | |

T1 runs the six requested rates (44.1 / 48 / 88.2 / 96 / 176.4 / 192 k) wherever a personality advertises them. P3's 352.8 k to 768 k are a stretch row.

Flags on every personality:
- `CanBeDefault=true`: Enhanced fallback re-asserts its target as the system default, `AudioEngineBridge+OutputDeviceMonitor.swift:152-166`.
- `CanBeDefaultForSystemSounds=false`.
- No software volume or mute: nothing may touch the samples.
- An optional "hardware" volume control that is reported but never applied (for D84).

---

## 5. Driver design ("AS Test DAC"), about 1,000–1,300 lines of C++

- **Location:** `tools/virtual-dac/driver/`, with libASPL **pinned at v3.1.2** as a submodule (like libebur128).
  - Built with CMake, ad-hoc signed with `codesign --force --sign -`.
  - Info.plist: `sandboxSafe=true`, `AudioServerPlugIn_Network=true`, CFPlugIn factory (exported symbol, no `-fvisibility=hidden`).
- **At load:**
  - **zero devices**;
  - a control and stream server on `127.0.0.1:47800` (loopback only).
- **Commands** (JSON lines):
  - `ping`;
  - `create {personality}` → UID;
  - `remove {uid}`;
  - `set-alive {uid,false}`;
  - `knobs {uid, rateDelayMs, formatDelayMs, refuseRates[], stopIOStallMs, startIOFailN}`;
  - `capture {uid,on|off}`;
  - `events {uid}`;
  - `remove-all`.
- **Device and stream subclass:**
  - It overrides `GetTransportType`.
  - It keeps the device rate, the stream physical format and the virtual format consistent on every change. Mode A: virtual = physical. Mode B: float32 at the same rate and channels.
  - It delays `RequestConfigurationChange` by the knob (the BlackHole `:2898` pattern), so a property read in the window returns the **old** value, as on a DAC that relocks slowly.
- **IO and capture:**
  - Mode A (`EnableMixing=true`): `OnProcessMixedOutput` → capture **C** (canonical float, untouched); `OnWriteMixedOutput` → capture **W** (native bytes).
  - Mode B (`EnableMixing=false`): the per-client float goes to capture C. The driver's own reference converter (×2^(N−1), round-to-nearest, clip; the same convention as `PureModeFormat.cpp:31-34`) produces W.
  - The RT thread only `memcpy`s into a preallocated SPSC ring (256 MB). A drain thread streams tagged blocks `{uid, op, sampleTime, hostTime, frames, formatGen}`.
  - **Ring overflow makes the run INVALID**; it is never counted as a pass.
- **Event log** (host-time stamped):
  - client add and remove (pid, bundle ID);
  - StartIO / StopIO per client;
  - rate request and perform (old → new);
  - physical-format request and perform;
  - IO overload;
  - device add and remove;
  - knob changes.
- **Not in the driver:** hog. The HAL owns it (§2.2). We observe it from the client side (`vdac-observe`) and from the driver's StartIO log.

---

## 6. Install and uninstall: what each step needs (for the founder to approve)

| Step | Command (founder runs it) | Needs | Touches system security? |
|---|---|---|---|
| Tier 0 | `vdac-observe <device>` while playing muted | nothing (user level, read-only) | No |
| Build | `cmake -S tools/virtual-dac -B build/vdac && cmake --build build/vdac` (in a worktree, never the main checkout) | Xcode CLT, cmake (brew) | No. Ad-hoc signature; a local build has no quarantine flag (check with `xattr -lr`) |
| Install | `sudo cp -R build/vdac/ASTestDAC.driver /Library/Audio/Plug-Ins/HAL/` then `sudo chown -R root:wheel /Library/Audio/Plug-Ins/HAL/ASTestDAC.driver` | **admin password** | Writes one bundle into a root-owned folder. No SIP, kext, system extension, TCC, login item or LaunchDaemon |
| Load | `sudo killall coreaudiod` (launchd restarts it). Quit music, video and call apps first. Reboot is the fallback | **admin password** | All audio drops for ~1–2 s; some apps need a relaunch |
| Verify | `vdac-ctl ping`; `vdac-ctl create uac2-24in32lo` → the device appears in Audio MIDI Setup; `vdac-ctl remove-all` | nothing | No. If the driver does not load on macOS 26, check System Settings › General › Login Items & Extensions (one vendor reports a HAL-driver toggle there on Tahoe; unconfirmed) and Console for sandbox denials |
| Runtime | — | — | Runs as `_coreaudiod` in Apple's sandboxed driver host. Listens on 127.0.0.1 only. Any local process could connect and read a *test* device's capture. Acceptable on a single-user dev Mac; an optional shared token is listed in §11 |
| Update | rebuild, then repeat Install + Load (expected 2–4 times while building Tier 1) | admin password each time | as Install |
| Uninstall | `vdac-ctl remove-all`; `sudo rm -rf /Library/Audio/Plug-Ins/HAL/ASTestDAC.driver`; `sudo killall coreaudiod` | **admin password** | Leaves only the HAL's per-UID settings in `/Library/Preferences/Audio` (harmless). If the app was pinned to a test device, re-pick the output |

Note: because the fake devices say "USB", macOS might auto-switch the system output to one when it appears. The harness snapshots the default output and system-output devices before `create` and restores them after `remove`, including on Ctrl-C.

---

## 7. Test plan

The predictions are what the current code should do, read from the lines cited. The rig confirms or refutes each one; a refuted prediction is a finding.

### Tier 0: real hardware, no install (founder present, everything muted)

| ID | What | How | Pass / prediction |
|---|---|---|---|
| T0.1 | **C-100 count** | A 44.1 k file in Pure on the built-in speakers (48 k now; RateMatchedFloat, shared) and on HDMI (FullBitPerfect, hog). Play 10 s, then pause and resume ×5, then stop. `vdac-observe` counts rate changes | **Predicted: 12 switches** (1 + 2×5 + 1) on the speakers. On HDMI also 12, but only if the 44.1 k change takes (T0.5); otherwise every start declines to Enhanced. The target after a fix is 1 (+1 at stop) |
| T0.2 | Hog on HDMI | Hog owner during and after play. Start QuickTime on HDMI while Pure plays | Owner = the app pid while playing, −1 after. QuickTime is cut off |
| T0.3 | Real hot-unplug | Pull the HDMI cable mid-Pure; replug; play | Pauses; no beach ball (run a `sample` loop); no crash; plays again after replug |
| T0.4 | **D75** | App log lines `AU output (post-set)` / `AU input (cached)` on HDMI | **Predicted: float32**, even though decision = FullBitPerfect. Record what the signal-path UI claims |
| T0.5 | HDMI 44.1 k | Does the 48 → 44.1 change take on VA279HG? | Either it rate-matches, or gate 2b declines to Enhanced. Then correct the engine comment either way |
| T0.6 (optional) | Process-tap spike | Tap the app on the built-in speakers during RateMatchedFloat | Bit-exact float vs the decoded file; and whether a hogged device is tappable |

### Tier 1: AS Test DAC (automated, silent)

| ID | What | Scenario | Pass criteria (and prediction) |
|---|---|---|---|
| **T1** | **Bit-exact per layout × rate** | P1–P5, P7, P8 × modes A/B × {44.1, 48, 88.2, 96, 176.4, 192 k} as advertised × 16- and 24-bit sources (WAV, AIFF-BE, FLAC, ALAC) | Every frame of W equals the source codes in the device layout; C equals code / 2^(N−1) bit for bit. 0 mismatches, 0 dropped or inserted frames. A 24-bit source on a 16-bit-only device is **expected not exact** (truncation, `PureModeFormat.cpp:78-83`), and the UI must not say bit-perfect there |
| **T2** | **Fallbacks** | mono → P4; stereo → P9 (8 ch); 6 ch → P4; 176.4 k → P2; 44.1 k → P7x; any → P10 | Enhanced plays: decision 2 with reasons 5 / 5 / 5 / 4 / 3, or (P7x) the engine's gate 2b after a policy "yes"; `fellBackToEnhanced=true`. The driver log shows **no** rate switch and no hog, except P7x: there a hog take, one refused rate request and a hog release come before the decline (`HALOutputEngine.mm:353-404`). The capture is non-silent and the right length (Enhanced is not bit-exact by design) |
| **T3** | **C-100 + restore** | P4 created with current **Int16 @ 48 k** (so a format that is not restored is visible), a 44.1 k file: play / pause / resume ×5 / stop, at engine level and app level | Count of rate performs, format performs and hog take/release, the gap on each resume, and the resume position (frames repeated or skipped). **Predicted:** 12 rate switches; 6 physical-format sets to 24in32lo and none back to Int16 (C-31: after stop the device is at 48 k but 24in32lo); hog released on every pause |
| T3-H1 | **Fast resume on a slow DAC** (new hypothesis) | P4 with `rateDelayMs=300`; resume 50 ms after pause | **Predicted defect:** teardown's restore is not awaited (`HALOutputEngine.mm:877`). The next start reads the stale 44.1 k (`CoreAudioDevice.cpp:494` → `PureModePolicy.cpp:142`; `originalRate_` at `:351`), requests no change, and the delayed 48 k then lands under a 44.1 k stream. Stop finally "restores" 44.1 k, so the user's 48 k is lost. The capture shows non-exact output |
| **T4** | **Hog** | `vdac-actor` takes hog, starts an IOProc and plays during Pure FullBitPerfect; during RateMatchedFloat (P8); before Pure starts; during a pause | FullBitPerfect: the actor's IO is refused, its StartIO never reaches the driver, and the owner is the app pid. RateMatchedFloat: no hog (bridge override), so the actor mixes in and the comparator flags non-exact (documents the shared-mode limit). Pre-hogged: the app reports a failure; no hang, no audio elsewhere. Owner is −1 after stop |
| **T5** | **Gapless, same rate** | 3-track album per layout × rate; 16 → 24-bit at the same rate; 44.1 → 48 k | Same format: a continuous stream across seams with 0 frames inserted or dropped. A bit-depth or rate change: **no** seam (`GaplessSource.cpp:89-91`), a fresh start, a gap, and (for the rate change) one rate switch |
| **T6** | **D41 on Pure** | The six actions mid-song (Play Next, shuffle on / off, repeat all→one / one→off, remove on-deck), two quick Play Next, Play Next in the last 0.5 s, NEXT-NEXT | The track ID heard after every seam (from the capture barcode) == what the VM shows, except for counted A2 cases (`d41-design.md` §2.3). Expected 12/12 hold, as in `p4-d41-impl-break.md` |
| **T7** | **Device disappears** | `remove` mid-play; during a rate change; at a seam; during a seek; `stopIOStallMs=7000` then remove (a dying USB device); `set-alive false`; re-add with the same UID | Pause; main thread never blocked > 50 ms (the existing stall probe); no crash; nothing left parked except via `parkRender` and logged. After re-add: no auto-resume (founder decision), and Play works in Pure again |
| T8 | Seek and resume accuracy | Seek to sample-indexed points | The first non-silent frame after a seek is exactly the target frame; no stale frames |
| T9 | **Format and rate races (DSP-05)** | `formatDelayMs` 0 / 50 / 500 and `rateDelayMs` 0 / 500 / 2500 | Set physical format, then read the AU output immediately (`:618-638`). Prediction: with a delay, the stale read makes Pure adopt the old format, and the output is not exact. A 2,500 ms rate delay exceeds the 2 s poll, so gate 2b declines |
| T10 | External rate change while shared (D77) | The actor changes P8's rate mid-RateMatchedFloat | Prediction: no listener, so AUHAL resamples while the UI still says "rate-matched" |
| T11 | **Large slice (DSP-04)** | The actor sets the buffer to 8,192 frames on P8 | **Predicted:** all silence (`HALOutputEngine.mm:758-765`) |
| T12 | Device volume (D84) | "Hardware" volume at −10 dB, main and per-channel-only variants | The capture is still exact (volume is never applied); the app shows the device volume. Per-channel-only shows "fixed" (D84) |
| T13 | Crash mid-Pure | `kill -9` the app | The HAL releases hog. The device is left at the file's rate and format (no teardown). Document it; Cog recovers on the next launch |
| T14 | **R1 picker rejections** | P14, P15, P11, P12, P13, P6 | P14: nothing writable → float or decline, never a guess. P15: the HAL accepts BE or not (record). P11: **predicted** no match (ranged rates ignored) → float. P12: **predicted** RateMatchedFloat on an integer-capable DAC (`CoreAudioDevice.cpp:502`). P13: **predicted** a wrong `ChannelCountMismatch` (first stream = 1 ch). P6: whether AUHAL drives non-mixable (Cog saw −10851) |

---

## 8. The comparison harness (offline, automated, nothing heard)

### 8.1 Test signals (`vdac-gen`, Python)

The generator writes WAV with the stdlib, converts to FLAC / ALAC / AIFF with the `ffmpeg` CLI (already required by the project), and writes a manifest of `{seed, params}`. Expected samples are regenerated from the seed, so **our decoder is never the oracle**.

Each file contains:
- **Header** (2,048 frames): a 64-frame sync word, the track ID, the rate and the bit depth, encoded as codes. This lets any capture identify itself after a seam.
- **Body:**
  - 16-bit: all 65,536 codes in a PRBS-permuted order. L and R use different seeds, which catches channel swap, byte order and sign errors.
  - 24-bit: a 2^20-sample PRBS24 window, plus edge codes (±full scale, 0, ±1, byte-boundary patterns 0x7F / 0x80 / 0xFF in each byte), which catches packing and alignment mix-ups. The full 2^24 period runs in nightly mode.
- **Tail:** a frame counter, so seams and seeks are checkable at any point.

Real-music rows use the founder's files with an **independent** oracle (`ffmpeg -f s32le` / `flac -d`).

### 8.2 Capture (`vdac-ctl`)

- It receives the driver's tagged C and W blocks and the event log.
- It splits them into segments at every format or rate event.
- It writes `capture-<scenario>/{W,C}-<seg>.bin` plus `events.jsonl`.

### 8.3 Compare (`vdac-compare`, Python; numpy if present)

- Decode each segment by its layout: Int16, Int24 packed, 24-in-32 high/low, Int32, Float32 bits; LE or BE.
- Find the sync word, then compare frame by frame through every seam against the concatenated expected stream.
- Report per segment:
  - first mismatch, mismatch count, max LSB error;
  - frames inserted or dropped;
  - leading silence;
  - seam positions.
- Check the event invariants per scenario: the rate and format switch counts, the hog owner, the restored state.
- Output: JSON and JUnit, with **exit code ≠ 0 on any mismatch or ring overflow**.
- The same comparator later accepts a **real** capture (a DAC with digital loopback, NFR-QUAL-03's MD5 bit-compare in `product.md:241`).

### 8.4 Playback driver

`AdaptiveSound -ASPureHIL <scenario.json>` is a DEBUG-only rig, the same pattern as `-ASMainThreadStall` (`Makefile:110-121`, `Debug/MainThreadStallRig.swift`). It has two levels:
- **Engine level:** calls the C ABI in `PureModeBridge.h` directly (start, seek, stop, arm, poll). Used for T1, T3, T5, T8, T9 and T11.
- **App level:** the real `AudioViewModel` + `AudioEngineBridge`. Used for T3 (VM pause), T6 (D41) and T7 (device-loss monitor).

### 8.5 Orchestration and the speaker interlock

- `make pure-hil` is opt-in: it skips with a message if the driver is unreachable. It is **never** part of `strict-gate` or CI.
- Before every scenario it checks:
  - the app's target UID has the test prefix;
  - if Enhanced could play, the system default output is a test device;
  - no real device is the target.
- If any check fails, it **aborts before play**.
- It restores the user's defaults at exit, including on a signal.
- `vdac-actor` (the adversary) refuses any UID without the test prefix.

---

## 9. Effort and phasing (agent days)

| Phase | Content | Effort |
|---|---|---|
| 0 | `vdac-observe` + Tier-0 runs with the founder (T0.1–T0.5) | 0.5–1 d |
| 1 | Driver skeleton: on-demand personalities, USB transport, formats and rates kept consistent, mode A, C/W capture, events, TCP control and stream, knobs. Smoke checks S1–S4 below | 2–3 d |
| 2 | `vdac-gen` / `-ctl` / `-compare`, the engine-level rig, then T1, T2, T3, T4, T5, T8, T9, T11, T14 | 2–3 d |
| 3 | Mode B (driver-owned mix and conversion), the app-level rig, then T6, T7, T10, T12, T13 | 2–3 d |
| | **Total** | **≈ 7–10 d**. Phases 0–2 (≈ 5 d) cover the bit-exact matrix, C-100, hog and the fallbacks before the DAC arrives |

**First-hour smoke checks after install** (each one's failure changes the plan):
- **S1:** the HAL's ConvertMix accepts each integer layout (packed-24, 24-in-32 lo/hi, Int32). Int16 is known to work.
- **S2:** hog behaves on a plug-in device as on hardware.
- **S3:** a plug-in reporting USB has no side effects (auto default switching, latency).
- **S4:** in mode A, AUHAL's output scope shows the integer virtual format (TN2091: "the format is always expressed on the output scope of the AUHAL's Element 0").

---

## 10. What this still cannot prove, compared with a real DAC

1. **Apple's USB driver.**
   - Its own float → integer conversion (mode B uses *our* reference converter; mode A uses the HAL's plug-in ConvertMix; neither is AppleUSBAudio's code).
   - How it maps UAC descriptors to formats.
   - Its integer-mode and hog behaviour on macOS 26 (Audirvana reports integer mode broken on Tahoe).
   - **Mitigation:** on DAC day, dump the DAC with `listfmt` and run P16 `clone`. Then a digital-loopback or by-ear smoke closes the converter gap.
2. **USB itself:**
   - isochronous transport, async feedback, the DAC's own clock domain, drift and jitter;
   - USB scheduling glitches;
   - real hot-unplug timing (IOKit termination) versus a driver removing a device.
3. **The DAC's firmware:**
   - relock time;
   - **audible clicks or mute on a rate switch** (we count switches, we cannot hear them);
   - quirks such as Cog's SMSL failing to start IO after a rate + format two-step.
4. **The analog stage:** filters, noise, THD. These don't matter for bit-perfect, but do for "sounds right".
5. **The faked transport:** the HAL may treat a real USB device differently in ways a plug-in claiming "USB" does not trigger.
6. **HDMI bytes:** Tier 0 proves behaviour, not the bits. Only an external HDMI capture or extractor box would.
7. **DSD / DoP:** out of scope.

---

## 11. Decisions for the founder (recommended option first)

1. **Run Tier 0 this week (no install)?**
   - **Recommended: yes.** It needs only muted playback on HDMI and the speakers plus one cable pull, and it settles C-100 and D75 on real Apple drivers.
2. **Approve the one-time driver install** (admin password + a `coreaudiod` restart; repeated 2–4 times while building)?
   - **Recommended: yes.** It touches no system security, and uninstalling is one `rm` and a restart.
3. **Where the rig lives:**
   - **Recommended:** in the repo, under `tools/virtual-dac/`, on its own branch, with libASPL pinned as a submodule. It is kept out of the app build and CI, but still meets the lint and format bar.
   - Alternative: scratch-only. That is faster to start, but the rig is lost for regression later.
4. **How the fake DAC passes the policy:**
   - **Recommended:** the driver reports USB. There is no product-code change, and the shipped policy is the one tested.
   - Alternative: a DEBUG override in the app. Not recommended.
5. **Verify first, then fix:**
   - **Recommended:** verify first. Let the rig confirm or refute the predictions (C-100 count, C-31, T3-H1, D75, DSP-04, P11–P13), then fix with the rig as the regression gate.
6. **Optional shared token on the localhost socket:**
   - **Recommended:** skip it on a single-user dev Mac, and add it only if the rig ever runs on a shared machine.

---

## 12. Sources

**Code read (repo @ c95e2c6):**
- `Sources/AudioDSP/AudioEngine/HALOutputEngine.mm`
- `Sources/AudioDSP/{PureModeFormat,PureModePolicy,PureModeBridge,PureModeBridgePolicy,CoreAudioDevice,GaplessSource}.cpp` and their headers
- `Sources/AdaptiveSound/AudioEngineBridge+{PureMode,Playback,OutputDeviceMonitor}.swift`
- `AudioViewModel+{Transport,Lifecycle}.swift`
- `Makefile`
- council `area-dsp-cpp.md` (DSP-04/05), `panel-p3-path-{breaker,sota}.md`, `p3a-purefix-break.md`, `stage5-architect.md` (C-100, C-31), `d41-design.md`, `p4-d41-impl-break.md`, `product.md:241`

**SDK headers (Xcode SDK 26.5):**
- `AudioServerPlugIn.h:34-62, 305-357`
- `AudioHardware.h:33-34, 300-304, 564-568, 932-944`
- `AudioHardwareBase.h:984-997, 1097-1105`
- `CATapDescription.h:85-111`

**Cloned or downloaded (scratch):**
- BlackHole `BlackHole/BlackHole.c`, `README.md`, `Installer/`, `Uninstaller/` — https://github.com/ExistentialAudio/BlackHole
- libASPL `include/aspl/*.hpp`, `src/{Device,Stream}.cpp`, `examples/` — https://github.com/gavv/libASPL
- Apple NullAudio sample (`NullAudio.c`) — https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in
- DriverKit sample page — https://developer.apple.com/documentation/coreaudio/building-an-audio-server-plug-in-and-driver-extension
- roc-vad (`CMakeLists.txt:28`, `driver/driver.cpp:83-89`, `driver/Info.plist.in`) — https://github.com/roc-streaming/roc-vad
- eqMac driver (`native/driver/Source/EQMDevice.swift:43, 229`) — https://github.com/bitgapp/eqMac

**Web:**
- BlackHole wiki "Build with Xcode" — https://github.com/ExistentialAudio/BlackHole/wiki/Build-with-Xcode
- Bypass driver notes (ad-hoc OK, quarantine refused, exported factory, `killall` vs kickstart) — https://github.com/alileza/bypass
- Apple TN2091 (AUHAL formats, channel map) — https://developer.apple.com/library/archive/technotes/tn2091/_index.html
- Apple forum 745835 (BE-24 WriteMix) — https://developer.apple.com/forums/thread/745835
- Apple forum 37553 (hog on a virtual driver) — https://developer.apple.com/forums/thread/37553
- Apple A2049 stream0 — https://lkml.iu.edu/hypermail/linux/kernel/2305.3/06978.html (bug https://bugzilla.kernel.org/show_bug.cgi?id=217501)
- Topping E30 stream0 — https://community.volumio.com/t/bitrate-padding/46069
- DragonFly Black spec — https://avstore.in/products/audioquest-dragonfly-black
- XMOS UAC1 / UAC2 — https://www.xmos.com/documentation/XM-012296-UG/html/doc/rst/opt_audio_class.html
- RME ADI-2 Pro formats — https://forum.rme-audio.de/viewtopic.php?id=25573

**Audirvana threads** (search snippets only; the pages are behind Cloudflare):
- "aligned low in 32bit" — https://community.audirvana.com/t/issue-flac-16bit-is-sent-out-as-24bit/7508?page=2
- Benchmark DAC2 mixable / non-mixable — https://community.audirvana.com/t/audirvana-not-working/33671
- Tahoe integer mode — https://community.audirvana.com/t/integer-mode-not-working-on-macos-tahoe-no-sound-during-playback/45241

**Other:**
- Rogue Amoeba Loopback — https://rogueamoeba.com/loopback/
- Soundflower — https://github.com/mattingalls/Soundflower
- Tahoe Login Items & Extensions (vendor HAL-driver toggle; unconfirmed for HAL plug-ins) — https://support.apple.com/guide/mac-help/change-login-items-extensions-settings-mtusr003/mac
