// StoreQuarantine — move a corrupt/too-new store aside (with its WAL sidecars).
//
// S8.1a (design §5, must-fix O1). When the store is corrupt, fails
// `integrity_check`, or is newer than the app (downgrade guard), the file is
// QUARANTINED rather than deleted — the library is a rebuildable cache (§2a), but
// a corrupt file may still hold user-recoverable rows, so we keep it for
// post-mortem and rebuild fresh.
//
// The quarantine renames THREE files atomically-enough for our purposes: the main
// `library.sqlite3` AND its `-wal` / `-shm` sidecars (a live WAL left orphaned
// next to a fresh DB would be silently replayed into it — the exact O1 hazard).
// Each existing file is moved to `library.corrupt-<stamp>.<ext>`.
//
// The `<stamp>` is passed IN as a parameter so the naming is deterministic and
// testable; app code passes a `Date()`/UUID-derived stamp, the harness passes a
// fixed one and asserts the resulting filenames.

import Foundation

/// Quarantines a store file (plus its WAL/SHM sidecars) by renaming them aside.
public enum StoreQuarantine {
    /// The `-wal` / `-shm` sidecar suffixes SQLite appends to a WAL-mode database.
    /// These sit next to the main file and MUST travel with it on quarantine.
    public static let sidecarSuffixes = ["-wal", "-shm"]

    /// Build the quarantine destination URL for a source file and a stamp.
    /// `library.sqlite3` + stamp "20260702-120000" → `library.corrupt-20260702-120000.sqlite3`.
    /// A sidecar `library.sqlite3-wal` → `library.corrupt-20260702-120000.sqlite3-wal`.
    public static func quarantineURL(for source: URL, stamp: String) -> URL {
        let directory = source.deletingLastPathComponent()
        let lastComponent = source.lastPathComponent

        // Split the primary name (before any `-wal`/`-shm`) from its sidecar suffix
        // so the stamp lands on the base name, not after the suffix.
        var primaryName = lastComponent
        var sidecarSuffix = ""
        for suffix in sidecarSuffixes where lastComponent.hasSuffix(suffix) {
            primaryName = String(lastComponent.dropLast(suffix.count))
            sidecarSuffix = suffix
            break
        }

        let dotExt = (primaryName as NSString).pathExtension
        let stem = (primaryName as NSString).deletingPathExtension
        let extPart = dotExt.isEmpty ? "" : ".\(dotExt)"
        let quarantinedName = "\(stem).corrupt-\(stamp)\(extPart)\(sidecarSuffix)"
        return directory.appendingPathComponent(quarantinedName)
    }

    /// Quarantine the store at `storeURL` and any present `-wal`/`-shm` sidecars,
    /// renaming each to its `.corrupt-<stamp>` name. Returns the list of
    /// destination URLs actually moved (main file + whichever sidecars existed).
    ///
    /// Missing files are simply skipped (a fresh-but-corrupt-header DB may have no
    /// sidecars yet). Throws if a rename fails for a file that does exist.
    @discardableResult
    public static func quarantine(storeURL: URL, stamp: String) throws -> [URL] {
        let fileManager = FileManager.default
        var moved: [URL] = []

        // Main file first, then sidecars.
        let candidates = [storeURL] + sidecarSuffixes.map { suffix in
            let base = storeURL.deletingLastPathComponent()
            return base.appendingPathComponent(storeURL.lastPathComponent + suffix)
        }

        for source in candidates where fileManager.fileExists(atPath: source.path) {
            let destination = quarantineURL(for: source, stamp: stamp)
            // If a same-stamp destination somehow exists, remove it first so the
            // move cannot fail on a stale collision.
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
            moved.append(destination)
        }
        return moved
    }

    /// A default stamp for app code: `yyyyMMdd-HHmmss` plus a short UUID fragment
    /// so two quarantines in the same second cannot collide. The harness passes an
    /// explicit stamp instead of using this.
    public static func defaultStamp(date: Date = Date(), uuid: UUID = UUID()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let shortID = uuid.uuidString.prefix(8)
        return "\(formatter.string(from: date))-\(shortID)"
    }
}
