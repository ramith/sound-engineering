#!/usr/bin/env bash
#
# scripts/gate/canary.sh — the weekly toolchain canary (ADVISORY: it never fails a PR).
#
# Asks what a bump would do BEFORE the bump is forced by a red PR. For each tool it compares the pinned
# version with the latest upstream release, then runs the cheap verdict steps (SwiftFormat, SwiftLint,
# semgrep, actionlint) with the LATEST binaries from a scratch bin dir, and writes one markdown report.
# The workflow opens or updates ONE issue from that report.
#
# Not run with the latest version (version comparison only, too heavy for a weekly probe):
#   LLVM (clang-tidy and clang-format) and cppcheck, which build from source; Periphery's index run.
#
# Writes: $CANARY_DIR/canary-report.md (default .build/gate/canary). Exit code is always 0 unless the
# probe itself could not run (a broken canary must be visible, but must not block merges).
set -uo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1
set -a; source toolchain/toolchain.env; set +a

out_dir="${CANARY_DIR:-$repo_root/.build/gate/canary}"
mkdir -p "$out_dir/bin" || { echo "canary: cannot create $out_dir" >&2; exit 1; }
report="$out_dir/canary-report.md"
work="$out_dir/work"; mkdir -p "$work"

latest_tag() { gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null; }
row() { printf '| %s | %s | %s | %s |\n' "$1" "$2" "$3" "$4" >> "$report"; }

{
    echo "# Toolchain canary"
    echo
    echo "Advisory: this report never fails a PR. A row marked BUMP means the latest release differs from the pin."
    echo
    echo "| tool | pinned | latest upstream | canary run with latest |"
    echo "|---|---|---|---|"
} > "$report"

# ---- SwiftFormat, SwiftLint: GitHub release zips
sf_latest="$(latest_tag nicklockwood/SwiftFormat | sed 's/^v//')"
sl_latest="$(latest_tag realm/SwiftLint | sed 's/^v//')"
if [[ -n "$sf_latest" ]] && curl -fsSL -o "$work/swiftformat.zip" "https://github.com/nicklockwood/SwiftFormat/releases/download/$sf_latest/swiftformat.zip"; then
    unzip -o -q "$work/swiftformat.zip" swiftformat -d "$out_dir/bin"
fi
if [[ -n "$sl_latest" ]] && curl -fsSL -o "$work/swiftlint.zip" "https://github.com/realm/SwiftLint/releases/download/$sl_latest/portable_swiftlint.zip"; then
    unzip -o -q "$work/swiftlint.zip" swiftlint -d "$out_dir/bin"
fi
# ---- semgrep: latest from PyPI, no hash lock (advisory only)
sg_latest="$(curl -fsSL https://pypi.org/pypi/semgrep/json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"])' 2>/dev/null)"
if [[ -n "$sg_latest" ]] && python3 -m venv "$work/semgrep-venv" && "$work/semgrep-venv/bin/pip" install --quiet "semgrep==$sg_latest"; then
    ln -sf "$work/semgrep-venv/bin/semgrep" "$out_dir/bin/semgrep"
fi
# ---- actionlint
al_latest="$(latest_tag rhysd/actionlint | sed 's/^v//')"
if [[ -n "$al_latest" ]] && curl -fsSL -o "$work/al.tgz" "https://github.com/rhysd/actionlint/releases/download/v$al_latest/actionlint_${al_latest}_darwin_arm64.tar.gz"; then
    tar -xzf "$work/al.tgz" -C "$out_dir/bin" actionlint
fi

# ---- the version rows
row "SwiftFormat" "$SWIFTFORMAT_VERSION" "${sf_latest:-?}" "$( [[ "${sf_latest:-}" == "$SWIFTFORMAT_VERSION" ]] && echo same || echo BUMP )"
row "SwiftLint" "$SWIFTLINT_VERSION" "${sl_latest:-?}" "$( [[ "${sl_latest:-}" == "$SWIFTLINT_VERSION" ]] && echo same || echo BUMP )"
row "semgrep" "$SEMGREP_VERSION" "${sg_latest:-?}" "$( [[ "${sg_latest:-}" == "$SEMGREP_VERSION" ]] && echo same || echo BUMP )"
row "actionlint" "$ACTIONLINT_VERSION" "${al_latest:-?}" "$( [[ "${al_latest:-}" == "$ACTIONLINT_VERSION" ]] && echo same || echo BUMP )"
row "Periphery" "$PERIPHERY_VERSION" "$(latest_tag peripheryapp/periphery | sed 's/^v//')" "not run (index build; version only)"
row "LLVM (clang-tidy, clang-format)" "$LLVM_VERSION" "$(latest_tag llvm/llvm-project | sed 's/^llvmorg-//')" "not run (heavy; version only)"
row "cppcheck" "$CPPCHECK_VERSION" "$(latest_tag danmar/cppcheck)" "not run (source build; version only)"

# ---- the latest-binary static steps (they never read the manifest; PATH decides the tools)
{
    echo
    echo "## Static steps with the latest binaries"
    echo
} >> "$report"
export PATH="$out_dir/bin:$PATH"
for step in swiftformat swiftlint semgrep actionlint; do
    log="$out_dir/$step.log"
    case "$step" in
        swiftformat) cmd=(bash scripts/gate/swiftformat.sh) ;;
        swiftlint)   cmd=(bash scripts/gate/swiftlint.sh) ;;
        semgrep)     cmd=(bash scripts/gate/semgrep.sh) ;;
        actionlint)  cmd=(bash scripts/gate/actionlint.sh) ;;
    esac
    if "${cmd[@]}" >"$log" 2>&1; then verdict="passes"; else verdict="FAILS (see the head below)"; fi
    printf -- '- **%s** with the latest binary: %s\n' "$step" "$verdict" >> "$report"
    if [[ "$verdict" != passes ]]; then
        printf '\n```\n' >> "$report"
        grep -iE 'error|warning|fail|violation' "$log" | head -30 >> "$report"
        printf '```\n\n' >> "$report"
    fi
done

cat "$report"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then cat "$report" >> "$GITHUB_STEP_SUMMARY"; fi
exit 0
