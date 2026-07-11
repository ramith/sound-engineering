#!/bin/bash
# Scripts/build-null-test.sh
#
# Builds and optionally runs the DSPKernel null test.
#
# Usage:
#   ./Scripts/build-null-test.sh                 # build + run (default)
#   ./Scripts/build-null-test.sh --build         # build only, do not run
#   ./Scripts/build-null-test.sh --sanitize      # build + run with ASan + UBSan
#   ./Scripts/build-null-test.sh --tsan          # build + run with ThreadSanitizer
#   ./Scripts/build-null-test.sh --release-strict # -O2 -Werror compile only (no run)
#
# --sanitize / --tsan add runtime instrumentation (mutually exclusive: ASan and
# TSan cannot coexist in one binary). Both imply -g -fno-omit-frame-pointer so
# reports carry symbolised stacks. UBSan (bundled with --sanitize) runs in
# halt-on-error mode so any undefined behaviour aborts with a non-zero exit.
#
# --release-strict compiles the C++ at -O2 -Werror (build only, no run) to surface
# optimization-only real bugs the debug -Werror build can't see: -Warray-bounds
# (auto-enabled at -O2) and inlining-exposed uninitialised reads. It is mutually
# exclusive with --sanitize / --tsan (mixing -O2 with a sanitizer would muddy which
# flag surfaced a finding, and this is a pure compile check).
#
# Output binary: Tests/DSPKernelNullTest  (gitignored; not checked in)
#
# Requirements: Xcode Command Line Tools (xcrun, clang++ with gnu++2b support,
#               AudioToolbox + Accelerate frameworks available via the SDK).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
OUTPUT="$REPO_ROOT/Tests/DSPKernelNullTest"

# Shared SINGLE SOURCE OF TRUTH for the C++/Obj-C++ core parse flags (std, isysroot, -fno-*,
# the -D defines, the AudioDSP includes, -isystem homebrew) — the same flags clang-tidy uses.
# Sourcing them makes THIS production compile the self-verification of exactly ONE library
# function, cxx_analysis_core_flags: a broken include/flag in that core set fails `make gate`
# loudly instead of silently drifting from the analysis flags. The values are byte-for-byte
# what this script already hard-coded. SCOPE NOTE: only cxx_analysis_core_flags is exercised by
# a real compile here; the library's other helpers (cxx_test_extra_flags, cxx_bridge_extra_flags,
# cxx_lang_flags) are NOT used by this script — it layers its own test-only extras below and
# selects language mode by file extension — so those are self-verified by the clang-tidy passes
# in strict-gate.sh / the pre-commit hook, not by this compile.
# shellcheck source=scripts/lib/cxx-analysis-flags.sh
source "$REPO_ROOT/scripts/lib/cxx-analysis-flags.sh"

# ---------------------------------------------------------------------------
# Argument parsing: --build (no run), --sanitize (ASan+UBSan), --tsan (TSan).
# SAN_FLAGS is applied to BOTH the C99 ebur128 compile and the C++ link so the
# whole binary is instrumented. BUILD_ONLY skips the run step.
# ---------------------------------------------------------------------------
SAN_FLAGS=()
SAN_LABEL="none"
BUILD_ONLY=0
RELEASE_STRICT=0
RELEASE_STRICT_FLAGS=()
for arg in "$@"; do
    case "$arg" in
        --build)    BUILD_ONLY=1 ;;
        --sanitize) SAN_FLAGS=(-fsanitize=address,undefined -fno-omit-frame-pointer -g)
                    SAN_LABEL="ASan+UBSan" ;;
        --tsan)     SAN_FLAGS=(-fsanitize=thread -fno-omit-frame-pointer -g)
                    SAN_LABEL="TSan" ;;
        --release-strict)
                    # -O2 surfaces optimization-only real bugs the debug build can't see:
                    # -Warray-bounds (auto-enabled at -O2) plus inlining-exposed uninitialised
                    # reads via clang's flow-sensitive -Wconditional-uninitialized. Do NOT add
                    # -Wmaybe-uninitialized / -Wstringop-overflow: those are GCC-only and Apple
                    # clang errors on the unknown option. Implies build-only (no run step).
                    RELEASE_STRICT=1
                    RELEASE_STRICT_FLAGS=(-O2 -Werror -Wconditional-uninitialized)
                    BUILD_ONLY=1 ;;
        *)          echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done

# --release-strict (-O2 -Werror) and the sanitizers (-fsanitize + -g) are mutually exclusive:
# mixing -O2 with a sanitizer would muddy which flag surfaced a finding, and --release-strict
# is a pure compile check with no run step. Reject the combination explicitly.
if ((RELEASE_STRICT)) && [[ "$SAN_LABEL" != "none" ]]; then
    echo "Error: --release-strict is mutually exclusive with --sanitize / --tsan" >&2
    exit 2
fi
[[ "$SAN_LABEL" != "none" ]] && echo "Sanitizer: $SAN_LABEL"
((RELEASE_STRICT)) && echo "Mode: release-strict (-O2 -Werror)"

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
# The core parse flags (-std/-isysroot/-fno-exceptions/-fno-rtti/the -D defines/the AudioDSP
# includes/-isystem homebrew) come from the shared library sourced above — byte-for-byte what
# this script used to hard-code, now the single source of truth also used by clang-tidy. Kept
# LOCAL to this compile: the warning flags (-Wall -Wextra), -fobjc-arc -fblocks (see below), the
# sanitizer/-O2 flag sets, the TEST-ONLY -DADAPTIVESOUND_TEST_DATA_DIR macro and the libebur128
# oracle include.
# -fobjc-arc -fblocks: the .mm translation units below are ARC-written (no manual retain/release),
# and BOTH production (SwiftPM, per .build/debug.yaml) and clang-tidy (cxx_lang_flags emits
# -x objective-c++ -fobjc-arc -fblocks for .mm) compile them under ARC — so without these flags
# this compile alone would build them in manual-retain-release, diverging from every other path.
# clang applies -fobjc-arc only to Obj-C++ (.mm) inputs; for the pure-C++ (.cpp) inputs here it
# is a verified harmless no-op (no warning/error even under -Werror, and identical codegen since
# they contain no Obj-C), so a single shared invocation still yields "ARC for .mm only" in effect.
# The C99 libebur128 oracle is compiled SEPARATELY above (-x c), so it never sees ARC / -x c++.
# strict-gate's drift-guard greps this compile list — do not reference Sources/AudioDSP/*.{mm,cpp,cc}
# paths in comments outside it (the grep is scoped to this xcrun clang++ … -o "$OUTPUT" block).
# shellcheck disable=SC2046  # intentional word-splitting of the space-separated core flags
xcrun clang++ \
    $(cxx_analysis_core_flags) \
    -Wall -Wextra \
    -fobjc-arc -fblocks \
    ${SAN_FLAGS[@]+"${SAN_FLAGS[@]}"} \
    ${RELEASE_STRICT_FLAGS[@]+"${RELEASE_STRICT_FLAGS[@]}"} \
    -DADAPTIVESOUND_TEST_DATA_DIR="\"$REPO_ROOT/test-data\"" \
    -I"$EBUR128_DIR" \
    "$REPO_ROOT/Sources/AudioDSP/DSPKernel.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/ChannelLayoutDecoder.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/CrossfeedModule.cpp" \
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
