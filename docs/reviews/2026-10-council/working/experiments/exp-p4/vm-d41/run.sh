#!/bin/bash
# Council P4: build the REAL AudioViewModel sources (copied verbatim from the panel-p4 worktree) with
# the scripted engine model, then run the scenarios. Never launches the app; plays nothing.
set -eu
WT=/Users/ramith/code/sound-engineering/.claude/worktrees/panel-p4
HERE=$(cd "$(dirname "$0")" && pwd)
APP=$WT/Sources/AdaptiveSound
DEBUG=$WT/.build/debug
OUT=$HERE/.out
rm -rf "$OUT"
mkdir -p "$OUT/src"
for FILE in AudioViewModel.swift AudioViewModel+Transport.swift AudioViewModel+Playback.swift \
    AudioViewModel+Playlist.swift AudioViewModel+Queue.swift AudioViewModel+AutoAdvance.swift \
    AudioViewModel+Lifecycle.swift AudioViewModel+SpectrumTimer.swift AudioViewModel+Devices.swift \
    AudioViewModel+PlayingTrack.swift AudioViewModel+MasterGain.swift EngineSnapshot.swift \
    AudioPlaybackEngine.swift AudioBridgeError.swift SignalPathInfo.swift \
    TabSelection.swift UXLog.swift Models/AudioFile.swift Models/QueueItem.swift Models/AudioDeviceModel.swift \
    Models/CrossfeedStrength.swift Loudness/LoudnessSnapshot.swift Spectrum/SpectrumConstants.swift \
    Monitoring/MonitorTap.swift
do
    cp "$APP/$FILE" "$OUT/src/"
done
# +PlayTracking is REAL except the store write (LibraryStore/GRDB not linked): the private
# writePlayCount is replaced by a recorder, everything above it is verbatim.
python3 -I - "$APP/AudioViewModel+PlayTracking.swift" "$OUT/src/AudioViewModel+PlayTracking.swift" <<'PY'
import sys
src = open(sys.argv[1]).read()
src = src.replace("import LibraryStore\n", "")
cut = src.index("    /// Fire the detached, fire-and-forget play-count write")
src = src[:cut] + """    private func writePlayCount(file: AudioFile) {
        playCountLog.append(file.absoluteURL.lastPathComponent)
    }
}
"""
open(sys.argv[2], "w").write(src)
PY
cp "$HERE"/*.swift "$OUT/src/"
python3 -I "$HERE/patch_vm.py" "$OUT/src"
swiftc -swift-version 6 -enable-upcoming-feature NonisolatedNonsendingByDefault -I "$DEBUG/Modules" \
    -module-name P4VM -o "$OUT/vmharness" "$OUT"/src/*.swift \
    "$DEBUG"/PlaybackQueueKit.build/*.o "$DEBUG"/EQEditKit.build/*.o "$DEBUG"/DesignTokenKit.build/*.o \
    "$DEBUG"/OutputDeviceKit.build/*.o 2>&1 | grep -v "^$" | head -60
"$OUT/vmharness" "$@"
