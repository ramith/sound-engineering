// SettingsStore — the ONE place the listener's settings persist (R1.1-A, council C-12: the keys used to
// live in four places, and the listening settings in none). Over the launch's defaults
// (`AppDataLocation`), injected, so a test gives it a suite of its own.
//
// It keeps the settings the way the EQ keeps its slots (`eqStateV2`): one versioned JSON value, written
// whole, so its fields can never disagree on disk; a value this build can't read at all is copied aside
// before anything overwrites it (`listeningSettingsV1.unreadable`); an earlier build's keys are read once,
// when there is no value yet, and left in place so a downgrade still finds them.
//
// WRITES ARE CHEAP AND COALESCED. `save` records the newest settings and writes them at the end of the
// main-actor turn — once, however many settings that turn changed, and not at all when they equal what
// is stored. No time debounce: a write that waited for a drag to settle would let a crash in between
// restore a louder Master Gain than the one left (the slider's 1 dB steps already bound a whole sweep to
// 61 writes). `flush` writes now (at quit). Main actor only: never the audio thread, no audio calls.

import Foundation

@MainActor
public final class SettingsStore {
    private enum Key {
        /// The listener's settings (`ListeningSettings`), version 1.
        static let settings = "listeningSettingsV1"
        /// The raw bytes of a `settings` value this build couldn't read, kept before it is overwritten.
        static let unreadable = "listeningSettingsV1.unreadable"
        /// R1 kept shuffle and repeat with the queue cursor (written at a clean quit, read only when a
        /// queue was restored). Read when no `settings` value exists yet; never written again.
        static let r1Shuffle = "queue.cursor.shuffle"
        static let r1RepeatMode = "queue.cursor.repeatMode"
    }

    private let defaults: UserDefaults
    /// What the defaults hold, as `load` read it or the last write wrote it: saving the same writes
    /// nothing.
    private var stored: ListeningSettings?
    /// The newest settings not yet written; a write is on its way while it is set.
    private var pending: ListeningSettings?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The settings the listener left: the stored value (a bad field reads as its faithful default,
    /// Master Gain never louder than it was left), else on the first launch after R1 the faithful
    /// default with R1's shuffle and repeat, else — a new install — the faithful default. Reads only:
    /// what it returns is written when it next changes.
    public func load() -> ListeningSettings {
        let settings: ListeningSettings
        if let data = defaults.data(forKey: Key.settings) {
            if let decoded = try? Self.decoder.decode(ListeningSettings.self, from: data) {
                settings = decoded
            } else {
                defaults.set(data, forKey: Key.unreadable)
                settings = .unreadable
            }
        } else {
            settings = ListeningSettings(
                shuffle: defaults.bool(forKey: Key.r1Shuffle),
                repeatMode: ListeningSettings.validRepeatMode(defaults.object(forKey: Key.r1RepeatMode) as? Int)
            )
        }
        stored = settings
        return settings
    }

    /// Keep `settings`: written at the end of this main-actor turn, with whatever else the turn saves.
    public func save(_ settings: ListeningSettings) {
        let writeOnItsWay = pending != nil
        pending = settings
        guard !writeOnItsWay else { return }
        Task { self.flush() }
    }

    /// Write the newest saved settings now, if they differ from what is stored.
    public func flush() {
        guard let settings = pending else { return }
        pending = nil
        guard settings != stored, let data = try? Self.encoder.encode(settings) else { return }
        defaults.set(data, forKey: Key.settings)
        stored = settings
    }

    // MARK: - Coders

    /// The non-finite levels as strings, since JSON has no number for them: Silent is −∞.
    private static let nonFinite = (positive: "+Infinity", negative: "-Infinity", nan: "NaN")

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: nonFinite.positive, negativeInfinity: nonFinite.negative, nan: nonFinite.nan
        )
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: nonFinite.positive, negativeInfinity: nonFinite.negative, nan: nonFinite.nan
        )
        return decoder
    }
}
