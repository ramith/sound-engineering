import SwiftUI

// MARK: - Library page actions (S10.8 E — the album, artist, genre and playlist pages' header pills)

/// A Library page's verbs as header pills, one set for every page (decision 36: Play · Shuffle · ⋯):
/// Play (the teal pill, with the app's keyboard ring), Shuffle (a neutral `HeaderPillButton`) and the
/// page's ⋯ menu (`LibraryPageMoreMenu`). Three sibling pills, laid out by the caller's row like a
/// `Group` — the playlist page puts them in `LibraryCardHeader`'s controls, the album, artist and
/// genre pages in their header's actions row. The caller decides when they act (`.disabled`) and
/// keeps them at their size (`.fixedSize()`).
struct LibraryPageActions<More: View>: View {
    let play: () -> Void
    let shuffle: () -> Void
    /// The page's ⋯ menu.
    @ViewBuilder let more: More

    var body: some View {
        Button("Play", systemImage: "play.fill", action: play)
            .buttonStyle(.pill)
            .controlSize(.large)
            .controlFocusRing(around: Capsule(style: .circular))
        HeaderPillButton("Shuffle", systemImage: "shuffle", action: shuffle)
        more
    }
}
