import EQEditKit
import Foundation
import SettingsKit

// MARK: - AudioViewModel: the listener's settings, kept across launches (R1.1-A, FD-2)

/// Pure, Master Gain, crossfeed and its strength, shuffle, repeat, "Keep playback on this device", the
/// output device the user chose and "Use FFmpeg for other formats" come back after a relaunch as the
/// listener left them (council C-102,
/// C-12, DEV-1) — Master Gain never louder — from ONE store (`SettingsStore`, over this view model's
/// `defaults`). Restored in `init`, so everything that reads them, the engine included, starts from them;
/// each setting's `didSet` saves them again, and the store writes once per main-actor turn. Intensity is
/// not among them: hidden and held at 0 until S17 (`offersIntensity`).
extension AudioViewModel {
    /// The settings as they stand.
    var listeningSettings: ListeningSettings {
        ListeningSettings(
            pureMode: pureModeEnabled,
            masterGainDecibels: masterGain,
            crossfeed: crossfeedEnabled,
            crossfeedStrength: crossfeedStrength,
            shuffle: shuffleEnabled,
            repeatMode: repeatMode,
            keepPlaybackOnDevice: pinPlaybackToSelectedDevice,
            chosenOutputUID: chosenOutputUID,
            useFFmpeg: useFFmpeg
        )
    }

    /// Take the settings the listener left. In `init`, so each `didSet` hands its value to the engine
    /// as a change would (the engine publishes them again at engine-ready). The switch comes before
    /// the chosen device: its `didSet` reads the choice back from the engine, which has none yet. Each
    /// `didSet` saves as it goes; the last save is the whole restored set — what was read — so the
    /// store writes nothing.
    func restoreListeningSettings() {
        let settings = settingsStore.load()
        pureModeEnabled = settings.pureMode
        masterGain = settings.masterGainDecibels
        crossfeedEnabled = settings.crossfeed
        crossfeedStrength = settings.crossfeedStrength
        shuffleEnabled = settings.shuffle
        repeatMode = settings.repeatMode
        pinPlaybackToSelectedDevice = settings.keepPlaybackOnDevice
        chosenOutputUID = settings.chosenOutputUID
        useFFmpeg = settings.useFFmpeg // sets the process's FFmpeg switch, before any library work
        rememberListeningSettings()
        logUX("settings restored: pure=\(settings.pureMode) gain=\(MasterGainLaw.text(settings.masterGainDecibels)) "
            + "crossfeed=\(settings.crossfeed) [\(settings.crossfeedStrength.displayName)] "
            + "shuffle=\(settings.shuffle) repeat=\(settings.repeatMode) "
            + "keepOnDevice=\(settings.keepPlaybackOnDevice) chosen=\(settings.chosenOutputUID ?? "none") "
            + "ffmpeg=\(settings.useFFmpeg)")
    }

    /// Keep the settings as they stand (written at the end of this main-actor turn).
    func rememberListeningSettings() {
        settingsStore.save(listeningSettings)
    }

    /// Keep the device the user chose, read back from the engine after a pick or the switch turned on —
    /// the engine's choice, so the kept one can never differ from it.
    func rememberOutputChoice() {
        chosenOutputUID = engine.chosenOutputUID()
        rememberListeningSettings()
    }
}
