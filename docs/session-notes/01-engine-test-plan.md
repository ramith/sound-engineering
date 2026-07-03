# Sprint 1 (US-ENG-01) Test & Validation Plan
## Audio Engine Foundation — Core Audio Device Enumeration & AUHAL Render Loop

> **⚠️ HISTORICAL / SUPERSEDED (Sprint 1 planning doc).** The Swift/XCTest suites and `swift test` gates described below were **never built that way**. The actual DSP gate is the **C++ null-test harness** (`bash scripts/build-null-test.sh`, golden master `0xE7267654BA01D315`); `swift test` is broken here (Swift mock tests run in Xcode). Engine coverage is via the C++ harness + the `VerifyAUGraph` offline-render executable. Retained for provenance only — do not use as live test guidance.

**Document ID:** SPRINT-1-TEST-001  
**Version:** 1.0  
**Date:** 2026-06-13  
**Author:** QA Review  
**Status:** Ready for Sprint 1 Execution  

---

## Executive Summary

Sprint 1 ships the **audio engine foundation**: Core Audio device enumeration, device listener callbacks, and the AUHAL render callback loop running at 512 frames / 48 kHz on M1 Pro without XRuns or audio-thread violations. This plan ensures zero memory safety issues on the real-time thread, validates callback reliability, and confirms device hot-swap resilience.

**Pass Criteria:** Engine initializes, audio thread runs callback-free, device changes are detected and handled, no XRuns logged, manual testing sign-off.

---

## Test Breakdown & Coverage

### 1. Unit Tests (Device Enumeration, Lifecycle)

**Scope:** Core Audio property enumeration, callback wiring, memory allocation strategy.

| Test ID | Category | Focus | Pass Criteria |
|---------|----------|-------|---------------|
| **UT-ENG-01** | Device Enum | Enumerate available output devices via `AudioObjectGetPropertyData` | ≥1 device found; device names non-empty; unique IDs assigned |
| **UT-ENG-02** | Device Enum | Filter by device type (headphones, speakers, aggregate) | Correct device type classification; no crashes on malformed device list |
| **UT-ENG-03** | Device Enum | Detect default output device on init | Default device matches system preference; handles "no device" gracefully |
| **UT-ENG-04** | Listener Callback | Install / uninstall `kAudioObjectPropertyListeners` without leaks | Callbacks triggered on property changes; no dangling listener refs |
| **UT-ENG-05** | Memory | Pre-allocate all buffers (engine state, listener queue, render scratch) before audio thread starts | No heap allocs detected on RT thread (ASAN in RT-safe mode) |
| **UT-ENG-06** | Lifecycle | Initialize engine once; multiple shutdown/re-init cycles | No crashes, no resource leaks (valgrind / ASAN on close) |

**Tools:**  
- XCTest (C++ bridging via `@testable` import)  
- ASAN with `malloc_stack=1` to catch heap allocs on audio thread  
- Valgrind for leak detection (off-RT path)

---

### 2. Integration Tests (Render Callback, Device Switching)

**Scope:** Real-time callback execution, device listener wakeup, parameter snapshots.

| Test ID | Category | Focus | Pass Criteria |
|---------|----------|-------|---------------|
| **IT-ENG-01** | Render Loop | Start AVAudioEngine; verify render callback invokes at expected buffer count (512 frames) | Callback fires ≥100 times without stall; frame count = 512 per invocation |
| **IT-ENG-02** | Render Loop | Measure callback latency (time from audio thread wake to callback return) | Mean latency ≤5 ms; max latency ≤10 ms (no glitch threshold) |
| **IT-ENG-03** | Device Listener | Simulate device change (unplug headphones, switch to speakers via System Preferences) | Listener callback fires within 100 ms; engine re-routes output without audio drop |
| **IT-ENG-04** | Device Listener | Hot-swap device during playback; verify no crash | App remains responsive; playback continues on new device; no audio gap >50 ms |
| **IT-ENG-05** | Parameter Snapshot | Store device list on audio thread; read on control thread without locks | Lock-free atomics verify: device list snapshot updated, no data race (ThreadSanitizer pass) |
| **IT-ENG-06** | Silence Path | Engine started but no input source; render callback still invokes | Callback produces silence (zeros) at 512 FPS without glitches |

**Tools:**  
- XCTest with real AVAudioEngine instance (macOS test target)  
- System Trace (Instruments `os_signpost`) to mark callback entry/exit, measure duration  
- ThreadSanitizer (`-fsanitize=thread`) to catch lock-free data races  
- Manual device hot-swap testing on M1 Pro (AirPods, Thunderbolt dock, USB DAC)

---

### 3. Real-Time Safety Validation

**Scope:** Verify audio thread is free of allocations, I/O, locks.

| Test ID | Focus | Method | Pass Criteria |
|---------|-------|--------|---------------|
| **RT-SAFE-01** | Heap Alloc | Run ASAN with RT-aware config; log any malloc/free on callback | ASAN output: zero allocations on audio thread |
| **RT-SAFE-02** | I/O | Audit render callback code: no `open()`, `read()`, `write()`, file ops | Code review + grep for POSIX I/O in callback body |
| **RT-SAFE-03** | Locks | Audit for `pthread_mutex_lock()`, `std::mutex`, `@synchronized` on audio thread | Code review + grep; use only `std::atomic<>` for cross-thread state |
| **RT-SAFE-04** | Obj-C Runtime | No Swift runtime, no Obj-C message sends on audio thread | Verify C++ kernel is called directly; no `objc_msgSend` in callback |
| **RT-SAFE-05** | Bounded Work | Measure CPU time per buffer on real hardware (M1 Pro) | Single buffer ≤ ~2 ms (512 @ 48 kHz = 10.67 ms per buffer; allow <20% CPU headroom) |

**Tools:**  
- ASAN (AddressSanitizer) in RT mode: `ASAN_OPTIONS=halt_on_error=1:sanitizer_coverage=inline`  
- Clang static analyzer (`scan-build`) to detect I/O and lock calls  
- Xcode Instruments "System Trace" to log CPU time per buffer  
- Manual flamegraph profiling (Instruments → Time Profiler)

---

### 4. XRun & Glitch Detection

**Scope:** Verify zero underruns / overruns; detect audio artifacts.

| Test ID | Focus | Method | Pass Criteria |
|---------|-------|--------|---------------|
| **GLITCH-01** | XRun Logging | Enable `kAudioDevicePropertyIORunning` listener; log any discontinuities | XRun count = 0 over 60-second playback session |
| **GLITCH-02** | Dropout Detection | Playback white noise / tone; analyze output in Audacity for gaps | No gaps / clicks / pops detected in 10-minute session |
| **GLITCH-03** | System Load | Run during 80% CPU load (background processes); verify no XRuns | XRun count = 0 even under contention (shows RT thread priority is working) |
| **GLITCH-04** | Buffer Boundary | Check if render callback respects buffer boundary timing from `AudioTimeStamp` | `mSampleTime` advances monotonically by 512 each invocation |

**Tools:**  
- Custom listener callback that increments counter on `kAudioDevicePropertyIORunning = false`  
- Audacity (manual listening test with artifact detection plugin or spectrogram analysis)  
- `stress-ng` (background CPU load simulator)  
- System Trace → Audio subsystem events (check `AUHostingModel` and callback timing)

---

### 5. Device Hot-Swap Testing

**Scope:** Resilience to device connect/disconnect during playback.

| Test ID | Scenario | Steps | Pass Criteria |
|---------|----------|-------|---------------|
| **HS-01** | Headphone unplug | Start playback on AirPods → unplug AirPods mid-track | Audio switches to built-in speakers; playback continues <100 ms latency |
| **HS-02** | Headphone plug | Speakers active → plug in AirPods → device switches | Audio routes to AirPods; no stall, no pop |
| **HS-03** | USB DAC connect | Playback on built-in → connect USB DAC → auto-switch | Engine detects USB DAC; playback continues on USB output; device name updated in UI |
| **HS-04** | Multiple rapid swaps | Plug/unplug AirPods 5× in 10 seconds | Engine remains stable; no crash; listener callback queue doesn't overflow |
| **HS-05** | Device list mutation | Enumerate devices before/after hot-swap | Device list reflects new state; old device ID no longer present |

**Tools:**  
- Manual testing with real hardware (AirPods Pro, Thunderbolt dock, USB DAC if available)  
- Instrumentation in device listener callback (log timestamp + device ID)  
- XCTest mock device listener (simulate `kAudioObjectPropertyListeners` event without physical hardware)

---

### 6. Manual Testing Checklist

**Tester:** Founder / QA lead  
**Duration:** ~30 minutes  
**Acceptance:** All items ✓ Pass

```
[ ] Engine initializes without crash on app launch
    → Console output shows "Audio engine ready"
    
[ ] Device enumeration displays ≥1 device
    → Device name, type, sample rate visible in debug logs
    → Default device matches system preference
    
[ ] Render callback runs
    → System Trace shows callback firing at 512-frame interval
    → No gaps or stalls in callback execution
    
[ ] Hot-swap (AirPods)
    → Start playback on built-in speaker
    → Connect AirPods → playback switches within 1 second
    → Audio is clean (no click, pop, or dropout)
    
[ ] Hot-swap (unplug)
    → Playback on AirPods
    → Unplug AirPods → playback continues on built-in speaker
    → No audio glitch or stall
    
[ ] Device listener callback
    → Trigger device change in System Preferences
    → Device listener fires within 100 ms (log timestamp)
    → Engine remains responsive during device switch
    
[ ] App stability
    → App runs for 10 minutes of continuous playback
    → No memory leaks (Xcode Memory Debugger clean)
    → No console warnings or errors (grep for "error", "exception", "crash")
    
[ ] Performance (M1 Pro, 512-frame buffer, 48 kHz)
    → CPU usage while idle (no playback) < 2%
    → CPU usage during playback + enumeration < 5%
    → No sustained CPU spike above 10%
    
[ ] Code quality
    → Clang static analyzer: zero warnings
    → ASAN: zero memory violations
    → ThreadSanitizer: zero data races
```

---

## Tools & Instrumentation Summary

| Tool | Purpose | Configuration |
|------|---------|----------------|
| **XCTest** | Unit + integration tests | Native to Xcode; bridging header for C++ |
| **ASAN** | Heap alloc detection on RT thread | `-fsanitize=address -g`; log to stderr |
| **ThreadSanitizer** | Lock-free data race detection | `-fsanitize=thread`; run on single-core to isolate races |
| **System Trace (Instruments)** | Callback timing, CPU profiling | `os_signpost` markers in callback entry/exit |
| **clang static analyzer** | I/O / lock call detection | `scan-build xcodebuild` |
| **Valgrind** | Leak detection (off-RT) | `valgrind --leak-check=full` (macOS via Homebrew) |
| **Audacity** | Manual glitch detection | Open output.wav; listen + inspect spectrogram |
| **Xcode Memory Debugger** | Live heap inspection | Pause during playback; verify allocation patterns |

---

## Test Execution Schedule

| Phase | When | Owner | Duration |
|-------|------|-------|----------|
| **Unit Tests** | Daily (per commit) | CI pipeline (or manual pre-push) | ~2 min |
| **Integration Tests** | End of day (before commit) | Developer | ~10 min |
| **RT Safety** | Pre-merge (before PR review) | Developer + automated CI | ~3 min |
| **Manual Tests** | Friday end-of-day (sprint review) | Founder | ~30 min |
| **Hot-swap Tests** | Friday (with real devices) | Founder | ~15 min |

---

## Pass Criteria (Done-Done)

Sprint 1 is **complete** when all of the following are true:

1. ✅ **Unit tests pass:** UT-ENG-01 through UT-ENG-06 (XCTest, 100% pass)  
2. ✅ **Integration tests pass:** IT-ENG-01 through IT-ENG-06 (no crashes, callback timing within bounds)  
3. ✅ **RT safety:** ASAN / ThreadSanitizer / static analyzer output is clean (zero violations)  
4. ✅ **XRuns:** System Trace + listener logs show 0 XRuns over 60-second playback  
5. ✅ **Manual testing sign-off:** Founder completes checklist; all items ✓ Pass  
6. ✅ **Code reviewed:** No blocking feedback on real-time safety or device handling  
7. ✅ **Documentation:** Code comments explain device enumeration, listener callback, render loop lifecycle  

---

## Known Risks & Gaps

| Risk | Mitigation |
|------|-----------|
| **Device list change mid-callback** | Use atomic snapshot for device list; listener updates a pending-change flag, not the active list. Reallocate on next control-thread cycle. |
| **Aggregate device enumeration** | Only enumerate simple output devices; aggregate device support is Phase 2 (too complex for Sprint 1). |
| **Sample rate mismatch** | AVAudioEngine handles SRC (sample-rate conversion) transparently; log if hardware differs from 48 kHz. |
| **Headphones with low buffer size** | M1 Pro + AirPods stable at 512 frames; if user sets <256 frames system-wide, XRuns may occur — document minimum supported buffer size. |
| **No background playback** | App is foreground-only (LD-19); backgrounding stops audio engine. Test this boundary. |

---

## References

- **Architecture.md § 3 (Foundation):** Core Audio + AUAudioUnit v3 design  
- **Requirements.md § FR-SYS (System Integration):** Device enumeration & listener requirements  
- **Sprint-plan.md:** Done-done template & acceptance criteria  
- **Apple Core Audio Documentation:** `AudioObjectGetPropertyData`, `AudioDeviceIOProcID`, `AudioTimeStamp`  
- **Xcode Instruments:** System Trace, Time Profiler, Memory Debugger user guides

---

## Post-Sprint Validation (Code Review Checklist)

Before merging to main, reviewer should verify:

- [ ] All test files committed to `/Tests/AudioEngineTests.swift` (XCTest)  
- [ ] Test coverage report shows ≥80% coverage for `AudioEngine.cpp`  
- [ ] No TODOs or FIXMEs left in render callback  
- [ ] Memory management: all allocations happen in constructor/init, none in `render()` callback  
- [ ] Device listener callback uses only atomic operations (no locks)  
- [ ] System Trace demonstrating callback timing included in PR description  
- [ ] Manual test results (photos / videos of hot-swap, glitch testing) attached to PR  

