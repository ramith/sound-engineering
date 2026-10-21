#!/usr/bin/env bash
#
# clang-format dry run (drift = failure) over every TRACKED C++ header and source under Sources/ and
# Tests/. .mm is excluded on purpose: clang-format no-ops Obj-C++ with this Cpp-only config and prints
# a notice that --Werror would misread (see .clang-format). .mm formatting rides on the pre-commit hook.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

files=()
while IFS= read -r f; do files+=("$f"); done < <(tracked Sources Tests | grep -E '\.(h|hpp|cpp|cc)$')
((${#files[@]})) || fail "git lists 0 tracked C++ sources under Sources/ and Tests/: the scope is broken"

clang-format --dry-run --Werror "${files[@]}" || fail "clang-format drift: run 'make format' and commit the result."
covered "${#files[@]}" cpp-files
