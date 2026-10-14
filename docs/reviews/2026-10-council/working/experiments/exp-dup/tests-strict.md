# clones ['Tests'] cross=False

```
{
 "files": 148,
 "tokens": 222802,
 "raw_clones": 187,
 "raw_by_kind": {
  "T1": 185,
  "T2": 0,
  "T3": 2,
  "REP": 0
 },
 "clones": 187,
 "by_kind": {
  "T1": 185,
  "T2": 0,
  "T3": 2,
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
   "Tests"
  ],
  "cross": false
 }
}
```

| module | lines | dup lines | % | pairs |
|---|---|---|---|---|
| Tests/(C++ harness) | 24022 | 1631 | 6.8 | 140 |
| Tests/DesignTokenKitTests | 3077 | 231 | 7.5 | 44 |
| Tests/LibraryBrowseKitTests | 3918 | 26 | 0.7 | 1 |
| Tests/TrackLoudnessKitTests | 276 | 14 | 5.1 | 1 |
| Tests/AudioViewModelTests | 2702 | 12 | 0.4 | 1 |
| Tests/AudioDSPTests | 145 | 0 | 0.0 | 0 |
| Tests/EQEditKitTests | 2165 | 0 | 0.0 | 0 |
| Tests/OutputDeviceKitTests | 299 | 0 | 0.0 | 0 |

| # | kind | tokens | lines | sim | A | B |
|---|---|---|---|---|---|---|
| 1 | T1 | 461 | 68 | 1.0 | Tests/CrossfeedTests.inc:95-154 | Tests/MultichannelTests.inc:35-102 |
| 2 | T1 | 316 | 45 | 1.0 | Tests/FileDecodeTests.inc:1673-1717 | Tests/FileDecodeTests.inc:2194-2238 |
| 3 | T1 | 186 | 16 | 1.0 | Tests/EqEngineBreakItMeasurements.inc:1440-1455 | Tests/EqEngineFixTests.inc:979-994 |
| 4 | T1 | 151 | 33 | 1.0 | Tests/GaplessContractTests.inc:166-198 | Tests/GaplessContractTests.inc:298-330 |
| 5 | T1 | 151 | 33 | 1.0 | Tests/GaplessContractTests.inc:166-198 | Tests/GaplessContractTests.inc:400-432 |
| 6 | T1 | 151 | 33 | 1.0 | Tests/GaplessContractTests.inc:298-330 | Tests/GaplessContractTests.inc:400-432 |
| 7 | T1 | 149 | 22 | 1.0 | Tests/LimiterTruePeakTests.inc:137-158 | Tests/LoudnessOracleTests.inc:50-67 |
| 8 | T1 | 132 | 24 | 1.0 | Tests/FileDecodeTests.inc:49-72 | Tests/FileDecodeTests.inc:299-322 |
| 9 | T1 | 132 | 14 | 1.0 | Tests/PureModeTests.inc:947-960 | Tests/PureModeTests.inc:972-985 |
| 10 | T1 | 122 | 14 | 1.0 | Tests/MultichannelTests.inc:580-593 | Tests/MultichannelTests.inc:601-614 |
| 11 | T1 | 111 | 11 | 1.0 | Tests/CrossfeedTests.inc:128-137 | Tests/DspBypassTests.inc:204-214 |
| 12 | T1 | 111 | 11 | 1.0 | Tests/DspBypassTests.inc:204-214 | Tests/MultichannelTests.inc:75-84 |
| 13 | T1 | 108 | 14 | 1.0 | Tests/EqFrequencyResponseSweepTests.inc:91-104 | Tests/EqFrequencyResponseSweepTests.inc:377-389 |
| 14 | T1 | 104 | 14 | 1.0 | Tests/DspBypassTests.inc:101-114 | Tests/DspBypassTests.inc:320-333 |
| 15 | T1 | 104 | 23 | 1.0 | Tests/FileDecodeTests.inc:1548-1570 | Tests/FileDecodeTests.inc:2047-2069 |
| 16 | T1 | 103 | 12 | 1.0 | Tests/CrossfeedTests.inc:101-112 | Tests/DspBypassTests.inc:187-198 |
| 17 | T1 | 103 | 13 | 1.0 | Tests/DspBypassTests.inc:187-198 | Tests/MultichannelTests.inc:46-58 |
| 18 | T3 | 102 | 16 | 1.0 | Tests/DspBypassTests.inc:156-168 | Tests/DspBypassTests.inc:331-346 |
| 19 | T1 | 101 | 15 | 1.0 | Tests/DspBypassTests.inc:27-40 | Tests/LimiterTests.inc:30-44 |
| 20 | T3 | 98 | 12 | 1.0 | Tests/DspBypassTests.inc:112-123 | Tests/LimiterTests.inc:45-55 |
| 21 | T1 | 98 | 12 | 1.0 | Tests/EqEngineTests.inc:174-185 | Tests/EqEngineTests.inc:975-984 |
| 22 | T1 | 96 | 14 | 1.0 | Tests/FileDecodeTests.inc:776-789 | Tests/FileDecodeTests.inc:876-887 |
| 23 | T1 | 81 | 12 | 1.0 | Tests/FileDecodeTests.inc:781-792 | Tests/FileDecodeTests.inc:1054-1064 |
| 24 | T1 | 80 | 16 | 1.0 | Tests/FileDecodeTests.inc:1328-1343 | Tests/FileDecodeTests.inc:1888-1902 |
| 25 | T1 | 80 | 12 | 1.0 | Tests/RealizerTests.inc:37-48 | Tests/RealizerTests.inc:126-137 |
| 26 | T1 | 79 | 14 | 1.0 | Tests/DesignTokenKitTests/EQAuditTests.swift:22-34 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:55-68 |
| 27 | T1 | 77 | 6 | 1.0 | Tests/CrossfeedTests.inc:313-318 | Tests/CrossfeedTests.inc:643-648 |
| 28 | T1 | 77 | 8 | 1.0 | Tests/EqEngineBreakItMeasurements.inc:955-962 | Tests/EqEngineBreakItTests.inc:156-163 |
| 29 | T1 | 77 | 10 | 1.0 | Tests/IntensityTests.inc:97-106 | Tests/IntensityTests.inc:166-174 |
| 30 | T1 | 76 | 10 | 1.0 | Tests/DspBypassTests.inc:144-153 | Tests/LimiterTests.inc:32-41 |
| 31 | T1 | 76 | 10 | 1.0 | Tests/DspBypassTests.inc:29-38 | Tests/DspBypassTests.inc:144-153 |
| 32 | T1 | 74 | 7 | 1.0 | Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:34-40 | Tests/TrackLoudnessKitTests/TrackLoudnessAnalyzerTests.swift:49-55 |
| 33 | T1 | 73 | 7 | 1.0 | Tests/EqFrequencyResponseSweepTests.inc:318-323 | Tests/IntensityTests.inc:371-377 |
| 34 | T1 | 73 | 18 | 1.0 | Tests/GaplessContractTests.inc:81-98 | Tests/GaplessContractTests.inc:319-336 |
| 35 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:106-112 | Tests/LimiterTests.inc:35-41 |
| 36 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:325-331 | Tests/LimiterTests.inc:35-41 |
| 37 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:32-38 | Tests/DspBypassTests.inc:106-112 |
| 38 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:32-38 | Tests/DspBypassTests.inc:325-331 |
| 39 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:106-112 | Tests/DspBypassTests.inc:147-153 |
| 40 | T1 | 68 | 7 | 1.0 | Tests/DspBypassTests.inc:147-153 | Tests/DspBypassTests.inc:325-331 |
| 41 | T1 | 67 | 14 | 1.0 | Tests/LibraryBrowseKitTests/ListSelectionMenuTests.swift:10-21 | Tests/LibraryBrowseKitTests/ListSelectionTests.swift:16-29 |
| 42 | T1 | 66 | 8 | 1.0 | Tests/FileDecodeTests.inc:780-787 | Tests/FileDecodeTests.inc:969-975 |
| 43 | T1 | 66 | 7 | 1.0 | Tests/FileDecodeTests.inc:879-885 | Tests/FileDecodeTests.inc:969-975 |
| 44 | T1 | 64 | 8 | 1.0 | Tests/FileDecodeTests.inc:776-782 | Tests/FileDecodeTests.inc:1270-1277 |
| 45 | T1 | 64 | 8 | 1.0 | Tests/FileDecodeTests.inc:876-881 | Tests/FileDecodeTests.inc:1270-1277 |
| 46 | T1 | 63 | 16 | 1.0 | Tests/DspBypassTests.inc:38-53 | Tests/DspBypassTests.inc:84-97 |
| 47 | T1 | 63 | 12 | 1.0 | Tests/LimiterTests.inc:305-316 | Tests/MultichannelTests.inc:396-407 |
| 48 | T1 | 62 | 16 | 1.0 | Tests/RoundTripTests.inc:125-140 | Tests/RoundTripTests.inc:167-182 |
| 49 | T1 | 61 | 10 | 1.0 | Tests/GaplessContractTests.inc:201-210 | Tests/PureGaplessTests.inc:396-403 |
| 50 | T1 | 61 | 17 | 1.0 | Tests/LimiterTests.inc:99-115 | Tests/LimiterTests.inc:239-250 |
| 51 | T1 | 60 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:331-337 | Tests/DesignTokenKitTests/MeterAuditTests.swift:17-23 |
| 52 | T1 | 60 | 14 | 1.0 | Tests/DesignTokenKitTests/EQAuditTests.swift:14-27 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:22-34 |
| 53 | T1 | 60 | 12 | 1.0 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:96-107 | Tests/DesignTokenKitTests/MonitorAuditTests.swift:111-120 |
| 54 | T1 | 60 | 7 | 1.0 | Tests/PureModeTests.inc:939-945 | Tests/PureModeTests.inc:964-970 |
| 55 | T1 | 59 | 9 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:153-161 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:201-209 |
| 56 | T1 | 58 | 7 | 1.0 | Tests/EqEngineBreakItTests.inc:233-239 | Tests/EqTransitionTests.inc:474-480 |
| 57 | T1 | 58 | 8 | 1.0 | Tests/MultichannelTests.inc:889-896 | Tests/MultichannelTests.inc:1587-1594 |
| 58 | T1 | 56 | 9 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-51 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-137 |
| 59 | T1 | 56 | 9 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-137 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-52 |
| 60 | T1 | 56 | 10 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-137 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-23 |
| 61 | T1 | 56 | 9 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-51 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-52 |
| 62 | T1 | 56 | 10 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-51 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-23 |
| 63 | T1 | 56 | 10 | 1.0 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-52 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-23 |
| 64 | T1 | 56 | 17 | 1.0 | Tests/LimiterTests.inc:99-115 | Tests/LimiterTests.inc:181-197 |
| 65 | T1 | 56 | 17 | 1.0 | Tests/LimiterTests.inc:181-197 | Tests/LimiterTests.inc:239-250 |
| 66 | T1 | 55 | 8 | 1.0 | Tests/EqEngineFixTests.inc:579-585 | Tests/EqEngineTests.inc:460-467 |
| 67 | T1 | 55 | 10 | 1.0 | Tests/MultichannelTests.inc:400-408 | Tests/MultichannelTests.inc:1048-1057 |
| 68 | T1 | 54 | 9 | 1.0 | Tests/DspBypassTests.inc:153-161 | Tests/DspBypassTests.inc:280-288 |
| 69 | T1 | 54 | 7 | 1.0 | Tests/LimiterTruePeakTests.inc:137-142 | Tests/MultichannelTests.inc:581-587 |
| 70 | T1 | 54 | 7 | 1.0 | Tests/LimiterTruePeakTests.inc:137-142 | Tests/MultichannelTests.inc:602-608 |
| 71 | T1 | 54 | 7 | 1.0 | Tests/LoudnessOracleTests.inc:50-55 | Tests/MultichannelTests.inc:581-587 |
| 72 | T1 | 54 | 7 | 1.0 | Tests/LoudnessOracleTests.inc:50-55 | Tests/MultichannelTests.inc:602-608 |
| 73 | T1 | 53 | 8 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:238-245 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:289-296 |
| 74 | T1 | 53 | 12 | 1.0 | Tests/LimiterTests.inc:308-318 | Tests/MultichannelTests.inc:1232-1243 |
| 75 | T1 | 52 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:31-36 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:416-421 |
| 76 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:44-50 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 |
| 77 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:44-50 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 78 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:130-136 |
| 79 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:45-51 |
| 80 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:16-22 |
| 81 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-62 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 82 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:130-136 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 83 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:45-51 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 84 | T1 | 52 | 7 | 1.0 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:16-22 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-35 |
| 85 | T1 | 52 | 9 | 1.0 | Tests/LimiterTests.inc:308-316 | Tests/MultichannelTests.inc:1048-1055 |
| 86 | T1 | 52 | 9 | 1.0 | Tests/MultichannelTests.inc:400-407 | Tests/MultichannelTests.inc:1232-1240 |
| 87 | T1 | 52 | 9 | 1.0 | Tests/MultichannelTests.inc:1048-1055 | Tests/MultichannelTests.inc:1232-1240 |
| 88 | T1 | 52 | 10 | 1.0 | Tests/SoakRtAllocTests.inc:124-131 | Tests/SoakRtAllocTests.inc:131-140 |
| 89 | T1 | 51 | 10 | 1.0 | Tests/FileDecodeTests.inc:781-790 | Tests/FileDecodeTests.inc:1134-1142 |
| 90 | T1 | 51 | 9 | 1.0 | Tests/FileDecodeTests.inc:1054-1062 | Tests/FileDecodeTests.inc:1134-1142 |
| 91 | T1 | 51 | 6 | 1.0 | Tests/LimiterTruePeakTests.inc:137-142 | Tests/LoudnessOracleTests.inc:67-72 |
| 92 | T1 | 51 | 6 | 1.0 | Tests/LoudnessOracleTests.inc:50-55 | Tests/LoudnessOracleTests.inc:67-72 |
| 93 | T1 | 51 | 8 | 1.0 | Tests/SpatialTests.inc:127-134 | Tests/SpatialTests.inc:174-181 |
| 94 | T1 | 50 | 7 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:43-49 |
| 95 | T1 | 50 | 7 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:129-135 |
| 96 | T1 | 50 | 7 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:44-50 |
| 97 | T1 | 50 | 8 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:60-66 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:14-21 |
| 98 | T1 | 50 | 6 | 1.0 | Tests/FileDecodeTests.inc:471-476 | Tests/FileDecodeTests.inc:533-538 |
| 99 | T1 | 50 | 12 | 1.0 | Tests/GaplessContractTests.inc:81-92 | Tests/GaplessContractTests.inc:187-198 |
| 100 | T1 | 50 | 12 | 1.0 | Tests/GaplessContractTests.inc:81-92 | Tests/GaplessContractTests.inc:421-432 |
| 101 | T1 | 50 | 12 | 1.0 | Tests/GaplessContractTests.inc:81-92 | Tests/SoakRtAllocTests.inc:421-431 |
| 102 | T1 | 50 | 12 | 1.0 | Tests/GaplessContractTests.inc:187-198 | Tests/SoakRtAllocTests.inc:421-431 |
| 103 | T1 | 50 | 12 | 1.0 | Tests/GaplessContractTests.inc:319-330 | Tests/SoakRtAllocTests.inc:421-431 |
| 104 | T1 | 50 | 12 | 1.0 | Tests/GaplessContractTests.inc:421-432 | Tests/SoakRtAllocTests.inc:421-431 |
| 105 | T1 | 50 | 11 | 1.0 | Tests/LimiterTests.inc:99-109 | Tests/LimiterTests.inc:305-314 |
| 106 | T1 | 50 | 6 | 1.0 | Tests/LimiterTruePeakTests.inc:142-147 | Tests/LoudnessTests.inc:25-30 |
| 107 | T1 | 50 | 6 | 1.0 | Tests/LoudnessOracleTests.inc:55-60 | Tests/LoudnessTests.inc:25-30 |
| 108 | T1 | 49 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:61-66 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:56-61 |
| 109 | T1 | 49 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:61-66 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:29-34 |
| 110 | T1 | 48 | 11 | 1.0 | Tests/LimiterTests.inc:181-191 | Tests/LimiterTests.inc:305-314 |
| 111 | T1 | 48 | 10 | 1.0 | Tests/LimiterTests.inc:239-247 | Tests/LimiterTests.inc:305-314 |
| 112 | T1 | 48 | 11 | 1.0 | Tests/LimiterTests.inc:99-109 | Tests/MultichannelTests.inc:396-405 |
| 113 | T1 | 48 | 11 | 1.0 | Tests/LimiterTests.inc:181-191 | Tests/MultichannelTests.inc:396-405 |
| 114 | T1 | 48 | 10 | 1.0 | Tests/LimiterTests.inc:239-247 | Tests/MultichannelTests.inc:396-405 |
| 115 | T1 | 48 | 6 | 1.0 | Tests/LoudnessTests.inc:24-29 | Tests/lufs-tool.cpp:81-86 |
| 116 | T1 | 46 | 6 | 1.0 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:35-40 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:84-89 |
| 117 | T1 | 46 | 7 | 1.0 | Tests/EqEngineTests.inc:928-934 | Tests/EqTransitionTests.inc:371-377 |
| 118 | T1 | 46 | 8 | 1.0 | Tests/IntensityTests.inc:97-104 | Tests/IntensityTests.inc:236-242 |
| 119 | T1 | 46 | 8 | 1.0 | Tests/IntensityTests.inc:97-104 | Tests/IntensityTests.inc:291-298 |
| 120 | T1 | 46 | 7 | 1.0 | Tests/IntensityTests.inc:166-172 | Tests/IntensityTests.inc:236-242 |
| 121 | T1 | 46 | 8 | 1.0 | Tests/IntensityTests.inc:166-172 | Tests/IntensityTests.inc:291-298 |
| 122 | T1 | 46 | 8 | 1.0 | Tests/IntensityTests.inc:236-242 | Tests/IntensityTests.inc:291-298 |
| 123 | T1 | 45 | 7 | 1.0 | Tests/DspBypassTests.inc:155-161 | Tests/DspBypassTests.inc:248-254 |
| 124 | T1 | 45 | 7 | 1.0 | Tests/DspBypassTests.inc:248-254 | Tests/DspBypassTests.inc:282-288 |
| 125 | T1 | 44 | 7 | 1.0 | Tests/DesignTokenKitTests/SettingsLayoutTests.swift:38-43 | Tests/DesignTokenKitTests/SlotFitTests.swift:19-25 |
| 126 | T1 | 43 | 11 | 1.0 | Tests/EqEngineTests.inc:97-106 | Tests/EqTransitionTests.inc:61-71 |
| 127 | T1 | 43 | 8 | 1.0 | Tests/LoudnessOracleTests.inc:148-155 | Tests/LoudnessOracleTests.inc:169-176 |
| 128 | T1 | 43 | 14 | 1.0 | Tests/SoakRtAllocTests.inc:327-340 | Tests/SoakRtAllocTests.inc:344-357 |
| 129 | T1 | 42 | 6 | 1.0 | Tests/AudioViewModelTests/QueueOpsTests.swift:35-40 | Tests/AudioViewModelTests/QueueOpsTests.swift:113-118 |
| 130 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:45-51 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 |
| 131 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/CapsuleSwitchAuditTests.swift:45-51 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 |
| 132 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:131-137 |
| 133 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:131-137 |
| 134 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:46-52 |
| 135 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 | Tests/DesignTokenKitTests/FocusRingAuditTests.swift:46-52 |
| 136 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-245 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:17-23 |
| 137 | T1 | 42 | 7 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-296 | Tests/DesignTokenKitTests/PlayingRowAuditTests.swift:17-23 |
| 138 | T1 | 42 | 6 | 1.0 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:36-41 | Tests/DesignTokenKitTests/QueueHeaderWidthsTests.swift:99-104 |
| 139 | T1 | 42 | 10 | 1.0 | Tests/GaplessContractTests.inc:275-284 | Tests/PureGaplessTests.inc:404-413 |
| 140 | T1 | 42 | 9 | 1.0 | Tests/GaplessTests.inc:74-82 | Tests/RoundTripTests.inc:68-76 |
| 141 | T1 | 42 | 6 | 1.0 | Tests/RoundTripTests.inc:99-104 | Tests/RoundTripTests.inc:140-145 |
| 142 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/AppGlowContrastAuditTests.swift:55-60 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:325-330 |
| 143 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-244 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:57-62 |
| 144 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-295 | Tests/DesignTokenKitTests/ControlChipAuditTests.swift:57-62 |
| 145 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:239-244 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:30-35 |
| 146 | T1 | 41 | 6 | 1.0 | Tests/DesignTokenKitTests/ContrastAuditTests.swift:290-295 | Tests/DesignTokenKitTests/SpectrumRampAuditTests.swift:30-35 |
| 147 | T1 | 41 | 8 | 1.0 | Tests/EqEngineBreakItTests.inc:269-276 | Tests/EqEngineFixTests.inc:347-353 |
| 148 | T1 | 41 | 6 | 1.0 | Tests/EqEngineFixTests.inc:1093-1098 | Tests/TrackLoudnessTests.inc:679-684 |
| 149 | T1 | 41 | 11 | 1.0 | Tests/FileDecodeTests.inc:1819-1829 | Tests/FileDecodeTests.inc:1907-1917 |
| 150 | T1 | 41 | 8 | 1.0 | Tests/FileDecodeTests.inc:1970-1977 | Tests/FileDecodeTests.inc:2020-2027 |
| 151 | T1 | 41 | 6 | 1.0 | Tests/LimiterTests.inc:310-315 | Tests/TestSupport.h:384-389 |
| 152 | T1 | 41 | 6 | 1.0 | Tests/MultichannelTests.inc:401-406 | Tests/TestSupport.h:384-389 |
| 153 | T1 | 41 | 6 | 1.0 | Tests/MultichannelTests.inc:1049-1054 | Tests/TestSupport.h:384-389 |
| 154 | T1 | 41 | 6 | 1.0 | Tests/MultichannelTests.inc:1234-1239 | Tests/TestSupport.h:384-389 |
| 155 | T1 | 41 | 10 | 1.0 | Tests/LoudnessNeutralTests.inc:128-137 | Tests/TrackLoudnessTests.inc:119-128 |
| 156 | T1 | 41 | 21 | 1.0 | Tests/SoakRtAllocTests.inc:327-340 | Tests/SoakRtAllocTests.inc:361-381 |
| 157 | T1 | 41 | 21 | 1.0 | Tests/SoakRtAllocTests.inc:344-357 | Tests/SoakRtAllocTests.inc:361-381 |
| 158 | T1 | 40 | 6 | 1.0 | Tests/DspBypassTests.inc:59-64 | Tests/LimiterTests.inc:50-55 |
| 159 | T1 | 40 | 6 | 1.0 | Tests/DspBypassTests.inc:59-64 | Tests/DspBypassTests.inc:118-123 |
| 160 | T1 | 40 | 13 | 1.0 | Tests/FileDecodeTests.inc:793-805 | Tests/FileDecodeTests.inc:1065-1077 |
| 161 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:880-887 | Tests/FileDecodeTests.inc:1054-1061 |
| 162 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:880-887 | Tests/FileDecodeTests.inc:1134-1141 |
| 163 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1708-1717 | Tests/FileDecodeTests.inc:1820-1829 |
| 164 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1708-1717 | Tests/FileDecodeTests.inc:1908-1917 |
| 165 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:1835-1842 |
| 166 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:1923-1930 |
| 167 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:2139-2146 |
| 168 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/FileDecodeTests.inc:2244-2251 |
| 169 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1820-1829 | Tests/FileDecodeTests.inc:2229-2238 |
| 170 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/FileDecodeTests.inc:1923-1930 |
| 171 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/FileDecodeTests.inc:2139-2146 |
| 172 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/FileDecodeTests.inc:2244-2251 |
| 173 | T1 | 40 | 10 | 1.0 | Tests/FileDecodeTests.inc:1908-1917 | Tests/FileDecodeTests.inc:2229-2238 |
| 174 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1923-1930 | Tests/FileDecodeTests.inc:2139-2146 |
| 175 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1923-1930 | Tests/FileDecodeTests.inc:2244-2251 |
| 176 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:2139-2146 | Tests/FileDecodeTests.inc:2244-2251 |
| 177 | T1 | 40 | 9 | 1.0 | Tests/FileDecodeTests.inc:781-789 | Tests/RoundTripTests.inc:85-92 |
| 178 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:880-887 | Tests/RoundTripTests.inc:85-92 |
| 179 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1054-1061 | Tests/RoundTripTests.inc:85-92 |
| 180 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1134-1141 | Tests/RoundTripTests.inc:85-92 |
| 181 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1723-1730 | Tests/RoundTripTests.inc:197-204 |
| 182 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1835-1842 | Tests/RoundTripTests.inc:197-204 |
| 183 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:1923-1930 | Tests/RoundTripTests.inc:197-204 |
| 184 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:2139-2146 | Tests/RoundTripTests.inc:197-204 |
| 185 | T1 | 40 | 8 | 1.0 | Tests/FileDecodeTests.inc:2244-2251 | Tests/RoundTripTests.inc:197-204 |
| 186 | T1 | 40 | 9 | 1.0 | Tests/GaplessTests.inc:204-212 | Tests/PureGaplessTests.inc:204-212 |
| 187 | T1 | 40 | 10 | 1.0 | Tests/PureModeTests.inc:562-571 | Tests/PureModeTests.inc:584-593 |
