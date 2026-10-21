#!/usr/bin/env bash
#
# scripts/gate/null-coverage.sh — the null-test source-coverage drift guard, moved from
# scripts/strict-gate.sh (same allowlist, same grep scope).
#
# Fails if a NEW production .mm/.cpp/.cc under Sources/AudioDSP is neither compiled by the null
# test (and therefore run under -O2 -Werror and the sanitizers) NOR listed in the documented
# live-only allowlist below. Keep the allowlist in sync when a live-only glue file is added or removed.
set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root" || exit 1

# ALLOWLIST: needs a live CoreAudio device or AU host, so it is intentionally not in the null test.
# PureModeBridge.cpp is allowlisted (it links CoreAudio) but gets runtime coverage from the
# leak-detection harness (make leak-check). Loudness/LoudnessMeterBridge.cpp is NOT here: the null
# test compiles it.
null_test_allowlist=(
    Sources/AudioDSP/CoreAudioDevice.cpp
    Sources/AudioDSP/PureModeBridge.cpp
    Sources/AudioDSP/AudioEngine/AUAudioUnit.mm
    Sources/AudioDSP/AudioEngine/HALOutputEngine.mm
    Sources/AudioDSP/AudioEngine/InProcessEffectAU.mm
    Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm
)

# Production sources, and the set the null test really compiles: grepped out of the compile block
# of build-null-test.sh (scoped by sed, so a comment mentioning a path cannot mask a gap).
production="$(find Sources/AudioDSP -type f \( -name '*.mm' -o -name '*.cpp' -o -name '*.cc' \) | sort -u)"
compiled="$(sed -n '/xcrun clang++/,/-o "\$OUTPUT"/p' scripts/build-null-test.sh | grep -oE 'Sources/AudioDSP/[^"]+\.(mm|cpp|cc)' | sort -u)"
[[ -n "$production" ]] || { echo "ERROR: found 0 production DSP sources under Sources/AudioDSP: the scope is broken" >&2; exit 1; }
[[ -n "$compiled" ]] || { echo "ERROR: could not read the null test's compile list from scripts/build-null-test.sh" >&2; exit 1; }

allow="$(printf '%s\n' "${null_test_allowlist[@]}" | sort -u)"
uncovered="$(comm -23 <(printf '%s\n' "$production") <(printf '%s\n%s\n' "$compiled" "$allow" | sort -u))"

if [[ -n "$uncovered" ]]; then
    while IFS= read -r src; do
        echo "ERROR: new production DSP source not covered by null-test/-O2/sanitizers: $src" >&2
        echo "       add it to build-null-test.sh or the documented allowlist in scripts/gate/null-coverage.sh." >&2
    done <<< "$uncovered"
    exit 1
fi

covered_count="$(printf '%s\n' "$production" | wc -l | tr -d ' ')"
echo "null-test source coverage complete: every one of $covered_count production DSP sources is compiled or documented live-only."
echo "GATE_COVERED $covered_count production-sources"
