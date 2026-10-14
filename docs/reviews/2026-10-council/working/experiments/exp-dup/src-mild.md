# clones ['Sources'] cross=False

```
{
 "files": 577,
 "tokens": 312093,
 "raw_clones": 297,
 "raw_by_kind": {
  "T1": 42,
  "T2": 251,
  "T3": 1,
  "REP": 3
 },
 "clones": 297,
 "by_kind": {
  "T1": 42,
  "T2": 251,
  "T3": 1,
  "REP": 3
 },
 "capped_buckets": 0,
 "settings": {
  "mode": "mild",
  "min_sim": 0.0,
  "k": 40,
  "min_lines": 6,
  "gap": 12,
  "roots": [
   "Sources"
  ],
  "cross": false
 }
}
```

| module | lines | dup lines | % | pairs |
|---|---|---|---|---|
| Sources/VerifyLibraryStore | 10791 | 1741 | 16.1 | 239 |
| Sources/AdaptiveSound/UI | 13325 | 300 | 2.3 | 20 |
| Sources/AudioDSP/AudioEngine | 2772 | 266 | 9.6 | 8 |
| Sources/AudioDSP | 3738 | 111 | 3.0 | 6 |
| Sources/AdaptiveSound(root) | 11865 | 75 | 0.6 | 6 |
| Sources/LibraryStore | 5479 | 74 | 1.4 | 5 |
| Sources/DesignTokenKit | 1694 | 72 | 4.3 | 7 |
| Sources/AdaptiveSound/Debug | 2446 | 45 | 1.8 | 3 |
| Sources/AudioDSP/Loudness | 3456 | 41 | 1.2 | 2 |
| Sources/VerifyAUGraph | 1374 | 33 | 2.4 | 3 |
| Sources/AudioDSP/Limiting | 573 | 23 | 4.0 | 1 |
| Sources/AudioDSP/Spatial | 569 | 18 | 3.2 | 1 |
| Sources/LibraryScan | 1528 | 9 | 0.6 | 1 |
| Sources/AdaptiveSound/Monitoring | 13 | 0 | 0.0 | 0 |
| Sources/AdaptiveSound/Spectrum | 446 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Clarity | 41 | 0 | 0.0 | 0 |
| Sources/AudioDSP/EQ | 1422 | 0 | 0.0 | 0 |
| Sources/AudioDSP/include | 3093 | 0 | 0.0 | 0 |
| Sources/AudioDSPTestBridge | 137 | 0 | 0.0 | 0 |
| Sources/AudioFormatKit | 105 | 0 | 0.0 | 0 |
| Sources/EQEditKit | 2113 | 0 | 0.0 | 0 |
| Sources/LibraryBrowseKit | 1997 | 0 | 0.0 | 0 |
| Sources/OutputDeviceKit | 153 | 0 | 0.0 | 0 |
| Sources/PlaybackQueueKit | 515 | 0 | 0.0 | 0 |
| Sources/SRCQualityMeasure | 523 | 0 | 0.0 | 0 |
| Sources/StoreSQLiteShim | 26 | 0 | 0.0 | 0 |
| Sources/TrackLoudnessKit | 431 | 0 | 0.0 | 0 |

| # | kind | tokens | lines | sim | A | B |
|---|---|---|---|---|---|---|
| 1 | T2 | 249 | 24 | 0.609 | Sources/VerifyLibraryStore/Fixtures.swift:198-216 | Sources/VerifyLibraryStore/Fixtures.swift:228-251 |
| 2 | T1 | 216 | 47 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:110-152 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:203-249 |
| 3 | REP | 204 | 18 | 0.625 | Sources/VerifyLibraryStore/Fixtures.swift:203-219 | Sources/VerifyLibraryStore/Fixtures.swift:217-234 |
| 4 | T2 | 179 | 24 | 0.955 | Sources/VerifyLibraryStore/ChecksArtworkCache.swift:74-97 | Sources/VerifyLibraryStore/ChecksArtworkMap.swift:106-129 |
| 5 | T2 | 174 | 12 | 0.741 | Sources/DesignTokenKit/SpectrumRamp.swift:27-38 | Sources/DesignTokenKit/SpectrumRamp.swift:39-50 |
| 6 | T3 | 159 | 26 | 0.898 | Sources/VerifyLibraryStore/ChecksCorruption.swift:120-145 | Sources/VerifyLibraryStore/ChecksCorruption.swift:299-320 |
| 7 | T2 | 154 | 17 | 0.891 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:52-68 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:139-154 |
| 8 | T2 | 140 | 18 | 0.729 | Sources/VerifyLibraryStore/Fixtures.swift:217-230 | Sources/VerifyLibraryStore/Fixtures.swift:234-251 |
| 9 | T2 | 139 | 22 | 0.816 | Sources/VerifyLibraryStore/ChecksSearch.swift:34-55 | Sources/VerifyLibraryStore/ChecksSearch.swift:64-85 |
| 10 | T2 | 131 | 15 | 0.87 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:192-206 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:133-147 |
| 11 | T2 | 128 | 10 | 0.958 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:19-28 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:24-33 |
| 12 | T2 | 123 | 13 | 0.925 | Sources/VerifyLibraryStore/ChecksMetadataReal.swift:37-49 | Sources/VerifyLibraryStore/ChecksMetadataReal.swift:113-125 |
| 13 | T2 | 121 | 13 | 0.854 | Sources/VerifyLibraryStore/ChecksSearch.swift:219-229 | Sources/VerifyLibraryStore/ChecksSearch.swift:251-263 |
| 14 | T2 | 116 | 8 | 0.741 | Sources/DesignTokenKit/SpectrumRamp.swift:27-34 | Sources/DesignTokenKit/SpectrumRamp.swift:35-42 |
| 15 | T2 | 116 | 8 | 0.741 | Sources/DesignTokenKit/SpectrumRamp.swift:27-34 | Sources/DesignTokenKit/SpectrumRamp.swift:43-50 |
| 16 | T2 | 113 | 6 | 0.577 | Sources/VerifyLibraryStore/Fixtures.swift:198-203 | Sources/VerifyLibraryStore/Fixtures.swift:214-219 |
| 17 | T2 | 111 | 13 | 0.976 | Sources/VerifyLibraryStore/ChecksMetadataReal.swift:50-62 | Sources/VerifyLibraryStore/ChecksMetadataReal.swift:126-138 |
| 18 | T2 | 106 | 10 | 0.9 | Sources/VerifyLibraryStore/ChecksSearch.swift:107-116 | Sources/VerifyLibraryStore/ChecksSearch.swift:180-189 |
| 19 | T1 | 97 | 23 | 1.0 | Sources/AudioDSP/Limiting/LimiterModule.h:193-215 | Sources/AudioDSP/Loudness/LoudnessModule.cpp:94-116 |
| 20 | T2 | 97 | 14 | 0.892 | Sources/VerifyLibraryStore/ChecksSearch.swift:79-92 | Sources/VerifyLibraryStore/ChecksSearch.swift:107-116 |
| 21 | T2 | 97 | 14 | 0.892 | Sources/VerifyLibraryStore/ChecksSearch.swift:79-92 | Sources/VerifyLibraryStore/ChecksSearch.swift:180-189 |
| 22 | T2 | 97 | 10 | 0.974 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:31-40 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:35-44 |
| 23 | T2 | 95 | 7 | 0.444 | Sources/AdaptiveSound/Debug/SheetFixture+Data.swift:31-37 | Sources/AdaptiveSound/Debug/SheetFixture+Data.swift:37-42 |
| 24 | T1 | 89 | 21 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:149-169 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:251-269 |
| 25 | T2 | 87 | 8 | 0.848 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:349-356 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:135-142 |
| 26 | T2 | 86 | 9 | 0.906 | Sources/VerifyLibraryStore/ChecksSearch.swift:15-23 | Sources/VerifyLibraryStore/ChecksSearch.swift:79-87 |
| 27 | T2 | 86 | 9 | 0.906 | Sources/VerifyLibraryStore/ChecksSearch.swift:15-23 | Sources/VerifyLibraryStore/ChecksSearch.swift:107-115 |
| 28 | T2 | 86 | 9 | 0.906 | Sources/VerifyLibraryStore/ChecksSearch.swift:15-23 | Sources/VerifyLibraryStore/ChecksSearch.swift:180-188 |
| 29 | T1 | 85 | 21 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:244-264 | Sources/AudioDSP/FileDecodeSource.cpp:718-738 |
| 30 | T2 | 84 | 8 | 0.848 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:213-220 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:10-17 |
| 31 | T2 | 80 | 7 | 0.862 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:93-99 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:84-90 |
| 32 | T2 | 80 | 7 | 0.867 | Sources/VerifyLibraryStore/ChecksSearch.swift:49-55 | Sources/VerifyLibraryStore/ChecksSearch.swift:219-225 |
| 33 | T2 | 80 | 7 | 0.867 | Sources/VerifyLibraryStore/ChecksSearch.swift:49-55 | Sources/VerifyLibraryStore/ChecksSearch.swift:251-257 |
| 34 | T2 | 80 | 8 | 0.839 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:57-64 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:196-203 |
| 35 | T2 | 79 | 7 | 0.968 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:247-253 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:264-270 |
| 36 | T2 | 79 | 7 | 0.657 | Sources/VerifyLibraryStore/Fixtures.swift:195-201 | Sources/VerifyLibraryStore/Fixtures.swift:209-215 |
| 37 | T2 | 79 | 7 | 0.657 | Sources/VerifyLibraryStore/Fixtures.swift:195-201 | Sources/VerifyLibraryStore/Fixtures.swift:223-229 |
| 38 | T2 | 79 | 9 | 0.6 | Sources/VerifyLibraryStore/Fixtures.swift:195-201 | Sources/VerifyLibraryStore/Fixtures.swift:240-248 |
| 39 | T2 | 77 | 9 | 0.576 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:55-60 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:337-345 |
| 40 | T2 | 77 | 9 | 0.839 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:126-132 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:119-127 |
| 41 | T2 | 76 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:349-355 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:82-88 |
| 42 | T2 | 76 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:82-88 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:135-141 |
| 43 | T2 | 75 | 7 | 0.929 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:139-145 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:264-270 |
| 44 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:15-21 | Sources/VerifyLibraryStore/ChecksSearch.swift:49-55 |
| 45 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:15-21 | Sources/VerifyLibraryStore/ChecksSearch.swift:219-225 |
| 46 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:15-21 | Sources/VerifyLibraryStore/ChecksSearch.swift:251-257 |
| 47 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:49-55 | Sources/VerifyLibraryStore/ChecksSearch.swift:107-113 |
| 48 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:49-55 | Sources/VerifyLibraryStore/ChecksSearch.swift:180-186 |
| 49 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:79-85 | Sources/VerifyLibraryStore/ChecksSearch.swift:219-225 |
| 50 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:79-85 | Sources/VerifyLibraryStore/ChecksSearch.swift:251-257 |
| 51 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:107-113 | Sources/VerifyLibraryStore/ChecksSearch.swift:219-225 |
| 52 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:107-113 | Sources/VerifyLibraryStore/ChecksSearch.swift:251-257 |
| 53 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:180-186 | Sources/VerifyLibraryStore/ChecksSearch.swift:219-225 |
| 54 | T2 | 75 | 7 | 0.893 | Sources/VerifyLibraryStore/ChecksSearch.swift:180-186 | Sources/VerifyLibraryStore/ChecksSearch.swift:251-257 |
| 55 | T2 | 74 | 6 | 0.485 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:58-63 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:332-337 |
| 56 | T2 | 72 | 7 | 0.258 | Sources/AdaptiveSound/Debug/SheetFixture+Browse.swift:15-21 | Sources/AdaptiveSound/Debug/SheetFixture+Browse.swift:22-28 |
| 57 | T2 | 72 | 6 | 0.5 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:58-63 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:334-339 |
| 58 | T2 | 72 | 6 | 0.5 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:58-63 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:335-340 |
| 59 | T2 | 71 | 7 | 0.96 | Sources/VerifyLibraryStore/ChecksArtworkMap.swift:16-22 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:52-58 |
| 60 | T2 | 71 | 7 | 0.96 | Sources/VerifyLibraryStore/ChecksArtworkMap.swift:16-22 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:139-145 |
| 61 | T2 | 68 | 6 | 0.533 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:58-63 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:336-341 |
| 62 | T1 | 67 | 10 | 1.0 | Sources/AdaptiveSound/AudioEngineBridge+Graph.swift:186-195 | Sources/AdaptiveSound/AudioEngineBridge+Graph.swift:208-216 |
| 63 | T1 | 67 | 8 | 1.0 | Sources/AdaptiveSound/UI/EQ/EQBringBackMessage.swift:54-61 | Sources/AdaptiveSound/UI/Shell/ShellToast.swift:117-124 |
| 64 | T2 | 67 | 13 | 0.913 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:79-91 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:113-123 |
| 65 | T2 | 66 | 7 | 0.957 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:349-355 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:230-235 |
| 66 | T2 | 66 | 7 | 0.957 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:349-355 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:89-95 |
| 67 | T2 | 66 | 7 | 0.957 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:89-95 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:82-88 |
| 68 | T2 | 66 | 7 | 0.957 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:89-95 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:135-140 |
| 69 | T2 | 66 | 7 | 0.957 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:89-95 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:230-235 |
| 70 | T2 | 66 | 7 | 0.957 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:82-88 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:230-235 |
| 71 | T2 | 66 | 6 | 0.957 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:135-140 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:230-235 |
| 72 | T1 | 65 | 8 | 1.0 | Sources/AdaptiveSound/DesignSystemGlass.swift:162-169 | Sources/AdaptiveSound/DesignSystemGlassControls.swift:51-58 |
| 73 | T2 | 65 | 11 | 0.96 | Sources/AdaptiveSound/UI/EQ/EQDeletePresetDialog.swift:8-18 | Sources/AdaptiveSound/UI/Playlist/PlaylistDeleteDialog.swift:8-18 |
| 74 | T1 | 65 | 15 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:59-73 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:149-163 |
| 75 | T2 | 65 | 7 | 0.593 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:329-334 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:259-265 |
| 76 | T2 | 64 | 7 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:193-199 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:10-16 |
| 77 | T2 | 64 | 7 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:193-199 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:213-219 |
| 78 | REP | 64 | 33 | 0.0 | Sources/VerifyLibraryStore/main.swift:339-365 | Sources/VerifyLibraryStore/main.swift:359-391 |
| 79 | T2 | 63 | 12 | 0.952 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:704-715 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:742-753 |
| 80 | T1 | 63 | 6 | 1.0 | Sources/LibraryStore/LibraryStore+DAO.swift:211-216 | Sources/LibraryStore/LibraryStore+MoveMatch.swift:80-85 |
| 81 | T2 | 63 | 6 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:126-131 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:10-15 |
| 82 | T2 | 63 | 6 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:170-175 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:10-15 |
| 83 | T2 | 63 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:170-175 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:119-126 |
| 84 | T2 | 63 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:193-198 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:119-126 |
| 85 | T2 | 63 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:213-218 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:119-126 |
| 86 | T2 | 63 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:10-15 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:119-126 |
| 87 | T2 | 63 | 6 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:126-131 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:170-175 |
| 88 | T2 | 63 | 6 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:126-131 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:193-198 |
| 89 | T2 | 63 | 6 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:126-131 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:213-218 |
| 90 | T2 | 63 | 6 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:170-175 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:193-198 |
| 91 | T2 | 63 | 6 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:170-175 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:213-218 |
| 92 | T2 | 62 | 19 | 0.882 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:198-215 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:306-324 |
| 93 | T1 | 62 | 24 | 1.0 | Sources/VerifyLibraryStore/Fixtures.swift:45-68 | Sources/VerifyLibraryStore/Fixtures.swift:330-341 |
| 94 | T2 | 61 | 6 | 0.857 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:95-100 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:104-109 |
| 95 | T1 | 60 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksFrecency.swift:41-46 | Sources/VerifyLibraryStore/ChecksFrecency.swift:164-169 |
| 96 | T2 | 59 | 11 | 0.895 | Sources/VerifyLibraryStore/Checks.swift:113-123 | Sources/VerifyLibraryStore/Checks.swift:178-188 |
| 97 | T2 | 59 | 6 | 0.952 | Sources/VerifyLibraryStore/ChecksSongsSort.swift:250-255 | Sources/VerifyLibraryStore/ChecksSongsSortPlayTracking.swift:11-16 |
| 98 | T2 | 59 | 12 | 0.8 | Sources/VerifyLibraryStore/ChecksFrecency.swift:49-60 | Sources/VerifyLibraryStore/ChecksFrecency.swift:172-183 |
| 99 | T2 | 59 | 6 | 0.87 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:150-155 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:343-348 |
| 100 | T1 | 58 | 10 | 1.0 | Sources/AdaptiveSound/AudioEngineBridge+GaplessRoll.swift:208-215 | Sources/AdaptiveSound/AudioEngineBridge+PureMode.swift:350-359 |
| 101 | T1 | 58 | 7 | 1.0 | Sources/LibraryStore/LibraryStore+Playlists.swift:215-221 | Sources/LibraryStore/LibraryStore+Playlists.swift:233-239 |
| 102 | T2 | 58 | 8 | 0.792 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:33-40 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:96-102 |
| 103 | T2 | 57 | 7 | 0.952 | Sources/AdaptiveSound/AudioEngineBridge+GaplessRoll.swift:34-40 | Sources/AdaptiveSound/AudioEngineBridge+GaplessRoll.swift:72-78 |
| 104 | T1 | 57 | 10 | 1.0 | Sources/AudioDSP/Loudness/LufsMeter.h:268-275 | Sources/AudioDSP/Loudness/LufsMeter.h:286-295 |
| 105 | T2 | 57 | 8 | 0.917 | Sources/AudioDSP/PureModeFormat.cpp:120-127 | Sources/AudioDSP/PureModeFormat.cpp:139-145 |
| 106 | T2 | 57 | 6 | 0.95 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:349-354 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:23-28 |
| 107 | T2 | 57 | 6 | 0.95 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:23-28 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:89-94 |
| 108 | T2 | 57 | 6 | 0.95 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:23-28 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:82-87 |
| 109 | T2 | 57 | 6 | 0.95 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:23-28 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:135-140 |
| 110 | T2 | 57 | 6 | 0.95 | Sources/VerifyLibraryStore/ChecksDecodeCoverage.swift:23-28 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:230-235 |
| 111 | T2 | 57 | 10 | 0.95 | Sources/VerifyLibraryStore/ChecksSearch.swift:15-20 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:16-25 |
| 112 | T2 | 57 | 10 | 0.95 | Sources/VerifyLibraryStore/ChecksSearch.swift:49-54 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:16-25 |
| 113 | T2 | 57 | 10 | 0.95 | Sources/VerifyLibraryStore/ChecksSearch.swift:79-84 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:16-25 |
| 114 | T2 | 57 | 10 | 0.95 | Sources/VerifyLibraryStore/ChecksSearch.swift:107-112 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:16-25 |
| 115 | T2 | 57 | 10 | 0.95 | Sources/VerifyLibraryStore/ChecksSearch.swift:180-185 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:16-25 |
| 116 | T2 | 57 | 10 | 0.95 | Sources/VerifyLibraryStore/ChecksSearch.swift:219-224 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:16-25 |
| 117 | T2 | 57 | 10 | 0.95 | Sources/VerifyLibraryStore/ChecksSearch.swift:251-256 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:16-25 |
| 118 | REP | 57 | 29 | 0.0 | Sources/VerifyLibraryStore/main.swift:339-366 | Sources/VerifyLibraryStore/main.swift:366-394 |
| 119 | T2 | 56 | 9 | 0.944 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:495-503 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:517-525 |
| 120 | T1 | 56 | 9 | 1.0 | Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp:39-47 | Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp:82-90 |
| 121 | T1 | 55 | 7 | 1.0 | Sources/LibraryStore/LibraryStore.swift:214-220 | Sources/LibraryStore/LibraryStore.swift:230-236 |
| 122 | T1 | 53 | 15 | 1.0 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:162-176 | Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift:423-435 |
| 123 | T2 | 53 | 6 | 0.762 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:354-359 | Sources/VerifyLibraryStore/ChecksConcurrency.swift:282-287 |
| 124 | T2 | 53 | 7 | 0.905 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:302-308 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:32-38 |
| 125 | T2 | 52 | 11 | 0.739 | Sources/DesignTokenKit/Palette.swift:69-79 | Sources/DesignTokenKit/Palette.swift:141-147 |
| 126 | T2 | 52 | 11 | 0.87 | Sources/DesignTokenKit/Palette.swift:69-79 | Sources/DesignTokenKit/Palette.swift:174-184 |
| 127 | T2 | 52 | 11 | 0.739 | Sources/DesignTokenKit/Palette.swift:141-147 | Sources/DesignTokenKit/Palette.swift:174-184 |
| 128 | T1 | 52 | 12 | 1.0 | Sources/LibraryStore/LibraryStore+BrowseReads.swift:134-141 | Sources/LibraryStore/LibraryStore+BrowseReads.swift:212-223 |
| 129 | T2 | 52 | 12 | 0.562 | Sources/VerifyLibraryStore/ChecksFacetSweep.swift:82-93 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:244-255 |
| 130 | T2 | 52 | 16 | 0.562 | Sources/VerifyLibraryStore/ChecksFacetSweep.swift:82-97 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:190-205 |
| 131 | T2 | 52 | 17 | 0.688 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:174-190 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:121-135 |
| 132 | T2 | 51 | 15 | 0.4 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:172-186 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:203-216 |
| 133 | T2 | 51 | 15 | 0.625 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:121-135 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:191-205 |
| 134 | T2 | 51 | 15 | 0.667 | Sources/VerifyLibraryStore/ChecksSearch.swift:127-141 | Sources/VerifyLibraryStore/ChecksSearch.swift:166-180 |
| 135 | T2 | 51 | 15 | 0.625 | Sources/VerifyLibraryStore/ChecksFacetSweep.swift:83-97 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:121-135 |
| 136 | T2 | 51 | 12 | 0.562 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:190-201 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:244-255 |
| 137 | T2 | 51 | 17 | 0.625 | Sources/VerifyLibraryStore/ChecksFacetSweep.swift:83-97 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:174-190 |
| 138 | T2 | 51 | 17 | 0.625 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:174-190 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:191-205 |
| 139 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:126-131 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:147-154 |
| 140 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:170-175 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:147-154 |
| 141 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:193-198 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:147-154 |
| 142 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:213-218 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:147-154 |
| 143 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:10-15 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:147-154 |
| 144 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:119-126 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:147-154 |
| 145 | T2 | 51 | 7 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:61-67 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:126-131 |
| 146 | T2 | 51 | 7 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:61-67 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:170-175 |
| 147 | T2 | 51 | 7 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:61-67 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:193-198 |
| 148 | T2 | 51 | 7 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:61-67 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:213-218 |
| 149 | T2 | 51 | 7 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:61-67 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:10-15 |
| 150 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:61-67 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:119-126 |
| 151 | T2 | 51 | 8 | 0.8 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:61-67 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:147-154 |
| 152 | T2 | 50 | 7 | 0.952 | Sources/AdaptiveSound/UI/Library/NavRow.swift:66-72 | Sources/AdaptiveSound/UI/Playlist/PlaylistItemRow.swift:127-133 |
| 153 | T2 | 50 | 11 | 0.562 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:121-131 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:245-255 |
| 154 | T2 | 50 | 11 | 0.562 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:174-184 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:245-255 |
| 155 | T2 | 50 | 13 | 0.786 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:353-363 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:135-147 |
| 156 | T2 | 49 | 6 | 0.933 | Sources/VerifyLibraryStore/ChecksCorruption.swift:165-170 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:315-320 |
| 157 | T2 | 49 | 7 | 0.875 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:102-108 | Sources/VerifyLibraryStore/ChecksMetadataStore.swift:166-172 |
| 158 | T2 | 49 | 7 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylistFolders.swift:88-94 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:363-368 |
| 159 | T2 | 49 | 7 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylistFolders.swift:88-94 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:57-62 |
| 160 | T2 | 49 | 7 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylistFolders.swift:88-94 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:171-176 |
| 161 | T2 | 49 | 7 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylistFolders.swift:88-94 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:196-201 |
| 162 | T2 | 49 | 13 | 0.786 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:224-234 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:135-147 |
| 163 | T2 | 49 | 6 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:363-368 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:57-62 |
| 164 | T2 | 49 | 6 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:363-368 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:171-176 |
| 165 | T2 | 49 | 6 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:363-368 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:196-201 |
| 166 | T2 | 49 | 6 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:57-62 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:171-176 |
| 167 | T2 | 49 | 6 | 0.842 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:171-176 | Sources/VerifyLibraryStore/ChecksPlaylistsHardening.swift:196-201 |
| 168 | T2 | 49 | 11 | 0.786 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:224-234 | Sources/VerifyLibraryStore/ChecksPlaylists.swift:353-363 |
| 169 | T2 | 48 | 10 | 0.947 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:189-197 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:204-213 |
| 170 | T1 | 48 | 14 | 1.0 | Sources/AdaptiveSound/UI/Playlist/PlaylistDetailView.swift:297-303 | Sources/AdaptiveSound/UI/Playlist/PlaylistItemRow.swift:111-124 |
| 171 | T2 | 48 | 6 | 0.933 | Sources/VerifyLibraryStore/ChecksAlbumArtistData.swift:84-89 | Sources/VerifyLibraryStore/ChecksArtworkMap.swift:16-21 |
| 172 | T2 | 48 | 6 | 0.933 | Sources/VerifyLibraryStore/ChecksAlbumArtistData.swift:84-89 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:52-57 |
| 173 | T2 | 48 | 6 | 0.933 | Sources/VerifyLibraryStore/ChecksAlbumArtistData.swift:84-89 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:139-144 |
| 174 | T2 | 48 | 10 | 0.938 | Sources/VerifyLibraryStore/ChecksCorruption.swift:56-63 | Sources/VerifyLibraryStore/ChecksCorruption.swift:87-96 |
| 175 | T1 | 47 | 6 | 1.0 | Sources/AdaptiveSound/UI/Library/AlbumArtworkView.swift:25-30 | Sources/AdaptiveSound/UI/Library/BrowseArt.swift:30-35 |
| 176 | T1 | 47 | 7 | 1.0 | Sources/LibraryStore/LibraryStore+DAO.swift:244-250 | Sources/LibraryStore/LibraryStore+MoveMatch.swift:111-117 |
| 177 | T2 | 47 | 11 | 0.882 | Sources/VerifyAUGraph/VerifyMultichannel.swift:153-163 | Sources/VerifyAUGraph/VerifyTwoAUGraph.swift:140-150 |
| 178 | T2 | 47 | 11 | 0.882 | Sources/VerifyAUGraph/VerifyMultichannel.swift:153-163 | Sources/VerifyAUGraph/VerifyTwoAUGraph.swift:229-239 |
| 179 | T2 | 47 | 11 | 0.941 | Sources/VerifyAUGraph/VerifyTwoAUGraph.swift:140-150 | Sources/VerifyAUGraph/VerifyTwoAUGraph.swift:229-239 |
| 180 | T2 | 46 | 6 | 0.944 | Sources/AdaptiveSound/UI/Loudness/LoudnessMetersView.swift:22-27 | Sources/AdaptiveSound/UI/NowPlaying/InspectorColumn.swift:145-150 |
| 181 | T2 | 46 | 6 | 0.889 | Sources/AdaptiveSound/UI/Loudness/LoudnessMetersView.swift:22-27 | Sources/AdaptiveSound/UI/Playlist/TrackInfoCard.swift:80-85 |
| 182 | T2 | 46 | 6 | 0.889 | Sources/AdaptiveSound/UI/NowPlaying/InspectorColumn.swift:145-150 | Sources/AdaptiveSound/UI/Playlist/TrackInfoCard.swift:80-85 |
| 183 | T1 | 46 | 11 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:268-278 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:334-344 |
| 184 | T2 | 46 | 7 | 0.875 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:65-70 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:167-173 |
| 185 | T1 | 45 | 9 | 1.0 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:27-34 | Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift:19-27 |
| 186 | T1 | 45 | 8 | 1.0 | Sources/AdaptiveSound/UI/Library/DetailTrackList.swift:138-143 | Sources/AdaptiveSound/UI/Library/SongsListView.swift:232-239 |
| 187 | T2 | 45 | 11 | 0.941 | Sources/AdaptiveSound/UI/NowPlaying/InspectorColumn.swift:88-98 | Sources/AdaptiveSound/UI/NowPlaying/MasterGainSliderView.swift:16-26 |
| 188 | T1 | 45 | 9 | 1.0 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:352-360 | Sources/AudioDSP/FileDecodeSource.cpp:906-914 |
| 189 | T2 | 45 | 10 | 0.737 | Sources/DesignTokenKit/Palette.swift:207-215 | Sources/DesignTokenKit/Palette.swift:226-235 |
| 190 | T2 | 45 | 8 | 0.526 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:124-130 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:155-162 |
| 191 | T2 | 45 | 8 | 0.938 | Sources/VerifyLibraryStore/ChecksCorruption.swift:299-306 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:163-168 |
| 192 | T2 | 44 | 11 | 0.765 | Sources/AdaptiveSound/UI/Library/ArtistsView.swift:25-35 | Sources/AdaptiveSound/UI/Library/GenresView.swift:22-32 |
| 193 | T1 | 44 | 6 | 1.0 | Sources/AudioDSP/GaplessSource.cpp:150-155 | Sources/AudioDSP/GaplessSource.cpp:163-168 |
| 194 | T2 | 44 | 21 | 0.462 | Sources/VerifyLibraryStore/ChecksAlbumArtist.swift:184-201 | Sources/VerifyLibraryStore/ChecksAlbumArtist.swift:266-286 |
| 195 | T2 | 44 | 17 | 0.692 | Sources/VerifyLibraryStore/ChecksCRUD.swift:40-53 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:233-249 |
| 196 | T2 | 44 | 6 | 0.857 | Sources/VerifyLibraryStore/ChecksQueryPlan.swift:25-30 | Sources/VerifyLibraryStore/ChecksSongsSort.swift:436-441 |
| 197 | T1 | 43 | 10 | 1.0 | Sources/AdaptiveSound/UI/Library/LibrarySidebar.swift:297-306 | Sources/AdaptiveSound/UI/Playlist/PlaylistDetailView.swift:160-169 |
| 198 | T1 | 43 | 9 | 1.0 | Sources/LibraryScan/FileSignature.swift:63-71 | Sources/VerifyLibraryStore/ScanFixtureBuilder.swift:165-171 |
| 199 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:140-145 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:54-59 |
| 200 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:140-145 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:141-146 |
| 201 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:265-270 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:54-59 |
| 202 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:265-270 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:141-146 |
| 203 | T1 | 43 | 7 | 1.0 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:94-100 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:280-286 |
| 204 | T2 | 43 | 22 | 0.0 | Sources/VerifyLibraryStore/main.swift:339-360 | Sources/VerifyLibraryStore/main.swift:373-394 |
| 205 | T1 | 42 | 9 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:1380-1387 | Sources/AudioDSP/FileDecodeSource.cpp:1390-1398 |
| 206 | T1 | 42 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:119-124 | Sources/VerifyLibraryStore/ChecksCRUD.swift:187-192 |
| 207 | T2 | 42 | 18 | 0.583 | Sources/VerifyLibraryStore/ChecksScan.swift:32-49 | Sources/VerifyLibraryStore/ChecksSongsSort.swift:419-432 |
| 208 | T1 | 41 | 8 | 1.0 | Sources/AdaptiveSound/MenuBarView.swift:12-19 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:27-33 |
| 209 | T1 | 41 | 8 | 1.0 | Sources/AdaptiveSound/MenuBarView.swift:12-19 | Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift:19-26 |
| 210 | T1 | 41 | 7 | 1.0 | Sources/AdaptiveSound/UI/Playlist/AddToPlaylistMenu.swift:42-48 | Sources/AdaptiveSound/UI/Playlist/AddToPlaylistMenu.swift:132-138 |
| 211 | T1 | 41 | 8 | 1.0 | Sources/AudioDSP/PureModeFormat.cpp:171-178 | Sources/AudioDSP/PureModeFormat.cpp:183-190 |
| 212 | T2 | 40 | 10 | 0.938 | Sources/AdaptiveSound/Debug/SheetFixture+Detail.swift:23-31 | Sources/AdaptiveSound/Debug/SheetFixture+Detail.swift:41-50 |
| 213 | T1 | 40 | 11 | 1.0 | Sources/AdaptiveSound/UI/Library/DetailTrackRow.swift:26-35 | Sources/AdaptiveSound/UI/Library/SongRow.swift:23-33 |
| 214 | T2 | 40 | 10 | 0.786 | Sources/AdaptiveSound/UI/Library/LibraryEmptyStateView.swift:35-44 | Sources/AdaptiveSound/UI/Library/LibraryEmptyStateView.swift:51-60 |
| 215 | T2 | 40 | 15 | 0.545 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:240-254 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:269-283 |
| 216 | T2 | 40 | 12 | 0.462 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:105-116 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:148-159 |
| 217 | T2 | 40 | 12 | 0.5 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:185-196 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:343-354 |
| 218 | T2 | 40 | 20 | 0.5 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:309-324 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:120-139 |
| 219 | T2 | 40 | 15 | 0.545 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:240-254 | Sources/VerifyLibraryStore/ChecksReachability.swift:22-36 |
| 220 | T2 | 40 | 15 | 0.545 | Sources/VerifyLibraryStore/ChecksAlbumIdentity.swift:269-283 | Sources/VerifyLibraryStore/ChecksReachability.swift:22-36 |
| 221 | T2 | 40 | 14 | 0.6 | Sources/VerifyLibraryStore/ChecksArtworkMap.swift:66-79 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:189-202 |
| 222 | T1 | 40 | 7 | 1.0 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:23-29 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:119-124 |
| 223 | T2 | 40 | 19 | 0.636 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:295-313 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:336-349 |
| 224 | T1 | 40 | 7 | 1.0 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:23-29 | Sources/VerifyLibraryStore/ChecksCRUD.swift:187-192 |
| 225 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:34-46 | Sources/VerifyLibraryStore/ChecksCRUD.swift:40-53 |
| 226 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:34-46 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:233-249 |
| 227 | T2 | 40 | 15 | 0.667 | Sources/VerifyLibraryStore/ChecksSearch.swift:237-251 | Sources/VerifyLibraryStore/ChecksSearch.swift:281-295 |
| 228 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 |
| 229 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 |
| 230 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 |
| 231 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 |
| 232 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 |
| 233 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 |
| 234 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 |
| 235 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 236 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 237 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 238 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksFSDivergence.swift:27-41 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 239 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 |
| 240 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 |
| 241 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 |
| 242 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 |
| 243 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 |
| 244 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 |
| 245 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 |
| 246 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 |
| 247 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 |
| 248 | T2 | 40 | 13 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 |
| 249 | T2 | 40 | 13 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 250 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 251 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 |
| 252 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 253 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 254 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 255 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 256 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:106-118 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 257 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:198-211 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 258 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 |
| 259 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 |
| 260 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 |
| 261 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 |
| 262 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 |
| 263 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 |
| 264 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 |
| 265 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 266 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 267 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 |
| 268 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 269 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 270 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 |
| 271 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 272 | T2 | 40 | 16 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 273 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 |
| 274 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 275 | T2 | 40 | 15 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 276 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 277 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 278 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 279 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 280 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:34-49 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 281 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:168-182 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 282 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:221-236 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 283 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:333-347 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 284 | T2 | 40 | 13 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 |
| 285 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 286 | T2 | 40 | 14 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 |
| 287 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 288 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 289 | T2 | 40 | 17 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 |
| 290 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:33-45 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 291 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:84-96 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 292 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:165-178 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 293 | T2 | 40 | 18 | 0.636 | Sources/VerifyLibraryStore/ChecksScanRescan.swift:31-47 | Sources/VerifyLibraryStore/ChecksSearchFilter.swift:42-59 |
| 294 | T2 | 40 | 17 | 0.5 | Sources/VerifyLibraryStore/ChecksGenreCovers.swift:365-380 | Sources/VerifyLibraryStore/ChecksStoreOpenSafety.swift:245-261 |
| 295 | T2 | 40 | 11 | 0.5 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:44-54 | Sources/VerifyLibraryStore/ChecksSearchMigration.swift:233-243 |
| 296 | T2 | 40 | 18 | 0.545 | Sources/VerifyLibraryStore/ChecksScan.swift:32-49 | Sources/VerifyLibraryStore/ChecksSongsSort.swift:286-300 |
| 297 | T2 | 40 | 15 | 0.545 | Sources/VerifyLibraryStore/ChecksSongsSort.swift:286-300 | Sources/VerifyLibraryStore/ChecksSongsSort.swift:419-432 |
