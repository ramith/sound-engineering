# 🤝 Handoff: Adaptive Sound Engineering

**From:** Laptop 1 (current)  
**To:** Laptop 2  
**Date:** 2026-06-16, 04:15 AM IST  
**Prepared at:** `git log --oneline | head -1` → commit `bbc0280`  
**Status:** Phase 0 complete, Phase 1 DSP ready to begin  
**Next session ETA:** 2026-06-16, whenever you switch laptops  

---

## 📊 Project Status Summary

### ✅ COMPLETE: Phase 0 (Audio Infrastructure)
- **Commit:** `bbc0280` (latest main)
- Playback infrastructure locked (AVAudioEngine + render callbacks)
- EQ consolidation (single canonical preset source)
- Parameter ramping with one-pole RC filters
- Intensity bypass (bit-exact passthrough at intensity=0)
- FTZ/DAZ denormal handling
- Null test framework (8 passing tests)
- Code review fixes: 50+ files refactored, deprecated APIs migrated, C++ type safety improved

### 🚀 NEXT: Phase 1 DSP Modules (Priority Order)
1. **Limiter** (true-peak ceiling enforcement, ~8ms GR latency)
2. **Loudness** (LUFS normalization per ITU-R BS.1770)
3. **Clarity** (spectral presence enhancement)
4. **BRIR** (binaural room impulse response spatial audio)

**Target shipping:** Phase 1b with Limiter + Loudness (hearing-safe playback)

---

## 🐛 Recent Bug Fixes (2026-06-16)

### Fixed: Stack Overflow in File Picker
**Commits:** `cec9f03`, `bbc0280`

**Bug 1 (cec9f03):** Infinite recursion in folder monitoring
```
fileImporter → loadMusicFolder(url) → musicFolderURL = url (didSet fires)
→ startFolderMonitoring() → file system event → loadMusicFolder(url) again → loop
```
**Fix:** Move `musicFolderURL` assignment to file picker handler only.

**Bug 2 (bbc0280):** Infinite recursion in Repeat button
```
cycleRepeatMode() → repeatMode = (repeatMode + 1) % 3 (didSet fires)
→ didSet handler does `repeatMode = repeatMode % 3` → didSet again → loop
```
**Fix:** Remove modulo from didSet (redundant; cycleRepeatMode already ensures valid range).

**Lesson:** Never modify a property inside its own didSet—SwiftUI's @Observable will recurse infinitely.

---

## 🎯 Key Architecture Decisions

### Audio Engine
- **File:** `Sources/AudioDSP/AudioEngine/AUAudioUnit.mm` + Swift bridge
- **Pattern:** Objective-C++ wrapper (AudioEngineBridge.swift) → C++ core
- **Real-time:** Render callbacks on dedicated thread, lock-free parameter passing via atomics
- **Null test:** DSPKernel must produce bit-identical output at intensity=0 (verified by 8 tests)

### Playlist & File Enumeration
- **File:** `Sources/AdaptiveSound/UI/Playlist/PlaylistView.swift`
- **Enumeration:** Recursive via `FileManager.enumerator` with `.skipsHiddenFiles` + `.skipsPackageDescendants`
- **Monitoring:** FSEvents-based folder monitoring (debounced 100ms) auto-reloads playlist on changes
- **State:** @Observable AudioViewModel, stored in `playlist: [AudioFile]`

### EQ Module
- **Canonical source:** `EQPreset` enum in AudioViewModel (single source of truth for preset gains)
- **UI binding:** EQTabView → @Environment(EQViewModel) → Binding to bandGains
- **Dispatch:** bandGains changes → audioViewModel.updateEQBands() → DSP kernel
- **Null test:** Identity (numBiquads=0, masterGainLinear=1) verified as bit-exact passthrough

### State Management
- **@MainActor:** AudioViewModel (main thread only, safe from race)
- **@Observable:** Modern Swift 6 pattern (no @Published needed)
- **Atomics:** Lock-free parameter passing (masterGain, intensity) on audio thread
- **Debouncing:** Folder monitor changes debounced 100ms to avoid thrashing

---

## 🛠️ Development Setup

### Prerequisites
```bash
# macOS 12+ (Monterey or newer)
# Xcode 15.4+ with Swift 6.0+
# Checked via: swift --version

# Clone and build
git clone https://github.com/ramith/sound-engineering.git
cd sound-engineering
swift build

# Run tests
swift test

# Run app
swift run AdaptiveSound
```

### Build Settings
- **Deployment target:** macOS 12
- **Swift version:** 6.0
- **C++ standard:** C++17
- **Frameworks:** CoreAudio, AudioToolbox, Accelerate
- **Pre-commit hook:** Runs null tests + format + lint (never skip with `--no-verify`)

### Key Build Directories
- **Sources/AudioDSP/:** C++ DSP kernel (real-time audio processing)
- **Sources/AdaptiveSound/:** Swift UI + view models
- **Tests/DSPKernelNullTest.cpp:** Standalone null test (executable, 8 test cases)
- **Tests/AudioDSPTests/:** Swift testing bridge to C++ modules

---

## 📁 Critical Files (Don't Delete)

| File | Purpose | Status |
|------|---------|--------|
| `Sources/AudioDSP/DSPKernel.h` + `.mm` | Main audio processing pipeline | **Locked** |
| `Sources/AudioDSP/EQ/EQModule.h` + `.mm` | Biquad filter bank + parameter ramping | **Locked** |
| `Sources/AdaptiveSound/Models/EQPreset.swift` | Canonical EQ preset data | **Single source of truth** |
| `Tests/DSPKernelNullTest.cpp` | Null test (identity + bypass verification) | **Pre-commit gate** |
| `.git/hooks/pre-commit` | Auto-runs null test before every commit | **Do not disable** |
| `Sources/AdaptiveSound/AudioViewModel.swift` | Main state controller | **Recently debugged** |

---

## 📖 File Reference Guide: Which Files to Read for Different Tasks

### **To Understand Real-Time Audio Processing**
1. **START HERE:** `Sources/AudioDSP/DSPKernel.h` (read header comments, ~80 lines)
   - Explains real-time constraints, null-test requirement, module pipeline
2. **THEN READ:** `Sources/AudioDSP/DSPKernel.mm` (process method, lines 1–150)
   - See how modules are called in sequence
   - Understand parameter passing via atomics
3. **DEEP DIVE:** `Sources/AudioDSP/include/TargetState.h` (entire file)
   - State struct that bridges Swift UI → C++ audio thread

### **To Implement Phase 1 Modules (Limiter/Loudness/Clarity/BRIR)**
1. **Reference template:** `Sources/AudioDSP/EQ/EQModule.h` + `.mm`
   - Shows how to structure a DSP module
   - Parameter handling, null-test pattern, vDSP usage
2. **Add to TargetState:** `Sources/AudioDSP/include/TargetState.h` (add your LimiterParameters struct)
3. **Wire into kernel:** `Sources/AudioDSP/DSPKernel.mm` (add module call in process method)
4. **Test template:** `Tests/DSPKernelNullTest.cpp` (lines 754–761)
   - Copy the Limiter test stub; implement your module's null test

### **To Understand Swift/UI State Management**
1. **Main controller:** `Sources/AdaptiveSound/AudioViewModel.swift` (lines 76–150)
   - @MainActor @Observable pattern
   - Property didSet patterns (see memory: [[didset-recursion-gotcha]])
2. **View binding example:** `Sources/AdaptiveSound/UI/Playlist/PlaylistView.swift`
   - How fileImporter works (lines 31–43)
   - How @Environment passes state to views
3. **ViewModel pattern:** `Sources/AdaptiveSound/Models/EQPreset.swift`
   - Canonical data source (single source of truth)

### **To Debug Audio Issues**
1. **Check state:** `Sources/AdaptiveSound/AudioViewModel.swift` (lines 79–140)
   - `isEngineReady`, `selectedDevice`, `isPlaying`, `errorMessage`
2. **Trace dispatch:** Search for `setParameter` in AudioViewModel
   - Shows how parameter changes reach DSP kernel
3. **Verify device:** `Sources/AudioDSP/AudioEngine/AUAudioUnit.mm` (render callback)
   - Where audio actually flows; add logging here if silent playback

### **To Fix UI Crashes**
1. **First read:** HANDOFF.md section "How to Debug" (above)
2. **Stack overflow?** → Check memory: [[didset-recursion-gotcha]]
3. **View not updating?** → `Sources/AdaptiveSound/AudioViewModel.swift` (check @Observable)
4. **Button not responsive?** → `Sources/AdaptiveSound/UI/Playlist/PlaylistView.swift` (check action handlers)

### **To Modify EQ**
1. **Presets:** `Sources/AdaptiveSound/Models/EQPreset.swift` (canonical data)
2. **UI controls:** `Sources/AdaptiveSound/UI/EQ/EQControlsSection.swift` (sliders)
3. **Canvas display:** `Sources/AdaptiveSound/UI/EQ/FrequencyResponseCanvas.swift` (visual)
4. **DSP implementation:** `Sources/AudioDSP/EQ/EQModule.h` + `.mm` (locked, don't change)

### **To Run Tests**
1. **Null test (C++):** `Tests/DSPKernelNullTest.cpp` (run: `./Tests/DSPKernelNullTest`)
2. **Swift tests:** `Tests/AudioDSPTests/EQTests.swift` (run: `swift test`)
3. **All tests:** `swift test` (runs everything)

### **To Understand the Architecture**
1. **Quick overview:** HANDOFF.md section "Key Architecture Decisions" (above)
2. **Swift/C++ bridge:** `Sources/AdaptiveSound/AudioEngineBridge.swift` + `Sources/AdaptiveSound/UI/Playlist/PlaylistView.swift`
3. **Real-time rules:** `Sources/AudioDSP/DSPKernel.h` (header comments)

### **For Phase 1 Implementation Checklist**
1. Read: `Sources/AudioDSP/EQ/EQModule.h` (module template)
2. Copy: Structure to `Sources/AudioDSP/Limiter/LimiterModule.h`
3. Update: `Sources/AudioDSP/include/TargetState.h` (add LimiterParameters)
4. Implement: `Sources/AudioDSP/Limiter/LimiterModule.mm` (process method)
5. Wire: `Sources/AudioDSP/DSPKernel.mm` (call limiter in process)
6. Test: `Tests/DSPKernelNullTest.cpp` (add null test, verify 8/8 pass)
7. Commit: `git commit -m "..."` (pre-commit hook runs null test automatically)

---

## 🔍 How to Debug

### Stack Overflow / Infinite Recursion
**Signs:** "Thread stack size exceeded due to excessive recursion" in crash log
**Causes:** 
- Property didSet modifying the same property (fixed in phase 0)
- Circular view dependencies in SwiftUI
- Recursive folder monitoring (fixed in phase 0)

**Fix:** 
1. Search for properties with didSet that modify themselves
2. Check fileImporter/folder monitoring handlers for feedback loops
3. Use Xcode's Call Stack navigator to find the recursive function

### Audio Not Playing
**Checks:**
1. Is `isEngineReady` true? (Check in AudioViewModel)
2. Does `selectedDevice` exist? (Device enumeration working?)
3. Is `isPlaying` true? (Playback started?)
4. Check `errorMessage` property for engine errors

**Debug output:**
```swift
// In AudioViewModel.startPlayback()
print("Playing track: \(selectedTrackIndex ?? -1)")
print("Engine ready: \(isEngineReady)")
print("Errors: \(errorMessage ?? "none")")
```

### EQ Not Responding
**Check path:** 
1. EQTabView → EQViewModel.selectedPreset changed?
2. EQViewModel.didSet calls audioViewModel.updateEQBands()?
3. updateEQBands → DSP kernel setParameter call?
4. Run null test: `./Tests/DSPKernelNullTest` (should be 8/8 pass)

---

## 📝 Code Review Findings Status

**All fixed in commit a2fb92a + cec9f03 + bbc0280:**
- ✅ Deprecated API migrations (Task.detached, .cornerRadius, Task.sleep, String.format)
- ✅ Accessibility: icon labels, font sizes
- ✅ File structure: 30+ files split to single-type-per-file
- ✅ C++ type safety: void* → std::unique_ptr
- ✅ Memory ordering clarity: acquire → relaxed loads
- ✅ Test bridging: EQ tests now call real EQModule
- ✅ Pre-commit hook: enforces null test passing

**No open code review findings.**

---

## 🚀 Next Steps for Phase 1

### 1. Limiter Implementation
- **File:** `Sources/AudioDSP/Limiter/LimiterModule.h` + `.mm` (create new)
- **Algorithm:** True-peak lookahead (8ms @ 48kHz), gain reduction curve
- **State:** Stores 384 sample ring buffer + GR envelope
- **Test:** Add to DSPKernelNullTest — verify bypass at ceiling ≥ 1.0

### 2. Loudness Normalization
- **File:** `Sources/AudioDSP/Loudness/LoudnessModule.h` + `.mm` (create new)
- **Standard:** ITU-R BS.1770-4 (LUFS measurement + normalization)
- **Integration:** Runs pre-Limiter (level → dynamics → limiting → true-peak)
- **Test:** Measure output LUFS with ffmpeg; verify matches target

### 3. Clarity Enhancement
- **Type:** Multi-band spectral enhancement (presence boost 2–5 kHz)
- **Implementation:** Parallel biquad filters, blended by clarity slider
- **Test:** Sweep input 20–20k Hz, measure output frequency response

### 4. BRIR Spatial Audio
- **Type:** Binaural room impulse response convolution
- **Files:** Pre-recorded HRTF impulses (KEMAR database, public domain)
- **Integration:** Runs post-clarity, before true-peak limiting
- **Latency:** ~512 samples @ 48 kHz (~11ms) for FFT convolution

---

## 🎓 Learning Resources (In Project)

- **Architecture Decision Records (ADRs):** See project root (none written yet—consider adding)
- **Code comments:** Real-time rules in DSPKernel.h, RBJ biquad references in EQModuleCoefficients.h
- **Test examples:** DSPKernelNullTest.cpp (7 null tests), EQTests.swift (3 end-to-end)

---

## ⚠️ Gotchas & Known Limitations

1. **No true-peak metering yet** — Limiter placeholder at ceiling ≥ 1.0 (phase 1b)
2. **Folder monitor events fire aggressively** — Debounced 100ms; may miss rapid file changes
3. **Device enumeration is real** — Switching devices may temporarily pause playback (expected)
4. **EQ presets don't save** — State is ephemeral; no persistence (phase 2)
5. **Spectrum analyzer runs at 20 Hz** — UI-thread safe, but may lag on slow machines

---

## 📞 Quick Reference: Common Commands

```bash
# Build
swift build

# Test (all suites)
swift test

# Run null test (standalone)
./Tests/DSPKernelNullTest

# Format & lint
swift format -i Sources/ Tests/
swiftlint --fix

# Run app
swift run AdaptiveSound

# Check git status before committing
git status
git diff (review changes)

# Commit with pre-commit hook
git commit -m "Your message"  # Hook runs automatically

# Check recent commits
git log --oneline -10
```

---

## 🏁 Handoff Checklist

- [ ] Clone repo on new laptop
- [ ] Run `swift build` (should succeed with no errors)
- [ ] Run `swift test` (8 null tests + others should pass)
- [ ] Review this document + memory entries
- [ ] Open Xcode: `xed .`
- [ ] Familiarize with AudioViewModel + AudioEngine architecture
- [ ] Read DSPKernel.h (understand real-time constraints)
- [ ] Start Phase 1: Create LimiterModule.h + skeleton implementation
- [ ] Add Limiter tests to DSPKernelNullTest.cpp
- [ ] Commit & push when ready

---

## 📚 Files You'll Touch First (Phase 1)

1. `Sources/AudioDSP/Limiter/LimiterModule.h` (create)
2. `Sources/AudioDSP/Limiter/LimiterModule.mm` (create)
3. `Sources/AudioDSP/DSPKernel.mm` (add Limiter to process chain)
4. `Tests/DSPKernelNullTest.cpp` (add Limiter bypass test)
5. `Sources/AudioDSP/include/TargetState.h` (add Limiter parameters)

---

**Questions?** See memory entries for recent decisions + debugging patterns.  
**Ready to ship Phase 1?** Start with Limiter—highest priority for 1b hearing-safe playback.
