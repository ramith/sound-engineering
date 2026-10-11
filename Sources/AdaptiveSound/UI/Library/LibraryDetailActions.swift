import LibraryStore
import SwiftUI

// MARK: - Detail page actions (S10.8 E2/E3 — the header's Play, Shuffle and ⋯)

/// An album, artist or genre page's verbs, on every Library page's header pills (`LibraryPageActions`,
/// the playlist page's too): Play (the whole page from the top), Shuffle (an artist's or a genre's
/// page) and ⋯ — Play Next, Add to Queue and Add to Playlist for the whole page. Off while the page
/// has no songs.
struct LibraryDetailActions: View {
    /// The page's songs in the order shown.
    let rows: [LibraryTrackDisplay]
    /// The page offers Shuffle (an artist's or a genre's; an album's page never had it).
    let offersShuffle: Bool
    /// "Add to Playlist…": the page's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        // The card header's spacing between pills (`LibraryCardHeader`), so every page's pills match.
        HStack(spacing: DesignSystem.Spacing.medium) {
            LibraryPageActions(play: play, shuffle: shuffleAction) {
                LibraryPageMoreMenu {
                    Button("Play Next", action: playNext)
                    Button("Add to Queue", action: append)
                    AddToPlaylistMenu(resolveTrackIDs: trackIDs, onChooseMore: choosePlaylist)
                }
            }
        }
        .fixedSize()
        .disabled(rows.isEmpty)
    }

    /// Shuffle, on a page that offers it.
    private var shuffleAction: (() -> Void)? {
        guard offersShuffle else { return nil }
        return shuffle
    }

    /// The page's songs, for Add to Playlist.
    private func trackIDs() async -> [Int64] {
        rows.map(\.id)
    }

    private func play() {
        model.play(rows, startAt: 0)
    }

    /// Shuffle on, then the page from a random song.
    private func shuffle() {
        model.shuffle(rows)
    }

    private func playNext() {
        model.playNext(rows)
    }

    private func append() {
        model.append(rows)
    }
}
