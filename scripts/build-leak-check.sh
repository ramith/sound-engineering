#!/bin/bash
# scripts/build-leak-check.sh
#
# Builds the headless C-ABI handle-leak harness (Tests/HandleLeakHarness.mm) and runs it
# under `xcrun leaks --atExit`, then proves the step is NOT a no-op with a plant-a-leak
# self-test.
#
# WHY: macOS / Apple-Silicon ASan has no LeakSanitizer, so the strict-gate sanitizer suite
# is blind to plain leaks. This script is the leak-DETECTION gate (audit hole #2). It mirrors
# scripts/build-null-test.sh's idiom (a standalone C++/Obj-C++ binary linking the AudioDSP
# sources + frameworks) and SOURCES the same shared parse-flag core so it can never drift
# from the compiler the analysis/null-test use.
#
# Two binaries are built from ONE source list:
#   * $BIN          — clean; MUST report 0 leaks (leaks exit 0).
#   * $PLANTED_BIN  — compiled -DADAPTIVE_PLANT_LEAK=1; the harness leaks exactly one
#                     loudness handle, so `leaks` MUST fire (non-zero exit) with
#                     `loudnessMeterCreate` in the leaked block's allocation stack.
#
# NO SANITIZER on purpose: ASan replaces malloc/free with its own allocator, which blinds
# `leaks(1)` (it can no longer walk the real malloc zones). -g -fno-omit-frame-pointer are
# added so `leaks` reports symbolised allocation stacks (needed for the plant-a-leak grep).
#
# Output binaries + log are gitignored (see .gitignore), like Tests/DSPKernelNullTest.
#
# Requirements: Xcode Command Line Tools (xcrun, clang++), leaks(1), the AudioToolbox /
#               CoreAudio / Foundation / Accelerate frameworks via the SDK.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES_DIR="$REPO_ROOT/Tests/Fixtures/artwork-audio"
BIN="$REPO_ROOT/Tests/HandleLeakHarness"
PLANTED_BIN="$REPO_ROOT/Tests/HandleLeakHarness-planted"
PLANT_LOG="$REPO_ROOT/Tests/HandleLeakHarness-plant.log"
HARNESS="$REPO_ROOT/Tests/HandleLeakHarness.mm"

# Shared SINGLE SOURCE OF TRUTH for the C++/Obj-C++ core parse flags (std, isysroot, -fno-*,
# the -D defines, the AudioDSP includes, -isystem homebrew) — the same flags clang-tidy and
# build-null-test.sh use. Sourcing them here keeps this compile matched to the compiler the
# rest of the gate uses (so __has_include(<libavformat/...>) branches parse identically).
# shellcheck source=scripts/lib/cxx-analysis-flags.sh
source "$REPO_ROOT/scripts/lib/cxx-analysis-flags.sh"

# Source list: build-null-test.sh's DSP kernels PLUS the two C-ABI bridges under test
# (LoudnessMeterBridge.cpp, PureModeBridge.cpp — NOT in the null-test list) and PureModeBridge's
# live-CoreAudio transitive deps (CoreAudioDevice.cpp for queryCapability + HALOutputEngine.mm
# for the engine session). Kept as an array so the clean + planted compiles reuse it verbatim.
# (Realizer.mm + HALOutputEngine.mm stay Obj-C++; the rest are pure C++ .cpp post-migration.)
SOURCES=(
    "$REPO_ROOT/Sources/AudioDSP/DSPKernel.cpp"
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQModule.cpp"
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessModule.cpp"
    "$REPO_ROOT/Sources/AudioDSP/Loudness/ChannelLayoutDecoder.cpp"
    "$REPO_ROOT/Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp"
    "$REPO_ROOT/Sources/AudioDSP/Spatial/CrossfeedModule.cpp"
    "$REPO_ROOT/Sources/AudioDSP/PureModePolicy.cpp"
    "$REPO_ROOT/Sources/AudioDSP/PureModeBridgePolicy.cpp"
    "$REPO_ROOT/Sources/AudioDSP/PureModeFormat.cpp"
    "$REPO_ROOT/Sources/AudioDSP/PureModeSource.cpp"
    "$REPO_ROOT/Sources/AudioDSP/FileDecodeSource.cpp"
    "$REPO_ROOT/Sources/AudioDSP/GaplessSource.cpp"
    "$REPO_ROOT/Sources/AudioDSP/AudioEngine/Realizer.mm"
    # --- ADDED for the leak harness (NOT compiled by build-null-test.sh) ---
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessMeterBridge.cpp" # under test
    "$REPO_ROOT/Sources/AudioDSP/PureModeBridge.cpp"               # under test
    "$REPO_ROOT/Sources/AudioDSP/CoreAudioDevice.cpp"              # PureModeBridge dep: queryCapability
    "$REPO_ROOT/Sources/AudioDSP/AudioEngine/HALOutputEngine.mm"   # PureModeBridge dep: engine session
)

# The frameworks build-null-test.sh links, plus CoreAudio: the added CoreAudioDevice.cpp /
# HALOutputEngine.mm / PureModeBridge.cpp reach the CoreAudio HAL (AudioObject* property calls),
# whose symbols live in CoreAudio.framework (build-null-test.sh never links it because it does
# not compile those live-CoreAudio files). This matches Package.swift's AudioDSP link settings.
FRAMEWORKS=(
    -framework AudioToolbox
    -framework CoreAudio
    -framework CoreFoundation
    -framework Foundation
    -framework Accelerate
)

# compile <output-path> [extra flags...] — one clang++ invocation for the whole harness.
# The core parse flags come from the shared library (byte-for-byte what build-null-test.sh
# uses); LOCAL to this compile are -Wall/-Wextra, -g -fno-omit-frame-pointer (symbolised leak
# stacks) and the fixtures -D. NO sanitizer (ASan would blind leaks(1)).
compile() {
    local out="$1"
    shift
    # shellcheck disable=SC2046  # intentional word-splitting of the space-separated core flags
    xcrun clang++ \
        $(cxx_analysis_core_flags) \
        -Wall -Wextra \
        -g -fno-omit-frame-pointer \
        -DADAPTIVE_FIXTURES_DIR="\"$FIXTURES_DIR\"" \
        "$@" \
        "${SOURCES[@]}" \
        "$HARNESS" \
        "${FRAMEWORKS[@]}" \
        -o "$out"
}

echo "Building leak harness (clean) ..."
compile "$BIN"
echo "Built: $BIN"

echo "Building leak harness (plant-a-leak) ..."
compile "$PLANTED_BIN" -DADAPTIVE_PLANT_LEAK=1
echo "Built: $PLANTED_BIN"

echo ""
echo "== Leak check: clean binary (expect 0 leaks) =="
# `leaks` exits 0 when no leaks are found, non-zero when leaks are found. The harness itself
# always exits 0, so the exit status here is `leaks`'s verdict on OUR heap.
if xcrun leaks --atExit -- "$BIN"; then
    echo "leak-check clean"
else
    echo "LEAK DETECTED"
    exit 1
fi

echo ""
echo "== Plant-a-leak self-test: planted binary (expect leaks(1) to CATCH the leak) =="
# INVERTED: the planted binary leaks one loudness handle on purpose, so `leaks` MUST exit
# non-zero. The harness exits 0, so a non-zero status can only be `leaks` finding the leak.
# A zero exit here means the gate found nothing where a leak was planted → it is a no-op.
if xcrun leaks --atExit -- "$PLANTED_BIN" >"$PLANT_LOG" 2>&1; then
    echo "PLANT-A-LEAK FAILED: gate is a no-op (leaks found nothing in the planted binary)"
    cat "$PLANT_LOG"
    exit 1
fi
# The caught leak MUST show loudnessMeterCreate in its allocation stack — proving the detected
# leak is our deliberately-leaked LoudnessMeter handle, not some incidental/system find.
if ! grep -q loudnessMeterCreate "$PLANT_LOG"; then
    echo "planted leak not in the expected alloc stack (loudnessMeterCreate missing from leaks output)"
    cat "$PLANT_LOG"
    exit 1
fi
echo "plant-a-leak caught (leaks flagged the deliberately-leaked loudnessMeterCreate handle)"

echo ""
echo "leak-check PASSED (clean binary: 0 leaks; planted leak: detected)."
