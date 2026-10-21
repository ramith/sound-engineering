# Development Guide — AdaptiveSound

This document covers coding standards, tooling, and guardrails to maintain code quality, especially for C++ real-time audio code and Swift UI/control-plane safety.

## Tool Setup

Every tool the gate depends on is pinned in **one file**, `toolchain/toolchain.env`, with its exact version and checksum. One install script serves your Mac and CI, so the Mac and CI run the same binaries:

```bash
scripts/toolchain/install.sh   # downloads, verifies every sha256, installs into ~/.cache/adaptivesound-toolchain/<hash>/
scripts/toolchain/check.sh     # the parity table: what the gate will run, against the manifest
```

- **No sudo, no global Homebrew change.** The install lives in a cache keyed by the manifest hash; a bump changes the hash and lands in a new directory. A failed download or checksum stops the install and names the file. Never edit a checksum to make it pass.
- **The gate puts that directory first on `PATH` itself.** For a by-hand tool call: `export PATH="$(scripts/toolchain/install.sh --print-bin):$PATH"`.
- **Verdict tools are exact.** SwiftFormat, SwiftLint, Periphery, clang-format and clang-tidy (one LLVM), cppcheck (built from its pinned source), semgrep (pip, `--require-hashes`) and actionlint. A mismatch **fails** the parity check, locally and in CI, before anything else runs.
- **Xcode and Swift are exact, macOS is info, FFmpeg warns here and fails in CI.** The Xcode build and Swift are EXACT everywhere (27.1, build 27A9275). macOS is info only (the founder accepted the Mac on 26.6 against the 27.0.1 CI image). The FFmpeg headers warn locally and fail in CI. The pin is **Xcode 27.1 (build 27A9275)**, Swift 6.4, on the `xcode-27` CI runner (GitHub's Xcode 27 preview image, macOS 27.0.1). An older Xcode fails the parity check with the fix: install Xcode 27.1, then re-run `check.sh`.
- **Xcode 27's SwiftPM uses the new `swiftbuild` engine.** Never hardcode the build directory: `swift build --show-bin-path` gives it (`.build/out/Products/Debug` today). Relative paths in `unsafeFlags` break, because the compiler runs from the package's parent directory.
- **Never set `-D_LIBCPP_DISABLE_AVAILABILITY`.** It made Xcode 27's libc++ emit a macOS 27-only symbol, so the app failed to load on macOS 26. The residual risk is that CI runs macOS 27 while the product targets macOS 26; `scripts/gate/deployment-target.sh` fails any built product whose minimum macOS is newer than the target.
- **FFmpeg headers** (the FFmpeg decode branch is only analysed when they are present): `brew install ffmpeg`. Parity asserts `FFMPEG_VERSION` from the installed `ffversion.h`; Homebrew cannot install an exact older ffmpeg, so a move on Homebrew is a visible parity change, not a silent one.
- **leaks(1)** comes with the Xcode Command Line Tools: `xcrun --find leaks`.

A bump is one commit, `toolchain: bump X a→b`, that changes the manifest **and** fixes what the new version finds. The weekly canary (`.github/workflows/canary.yml`) reports what each bump would change, as one issue, before a red PR forces it.

**Why clang-tidy is REQUIRED:**
- Catches subtle C++ bugs (nullptr dereferences, use-after-free, data races)
- Enforces the Core Guidelines subset as build-breaking errors (`WarningsAsErrors: '*'`)
- Prevents hard-to-debug audio glitches

The pre-commit hook **fails** (no longer skips) if a required tool is missing for the file
types you staged. `git commit --no-verify` is the deliberate escape hatch; the repo-wide
gate / CI is the real net.

---

## Code Style & Enforcement

### Automatic Formatting

```bash
make format   # SwiftFormat over Sources + Tests, clang-format over every .h/.hpp/.cpp/.cc/.mm
```

Both formatters are enforced by the pre-commit hook and `make strict-gate`. In VS Code, C++ formats on save (cpptools → clang-format, `.clang-format`). The repo's `.vscode/settings.json` also formats Swift on save with the Swift extension, which uses Apple's swift-format, **not** SwiftFormat — the two disagree (see the `make format` note in the `Makefile`), so rely on the hook / `make format` for Swift.

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

The gate is a **registry**, not a script: every check is one row in `scripts/gate/steps.tsv` (id, CI job, tiers, blocking or advisory, timeout, the coverage rule, the command). Every local tier, every `make` gate target and every CI job runs the same rows through `scripts/gate/run.sh`, so the two cannot diverge. The old inline steps of `scripts/strict-gate.sh` map one to one onto registry ids (see `scripts/gate/README.md`); nothing was dropped.

**The four rules the gate enforces:**
1. **Collect-all.** A failing step never stops the run. Every step runs to completion; a skip is recorded with its reason, never as green. Only a real dependency is skipped.
2. **Every step has a ceiling.** Each step runs in its own process group under a watchdog (macOS has no `timeout`). A hang is killed and named: `timed out after 25m`.
3. **Zero is a failure.** A step that covers 0 files or 0 tests fails. `swift test --filter` with a misspelt name runs 0 tests and exits 0 on its own; the gate turns that into a failure.
4. **The exit code is the verdict**, and the summary is the table. Every failure's head is printed at once; full logs are in `.build/gate/<run>/logs/`.

**Parity runs first, always.** `toolchain-parity` is step one of every run. If it fails, every other step is skipped with the reason, because a verdict from the wrong tools means nothing.

| Tier | Command | When | What it runs (registry tiers) |
|------|---------|------|-------------------------------|
| T0 | pre-commit hook | each `git commit` | staged files: format (auto-fix), swiftlint, clang-tidy |
| T1 | `.githooks/pre-push` | each push | parity; swiftformat, swiftlint, semgrep, suppressions, posture guards, actionlint |
| T2 | `make check` | a lane says "done" | T1 + swift build, `swift test`, clang-format, cppcheck, clang-tidy, the debug null test |
| T3 | `make combine-check` | before pushing an integration branch | T2 + Periphery, the whole-program steps, the verifiers, the null-test drift guard, the stall self-test |
| T4 | `make strict-gate` == `make ci` == CI | each push, each PR, main | everything, as five parallel CI jobs |

**Reading a run.** `make strict-gate` prints the table (`job | step | verdict | time | reason`) and the final line `GATE PASSED` or `GATE FAILED`, then `exit: <code>`. CI shows the same table as the job summary of the **`strict-gate`** check, which is the one check to read: a job that did not report (cancelled, timed out, crashed) is a failure, never an absence of failures. Advisory rows are marked `(advisory)` and never turn it red.

**CI jobs** (`.github/workflows/strict-ci.yml`, all on the `xcode-27` runner (Xcode 27.1 selected by path), each with a `timeout-minutes`): `static`, `swift`, `cpp`, `asan`, `tsan`, then `strict-gate` on Linux. Cancellation applies to pull requests only: a run on `main` is never cancelled.

| Command | What |
|---------|------|
| `make lint` | swiftformat, swiftlint, clang-format, semgrep (no mutation) |
| `make check` | T2 |
| `make combine-check` | T3, before pushing an integration branch |
| `make strict-gate` / `make ci` | T4 |
| `make gate` | the verifiers (`VerifyAUGraph`, `SRCQualityMeasure`, `VerifyLibraryStore`) and the debug null test |
| `make sanitize` / `make tsan` / `make sanitize-library-store` / `make leak-check` | the sanitizer and leak steps by themselves |
| `make main-thread-stall` | the stall self-test by itself |
| `make toolchain` | install the pinned tools, then the parity table |
| `make format` | auto-format in place (SwiftFormat + clang-format); local convenience, never CI |

**`make stress`: repeat a test under the CI-like profile.** Before merging a new or changed timing test, stress it:

```bash
make stress TEST='prefetchPromoted' N=50     # Swift: swift test --skip-build --filter (function/type names), every iteration must run >= 1 test
make stress KIND=cpp TEST='*.Loudness_WorkersSleepWhileIdle' N=20   # C++: a GoogleTest filter (Tier.Name), shuffled, seed printed
```

The profile puts `ncpu − 3` CPU hogs in their own process group (a `trap` kills the group on any exit, so a leaked busy loop cannot outlive the run) and sets `LIBDISPATCH_COOPERATIVE_POOL_STRICT=1`. Each iteration has a hard cap (`STRESS_TIMEOUT`, default 600 s). The exit code is the verdict; put the pass rate in the PR (e.g. "ANALYZER-05 50/50 under the CI-like profile"). A C++ stress run (`KIND=cpp TEST='Concurrent.*'`) repeats the GoogleTest filter N times, shuffled, with its seed printed so a failure can be replayed. The nightly stress workflow (`.github/workflows/nightly-stress.yml`) runs the same command on a schedule and is advisory.

`make ci` == `make strict-gate`: the same registry on your Mac and in CI, so a green local run means the same thing as a green CI run.


### Suppression policy

Every lint/analysis suppression in first-party code must be **accountable**, enforced by
`scripts/check-suppressions.sh` (part of `make strict-gate`). Metadata rides on the same
comment line as the directive (clang-tidy/semgrep ignore trailing text) — no multi-line
blocks. *Exception:* for `swiftlint:disable…`, put the PERMANENT/TEMP + reason on the comment
line immediately before it (SwiftLint reads trailing tokens as rule ids). Two classes:

- **PERMANENT** — an architectural necessity that does not expire (C-ABI `reinterpret_cast`,
  CoreAudio `AudioObjectPropertyAddress[]` arrays, opaque-handle boundaries, C11 ABI buffers).
  *(The old `NSLog`/`fprintf` varargs sites are gone — `include/AsLog.h` replaced them.)*
  Carries a reason, **no** expiry.
- **TEMP** — time-boxed tech debt. Requires `expiry=YYYY-MM-DD` (fails once past) **or**
  `issue=<#id|url>`.

```cpp
// NOLINTNEXTLINE(cppcoreguidelines-avoid-c-arrays,modernize-avoid-c-arrays) PERMANENT reason="C11 ABI name buffer: std::array unavailable in ISO C11"
// NOLINTBEGIN(cppcoreguidelines-avoid-c-arrays) PERMANENT reason="CoreAudio AudioObjectPropertyAddress[]"
// nosemgrep: cpp-no-thread-detach PERMANENT reason="reviewed boundary; joined at teardown"
// NOLINTNEXTLINE(bugprone-narrowing-conversions) TEMP reason="works around SDK bug" expiry=2027-03-01
```

Rules: rule-id mandatory (no blanket `// NOLINT`), exactly one of PERMANENT|TEMP, a
`reason="…"` of ≥12 chars, owner resolved from the path→owner map in the script,
`NOLINTBEGIN` balanced by `NOLINTEND` (same rules), and **every NOLINT'd rule must be in the
effective clang-tidy enabled set for that file's directory** (honouring the `Tests/` and
`Sources/AudioDSPTestBridge/` `.clang-tidy` overrides) — a disabled, never-enabled or misspelled
rule is a dead suppression and fails (remove it). Fix the code first; suppress only a
genuine, documented necessity — never to quiet the gate.

### TODO policy

The `todo` SwiftLint rule is disabled so roadmap markers are allowed, but a `TODO` must carry
an **owner or a sprint/issue ID** — e.g. `// TODO(S8.4): …` or `// TODO(ramith): …`. Bare
`// TODO` with no attribution is not allowed in review.

### Accepted residual risks / follow-ups

The C++ static-analysis gate is deliberately strict; these are the known, accepted edges:

- **clang-tidy fail-on-any is LLVM-version-sensitive — so the major is PINNED.**
  `WarningsAsErrors: '*'` promotes every enabled check to fatal, so a new LLVM major can fire
  *newly-added* checks on otherwise unchanged code (LLVM 23 did exactly that on hosted CI:
  ~120 findings, mostly `readability-trailing-comma`, PR #63 run 1). The expected major lives in
  ONE place — `CXX_CLANG_TIDY_MAJOR_PIN` in `scripts/lib/cxx-analysis-flags.sh` — and is asserted
  by both `strict-gate.sh` and the pre-commit hook; CI installs the matching `llvm@N`
  (`strict-ci.yml`). A skew now fails the tool check with instructions instead of a wall of
  findings. A deliberate upgrade bumps the pin + the workflow's `llvm@N` and triages the new
  checks in the SAME commit (same doctrine as the SwiftFormat/SwiftLint pins).
  Two clang-tidy 23 fix-it traps met during the 22→23 bump: `--fix` silently writes NOTHING for
  `.mm` (its post-fix reformat rejects the Cpp-only `.clang-format`; use `--format-style=none`
  and format the touched lines by hand), and `readability-trailing-comma` misreads the comma
  between two `member{}` constructor initializers as a trailing comma and DELETES it (prefer
  default member initializers there).
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
- *(Done: the meter bridge — now `Loudness/LoudnessMeterBridge.cpp` — is compiled by the null
  test, so it rides the `-O2`/sanitizer gates (`Loudness_MeterBridge_TruePeak`); its entry in the
  `strict-gate.sh` live-only allowlist comment is now redundant. The former ARC/MRC-parity item —
  `-fobjc-arc` on the null-test `.mm` compile — is also done.)*
- **`ADAPTIVESOUND_TEST_DATA_DIR` is defined in two places.** `scripts/lib/cxx-analysis-flags.sh`
  (`cxx_test_extra_flags`, for analysis) and `scripts/build-null-test.sh` (the compile) each define
  it independently; they agree today (both `<repo>/test-data`). A clean single-source dedup isn't
  possible without `build-null-test.sh` also inheriting `cxx_test_extra_flags`' `ADAPTIVE_FIXTURES_DIR`,
  which the null test doesn't use (the libebur128 `-I` is likewise passed in both places), so it's
  left as a low-risk known duplication.

---

## Swift Control Plane Best Practices

Swift runs on the **UI/control plane** (not the audio render thread), so the constraints are different from C++. The binding rules for reaching the audio engine are the **[threading rules in architecture.md](../architecture/architecture.md#threading-rules-app--engine)** (Sprint G, after the disconnect freeze); this section is the practical summary. *(Rewritten 2026-10-13 to match the code: the earlier examples — an `ObservableObject` view model, a `weak var audioEngine: AudioEngineProtocol?`, an `@Atomic` property wrapper — described APIs this codebase does not have.)*

### MUST DO

✅ **Reach the engine only through `AudioPlaybackEngine`, injected as `any AudioPlaybackEngine`.** The view model holds it as a plain injected `let engine` (`AudioViewModel.swift`; a mock conforms in `Tests/AudioViewModelTests/MockAudioEngine.swift`, and since R1 scripted engines in `Tests/AdaptiveSoundTests/` — `OnDeckEngineModel`, `DeviceTestEngine` — drive the shipped view model). Outside the bridge's own files (`AudioEngineBridge*.swift`, `PureModeSession.swift`) never name the concrete `AudioEngineBridge` — semgrep `main-thread-no-concrete-bridge` fails the gate.

✅ **Read engine state from one snapshot.** `engine.snapshot()` returns an `EngineSnapshot` (transport, signal path, loudness, EQ design rate) that the engine publishes from its own queues; the 20 Hz tick reads it and nothing else.

✅ **Send intents as hand-offs.** The publishes (`publishEQ`, `publishIntensity`, `publishCrossfeed`, `publishOutputTransport`) borrow the effects AU without waiting; `publishMasterGain` and `requestDeviceVolume` queue the work (latest wins); start / stop / seek are `async` and numbered (`nextTransportEpoch()`), so a stale snapshot is ignored (`TransportSnapshot.isCurrent(for:)`). The next track goes only through `armOnDeck`, which numbers the request (`OnDeckTicket`); the engine applies only the newest of the current playback (`OnDeckGate`, R1 — council D41).

✅ **UI state is `@MainActor @Observable`.**
```swift
@MainActor @Observable
final class AudioViewModel {
    var intensity: Float = 0.20 {
        didSet { /* clamp into a LOCAL, never re-assign `intensity` here (infinite recursion) */ }
    }
    let engine: any AudioPlaybackEngine
}
```

### MUST NOT

❌ **Touch AVFAudio engine objects, the CoreAudio HAL, an AU or the Pure C-ABI from the app** — not even `isPlaying`, `volume` or `.auAudioUnit`: each takes AVFAudio's engine-wide lock, which a dying device can hold for seconds (the 3–7 s disconnect freeze). Semgrep `main-thread-no-audio-hardware` fails the gate.

❌ **`.sync` onto a bridge queue, or take a lock held across engine work, from the main thread.** Add a snapshot field or an async / queued engine method instead — and register any new synchronous `AudioPlaybackEngine` member with the self-test's `EntryProbe` (`Debug/MainThreadStallSelfTest.swift`), which `make main-thread-stall` runs in the strict gate (no main-thread entry may take 25 ms while the engine lock is held for 2.5 s).

❌ **Put a CoreAudio property listener on the main queue** (semgrep `coreaudio-listener-not-on-main`) or a `@MainActor` declaration in the bridge's files (`bridge-not-main-actor`).

❌ **Share mutable state with the render thread from Swift.** Parameters cross into C++ through the C-ABI (`Sources/AudioDSP/include/*.h`) and the Realizer's published `TargetState` snapshot; the render thread never reads Swift objects.

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
(`-Warray-bounds`, `-Wconditional-uninitialized`, …) must never brick a shippable /
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
clang-tidy Sources/AudioDSP/EQ/EQModule.cpp -- -x c++ $(source scripts/lib/cxx-analysis-flags.sh && cxx_analysis_core_flags)
```

**Configure rules** in `.clang-tidy` (already set up with audio-safe subset).

---

## Building & Testing

### Debug Build (Full Diagnostics)
```bash
swift build -c debug
```
- All warnings enabled & fail the build: C++ `-Werror`, and Swift warnings are errors (`treatAllWarnings(as: .error)`, debug only)
- clang-tidy is **not** part of `swift build` — it runs in the pre-commit hook and `make strict-gate`
- Optimizations off (faster compile, slower runtime—OK for dev)

### Release Build (Optimized)
```bash
swift build -c release
```
- Warnings permissive on purpose (see "Compiler Flags" above); the strict gate's `--release-strict` null-test compile is where `-O2` diagnostics are made fatal
- SwiftPM's default release optimization on C++ (no `-O` level is set in `Package.swift`)

### Run with AddressSanitizer (Catch Memory Bugs)
```bash
make sanitize                # the C++ null test under ASan + UBSan
make tsan                    # the C++ null test under ThreadSanitizer
make sanitize-library-store  # swift run --sanitize=address VerifyLibraryStore
make leak-check              # leaks(1) over the C-ABI handle lifecycles
# ad hoc, any target:
swift run --sanitize=address <target>
```

ASan reports buffer overruns, use-after-free, double-free, etc. **Apple-Silicon ASan ships no
LeakSanitizer** — leaks are covered by `make leak-check` (leaks(1)).

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
2. Suppress only per the **Suppression policy** above — `// NOLINTNEXTLINE(rule) PERMANENT|TEMP reason="…"`; a blanket or unannotated `// NOLINT` fails the gate
3. Discuss in PR before merging

---

## Further Reading

- **C++ Core Guidelines:** https://isocpp.github.io/CppCoreGuidelines/CppCoreGuidelines
- **Real-Time Audio Rules:** See `../architecture/architecture.md` §2 (RT rules) and §14 (threading / Audio Workgroups)
- **Core Audio Essentials:** Apple's official real-time audio guide (linked in core-audio-macos skill)

---

**Last Updated:** 2026-10-13 (product council: reconciled to the code — tool pins + Periphery, strict-gate contents, `macos-26` hosted CI, the Swift engine-access rules after Sprint G, sanitizer targets) · *previous: 2026-07-03, strict build guardrails*

**Maintained By:** AdaptiveSound Team
