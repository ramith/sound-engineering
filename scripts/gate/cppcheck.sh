#!/usr/bin/env bash
#
# cppcheck over the tracked C++ translation units of AudioDSP and its test bridge.
#
# cppcheck is a VERDICT tool now (pinned in toolchain/toolchain.env, parity-checked), so it is no
# longer optional: a missing binary is a parity failure, not a skip. Warnings/style/performance/
# portability, not --enable=all (noisy on Obj-C++ / Apple SDK interaction); inline suppressions are
# honoured and each one must pass the suppression policy (scripts/check-suppressions.sh).
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

files=()
while IFS= read -r f; do files+=("$f"); done < <(tracked Sources/AudioDSP Sources/AudioDSPTestBridge | grep -E '\.(cpp|cc|c)$')
((${#files[@]})) || fail "git lists 0 cppcheck-analysable sources under Sources/AudioDSP: the scope is broken"

cppcheck \
    --enable=warning,style,performance,portability \
    --error-exitcode=1 \
    --inline-suppr \
    --std=c++23 \
    --quiet \
    "${files[@]}" || fail "cppcheck reported findings above (or failed to run)."
covered "${#files[@]}" translation-units
