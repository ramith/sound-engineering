# Development Guide — AdaptiveSound

This document covers coding standards, tooling, and guardrails to maintain code quality, especially for C++ real-time audio code and Swift UI/control-plane safety.

## Tool Setup

The strict gate (`make strict-gate`) and the pre-commit hook require the full toolchain.
Missing tools are now a **hard failure**, not a silent skip — install everything:

```bash
# Swift format + lint
brew install swiftformat swiftlint

# C++ static analysis (keg-only clang-tidy) + supplementary checker
brew install llvm cppcheck

# Pattern-based safety bans (Swift force-try/cast; C++ unbounded string funcs)
brew install semgrep

# clang-format ships with Xcode/LLVM. Verify the whole set:
swiftformat --version
swiftlint --version
clang-format --version
/opt/homebrew/opt/llvm/bin/clang-tidy --version
semgrep --version
cppcheck --version   # optional: strict-gate runs a supplementary pass if present
```

**Why clang-tidy is now REQUIRED (was "optional"):**
- Catches subtle C++ bugs (nullptr dereferences, use-after-free, data races)
- Enforces the Core Guidelines subset as build-breaking errors (`WarningsAsErrors: '*'`)
- Prevents hard-to-debug audio glitches

The pre-commit hook **fails** (no longer skips) if a required tool is missing for the file
types you staged. `git commit --no-verify` is the deliberate escape hatch; the repo-wide
`make strict-gate` / CI is the real net.

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
3. **Static-analyses** staged C++ with clang-tidy — failures block the commit

A **missing required tool now blocks the commit** (it used to skip with a warning). Bypass
once (not recommended): `git commit --no-verify`. The pre-commit hook is fast + staged-only;
it is a convenience, not the real protection — that is `make strict-gate` / CI.

---

## Quality Gates

Three tiers, fastest first:

| Command | When | Scope | What it runs |
|---------|------|-------|--------------|
| pre-commit hook | every `git commit` | staged files | swiftformat + clang-format (auto-fix), swiftlint (errors block), clang-tidy |
| `make lint` | anytime / editor | whole repo, no mutation | swiftformat `--lint`, `swiftlint --strict`, `clang-format --dry-run --Werror`, semgrep |
| `make strict-gate` | before PR / merge | whole repo | `make lint` + suppression policy + cppcheck + **clang-tidy fail-on-any** over first-party C++ (production + `Tests/*.cpp`) + `swift build` + `swift test` + `make gate` + **null-test source-list drift-guard** + **`-O2 -Werror` release compile** (`build-null-test.sh --release-strict`) + ASan/UBSan/TSan |

`make ci` == `make strict-gate`; the CI workflow (`.github/workflows/strict-ci.yml`) runs the
identical command on a self-hosted macOS 26 / Xcode 26 runner, so local and CI cannot diverge.
(GitHub-hosted `macos-latest` cannot build this package until it ships Tahoe/Xcode 26.)

`make format` auto-formats in place (SwiftFormat + clang-format) — local convenience, never CI.

### Suppression policy

Every lint/analysis suppression in first-party code must be **accountable**, enforced by
`scripts/check-suppressions.sh` (part of `make strict-gate`). Metadata rides on the same
comment line as the directive (clang-tidy/semgrep ignore trailing text) — no multi-line
blocks. Two classes:

- **PERMANENT** — an architectural necessity that does not expire (C-ABI `reinterpret_cast`,
  CoreAudio `AudioObjectPropertyAddress[]` arrays, opaque-handle boundaries, `NSLog` varargs).
  Carries a reason, **no** expiry.
- **TEMP** — time-boxed tech debt. Requires `expiry=YYYY-MM-DD` (fails once past) **or**
  `issue=<#id|url>`.

```cpp
// NOLINTNEXTLINE(cppcoreguidelines-pro-type-vararg) PERMANENT reason="NSLog is the platform log API"
// NOLINTBEGIN(cppcoreguidelines-avoid-c-arrays) PERMANENT reason="CoreAudio AudioObjectPropertyAddress[]"
// nosemgrep: cpp-no-thread-detach PERMANENT reason="reviewed boundary; joined at teardown"
// NOLINTNEXTLINE(some-check) TEMP reason="works around SDK bug" expiry=2026-09-01
```

Rules: rule-id mandatory (no blanket `// NOLINT`), exactly one of PERMANENT|TEMP, a
`reason="…"` of ≥12 chars, owner resolved from the path→owner map in the script,
`NOLINTBEGIN` balanced by `NOLINTEND` (same rules), and **no suppression of a rule already
globally disabled in `.clang-tidy`** (dead → remove it). Fix the code first; suppress only a
genuine, documented necessity — never to quiet the gate.

### TODO policy

The `todo` SwiftLint rule is disabled so roadmap markers are allowed, but a `TODO` must carry
an **owner or a sprint/issue ID** — e.g. `// TODO(S8.4): …` or `// TODO(ramith): …`. Bare
`// TODO` with no attribution is not allowed in review.

### Accepted residual risks / follow-ups

The C++ static-analysis gate is deliberately strict; these are the known, accepted edges:

- **clang-tidy fail-on-any is LLVM-version-sensitive.** `WarningsAsErrors: '*'` promotes every
  enabled check to fatal, so a `brew upgrade llvm` can fire a *newly-added* check on otherwise
  unchanged code and break the gate. When convenient, pin/record the expected LLVM major
  (CI uses the runner's `llvm`). Treat such a break as a check-triage task, not a code bug.
- **clang-tidy scope is hardcoded.** It analyses `Sources/AudioDSP` + `Sources/AudioDSPTestBridge`
  + `Tests/` (`.cpp`/`.mm`/`.cc`, any depth — matching the pre-commit hook and the Makefile). A
  **new C++ directory/target** outside those roots would go unanalysed until it is explicitly added
  to the gate (`scripts/strict-gate.sh` clang-tidy step + `build-null-test.sh` if it belongs in the
  null test). The "analyzed ≥1 file" guard only catches a broken *existing* scope, not a brand-new
  unlisted one.
- **`-O2` diagnostics: prove real-vs-false-positive first.** The `--release-strict` pass surfaces
  optimization-only diagnostics (`-Warray-bounds`, `-Wconditional-uninitialized`). If one fires,
  confirm whether it is a genuine bug or a compiler false positive *before* changing code. For a
  real FP, prefer a **narrowly-scoped `#pragma clang diagnostic push/ignored/pop`** carrying the
  suppression-policy comment (owner / reason / expiry) over a value-changing zero-init or clamp on
  the audio path — silencing a warning must never alter DSP output.
- **Optional deferred polish** (nice-to-have, not blocking): move the off-RT-path meter-peak loop
  in `LoudnessMeterBridge.mm` into a null-tested helper so it rides the `-O2`/sanitizer gates
  instead of the live-only allowlist. (The former ARC/MRC-parity item — `-fobjc-arc` on the
  null-test `.mm` compile — is now done; `build-null-test.sh` compiles Obj-C++ under ARC to match
  the SwiftPM build.)
- **`ADAPTIVESOUND_TEST_DATA_DIR` is defined in two places.** `scripts/lib/cxx-analysis-flags.sh`
  (`cxx_test_extra_flags`, for analysis) and `scripts/build-null-test.sh` (the compile) each define
  it independently; they agree today (both `<repo>/test-data`). A clean single-source dedup isn't
  possible without `build-null-test.sh` also inheriting `cxx_test_extra_flags`' unrelated flags
  (libebur128 `-I`, `ADAPTIVE_FIXTURES_DIR`) that it neither wants nor uses, so it's left as a
  low-risk known duplication.

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

### Compiler Flags (`AudioDSP` C++ target)

**Debug builds fail on ANY warning** — full `-Werror` over a wide set (this is the primary
dev + `make gate` build, so it catches everything except optimization-only diagnostics):
- `-Wall -Wextra -Wpedantic` — all standard warnings
- `-Wshadow`, `-Wconversion -Wsign-conversion`, `-Wnull-dereference`, `-Wold-style-cast`
- `-Wformat=2`, `-Wimplicit-fallthrough`, `-Wunreachable-code`, `-Wcast-align`
- `-Werror` — every warning above is a build-breaking error

**Deliberately NOT enabled:** `-Wfloat-equal` — DSP legitimately compares to `0.0f`/`1.0f`
for silence / bypass / coefficient-change detection.

**Release builds stay PERMISSIVE on purpose** (`-Wall -Wextra` + the three new warnings, but
**no** `-Werror`). Rationale: `-O2`-only, toolchain-version-dependent warnings
(`-Wmaybe-uninitialized`, `-Wstringop-overflow`, …) must never brick a shippable /
notarization build with no code change. Debug's full `-Werror` already gates everything
except optimization-only diagnostics before release is ever built. (The `AudioDSPTestBridge`
target is intentionally lighter — `-Wall -Wextra`, no `-Werror` — because the stub module
headers carry expected `-Wunused-parameter` warnings.)

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
- **Real-Time Audio Rules:** See `../architecture/architecture.md` §2 (RT rules) and §14 (threading / Audio Workgroups)
- **Core Audio Essentials:** Apple's official real-time audio guide (linked in core-audio-macos skill)

---

**Last Updated:** 2026-07-03 (strict build guardrails: `make strict-gate`, suppression policy, C++23)

**Maintained By:** AdaptiveSound Team
