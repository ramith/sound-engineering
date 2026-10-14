#!/bin/bash
set -euo pipefail
R=/Users/ramith/code/sound-engineering/.claude/worktrees/panel-p2-breaker
SDK="$(xcrun --show-sdk-path)"
E=$R/third_party/libebur128/ebur128
xcrun clang -x c -std=c11 -isysroot "$SDK" -O2 -I"$E" -c "$E/ebur128.c" -o ebur128.o
xcrun clang++ -std=gnu++2b -isysroot "$SDK" -O2 -fno-exceptions -fno-rtti -D_LIBCPP_DISABLE_AVAILABILITY -DACCELERATE_NEW_LAPACK \
  -I $R/Sources/AudioDSP -I $R/Sources/AudioDSP/include -I "$E" -fobjc-arc -fblocks \
  p2harness.cpp \
  $R/Sources/AudioDSP/DSPKernel.cpp $R/Sources/AudioDSP/EQ/EQModule.cpp $R/Sources/AudioDSP/EQ/GraphicEQDesigner.cpp \
  $R/Sources/AudioDSP/Loudness/LoudnessModule.cpp $R/Sources/AudioDSP/Loudness/CausalLoudnessTap.cpp \
  $R/Sources/AudioDSP/Loudness/TrackLoudnessProfile.cpp $R/Sources/AudioDSP/Loudness/TrackLoudnessProfiler.cpp \
  $R/Sources/AudioDSP/Loudness/ChannelLayoutDecoder.cpp $R/Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp \
  $R/Sources/AudioDSP/Spatial/CrossfeedModule.cpp ebur128.o \
  -framework AudioToolbox -framework CoreFoundation -framework Foundation -framework Accelerate -o p2harness
echo built
