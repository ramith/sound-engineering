#!/bin/bash
# research/eq-engine-break-it/run-clang-tidy.sh — clang-tidy one or more repo-relative C++ files
# with exactly the flags the pre-commit hook / strict gate use (Tests/* get the test extras).
# Usage (from the repo root): bash research/eq-engine-break-it/run-clang-tidy.sh <file>…
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1
# shellcheck source=scripts/lib/cxx-analysis-flags.sh
source "$REPO_ROOT/scripts/lib/cxx-analysis-flags.sh"
CLANG_TIDY="$(cxx_clang_tidy_path)"
status=0
for f in "$@"; do
    extra=""
    case "$f" in Tests/* | research/eq-engine-break-it/*) extra="$(cxx_test_extra_flags) -I$REPO_ROOT/Tests" ;; esac
    # shellcheck disable=SC2046,SC2086  # intentional word-splitting of the space-separated flags
    if ! "$CLANG_TIDY" "$f" --quiet --use-color=false -- $(cxx_lang_flags "$f") $(cxx_analysis_core_flags) $extra; then
        status=1
    fi
done
exit $status
