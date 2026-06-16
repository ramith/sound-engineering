#!/bin/bash
# Scripts/build-null-test.sh
#
# Builds and optionally runs the DSPKernel null test.
#
# Usage:
#   ./Scripts/build-null-test.sh          # build + run (default)
#   ./Scripts/build-null-test.sh --build  # build only, do not run
#
# Output binary: Tests/DSPKernelNullTest  (gitignored; not checked in)
#
# Requirements: Xcode Command Line Tools (xcrun, clang++ with gnu++2b support,
#               AudioToolbox + Accelerate frameworks available via the SDK).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
OUTPUT="$REPO_ROOT/Tests/DSPKernelNullTest"

echo "Building null test..."
xcrun clang++ \
    -std=gnu++2b \
    -isysroot "$SDK" \
    -fno-exceptions \
    -fno-rtti \
    -Wall -Wextra \
    -D_LIBCPP_DISABLE_AVAILABILITY \
    -I"$REPO_ROOT/Sources/AudioDSP/include" \
    -I"$REPO_ROOT/Sources/AudioDSP" \
    "$REPO_ROOT/Sources/AudioDSP/DSPKernel.mm" \
    "$REPO_ROOT/Sources/AudioDSP/EQ/EQModule.mm" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/LoudnessModule.mm" \
    "$REPO_ROOT/Sources/AudioDSP/Loudness/ChannelLayoutDecoder.mm" \
    "$REPO_ROOT/Tests/DSPKernelNullTest.cpp" \
    -framework AudioToolbox \
    -framework Accelerate \
    -o "$OUTPUT"

echo "Built: $OUTPUT"

if [[ "${1:-}" == "--build" ]]; then
    exit 0
fi

echo ""
echo "Running null test..."
"$OUTPUT"
