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
            // Pure is asked for wherever it plays or was declined: a Pure world with the switch off would be one
            // whose Leave Pure was already pressed.
            audio.pureModeEnabled = [.settingsStates, .settingsFallback, .settingsPure, .eqPure, .soundFold, .soundPure,
                                     .soundFoldBluetooth, .soundBluetoothCrossfeed].contains(variant)
            audio.pinPlaybackToSelectedDevice = variant != .settingsStates
            audio.signalPath.pureReason = variant == .settingsFallback ? .rateUnsupported : nil
            switch variant {
            case .settingsNoDevices: // nothing to play on: no rate either
                audio.availableDevices = []
                audio.selectedDevice = nil
                audio.signalPath.achievedSampleRate = 0
            case .settingsPure: // bit-perfect on the DAC: the file's own rate, integer PCM, FFmpeg decoding
                audio.selectedDevice = audio.availableDevices.first { $0.type == .usb }
                audio.signalPath.path = .pure
                audio.signalPath.playedPath = .pure // the path that plays, which the DSP rows follow
                audio.signalPath.decision = .fullBitPerfect
                audio.signalPath.achievedSampleRate = 96000
                audio.signalPath.bitDepth = 24
                audio.signalPath.decoder = .ffmpeg
            default:
                break
            }
        }
    }
#endif
