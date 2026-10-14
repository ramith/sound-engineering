# clones ['Tests'] cross=False

```
{
 "files": 148,
 "tokens": 222802,
 "raw_clones": 272,
 "raw_by_kind": {
  "T1": 144,
  "T2": 125,
  "T3": 3,
  "REP": 0
 },
 "clones": 272,
 "by_kind": {
  "T1": 144,
  "T2": 125,
  "T3": 3,
  "REP": 0
 },
 "capped_buckets": 0,
 "settings": {
  "mode": "mild",
  "min_sim": 0.0,
  "k": 40,
  "min_lines": 6,
  "gap": 12,
  "roots": [
   "Tests"
  ],
  "cross": false
 }
}
```

| module | lines | dup lines | % | pairs |
|---|---|---|---|---|
| Tests/(C++ harness) | 24022 | 2547 | 10.6 | 203 |
| Tests/DesignTokenKitTests | 3077 | 250 | 8.1 | 46 |
| Tests/LibraryBrowseKitTests | 3918 | 175 | 4.5 | 11 |
| Tests/AudioViewModelTests | 2702 | 154 | 5.7 | 10 |
| Tests/TrackLoudnessKitTests | 276 | 21 | 7.6 | 2 |
| Tests/AudioDSPTests | 145 | 0 | 0.0 | 0 |
| Tests/EQEditKitTests | 2165 | 0 | 0.0 | 0 |
| Tests/OutputDeviceKitTests | 299 | 0 | 0.0 | 0 |

| # | kind | tokens | lines | sim | A | B |
|---|---|---|---|---|---|---|
| 1 | T1 | 510 | 82 | 0.983 | Tests/CrossfeedTests.inc:93-166 | Tests/MultichannelTests.inc:33-114 |
| 2 | T1 | 316 | 45 | 1.0 | Tests/FileDecodeTests.inc:1673-1717 | Tests/FileDecodeTests.inc:2194-2238 |
| 3 | T1 | 186 | 16 | 1.0 | Tests/EqEngineBreakItMeasurements.inc:1440-1455 | Tests/EqEngineFixTests.inc:979-994 |
| 4 | T2 | 164 | 35 | 0.978 | Tests/GaplessContractTests.inc:164-198 | Tests/GaplessContractTests.inc:296-330 |
| 5 | T2 | 164 | 35 | 0.978 | Tests/GaplessContractTests.inc:164-198 | Tests/GaplessContractTests.inc:398-432 |
| 6 | T2 | 164 | 35 | 0.978 | Tests/GaplessContractTests.inc:296-330 | Tests/GaplessContractTests.inc:398-432 |
| 7 | T1 | 149 | 22 | 1.0 | Tests/LimiterTruePeakTests.inc:137-158 | Tests/LoudnessOracleTests.inc:50-67 |
| 8 | T3 | 145 | 23 | 0.98 | Tests/DspBypassTests.inc:19-40 | Tests/LimiterTests.inc:22-44 |
| 9 | T1 | 132 | 24 | 1.0 | Tests/FileDecodeTests.inc:49-72 | Tests/FileDecodeTests.inc:299-322 |
| 10 | T2 | 132 | 14 | 0.976 | Tests/PureModeTests.inc:947-960 | Tests/PureModeTests.inc:972-985 |
| 11 | T2 | 122 | 15 | 0.865 | Tests/EqEngineTests.inc:171-185 | Tests/EqEngineTests.inc:972-984 |
| 12 | T1 | 122 | 14 | 1.0 | Tests/MultichannelTests.inc:580-593 | Tests/MultichannelTests.inc:601-614 |
| 13 | T1 | 111 | 11 | 1.0 | Tests/CrossfeedTests.inc:128-137 | Tests/DspBypassTests.inc:204-214 |
| 14 | T1 | 111 | 11 | 1.0 | Tests/DspBypassTests.inc:204-214 | Tests/MultichannelTests.inc:75-84 |
| 15 | T1 | 108 | 14 | 1.0 | Tests/EqFrequencyResponseSweepTests.inc:91-104 | Tests/EqFrequencyResponseSweepTests.inc:377-389 |
| 16 | T2 | 106 | 17 | 0.969 | Tests/FileDecodeTests.inc:773-789 | Tests/FileDecodeTests.inc:873-887 |
| 17 | T1 | 104 | 14 | 1.0 | Tests/DspBypassTests.inc:101-114 | Tests/DspBypassTests.inc:320-333 |
| 18 | T2 | 104 | 23 | 0.97 | Tests/FileDecodeTests.inc:1548-1570 | Tests/FileDecodeTests.inc:2047-2069 |
| 19 | T1 | 103 | 12 | 1.0 | Tests/CrossfeedTests.inc:101-112 | Tests/DspBypassTests.inc:187-198 |
| 20 | T1 | 103 | 13 | 1.0 | Tests/DspBypassTests.inc:187-198 | Tests/MultichannelTests.inc:46-58 |
| 21 | T2 | 103 | 40 | 0.931 | Tests/DspBypassTests.inc:55-77 | Tests/LimiterTests.inc:46-85 |
| 22 | T3 | 102 | 16 | 1.0 | Tests/DspBypassTests.inc:156-168 | Tests/DspBypassTests.inc:331-346 |
| 23 | T3 | 99 | 12 | 0.926 | Tests/DspBypassTests.inc:112-123 | Tests/LimiterTests.inc:45-55 |
| 24 | T2 | 96 | 13 | 0.84 | Tests/IntensityTests.inc:233-244 | Tests/IntensityTests.inc:288-300 |
| 25 | T2 | 93 | 21 | 0.929 | Tests/PureModeTests.inc:562-582 | Tests/PureModeTests.inc:584-604 |
| 26 | T2 | 93 | 14 | 0.964 | Tests/RealizerTests.inc:35-48 | Tests/RealizerTests.inc:124-137 |
| 27 | T2 | 86 | 21 | 0.957 | Tests/GaplessContractTests.inc:78-98 | Tests/GaplessContractTests.inc:316-336 |
| 28 | T2 | 86 | 12 | 0.88 | Tests/IntensityTests.inc:97-108 | Tests/IntensityTests.inc:291-302 |
| 29 | T2 | 85 | 20 | 0.0 | Tests/EqDesignerTests.inc:931-948 | Tests/EqDesignerTests.inc:949-968 |
| 30 | T2 | 84 | 16 | 0.857 | Tests/LoudnessTests.inc:99-114 | Tests/LoudnessTests.inc:119-134 |
| 31 | T2 | 83 | 17 | 0.913 | Tests/FileDecodeTests.inc:1964-1980 | Tests/FileDecodeTests.inc:2014-2030 |
| 32 | T2 | 82 | 11 | 0.8 | Tests/EqEngineFixTests.inc:299-308 | Tests/EqTransitionTests.inc:472-482 |
| 33 | T1 | 81 | 12 | 1.0 | Tests/FileDecodeTests.inc:781-792 | Tests/FileDecodeTests.inc:1054-1064 |
| 34 | T2 | 80 | 7 | 0.938 | Tests/EqDesignerTests.inc:137-143 | Tests/EqDesignerTests.inc:148-153 |
| 35 | T1 | 80 | 16 | 1.0 | Tests/FileDecodeTests.inc:1328-1343 | Tests/FileDecodeTests.inc:1888-1902 |
| 36 | T2 | 80 | 12 | 0.909 | Tests/IntensityTests.inc:166-175 | Tests/IntensityTests.inc:236-247 |
| 37 | T1 | 79 | 14 | 1.0 | Tests/DesignTokenKitTests/EQAuditTests.swift:22-34 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:55-68 |
| 38 | T2 | 79 | 10 | 0.955 | Tests/IntensityTests.inc:97-106 | Tests/IntensityTests.inc:166-174 |
| 39 | T2 | 79 | 10 | 0.909 | Tests/IntensityTests.inc:97-106 | Tests/IntensityTests.inc:236-244 |
| 40 | T2 | 79 | 10 | 0.864 | Tests/IntensityTests.inc:166-174 | Tests/IntensityTests.inc:291-300 |
| 41 | T1 | 77 | 6 | 1.0 | Tests/CrossfeedTests.inc:313-318 | Tests/CrossfeedTests.inc:643-648 |
| 42 | T1 | 77 | 8 | 1.0 | Tests/EqEngineBreakItMeasurements.inc:955-962 | Tests/EqEngineBreakItTests.inc:156-163 |
| 43 | T1 | 76 | 10 | 1.0 | Tests/DspBypassTests.inc:29-38 | Tests/DspBypassTests.inc:144-153 |
| 44 | T1 | 76 | 10 | 1.0 | Tests/DspBypassTests.inc:144-153 | Tests/LimiterTests.inc:32-41 |
| 45 | T2 | 76 | 13 | 0.0 | Tests/EqDesignerTests.inc:137-142 | Tests/EqDesignerTests.inc:933-945 |
| 46 | T2 | 76 | 13 | 0.0 | Tests/EqDesignerTests.inc:137-142 | Tests/EqDesignerTests.inc:951-963 |
| 47 | T2 | 76 | 10 | 0.96 | Tests/FileDecodeTests.inc:780-789 | Tests/FileDecodeTests.inc:969-977 |
| 48 | T2 | 76 | 9 | 0.96 | Tests/FileDecodeTests.inc:879-887 | Tests/FileDecodeTests.inc:969-977 |
| 49 | T2 | 74 | 9 | 0.722 | Tests/EqEngineBreakItTests.inc:231-239 | Tests/EqEngineFixTests.inc:299-307 |
| 50 | T2 | 74 | 9 | 0.889 | Tests/EqEngineBreakItTests.inc:231-239 | Tests/EqTransitionTests.inc:472-480 |
| 51 | T1 | 74 | 7 | 1.0 | Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:34-40 | Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:49-55 |
| 52 | T2 | 73 | 9 | 0.143 | Tests/EqDesignerTests.inc:78-86 | Tests/EqDesignerTests.inc:99-107 |
| 53 | T1 | 73 | 7 | 1.0 | Tests/EqFrequencyResponseSweepTests.inc:318-323 | Tests/IntensityTests.inc:371-377 |
| 54 | T2 | 72 | 16 | 0.95 | Tests/GaplessContractTests.inc:183-198 | Tests/SoakRtAllocTests.inc:417-431 |
| 55 | T2 | 72 | 16 | 0.95 | Tests/GaplessContractTests.inc:315-330 | Tests/SoakRtAllocTests.inc:417-431 |
| 56 | T2 | 72 | 16 | 0.95 | Tests/GaplessContractTests.inc:417-432 | Tests/SoakRtAllocTests.inc:417-431 |
| 57 | T2 | 71 | 18 | 0.895 | Tests/SoakRtAllocTests.inc:323-340 | Tests/SoakRtAllocTests.inc:340-357 |
| 58 | T2 | 70 | 15 | 0.96 | Tests/LibraryBrowseKitTests/ListSelectionMenuTests.swift:10-22 | Tests/LibraryBrowseKitTests/ListSelectionTests.swift:16-30 |
| 59 | T2 | 69 | 9 | 0.344 | Tests/EqDesignerTests.inc:87-95 | Tests/EqDesignerTests.inc:101-109 |
| 60 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:32-38 | Tests/DspBypassTests.inc:106-112 |
| 61 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:32-38 | Tests/DspBypassTests.inc:325-331 |
| 62 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:106-112 | Tests/DspBypassTests.inc:147-153 |
| 63 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:147-153 | Tests/DspBypassTests.inc:325-331 |
| 64 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:106-112 | Tests/LimiterTests.inc:35-41 |
| 65 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:325-331 | Tests/LimiterTests.inc:35-41 |
| 66 | T2 | 67 | 16 | 0.81 | Tests/PureGaplessTests.inc:172-187 | Tests/PureGaplessTests.inc:409-424 |
| 67 | T2 | 66 | 19 | 0.826 | Tests/DeviceListPolicyTests.inc:68-85 | Tests/DeviceListPolicyTests.inc:100-118 |
| 68 | T2 | 66 | 8 | 0.258 | Tests/EqDesignerTests.inc:69-76 | Tests/EqDesignerTests.inc:90-97 |
| 69 | T2 | 65 | 6 | 0.097 | Tests/EqDesignerTests.inc:69-74 | Tests/EqDesignerTests.inc:104-109 |
| 70 | T2 | 65 | 9 | 0.955 | Tests/LibraryBrowseKitTests/DetailPageBreakItTests.swift:21-29 | Tests/LibraryBrowseKitTests/LibraryBreakItGTests.swift:18-26 |
| 71 | T2 | 65 | 12 | 0.967 | Tests/LimiterTests.inc:305-316 | Tests/MultichannelTests.inc:396-407 |
| 72 | T2 | 64 | 18 | 0.0 | Tests/EqDesignerTests.inc:69-74 | Tests/EqDesignerTests.inc:117-134 |
| 73 | T2 | 64 | 18 | 0.0 | Tests/EqDesignerTests.inc:90-95 | Tests/EqDesignerTests.inc:117-134 |
| 74 | T2 | 64 | 18 | 0.0 | Tests/EqDesignerTests.inc:104-109 | Tests/EqDesignerTests.inc:117-134 |
| 75 | T1 | 64 | 8 | 1.0 | Tests/FileDecodeTests.inc:776-782 | Tests/FileDecodeTests.inc:1270-1277 |
| 76 | T1 | 64 | 8 | 1.0 | Tests/FileDecodeTests.inc:876-881 | Tests/FileDecodeTests.inc:1270-1277 |
| 77 | T2 | 63 | 13 | 0.958 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:96-108 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:111-121 |
| 78 | T1 | 63 | 16 | 1.0 | Tests/DspBypassTests.inc:38-53 | Tests/DspBypassTests.inc:84-97 |
| 79 | T2 | 63 | 15 | 0.944 | Tests/GaplessContractTests.inc:78-92 | Tests/GaplessContractTests.inc:184-198 |
| 80 | T2 | 63 | 15 | 0.944 | Tests/GaplessContractTests.inc:78-92 | Tests/GaplessContractTests.inc:418-432 |
| 81 | T2 | 63 | 15 | 0.944 | Tests/GaplessContractTests.inc:78-92 | Tests/SoakRtAllocTests.inc:418-431 |
| 82 | T2 | 62 | 20 | 0.85 | Tests/GaplessContractTests.inc:221-240 | Tests/GaplessContractTests.inc:277-296 |
| 83 | T2 | 62 | 7 | 0.727 | Tests/LibraryBrowseKitTests/ListSelectionTypeSelectTests.swift:51-57 | Tests/LibraryBrowseKitTests/ListSelectionTypeSelectTests.swift:59-65 |
| 84 | T1 | 62 | 16 | 1.0 | Tests/RoundTripTests.inc:125-140 | Tests/RoundTripTests.inc:167-182 |
| 85 | T2 | 61 | 8 | 0.955 | Tests/EqEngineBreakItMeasurements.inc:1181-1188 | Tests/EqEngineFixTests.inc:577-584 |
| 86 | T1 | 61 | 10 | 1.0 | Tests/GaplessContractTests.inc:201-210 | Tests/PureGaplessTests.inc:396-403 |
| 87 | T1 | 61 | 17 | 1.0 | Tests/LimiterTests.inc:99-115 | Tests/LimiterTests.inc:239-250 |
| 88 | T1 | 60 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:331-337 | Tests/DesignTokenKitTests/MeterAuditTests.swift:17-23 |
| 89 | T1 | 60 | 14 | 1.0 | Tests/DesignTokenKitTests/EQAuditTests.swift:14-27 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:22-34 |
| 90 | T1 | 60 | 7 | 1.0 | Tests/PureModeTests.inc:939-945 | Tests/PureModeTests.inc:964-970 |
| 91 | T1 | 59 | 9 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:153-161 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:201-209 |
| 92 | T2 | 59 | 7 | 0.909 | Tests/DesignTokenKitTests/MonitorLayoutTests.swift:48-54 | Tests/DesignTokenKitTests/MonitorLayoutTests.swift:63-69 |
| 93 | T2 | 59 | 8 | 0.762 | Tests/LibraryBrowseKitTests/ScrollPlacementTests.swift:27-34 | Tests/LibraryBrowseKitTests/ScrollPlacementTests.swift:35-42 |
| 94 | T2 | 58 | 6 | 0.933 | Tests/EqEngineTests.inc:516-521 | Tests/EqEngineTests.inc:1049-1054 |
| 95 | T2 | 58 | 17 | 0.963 | Tests/LimiterTests.inc:99-115 | Tests/LimiterTests.inc:181-197 |
| 96 | T1 | 58 | 8 | 1.0 | Tests/MultichannelTests.inc:889-896 | Tests/MultichannelTests.inc:1587-1594 |
| 97 | T2 | 58 | 11 | 0.684 | Tests/MultichannelTests.inc:1457-1467 | Tests/MultichannelTests.inc:1467-1477 |
| 98 | T2 | 57 | 10 | 0.833 | Tests/LibraryBrowseKitTests/ListKeyboardCursorTests.swift:50-59 | Tests/LibraryBrowseKitTests/ListKeyboardCursorTests.swift:59-66 |
| 99 | T1 | 56 | 9 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-51 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-137 |
| 100 | T1 | 56 | 9 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-137 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-52 |
| 101 | T1 | 56 | 10 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-137 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-23 |
| 102 | T1 | 56 | 9 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-51 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-52 |
| 103 | T1 | 56 | 10 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-51 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-23 |
| 104 | T1 | 56 | 10 | 1.0 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-52 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-23 |
| 105 | T2 | 56 | 8 | 0.667 | Tests/FileDecodeTests.inc:367-374 | Tests/FileDecodeTests.inc:379-386 |
| 106 | T1 | 56 | 17 | 1.0 | Tests/LimiterTests.inc:181-197 | Tests/LimiterTests.inc:239-250 |
| 107 | T2 | 55 | 7 | 0.0 | Tests/EqDesignerTests.inc:71-77 | Tests/EqDesignerTests.inc:99-105 |
| 108 | T1 | 55 | 8 | 1.0 | Tests/EqEngineFixTests.inc:579-585 | Tests/EqEngineTests.inc:460-467 |
| 109 | T2 | 55 | 7 | 0.667 | Tests/FileDecodeTests.inc:376-382 | Tests/FileDecodeTests.inc:394-400 |
| 110 | T2 | 55 | 7 | 0.667 | Tests/FileDecodeTests.inc:377-383 | Tests/FileDecodeTests.inc:394-400 |
| 111 | T2 | 55 | 7 | 0.667 | Tests/FileDecodeTests.inc:378-384 | Tests/FileDecodeTests.inc:394-400 |
| 112 | T2 | 55 | 7 | 0.75 | Tests/FileDecodeTests.inc:379-385 | Tests/FileDecodeTests.inc:394-400 |
| 113 | T2 | 55 | 11 | 0.867 | Tests/GaplessTests.inc:328-337 | Tests/GaplessTests.inc:371-381 |
| 114 | T2 | 55 | 6 | 0.682 | Tests/LibraryBrowseKitTests/CoalescingWriterTests.swift:41-46 | Tests/LibraryBrowseKitTests/CoalescingWriterTests.swift:149-154 |
| 115 | T1 | 55 | 10 | 1.0 | Tests/MultichannelTests.inc:400-408 | Tests/MultichannelTests.inc:1048-1057 |
| 116 | T2 | 55 | 10 | 0.867 | Tests/PureGaplessTests.inc:219-228 | Tests/PureGaplessTests.inc:376-385 |
| 117 | T1 | 54 | 9 | 1.0 | Tests/DspBypassTests.inc:153-161 | Tests/DspBypassTests.inc:280-288 |
| 118 | T2 | 54 | 7 | 0.667 | Tests/FileDecodeTests.inc:367-373 | Tests/FileDecodeTests.inc:376-382 |
| 119 | T2 | 54 | 7 | 0.667 | Tests/FileDecodeTests.inc:367-373 | Tests/FileDecodeTests.inc:377-383 |
| 120 | T2 | 54 | 7 | 0.667 | Tests/FileDecodeTests.inc:367-373 | Tests/FileDecodeTests.inc:378-384 |
| 121 | T2 | 54 | 7 | 0.667 | Tests/FileDecodeTests.inc:367-373 | Tests/FileDecodeTests.inc:394-400 |
| 122 | T1 | 54 | 7 | 1.0 | Tests/LimiterTruePeakTests.inc:137-142 | Tests/MultichannelTests.inc:581-587 |
| 123 | T1 | 54 | 7 | 1.0 | Tests/LimiterTruePeakTests.inc:137-142 | Tests/MultichannelTests.inc:602-608 |
| 124 | T1 | 54 | 7 | 1.0 | Tests/LoudnessOracleTests.inc:50-55 | Tests/MultichannelTests.inc:581-587 |
| 125 | T1 | 54 | 7 | 1.0 | Tests/LoudnessOracleTests.inc:50-55 | Tests/MultichannelTests.inc:602-608 |
| 126 | T2 | 53 | 10 | 0.579 | Tests/AudioViewModelTests/QueueOpsTests.swift:71-80 | Tests/AudioViewModelTests/QueueOpsTests.swift:118-127 |
| 127 | T1 | 53 | 8 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:238-245 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:289-296 |
| 128 | T2 | 53 | 7 | 0.947 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:35-41 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:98-104 |
| 129 | T1 | 53 | 12 | 1.0 | Tests/LimiterTests.inc:308-318 | Tests/MultichannelTests.inc:1232-1243 |
| 130 | T2 | 53 | 8 | 0.938 | Tests/SpatialTests.inc:127-134 | Tests/SpatialTests.inc:174-181 |
| 131 | T2 | 52 | 14 | 0.913 | Tests/AudioViewModelTests/AutoAdvanceGaplessSeamTests.swift:10-23 | Tests/AudioViewModelTests/AutoAdvanceGaplessSeamTests.swift:31-42 |
| 132 | T1 | 52 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:31-36 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:416-421 |
| 133 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:44-50 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 |
| 134 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:44-50 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 135 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:130-136 |
| 136 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:45-51 |
| 137 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:16-22 |
| 138 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 139 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:130-136 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 140 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:45-51 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 141 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:16-22 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 142 | T1 | 52 | 9 | 1.0 | Tests/LimiterTests.inc:308-316 | Tests/MultichannelTests.inc:1048-1055 |
| 143 | T1 | 52 | 9 | 1.0 | Tests/MultichannelTests.inc:400-407 | Tests/MultichannelTests.inc:1232-1240 |
| 144 | T1 | 52 | 9 | 1.0 | Tests/MultichannelTests.inc:1048-1055 | Tests/MultichannelTests.inc:1232-1240 |
| 145 | T1 | 52 | 10 | 1.0 | Tests/SoakRtAllocTests.inc:124-131 | Tests/SoakRtAllocTests.inc:131-140 |
| 146 | T2 | 52 | 8 | 0.941 | Tests/TrackLoudnessTests.inc:2161-2168 | Tests/TrackLoudnessTests.inc:2168-2175 |
| 147 | T2 | 51 | 8 | 0.722 | Tests/DeviceListPolicyTests.inc:62-69 | Tests/DeviceListPolicyTests.inc:85-92 |
| 148 | T2 | 51 | 7 | 0.125 | Tests/EqDesignerTests.inc:71-77 | Tests/EqDesignerTests.inc:78-84 |
| 149 | T1 | 51 | 10 | 1.0 | Tests/FileDecodeTests.inc:781-790 | Tests/FileDecodeTests.inc:1134-1142 |
| 150 | T1 | 51 | 9 | 1.0 | Tests/FileDecodeTests.inc:1054-1062 | Tests/FileDecodeTests.inc:1134-1142 |
| 151 | T2 | 51 | 9 | 0.769 | Tests/FileDecodeTests.inc:1652-1660 | Tests/FileDecodeTests.inc:1947-1955 |
| 152 | T1 | 51 | 6 | 1.0 | Tests/LimiterTruePeakTests.inc:137-142 | Tests/LoudnessOracleTests.inc:67-72 |
| 153 | T1 | 51 | 6 | 1.0 | Tests/LoudnessOracleTests.inc:50-55 | Tests/LoudnessOracleTests.inc:67-72 |
| 154 | T2 | 51 | 6 | 0.882 | Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:33-38 | Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:106-111 |
| 155 | T2 | 50 | 10 | 0.909 | Tests/AudioViewModelTests/AutoAdvanceLinearRepeatShuffleTests.swift:55-64 | Tests/AudioViewModelTests/AutoAdvanceLinearRepeatShuffleTests.swift:78-87 |
| 156 | T2 | 50 | 21 | 0.875 | Tests/CrossfeedTests.inc:285-305 | Tests/CrossfeedTests.inc:382-399 |
| 157 | T1 | 50 | 7 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-49 |
| 158 | T1 | 50 | 7 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-135 |
| 159 | T1 | 50 | 7 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-50 |
| 160 | T1 | 50 | 8 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-21 |
| 161 | T1 | 50 | 6 | 1.0 | Tests/FileDecodeTests.inc:471-476 | Tests/FileDecodeTests.inc:533-538 |
| 162 | T1 | 50 | 11 | 1.0 | Tests/LimiterTests.inc:99-109 | Tests/LimiterTests.inc:305-314 |
| 163 | T2 | 50 | 11 | 0.957 | Tests/LimiterTests.inc:181-191 | Tests/LimiterTests.inc:305-314 |
| 164 | T2 | 50 | 11 | 0.957 | Tests/LimiterTests.inc:99-109 | Tests/MultichannelTests.inc:396-405 |
| 165 | T2 | 50 | 11 | 0.957 | Tests/LimiterTests.inc:181-191 | Tests/MultichannelTests.inc:396-405 |
| 166 | T1 | 50 | 6 | 1.0 | Tests/LimiterTruePeakTests.inc:142-147 | Tests/LoudnessTests.inc:25-30 |
| 167 | T1 | 50 | 6 | 1.0 | Tests/LoudnessOracleTests.inc:55-60 | Tests/LoudnessTests.inc:25-30 |
| 168 | T2 | 50 | 7 | 0.867 | Tests/PureModeTests.inc:486-492 | Tests/PureModeTests.inc:519-525 |
| 169 | T2 | 49 | 14 | 0.632 | Tests/AudioViewModelTests/AutoAdvanceGaplessSeamTests.swift:99-112 | Tests/AudioViewModelTests/AutoAdvanceLinearRepeatShuffleTests.swift:90-99 |
| 170 | T1 | 49 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:61-66 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-61 |
| 171 | T1 | 49 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:61-66 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-34 |
| 172 | T2 | 48 | 7 | 0.938 | Tests/EqEngineBreakItMeasurements.inc:1183-1188 | Tests/EqEngineTests.inc:460-466 |
| 173 | T2 | 48 | 9 | 0.923 | Tests/FileDecodeTests.inc:1126-1133 | Tests/GaplessTests.inc:89-97 |
| 174 | T2 | 48 | 10 | 0.812 | Tests/GaplessContractTests.inc:467-476 | Tests/GaplessContractTests.inc:485-494 |
| 175 | T1 | 48 | 10 | 1.0 | Tests/LimiterTests.inc:239-247 | Tests/LimiterTests.inc:305-314 |
| 176 | T1 | 48 | 10 | 1.0 | Tests/LimiterTests.inc:239-247 | Tests/MultichannelTests.inc:396-405 |
| 177 | T1 | 48 | 6 | 1.0 | Tests/LoudnessTests.inc:24-29 | Tests/lufs-tool.cpp:81-86 |
| 178 | T2 | 47 | 8 | 0.941 | Tests/DesignTokenKitTests/SettingsLayoutTests.swift:38-44 | Tests/DesignTokenKitTests/SlotFitTests.swift:19-26 |
| 179 | T2 | 46 | 6 | 0.882 | Tests/AudioViewModelTests/QueueAdvanceTests.swift:79-84 | Tests/AudioViewModelTests/QueueAdvanceTests.swift:88-93 |
| 180 | T1 | 46 | 6 | 1.0 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:35-40 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:84-89 |
| 181 | T2 | 46 | 6 | 0.938 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:84-89 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:98-103 |
| 182 | T2 | 46 | 10 | 0.909 | Tests/EqEngineBreakItTests.inc:41-50 | Tests/EqEngineFixTests.inc:135-144 |
| 183 | T1 | 46 | 7 | 1.0 | Tests/EqEngineTests.inc:928-934 | Tests/EqTransitionTests.inc:371-377 |
| 184 | T2 | 46 | 6 | 0.357 | Tests/LibraryBrowseKitTests/ListOrderTests.swift:16-21 | Tests/LibraryBrowseKitTests/ListOrderTests.swift:26-31 |
| 185 | T1 | 45 | 7 | 1.0 | Tests/DspBypassTests.inc:155-161 | Tests/DspBypassTests.inc:248-254 |
| 186 | T1 | 45 | 7 | 1.0 | Tests/DspBypassTests.inc:248-254 | Tests/DspBypassTests.inc:282-288 |
| 187 | T2 | 45 | 9 | 0.938 | Tests/FileDecodeTests.inc:1773-1781 | Tests/FileDecodeTests.inc:1805-1813 |
| 188 | T2 | 45 | 10 | 0.929 | Tests/FileDecodeTests.inc:970-979 | Tests/RoundTripTests.inc:85-94 |
| 189 | T2 | 45 | 9 | 0.615 | Tests/LibraryBrowseKitTests/GridLayoutMathTests.swift:14-22 | Tests/LibraryBrowseKitTests/GridLayoutMathTests.swift:22-30 |
| 190 | T2 | 45 | 12 | 0.615 | Tests/MultichannelTests.inc:1310-1321 | Tests/MultichannelTests.inc:1322-1333 |
| 191 | T2 | 44 | 6 | 0.0 | Tests/EqDesignerTests.inc:919-924 | Tests/EqDesignerTests.inc:1010-1015 |
| 192 | T2 | 44 | 6 | 0.533 | Tests/LibraryBrowseKitTests/GridKeyboardCursorTests.swift:129-134 | Tests/LibraryBrowseKitTests/GridKeyboardCursorTests.swift:136-141 |
| 193 | T2 | 43 | 8 | 0.625 | Tests/AudioViewModelTests/QueueAdvanceTests.swift:38-45 | Tests/AudioViewModelTests/QueueAdvanceTests.swift:60-66 |
| 194 | T2 | 43 | 27 | 0.917 | Tests/CrossfeedTests.inc:674-695 | Tests/LoudnessOracleTests.inc:393-419 |
| 195 | T2 | 43 | 9 | 0.933 | Tests/DspBypassTests.inc:19-27 | Tests/DspBypassTests.inc:134-142 |
| 196 | T2 | 43 | 7 | 0.15 | Tests/EqDesignerTests.inc:80-86 | Tests/EqDesignerTests.inc:87-93 |
| 197 | T1 | 43 | 11 | 1.0 | Tests/EqEngineTests.inc:97-106 | Tests/EqTransitionTests.inc:61-71 |
| 198 | T2 | 43 | 7 | 0.938 | Tests/EqEngineTests.inc:389-395 | Tests/EqEngineTests.inc:455-461 |
| 199 | T1 | 43 | 8 | 1.0 | Tests/LoudnessOracleTests.inc:148-155 | Tests/LoudnessOracleTests.inc:169-176 |
| 200 | T2 | 42 | 12 | 0.625 | Tests/AudioViewModelTests/AutoAdvanceDeviceLossTests.swift:106-117 | Tests/AudioViewModelTests/AutoAdvanceLinearRepeatShuffleTests.swift:91-100 |
| 201 | T2 | 42 | 7 | 0.833 | Tests/AudioViewModelTests/AutoAdvanceLinearRepeatShuffleTests.swift:105-111 | Tests/AudioViewModelTests/AutoAdvanceReconfigureGapTests.swift:10-15 |
| 202 | T1 | 42 | 6 | 1.0 | Tests/AudioViewModelTests/QueueOpsTests.swift:35-40 | Tests/AudioViewModelTests/QueueOpsTests.swift:113-118 |
| 203 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:45-51 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 |
| 204 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:45-51 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 |
| 205 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:131-137 |
| 206 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:131-137 |
| 207 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:46-52 |
| 208 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:46-52 |
| 209 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:17-23 |
| 210 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:17-23 |
| 211 | T2 | 42 | 8 | 0.933 | Tests/EqEngineBreakItTests.inc:269-276 | Tests/EqEngineFixTests.inc:347-354 |
| 212 | T1 | 42 | 10 | 1.0 | Tests/GaplessContractTests.inc:275-284 | Tests/PureGaplessTests.inc:404-413 |
| 213 | T1 | 42 | 9 | 1.0 | Tests/GaplessTests.inc:74-82 | Tests/RoundTripTests.inc:68-76 |
| 214 | T1 | 42 | 6 | 1.0 | Tests/RoundTripTests.inc:99-104 | Tests/RoundTripTests.inc:140-145 |
| 215 | T2 | 41 | 12 | 0.75 | Tests/AudioViewModelTests/AutoAdvanceDeviceLossTests.swift:106-116 | Tests/AudioViewModelTests/AutoAdvanceGaplessSeamTests.swift:101-112 |
| 216 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:55-60 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:325-330 |
| 217 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-244 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:57-62 |
| 218 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-295 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:57-62 |
| 219 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-244 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:30-35 |
| 220 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-295 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:30-35 |
| 221 | T2 | 41 | 6 | 0.909 | Tests/DspBypassTests.inc:59-64 | Tests/DspBypassTests.inc:118-123 |
| 222 | T2 | 41 | 9 | 0.929 | Tests/DspBypassTests.inc:134-142 | Tests/LimiterTests.inc:22-30 |
| 223 | T2 | 41 | 7 | 0.933 | Tests/EqEngineBreakItTests.inc:72-78 | Tests/EqEngineTests.inc:318-324 |
| 224 | T1 | 41 | 6 | 1.0 | Tests/EqEngineFixTests.inc:1093-1098 | Tests/TrackLoudnessTests.inc:679-684 |
| 225 | T2 | 41 | 11 | 0.917 | Tests/FileDecodeTests.inc:1660-1670 | Tests/FileDecodeTests.inc:1866-1875 |
| 226 | T2 | 41 | 11 | 0.917 | Tests/FileDecodeTests.inc:1660-1670 | Tests/FileDecodeTests.inc:2082-2091 |
| 227 | T2 | 41 | 11 | 0.917 | Tests/FileDecodeTests.inc:1660-1670 | Tests/FileDecodeTests.inc:2173-2182 |
| 228 | T2 | 41 | 8 | 0.909 | Tests/FileDecodeTests.inc:1765-1772 | Tests/FileDecodeTests.inc:1783-1790 |
| 229 | T1 | 41 | 11 | 1.0 | Tests/FileDecodeTests.inc:1819-1829 | Tests/FileDecodeTests.inc:1907-1917 |
| 230 | T2 | 41 | 10 | 0.917 | Tests/FileDecodeTests.inc:1866-1875 | Tests/FileDecodeTests.inc:2082-2091 |
| 231 | T2 | 41 | 10 | 0.917 | Tests/FileDecodeTests.inc:1866-1875 | Tests/FileDecodeTests.inc:2173-2182 |
| 232 | T2 | 41 | 10 | 0.917 | Tests/FileDecodeTests.inc:2082-2091 | Tests/FileDecodeTests.inc:2173-2182 |
| 233 | T1 | 41 | 6 | 1.0 | Tests/LimiterTests.inc:310-315 | Tests/TestSupport.h:384-389 |
| 234 | T1 | 41 | 6 | 1.0 | Tests/MultichannelTests.inc:401-406 | Tests/TestSupport.h:384-389 |
| 235 | T1 | 41 | 6 | 1.0 | Tests/MultichannelTests.inc:1049-1054 | Tests/TestSupport.h:384-389 |
| 236 | T1 | 41 | 6 | 1.0 | Tests/MultichannelTests.inc:1234-1239 | Tests/TestSupport.h:384-389 |
| 237 | T1 | 41 | 10 | 1.0 | Tests/LoudnessNeutralTests.inc:128-137 | Tests/TrackLoudnessTests.inc:119-128 |
| 238 | T1 | 41 | 21 | 1.0 | Tests/SoakRtAllocTests.inc:327-340 | Tests/SoakRtAllocTests.inc:361-381 |
| 239 | T1 | 41 | 21 | 1.0 | Tests/SoakRtAllocTests.inc:344-357 | Tests/SoakRtAllocTests.inc:361-381 |
| 240 | T2 | 40 | 6 | 0.778 | Tests/EqDesignerTests.inc:1483-1488 | Tests/EqEngineTests.inc:555-560 |
| 241 | T1 | 40 | 13 | 1.0 | Tests/FileDecodeTests.inc:793-805 | Tests/FileDecodeTests.inc:1065-1077 |
| 242 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:880-887 | Tests/FileDecodeTests.inc:1054-1061 |
| 243 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:880-887 | Tests/FileDecodeTests.inc:1134-1141 |
| 244 | T2 | 40 | 8 | 0.929 | Tests/FileDecodeTests.inc:970-977 | Tests/FileDecodeTests.inc:1054-1061 |
| 245 | T2 | 40 | 8 | 0.929 | Tests/FileDecodeTests.inc:970-977 | Tests/FileDecodeTests.inc:1134-1141 |
| 246 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1708-1717 | Tests/FileDecodeTests.inc:1820-1829 |
| 247 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1708-1717 | Tests/FileDecodeTests.inc:1908-1917 |
| 248 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:1835-1842 |
| 249 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:1923-1930 |
| 250 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:2139-2146 |
| 251 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:2244-2251 |
| 252 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1820-1829 | Tests/FileDecodeTests.inc:2229-2238 |
| 253 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/FileDecodeTests.inc:1923-1930 |
| 254 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/FileDecodeTests.inc:2139-2146 |
| 255 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/FileDecodeTests.inc:2244-2251 |
| 256 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1908-1917 | Tests/FileDecodeTests.inc:2229-2238 |
| 257 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1923-1930 | Tests/FileDecodeTests.inc:2139-2146 |
| 258 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1923-1930 | Tests/FileDecodeTests.inc:2244-2251 |
| 259 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:2139-2146 | Tests/FileDecodeTests.inc:2244-2251 |
| 260 | T1 | 40 | 9 | 1.0 | Tests/FileDecodeTests.inc:781-789 | Tests/RoundTripTests.inc:85-92 |
| 261 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:880-887 | Tests/RoundTripTests.inc:85-92 |
| 262 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1054-1061 | Tests/RoundTripTests.inc:85-92 |
| 263 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1134-1141 | Tests/RoundTripTests.inc:85-92 |
| 264 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/RoundTripTests.inc:197-204 |
| 265 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/RoundTripTests.inc:197-204 |
| 266 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1923-1930 | Tests/RoundTripTests.inc:197-204 |
| 267 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:2139-2146 | Tests/RoundTripTests.inc:197-204 |
| 268 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:2244-2251 | Tests/RoundTripTests.inc:197-204 |
| 269 | T2 | 40 | 9 | 0.857 | Tests/GaplessContractTests.inc:221-229 | Tests/PureGaplessTests.inc:406-413 |
| 270 | T1 | 40 | 9 | 1.0 | Tests/GaplessTests.inc:204-212 | Tests/PureGaplessTests.inc:204-212 |
| 271 | T2 | 40 | 7 | 0.455 | Tests/LibraryBrowseKitTests/DetailTrackLayoutTests.swift:64-70 | Tests/LibraryBrowseKitTests/DetailTrackLayoutTests.swift:120-126 |
| 272 | T2 | 40 | 8 | 0.545 | Tests/LibraryBrowseKitTests/PlaylistDialogLatchTests.swift:75-82 | Tests/LibraryBrowseKitTests/PlaylistDialogLatchTests.swift:94-100 |
