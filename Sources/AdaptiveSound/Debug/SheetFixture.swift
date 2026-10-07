#if DEBUG
    import LibraryStore
    import SwiftUI

    // MARK: - Picture-sheet fixture

    /// The renderer's world: the app's real view models over FIXTURE data, wired like
    /// `AdaptiveSound.init()` minus everything that reaches outside the process —
    /// - no library store: `LibraryModel(storeless:)` never builds one, so `store` stays `nil` and
    ///   every store-backed loader returns early;
    /// - no audio engine or device: `SheetEngine`, and `initializeEngine()` is never called;
    /// - no `UserDefaults.standard`: the EQ model and every `@AppStorage` use the caller's suite;
    /// - no system Now Playing: `onNowPlayingRefresh` stays unwired and `registerCommands()` is never
    ///   called, so Control Center and the media keys are untouched.
    ///
    /// One fixture per `SheetVariant`: `empty` seeds no songs and no queue; the ring variants seed
    /// the standard world and draw keyboard focus in their lists (`root(for:)`).
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

        init(defaults: UserDefaults, variant: SheetVariant) {
            self.defaults = defaults
            self.variant = variant
            let monitor = Self.monitorSpectra()
            audio = AudioViewModel(engine: SheetEngine(before: monitor.before, after: monitor.after))
            eq = EQViewModel(audioViewModel: audio, defaults: defaults)
            browse = LibraryBrowseModel(audio: audio, library: library)
            playlists = PlaylistsModel(library: library, audio: audio)
            let songs = variant == .empty ? [] : Self.songs()
            selectedSongs = Set(songs.filter { $0.title == Self.selectedTitle }.map(\.id))
            browse.seedRenderFixture(songs: songs)
            seedDevices()
            seedPlayback(songs)
            eq.bandGains = Self.eqCurve()
            eq.selectedPreset = nil // a hand-drawn curve reads "Custom"
            nowPlaying.audio = audio
            nowPlaying.seedRenderFixture(ResolvedTrackMeta(artist: "A. R. Rahman", album: "Roja", artworkKey: nil))
        }

        /// The whole window content, as `AdaptiveSound.body` builds it, in `appearance`'s environment.
        /// Reduce Motion is always on: sheets are still frames. The ring variants draw keyboard focus
        /// (as after an arrow press) in the lists they focus.
        func root(for appearance: SheetAppearance) -> some View {
            ContentView()
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
                .defaultAppStorage(defaults)
        }

        /// The built-in speakers selected, a USB DAC beside them — every variant has an output device.
        private func seedDevices() {
            let speakers = AudioDeviceModel(id: 1, name: "MacBook Pro Speakers", sampleRate: 48000,
                                            bufferFrameSize: 512, type: .builtin)
            let dac = AudioDeviceModel(id: 2, name: "Modi+ USB DAC", sampleRate: 96000,
                                       bufferFrameSize: 512, type: .usb)
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
