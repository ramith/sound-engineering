#!/usr/bin/env bash
#
# scripts/gate/report.sh <dir> — the CI `strict-gate` summary. Reads every job's gate artifact under
# <dir> (gate-results/gate-<job>/...) and writes ONE table to $GITHUB_STEP_SUMMARY (and stdout).
#
# Its exit code is the verdict of the whole PR or main commit. It is red when:
#   - a job never reported (its run.json is missing: cancelled, timed out, or crashed before the runner
#     wrote its verdict). A job that did not report is a failure, never an absence of failures;
#   - a registry step for that job has no result record (a step lost in the middle of a run);
#   - any blocking step did not pass (fail, timeout, or skipped), or a record cannot be read.
# Advisory rows are shown and never turn it red.
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

dir="${1:-}"
[[ -n "$dir" && -d "$dir" ]] || { echo "ERROR: report.sh needs the directory of downloaded gate artifacts" >&2; exit 2; }

jobs="static swift cpp asan tsan"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

# Missing job reports and missing step records, one problem per line.
missing="$(python3 - "$dir" "$repo_root/scripts/gate/steps.tsv" $jobs <<'PY'
import glob, os, sys
root, registry, jobs = sys.argv[1], sys.argv[2], sys.argv[3:]
expected = {j: [] for j in jobs}
for line in open(registry, encoding="utf-8"):
    if not line.strip() or line.startswith("#") or line.startswith("id\t"):
        continue
    cols = line.rstrip("\n").split("\t")
    if cols[1] in expected:
        expected[cols[1]].append(cols[0])
for job in jobs:
    art = os.path.join(root, "gate-" + job)
    if not glob.glob(os.path.join(art, "**", "run.json"), recursive=True):
        print("job %s did not report: no run.json in its gate artifact (cancelled, timed out or crashed)" % job)
        continue
    have = {os.path.basename(p)[:-5]
            for p in glob.glob(os.path.join(art, "**", "results", "*.json"), recursive=True)}
    for sid in expected[job]:
        if sid not in have:
            print("job %s: step %s has no result record (lost in the run)" % (job, sid))
PY
)"

python3 "$repo_root/scripts/gate/result.py" render "$dir" > "$tmp"
table_rc=$?

{
    echo "## strict-gate"
    echo
    echo "Every job ran its registry steps to completion. Failures show their head; full logs are in each job's gate artifact."
    echo
    cat "$tmp"
    if [[ -n "$missing" ]]; then
        echo
        echo "### Missing reports (each is a failure)"
        while IFS= read -r line; do echo "- $line"; done <<< "$missing"
    fi
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
if [[ -n "$missing" ]]; then
    printf '%s\n' "$missing" >&2
    echo "strict-gate: FAILED (missing reports)" >&2
    exit 1
fi
if ((table_rc != 0)); then
    echo "strict-gate: FAILED (a blocking step did not pass; see the table)" >&2
    exit 1
fi
echo "strict-gate: PASSED"
exit 0
