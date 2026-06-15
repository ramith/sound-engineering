# Development Guide — AdaptiveSound

This document covers coding standards, tooling, and guardrails to maintain code quality, especially for C++ real-time audio code and Swift UI/control-plane safety.

## Tool Setup

**Required:**
```bash
# Format for C++ (included with Xcode)
clang-format --version

# Format for Swift
brew install swiftformat

# Lint for Swift
brew install swiftlint

# Verify
swiftformat --version
swiftlint --version
```

**Recommended (for C++ static analysis):**
```bash
# Install LLVM toolchain with clang-tidy
brew install llvm

# Verify
/opt/homebrew/opt/llvm/bin/clang-tidy --version
```

**Why clang-tidy is optional but recommended:**
- Catches subtle C++ bugs (nullptr dereferences, use-after-free, data races)
- Enforces Core Guidelines at build time
- Prevents hard-to-debug audio glitches

Pre-commit hooks will warn if clang-tidy is missing and gracefully skip static analysis. All tools run automatically on `git commit`. No manual execution needed unless debugging locally.

---

## Code Style & Enforcement

### Automatic Formatting

**C++ Code**
```bash
clang-format -i Sources/AudioDSP/**/*.{h,cpp}
```

**Swift Code**
```bash
swiftformat Sources/AdaptiveSound/
```

Both formatters run automatically on save in VS Code and are enforced via pre-commit hooks.

### Pre-Commit Hooks

The hook lives in version control at `.githooks/pre-commit`. Activate it once per clone:

```bash
git config core.hooksPath .githooks
```

It then runs automatically on `git commit` and:
1. **Formats** staged Swift/C++/Obj-C++ files (swiftformat, clang-format) and re-stages them
2. **Lints** staged Swift with swiftlint — error-severity violations block the commit
3. **Static-analyses** staged C++ with clang-tidy — failures block the commit (gracefully skipped with a warning if clang-tidy is not installed)

Bypass once (not recommended): `git commit --no-verify`. No need to run manually unless debugging.

---

## Swift Control Plane Best Practices

Swift runs on the **UI/control plane** (not the audio render thread), so the constraints are different from C++. However, care is still needed when communicating with the C++ audio engine.

### MUST DO (Swift/UI Thread Safe)

✅ **Use Sendable types for thread-safe communication**
```swift
// Define a Sendable param message
struct AudioGainMessage: Sendable {
    let newGain: Float
    let timestamp: UInt64
}

// Send to audio engine via lock-free bridge
audioEngine.setGain(message)
```

✅ **Use `@MainActor` for UI updates**
```swift
@MainActor
class AudioViewModel: ObservableObject {
    @Published var status = "Initializing"

    // Must run on main thread
    func updateStatus(_ newStatus: String) {
        self.status = newStatus
    }
}
```

✅ **Keep bindings simple — observe, don't mutate**
```swift
@State private var gain: Float = 1.0

var body: some View {
    Slider(value: $gain, in: 0...1)
        .onChange(of: gain) { oldVal, newVal in
            // Pass to audio engine off-main-thread
            Task.detached {
                await audioEngine.setGain(newVal)
            }
        }
}
```

---

### MUST NOT (Control Plane Mistakes)

❌ **Synchronous calls to audio engine (can block rendering)**
```swift
// BAD — blocks main thread waiting for audio thread
let status = audioEngine.getStatusSync()  // slow!
```

✅ **GOOD — use async/await or atomics**
```swift
// GOOD — non-blocking, uses atomic reads
let status = audioEngine.getStatusAsync()
```

---

❌ **Holding strong references to audio objects from UI**
```swift
// BAD
class ViewController {
    let audioEngine = AudioEngine()  // strong ref, circular?
}
```

✅ **GOOD — weak or unowned references**
```swift
class AudioViewModel: ObservableObject {
    weak var audioEngine: AudioEngineProtocol?
    // Passed in by dependency injection
}
```

---

❌ **Data races on bridged types**
```swift
// BAD — C++ object accessed from multiple threads unsafely
let audioBuffer = audioEngine.getBuffer()  // can be accessed by render thread too!
audioBuffer[0] = 1.0  // data race!
```

✅ **GOOD — use synchronization primitives**
```swift
// Use atomics or lock-free queues for parameter updates
@Atomic private var targetGain = 1.0f

// C++ reads: targetGain.load()
// Swift writes: targetGain.store(newValue)
```

---

## C++ Real-Time Audio Safety Rules

The audio render thread runs on a hard deadline (~10 ms per buffer at 48 kHz / 512 frames). Violating these rules causes glitches that are invisible to testing but audible to users.

### MUST NOT (Audio Thread Forbidden)

❌ **Heap allocation**
```cpp
// BAD — called inside render callback
std::vector<float> buf(frameCount);  // malloc on RT thread
new AudioFrame();  // heap alloc
```

✅ **GOOD — pre-allocate once at init**
```cpp
std::vector<float> buf;  // member variable
void initialize(size_t maxFrames) {
    buf.resize(maxFrames);  // allocate once, off-thread
}
```

---

❌ **Locks that block**
```cpp
// BAD
std::mutex mu;
{
    std::lock_guard<std::mutex> lg(mu);  // can block indefinitely
    // ...
}
```

✅ **GOOD — lock-free atomics**
```cpp
std::atomic<float> gain{1.0f};  // zero-cost, wait-free
// In render: gain.load(std::memory_order_acquire)
```

---

❌ **I/O or logging on hot path**
```cpp
// BAD
OSStatus render(...) {
    printf("rendering frame %d\n", frameNumber);  // system call!
    fwrite(...);  // file I/O
    return noErr;
}
```

✅ **GOOD — defer logging to off-thread**
```cpp
// In render: just set atomic flag
shouldLog.store(true, std::memory_order_release);

// Elsewhere: read flag and log at leisure
if (shouldLog.exchange(false, std::memory_order_acquire)) {
    fprintf(stderr, "event occurred\n");
}
```

---

❌ **Objective-C or Swift runtime calls**
```cpp
// BAD
OSStatus render(...) {
    [NSLog(@"frame %d", frameNum];  // Obj-C runtime
    print("Processing...");  // Swift runtime (if bridged)
}
```

✅ **GOOD — pure C++23**
```cpp
// Pure C++ only on RT thread
OSStatus render(const AudioBufferList *buf, ...) {
    // Process, no language runtime
}
```

---

### MUST DO (Audio Thread Safe)

✅ **Pre-allocate all buffers at initialization**
```cpp
class AudioEngine {
    std::vector<float> workBuffer;
    std::vector<float> filterState;

    void initialize(size_t maxFrames, size_t numChannels) {
        workBuffer.resize(maxFrames * numChannels);
        filterState.resize(numChannels * 2);  // bi-quad state
    }

    OSStatus render(UInt32 inFrames, AudioBufferList *ioData) {
        // Use pre-allocated buffers
        process(workBuffer.data(), ioData, inFrames);
        return noErr;
    }
};
```

✅ **Communicate via lock-free SPSC (Single-Producer, Single-Consumer)**
```cpp
// Control plane (UI thread) writes parameter
std::atomic<float> targetGain{1.0f};

// Audio thread (RT) reads latest value
float gain = targetGain.load(std::memory_order_acquire);
```

✅ **Handle variable frame counts**
```cpp
OSStatus render(UInt32 inFrames, AudioBufferList *ioData) {
    // Never assert or fail on frame count mismatch
    size_t frames = std::min(inFrames, maxFramesPerSlice);
    process(frames);
    return noErr;
}
```

✅ **Use vDSP for vectorized operations**
```cpp
// Process N samples in one call, not per-sample loops
vDSP_vsmul(input, 1, &gain, output, 1, frameCount);
```

---

## Compiler & Linting

### Compiler Flags (Enabled by Default)

**Debug builds** treat warnings as errors:
- `-Wall -Wextra -Wpedantic` — all standard warnings
- `-Wshadow` — catch variable shadowing
- `-Wconversion -Wsign-conversion` — implicit type conversions
- `-Wnull-dereference` — null pointer dereferences
- `-Wold-style-cast` — C-style casts (use `static_cast`)
- `-Werror=all -Werror=conversion` — fail on warnings

**Release builds** are slightly permissive (smaller binary, faster):
- Still `-Wall -Wextra`, but warnings don't fail build

### SwiftLint Analysis

Runs automatically on pre-commit for Swift files. Catches:
- **Naming violations** (variable/function naming conventions)
- **Force unwrapping** (crashes if nil—errors in debug)
- **Redundancy** (unused vars, redundant initializers)
- **Complexity** (functions too long, high cyclomatic complexity)
- **Type safety** (implicit optionals, type inference issues)
- **API usage** (deprecated APIs, discouraged patterns)

**Run manually:**
```bash
swiftlint Sources/AdaptiveSound/
```

**Fix automatically (many rules auto-correctible):**
```bash
swiftlint --fix Sources/AdaptiveSound/
```

**Configure rules** in `.swiftlint.yml` (already set up with strict defaults).

---

### clang-tidy Static Analysis (C++)

Runs automatically on pre-commit. Catches:
- **Core Guidelines violations** (owning pointers, resource leaks)
- **Modernization** (use `nullptr`, not `NULL`; avoid C-style casts)
- **Performance** (unnecessary copies, inefficient algorithms)
- **Concurrency bugs** (data races, deadlocks)
- **UB & memory safety** (out-of-bounds, use-after-free)

**Run manually:**
```bash
clang-tidy Sources/AudioDSP/EQ/EQModule.mm -- -x objective-c++ -std=gnu++2b -fobjc-arc -fblocks -I Sources/AudioDSP/include
```

**Configure rules** in `.clang-tidy` (already set up with audio-safe subset).

---

## Building & Testing

### Debug Build (Full Diagnostics)
```bash
swift build -c debug
```
- All warnings enabled & fail the build
- clang-tidy runs (catches UB, threading bugs)
- Optimizations off (faster compile, slower runtime—OK for dev)

### Release Build (Optimized)
```bash
swift build -c release
```
- Some warnings permissive (smaller, faster binary)
- clang-tidy still catches critical issues
- `-O3` optimization on C++ (real-time safe)

### Run with AddressSanitizer (Catch Memory Bugs)
```bash
# To enable ASAN, add to Package.swift cxxSettings:
.unsafeFlags(["-fsanitize=address"], .when(configuration: .debug))

# Then build & run:
swift build -c debug
swift run AdaptiveSound
```

ASAN reports memory leaks, buffer overruns, use-after-free, etc. in real-time.

---

## Code Review Checklist (Before Commit)

- [ ] **No warnings** — build succeeds with `-Werror`
- [ ] **clang-tidy passes** — pre-commit enforces this
- [ ] **No heap alloc on audio thread** — all buffers pre-allocated
- [ ] **No locks in render callback** — use `std::atomic` only
- [ ] **No I/O or logging on RT path** — defer to off-thread
- [ ] **Variable frame counts handled** — never assert frame size
- [ ] **vDSP used for loops** — no per-sample C++ loops
- [ ] **Pre-commit formatting applied** — code matches style
- [ ] **Comments explain WHY, not WHAT** — naming should be clear
- [ ] **Tests updated** — if behavior changes, tests verify

---

## Debugging Real-Time Audio Issues

### Symptom: Glitches, clicks, pops during playback

**Check:**
1. **Frame count assertion** — Did you assume a fixed frame size?
2. **Memory allocation** — Is the render callback calling `new`/`malloc`?
3. **Logging on RT thread** — Remove `printf`/`NSLog` from render
4. **Lock contention** — Are you using `std::mutex` instead of `std::atomic`?

**Tools:**
- **System Trace (Xcode)** — Profile → System Trace, look for XRuns and render thread overruns
- **ASAN** — Enable and run under sanitizer to catch memory bugs
- **lldb breakpoints** — Set breakpoints off-thread (UI/control plane), never in render

### Symptom: Build warnings or clang-tidy errors

**Check the `.clang-tidy` file** — Some rules are strict intentionally. If a warning seems spurious:
1. Review the guideline (usually there's a reason)
2. Use `// NOLINT(rule-name)` comment **sparingly** — document WHY
3. Discuss in PR before merging

---

## Further Reading

- **C++ Core Guidelines:** https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
- **Real-Time Audio Rules:** See `../docs/architecture/architecture.md` § Real-Time Audio Constraints
- **Core Audio Essentials:** Apple's official real-time audio guide (linked in core-audio-macos skill)

---

**Last Updated:** 2026-06-13  
**Maintained By:** AdaptiveSound Team
