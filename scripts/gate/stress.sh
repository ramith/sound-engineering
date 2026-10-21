#!/usr/bin/env bash
#
# make stress TEST=<filter> N=<n> [KIND=swift|cpp] — repeat a concurrency-sensitive test under the
# CI-like profile, and report every iteration. The verdict is the exit code.
#
# CI-like profile (what the hosted runner does to a test, made local):
#   1. CONTENTION: ncpu-3 CPU hogs (`yes`) in their OWN process group. A trap kills the group on
#      EXIT, INT and TERM, so a leaked busy loop can never outlive the run (16 once did, on the Mac).
#   2. NARROW SCHEDULING (Swift): LIBDISPATCH_COOPERATIVE_POOL_STRICT=1, width 1, harsher than
#      CI's 3-core runners, which is the side to err on for flakes.
#   3. HARD CAP per iteration (STRESS_TIMEOUT, default 600s): a hang is killed and named.
#
# Swift: loops `swift test --skip-build --filter TEST`, and every iteration must run >= 1 test.
# C++:   scripts/build-null-test.sh with --shards 3 --gtest_filter=TEST --gtest_repeat=N
#        --gtest_shuffle and a printed --gtest_random_seed (TEST is a GoogleTest filter, e.g.
#        'Concurrent.*' for the Concurrent tier or 'Concurrent.Loudness_*').
#
# Environment: TEST (required), N (default 20), KIND (default swift), STRESS_TIMEOUT (default 600),
#              STRESS_HOGS (default ncpu-3), PROFILE=ci-like (default; `none` disables the hogs).
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

TEST="${TEST:-}"
N="${N:-20}"
KIND="${KIND:-swift}"
STRESS_TIMEOUT="${STRESS_TIMEOUT:-600}"
PROFILE="${PROFILE:-ci-like}"

[[ -n "$TEST" ]] || fail "make stress needs TEST=<filter> (a function or type name, not a display name), e.g. make stress TEST=prefetchPromoted N=50"
[[ "$N" =~ ^[0-9]+$ ]] && ((N >= 1)) || fail "N must be a positive integer (got '$N')"

ncpu="$(sysctl -n hw.ncpu)"
hogs="${STRESS_HOGS:-$((ncpu - 3))}"
((hogs < 0)) && hogs=0

# ------------------------------------------------------------ hogs in their own process group
# Each hog is its OWN job and process group (job control gives every background job one), so the
# kill walks the recorded pids: group and pid for each. Killing only one group leaked 10 hogs once.
hog_pids=()
kill_hogs() {
    local p
    ((${#hog_pids[@]})) || return 0
    for p in "${hog_pids[@]}"; do kill -TERM -- "-$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; done
    sleep 1
    for p in "${hog_pids[@]}"; do kill -KILL -- "-$p" 2>/dev/null; kill -KILL "$p" 2>/dev/null; done
    hog_pids=()
}
trap 'kill_hogs' EXIT INT TERM

if [[ "$PROFILE" == "ci-like" ]] && ((hogs > 0)); then
    set -m
    for _ in $(seq 1 "$hogs"); do
        yes >/dev/null 2>&1 &
        hog_pids+=("$!")
    done
    set +m
    echo "load: $hogs CPU hog(s), pids ${hog_pids[*]} (each its own process group; all killed on exit)"
elif [[ "$PROFILE" == "ci-like" ]]; then
    echo "load: none (ncpu=$ncpu leaves no room for hogs)"
fi

echo "profile: $PROFILE  kind: $KIND  test: $TEST  iterations: $N  cap per iteration: ${STRESS_TIMEOUT}s"

# run_iteration <index> <command...>: one run under a cap; sets ITER_OUT and ITER_RC.
run_iteration() {
    local idx="$1"; shift
    local log dir
    dir="${GATE_RUN_DIR:-$repo_root/.build/gate}"
    mkdir -p "$dir" || fail "cannot create $dir for the stress logs"
    log="$(mktemp "$dir/stress-$idx.XXXXXX")" || fail "cannot create a stress log in $dir"
    ( set -m; "$@" >"$log" 2>&1 ) &
    local pid=$!
    local pgid="$pid"
    # The watcher's stderr is closed: killed mid-`sleep` when the run ends first, bash would print
    # "Terminated: 15 sleep" into the stress output (and `wait` its job notice when a run is capped).
    ( exec 2>/dev/null; sleep "$STRESS_TIMEOUT"; kill -0 -- "-$pgid" 2>/dev/null && { kill -TERM -- "-$pgid" 2>/dev/null; sleep 5; kill -KILL -- "-$pgid" 2>/dev/null; echo "CAP" > "$log.cap"; } ) &
    local wd=$!
    wait "$pid" 2>/dev/null
    ITER_RC=$?
    # The cap watcher is not in its own group (only the step is), so kill it and its sleep by pid.
    pkill -P "$wd" 2>/dev/null
    kill "$wd" 2>/dev/null
    wait "$wd" 2>/dev/null
    if [[ -f "$log.cap" ]]; then ITER_RC=124; rm -f "$log.cap"; fi
    ITER_OUT="$log"
}

passed=0
failed=0
if [[ "$KIND" == "swift" ]]; then
    export LIBDISPATCH_COOPERATIVE_POOL_STRICT="${LIBDISPATCH_COOPERATIVE_POOL_STRICT:-1}"
    echo "LIBDISPATCH_COOPERATIVE_POOL_STRICT=$LIBDISPATCH_COOPERATIVE_POOL_STRICT"
    swift build --build-tests -c debug -j 8 >/dev/null 2>&1 || fail "swift build --build-tests failed: build before stressing"
    for i in $(seq 1 "$N"); do
        run_iteration "$i" swift test --skip-build --filter "$TEST"
        # Sum over every target's "Test run with N tests" line (Xcode 27 prints one per target).
        ran="$(python3 -c 'import re,sys; print(sum(int(m) for m in re.findall(r"Test run with (\d+) tests? in ", open(sys.argv[1]).read())))' "$ITER_OUT")"
        if grep -qE 'Failed to open test bundle|Fatal error|Symbol not found' "$ITER_OUT"; then ran=0; fi
        if ((ITER_RC == 0)) && [[ -n "$ran" ]] && ((ran >= 1)); then
            passed=$((passed + 1))
        else
            failed=$((failed + 1))
            echo "iteration $i/$N FAILED (exit $ITER_RC, tests run: ${ran:-none}); log: $ITER_OUT"
            sed -n '1,60p' "$ITER_OUT" | grep -iE 'error|fail|expect|issue|timed out|cap' | head -20 | sed 's/^/    | /'
        fi
    done
elif [[ "$KIND" == "cpp" ]]; then
    # The C++ runner's repeat, filter and shuffle flags (Lane B). Until the combined branch has them,
    # a C++ stress run is refused, not faked.
    if ! grep -q -- '--gtest_repeat' scripts/build-null-test.sh; then
        fail "KIND=cpp needs scripts/build-null-test.sh with --gtest_repeat (Lane B). Not on this branch yet."
    fi
    seed="${SEED:-$(( (RANDOM * 32768 + RANDOM) % 99999 + 1 ))}"
    echo "C++ shuffle seed: $seed (rerun with SEED=$seed to reproduce the order)"
    # One process, no shards: a stress filter is usually one test or a few, and a shard that selects
    # none fails by design (--gtest_fail_if_no_test_selected). Repetition, not splitting, is the point.
    run_iteration 1 bash scripts/gate/null-run.sh "--gtest_filter=$TEST" "--gtest_repeat=$N" \
        --gtest_shuffle "--gtest_random_seed=$seed"
    if ((ITER_RC == 0)); then passed=$N; else failed=$N; echo "C++ stress FAILED: the run of $N shuffled repeats exited $ITER_RC; log: $ITER_OUT"; fi
else
    fail "KIND must be swift or cpp (got '$KIND')"
fi

echo
echo "STRESS: $passed/$N passed, $failed failed  (test '$TEST', profile $PROFILE, kind $KIND)"
kill_hogs
((failed == 0)) || fail "stress: $failed of $N iterations failed. Fix the flake; do not retry it away."
covered "$passed" iterations
