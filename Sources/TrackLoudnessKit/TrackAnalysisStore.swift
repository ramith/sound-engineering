import Foundation

/// The analysis store (R1.1-B W5, lane 3-A; level-and-fold "The store and the scheduler", M5, M6, architect N7;
/// US-R1F-10 item 16): every track's `TrackAnalysis`, kept in a rebuildable derived-data file beside the library —
/// `track-analysis.sqlite3` in the app's data folder, its own GRDB connection — and never in the library database.
///
/// - Records are keyed by the file's full identity (path, size, mtime): an edited or replaced file is a new one.
/// - A record of another analysis version, or one whose payload will not decode, counts as not analysed and is
///   overwritten by the next save.
/// - The scalar record (numbers, histograms, LFE statistics: a few KB) is kept for every analysed track; the
///   compact −ΔL profiles (up to ~600 KB per basis) are capped at `defaultProfileBudgetBytes` in all, the least
///   recently used going first. A track whose profiles went keeps its numbers.
/// - Everything here can be rebuilt by analysing again, so a file that will not open is recreated, never refused.
///
/// Every method is async and runs one read or one write transaction on the store's own queue: call it from any
/// task, never wait on it from the main thread.
public final class TrackAnalysisStore: Sendable {
    /// The store's file name in the app's data folder (`AppDataLocation.directory`).
    public static let fileName = "track-analysis.sqlite3"
    /// The compact profiles' cap (1 GB).
    public static let defaultProfileBudgetBytes = 1 << 30

    /// The store's file.
    public let url: URL

    /// Open the store in `directory` (created when missing), recreating a file that will not open. Throws only
    /// when even a fresh file cannot be made.
    public init(directory: URL, profileBudgetBytes _: Int = defaultProfileBudgetBytes) throws {
        url = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
    }

    /// The current-version records of `identities` that the store holds, by identity — numbers, histograms and LFE
    /// statistics, **without** the profiles (their slots are nil; read them with `profiles(for:bases:)`). An
    /// identity with no usable record is absent. Lane 3-A's store (stub until it lands).
    public func analyses(for _: [TrackIdentity]) async throws -> [TrackIdentity: TrackAnalysis] {
        [:]
    }

    /// The saved compact profiles of `identity` on `bases` (`TrackAnalysis`'s own indices: 0 as decoded, 1 + v the
    /// fold at LFE variant v) that are still kept, by basis; reading them marks them used. Lane 3-A's store (stub
    /// until it lands).
    public func profiles(for _: TrackIdentity, bases _: [Int]) async throws -> [Int: TrackAnalysis.Profile] {
        [:]
    }

    /// Keep `analysis` (replacing any record at its path), then trim the profiles to the cap. Lane 3-A's store
    /// (stub until it lands).
    public func save(_: TrackAnalysis) async throws {}

    /// After "Use this drive" moved a music folder from `oldRoot` to `newRoot` (both directory paths): every record
    /// under `oldRoot` whose file is at the same place under `newRoot` with the same size and modification time
    /// moves there, so the drive's songs are not analysed again. Returns how many moved. Lane 3-A's store (stub
    /// until it lands).
    @discardableResult
    public func rekey(root _: String, to _: String) async throws -> Int {
        0
    }
}
