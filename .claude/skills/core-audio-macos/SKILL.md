---
name: core-audio-macos
description: Develop macOS audio applications in C/C++ using Core Audio — device I/O, real-time DSP, system-wide audio processing, and virtual audio drivers. Use this skill whenever the user mentions Core Audio, AudioToolbox, AUHAL, Audio Units, AudioServerPlugIn, HAL plugins, virtual audio devices, vDSP/Accelerate for audio, audio render callbacks, system-wide EQ or sound enhancement on macOS, capturing or processing speaker output, or any macOS audio app work in C or C++ — even if they don't say "Core Audio" explicitly (e.g. "list audio devices on my Mac", "process all system audio", "build an EQ for macOS").
---

# Core Audio Development on macOS (C/C++)

This skill covers building macOS audio applications with Apple's Core Audio stack: enumerating and controlling devices, low-latency I/O with render callbacks, DSP with vDSP/Accelerate, and system-wide audio processing via AudioServerPlugIn virtual devices.

## How to use this skill

1. Identify which scenario the task falls under (table below) and confirm the architecture before writing code.
2. Read `references/code-samples.md` for code for the specific task. Each sample carries a `Source:` line naming the Apple document or SDK header it derives from.
3. **Ground all code in Apple primary sources, not model memory.** Core Audio's property-based APIs are easy to get subtly wrong (wrong scope/element, missing size checks, leaked CFObjects, deprecated calls), and training data mixes decades of deprecated patterns. When a task goes beyond the bundled samples: fetch the relevant Apple Documentation Archive page (static HTML, fetchable — TN2091, QA1811, Core Audio Essentials; URLs in resources.md), or read the SDK headers on the user's machine (`xcrun --show-sdk-path`, then the headers in `CoreAudio.framework/Headers/` and `AudioToolbox.framework/Headers/` — Apple's header comments are the canonical modern documentation). Note that modern developer.apple.com/documentation pages are JS-rendered and return nothing useful to fetch tools; use the archive pages or local headers instead. Preserve `Source:` comments in code handed to the user.
4. When citing documentation, sample projects, or learning material, pull links from `references/resources.md` rather than inventing URLs.
5. Apply the real-time rules below to ANY code that runs on the audio thread. This is the most common source of bugs in Core Audio projects.

## Choosing the right API for the task

| Task | API | Sample |
|---|---|---|
| List/inspect audio devices | AudioObject property API (`kAudioHardwarePropertyDevices`) | code-samples.md §1 |
| Get/set default output device | `kAudioHardwarePropertyDefaultOutputDevice` | code-samples.md §2 |
| React to device plug/unplug, default-device changes | `AudioObjectAddPropertyListenerBlock` | code-samples.md §3 |
| Play/process audio in your own app | AUHAL output unit + render callback | code-samples.md §4 |
| Capture from an input device | AUHAL with input enabled (TN2091) | code-samples.md §5 |
| EQ / filtering / FFT | vDSP (Accelerate) — `vDSP_biquad`, `vDSP_fft_zrip` | code-samples.md §6 |
| Sample-rate / format conversion | AudioConverter | code-samples.md §7 |
| Audio-thread ↔ UI-thread communication | Atomics / SPSC ring buffer (CARingBuffer, TPCircularBuffer) | code-samples.md §8 |
| Process ALL system audio (other apps' output) | AudioServerPlugIn virtual device + companion app | code-samples.md §9 + resources.md |
| Connect a SwiftUI/AppKit GUI to the C++ engine | Objective-C++ wrapper or Swift C++ interop | references/swift-bridge.md |

Key architectural fact: macOS provides no way to directly intercept another app's audio. System-wide processing (e.g. a system EQ or sound enhancer) requires shipping a virtual audio device — an `AudioServerPlugIn` installed in `/Library/Audio/Plug-Ins/HAL/` — that the user selects as the default output. Your app reads from the virtual device, applies DSP, and writes to the physical device. Do not propose tapping `coreaudiod` or other apps directly; recommend the virtual-device architecture and point at BlackHole / Background Music as reference implementations (links in resources.md). Note: as an alternative for capture-style features on macOS 14.4+, Core Audio taps (`CATapDescription` / `AudioHardwareCreateProcessTap`) can capture other processes' audio with user permission — worth mentioning, but a processing chain that feeds the speakers still typically needs the virtual-device route.

## Real-time audio thread rules

Code inside a render callback or `AudioServerPlugIn` IO function runs on a real-time thread with a hard deadline (one buffer period, e.g. ~10 ms at 512 frames / 48 kHz; often much less). Violating these rules produces intermittent glitches that are very hard to debug, so enforce them in every sample you write or review:

- No heap allocation (`malloc`, `new`, growing a `std::vector`, `std::string` ops, most of Objective-C/Swift).
- No locks that a non-real-time thread might hold (`std::mutex`, `@synchronized`, `dispatch_sync`).
- No file or network I/O, no logging with `printf`/`NSLog`/`os_log` on the hot path.
- No Objective-C message sends or Swift runtime calls.
- Communicate with other threads via lock-free SPSC ring buffers and `std::atomic` parameters (sample §8).
- Pre-allocate every buffer at initialization time, sized for the maximum buffer size (`kAudioDevicePropertyBufferFrameSizeRange`).
- Handle the case where `inNumberFrames` differs from the expected size rather than asserting.

If the user's design requires the audio thread to wait for anything, redesign it: the audio thread reads the latest available state and never blocks.

## AudioServerPlugIn-specific constraints

When working on virtual-device driver code, additionally observe (see QA1811 in resources.md):

- The plug-in runs inside `coreaudiod`, sandboxed: it may only read files inside its own bundle and system frameworks; persistent state goes through the host's storage API, not direct file writes.
- It must never call the HAL client API in `CoreAudio.framework` (undefined behavior).
- Pure C/C++ only; no Objective-C. Keep dependencies minimal.
- IPC with a companion app requires listing mach service names under the `AudioServerPlugIn_MachServices` Info.plist key.
- Installation requires copying the bundle to `/Library/Audio/Plug-Ins/HAL/` and restarting `coreaudiod` (`sudo killall coreaudiod`) — warn users this briefly interrupts all system audio.
- Distribution requires Developer ID signing and notarization.

## Common pitfalls to check for in any Core Audio code

- `AudioObjectPropertyAddress` needs the right **scope** (`kAudioObjectPropertyScopeGlobal` vs `Input`/`Output`) and **element** (`kAudioObjectPropertyElementMain`); wrong scope silently returns the wrong data.
- Always call `AudioObjectGetPropertyDataSize` first for variable-size properties; never assume counts.
- Check every `OSStatus`; many codes are four-char codes — print them as such when debugging.
- AUHAL: enabling input requires disabling output on the same unit (or using two units) and setting the device **before** initialization.
- `AudioStreamBasicDescription` mismatches (interleaved vs non-interleaved, Float32 vs SInt16) are the #1 cause of garbage audio — log the ASBD on both sides when debugging.
- Release CoreFoundation objects returned by properties (`CFStringRef` device names etc.).
- On Apple Silicon, prefer Float32 non-interleaved internally and use vDSP for any per-sample loop you can vectorize.

## Build settings

Link frameworks: `-framework CoreAudio -framework AudioToolbox -framework Accelerate` (add `CoreFoundation` implicitly via the others). Minimum practical deployment target for samples here: macOS 12+. Compile C++ with `-std=c++17` or later.

## References

- `references/code-samples.md` — working code for the tasks in the table above. Read the relevant section before implementing; each sample is self-contained and compiles with the build settings above.
- `references/resources.md` — official Apple docs, WWDC sessions, open-source reference projects (BlackHole, Background Music, eqMac), real-time audio articles, and DSP theory links. Use these URLs verbatim when recommending material to the user.
- `references/swift-bridge.md` — connecting a SwiftUI app to the C++ engine: Objective-C++ wrapper vs. direct Swift/C++ interop, real-time-safe bridge design (control plane vs. data plane), and the MenuBarExtra app pattern. Read whenever the task touches the GUI↔engine boundary.
