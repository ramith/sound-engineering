# shellcheck shell=bash
#
# scripts/lib/cxx-analysis-flags.sh
#
# SINGLE SOURCE OF TRUTH for the clang-tidy / static-analysis PARSE flags used to
# analyse this repo's C++ / Obj-C++. This is a *sourceable library* (no shebang, not
# executable, no top-level side effects) — it only defines functions.
#
# Sourced by:
#   - .githooks/pre-commit         (clang-tidy over STAGED C++/Obj-C++ files)
#   - scripts/strict-gate.sh       (clang-tidy over the whole AudioDSP tree + tests)
#   - (planned) scripts/build-null-test.sh
#
# WHY THIS EXISTS: these flags MUST stay matched to the PRODUCTION compile in
# scripts/build-null-test.sh (the clang++ invocation that actually compiles this C++
# into the test binary). Analysis has to parse the SAME translation units the compiler
# does — otherwise `__has_include(<...>)` branches (notably the FFmpeg decode + metadata
# bridge in FileDecodeSource.cpp, gated on <libavformat/avformat.h>) silently diverge
# between build and analysis, and the -D defines / -fno-exceptions / -isystem paths that
# make those branches parse would be missing. If you change a compile flag in
# build-null-test.sh, mirror it here (and vice-versa).
#
# Callers consume the functions' space-separated stdout via unquoted command
# substitution (word-splitting). Every path in this repo is space-free, which this
# design relies on.

# Repo root, derived from THIS file's own location (scripts/lib/ -> two levels up), so
# the flags are correct no matter what the caller's working directory is.
_cxx_flags_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_cxx_repo_root="$(cd "$_cxx_flags_lib_dir/../.." && pwd)"

# cxx_analysis_core_flags — the AUTHORITATIVE core parse flags shared by every C++/
# Obj-C++ translation unit. Mirrors the clang++ invocation in build-null-test.sh minus
# the warning flags (-Wall/-Wextra) and the test-only extras (see cxx_test_extra_flags).
# -isysroot is resolved live via `xcrun --show-sdk-path` so it tracks the active SDK.
cxx_analysis_core_flags() {
    local flags=(
        -std=gnu++2b
        -isysroot "$(xcrun --show-sdk-path)"
        -fno-exceptions
        -fno-rtti
        -D_LIBCPP_DISABLE_AVAILABILITY
        -DACCELERATE_NEW_LAPACK
        -I "$_cxx_repo_root/Sources/AudioDSP"
        -I "$_cxx_repo_root/Sources/AudioDSP/include"
        -isystem /opt/homebrew/include
    )
    printf '%s ' "${flags[@]}"
}

# cxx_test_extra_flags — the TEST-ONLY additions layered on top of the core flags for
# translation units under Tests/: the vendored libebur128 oracle headers (a submodule)
# and two quoted-string-literal path macros. The embedded double quotes are intentional
# and survive the caller's word-splitting because the repo path is space-free.
#   - ADAPTIVESOUND_TEST_DATA_DIR — the DSP-kernel null-test data dir.
#   - ADAPTIVE_FIXTURES_DIR       — the audio fixtures dir; Tests/HandleLeakHarness.mm hard
#     `#error`s without it, so it must live HERE (not injected per-caller) or the pre-commit
#     hook and the strict-gate tests-pass would drift — build-leak-check.sh passes the same
#     value for the actual harness build.
cxx_test_extra_flags() {
    local flags=(
        -I "$_cxx_repo_root/third_party/libebur128/ebur128"
        "-DADAPTIVESOUND_TEST_DATA_DIR=\"$_cxx_repo_root/test-data\""
        "-DADAPTIVE_FIXTURES_DIR=\"$_cxx_repo_root/Tests/Fixtures/artwork-audio\""
    )
    printf '%s ' "${flags[@]}"
}

# cxx_bridge_extra_flags — the extra include needed to analyse the Obj-C++ test-support
# bridge under Sources/AudioDSPTestBridge. Its public C-ABI header (EQTestBridge.h) lives
# in include/, so analysing EQTestBridge.mm needs that dir on the search path. Kept OUT of
# the core set (and separate, like cxx_test_extra_flags) on purpose: the bridge is compiled
# by SwiftPM via its module map, NEVER by build-null-test.sh, so build-null-test.sh has no
# such -I — and the core must stay byte-for-byte matched to build-null-test.sh. Callers
# layer this on only for Sources/AudioDSPTestBridge/* files. (This restores what the old
# pre-commit resolved via its broad `find … -type d` include-dir sweep.)
cxx_bridge_extra_flags() {
    printf '%s ' -I "$_cxx_repo_root/Sources/AudioDSPTestBridge/include"
}

# cxx_lang_flags <path> — the per-file language-mode flags. Project headers may be
# Obj-C++, so .h/.hpp are analysed in objective-c++ mode (a superset that also parses
# pure C++); everything else is plain C++. Always emits at least one flag.
cxx_lang_flags() {
    case "$1" in
        *.mm|*.h|*.hpp) printf '%s ' -x objective-c++ -fobjc-arc -fblocks ;;
        *)              printf '%s ' -x c++ ;;
    esac
}

# ---------------------------------------------------------------------------------------
# clang-tidy resolution + MAJOR-version pin (the tool-skew doctrine, C++ side).
#
# clang-tidy majors ADD checks: LLVM 23 introduced readability-trailing-comma,
# readability-redundant-lambda-parameter-list, modernize-use-string-view,
# portability-no-assembler… — a brew-latest major bump on hosted CI surfaced as ~120
# red-herring findings the local 22 gate had passed (PR #63 run 1). Like SWIFTFORMAT_PIN /
# SWIFTLINT_PIN in strict-gate.sh, the major is pinned HERE (one place, consumed by the gate
# and the pre-commit hook) and installed pinned in .github/workflows/strict-ci.yml
# (`brew install llvm@N`). A deliberate upgrade bumps this pin + the workflow's llvm@N and
# fixes the new findings in the SAME commit (last bumped 22→23, S10.8 part 2).
CXX_CLANG_TIDY_MAJOR_PIN=23

# cxx_clang_tidy_path — the pinned clang-tidy binary, or nothing (exit 1) when absent.
# Order: the versioned Homebrew keg (opt/llvm@N — what `llvm@N` installs once N is no longer
# current), the unversioned keg (opt/llvm — `llvm@N` is an alias of `llvm` while N IS
# current), then PATH. Callers assert the major with cxx_clang_tidy_major.
cxx_clang_tidy_path() {
    local candidate
    for candidate in \
        "/opt/homebrew/opt/llvm@${CXX_CLANG_TIDY_MAJOR_PIN}/bin/clang-tidy" \
        /opt/homebrew/opt/llvm/bin/clang-tidy; do
        if [[ -x "$candidate" ]]; then
            printf '%s' "$candidate"
            return 0
        fi
    done
    command -v clang-tidy 2>/dev/null
}

# cxx_clang_tidy_major <clang-tidy> — "23" from `… version 23.1.0` (Homebrew and Apple
# builds both print "version <major>.<minor>…").
cxx_clang_tidy_major() {
    "$1" --version | sed -nE 's/.*version ([0-9]+)\..*/\1/p' | head -1
}
