#!/usr/bin/env bash
#
# scripts/gate/null-run.sh <build-null-test.sh flags...> — runs the C++ null test through its script and
# turns its output into gate evidence:
#   - every GoogleTest JSON written for this run (plain, or sharded: <name>.shard<i>.json and .serial.json)
#     is read; the TOTAL test count is printed as GATE_COVERED, so a run that executed 0 tests fails;
#   - any failed test fails the step, with its name;
#   - exit 134 with NO JSON is a named hang: the null test's watchdog printed a "[HANG] <test>" line and
#     aborted. The runner reports it as a hang (not a generic failure).
#
# The JSON goes to $GATE_RUN_DIR/null/ (or .build/gate/null/ outside a gate run), so sharded and
# serial files for one run stay together and are not mixed with an older run.
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

out_dir="${GATE_RUN_DIR:-$repo_root/.build/gate}/null"
rm -rf "$out_dir"
mkdir -p "$out_dir" || { echo "ERROR: cannot create $out_dir" >&2; exit 1; }
json="$out_dir/result.json"

bash scripts/build-null-test.sh "$@" "--gtest_output=json:$json"
rc=$?

count="$(python3 - "$out_dir" <<'PY'
import glob, json, os, sys
files = sorted(glob.glob(os.path.join(sys.argv[1], "*.json")))
tests = failures = 0
bad = []
for f in files:
    try:
        data = json.load(open(f, encoding="utf-8"))
    except (OSError, ValueError) as exc:
        bad.append("%s unreadable: %s" % (os.path.basename(f), exc))
        continue
    tests += int(data.get("tests", 0))
    failures += int(data.get("failures", 0))
    for suite in data.get("testsuites", []):
        for case in suite.get("testsuite", []):
            if case.get("failures"):
                bad.append("FAILED %s.%s" % (suite.get("name"), case.get("name")))
print("%d %d %d" % (len(files), tests, failures))
for line in bad:
    print(line, file=sys.stderr)
PY
)"
read -r nfiles tests failures <<< "$count"

if ((rc == 134)) && ((nfiles == 0)); then
    echo "NAMED HANG: the null test's watchdog aborted (exit 134) and wrote no JSON. The [HANG] line above names the test." >&2
    exit 134
fi
((rc == 0)) || { echo "ERROR: the null test failed (exit $rc). See the failing tests above." >&2; exit "$rc"; }
((nfiles >= 1)) || { echo "ERROR: exit 0 but no GoogleTest JSON was written: the run's evidence is missing." >&2; exit 1; }
((failures == 0)) || { echo "ERROR: $failures failed test(s) in the JSON." >&2; exit 1; }
((tests >= 1)) || { echo "ERROR: the null test ran 0 tests (a filter that selects nothing is a failure)." >&2; exit 1; }
echo "null test: $tests tests in $nfiles result file(s), 0 failures."
echo "GATE_COVERED $tests tests"
