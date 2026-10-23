#!/usr/bin/env bash
#
# actionlint over every tracked workflow under .github/workflows (pinned in toolchain/toolchain.env).
#
# ShellCheck is pinned in the manifest and is found on PATH by the parity check (scripts/toolchain/check.sh),
# so actionlint runs it on every run: block here: the verdict never depends on a tool nobody pinned.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

files=()
while IFS= read -r f; do files+=("$f"); done < <(tracked '.github/workflows/*.yml' '.github/workflows/*.yaml')
((${#files[@]})) || fail "git lists 0 workflow files under .github/workflows"

actionlint "${files[@]}" || fail "actionlint found problems in the workflows (above)."
covered "${#files[@]}" workflows
