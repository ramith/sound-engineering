// MARK: - PlaylistAddDecision (S10.3 — add-to-playlist: order, dedupe, toast; pure + testable)

/// Pure decisions for "add these tracks to a playlist" (US-PLIST-02). Extracted so the multi-select
/// order/dedupe + the confirmation copy are unit-testable, independent of SwiftUI + the store.
///
/// Membership is a REFERENCE-ADD by track id — never a file move/copy (US-PLIST-04). Duplicates
/// against the EXISTING playlist are allowed (a playlist may hold the same track twice, by design);
/// only the incoming SELECTION is de-duplicated (selecting the same row twice shouldn't add it
/// twice), preserving first-seen order so the added block matches the on-screen order.
public enum PlaylistAddDecision {
    /// The track ids to append: the selection de-duplicated, first-seen order preserved. Empty in →
    /// empty out (a no-op add).
    public static func trackIDsToAdd(_ selected: [Int64]) -> [Int64] {
        var seen = Set<Int64>()
        var ordered: [Int64] = []
        for id in selected where seen.insert(id).inserted {
            ordered.append(id)
        }
        return ordered
    }

    /// The confirmation-toast copy for adding `count` tracks to `playlistName`; nil when nothing was
    /// added (no toast for a no-op).
    public static func toastMessage(added count: Int, playlistName: String) -> String? {
        guard count > 0 else { return nil }
        return "Added \(count) \(count == 1 ? "song" : "songs") to “\(playlistName)”"
    }
}
