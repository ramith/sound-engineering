import LibraryScan
import LibraryStore

// MusicFolderStatus — what a Music Folders row says under its path (R1.1-A, KI-LIB-02; founder
// 2026-10-15).
//
// One caption line, in the slot "Scanning…" has always used. A folder being scanned says so. A PAUSED
// folder — its last walk was refused (`SweepRefusal`), so its songs are kept until a walk is evidence
// again — says why, in a few words, and wears the paused look (a folder with a question mark, a
// tooltip). Any other folder says nothing. The words for each refusal reason live here, once, so the
// row and its tests read the same ones.

/// The status line of one Music Folders row.
public enum MusicFolderStatus: Equatable, Sendable {
    /// "Use This Drive…" is looking for the folder's songs on the drive chosen (R1.1-B, LIB-VOL-1): the row
    /// waits — a 20,000-song folder on a USB disk takes seconds — and offers nothing meanwhile.
    case checkingDrive
    /// A walk of the folder is running now (an add's scan).
    case scanning
    /// The folder is paused: its last walk was refused, for this reason.
    case paused(SweepRefusal.Reason)

    /// The paused row's tooltip: what the pause means for the folder's songs.
    public static let pausedHelp = "Its songs stay in your library and playlists, and come back when it’s back."

    /// The row's status, or nil for a folder with nothing to say. A drive being checked wins the slot (the
    /// user is waiting on it), then a running scan: it is the newer fact (a walk that is evidence ends the
    /// pause).
    public init?(isCheckingDrive: Bool = false, isScanning: Bool, pausedBy reason: SweepRefusal.Reason?) {
        if isCheckingDrive {
            self = .checkingDrive
        } else if isScanning {
            self = .scanning
        } else if let reason {
            self = .paused(reason)
        } else {
            return nil
        }
    }

    /// The caption line under the folder's path.
    public var caption: String {
        switch self {
        case .checkingDrive: "Checking the drive…"
        case .scanning: "Scanning…"
        case let .paused(reason): Self.caption(for: reason)
        }
    }

    /// Whether the row offers "Use This Drive…" (R1.1-B, US-R1F-03 LIB-VOL-1): a folder paused because its
    /// drive is gone, another drive is at its path, or its drive can't be confirmed — the folder may be on
    /// another drive now. Never for a folder the app can't open or that walked empty: its drive is there,
    /// and pointing it elsewhere would not bring its songs back.
    public var offersUseThisDrive: Bool {
        switch self {
        case .paused(.rootVanished), .paused(.differentVolume), .paused(.unrecognizedFolder): true
        case .paused(.incompleteWalk), .paused(.emptyWalk), .scanning, .checkingDrive: false
        }
    }

    /// Whether the row shows "Use This Drive…" — offered, or held (dimmed, with the row's Remove) while the
    /// drive chosen is checked, so a second choice cannot start a second rebind.
    public var showsUseThisDrive: Bool {
        offersUseThisDrive || self == .checkingDrive
    }

    /// A paused folder of the same drive that "Use This Drive…" moved along with the one chosen (plan check
    /// §6, "Use this drive" (10)): its name, and what its rebind kept and removed.
    public struct MovedAlong: Equatable, Sendable {
        public let folderName: String
        public let kept: Int
        public let removed: Int

        public init(folderName: String, kept: Int, removed: Int) {
            self.folderName = folderName
            self.kept = kept
            self.removed = removed
        }
    }

    /// The words the app says after "Use This Drive…": what the rebind kept and removed — and what the
    /// folders of the same drive that moved along with it kept and removed — or why it did nothing. nil for
    /// a refusal the app does not say (a folder removed meanwhile).
    public static func rebindMessage(_ outcome: RebindOutcome, folderName: String,
                                     movedAlong: [MovedAlong] = []) -> String? {
        switch outcome {
        case let .rebound(kept, removed):
            let chosen = "“\(folderName)” now uses this drive — \(foundPhrase(kept: kept, removed: removed))."
            guard let first = movedAlong.first else { return chosen }
            let kept = movedAlong.reduce(0) { $0 + $1.kept }
            let removed = movedAlong.reduce(0) { $0 + $1.removed }
            let along = movedAlong.count == 1 ? "“\(first.folderName)”"
                : "\(movedAlong.count.formatted()) more of its drive’s folders"
            return chosen + " \(along) moved with it — \(foundPhrase(kept: kept, removed: removed))."
        case .refused(.noSongsFound):
            return "That’s not the drive for “\(folderName)” — none of its songs are on it. Nothing was changed."
        case .refused(.unreadableFolder):
            return "That folder can’t be read — is its drive connected? Nothing was changed."
        case .refused(.overlapsFolder):
            return "That folder is already in your library, or inside or around one that is. Nothing was changed."
        case .refused(.songsChanged):
            return "“\(folderName)” changed while the drive was checked. Try again."
        case .refused(.notAFolder):
            return nil
        }
    }

    /// "all 1,234 songs found", "its song found", or "8 songs found; 2 that aren’t on it were removed".
    private static func foundPhrase(kept: Int, removed: Int) -> String {
        guard removed > 0 else {
            return kept == 1 ? "its song found" : "all \(kept.formatted()) songs found"
        }
        let found = kept == 1 ? "1 song" : "\(kept.formatted()) songs"
        let gone = removed == 1 ? "1 that isn’t on it was" : "\(removed.formatted()) that aren’t on it were"
        return "\(found) found; \(gone) removed"
    }

    /// Whether the row wears the paused look: the folder-with-a-question-mark glyph and the tooltip.
    public var isPaused: Bool {
        if case .paused = self {
            true
        } else {
            false
        }
    }

    /// Why the folder is paused, in a few words: one per refusal reason.
    private static func caption(for reason: SweepRefusal.Reason) -> String {
        switch reason {
        case .rootVanished: "Not found — is its drive connected?"
        case .differentVolume: "Another drive is using this name"
        case .unrecognizedFolder: "Can’t confirm this is the folder’s drive"
        case .incompleteWalk: "Can’t open this folder — check its permissions"
        case .emptyWalk: "Looks empty — songs kept"
        }
    }
}
