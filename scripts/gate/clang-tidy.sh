#!/usr/bin/env bash
#
# clang-tidy over AudioDSP, its test bridge and the tests (.clang-tidy enforcement, WarningsAsErrors).
#
# The parse flags come from scripts/lib/cxx-analysis-flags.sh, the single source shared with the
# pre-commit hook and build-null-test.sh, so the gate analyses the SAME translation units the compiler
# builds. The binary is the toolchain's clang-tidy (first on PATH, parity-checked against the
# manifest), not whatever the library's own resolver finds.
#
# Every bad file is reported, then the step fails once. A 0-file scope fails loudly (never a silent green).
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1
# shellcheck source=scripts/lib/cxx-analysis-flags.sh
source "$repo_root/scripts/lib/cxx-analysis-flags.sh"

CLANG_TIDY="$(command -v clang-tidy || true)"
[[ -n "$CLANG_TIDY" ]] || fail "clang-tidy is not on PATH: the toolchain is not installed (scripts/toolchain/install.sh)"

fail_count=0
analysed=0

# analyse <file> <extra-flags...> — one translation unit; accumulates failures instead of stopping.
analyse() {
    local f="$1" extra="${2:-}"
    local out lang=() core=() xtra=()
    read -r -a lang <<< "$(cxx_lang_flags "$f")"
    read -r -a core <<< "$(cxx_analysis_core_flags)"
    read -r -a xtra <<< "$extra"
    analysed=$((analysed + 1))
    if ! out="$("$CLANG_TIDY" "$f" --quiet --use-color=false -- ${lang[@]+"${lang[@]}"} ${core[@]+"${core[@]}"} ${xtra[@]+"${xtra[@]}"} 2>&1)"; then
        echo "clang-tidy findings in $f:"
        printf '%s\n' "$out"
        fail_count=$((fail_count + 1))
    fi
}

# Production pass: AudioDSP and the Obj-C++ test bridge (the bridge's public header needs its own -I).
while IFS= read -r f; do
    case "$f" in
        Sources/AudioDSPTestBridge/*) analyse "$f" "$(cxx_bridge_extra_flags)" ;;
        *) analyse "$f" ;;
    esac
done < <(tracked Sources/AudioDSP Sources/AudioDSPTestBridge | grep -E '\.(cpp|mm|cc)$')

# Test pass: Tests/*.{cpp,mm,cc} with the test-only extras (libebur128, fixtures dir, test-data dir).
while IFS= read -r f; do
    analyse "$f" "$(cxx_test_extra_flags)"
done < <(tracked Tests | grep -E '\.(cpp|mm|cc)$')

((analysed > 0)) || fail "clang-tidy analysed 0 files: the source scope is broken (Sources/AudioDSP renamed or emptied?)"
if ((fail_count)); then
    fail "clang-tidy reported findings in $fail_count file(s) (WarningsAsErrors per .clang-tidy). Fix them above."
fi
echo "clang-tidy clean across $analysed files."
covered "$analysed" translation-units
