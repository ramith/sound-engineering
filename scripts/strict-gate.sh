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
red()    { printf '\033[31m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
step()   { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

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
require_tool periphery
require_tool make

# leaks(1) backs the leak-detection gate (make leak-check). It ships with the Xcode Command
# Line Tools but is not on PATH like a normal binary, so `require_tool` (command -v) misses it;
# resolve it via xcrun instead and fail hard if absent (this gate REQUIRES it).
xcrun --find leaks >/dev/null 2>&1 || { red "ERROR: leaks(1) missing (Xcode CLT)"; exit 1; }

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

step "Migrator posture guard (user data must never be erased on a schema change)"
# S10.3 ONE-STORE posture: LibraryStore holds NON-rebuildable USER data (playlists/folders + the
# track user-state columns), so a schema change must NEVER wipe it. Forbid ever re-enabling GRDB's
# eraseDatabaseOnSchemaChange, and assert the intended `= false` line is present — so a merge or
# refactor can't silently resurrect the old drop-and-recreate posture (break-it "Attack A"). The
# companion `additive-migration-convergence` VerifyLibraryStore check covers "Attack B" (an edited
# shipped migration body silently diverging existing users' schema).
migrator_src="Sources/LibraryStore/LibraryStore.swift"
if grep -nE 'eraseDatabaseOnSchemaChange[[:space:]]*=[[:space:]]*true' "$migrator_src"; then
  red "ERROR: eraseDatabaseOnSchemaChange = true in $migrator_src — this WIPES all user data on a"
  red "       schema change. Forbidden (S10.3 one-store posture holds playlists + track user-state)."
  exit 1
fi
if ! grep -qE 'eraseDatabaseOnSchemaChange[[:space:]]*=[[:space:]]*false' "$migrator_src"; then
  red "ERROR: '$migrator_src' must explicitly pin 'eraseDatabaseOnSchemaChange = false' (S10.3)."
  exit 1
fi
green "migrator posture ok (eraseDatabaseOnSchemaChange pinned false; never-erase)."

step "Playlist add/drop path must never move or copy files (US-PLIST-04 reference-add)"
# Adding a track to a playlist — via context menu, the picker sheet, or a drag-drop — is a
# REFERENCE-ADD by track id; it must NEVER touch the filesystem. Belt (on top of the type-level
# PlaylistDropRouter add-only outcome + the typed LibraryTrackDragItem drop a file-URL can't match):
# forbid FileManager move/copy anywhere in the playlist UI + model + drop-router + playlist DAO.
playlist_add_paths=(
  "Sources/AdaptiveSound/UI/Library/LibrarySidebar.swift"
  "Sources/AdaptiveSound/UI/Playlist/AddToPlaylistMenu.swift"
  "Sources/AdaptiveSound/PlaylistsModel.swift"
  "Sources/LibraryBrowseKit/PlaylistDropRouter.swift"
  "Sources/LibraryStore/LibraryStore+Playlists.swift"
)
if grep -nE '\.(moveItem|copyItem)\(' "${playlist_add_paths[@]}"; then
  red "ERROR: a playlist add/drop path references moveItem/copyItem — playlist membership is a"
  red "       reference-add by track id and must NEVER move or copy a file on disk (US-PLIST-04)."
  exit 1
fi
green "playlist add/drop path ok (no moveItem/copyItem — reference-add only)."

if [[ "$HAVE_CPPCHECK" == "1" ]]; then
  step "cppcheck (supplementary C++ analysis)"
  # Start strict-but-useful: warnings/style/perf/portability, not --enable=all (which is
  # noisy on Obj-C++ / Apple SDK interaction). inline-suppr honours // cppcheck-suppress.
  # NO blanket --suppress flags: the useStlAlgorithm sites were rewritten to real std
  # algorithms (std::ranges::max/find_if, std::array::fill) and missingIncludeSystem never
  # fires under this --enable set. Any future finding is fixed in source or carries an inline
  # // cppcheck-suppress with a reason (enforced by the suppression-policy gate above).
  cppcheck \
    --enable=warning,style,performance,portability \
    --error-exitcode=1 \
    --inline-suppr \
    --std=c++23 \
    --quiet \
    Sources/AudioDSP Sources/AudioDSPTestBridge
else
  step "cppcheck (SKIPPED — not installed; optional)"
fi

step "clang-tidy (.clang-tidy enforcement over AudioDSP + tests)"
# The parse flags come from the single source of truth shared with the pre-commit hook and
# build-null-test.sh, so this gate analyses the SAME translation units the compiler builds.
# This is what closes the biggest gate hole: until now .clang-tidy was enforced only by the
# bypassable pre-commit hook and NEVER by the merge gate. $CLANG_TIDY (resolved in the tool
# check) is finally USED here.
# shellcheck source=scripts/lib/cxx-analysis-flags.sh
source "$repo_root/scripts/lib/cxx-analysis-flags.sh"

# The FFmpeg decode + metadata branch in FileDecodeSource.cpp is behind
# __has_include(<libavformat/avformat.h>); clang-tidy only PARSES (hence analyses) it when
# the ffmpeg headers are installed. Warn loudly — but do NOT fail — locally when they are
# absent; CI (with ffmpeg installed) is the guaranteed coverage for that branch.
if [[ ! -f /opt/homebrew/include/libavformat/avformat.h ]]; then
  yellow "WARNING: libavformat headers not found under /opt/homebrew/include —"
  yellow "         the FFmpeg decode + metadata branch in FileDecodeSource.cpp will go"
  yellow "         UNANALYZED locally. Only CI (with ffmpeg installed) covers that branch."
  yellow "         Install locally with:  brew install ffmpeg"
fi

# Guarded per-file loops: `if ! ct_out=$(...)` keeps `set -e` from aborting before we can
# print the offending file's findings. clang_tidy_fail accumulates across BOTH passes so
# every bad file is reported, then the step fails once at the end. clang_tidy_analyzed counts
# the TUs actually fed to clang-tidy so a 0-file scope (e.g. a renamed/emptied Sources/AudioDSP)
# fails loudly instead of silently passing green.
# --use-color=false is passed to BOTH invocations (matching the pre-commit hook): .clang-tidy
# sets UseColor:true, which would otherwise emit raw ANSI escapes into captured CI output.
clang_tidy_fail=0
clang_tidy_analyzed=0

# Production pass — AudioDSP + the Obj-C++ test bridge. The bridge's public C-ABI header
# lives in Sources/AudioDSPTestBridge/include, so bridge TUs get that extra -I (see the
# flags library); AudioDSP proper needs core flags only.
while IFS= read -r f; do
  clang_tidy_analyzed=$((clang_tidy_analyzed + 1))
  bridge_extra=""
  case "$f" in Sources/AudioDSPTestBridge/*) bridge_extra="$(cxx_bridge_extra_flags)" ;; esac
  if ! ct_out="$("$CLANG_TIDY" "$f" --quiet --use-color=false -- $(cxx_lang_flags "$f") $(cxx_analysis_core_flags) $bridge_extra 2>&1)"; then
    red "clang-tidy findings in $f:"
    printf '%s\n' "$ct_out"
    clang_tidy_fail=1
  fi
done < <(find Sources/AudioDSP Sources/AudioDSPTestBridge -type f \( -name '*.cpp' -o -name '*.mm' -o -name '*.cc' \))

# Tests pass — Tests/*.{cpp,mm,cc} (core flags + cxx_test_extra_flags: libebur128 +
# test-data-dir + fixtures-dir). .mm included so the Obj-C++ leak harness
# (Tests/HandleLeakHarness.mm) is actually analysed — it was previously missed by a .cpp-only
# glob, which is how its findings slipped past the gate while the pre-commit hook (which globs
# .mm) would have caught them. .cc is included for the same forward-looking reason as the
# production pass (the Makefile/pre-commit treat it as first-class C++). cxx_lang_flags already
# selects -x objective-c++ -fobjc-arc -fblocks per file, exactly like the production pass. The
# harness hard-#errors unless ADAPTIVE_FIXTURES_DIR is defined; that now lives in
# cxx_test_extra_flags (shared with the pre-commit hook) so the two can't drift — no per-caller
# injection here. No -maxdepth: the pre-commit hook matches staged Tests/* at ANY depth, so the
# gate scans the same set (the .inc test fragments are #included into a TU, never matched by
# this {cpp,mm,cc} glob, and there are no nested standalone TUs today).
while IFS= read -r f; do
  clang_tidy_analyzed=$((clang_tidy_analyzed + 1))
  if ! ct_out="$("$CLANG_TIDY" "$f" --quiet --use-color=false -- $(cxx_lang_flags "$f") $(cxx_analysis_core_flags) $(cxx_test_extra_flags) 2>&1)"; then
    red "clang-tidy findings in $f:"
    printf '%s\n' "$ct_out"
    clang_tidy_fail=1
  fi
done < <(find Tests -type f \( -name '*.cpp' -o -name '*.mm' -o -name '*.cc' \))

# Analyzed-≥1-file guard: a 0-file run means the source scope is broken (Sources/AudioDSP
# renamed/emptied, a bad find, etc.). Without this, clang_tidy_fail stays 0 and the step would
# report a bogus "clean" — a silent green-pass. Fail hard instead.
if ((clang_tidy_analyzed == 0)); then
  red "clang-tidy analyzed 0 files — source scope is broken (Sources/AudioDSP renamed/emptied?)."
  exit 1
fi

if ((clang_tidy_fail)); then
  red "clang-tidy reported findings (build-breaking per .clang-tidy WarningsAsErrors). Fix them above."
  exit 1
fi
green "clang-tidy clean (0 findings across $clang_tidy_analyzed files)."

# --------------------------------------------------------------------------- dead code
step "Periphery (Swift dead-code detection — hostile config, --strict)"
# .periphery.yml sets strict:true (non-zero exit on ANY unused declaration), retain_public:false
# (analyze the app + its own SwiftPM libraries — there are no external consumers), and excludes
# Tests/ (mocks implement whole protocols tests exercise only in part). Deliberate keeps carry a
# `// periphery:ignore` + reason. Periphery builds its own SwiftPM index, so it heads the
# build/test section rather than the cheap static block above.
periphery scan

# --------------------------------------------------------------------------- builds / tests
step "Swift build (debug) — Swift 6 data-race checking + C++ -Werror"
swift build -c debug

step "Swift test"
swift test

step "make gate (C++ null test + VerifyAUGraph + VerifyLibraryStore)"
make gate

# --------------------------------------------------------------------------- null-test coverage guard
step "Null-test source-coverage drift guard"
# The null test compiles the PURE-DSP kernels but DELIBERATELY excludes the CoreAudio/AU/
# bridge glue that needs a live device / AU host. This guard fails if a NEW production
# .mm/.cpp/.cc under Sources/AudioDSP is neither compiled by the null test (and therefore run
# under -O2 -Werror below + the ASan/UBSan/TSan gates) NOR listed in the documented live-only
# allowlist — closing the "a new .mm silently escapes the null test / sanitizers" drift.
#
# ALLOWLIST — needs a live CoreAudio device / AU host — intentionally not in the standalone
# null test. Derived empirically as (find-all) minus (build-null-test.sh compile list); keep
# in sync when adding/removing a live-only glue file.
# NOTE: PureModeBridge.cpp + Loudness/LoudnessMeterBridge.cpp are allowlisted here (they link
# CoreAudio, so the null test can't build them) but ADDITIONALLY get runtime coverage from the
# leak-detection harness (make leak-check, Tests/HandleLeakHarness.mm) — their C-ABI handle
# lifecycles run under leaks(1) even though they stay out of the standalone null test.
# (CoreAudioDevice/PureModeBridge/LoudnessMeterBridge became .cpp in the .mm→.cpp migration; they
# remain live-only glue — CoreAudio-linked, no offline null-test coverage.)
null_test_allowlist=(
  Sources/AudioDSP/CoreAudioDevice.cpp
  Sources/AudioDSP/PureModeBridge.cpp
  Sources/AudioDSP/Loudness/LoudnessMeterBridge.cpp
  Sources/AudioDSP/AudioEngine/AUAudioUnit.mm
  Sources/AudioDSP/AudioEngine/HALOutputEngine.mm
  Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm
)
# uncovered = (every production .mm/.cpp/.cc) minus (files build-null-test.sh actually compiles,
# grepped straight out of the script so this tracks the real list) minus (the allowlist). The
# compile list is grepped (not re-hardcoded) so it can never drift from build-null-test.sh.
# The grep is SCOPED (via sed) to ONLY the `xcrun clang++ … -o "$OUTPUT"` compile block, not the
# whole script: this guards the dangerous OVER-COUNT direction — a Sources/AudioDSP/*.{mm,cpp,cc}
# path mentioned in a COMMENT elsewhere in build-null-test.sh would otherwise be counted as
# "covered" and MASK a genuinely-uncovered source. Only real compile-list entries count.
null_test_uncovered="$(
  comm -23 \
    <(find Sources/AudioDSP -type f \( -name '*.mm' -o -name '*.cpp' -o -name '*.cc' \) | sort -u) \
    <( { sed -n '/xcrun clang++/,/-o "\$OUTPUT"/p' scripts/build-null-test.sh \
           | grep -oE 'Sources/AudioDSP/[^"]+\.(mm|cpp|cc)'
         printf '%s\n' "${null_test_allowlist[@]}"; } | sort -u )
)"
if [[ -n "$null_test_uncovered" ]]; then
  while IFS= read -r src; do
    red "new production DSP source not covered by null-test/-O2/sanitizers: $src — add it to build-null-test.sh or the documented allowlist."
  done <<< "$null_test_uncovered"
  exit 1
fi
green "null-test source coverage complete (every production DSP source is compiled or documented live-only)."

# --------------------------------------------------------------------------- -O2 strict compile
step "Null test -O2 -Werror strict compile (optimization-only diagnostics)"
# Surfaces -O2-only real bugs the debug -Werror build can't see: -Warray-bounds (auto-enabled
# at -O2) and inlining-exposed uninitialised reads (-Wconditional-uninitialized). Build-only.
bash "$repo_root/scripts/build-null-test.sh" --release-strict

step "Sanitizer gates (ASan/UBSan + TSan + library-store ASan)"
make sanitize
make tsan
make sanitize-library-store

# Leak detection is the runtime complement to the sanitizers above: macOS/Apple-Silicon ASan
# ships NO LeakSanitizer, so leaks are otherwise invisible to this gate. Placed AFTER the
# sanitizer block because, like them, it is an expensive runtime check (builds + runs a
# dedicated harness twice under leaks(1), including a plant-a-leak self-test).
step "Leak detection (leaks(1) over the C-ABI opaque handles)"
make leak-check

green "
=========================================
   STRICT GATE PASSED
=========================================
"
