#!/usr/bin/env bash
#
# Periphery 2.21.2 (Swift dead code, hostile config: .periphery.yml strict + retain_public false).
#
# Pinned to 2.21.2 on purpose: 3.8.0 reports 514 findings and misreads an executable main.swift.
#
# Xcode 27's SwiftPM uses the "swiftbuild" engine, so a plain `periphery scan` (which looks for
# .build/debug/index/store) fails. The working recipe, verified: build the tests with the index store
# enabled, then scan with --skip-build against the index in the build's own bin path. The index is
# written only while files COMPILE, so this step needs a build that compiled them (it does, here).
# The bin path comes from `swift build --show-bin-path`, never a hardcoded directory.
set -uo pipefail
# shellcheck source=scripts/gate/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

swift build --build-tests --enable-index-store -c debug -j 8 || fail "the build with the index store failed (Periphery cannot run without it)"
bin="$(swift build --show-bin-path -c debug)" || fail "swift build --show-bin-path failed"
index="$bin/index/store"
[[ -d "$index" ]] || fail "no index store at $index: periphery has nothing to analyse (the index is written by compiling)"

periphery scan --skip-build --index-store-path "$index"
rc=$?
((rc == 0)) || fail "periphery found unused declarations (exit $rc); see the list above."
covered 1 whole-program-scan
