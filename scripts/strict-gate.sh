#!/usr/bin/env bash
#
# strict-gate.sh — the local pre-merge gate for AdaptiveSound.
#
# Runs the FULL set of quality/safety checks and fails on the first problem. This is the
# repo-wide net (the pre-commit hook is only a fast, staged-files convenience). Run before
# opening/merging a PR:  `make strict-gate`
#
# Ordering is fail-fast: cheap static checks first (formatting, lint, static analysis),
# then the expensive builds/tests/sanitizers.
#
# A missing REQUIRED tool is a hard failure here (unlike the pre-commit hook, which may
# skip). Slow checks (sanitizers) belong in this pre-merge gate, not the commit hook.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# --------------------------------------------------------------------------- helpers
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
green() { printf '\033[32m%s\033[0m\n' "$*"; }
step()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

require_tool() {
  if ! command -v "$1" >/dev/null 2>&1; then
    red "ERROR: required tool missing: $1"
    red "       install it (see docs/development/DEVELOPMENT.md) and re-run."
    exit 1
  fi
}

# --------------------------------------------------------------------------- tool check
step "Tool check"
require_tool swift
require_tool xcrun
require_tool clang-format
require_tool swiftformat
require_tool swiftlint
require_tool semgrep
require_tool make

# clang-tidy is keg-only under Homebrew LLVM; prefer that path, fall back to PATH. It is
# REQUIRED (not skipped) so the pre-commit C++ static-analysis net is guaranteed to work.
if [[ -x /opt/homebrew/opt/llvm/bin/clang-tidy ]]; then
  CLANG_TIDY=/opt/homebrew/opt/llvm/bin/clang-tidy
elif command -v clang-tidy >/dev/null 2>&1; then
  CLANG_TIDY="$(command -v clang-tidy)"
else
  red "ERROR: required tool missing: clang-tidy (brew install llvm)"
  exit 1
fi
echo "clang-tidy: $CLANG_TIDY"
# cppcheck is optional; a supplementary C++ pass runs only if it is installed.
HAVE_CPPCHECK=0
command -v cppcheck >/dev/null 2>&1 && HAVE_CPPCHECK=1
echo "all required tools present."

# --------------------------------------------------------------------------- static checks
step "SwiftFormat lint (drift = failure)"
swiftformat Sources Tests --lint

step "SwiftLint strict (every warning is a failure)"
swiftlint lint --strict

step "clang-format dry-run (drift = failure)"
# .mm (Obj-C++) EXCLUDED on purpose: clang-format no-ops .mm with this Cpp-only config and
# emits a "does not support Objective-C" notice that --Werror would misread as failure (see
# .clang-format). .mm formatting rides on pre-commit; .mm correctness on clang-tidy/sanitizers.
find Sources Tests -type f \
  \( -name '*.h' -o -name '*.hpp' -o -name '*.cpp' -o -name '*.cc' \) \
  -print0 | xargs -0 clang-format --dry-run --Werror

step "Semgrep (Swift force-try/force-cast bans)"
semgrep scan --config .semgrep.yml --error --quiet

step "Suppression policy (owner/reason/expiry accountability)"
bash scripts/check-suppressions.sh

if [[ "$HAVE_CPPCHECK" == "1" ]]; then
  step "cppcheck (supplementary C++ analysis)"
  # Start strict-but-useful: warnings/style/perf/portability, not --enable=all (which is
  # noisy on Obj-C++ / Apple SDK interaction). inline-suppr honours // cppcheck-suppress.
  # useStlAlgorithm is an ADVISORY style nag ("prefer std::find_if/accumulate over a raw
  # loop"). The few sites it flags are clear as-is in RT-adjacent DSP code and reduce to
  # lambda noise if rewritten — not a correctness/safety issue. Suppressed to keep cppcheck
  # "strict but useful, not noisy" (guide §13). All warning/perf/portability checks stay on.
  cppcheck \
    --enable=warning,style,performance,portability \
    --error-exitcode=1 \
    --inline-suppr \
    --suppress=missingIncludeSystem \
    --suppress=useStlAlgorithm \
    --std=c++23 \
    --quiet \
    Sources/AudioDSP Sources/AudioDSPTestBridge
else
  step "cppcheck (SKIPPED — not installed; optional)"
fi

# --------------------------------------------------------------------------- builds / tests
step "Swift build (debug) — Swift 6 data-race checking + C++ -Werror"
swift build -c debug

step "Swift test"
swift test

step "make gate (C++ null test + VerifyAUGraph + VerifyLibraryStore)"
make gate

step "Sanitizer gates (ASan/UBSan + TSan + library-store ASan)"
make sanitize
make tsan
make sanitize-library-store

green "
=========================================
   STRICT GATE PASSED
=========================================
"
