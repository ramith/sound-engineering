#!/usr/bin/env bash
#
# SwiftLint strict over every TRACKED Swift file (every warning is a failure).
#
# Worktree-safe, like swiftformat.sh: the config is explicit, the file list is explicit, and the
# step fails if SwiftLint reports fewer linted files than git lists.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

files=()
while IFS= read -r f; do files+=("$f"); done < <(tracked '*.swift' | grep -vE '^(docs/|scripts/gate/semgrep-fixtures/)')
((${#files[@]})) || fail "git lists 0 tracked Swift files: nothing to lint is not a pass"

out="$(swiftlint lint --strict --config "$repo_root/.swiftlint.yml" "${files[@]}" 2>&1)"
rc=$?
printf '%s\n' "$out"
((rc == 0)) || fail "SwiftLint strict failed (exit $rc): every warning and error is a failure here."

linted="$(sed -nE 's/.*Done linting! Found [0-9]+ violations?, [0-9]+ serious in ([0-9]+) files?\..*/\1/p' <<< "$out" | tail -1)"
[[ -n "$linted" ]] || fail "could not read SwiftLint's file count from its summary line"
((linted == ${#files[@]})) || fail "SwiftLint linted $linted of ${#files[@]} tracked Swift files"
covered "$linted" swift-files
