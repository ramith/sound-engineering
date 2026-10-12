#if DEBUG
    import Foundation

    // MARK: - Picture-sheet fixture data: Settings (S10.8 F2)

    extension SheetFixture {
        /// The folder the remove-folder world's dialog asks about, as the rail's row shows it.
        static let removedFolder = "~/Music/Lossless"

        /// Puts the Settings tab in `variant`'s state; every other world keeps the standard one (the
        /// speakers in use, Pure off, playback kept on the device). Set for every world, so one world's
        /// never carries into the next.
        static func seedSettings(_ audio: AudioViewModel, for variant: SheetVariant) {
            audio.pureModeEnabled = variant == .settingsStates || variant == .settingsFallback
            audio.pinPlaybackToSelectedDevice = variant != .settingsStates
            audio.signalPath.fellBackToEnhanced = variant == .settingsFallback
            if variant == .settingsNoDevices { // nothing to play on: no rate either
                audio.availableDevices = []
                audio.selectedDevice = nil
                audio.signalPath.achievedSampleRate = 0
            }
        }
    }
#endif
