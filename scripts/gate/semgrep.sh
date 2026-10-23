#!/usr/bin/env bash
#
# semgrep over the tracked tree with .semgrep.yml (--error: any finding fails).
#
# Coverage is the number of files semgrep actually scanned (its JSON "paths.scanned"), so a config or
# ignore mistake that scans nothing fails instead of passing. Findings are printed from the JSON.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

json="${GATE_RUN_DIR:-$repo_root/.build/gate}/semgrep-scan.json"
mkdir -p "$(dirname "$json")"

semgrep scan --config .semgrep.yml --error --metrics=off --quiet --json --output "$json" >/dev/null 2>&1
rc=$?

scanned="$(python3 - "$json" <<'PY'
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except (OSError, ValueError) as exc:
    print("UNREADABLE %s" % exc)
    sys.exit(0)
for r in data.get("results", []):
    msg = (r.get("extra", {}).get("message", "") or "").splitlines()
    print("%s:%s: [%s] %s" % (r["path"], r["start"]["line"], r["check_id"], msg[0] if msg else ""))
for e in data.get("errors", []):
    print("semgrep error: %s" % e.get("message", e))
print("SCANNED %d" % len(data.get("paths", {}).get("scanned", [])))
PY
)"
printf '%s\n' "$(grep -v '^SCANNED ' <<< "$scanned")"
if grep -q '^UNREADABLE' <<< "$scanned"; then
    fail "semgrep's JSON report could not be read: ${scanned#UNREADABLE }"
fi
((rc == 0)) || fail "semgrep found problems (exit $rc). Each finding is listed above."

n="$(sed -nE 's/^SCANNED ([0-9]+)$/\1/p' <<< "$scanned")"
[[ -n "$n" ]] || fail "semgrep reported no scanned-file count"
((n >= 1)) || fail "semgrep scanned 0 files: the config or ignore file has excluded the whole tree"
covered "$n" files
