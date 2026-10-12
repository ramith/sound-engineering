#if DEBUG
    import CoreAudio
    import LibraryStore
    import SwiftUI

    // MARK: - Picture-sheet fixture

    /// The renderer's world: the app's real view models over FIXTURE data, wired like
    /// `AdaptiveSound.init()` minus everything that reaches outside the process —
    /// - no library store: `LibraryModel(storeless:)` never builds one, so `store` stays `nil` and
    ///   every store-backed loader returns early;
    /// - no audio engine or device: `SheetEngine`, and `initializeEngine()` is never called;
    /// - none of the app's settings: the audio and EQ models and every `@AppStorage` use the
    ///   caller's suite;
    /// - no system Now Playing: `onNowPlayingRefresh` stays unwired and `registerCommands()` is never
    ///   called, so Control Center and the media keys are untouched.
    ///
    /// One fixture per `SheetVariant`: `empty` seeds no songs and no queue; the ring variants seed
    /// the standard world and draw keyboard focus in their lists (`root(for:)`); the grid variants
    /// add the browse grids' albums, artists, genres and covers (`+Browse`) and open their category;
    /// the playlist worlds open a playlist (`+Playlist`); the EQ worlds put the EQ screen in one state
    /// each (`+EQ`). Every world's engine reads "ready"
    /// (nothing is ever started) except `eqEngine`'s.
    @MainActor
    final class SheetFixture {
        let audio: AudioViewModel
        let variant: SheetVariant
        private let library = LibraryModel(storeless: ())
        private let eq: EQViewModel
        private let browse: LibraryBrowseModel
        private let playlists: PlaylistsModel
        private let nowPlaying = NowPlayingController()
        private let keyboardFocus = KeyboardTransportFocus()
        private let defaults: UserDefaults
        private let selectedSongs: Set<LibraryTrackDisplay.ID>
        /// The browse grids' and pages' covers (`SheetArtwork`) — only in a grid or page variant's world.
        private let artwork: [String: NSImage]
        /// The album, artist or genre page a page variant's world opens (`+Detail`).
        private let detailPage: LibraryDetailContent?

        init(defaults: UserDefaults, variant: SheetVariant) {
            self.defaults = defaults
            self.variant = variant
            let monitor = Self.monitorSpectra()
            audio = AudioViewModel(defaults: defaults,
                                   engine: SheetEngine(before: monitor.before, after: monitor.after))
            eq = EQViewModel(audioViewModel: audio, defaults: defaults)
            audio.onOutputIdentityChanged = { [weak eq] key in eq?.outputDidChange(to: key) } // Edge 5
            browse = LibraryBrowseModel(audio: audio, library: library)
            playlists = PlaylistsModel(library: library, audio: audio)
            let songs = variant == .empty ? [] : Self.songs()
            detailPage = Self.detailPage(for: variant)
            selectedSongs = variant == .pageStates ? Self.pageSelection
                : Set(songs.filter { $0.title == Self.selectedTitle }.map(\.id))
            let showsGrid = variant.category != .songs
            browse.seedRenderFixture(songs: songs, albums: showsGrid ? Self.albums() : [])
            if showsGrid {
                browse.artists = Self.artists()
                browse.artistsState = .loaded
                browse.genres = Self.genres()
                browse.genresState = .loaded
                browse.genreCoverKeys = Self.genreCovers()
                browse.selectedCategory = variant.category
            }
            // A page opens over its category's grid, as a click on its tile opens it.
            browse.path = variant.page.map { [$0.route] } ?? []
            artwork = showsGrid ? SheetArtwork.images(for: Self.browseArtworkKeys() + Self.pageArtworkKeys) : [:]
            if variant.opensPlaylist {
                Self.seedPlaylist(playlists, browse: browse, songs: songs)
            }
            library.isReconciling = variant == .playlistRemoveMissingScan // a scan under way: Remove is off
            seedDevices()
            seedPlayback(songs)
            Self.seedSettings(audio, for: variant)
            Self.seedEQ(eq, audio: audio, defaults: defaults, for: variant) // "Warm · Edited", then the world's
            nowPlaying.audio = audio
            nowPlaying.seedRenderFixture(ResolvedTrackMeta(artist: "A. R. Rahman", album: "Roja", artworkKey: nil))
        }

        /// The whole window content, as `AdaptiveSound.body` builds it, in `appearance`'s environment.
        /// Reduce Motion is always on: sheets are still frames. The ring variants draw keyboard focus
        /// (as after an arrow press) in the lists they focus. Each sheet's browse grid starts at the
        /// top: tearing down the previous sheet's window remembered its place (D6), which a sheet of
        /// another size would restore at a slightly different height.
        func root(for appearance: SheetAppearance) -> some View {
            browse.browsePlace = nil
            return ContentView()
                .overlay { dialogStandIn }
                .environment(audio)
                .environment(eq)
                .environment(library)
                .environment(browse)
                .environment(playlists)
                .environment(nowPlaying)
                .environment(keyboardFocus)
                .environment(\._colorSchemeContrast, appearance.increasedContrast ? .increased : .standard)
                .environment(\._accessibilityReduceTransparency, appearance.reduceTransparency)
                .environment(\._accessibilityReduceMotion, true)
                .environment(\.sheetSongSelection, selectedSongs)
                .environment(\.showsKeyboardFocus, !variant.focusedLists.isEmpty)
                .environment(\.sheetFocusedLists, variant.focusedLists)
                .environment(\.sheetArtwork, artwork)
                .environment(\.sheetGridStates, variant == .gridStates ? Self.gridStates : SheetGridStates())
                .environment(\.sheetEQGraph, Self.eqGraphSeed(for: variant))
                .environment(\.sheetDetailPage, detailPage)
                .defaultAppStorage(defaults)
        }

        /// The dialog world's sheet, drawn in the window (`SheetDialogStandIn`): the EQ's Save, Rename or
        /// Delete; a playlist's Delete, Remove Missing or failure notice; a music folder's Remove.
        @ViewBuilder private var dialogStandIn: some View {
            switch variant {
            case .eqSave:
                SheetDialogStandIn { SaveCustomPresetView(sheet: .save(eq.saveSource()), eqViewModel: eq) }
            case .eqRename:
                SheetDialogStandIn { SaveCustomPresetView(sheet: .rename(Self.renamedPreset), eqViewModel: eq) }
            case .eqDelete:
                SheetDialogStandIn { EQDeletePresetDialog(name: Self.renamedPreset, delete: {}, cancel: {}) }
            case .playlistDelete:
                SheetDialogStandIn { PlaylistDeleteDialog(name: Self.openPlaylist.name, delete: {}, cancel: {}) }
            case .playlistRemoveMissing, .playlistRemoveMissingScan:
                SheetDialogStandIn {
                    PlaylistRemoveMissingDialog(count: playlists.missingEntryCount,
                                                isScanning: playlists.isLibraryPopulating, remove: {}, cancel: {})
                }
            case .playlistFailure:
                SheetDialogStandIn { PlaylistFailureNotice(message: Self.playlistFailure, dismiss: {}) }
            case .folderRemove:
                SheetDialogStandIn { MusicFolderRemoveDialog(path: Self.removedFolder, remove: {}, cancel: {}) }
            default:
                EmptyView()
            }
        }

        /// The built-in speakers selected, a USB DAC beside them — every variant has an output device.
        private func seedDevices() {
            let speakers = AudioDeviceModel(id: 1, name: "MacBook Pro Speakers", sampleRate: 48000,
                                            bufferFrameSize: 512, uid: "BuiltInSpeakerDevice", modelUID: nil,
                                            transportType: kAudioDeviceTransportTypeBuiltIn, type: .builtin)
            let dac = AudioDeviceModel(id: 2, name: "Modi+ USB DAC", sampleRate: 96000,
                                       bufferFrameSize: 512, uid: "AppleUSBAudioEngine:Schiit:Modi+:1",
                                       modelUID: "Modi+:30BE:0001",
                                       transportType: kAudioDeviceTransportTypeUSB, type: .usb)
            audio.availableDevices = [speakers, dac]
            audio.selectedDevice = speakers
        }

        /// A playing queue: track 3 at 1:21, Enhanced at 20%, measured loudness and a live-looking
        /// analyzer frame. Nothing at all when the library is empty (`empty`).
        private func seedPlayback(_ songs: [LibraryTrackDisplay]) {
            guard !songs.isEmpty else { return }
            let byTitle = Dictionary(uniqueKeysWithValues: songs.map { ($0.title, $0) })
            let queue = Self.queueTitles.compactMap { byTitle[$0] }
            audio.queue = queue.map { QueueItem(file: AudioFile($0)) }
            audio.selectedTrackIndex = Self.queueTitles.firstIndex(of: Self.playingTitle)
            audio.isPlaying = true
            audio.duration = byTitle[Self.playingTitle]?.durationSeconds ?? 0
            audio.playbackPosition = 81
            audio.sampleRate = 48000
            var path = SignalPathInfo()
            path.path = .enhanced
            path.achievedSampleRate = 48000
            path.intensityLinear = audio.intensity
            audio.signalPath = path
            audio.loudness = LoudnessSnapshot(integratedLufs: -15.9, shortTermLufs: -14.2, truePeakDb: -3.2)
            audio.spectrumBars = Self.spectrum(count: SpectrumConstants.displayBarCount, phase: 0)
            audio.peakCaps = audio.spectrumBars.map { min($0 + 0.08, 1) }
        }
    }
#endif
