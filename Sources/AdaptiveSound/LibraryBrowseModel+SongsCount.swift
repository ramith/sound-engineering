import Foundation
import LibraryBrowseKit

// MARK: - The Songs count line (S9.5 design §3.3/§6; S10.8 D6)

/// The Songs header's summary text, driven off `visibleSongs` / `matchedIDs`.
extension LibraryBrowseModel {
    /// The Songs summary line: unfiltered "N songs · total duration"; filtered "N results" (duration
    /// dropped; `0` → "0 results").
    var songsCountLine: String {
        guard matchedIDs == nil else { return songsCount }
        let total = humaneTotalDuration(visibleSongs.reduce(0.0) { $0 + $1.durationSeconds })
        return "\(songsCount) · \(total)"
    }

    /// The count alone — "N songs", or "N results" while filtered: the summary line's lead, and the
    /// whole line where the full one would not fit on one line (the 880×640 minimum window, D6).
    /// The card headers' one count rule (`FacetCountLabel.count`).
    var songsCount: String {
        FacetCountLabel.count(visibleSongs.count, noun: "song", filtered: matchedIDs != nil)
    }
}
