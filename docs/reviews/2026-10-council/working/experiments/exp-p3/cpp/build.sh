#!/bin/bash
# usage: build.sh <main.cpp> <out> [extra flags...]
set -e
WT=/Users/ramith/code/sound-engineering/.claude/worktrees/panel-p3-breaker
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
main=$1; out=$2; shift 2
xcrun clang++ -std=gnu++2b -isysroot $SDK -fno-exceptions -fno-rtti -D_LIBCPP_DISABLE_AVAILABILITY -DACCELERATE_NEW_LAPACK \
  -I $WT/Sources/AudioDSP -I $WT/Sources/AudioDSP/include -isystem /opt/homebrew/include -I /private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad/council/exp-p3/cpp \
  -O1 -g "$@" $main \
  $WT/Sources/AudioDSP/PureModeFormat.cpp $WT/Sources/AudioDSP/PureModeSource.cpp \
  $WT/Sources/AudioDSP/FileDecodeSource.cpp $WT/Sources/AudioDSP/GaplessSource.cpp \
  -framework AudioToolbox -framework CoreFoundation -framework Foundation -framework Accelerate -o $out
