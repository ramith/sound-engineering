#if DEBUG
    import CoreAudio
    import LevelingKit

    // MARK: - Picture-sheet fixture data: the sound UI (R1.1-B W5, lane 3-B)

    extension SheetFixture {
        /// Puts `variant`'s sound state on the playing world: every world levels Auto, the song playing 4.2 dB down
        /// from its analysis (the Settings row's line); the fold world plays a 5.1 file folded on its first,
        /// unmeasured play, crossfeed chosen on the headphones, Pure declined for the channels; the Pure world plays
        /// bit-perfect on the DAC (headphones) with crossfeed chosen. (The toast world raises "Volume restored" once
        /// its window is up — `raiseSheetToast` — since a toast raised before it is stale by the host's rule.)
        static func seedSound(_ audio: AudioViewModel, for variant: SheetVariant) {
            guard let index = audio.selectedTrackIndex, index < audio.queue.count else { return }
            audio.leveling = .auto
            let measured = variant != .soundFold && variant != .soundFoldBluetooth
            let decision = TrackLevelingDecision(
                mode: .leveled, source: measured ? .analysis : .unknownCut, continuousWithPrevious: false,
                unfolded: .init(loudness: measured ? -13.8 : nil, truePeak: measured ? -0.6 : nil), folded: nil,
                roles: []
            )
            audio.levelingState.play(.init(url: audio.queue[index].file.absoluteURL, decision: decision, atSeam: false,
                                           previous: nil))
            audio.signalPath.leveling = measured
                ? LevelingReadout(mode: .leveled, gainDb: -4.2, foldMeasured: true, sourceLayout: "2.0")
                : LevelingReadout(mode: .unknownCut, gainDb: -6.3, foldMeasured: false, sourceLayout: "5.1")
            switch variant {
            case .soundFold, .soundFoldBluetooth:
                audio.selectedDevice = variant == .soundFold ? audio.availableDevices.first { $0.isHeadphones }
                    : bluetoothHeadphones(audio)
                audio.crossfeedEnabled = true
                audio.signalPath.crossfeedStrength = audio.crossfeedStrength
                audio.signalPath.crossfeedEngaged = false
                audio.signalPath.pureReason = variant == .soundFold ? .channelCountMismatch : .bluetooth
                audio.signalPath.fold = FoldState(sourceChannels: 6, outputChannels: 2, fromPlan: true, trimDb: -8.94,
                                                  lfeGain: 0, backstopPeakGrDb: 0)
            case .soundBluetoothCrossfeed:
                audio.selectedDevice = bluetoothHeadphones(audio)
                audio.crossfeedEnabled = true
                audio.signalPath.crossfeedStrength = audio.crossfeedStrength
                audio.signalPath.crossfeedEngaged = true
                audio.signalPath.pureReason = .bluetooth
            case .soundPure:
                audio.selectedDevice = audio.availableDevices.first { $0.isHeadphones }
                audio.crossfeedEnabled = true
                audio.signalPath.path = .pure
                audio.signalPath.playedPath = .pure // the path that plays, which the DSP rows follow
                audio.signalPath.decision = .fullBitPerfect
                audio.signalPath.achievedSampleRate = 96000
                audio.signalPath.bitDepth = 24
                audio.signalPath.decoder = .apple
                audio.signalPath.leveling = nil
            default:
                break
            }
        }

        /// The XM4 — Bluetooth headphones, where Pure declines — added to the devices and returned, for the badge
        /// row's crowded worlds.
        private static func bluetoothHeadphones(_ audio: AudioViewModel) -> AudioDeviceModel {
            let headphones = AudioDeviceModel(id: 3, name: "WH-1000XM4", sampleRate: 48000, bufferFrameSize: 512,
                                              uid: "AC-80-0A-00-00-01:output", modelUID: nil,
                                              transportType: kAudioDeviceTransportTypeBluetooth, type: .wireless,
                                              isHeadphones: true)
            audio.availableDevices.append(headphones)
            return headphones
        }

        /// The toast world's toast, raised from the window's first task: the host is up, so it shows.
        func raiseSheetToast() {
            if variant == .volumeRestored {
                audio.pureVolumeRestored()
            }
        }
    }
#endif
