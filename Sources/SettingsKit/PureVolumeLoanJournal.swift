// PureVolumeLoanJournal — the device-volume loans Pure has out, kept so a crash gives them back (R1.1-A
// close-out break-it, H-2).
//
// On Pure, Master Gain turns the output device's own volume down (`MasterGainOnPure`, EQEditKit); each
// device so lowered is a loan to give back. The loans used to be kept with the listener's settings, from
// the 20 Hz transport tick — which sleeps while paused — so a crash right after Pure lowered a device, or
// after a change made while paused, left it turned down for good. The rule now WRITES AHEAD: the engine
// keeps the loans here synchronously, from its device-volume queue, before each change it makes to a
// device (with the level it is about to set) and after every change to the record. So this is a store of
// its own, not a `ListeningSettings` field: `SettingsStore` belongs to the main actor and writes at the end
// of a turn, and the engine must not wait on the main thread.
//
// One JSON array under its own key (`pureVolumeLoansV1`) in the launch's defaults (`AppDataLocation`,
// injected). UserDefaults is thread-safe; the journal's own lock only orders its writes and skips one equal
// to the last. Read one by one: an entry that can't be read, or a damaged one (`PureVolumeLoan.isSound`), is
// dropped on its own — every other is a device still turned down. Nothing out: no key.

import EQEditKit
import Foundation

public final class PureVolumeLoanJournal: @unchecked Sendable {
    private static let key = "pureVolumeLoansV1"

    // UserDefaults is documented thread-safe; `lock` guards `written` and orders the writes.
    private let defaults: UserDefaults
    private let lock = NSLock()
    private var written: [PureVolumeLoan]?

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The loans kept: each that reads and is sound, in order.
    public func loans() -> [PureVolumeLoan] {
        guard let data = defaults.data(forKey: Self.key),
              let stored = try? Self.decoder.decode([Lenient<PureVolumeLoan>].self, from: data) else { return [] }
        return stored.compactMap(\.value).filter(\.isSound)
    }

    /// Keep `loans`, now — any thread. Equal to what was last kept: nothing written.
    public func keep(_ loans: [PureVolumeLoan]) {
        lock.withLock {
            guard loans != written else { return }
            if loans.isEmpty {
                defaults.removeObject(forKey: Self.key)
            } else if let data = try? Self.encoder.encode(loans) {
                defaults.set(data, forKey: Self.key)
            } else {
                return
            }
            written = loans
        }
    }

    /// One element of the stored array, read on its own: a bad one is nil, and the array still reads.
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) {
            value = try? Value(from: decoder)
        }
    }

    // MARK: - Coders (as `SettingsStore`'s: a non-finite level is a string, read back as itself)

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return decoder
    }
}
