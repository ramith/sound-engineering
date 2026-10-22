#!/usr/bin/env bash
#
# swift test, with the ZERO-TESTS guard and the load-failure guard.
#
# Xcode 27's SwiftPM (the swiftbuild engine) runs each test target separately and prints one
# "Test run with N tests" line PER TARGET. So the guard SUMS them: a total of 0 fails, and so does any
# target that never ran. A misspelt --filter runs 0 tests and exits 0, which this turns into a failure.
#
# A target that fails to LOAD (its bundle will not open, a symbol is missing) prints its error and the
# other targets still print green lines, so the load errors are failures even when the exit code and
# the totals look fine.
#
#   scripts/gate/swift-test.sh                  # everything
#   TEST=<regex> scripts/gate/swift-test.sh     # --filter; matches function/type names, NOT @Test display names
#   PART=main scripts/gate/swift-test.sh        # everything but the heavy real-engine rig suites (parallel)
#   PART=rig  scripts/gate/swift-test.sh        # only those suites, one test at a time (--no-parallel)
#
# The rig suites (the Enhanced* suites) each build a real offline AVAudioEngine graph, render it and
# register AU subclasses process-wide; run beside ~950 parallel tests they load the runner and share
# process state (hazard R10). The pattern is anchored on the type name: other tests mention "Enhanced".
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

rig_suites='AdaptiveSoundTests\.Enhanced[A-Za-z]*Tests/'
args=()
case "${PART:-all}" in
    all) ;;
    main) args+=(--skip "$rig_suites") ;;
    rig) args+=(--no-parallel --filter "$rig_suites") ;;
    *) fail "PART must be all, main or rig (got '${PART}')" ;;
esac
[[ -n "${TEST:-}" ]] && args+=(--filter "$TEST")

out="$(swift test ${args[@]+"${args[@]}"} 2>&1)"
rc=$?
printf '%s\n' "$out"

# Load failures: fatal whatever the totals say.
if grep -qE 'Failed to open test bundle|Fatal error|Symbol not found' <<< "$out"; then
    fail "a test bundle failed to load (Failed to open test bundle / Fatal error / Symbol not found). Other targets' green lines do not cover it."
fi
((rc == 0)) || fail "swift test failed (exit $rc). The failing tests are listed above."

# swift-testing: "Test run with N tests in M suites passed" (one line per target); XCTest: "Executed N tests".
total="$(python3 -c '
import re, sys
text = sys.stdin.read()
n = sum(int(m) for m in re.findall(r"Test run with (\d+) tests? in ", text))
n += sum(int(m) for m in re.findall(r"Executed (\d+) tests?, with ", text))
lines = len(re.findall(r"Test run with \d+ tests? in |Executed \d+ tests?, with ", text))
print(n, lines)
' <<< "$out")"
n="${total%% *}"
runs="${total##* }"
[[ -n "$n" && -n "$runs" ]] || fail "could not read a test count from swift test's output: the step cannot prove anything ran"
((runs >= 1)) || fail "swift test printed no 'Test run' or 'Executed' line: nothing reported a run"
((n >= 1)) || fail "swift test ran 0 tests in total (part='${PART:-all}', filter='${TEST:-<none>}'). A misspelt filter runs nothing and exits 0; that is a failure."
echo "swift test: $n tests across $runs target run line(s)."
covered "$n" tests
