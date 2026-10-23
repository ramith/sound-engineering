#!/usr/bin/env bash
#
# registry-lint.sh — runs registry-lint.py on the real registry and workflows (must pass), then on a PLANTED
# bad registry (a misspelt job, a row without ci, a malformed timeout): it must fail, or the lint cannot fail.
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1
lint="$repo_root/scripts/gate/registry-lint.py"

scratch="${GATE_RUN_DIR:-$repo_root/.build/gate}"
mkdir -p "$scratch"
real="$scratch/registry-lint.out"
python3 "$lint" > "$real" 2>&1 || { cat "$real"; echo "ERROR: the real registry does not agree with CI" >&2; exit 1; }
grep -v '^GATE_COVERED' "$real"
rows="$(sed -nE 's/^GATE_COVERED ([0-9]+) rows/\1/p' "$real")"

planted="${GATE_RUN_DIR:-$repo_root/.build/gate}/registry-planted.tsv"
mkdir -p "$(dirname "$planted")"
printf 'id\tjob\ttiers\tblocking\ttimeout\tcoverage\tneeds\tcommand\nbad-job\tstat\tci\tyes\t2m\tfiles\t-\ttrue\nbad-tier\tstatic\tpush\tyes\t2m\tfiles\t-\ttrue\nbad-timeout\tstatic\tci\tyes\t2 minutes\tfiles\t-\ttrue\n' > "$planted"
out="$(python3 "$lint" --registry "$planted" 2>&1)"
rc=$?
if ((rc == 0)); then echo "ERROR: the planted bad registry passed the lint" >&2; exit 1; fi
for want in "job 'stat'" "tiers 'push' lack ci" "timeout '2 minutes'"; do
    grep -qF "$want" <<< "$out" || { echo "ERROR: the lint missed the planted problem: $want" >&2; exit 1; }
done
echo "planted bad registry: 3 of 3 problems caught (exit $rc)."
echo "GATE_COVERED ${rows:-0} rows"
