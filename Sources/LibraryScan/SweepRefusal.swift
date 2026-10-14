// SweepRefusal — why a walk did not sweep: a sweep deletes only songs POSITIVELY known to be gone.
//
// A walk ends by sweeping every row of its root that it did not see, and the delete cascades to the
// song's playlist entries and play history. So "not seen" must mean "gone", and `LibraryScanner.scan`
// throws this, instead of sweeping, when the walk is not that evidence. The rows (and their user data)
// are kept; a later walk that is the evidence reaps genuine deletions. The reasons:
//   • the root VANISHED — it is not there (an unplugged drive, a deleted folder), or it went away or
//     was replaced while it was walked;
//   • a DIFFERENT VOLUME is at its path — another drive mounted under the same name (two "T7" SSDs, two
//     "Untitled" sticks), before or during the walk (R1, council P5A-02);
//   • the folder is UNRECOGNIZED — the root is not bound to a drive yet (added before v8, or on a volume
//     with no UUID), and none of its songs is where the library has it: the folder at its path may be
//     another drive's, or a stale one (R1, council P5A-02 break-it);
//   • the walk was INCOMPLETE — it could not read part of the folder: a subfolder it may not open, an
//     audio file it could not read, a drive that failed under it (R1, council P5A-01);
//   • the walk was EMPTY — it saw no file at all (S8.4 slice 3's founder-approved "never wipe on an
//     empty walk": an unmounted or zombie-mounted volume reads exactly like "every file deleted").
// A root that vanished, is on a different volume or is unrecognized when the walk would start is not
// walked at all (nor bound or re-stamped). A root that vanished or changed drive DURING the walk stops it
// at the next batch, and always refuses. An incomplete or empty walk refuses only when the sweep would
// delete something — with nothing unseen there is nothing to refuse, and the walk ends as usual; the
// rows it found are committed either way. Both walk callers catch this silently, like
// `CancellationError` (a background non-event): logged, and the root is marked paused.

import Foundation
import LibraryStore

/// Thrown by `LibraryScanner.scan` when a walk is not evidence of which of its root's songs are gone.
public struct SweepRefusal: Error, Sendable, Equatable {
    /// Why the walk is not that evidence (see the file header).
    public enum Reason: Sendable, Equatable {
        /// The root is not reachable at its path, or went away or was replaced during the walk.
        case rootVanished
        /// The root's path is on a volume other than the one the root is bound to.
        case differentVolume
        /// The root is bound to no drive, and none of its songs is where the library has it.
        case unrecognizedFolder
        /// The walk could not read part of the folder.
        case incompleteWalk
        /// The walk saw no file at all.
        case emptyWalk
    }

    /// The `folders` rowid whose sweep was refused.
    public let folderID: Int64
    /// Why.
    public let reason: Reason
    /// How many rows the store held for that root when the walk began — all kept.
    public let storedRowCount: Int

    public init(folderID: Int64, reason: Reason, storedRowCount: Int) {
        self.folderID = folderID
        self.reason = reason
        self.storedRowCount = storedRowCount
    }
}

/// What is at a root's path right now: whether it is reachable, and which directory on which drive.
public enum RootReachabilityProbe {
    /// A root is reachable iff its path resolves to a readable directory RIGHT NOW. An unmounted
    /// volume and a deleted folder both read as unreachable, and are handled alike: the root is not
    /// walked. Reachable is not enough to walk it, though — the directory may be on another drive
    /// than the root's (`identity(of:)`).
    public static func isReachable(_ root: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// The identity of what is at `root`'s path now — nil when it is not reachable. Its `(dev,
    /// inode)` is the `lstat` stamp `addRoot` dedups on; its volume UUID is that of the directory a
    /// symlinked root resolves to (where the songs are), read afresh — a URL caches resource values,
    /// and a walk compares two reads. The default of `LibraryScanner`'s seam: a walk reads it before it
    /// starts and again before it sweeps.
    ///
    /// The drive reads as `RootIdentity.startupDisk` on the STARTUP volume, not as its UUID: nothing can
    /// be mounted in the startup volume's place, but its UUID (the Data volume's, which every path on it
    /// reports) changes with the Mac — Migration Assistant, an erase-and-restore — while the library
    /// comes along with it, and binding that UUID would freeze every such folder on the new Mac. A
    /// volume that reports no UUID reads as nil (the root stays unbound).
    public static func identity(of root: URL) -> RootIdentity? {
        guard isReachable(root) else { return nil }
        let signature = FileSignature.deviceInode(of: root)
        var resolved = root.resolvingSymlinksInPath()
        resolved.removeAllCachedResourceValues()
        let values = try? resolved.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsRootFileSystemKey])
        let volume = values?.volumeIsRootFileSystem == true ? RootIdentity.startupDisk : values?.volumeUUIDString
        return RootIdentity(dev: signature.dev, inode: signature.inode, volume: volume)
    }
}
