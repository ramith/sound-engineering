#!/usr/bin/env bash
#
# scripts/gate/report.sh <artifact-root> — the CI `strict-gate` summary: one table, one verdict.
#
# All the rules live in scripts/gate/result.py (summary): one run.json per job, stamped with THIS run
# (GITHUB_RUN_ID / ATTEMPT / SHA), step records only under results/, and every problem a named RED row.
# This wrapper only prints the table to the log and to $GITHUB_STEP_SUMMARY, and exits with the verdict.
# Self-tested on every local run by the registry row report-selftest (scripts/gate/report-selftest.sh).
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

root="${1:-}"
[[ -n "$root" && -d "$root" ]] || { echo "ERROR: report.sh needs the directory of downloaded gate artifacts" >&2; exit 2; }

out="$(python3 "$repo_root/scripts/gate/result.py" summary "$root")"
rc=$?
{
    echo "## strict-gate"
    echo
    echo "Every job ran its registry steps to completion. Failures show their head; full logs are in each job's gate artifact."
    echo
    printf '%s\n' "$out"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
if ((rc == 0)); then
    echo "strict-gate: PASSED"
else
    echo "strict-gate: FAILED (see the RED rows above)" >&2
fi
exit "$rc"
