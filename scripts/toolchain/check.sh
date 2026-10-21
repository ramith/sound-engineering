#!/usr/bin/env bash
#
# scripts/toolchain/check.sh — the toolchain PARITY check. Step one of every gate tier.
#
# Prints one table (tool, expected, actual, verdict) and exits non-zero if any row is FAIL.
#
#   FAIL (locally and in CI): every tool that decides a verdict, by EXACT version. A 2.21 -> 2.22
#        cppcheck or a 23.1.2 -> 23.1.3 clang-tidy was enough to turn a green PR red (PR #91).
#   Xcode and Swift: EXACT (the Xcode build, 27.1 27A9275), everywhere. A Mac on another Xcode fails with
#        the fix. macOS: INFO only, never fails (the founder accepted 26.6 locally vs the 27.0.1 CI image).
#   WARN locally, FAIL in CI: the FFmpeg headers.
#   CI only: the runner image date must be at least RUNNER_IMAGE_MIN.
#
# Run it with the same PATH the gate uses (the runner does this for you):
#   scripts/toolchain/check.sh
# Test a planted wrong manifest (the self-test that proves the hard fail):
#   TOOLCHAIN_ENV=/path/to/wrong.env scripts/toolchain/check.sh
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest="${TOOLCHAIN_ENV:-$repo_root/toolchain/toolchain.env}"
[[ -f "$manifest" ]] || { echo "ERROR: manifest not found: $manifest" >&2; exit 1; }
# shellcheck source=toolchain/toolchain.env
set -a; source "$manifest"; set +a

# Put the installed toolchain first, exactly as the gate does (the install script's bin dir).
# The REAL install dir (the real manifest): TOOLCHAIN_ENV only changes the expectations below,
# so a planted wrong manifest is compared against what is actually installed.
bin_dir="$(env -u TOOLCHAIN_ENV "$repo_root/scripts/toolchain/install.sh" --print-bin)"
export PATH="$bin_dir:$PATH"

in_ci="${CI:-}"
rows=()
fails=0
warns=0

# row <tool> <expected> <actual> <verdict> — verdict is OK, FAIL or WARN.
row() {
    rows+=("$(printf '%-16s %-22s %-40s %s' "$1" "$2" "$3" "$4")")
    case "$4" in
        FAIL) fails=$((fails + 1)) ;;
        WARN) warns=$((warns + 1)) ;;
    esac
}

# exact <tool> <expected> <actual> — a verdict tool: exact match or FAIL, everywhere.
exact() {
    local tool="$1" want="$2" got="$3"
    if [[ "$got" == *"$want"* ]]; then
        row "$tool" "$want" "$got" "OK"
    else
        row "$tool" "$want" "${got:-<missing>}" "FAIL"
    fi
}

# patch <label> <expected> <actual> <fix> — environment: WARN locally, FAIL in CI.
patch() {
    local label="$1" want="$2" got="$3" fix="$4"
    if [[ "$got" == *"$want"* ]]; then
        row "$label" "$want" "$got" "OK"
    elif [[ -n "$in_ci" ]]; then
        row "$label" "$want" "$got" "FAIL"
    else
        row "$label" "$want" "$got" "WARN"
        WARN_NOTES+=("$label: $fix")
    fi
}
WARN_NOTES=()

# ---------------------------------------------------------------- verdict tools (exact)
exact "swiftformat"  "$SWIFTFORMAT_VERSION" "$(swiftformat --version 2>/dev/null)"
exact "swiftlint"    "$SWIFTLINT_VERSION"   "$(swiftlint --version 2>/dev/null)"
exact "periphery"    "$PERIPHERY_VERSION"   "$(periphery version 2>/dev/null)"
exact "clang-format" "$LLVM_VERSION"        "$(clang-format --version 2>/dev/null | sed -nE 's/.*version ([0-9.]+).*/\1/p' | head -1)"
exact "clang-tidy"   "$LLVM_VERSION"        "$(clang-tidy --version 2>/dev/null | sed -nE 's/.*version ([0-9.]+).*/\1/p' | head -1)"
exact "cppcheck"     "$CPPCHECK_VERSION"    "$(cppcheck --version 2>/dev/null)"
exact "semgrep"      "$SEMGREP_VERSION"     "$(semgrep --version 2>/dev/null)"
# semgrep-core is the engine the verdicts come from: a stale core under a pinned CLI would change results.
exact "semgrep-core" "$SEMGREP_VERSION"    "$(semgrep-core -version 2>/dev/null | sed -nE 's/.*version: ([0-9.]+).*/\1/p')"
exact "actionlint"   "$ACTIONLINT_VERSION"  "$(actionlint -version 2>/dev/null | head -1)"

# The C++ analysis library pins a clang-tidy MAJOR of its own (scripts/lib/cxx-analysis-flags.sh).
# It must agree with the manifest's LLVM major, or the two halves of the gate analyse differently.
lib_major="$(bash --norc -c "source '$repo_root/scripts/lib/cxx-analysis-flags.sh'; printf '%s' \"\$CXX_CLANG_TIDY_MAJOR_PIN\"" 2>/dev/null)"
if [[ "$lib_major" == "$LLVM_MAJOR" ]]; then
    row "clang-tidy pin" "major $LLVM_MAJOR" "library pins major $lib_major" "OK"
else
    row "clang-tidy pin" "major $LLVM_MAJOR" "library pins major ${lib_major:-<none>}" "FAIL"
fi

# semgrep's lock must pin the same version as the manifest.
if grep -qE "^semgrep==${SEMGREP_VERSION} " "$repo_root/scripts/toolchain/semgrep-requirements.txt"; then
    row "semgrep lock" "semgrep==$SEMGREP_VERSION" "semgrep-requirements.txt" "OK"
else
    row "semgrep lock" "semgrep==$SEMGREP_VERSION" "semgrep-requirements.txt disagrees" "FAIL"
fi

# GoogleTest (the C++ runner's framework): the submodule must be the commit the manifest pins.
if [[ -n "${GOOGLETEST_COMMIT:-}" ]]; then
    gt_actual="$(git -C "$repo_root/third_party/googletest" rev-parse HEAD 2>/dev/null || true)"
    exact "googletest" "$GOOGLETEST_COMMIT" "${gt_actual:-<submodule missing: git submodule update --init third_party/googletest>}"
else
    row "googletest" "GOOGLETEST_COMMIT" "not in toolchain/toolchain.env" "FAIL"
fi

# ---------------------------------------------------------------- Xcode / Swift (EXACT) and macOS (info)
# The Xcode BUILD is exact everywhere: 27.1 (27A9275) on the Mac and on CI. Swift comes with that Xcode,
# so its version is exact too. Both are verdict tools: a different Xcode changes what the gate analyses.
xcode_build="$(xcodebuild -version 2>/dev/null | sed -nE 's/^Build version (.+)$/\1/p' | head -1)"
xcode_ver="$(xcodebuild -version 2>/dev/null | sed -nE 's/^Xcode ([0-9.]+).*/\1/p' | head -1)"
if [[ "$xcode_ver" == "$XCODE_VERSION" && "$xcode_build" == "$XCODE_BUILD" ]]; then
    row "xcode" "$XCODE_VERSION ($XCODE_BUILD)" "$xcode_ver ($xcode_build)" "OK"
else
    row "xcode" "$XCODE_VERSION ($XCODE_BUILD)" "${xcode_ver:-<none>} (${xcode_build:-<none>})" "FAIL"
    if [[ -z "$in_ci" ]]; then
        WARN_NOTES+=("xcode: this Mac is not on $XCODE_VERSION ($XCODE_BUILD). Update Xcode (App Store, or developer.apple.com/download), then re-run this check. The gate cannot pass on another Xcode.")
    fi
fi
swift_actual="$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9.]+).*/\1/p' | head -1)"
exact "swift" "$SWIFT_VERSION" "${swift_actual:-}"

# macOS: INFO only. The founder accepted the Mac (26.6) vs CI image (27.0.1) difference. It never fails.
macos_actual="$(sw_vers -productVersion 2>/dev/null)"
row "macos (info)" "CI image $MACOS_CI_IMAGE" "local $macos_actual" "INFO"

# CI only: the runner image must be new enough. GitHub sets ImageVersion on hosted runners.
if [[ -n "$in_ci" ]]; then
    image="${ImageVersion:-}"
    if [[ -z "$image" ]]; then
        row "runner image" ">= $RUNNER_IMAGE_MIN" "<unknown: ImageVersion unset>" "FAIL"
    elif [[ "${image%%.*}" -ge "$RUNNER_IMAGE_MIN" ]]; then
        row "runner image" ">= $RUNNER_IMAGE_MIN" "$image" "OK"
    else
        row "runner image" ">= $RUNNER_IMAGE_MIN" "$image" "FAIL"
    fi
fi

# ---------------------------------------------------------------- FFmpeg headers (asserted from the header)
ff_header="/opt/homebrew/include/libavutil/ffversion.h"
ff_actual="$(sed -nE 's/^#define FFMPEG_VERSION "([^"]+)".*/\1/p' "$ff_header" 2>/dev/null | head -1)"
patch "ffmpeg headers" "$FFMPEG_HEADERS_VERSION" "${ff_actual:-<not installed>}" \
    "install FFmpeg headers with 'brew install ffmpeg' (or 'brew upgrade ffmpeg' to move to $FFMPEG_HEADERS_VERSION); the FileDecodeSource FFmpeg branch is only analysed when they are present"

# ---------------------------------------------------------------- the table
printf '\n%-16s %-22s %-40s %s\n' "TOOL" "EXPECTED" "ACTUAL" "VERDICT"
printf '%s\n' "$(printf '%.0s-' {1..92})"
for r in "${rows[@]}"; do printf '%s\n' "$r"; done
printf '\n'

if ((${#WARN_NOTES[@]})); then
    echo "Warnings (local only; CI would fail on these):"
    for n in "${WARN_NOTES[@]}"; do echo "  - $n"; done
    echo
fi

if ((fails)); then
    echo "PARITY FAILED: $fails verdict-deciding row(s) differ from toolchain/toolchain.env." >&2
    echo "Fix: scripts/toolchain/install.sh, then put its bin dir first on PATH (see the script header)." >&2
    exit 1
fi
echo "PARITY OK ($warns warning(s))."
exit 0
