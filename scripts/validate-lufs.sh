#!/bin/bash
# scripts/validate-lufs.sh
#
# LUFS oracle cross-check: builds Tests/lufs-tool, which writes a 1 kHz stereo
# sine WAV and measures it with LufsMeter, then measures the SAME WAV with
# `ffmpeg ebur128` and asserts the two integrated-LUFS values agree within the
# EBU R128 tolerance (±0.1 LU). Requires ffmpeg on PATH.
#
# Usage: ./scripts/validate-lufs.sh [peakDbfs=-23]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(xcrun --show-sdk-path)"
TOOL="$REPO_ROOT/Tests/lufs-tool"
WAV="$(mktemp -t lufs_oracle).wav"
PEAK="${1:--23}"
TOL="0.1"

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "SKIP: ffmpeg not found on PATH (brew install ffmpeg)"
    exit 0
fi

echo "Building lufs-tool..."
xcrun clang++ -std=gnu++2b -O2 -isysroot "$SDK" \
    -I"$REPO_ROOT/Sources/AudioDSP" \
    "$REPO_ROOT/Tests/lufs-tool.cpp" -o "$TOOL"

echo "Generating + measuring (LufsMeter)..."
METER_LINE="$("$TOOL" "$WAV" "$PEAK")"
METER="$(echo "$METER_LINE" | awk '{print $2}')"

echo "Measuring with ffmpeg ebur128..."
FFMPEG_I="$(ffmpeg -hide_banner -nostats -i "$WAV" -af ebur128 -f null - 2>&1 \
    | grep -E '^[[:space:]]*I:' | tail -1 | awk '{print $2}')"

DELTA="$(awk -v a="$METER" -v b="$FFMPEG_I" 'BEGIN{d=a-b; if(d<0)d=-d; printf "%.3f", d}')"

echo ""
echo "  LufsMeter : $METER LUFS"
echo "  ffmpeg    : $FFMPEG_I LUFS"
echo "  delta     : $DELTA LU (tolerance $TOL)"

rm -f "$WAV"

PASS="$(awk -v d="$DELTA" -v t="$TOL" 'BEGIN{print (d<=t)?"1":"0"}')"
if [[ "$PASS" == "1" ]]; then
    echo "PASS: LufsMeter agrees with ffmpeg ebur128 within ±$TOL LU"
    exit 0
else
    echo "FAIL: LufsMeter disagrees with ffmpeg ebur128 by $DELTA LU (> $TOL)"
    exit 1
fi
