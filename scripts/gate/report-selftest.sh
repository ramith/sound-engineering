#!/usr/bin/env bash
#
# report-selftest.sh — proves the strict-gate summary (report.sh / result.py summary) on fixture trees built
# from the REAL registry, so it runs on every local gate and in the static job, not first on GitHub.
#
# Cases (each must exit with the stated code and name its problem):
#   all-pass   every registry step passed; decoy JSON files that are not step records sit beside them -> 0
#   failure    one blocking step failed                                                          -> 1
#   timeout    one blocking step timed out                                                       -> 1
#   missing    one job never reported (no run.json)                                              -> 1
#   stale      one job's run.json is from another run                                            -> 1
#   duplicate  one job has two run.json files                                                    -> 1
#   malformed  one record is not a valid step record                                             -> 1
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

base="${GATE_RUN_DIR:-$repo_root/.build/gate}/report-selftest"
rm -rf "$base"
mkdir -p "$base"
failures=0

# build <case> <dir>: writes the fixture tree for one case.
build() {
    python3 - "$1" "$2" "$repo_root/scripts/gate/steps.tsv" <<'PY'
import json, os, sys
case, root, reg = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
for line in open(reg, encoding="utf-8"):
    if not line.strip() or line.startswith("#") or line.startswith("id\t"):
        continue
    c = line.rstrip("\n").split("\t")
    rows.append((c[0], c[1], c[3] == "yes"))
jobs = []
for _, j, _ in rows:
    if j not in jobs:
        jobs.append(j)
stamp = "local"
target_job = jobs[0]
target_step = next(sid for sid, j, _ in rows if j == target_job)
for job in jobs:
    art = os.path.join(root, "gate-" + job)
    if case == "missing" and job == jobs[-1]:
        continue
    os.makedirs(os.path.join(art, "gate-run", "results"), exist_ok=True)
    run_stamp = "99.1.stale" if (case == "stale" and job == jobs[-1]) else stamp
    run = {"mode": "job", "selector": job, "exit_code": 0, "stamp": run_stamp}
    with open(os.path.join(art, "gate-run", "run.json"), "w") as fh:
        json.dump(run, fh)
    if case == "duplicate" and job == jobs[1]:
        os.makedirs(os.path.join(art, "gate-run-2"), exist_ok=True)
        with open(os.path.join(art, "gate-run-2", "run.json"), "w") as fh:
            json.dump(run, fh)
    for sid, j, blocking in rows:
        if j != job:
            continue
        status, code = "pass", 0
        if case == "failure" and sid == target_step:
            status, code = "fail", 1
        if case == "timeout" and sid == target_step:
            status, code = "timeout", 124
        rec = {"id": sid, "job": job, "run": stamp, "blocking": blocking, "status": status,
               "exit_code": code, "duration_s": 1, "timeout": "1m", "reason": "fixture " + status,
               "coverage_rule": "-", "covered": None, "log": "-", "failing_lines": []}
        if case == "malformed" and sid == target_step:
            rec = {"id": sid}
        with open(os.path.join(art, "gate-run", "results", sid + ".json"), "w") as fh:
            json.dump(rec, fh)
    if job == target_job:
        # decoys that are NOT step records (the shape B1 broke on): semgrep and GoogleTest output
        with open(os.path.join(art, "gate-run", "semgrep-scan.json"), "w") as fh:
            json.dump({"results": [], "errors": [], "paths": {"scanned": []}}, fh)
        os.makedirs(os.path.join(art, "gate-run", "null", "null-debug"), exist_ok=True)
        with open(os.path.join(art, "gate-run", "null", "null-debug", "result.shard1.json"), "w") as fh:
            json.dump({"tests": 3, "failures": 0, "testsuites": []}, fh)
PY
}

expect() {  # expect <case> <exit> <text that must appear>
    local case="$1" want="$2" text="$3" dir="$base/$1" out rc
    build "$case" "$dir"
    # The fixtures carry the stamp "local". In CI the real run identity is in the environment, so clear it here:
    # the cases test the rules, not the CI stamp (the CI stamp is exercised by the real run).
    out="$(env -u GITHUB_RUN_ID -u GITHUB_RUN_ATTEMPT -u GITHUB_SHA bash "$repo_root/scripts/gate/report.sh" "$dir" 2>&1)"
    rc=$?
    if [[ "$rc" != "$want" ]]; then
        echo "FAIL $case: exit $rc, expected $want"; printf '%s\n' "$out" | tail -8; failures=$((failures + 1)); return
    fi
    if [[ -n "$text" ]] && ! grep -qF "$text" <<< "$out"; then
        echo "FAIL $case: exit $rc as expected, but the row '$text' is missing"; failures=$((failures + 1)); return
    fi
    echo "ok   $case: exit $rc${text:+, row: $text}"
}

expect all-pass 0 "VERDICT: PASS"
expect failure 1 "blocking step"
expect timeout 1 "blocking step"
expect missing 1 "expected exactly one run.json"
expect stale 1 "from another run"
expect duplicate 1 "expected exactly one run.json"
expect malformed 1 "malformed record"

if ((failures)); then
    echo "report self-test: $failures case(s) failed"
    exit 1
fi
echo "report self-test: 7 of 7 cases behave"
echo "GATE_COVERED 7 cases"
