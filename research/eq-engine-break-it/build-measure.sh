#!/bin/bash
# research/eq-engine-break-it/build-measure.sh — builds the EQ-engine break-it MEASUREMENT harness
# (Tests/EqEngineBreakItMeasure.cpp + Tests/EqEngineBreakItMeasurements.inc): the same production
# sources and test helpers as Tests/DSPKernelNullTest, with a different main. Not part of
# `make gate`. Extra arguments go to clang++ (e.g. -O2, or -fsanitize=thread -g -O1).
#
# Usage: research/eq-engine-break-it/build-measure.sh -O2
#        research/eq-engine-break-it/measure [measurement-name …]   (no name = all)
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
# shellcheck source=scripts/lib/cxx-analysis-flags.sh
source "$REPO_ROOT/scripts/lib/cxx-analysis-flags.sh"
OPT=("$@")
EBUR128_DIR="$REPO_ROOT/third_party/libebur128/ebur128"
OBJ="$HERE/.ebur128.o"
xcrun clang -x c -std=c11 -isysroot "$SDK" -O2 -DACCELERATE_NEW_LAPACK -I"$EBUR128_DIR" \
    -c "$EBUR128_DIR/ebur128.c" -o "$OBJ"
# shellcheck disable=SC2046  # intentional word-splitting of the space-separated core flags
xcrun clang++ $(cxx_analysis_core_flags) -fobjc-arc -fblocks ${OPT[@]+"${OPT[@]}"} \
    -DADAPTIVESOUND_TEST_DATA_DIR="\"$REPO_ROOT/test-data\"" -I"$EBUR128_DIR" -I"$REPO_ROOT/Tests" \
    "$REPO_ROOT/Sources/AudioDSP/DSPKernel.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/GraphicEQDesigner.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQDesignBridge.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/CausalLoudnessTap.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessMeterBridge.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessProfile.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessProfiler.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessGain.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/TrackLoudnessBridge.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/ChannelLayoutDecoder.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/Spatial/CrossfeedModule.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModePolicy.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModeBridgePolicy.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/PureModeFormat.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/FileDecodeSource.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/GaplessSource.cpp" \
    "$REPO_ROOT/Sources/AudioDSP/AudioEngine/Realizer.mm" \
    "$REPO_ROOT/Tests/EqEngineBreakItMeasure.cpp" "$OBJ" \
    -framework AudioToolbox -framework CoreFoundation -framework Foundation -framework Accelerate \
    -o "$HERE/measure"
echo "Built: $HERE/measure"
