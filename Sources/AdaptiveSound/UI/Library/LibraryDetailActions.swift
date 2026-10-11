import LibraryStore
import SwiftUI

// MARK: - Detail page actions (S10.8 E2/E3 — the header's Play, Shuffle and ⋯)

/// The page's actions, on the header pills: Play (the teal pill — the whole page from the top),
/// Shuffle (an artist's or a genre's page) and ⋯ (Play Next, Add to Queue, Add to Playlist for the
/// whole page). Off while the page has no songs.
struct LibraryDetailActions: View {
    /// The page's songs in the order shown.
    let rows: [LibraryTrackDisplay]
    /// The page offers Shuffle (an artist's or a genre's; an album's page never had it).
    let offersShuffle: Bool
    /// "Add to Playlist…": the page's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        HStack(spacing: ControlMetrics.pillGap) {
            Button("Play", systemImage: "play.fill", action: play)
                .buttonStyle(.pill)
                .controlSize(.large)
            if offersShuffle {
                HeaderPillButton("Shuffle", systemImage: "shuffle", action: shuffle)
            }
            moreMenu
        }
        .disabled(rows.isEmpty)
        .fixedSize()
    }

    /// ⋯ — the whole page's queue verbs. A pill menu (`pillMenuStyle`): the borderless style would
    /// drop the capsule.
    private var moreMenu: some View {
        Menu {
            Button("Play Next", action: playNext)
            Button("Add to Queue", action: append)
            AddToPlaylistMenu(resolveTrackIDs: { rows.map(\.id) }, onChooseMore: choosePlaylist)
        } label: {
            Label("More", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(DesignSystem.Font.bodyMedium)
                .foregroundStyle(rows.isEmpty ? DesignSystem.Color.labelDisabled : DesignSystem.Color.label)
                .headerPillChrome(.neutral)
                .contentShape(Capsule())
        }
        .pillMenuStyle()
        .controlFocusRing(around: Capsule())
        .help("More")
        .accessibilityLabel("More")
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
