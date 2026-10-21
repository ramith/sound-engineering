#!/usr/bin/env bash
#
# actionlint over every tracked workflow under .github/workflows (pinned in toolchain/toolchain.env).
#
# shellcheck is deliberately NOT run by actionlint here: it would decide a verdict with a tool that
# is not in the manifest, so the verdict would depend on whatever happens to be installed. The run:
# blocks are still parsed and type-checked by actionlint itself.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

files=()
while IFS= read -r f; do files+=("$f"); done < <(tracked '.github/workflows/*.yml' '.github/workflows/*.yaml')
((${#files[@]})) || fail "git lists 0 workflow files under .github/workflows"

actionlint -shellcheck= "${files[@]}" || fail "actionlint found problems in the workflows (above)."
covered "${#files[@]}" workflows
