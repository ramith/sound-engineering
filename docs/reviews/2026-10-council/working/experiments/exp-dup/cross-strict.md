# clones ['Sources', 'Tests'] cross=True

```
{
 "files": 725,
 "tokens": 534895,
 "raw_clones": 4,
 "raw_by_kind": {
  "T1": 4,
  "T2": 0,
  "T3": 0,
  "REP": 0
 },
 "clones": 4,
 "by_kind": {
  "T1": 4,
  "T2": 0,
  "T3": 0,
  "REP": 0
 },
 "capped_buckets": 0,
 "settings": {
  "mode": "strict",
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
| Tests/(C++ harness) | 24022 | 18 | 0.1 | 2 |
| Sources/AdaptiveSound/Debug | 2446 | 15 | 0.6 | 1 |
| Tests/AudioDSPTests | 145 | 15 | 10.3 | 1 |
| Sources/AudioDSP | 3738 | 9 | 0.2 | 2 |
| Sources/AdaptiveSound(root) | 11865 | 7 | 0.1 | 1 |
| Tests/AudioViewModelTests | 2702 | 7 | 0.3 | 1 |
| Sources/AdaptiveSound/Monitoring | 13 | 0 | 0.0 | 0 |
| Sources/AdaptiveSound/Spectrum | 446 | 0 | 0.0 | 0 |
| Sources/AdaptiveSound/UI | 13325 | 0 | 0.0 | 0 |
| Sources/AudioDSP/AudioEngine | 2772 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Clarity | 41 | 0 | 0.0 | 0 |
| Sources/AudioDSP/EQ | 1422 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Limiting | 573 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Loudness | 3456 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Spatial | 569 | 0 | 0.0 | 0 |
| Sources/AudioDSP/include | 3093 | 0 | 0.0 | 0 |
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
| Sources/VerifyLibraryStore | 10791 | 0 | 0.0 | 0 |
| Tests/DesignTokenKitTests | 3077 | 0 | 0.0 | 0 |
| Tests/EQEditKitTests | 2165 | 0 | 0.0 | 0 |
| Tests/LibraryBrowseKitTests | 3918 | 0 | 0.0 | 0 |
| Tests/OutputDeviceKitTests | 299 | 0 | 0.0 | 0 |
| Tests/TrackLoudnessKitTests | 276 | 0 | 0.0 | 0 |

| # | kind | tokens | lines | sim | A | B |
|---|---|---|---|---|---|---|
| 1 | T1 | 69 | 15 | 1.0 | Sources/AdaptiveSound/Debug/SplitMix64.swift:7-21 | Tests/AudioDSPTests/EQTests+Helpers.swift:52-66 |
| 2 | T1 | 50 | 9 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:171-179 | Tests/FileDecodeTests.inc:52-60 |
| 3 | T1 | 50 | 9 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:171-179 | Tests/FileDecodeTests.inc:302-310 |
| 4 | T1 | 48 | 7 | 1.0 | Sources/AdaptiveSound/AudioViewModel+Queue.swift:178-184 | Tests/AudioViewModelTests/MockAdvanceController.swift:312-318 |
