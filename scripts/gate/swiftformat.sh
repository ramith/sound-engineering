#!/usr/bin/env bash
#
# SwiftFormat drift check (lint only, never mutates) over every TRACKED Swift file.
#
# Worktree-safe (architect §4.1): SwiftFormat walks up to the parent checkout's .swiftformat unless
# told otherwise, so the config is passed explicitly from THIS repo root. Files are the explicit
# tracked list, so a skipped file cannot pass silently; the step also fails if SwiftFormat reports
# any skipped file or lints fewer files than git lists.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

files=()
while IFS= read -r f; do files+=("$f"); done < <(tracked '*.swift' | grep -vE '^(docs/|scripts/gate/semgrep-fixtures/)')
((${#files[@]})) || fail "git lists 0 tracked Swift files: nothing to lint is not a pass"

out="$(swiftformat --lint --config "$repo_root/.swiftformat" "${files[@]}" 2>&1)"
rc=$?
printf '%s\n' "$out"
((rc == 0)) || fail "SwiftFormat drift (exit $rc). Fix it with: make format (in place), then commit."

if grep -qi 'skipped' <<< "$out"; then
    fail "SwiftFormat skipped files (see above): a skipped file is not a lint pass"
fi
linted="$(sed -nE 's#^[0-9]+/([0-9]+) files? require formatting.*#\1#p' <<< "$out" | tail -1)"
[[ -n "$linted" ]] || fail "could not read SwiftFormat's file count from its output"
((linted == ${#files[@]})) || fail "SwiftFormat linted $linted of ${#files[@]} tracked Swift files"
covered "$linted" swift-files
