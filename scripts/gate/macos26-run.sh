#!/usr/bin/env bash
#
# macos26-run.sh <dir> — RUNS the binaries built on the xcode-27 runner (review H1, founder decision: nightly
# and before release). Run it on a macOS 26 machine: the macos-26 CI runner, or this Mac (26.6).
#
# What it runs, each one a named check:
#   stall-<mode>   AdaptiveSound -ASMainThreadStall <stop|start|device-loss|ended-advance>
#                  (loads the app's full link graph and drives AVFAudio on this macOS)
#   null-correctness  DSPKernelNullTest --tier=correctness (the C++ DSP correctness tier)
#   verify-au-graph   VerifyAUGraph (the AU graph integration check)
#
# A check is RED when its exit is non-zero, or its output names a dynamic-loader failure: "Symbol not found",
# "Library not loaded" or "dyld". Those are the signatures of a binary that needs a newer macOS than this one
# (the _LIBCPP_DISABLE_AVAILABILITY incident): the loader aborts before any code runs, but exit codes can lie.
#
# What it CAN'T catch: a behaviour that differs on macOS 26 without a loader error, or a difference in
# hardware (CI has no audio device; the stall check runs offline on purpose).
set -uo pipefail
dir="${1:-}"
[[ -d "$dir" ]] || { echo "usage: macos26-run.sh <dir-with-the-binaries>" >&2; exit 2; }
log="${GATE_RUN_DIR:-$dir}"
mkdir -p "$log"
echo "running on macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))"

red=0
check() {  # check <name> <command...>
    local name="$1"; shift
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    printf '%s\n' "$out" > "$log/macos26-$name.log"
    if grep -qE 'Symbol not found|Library not loaded|dyld' <<< "$out"; then
        echo "RED  $name: the loader refused the binary (needs a newer macOS?): $(grep -m1 -E 'Symbol not found|Library not loaded|dyld' <<< "$out" | cut -c1-160)"
        red=1
    elif ((rc != 0)); then
        echo "RED  $name: exit $rc"
        red=1
    else
        echo "ok   $name"
    fi
}

if [[ -x "$dir/AdaptiveSound" ]]; then
    for mode in stop start device-loss ended-advance; do
        check "stall-$mode" "$dir/AdaptiveSound" -ASMainThreadStall "$mode"
    done
else
    echo "RED  AdaptiveSound: not in $dir"; red=1
fi
if [[ -x "$dir/DSPKernelNullTest" ]]; then
    check null-correctness "$dir/DSPKernelNullTest" --tier=correctness
else
    echo "RED  DSPKernelNullTest: not in $dir"; red=1
fi
if [[ -x "$dir/VerifyAUGraph" ]]; then
    check verify-au-graph "$dir/VerifyAUGraph"
else
    echo "RED  VerifyAUGraph: not in $dir"; red=1
fi

if ((red)); then
    echo "macOS 26 RUN: FAILED. Logs: $log/macos26-*.log"
    exit 1
fi
echo "macOS 26 RUN: PASSED"
