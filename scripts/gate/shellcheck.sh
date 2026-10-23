#!/usr/bin/env bash
#
# ShellCheck over every TRACKED shell script and the git hooks (the workflows' run: blocks are checked by
# actionlint, which calls the same pinned ShellCheck from PATH). The version is pinned in toolchain/toolchain.env
# and checked by the parity step, so a finding never depends on what happens to be installed.
#
# Scope: docs/ and research/ are excluded, as they are for SwiftLint, SwiftFormat and Semgrep: they are archived
# experiments that nothing builds or runs. Zero suppressions: a finding is fixed at its root, never disabled.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

files=()
while IFS= read -r f; do
    [[ -f "$f" ]] && files+=("$f")
done < <(tracked '*.sh' '.githooks/*' | grep -vE '^(docs|research)/')
((${#files[@]})) || fail "git lists 0 tracked shell scripts: nothing to check is not a pass"

command -v shellcheck >/dev/null 2>&1 || fail "shellcheck is not on PATH: the toolchain is not installed (make toolchain)"
shellcheck -x "${files[@]}" || fail "ShellCheck reported findings above. Fix them at the root; do not disable a rule."
covered "${#files[@]}" shell-files
