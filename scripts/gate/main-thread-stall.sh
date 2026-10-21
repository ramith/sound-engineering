#!/usr/bin/env bash
#
# Main-thread stall self-test (S10.8 G, the disconnect freeze): the real engine bridge and view model
# on an OFFLINE engine, with AVFAudio's engine-wide lock held on purpose for 2.5 s, in four modes.
# Any non-zero exit fails the step and names the mode.
#
# The oracle is Lane B/C's to change (judged by behaviour, not a 25 ms timer, per the sprint's
# founder decision 6). This script only runs the binary and counts the modes it ran, so the
# coverage rule holds: all four modes must run.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

swift build -c debug -j 8 || fail "debug build failed (main-thread-stall)"
BIN="$(swift build -c debug --show-bin-path)"
ran=0
for mode in stop start device-loss ended-advance; do
    echo "-- main-thread-stall mode: $mode"
    "$BIN/AdaptiveSound" -ASMainThreadStall "$mode" || fail "main-thread-stall mode '$mode' failed"
    ran=$((ran + 1))
done
covered "$ran" modes
