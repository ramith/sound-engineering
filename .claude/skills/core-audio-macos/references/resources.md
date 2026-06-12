# Core Audio Resources — Authoritative Sources

Use these URLs verbatim when recommending material. Prefer Apple primary
sources first, reference implementations second, community material last.
Modern developer.apple.com/documentation pages are JS-rendered — when you need
their content programmatically, prefer the Documentation Archive pages or the
local SDK headers instead.

## Apple primary documentation

- Core Audio framework reference (browse, JS-rendered):
  https://developer.apple.com/documentation/coreaudio
- AudioToolbox framework reference:
  https://developer.apple.com/documentation/audiotoolbox
- Accelerate / vDSP reference:
  https://developer.apple.com/documentation/accelerate/vdsp
- Core Audio Overview / Essentials (archive; static HTML, fetchable; the best
  conceptual document — ASBDs, audio units, the HAL):
  https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/CoreAudioEssentials/CoreAudioEssentials.html
- TN2091 — Device input using the HAL Output Audio Unit (canonical AUHAL
  document with code listings):
  https://developer.apple.com/library/archive/technotes/tn2091/_index.html
- QA1811 — AudioServerPlugIn environment & MachServices key:
  https://developer.apple.com/library/archive/qa/qa1811/_index.html
- vDSP Programming Guide (archive):
  https://developer.apple.com/library/archive/documentation/Performance/Conceptual/vDSP_Programming_Guide/
- SDK headers (canonical modern reference, available locally):
  `xcrun --show-sdk-path` →
  `System/Library/Frameworks/CoreAudio.framework/Headers/AudioHardware.h`,
  `AudioHardwareBase.h`, `AudioServerPlugIn.h`;
  `AudioToolbox.framework/Headers/AUComponent.h`, `AudioConverter.h`.

## Apple sample code & WWDC

- CAPlayThrough (two-AUHAL play-through with CARingBuffer; linked from
  TN2091): https://developer.apple.com/library/archive/samplecode/CAPlayThrough/Introduction/Intro.html
- Creating an Audio Server Driver Plug-in (current Apple sample for virtual
  devices): https://developer.apple.com/documentation/coreaudio/creating-an-audio-server-driver-plug-in
- Building an Audio Server Plug-in and Driver Extension (plug-in + dext,
  C++): search "Building an Audio Server Plug-in" at
  https://developer.apple.com/documentation/coreaudio
- Note: QA1811 links the older "AudioDriverExamples" sample, which Apple has
  retired (the URL now redirects). Use the two samples above instead. Per
  Apple (WWDC21 session 10190 and Developer Forums guidance), AudioDriverKit
  is NOT granted entitlements for virtual audio devices — AudioServerPlugIn
  remains the required model for virtual devices.
- WWDC21 — Create audio drivers with DriverKit (confirms AudioServerPlugIn is
  not deprecated): https://developer.apple.com/videos/play/wwdc2021/10190/
- WWDC session search: https://developer.apple.com/videos/ (filter: Audio)

## Reference implementations (open source)

- BlackHole — modern, minimal AudioServerPlugIn virtual device:
  https://github.com/ExistentialAudio/BlackHole
- Background Music — virtual device + companion app with mach IPC; its
  DEVELOPING.md is a guided tour of HAL plug-in code:
  https://github.com/kyleneideck/BackgroundMusic
- eqMac — open-source system-wide EQ for macOS (the product category of a
  system sound enhancer): https://github.com/bitgapp/eqMac
- JUCE — its CoreAudio wrapper code is instructive even if not adopted:
  https://github.com/juce-framework/JUCE
- libASPL — C++17 library that wraps the AudioServerPlugIn boilerplate
  (property dispatch, CF types) behind typed C++ classes:
  https://github.com/gavv/libASPL

## Real-time audio programming

- Ross Bencina — "Real-time audio programming 101: time waits for nothing"
  (the canonical article on audio-thread discipline):
  http://www.rossbencina.com/code/real-time-audio-programming-101-time-waits-for-nothing
- Audio Developer Conference talks (free):
  https://www.youtube.com/@audiodevcon
- TPCircularBuffer (well-tested lock-free ring buffer):
  https://github.com/michaeltyson/TPCircularBuffer

## DSP theory

- Julius O. Smith free online DSP books (Stanford CCRMA):
  https://ccrma.stanford.edu/~jos/
- Audio EQ Cookbook (biquad coefficient formulas):
  https://www.w3.org/TR/audio-eq-cookbook/
- musicdsp.org code archive: https://www.musicdsp.org/

## Book

- *Learning Core Audio*, Adamson & Avila (2012) — dated but the only
  book-length treatment; the C API it teaches is largely unchanged.

## Communities

- Apple Developer Forums (Core Audio tag):
  https://developer.apple.com/forums/tags/core-audio
- The Audio Programmer (Discord + YouTube):
  https://www.theaudioprogrammer.com/
- Stack Overflow `core-audio` tag.
