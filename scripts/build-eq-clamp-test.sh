#!/usr/bin/env bash
# Build + run the standalone EQSafetyClamp test harness (Sprint 4, Milestone 5).
#
# This standalone harness
# compiles the REAL production source together with the assertions via swiftc —
# the same "compile the real code, not a copy" approach as build-null-test.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/Sources/AdaptiveSound/EQSafetyClamp.swift"
TEST="$ROOT/Tests/EQSafetyClampTest.swift"
OUT="$ROOT/Tests/EQSafetyClampTest"

echo "Compiling EQSafetyClamp test harness..."
swiftc -O "$SRC" "$TEST" -o "$OUT"

echo "Running..."
"$OUT"
