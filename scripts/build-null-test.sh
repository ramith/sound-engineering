#!/bin/bash
# Scripts/build-null-test.sh
#
# Builds and optionally runs the DSPKernel null test.
#
# Usage:
#   ./Scripts/build-null-test.sh            # build + run (default)
#   ./Scripts/build-null-test.sh --build    # build only, do not run
#   ./Scripts/build-null-test.sh --sanitize # build + run with ASan + UBSan
#   ./Scripts/build-null-test.sh --tsan     # build + run with ThreadSanitizer
#
# --sanitize / --tsan add runtime instrumentation (mutually exclusive: ASan and
# TSan cannot coexist in one binary). Both imply -g -fno-omit-frame-pointer so
# reports carry symbolised stacks. UBSan (bundled with --sanitize) runs in
# halt-on-error mode so any undefined behaviour aborts with a non-zero exit.
#
# Output binary: Tests/DSPKernelNullTest  (gitignored; not checked in)
#
# Requirements: Xcode Command Line Tools (xcrun, clang++ with gnu++2b support,
#               AudioToolbox + Accelerate frameworks available via the SDK).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
OUTPUT="$REPO_ROOT/Tests/DSPKernelNullTest"

# ---------------------------------------------------------------------------
# Argument parsing: --build (no run), --sanitize (ASan+UBSan), --tsan (TSan).
# SAN_FLAGS is applied to BOTH the C99 ebur128 compile and the C++ link so the
# whole binary is instrumented. BUILD_ONLY skips the run step.
# ---------------------------------------------------------------------------
SAN_FLAGS=()
SAN_LABEL="none"
BUILD_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --build)    BUILD_ONLY=1 ;;
        --sanitize) SAN_FLAGS=(-fsanitize=address,undefined -fno-omit-frame-pointer -g)
                    SAN_LABEL="ASan+UBSan" ;;
        --tsan)     SAN_FLAGS=(-fsanitize=thread -fno-omit-frame-pointer -g)
                    SAN_LABEL="TSan" ;;
        *)          echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done
[[ "$SAN_LABEL" != "none" ]] && echo "Sanitizer: $SAN_LABEL"

# ---------------------------------------------------------------------------
# TEST-ONLY loudness oracle: libebur128 (MIT, pinned v1.2.6) is vendored as a git
# submodule at third_party/libebur128. It is compiled into the test binary ONLY
# (never Package.swift / the AudioDSP target / the shipping app). A fresh clone
# auto-fetches the submodule on first build; idempotent no-op once present.
# ---------------------------------------------------------------------------
EBUR128_DIR="$REPO_ROOT/third_party/libebur128/ebur128"
if [ ! -f "$EBUR128_DIR/ebur128.c" ]; then
    echo "libebur128 submodule missing — initialising..."
    git -C "$REPO_ROOT" submodule update --init --depth 1 third_party/libebur128
fi
EBUR128_OBJ="$REPO_ROOT/Tests/.ebur128.o"

echo "Compiling libebur128 (test-only oracle, C99) ..."
# Compile ebur128.c AS C (it is C99 — NOT objc++). queue/ headers it includes live
# under $EBUR128_DIR/queue, which is already on its relative include path.
xcrun clang \
    -x c -std=c11 \
    -isysroot "$SDK" \
    -O2 \
    -DACCELERATE_NEW_LAPACK \
    ${SAN_FLAGS[@]+"${SAN_FLAGS[@]}"} \
    -I"$EBUR128_DIR" \
    -c "$EBUR128_DIR/ebur128.c" \
    -o "$EBUR128_OBJ"

echo "Building null test..."
# Test fixtures are written + read here (never /tmp). The dir is tracked via test-data/README.md;
# the generated WAV/bin fixtures inside are git-ignored.
mkdir -p "$REPO_ROOT/test-data"
xcrun clang++ \
    -std=gnu++2b \
    -isysroot "$SDK" \
    -fno-exceptions \
    -fno-rtti \
    -Wall -Wextra \
    ${SAN_FLAGS[@]+"${SAN_FLAGS[@]}"} \
    -D_LIBCPP_DISABLE_AVAILABILITY \
    -DACCELERATE_NEW_LAPACK \
    -DADAPTIVESOUND_TEST_DATA_DIR="\"$REPO_ROOT/test-data\"" \
    -I"$REPO_ROOT/Sources/AudioDSP/include" \
    -I"$REPO_ROOT/Sources/AudioDSP" \
    -I"$EBUR128_DIR" \
    -isystem /opt/homebrew/include \
    "$REPO_ROOT/Sources/AudioDSP/DSPKernel.mm" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQModule.mm" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessModule.mm" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/ChannelLayoutDecoder.mm" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/SpatialRenderKernel.mm" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/CrossfeedModule.mm" \
    "$REPO_ROOT/Sources/AudioDSP/PureModePolicy.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModeBridgePolicy.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModeFormat.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModeSource.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/FileDecodeSource.mm" \
    "$REPO_ROOT/Sources/AudioDSP/GaplessSource.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/AudioEngine/Realizer.mm" \
    "$REPO_ROOT/Tests/DSPKernelNullTest.cpp" \
    "$EBUR128_OBJ" \
    -framework AudioToolbox \
    -framework CoreFoundation \
    -framework Foundation \
    -framework Accelerate \
    -o "$OUTPUT"

echo "Built: $OUTPUT"

if ((BUILD_ONLY)); then
    exit 0
fi

echo ""
echo "Running null test..."
# halt_on_error=1: abort on the first UBSan/ASan finding with a non-zero exit so
# the gate (&&-chained in the Makefile) actually fails instead of printing and
# continuing. abort_on_error=1 gives a symbolisable crash for the debugger.
ASAN_OPTIONS="halt_on_error=1:abort_on_error=1:detect_leaks=0" \
UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1" \
TSAN_OPTIONS="halt_on_error=1" \
"$OUTPUT"
