# clones ['Sources'] cross=False

```
{
 "files": 577,
 "tokens": 312093,
 "raw_clones": 55,
 "raw_by_kind": {
  "T1": 55,
  "T2": 0,
  "T3": 0,
  "REP": 0
 },
 "clones": 55,
 "by_kind": {
  "T1": 55,
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
   "Sources"
  ],
  "cross": false
 }
}
```

| module | lines | dup lines | % | pairs |
|---|---|---|---|---|
| Sources/VerifyLibraryStore | 10791 | 252 | 2.3 | 20 |
| Sources/AudioDSP/AudioEngine | 2772 | 213 | 7.7 | 7 |
| Sources/AdaptiveSound/UI | 13325 | 163 | 1.2 | 11 |
| Sources/AudioDSP | 3738 | 108 | 2.9 | 6 |
| Sources/LibraryStore | 5479 | 74 | 1.4 | 5 |
| Sources/AdaptiveSound(root) | 11865 | 73 | 0.6 | 6 |
| Sources/AudioDSP/Loudness | 3456 | 41 | 1.2 | 2 |
| Sources/AudioDSP/Limiting | 573 | 23 | 4.0 | 1 |
| Sources/AudioDSP/Spatial | 569 | 18 | 3.2 | 1 |
| Sources/LibraryScan | 1528 | 9 | 0.6 | 1 |
| Sources/AdaptiveSound/Debug | 2446 | 0 | 0.0 | 0 |
| Sources/AdaptiveSound/Monitoring | 13 | 0 | 0.0 | 0 |
| Sources/AdaptiveSound/Spectrum | 446 | 0 | 0.0 | 0 |
| Sources/AudioDSP/Clarity | 41 | 0 | 0.0 | 0 |
| Sources/AudioDSP/EQ | 1422 | 0 | 0.0 | 0 |
| Sources/AudioDSP/include | 3093 | 0 | 0.0 | 0 |
| Sources/AudioDSPTestBridge | 137 | 0 | 0.0 | 0 |
| Sources/AudioFormatKit | 105 | 0 | 0.0 | 0 |
| Sources/DesignTokenKit | 1694 | 0 | 0.0 | 0 |
| Sources/EQEditKit | 2113 | 0 | 0.0 | 0 |
| Sources/LibraryBrowseKit | 1997 | 0 | 0.0 | 0 |
| Sources/OutputDeviceKit | 153 | 0 | 0.0 | 0 |
| Sources/PlaybackQueueKit | 515 | 0 | 0.0 | 0 |
| Sources/SRCQualityMeasure | 523 | 0 | 0.0 | 0 |
| Sources/StoreSQLiteShim | 26 | 0 | 0.0 | 0 |
| Sources/TrackLoudnessKit | 431 | 0 | 0.0 | 0 |
| Sources/VerifyAUGraph | 1374 | 0 | 0.0 | 0 |

| # | kind | tokens | lines | sim | A | B |
|---|---|---|---|---|---|---|
| 1 | T1 | 216 | 47 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:110-152 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:203-249 |
| 2 | T1 | 179 | 24 | 1.0 | Sources/VerifyLibraryStore/ChecksArtworkCache.swift:74-97 | Sources/VerifyLibraryStore/ChecksArtworkMap.swift:106-129 |
| 3 | T1 | 97 | 23 | 1.0 | Sources/AudioDSP/Limiting/LimiterModule.h:193-215 | Sources/AudioDSP/Loudness/LoudnessModule.cpp:94-116 |
| 4 | T1 | 95 | 10 | 1.0 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:31-40 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:35-44 |
| 5 | T1 | 89 | 21 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:149-169 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:251-269 |
| 6 | T1 | 85 | 21 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:244-264 | Sources/AudioDSP/FileDecodeSource.cpp:718-738 |
| 7 | T1 | 83 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksMoveMatch.swift:22-27 | Sources/VerifyLibraryStore/ChecksPlaylistScan.swift:27-32 |
| 8 | T1 | 76 | 8 | 1.0 | Sources/VerifyLibraryStore/ChecksMetadataReal.swift:50-57 | Sources/VerifyLibraryStore/ChecksMetadataReal.swift:126-133 |
| 9 | T1 | 67 | 10 | 1.0 | Sources/AdaptiveSound/AudioEngineBridge+Graph.swift:186-195 | Sources/AdaptiveSound/AudioEngineBridge+Graph.swift:208-216 |
| 10 | T1 | 67 | 8 | 1.0 | Sources/AdaptiveSound/UI/EQ/EQBringBackMessage.swift:54-61 | Sources/AdaptiveSound/UI/Shell/ShellToast.swift:117-124 |
| 11 | T1 | 65 | 8 | 1.0 | Sources/AdaptiveSound/DesignSystemGlass.swift:162-169 | Sources/AdaptiveSound/DesignSystemGlassControls.swift:51-58 |
| 12 | T1 | 65 | 15 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:59-73 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:149-163 |
| 13 | T1 | 63 | 6 | 1.0 | Sources/LibraryStore/LibraryStore+DAO.swift:211-216 | Sources/LibraryStore/LibraryStore+MoveMatch.swift:80-85 |
| 14 | T1 | 62 | 24 | 1.0 | Sources/VerifyLibraryStore/Fixtures.swift:45-68 | Sources/VerifyLibraryStore/Fixtures.swift:330-341 |
| 15 | T1 | 60 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksFrecency.swift:41-46 | Sources/VerifyLibraryStore/ChecksFrecency.swift:164-169 |
| 16 | T1 | 59 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:54-59 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:141-146 |
| 17 | T1 | 58 | 10 | 1.0 | Sources/AdaptiveSound/AudioEngineBridge+GaplessRoll.swift:208-215 | Sources/AdaptiveSound/AudioEngineBridge+PureMode.swift:350-359 |
| 18 | T1 | 58 | 7 | 1.0 | Sources/LibraryStore/LibraryStore+Playlists.swift:215-221 | Sources/LibraryStore/LibraryStore+Playlists.swift:233-239 |
| 19 | T1 | 57 | 10 | 1.0 | Sources/AudioDSP/Loudness/LufsMeter.h:268-275 | Sources/AudioDSP/Loudness/LufsMeter.h:286-295 |
| 20 | T1 | 56 | 9 | 1.0 | Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp:39-47 | Sources/AudioDSP/Spatial/SpatialRenderKernel.cpp:82-90 |
| 21 | T1 | 55 | 7 | 1.0 | Sources/LibraryStore/LibraryStore.swift:214-220 | Sources/LibraryStore/LibraryStore.swift:230-236 |
| 22 | T1 | 55 | 10 | 1.0 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:80-89 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:114-121 |
| 23 | T1 | 53 | 15 | 1.0 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:162-176 | Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift:423-435 |
| 24 | T1 | 52 | 12 | 1.0 | Sources/LibraryStore/LibraryStore+BrowseReads.swift:134-141 | Sources/LibraryStore/LibraryStore+BrowseReads.swift:212-223 |
| 25 | T1 | 50 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:140-145 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:265-270 |
| 26 | T1 | 48 | 14 | 1.0 | Sources/AdaptiveSound/UI/Playlist/PlaylistDetailView.swift:297-303 | Sources/AdaptiveSound/UI/Playlist/PlaylistItemRow.swift:111-124 |
| 27 | T1 | 47 | 6 | 1.0 | Sources/AdaptiveSound/UI/Library/AlbumArtworkView.swift:25-30 | Sources/AdaptiveSound/UI/Library/BrowseArt.swift:30-35 |
| 28 | T1 | 47 | 6 | 1.0 | Sources/AudioDSP/PureModeFormat.cpp:122-127 | Sources/AudioDSP/PureModeFormat.cpp:140-145 |
| 29 | T1 | 47 | 7 | 1.0 | Sources/LibraryStore/LibraryStore+DAO.swift:244-250 | Sources/LibraryStore/LibraryStore+MoveMatch.swift:111-117 |
| 30 | T1 | 46 | 11 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:268-278 | Sources/AudioDSP/AudioEngine/SpatialRendererAU.mm:334-344 |
| 31 | T1 | 45 | 9 | 1.0 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:27-34 | Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift:19-27 |
| 32 | T1 | 45 | 8 | 1.0 | Sources/AdaptiveSound/UI/Library/DetailTrackList.swift:138-143 | Sources/AdaptiveSound/UI/Library/SongsListView.swift:232-239 |
| 33 | T1 | 45 | 9 | 1.0 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:352-360 | Sources/AudioDSP/FileDecodeSource.cpp:906-914 |
| 34 | T1 | 44 | 6 | 1.0 | Sources/AudioDSP/GaplessSource.cpp:150-155 | Sources/AudioDSP/GaplessSource.cpp:163-168 |
| 35 | T1 | 43 | 10 | 1.0 | Sources/AdaptiveSound/UI/Library/LibrarySidebar.swift:297-306 | Sources/AdaptiveSound/UI/Playlist/PlaylistDetailView.swift:160-169 |
| 36 | T1 | 43 | 9 | 1.0 | Sources/LibraryScan/FileSignature.swift:63-71 | Sources/VerifyLibraryStore/ScanFixtureBuilder.swift:165-171 |
| 37 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:140-145 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:54-59 |
| 38 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:140-145 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:141-146 |
| 39 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:265-270 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:54-59 |
| 40 | T1 | 43 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksAlbumFixRound.swift:265-270 | Sources/VerifyLibraryStore/ChecksMetadataPass.swift:141-146 |
| 41 | T1 | 43 | 7 | 1.0 | Sources/VerifyLibraryStore/ChecksScanEdge.swift:94-100 | Sources/VerifyLibraryStore/ChecksScanReconcile.swift:280-286 |
| 42 | T1 | 42 | 6 | 1.0 | Sources/AdaptiveSound/AudioEngineBridge+GaplessRoll.swift:35-40 | Sources/AdaptiveSound/AudioEngineBridge+GaplessRoll.swift:73-78 |
| 43 | T1 | 42 | 9 | 1.0 | Sources/AudioDSP/FileDecodeSource.cpp:1380-1387 | Sources/AudioDSP/FileDecodeSource.cpp:1390-1398 |
| 44 | T1 | 42 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:119-124 | Sources/VerifyLibraryStore/ChecksCRUD.swift:187-192 |
| 45 | T1 | 42 | 7 | 1.0 | Sources/VerifyLibraryStore/ChecksCorruption.swift:120-126 | Sources/VerifyLibraryStore/ChecksCorruption.swift:299-305 |
| 46 | T1 | 41 | 8 | 1.0 | Sources/AdaptiveSound/MenuBarView.swift:12-19 | Sources/AdaptiveSound/UI/NowPlaying/HeroBand.swift:27-33 |
| 47 | T1 | 41 | 8 | 1.0 | Sources/AdaptiveSound/MenuBarView.swift:12-19 | Sources/AdaptiveSound/UI/Shell/NowPlayingBar.swift:19-26 |
| 48 | T1 | 41 | 7 | 1.0 | Sources/AdaptiveSound/UI/Playlist/AddToPlaylistMenu.swift:42-48 | Sources/AdaptiveSound/UI/Playlist/AddToPlaylistMenu.swift:132-138 |
| 49 | T1 | 41 | 8 | 1.0 | Sources/AudioDSP/PureModeFormat.cpp:171-178 | Sources/AudioDSP/PureModeFormat.cpp:183-190 |
| 50 | T1 | 40 | 11 | 1.0 | Sources/AdaptiveSound/UI/Library/DetailTrackRow.swift:26-35 | Sources/AdaptiveSound/UI/Library/SongRow.swift:23-33 |
| 51 | T1 | 40 | 7 | 1.0 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:497-503 | Sources/AudioDSP/AudioEngine/AUAudioUnit.mm:519-525 |
| 52 | T1 | 40 | 6 | 1.0 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:704-709 | Sources/AudioDSP/AudioEngine/HALOutputEngine.mm:742-747 |
| 53 | T1 | 40 | 7 | 1.0 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:23-29 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:119-124 |
| 54 | T1 | 40 | 7 | 1.0 | Sources/VerifyLibraryStore/ChecksBrowseReads.swift:23-29 | Sources/VerifyLibraryStore/ChecksCRUD.swift:187-192 |
| 55 | T1 | 40 | 6 | 1.0 | Sources/VerifyLibraryStore/ChecksQueryPlan.swift:25-30 | Sources/VerifyLibraryStore/ChecksSongsSort.swift:436-441 |
