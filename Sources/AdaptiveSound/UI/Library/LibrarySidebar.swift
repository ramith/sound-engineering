import SwiftUI

// MARK: - Library sidebar (S9.4)

/// The category list. Selection binds to the injected model (`selectedCategory`), so it
/// survives tab teardown. `.tag(category)` makes the `List` selection a `LibraryCategory?`.
struct LibrarySidebar: View {
    @Environment(LibraryBrowseModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedCategory) {
            ForEach(LibraryCategory.allCases) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
        }
        .navigationTitle("Library")
    }
}
