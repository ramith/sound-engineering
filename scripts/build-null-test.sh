#!/bin/bash
# scripts/build-null-test.sh
#
# Builds and (unless told otherwise) runs the DSPKernel null test: one C++ translation unit
# (Tests/DSPKernelNullTest.cpp) on GoogleTest 1.18.0 (third_party/googletest, pinned in
# toolchain/toolchain.env), with our per-test watchdog (Tests/NullTestRunner.h).
#
# Usage: ./scripts/build-null-test.sh [variant] [--build] [--tier <list>] [--shards <N>] [test flags]
#
# Variants (one; none = the plain debug build):
#   (none)             build -O0 + run
#   --sanitize         build + run with ASan + UBSan (halt on error)
#   --tsan             build + run with ThreadSanitizer (halt on error)
#   --release-strict   -O2 -Werror compile only (no run)
#   --opt-run          the same -O2 -Werror build, then RUN it: the timing tier's strict budgets
# --build              build only, do not run (any variant)
#
# Which tests run (Tests/NullTestRunner.h has the tiers):
#   --tier <list>      comma-separated tiers/flags, '-' excludes: correctness concurrent
#                      accuracySweep timing serial parallelSafe needsFfmpeg all
#                      Defaults, by variant — every test runs in the plain build:
#                        plain: all | --sanitize: -timing | --tsan: concurrent | --opt-run: timing
#   --shards <N>       N parallel processes (GoogleTest sharding) over the parallel-safe tests,
#                      beside ONE process for the serial tests (they share fixtures in test-data/);
#                      each output line is prefixed with its process. Exit: non-zero if any failed.
#   --gtest_*          passed to GoogleTest: --gtest_filter=, --gtest_repeat=N, --gtest_shuffle,
#                      --gtest_random_seed=N (shuffle prints its seed), --gtest_output=json:FILE,
#                      --gtest_fail_fast, --gtest_list_tests, …
#   --test-ceiling=S, --filter=NAME, --list   passed to the runner (NullTestRunner.h)
#
# Results: GoogleTest's JSON (per test: status, time, tier, flags, process CPU ms) goes to
# .build/null-test/<variant>.json — sharded: <variant>.shard<i>.json and <variant>.serial.json —
# unless --gtest_output=json:FILE says where (sharded: FILE's name gets .shard<i> / .serial).
# Output is line-buffered; each test's line shows its elapsed time, then "[cpu] <ms>".
# A test that runs past its ceiling prints "[HANG] <Suite.Test> ran past its N s ceiling. Last
# progress: …" and aborts the run (exit 134). A filter or tier that selects nothing fails.
#
# --sanitize / --tsan add runtime instrumentation (mutually exclusive: ASan and TSan cannot
# coexist in one binary). Both imply -g -fno-omit-frame-pointer so reports carry symbolised
# stacks. UBSan (bundled with --sanitize) runs in halt-on-error mode so any undefined behaviour
# aborts with a non-zero exit.
#
# --release-strict compiles the C++ at -O2 -Werror to surface optimization-only real bugs the
# debug -Werror build can't see: -Warray-bounds (auto-enabled at -O2) and inlining-exposed
# uninitialised reads. It is mutually exclusive with --sanitize / --tsan (mixing -O2 with a
# sanitizer would muddy which flag surfaced a finding). --opt-run is that build, run.
#
# GoogleTest is compiled from the submodule with exactly the flags of the variant (the shared core
# flags, -fno-exceptions -fno-rtti, the sanitizer or -O2 -Werror set), into .build/null-test/.
#
# Output binary: Tests/DSPKernelNullTest  (gitignored; not checked in)
#
# Requirements: Xcode Command Line Tools (xcrun, clang++ with gnu++2b support,
#               AudioToolbox + Accelerate frameworks available via the SDK).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
OUTPUT="$REPO_ROOT/Tests/DSPKernelNullTest"
WORK_DIR="$REPO_ROOT/.build/null-test"

# Shared SINGLE SOURCE OF TRUTH for the C++/Obj-C++ core parse flags (std, isysroot, -fno-*,
# the -D defines, the AudioDSP includes, -isystem homebrew) — the same flags clang-tidy uses.
# Sourcing them makes THIS production compile the self-verification of exactly ONE library
# function, cxx_analysis_core_flags: a broken include/flag in that core set fails `make gate`
# loudly instead of silently drifting from the analysis flags. SCOPE NOTE: only
# cxx_analysis_core_flags is exercised by a real compile here; the library's other helpers
# (cxx_test_extra_flags, cxx_bridge_extra_flags, cxx_lang_flags) are NOT used by this script — it
# layers its own test-only extras below and selects language mode by file extension — so those
# are self-verified by the clang-tidy passes in strict-gate.sh / the pre-commit hook.
# shellcheck source=scripts/lib/cxx-analysis-flags.sh
source "$REPO_ROOT/scripts/lib/cxx-analysis-flags.sh"

# ---------------------------------------------------------------------------
# Arguments. SAN_FLAGS is applied to the C99 ebur128 compile, the GoogleTest compile and the C++
# link so the whole binary is instrumented. BUILD_ONLY skips the run step.
# ---------------------------------------------------------------------------
SAN_FLAGS=()
SAN_LABEL="none"
VARIANT="plain"
BUILD_ONLY=0
RELEASE_STRICT=0
OPT_RUN=0
RELEASE_STRICT_FLAGS=()
TIER=""
SHARDS=1
JSON_OUT=""
TEST_ARGS=()
while (($#)); do
    arg="$1"
    shift
    case "$arg" in
        --build)    BUILD_ONLY=1 ;;
        --sanitize) SAN_FLAGS=("-fsanitize=address,undefined" -fno-omit-frame-pointer -g)
                    SAN_LABEL="ASan+UBSan"; VARIANT="asan" ;;
        --tsan)     SAN_FLAGS=(-fsanitize=thread -fno-omit-frame-pointer -g)
                    SAN_LABEL="TSan"; VARIANT="tsan" ;;
        --release-strict|--opt-run)
                    # -O2 surfaces optimization-only real bugs the debug build can't see:
                    # -Warray-bounds (auto-enabled at -O2) plus inlining-exposed uninitialised
                    # reads via clang's flow-sensitive -Wconditional-uninitialized. Do NOT add
                    # -Wmaybe-uninitialized / -Wstringop-overflow: those are GCC-only and Apple
                    # clang errors on the unknown option. --release-strict is build-only;
                    # --opt-run runs the build (the timing tier's strict budgets).
                    RELEASE_STRICT=1
                    RELEASE_STRICT_FLAGS=(-O2 -Werror -Wconditional-uninitialized)
                    VARIANT="opt"
                    if [[ "$arg" == "--opt-run" ]]; then OPT_RUN=1; fi ;;
        --tier)     [[ $# -gt 0 ]] || { echo "Error: --tier needs a list" >&2; exit 2; }
                    TIER="$1"; shift ;;
        --tier=*)   TIER="${arg#--tier=}" ;;
        --shards)   [[ $# -gt 0 ]] || { echo "Error: --shards needs a count" >&2; exit 2; }
                    SHARDS="$1"; shift ;;
        --shards=*) SHARDS="${arg#--shards=}" ;;
        --gtest_output=json:*) JSON_OUT="${arg#--gtest_output=json:}" ;;
        --gtest_*|--test-ceiling=*|--filter=*|--list|--serial-only|--parallel-safe-only)
                    TEST_ARGS+=("$arg") ;;
        *)          echo "Unknown argument: $arg" >&2; exit 2 ;;
    esac
done
((RELEASE_STRICT && !OPT_RUN)) && BUILD_ONLY=1

if ! [[ "$SHARDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: --shards wants a whole number ≥ 1 (got '$SHARDS')" >&2
    exit 2
fi
# --release-strict / --opt-run (-O2 -Werror) and the sanitizers (-fsanitize + -g) are mutually
# exclusive: mixing -O2 with a sanitizer would muddy which flag surfaced a finding.
if ((RELEASE_STRICT)) && [[ "$SAN_LABEL" != "none" ]]; then
    echo "Error: --release-strict / --opt-run are mutually exclusive with --sanitize / --tsan" >&2
    exit 2
fi
# The default tiers by variant (every test runs in the plain build, so each runs somewhere).
if [[ -z "$TIER" ]]; then
    case "$VARIANT" in
        plain) TIER="all" ;;
        asan)  TIER="-timing" ;;
        tsan)  TIER="concurrent" ;;
        opt)   TIER="timing" ;;
    esac
fi
[[ "$SAN_LABEL" != "none" ]] && echo "Sanitizer: $SAN_LABEL"
((RELEASE_STRICT)) && echo "Mode: release-strict (-O2 -Werror)$( ((OPT_RUN)) && echo ', run')"
mkdir -p "$WORK_DIR"

# ---------------------------------------------------------------------------
# GoogleTest: the submodule, at the commit toolchain/toolchain.env pins (a stale checkout in a
# worktree would otherwise build another GoogleTest without a word).
# ---------------------------------------------------------------------------
GTEST_DIR="$REPO_ROOT/third_party/googletest/googletest"
if [ ! -f "$GTEST_DIR/src/gtest-all.cc" ]; then
    echo "googletest submodule missing — initialising..."
    git -C "$REPO_ROOT" submodule update --init --depth 1 third_party/googletest
fi
GTEST_PIN="$(sed -n 's/^GOOGLETEST_COMMIT=//p' "$REPO_ROOT/toolchain/toolchain.env")"
GTEST_HEAD="$(git -C "$REPO_ROOT/third_party/googletest" rev-parse HEAD)"
if [[ "$GTEST_HEAD" != "$GTEST_PIN" ]]; then
    echo "Error: third_party/googletest is at $GTEST_HEAD, toolchain/toolchain.env pins" >&2
    echo "       '$GTEST_PIN'. Run: git submodule update --init third_party/googletest" >&2
    exit 1
fi

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
EBUR128_OBJ="$WORK_DIR/ebur128-$VARIANT.o"

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

echo "Compiling GoogleTest 1.18.0 ($VARIANT flags) ..."
GTEST_OBJ="$WORK_DIR/gtest-$VARIANT.o"
read -r -a CORE_FLAGS <<< "$(cxx_analysis_core_flags)"
xcrun clang++ \
    "${CORE_FLAGS[@]}" \
    -Wall -Wextra \
    ${SAN_FLAGS[@]+"${SAN_FLAGS[@]}"} \
    ${RELEASE_STRICT_FLAGS[@]+"${RELEASE_STRICT_FLAGS[@]}"} \
    -I"$GTEST_DIR/include" \
    -I"$GTEST_DIR" \
    -c "$GTEST_DIR/src/gtest-all.cc" \
    -o "$GTEST_OBJ"

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
read -r -a CORE_FLAGS <<< "$(cxx_analysis_core_flags)"
xcrun clang++ \
    "${CORE_FLAGS[@]}" \
    -Wall -Wextra \
    -fobjc-arc -fblocks \
    ${SAN_FLAGS[@]+"${SAN_FLAGS[@]}"} \
    ${RELEASE_STRICT_FLAGS[@]+"${RELEASE_STRICT_FLAGS[@]}"} \
    -DADAPTIVESOUND_TEST_DATA_DIR="\"$REPO_ROOT/test-data\"" \
    -DADAPTIVESOUND_GAPLESS_TEST_HOOKS=1 \
    -I"$GTEST_DIR/include" \
    -I"$EBUR128_DIR" \
    "$REPO_ROOT/Sources/AudioDSP/DSPKernel.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/GraphicEQDesigner.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQDesignBridge.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/CausalLoudnessTap.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessMeterBridge.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessProfile.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessProfiler.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessGain.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessBridge.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/ChannelLayoutDecoder.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Planning/TrackPlan.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/CrossfeedModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModePolicy.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModeBridgePolicy.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/DeviceListPolicy.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModeFormat.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/FileDecodeSource.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/FFmpegLoader.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/GaplessSource.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/AudioEngine/Realizer.mm" \
    "$REPO_ROOT/Tests/DSPKernelNullTest.cpp" \
    "$EBUR128_OBJ" \
    "$GTEST_OBJ" \
    -framework AudioToolbox \
    -framework CoreFoundation \
    -framework Foundation \
    -framework Accelerate \
    -o "$OUTPUT"

echo "Built: $OUTPUT"

if ((BUILD_ONLY)); then
    exit 0
fi

# ---------------------------------------------------------------------------
# Run. halt_on_error=1: abort on the first UBSan/ASan/TSan finding with a non-zero exit so the gate
# fails instead of printing and continuing. abort_on_error=1 gives a symbolisable crash.
# ---------------------------------------------------------------------------
export ASAN_OPTIONS="halt_on_error=1:abort_on_error=1:detect_leaks=0"
export UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
export TSAN_OPTIONS="halt_on_error=1"

# The JSON file for one process: <role> is "" (one process), "shard<i>" or "serial".
json_for() {
    local role="$1" base="${JSON_OUT:-$WORK_DIR/$VARIANT.json}"
    if [[ -z "$role" ]]; then
        printf '%s' "$base"
    elif [[ "$base" == *.json ]]; then
        printf '%s' "${base%.json}.$role.json"
    else
        printf '%s' "$base.$role.json"
    fi
}

echo ""
echo "Running null test (tiers: $TIER$( ((SHARDS > 1)) && echo ", $SHARDS shards + the serial process"))..."
if ((SHARDS == 1)); then
    "$OUTPUT" --tier="$TIER" "--gtest_output=json:$(json_for '')" \
        ${TEST_ARGS[@]+"${TEST_ARGS[@]}"}
    exit $?
fi

# Sharded: each process's exit code goes to a file BEFORE its output is prefixed (a pipe's own
# exit code would hide it); the run fails if any process failed. A process the watchdog aborted
# (134, its "[HANG] <test>" line above) makes the whole run exit 134, as an unsharded run would,
# so the gate names it a hang rather than a plain failure.
RUN_DIR="$(mktemp -d "$WORK_DIR/shards.XXXXXX")"
run_process() {
    local label="$1"
    shift
    { local rc=0; "$@" || rc=$?; echo "$rc" > "$RUN_DIR/$label.rc"; } 2>&1 |
        awk -v tag="[$label] " '{ print tag $0; fflush() }'
}
for ((index = 0; index < SHARDS; index++)); do
    run_process "shard$index" env GTEST_TOTAL_SHARDS="$SHARDS" GTEST_SHARD_INDEX="$index" \
        "$OUTPUT" --tier="$TIER" --parallel-safe-only "--gtest_output=json:$(json_for "shard$index")" \
        ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} &
done
run_process serial "$OUTPUT" --tier="$TIER" --serial-only \
    "--gtest_output=json:$(json_for serial)" ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} &
wait
status=0
for rc_file in "$RUN_DIR"/*.rc; do
    rc="$(cat "$rc_file")"
    echo "$(basename "$rc_file" .rc): exit $rc"
    if [[ "$rc" == "134" ]]; then
        status=134
    elif [[ "$rc" != "0" && "$status" != "134" ]]; then
        status=1
    fi
done
expected=$((SHARDS + 1))
found="$(find "$RUN_DIR" -name '*.rc' | wc -l | tr -d ' ')"
if [[ "$found" != "$expected" ]]; then
    echo "Error: $found of $expected processes reported an exit code" >&2
    status=1
fi
rm -rf "$RUN_DIR"
exit "$status"
