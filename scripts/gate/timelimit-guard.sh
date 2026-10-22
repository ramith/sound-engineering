#!/usr/bin/env bash
#
# timelimit-guard.sh — runs timelimit-guard.py on the real Tests/ tree (must pass) and on a planted
# fixture with one waiting suite that has no limit (must fail). The planted case proves the guard can fail.
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1
guard="$repo_root/scripts/gate/timelimit-guard.py"

python3 "$guard" Tests > /dev/null || { python3 "$guard" Tests; echo "ERROR: the Tests/ tree has a waiting suite without .timeLimit" >&2; exit 1; }
count="$(python3 "$guard" Tests | sed -nE 's/^GATE_COVERED ([0-9]+) .*/\1/p')"

planted="${GATE_RUN_DIR:-$repo_root/.build/gate}/timelimit-planted"
rm -rf "$planted"; mkdir -p "$planted"
cat > "$planted/Planted.swift" <<'SWIFT'
@Suite("planted: waits, no limit")
struct Planted {
    @Test func waits() async { await until { true } }
}
SWIFT
if python3 "$guard" "$planted" > /dev/null; then
    echo "ERROR: the planted waiting suite (no .timeLimit) was NOT caught: the guard cannot fail" >&2
    exit 1
fi
echo "planted waiting suite without .timeLimit: caught (exit 1, as required)."
echo "GATE_COVERED ${count:-0} waiting-file-suites"
