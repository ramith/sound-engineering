#!/usr/bin/env bash
#
# Semgrep rule self-tests: every rule in .semgrep.yml must FLAG a line it is meant to flag and must
# NOT flag the same token inside a comment (architect §4.3, BT-5).
#
# semgrep --test only resolves one rule per file (named <rule-id>.yaml, with its fixture beside it),
# so this step splits the single .semgrep.yml into one file per rule in a scratch directory, pairs
# each with scripts/gate/semgrep-fixtures/<rule-id>.<ext>, and runs semgrep --test there.
# A rule with no fixture FAILS: an untested rule is not a checked rule.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

fixtures="$repo_root/scripts/gate/semgrep-fixtures"
scratch="${GATE_RUN_DIR:-$repo_root/.build/gate}"
mkdir -p "$scratch" || fail "cannot create $scratch"
work="$(mktemp -d "$scratch/semgrep-rules.XXXXXX")" || fail "cannot create a scratch directory"
trap 'rm -rf "$work"' EXIT

# Split the rules: one <id>.yaml per rule (the chunk from "  - id:" to the next rule), and copy its fixture.
split_out="$(python3 - "$repo_root/.semgrep.yml" "$work" "$fixtures" <<'PY'
import glob, os, re, shutil, sys
src, work, fixtures = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(src, encoding="utf-8").read()
chunks = re.split(r"(?m)^(?=  - id: )", text)[1:]
ids, missing = [], []
for chunk in chunks:
    rid = re.match(r"  - id: (\S+)", chunk).group(1)
    ids.append(rid)
    fx = sorted(glob.glob(os.path.join(fixtures, rid + ".*")))
    if not fx:
        missing.append(rid)
        continue
    with open(os.path.join(work, rid + ".yaml"), "w", encoding="utf-8") as fh:
        fh.write("rules:\n" + chunk)
    for f in fx:
        shutil.copy(f, work)
extra = sorted(os.path.basename(p).split(".")[0] for p in glob.glob(os.path.join(fixtures, "*")))
orphans = sorted(set(extra) - set(ids))
for rid in missing:
    print("MISSING-FIXTURE %s" % rid)
for rid in orphans:
    print("ORPHAN-FIXTURE %s (no rule with that id in .semgrep.yml)" % rid)
print("RULES %d" % len(ids))
PY
)"
echo "$split_out" | grep -v '^RULES '
rules="$(sed -nE 's/^RULES ([0-9]+)$/\1/p' <<< "$split_out")"
[[ -n "$rules" ]] || fail "could not split .semgrep.yml into rules"
((rules >= 1)) || fail "0 rules in .semgrep.yml: nothing to test is not a pass"
if grep -qE '^(MISSING-FIXTURE|ORPHAN-FIXTURE) ' <<< "$split_out"; then
    fail "every rule needs a fixture in scripts/gate/semgrep-fixtures/ and every fixture needs a rule (see above)"
fi

(cd "$work" && semgrep --test --metrics=off .)
rc=$?
((rc == 0)) || fail "a Semgrep rule self-test failed (exit $rc): a rule no longer flags its ruleid line, or flags its ok line"
covered "$rules" rules
