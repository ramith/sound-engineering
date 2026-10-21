#!/usr/bin/env bash
#
# Main-thread stall self-test (S10.8 G, the disconnect freeze): the real engine bridge and view model
# on an OFFLINE engine, with AVFAudio's engine-wide lock held on purpose until the TEST releases it,
# in four modes. Judged by BEHAVIOUR, not a stopwatch (sprint decision 6): the run passes only if the
# main thread keeps finishing its work while the lock is held; a main thread that touches the lock
# cannot, and a hang cap fails the run naming what main was inside. Any non-zero exit fails the step
# and names the mode; all four modes must run (the coverage rule).
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
