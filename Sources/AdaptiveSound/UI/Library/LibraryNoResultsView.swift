import SwiftUI

// MARK: - Library "no results" (S10.8 D5 — one state for Songs and the browse grids)

/// A filter matched nothing: shown under the card header, which keeps the Filter pill and its
/// "0 results" in place — distinct from an empty library, which has no header. Not animated in or
/// out; `ContentUnavailableView` respects Reduce Motion natively.
struct LibraryNoResultsView: View {
    /// What the list holds, plural: "songs", "albums".
    let items: String
    let query: String

    var body: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No \(items) match “\(query)”.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
