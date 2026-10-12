#!/bin/bash
# S10.8 G break-it (playback/shell lane): builds the REAL AudioViewModel sources (copied verbatim)
# with the harness stand-ins, then runs the scenarios. Exit 1 = at least one scenario BROKEN.
# Run from the repository root after `swift build` (the kits' modules and objects come from .build/debug).
set -eu
APP=Sources/AdaptiveSound
HARNESS=Tests/BreakItG/vmharness
OUT=.build/breakit-vm
DEBUG=.build/debug
rm -rf $OUT
mkdir -p $OUT/src
for FILE in AudioViewModel.swift AudioViewModel+Transport.swift AudioViewModel+Playback.swift \
    AudioViewModel+Playlist.swift AudioViewModel+Queue.swift AudioViewModel+AutoAdvance.swift \
    AudioViewModel+Lifecycle.swift AudioViewModel+SpectrumTimer.swift AudioViewModel+Devices.swift \
    AudioViewModel+PlayingTrack.swift AudioPlaybackEngine.swift AudioBridgeError.swift SignalPathInfo.swift \
    TabSelection.swift UXLog.swift Models/AudioFile.swift Models/QueueItem.swift Models/AudioDeviceModel.swift \
    Models/CrossfeedStrength.swift Loudness/LoudnessSnapshot.swift Spectrum/SpectrumConstants.swift \
    Monitoring/MonitorTap.swift
do
    cp $APP/$FILE $OUT/src/
done
cp $HARNESS/*.swift $OUT/src/
swiftc -swift-version 6 -I $DEBUG/Modules -module-name BreakItVM -o $OUT/vmharness $OUT/src/*.swift \
    $DEBUG/PlaybackQueueKit.build/*.o $DEBUG/EQEditKit.build/*.o $DEBUG/DesignTokenKit.build/*.o
$OUT/vmharness
