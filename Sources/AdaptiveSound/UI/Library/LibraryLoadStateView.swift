import SwiftUI

// MARK: - Library load states (S10.8 D5 — one state machine for every Library card root)

/// The load-state machine of every Library card root — Songs, Albums, Artists, Genres — written
/// once, so the facet-empty-vs-"no music" distinction and the scanning states stay right in all
/// four: a spinner until the first load (a refresh keeps the cached items showing); the first-run
/// call to action, or "scanning" once a scan started from it; the category's own empty state, or
/// "scanning" while a pass is live; a failure. Every state sits on the Library card (D1), so the
/// card is never blank.
struct LibraryLoadStateView<Empty: View, Content: View>: View {
    let state: LibraryBrowseModel.LoadState
    /// The category has nothing to show, before any filter.
    let isEmpty: Bool
    /// The category is empty while the library is not: "No Music Found" for Songs and Albums (every
    /// song was removed), "No Artists" / "No Genres" for untagged songs.
    @ViewBuilder let empty: Empty
    @ViewBuilder let content: Content

    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        switch state {
        case .idle, .loading:
            if isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
        case .loaded:
            if isEmpty {
                empty
            } else {
                content
            }
        case .firstRun:
            LibraryEmptyStateView(kind: model.isPopulating ? .scanning : .firstRun)
        case .empty:
            if model.isPopulating {
                LibraryEmptyStateView(kind: .scanning)
            } else {
                empty
            }
        case let .failed(message):
            LibraryEmptyStateView(kind: .failed(message))
        }
    }
}
