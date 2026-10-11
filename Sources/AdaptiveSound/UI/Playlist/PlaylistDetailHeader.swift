import LibraryBrowseKit
import SwiftUI

// MARK: - Playlist page header (S10.8 E4 — the Library card's header)

/// The playlist page's header, on the Library card's grammar (`LibraryCardHeader`, Sprint D): the
/// playlist's name, the count line under it, and the page's verbs as the header's pills — Play (the
/// teal pill), Shuffle and ⋯ (`PlaylistMoreMenu`), the album, artist and genre pages' set. No Filter: a
/// playlist is played and moved in its own order.
///
/// The count line is "12 songs · 48 min", ending "· 2 unavailable" while files are missing; where it
/// doesn't fit on one line the duration goes first ("12 songs · 2 unavailable"). VoiceOver reads it
/// whole. The pills act once the playlist has loaded.
struct PlaylistDetailHeader: View {
    let play: () -> Void
    let shuffle: () -> Void
    /// Asks to remove the entries whose files are missing (the page confirms first).
    let removeMissing: () -> Void

    @Environment(PlaylistsModel.self) private var model

    var body: some View {
        LibraryCardHeader(title: model.openPlaylist?.name ?? "Playlist", count: countLine, compactCount: compactCount) {
            Group {
                Button("Play", systemImage: "play.fill", action: play)
                    .buttonStyle(.pill)
                    .controlSize(.large)
                    .controlFocusRing(around: Capsule(style: .circular))
                HeaderPillButton("Shuffle", systemImage: "shuffle", action: shuffle)
                PlaylistMoreMenu(removeMissing: removeMissing)
            }
            // The pills keep their size; a long name truncates instead.
            .fixedSize()
            .disabled(model.detailState != .loaded)
        }
    }

    /// "12 songs · 48 min" — every listed song's length, missing ones included: how long the playlist is.
    private var countLine: String {
        let seconds = model.detail.reduce(0) { $0 + ($1.display?.durationSeconds ?? 0) }
        return line([songs, humaneTotalDuration(seconds)])
    }

    /// "12 songs": the count line without its duration.
    private var compactCount: String {
        line([songs])
    }

    private var songs: String {
        FacetCountLabel.songs(count: model.detail.count)
    }

    /// `parts` joined by " · ", ending "· 2 unavailable" while some entries' files are missing.
    private func line(_ parts: [String]) -> String {
        let missing = model.missingEntryCount
        let unavailable = missing > 0 ? ["\(missing.formatted(.number)) unavailable"] : []
        return (parts + unavailable).joined(separator: " · ")
    }
}
