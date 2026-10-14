# clones ['Sources', 'Tests'] cross=True

```
{
 "files": 725,
 "tokens": 534895,
 "raw_clones": 42,
 "raw_by_kind": {
  "T1": 2,
  "T2": 33,
  "T3": 7,
  "REP": 0
 },
 "clones": 42,
 "by_kind": {
  "T1": 2,
  "T2": 33,
  "T3": 7,
  "REP": 0
 },
 "capped_buckets": 23,
 "settings": {
  "mode": "weak",
  "min_sim": 0.0,
  "k": 40,
  "min_lines": 6,
  "gap": 12,
  "roots": [
   "Sources",
   "Tests"
  ],
  "cross": true
 }
}
```

| module | lines | dup lines | % | pairs |
|---|---|---|---|---|
| Tests/(C++ harness) | 24022 | 188 | 0.8 | 35 |
| Sources/AdaptiveSound(root) | 11865 | 65 | 0.5 | 5 |
| Sources/AudioDSP | 3738 | 60 | 1.6 | 22 |
| Tests/AudioViewModelTests | 2702 | 46 | 1.7 | 5 |
| Sources/AudioDSP/Loudness | 3456 | 44 | 1.3 | 3 |
| Sources/AudioDSP/include | 3093 | 27 | 0.9 | 3 |
| Sources/AudioDSP/EQ | 1422 | 19 | 1.3 | 4 |
| Sources/AdaptiveSound/Debug | 2446 | 15 | 0.6 | 1 |
| Tests/AudioDSPTests | 145 | 15 | 10.3 | 1 |
| Sources/AudioDSP/Spatial | 569 | 12 | 2.1 | 1 |
| Sources/AudioDSP/AudioEngine | 2772 | 7 | 0.3 | 2 |
| Sources/VerifyLibraryStore | 10791 | 7 | 0.1 | 1 |
| Tests/LibraryBrowseKitTests | 3918 | 7 | 0.2 | 1 |
| Sources/AdaptiveSound/Monitoring | 13 | 0 | 0.0 | 0 |
| Sources/AdaptiveSound/Spectrum | 446 | 0 | 0.0 | 0 |
| Sources/AdaptiveSound/UI | 13325 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Clarity | 41 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Limiting | 573 | 0 | 0.0 | 0 |
| Sources/AudioDSPTestBridge | 137 | 0 | 0.0 | 0 |
| Sources/AudioFormatKit | 105 | 0 | 0.0 | 0 |
| Sources/DesignTokenKit | 1694 | 0 | 0.0 | 0 |
| Sources/EQEditKit | 2113 | 0 | 0.0 | 0 |
| Sources/LibraryBrowseKit | 1997 | 0 | 0.0 | 0 |
| Sources/LibraryScan | 1528 | 0 | 0.0 | 0 |
| Sources/LibraryStore | 5479 | 0 | 0.0 | 0 |
| Sources/OutputDeviceKit | 153 | 0 | 0.0 | 0 |
| Sources/PlaybackQueueKit | 515 | 0 | 0.0 | 0 |
| Sources/SRCQualityMeasure | 523 | 0 | 0.0 | 0 |
| Sources/StoreSQLiteShim | 26 | 0 | 0.0 | 0 |
| Sources/TrackLoudnessKit | 431 | 0 | 0.0 | 0 |
| Sources/VerifyAUGraph | 1374 | 0 | 0.0 | 0 |
| Tests/DesignTokenKitTests | 3077 | 0 | 0.0 | 0 |
| Tests/EQEditKitTests | 2165 | 0 | 0.0 | 0 |
| Tests/OutputDeviceKitTests | 299 | 0 | 0.0 | 0 |
| Tests/TrackLoudnessKitTests | 276 | 0 | 0.0 | 0 |

| # | kind | tokens | lines | sim | A | B |
|---|---|---|---|---|---|---|
| 1 | T2 | 282 | 23 | 0.875 | Sources/AudioDSP/Loudness/LufsMeter.h:179-200 | Tests/MultichannelTests.inc:665-687 |
| 2 | T2 | 84 | 14 | 0.593 | Sources/AudioDSP/Loudness/LufsMeter.h:373-386 | Tests/MultichannelTests.inc:773-785 |
| 3 | T3 | 76 | 16 | 0.045 | Sources/AudioDSP/PureModeFormat.cpp:38-53 | Tests/FileDecodeTests.inc:233-247 |
| 4 | T3 | 71 | 16 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:38-53 | Tests/TestSupport.h:85-98 |
| 5 | T2 | 70 | 15 | 0.962 | Sources/AdaptiveSound/Debug/SplitMix64.swift:7-21 | Tests/AudioDSPTests/EQTests+Helpers.swift:52-66 |
| 6 | T3 | 68 | 16 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:37-51 | Tests/TestSupport.h:127-142 |
| 7 | T2 | 65 | 7 | 0.87 | Sources/AudioDSP/FileDecodeSource.cpp:226-232 | Tests/FileDecodeTests.inc:323-328 |
| 8 | T2 | 62 | 8 | 0.312 | Sources/AudioDSP/Loudness/LufsMeter.h:352-359 | Tests/MultichannelTests.inc:791-798 |
| 9 | T2 | 60 | 12 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:42-53 | Tests/TestSupport.h:85-96 |
| 10 | T3 | 58 | 15 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:42-53 | Tests/TestSupport.h:128-142 |
| 11 | T2 | 58 | 13 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:42-53 | Tests/FileDecodeTests.inc:233-245 |
| 12 | T2 | 56 | 7 | 0.905 | Sources/VerifyLibraryStore/ChecksWalkOverlap.swift:37-43 | Tests/LibraryBrowseKitTests/LibraryBreakItGTests.swift:63-69 |
| 13 | T3 | 54 | 19 | 0.0 | Sources/AudioDSP/EQ/GraphicEQBands.h:39-57 | Tests/TrackLoudnessTests.inc:264-273 |
| 14 | T1 | 50 | 9 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:171-179 | Tests/FileDecodeTests.inc:52-60 |
| 15 | T1 | 50 | 9 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:171-179 | Tests/FileDecodeTests.inc:302-310 |
| 16 | T2 | 49 | 7 | 0.95 | Sources/AdaptiveSound/AudioViewModel+Queue.swift:178-184 | Tests/AudioViewModelTests/MockAdvanceController.swift:312-318 |
| 17 | T3 | 48 | 19 | 0.0 | Sources/AudioDSP/EQ/GraphicEQBands.h:39-57 | Tests/TestSupport.h:118-128 |
| 18 | T2 | 47 | 13 | 0.895 | Sources/AdaptiveSound/AudioViewModel+Queue.swift:89-97 | Tests/AudioViewModelTests/MockAdvanceController.swift:278-290 |
| 19 | T3 | 47 | 19 | 0.0 | Sources/AudioDSP/EQ/GraphicEQBands.h:39-57 | Tests/TrackLoudnessTests.inc:267-275 |
| 20 | T2 | 47 | 8 | 0.478 | Sources/AudioDSP/FileDecodeSource.cpp:299-306 | Tests/FileDecodeTests.inc:42-49 |
| 21 | T2 | 47 | 8 | 0.522 | Sources/AudioDSP/FileDecodeSource.cpp:299-306 | Tests/FileDecodeTests.inc:292-299 |
| 22 | T2 | 47 | 12 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:38-49 | Tests/FileDecodeTests.inc:236-247 |
| 23 | T2 | 46 | 7 | 0.0 | Sources/AudioDSP/include/RtSwappableResource.h:62-68 | Tests/TrackLoudnessTests.inc:838-843 |
| 24 | T2 | 44 | 20 | 0.0 | Sources/AudioDSP/include/AudioConstants.h:15-34 | Tests/TestSupport.h:101-110 |
| 25 | T2 | 43 | 7 | 0.0 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:352-358 | Tests/EqEngineTests.inc:795-800 |
| 26 | T2 | 43 | 7 | 0.0 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:352-358 | Tests/TrackLoudnessTests.inc:838-843 |
| 27 | T2 | 43 | 6 | 0.0 | Sources/AudioDSP/FileDecodeSource.cpp:158-163 | Tests/EqEngineTests.inc:795-800 |
| 28 | T2 | 43 | 6 | 0.0 | Sources/AudioDSP/FileDecodeSource.cpp:507-512 | Tests/EqEngineTests.inc:795-800 |
| 29 | T2 | 43 | 7 | 0.0 | Sources/AudioDSP/FileDecodeSource.cpp:906-912 | Tests/EqEngineTests.inc:795-800 |
| 30 | T2 | 43 | 6 | 0.0 | Sources/AudioDSP/FileDecodeSource.cpp:158-163 | Tests/TrackLoudnessTests.inc:838-843 |
| 31 | T2 | 43 | 6 | 0.0 | Sources/AudioDSP/FileDecodeSource.cpp:507-512 | Tests/TrackLoudnessTests.inc:838-843 |
| 32 | T2 | 43 | 7 | 0.0 | Sources/AudioDSP/FileDecodeSource.cpp:906-912 | Tests/TrackLoudnessTests.inc:838-843 |
| 33 | T2 | 43 | 7 | 0.0 | Sources/AudioDSP/include/RtSwappableResource.h:62-68 | Tests/EqEngineTests.inc:795-800 |
| 34 | T2 | 42 | 10 | 0.81 | Sources/AdaptiveSound/AudioViewModel+Playlist.swift:99-108 | Tests/AudioViewModelTests/MockAdvanceController.swift:222-230 |
| 35 | T2 | 42 | 24 | 0.722 | Sources/AdaptiveSound/SignalPathInfo.swift:44-67 | Tests/AudioViewModelTests/MockAudioEngine.swift:21-29 |
| 36 | T2 | 42 | 19 | 0.0 | Sources/AudioDSP/EQ/GraphicEQBands.h:39-57 | Tests/TrackLoudnessTests.inc:60-68 |
| 37 | T2 | 42 | 9 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:46-53 | Tests/TestSupport.h:85-93 |
| 38 | T2 | 41 | 15 | 0.944 | Sources/AdaptiveSound/AudioViewModel+AutoAdvance.swift:92-106 | Tests/AudioViewModelTests/MockAdvanceController.swift:191-198 |
| 39 | T2 | 41 | 11 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:38-48 | Tests/TestSupport.h:88-98 |
| 40 | T2 | 40 | 13 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:46-53 | Tests/TestSupport.h:128-140 |
| 41 | T2 | 40 | 10 | 0.0 | Sources/AudioDSP/PureModeFormat.cpp:46-53 | Tests/FileDecodeTests.inc:233-242 |
| 42 | T2 | 40 | 12 | 0.231 | Sources/AudioDSP/Spatial/CrossfeedModule.cpp:87-98 | Tests/CrossfeedTests.inc:727-733 |
