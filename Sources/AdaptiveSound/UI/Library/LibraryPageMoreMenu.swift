import SwiftUI

// MARK: - Library page ⋯ menu (S10.8 E4's playlist menu, shared with the detail pages)

/// A Library page's ⋯ pill — the album, artist, genre and playlist pages: a menu of the page's other
/// verbs (Play Next, Add to Queue, …) whose label is a header pill (`HeaderPillFace`, washed on hover,
/// dimmed while disabled), drawn as a real view (`pillMenuStyle`) with the app's keyboard ring.
/// VoiceOver reads it as "More".
struct LibraryPageMoreMenu<Items: View>: View {
    @ViewBuilder let items: Items

    @State private var isHovered = false

    var body: some View {
        Menu {
            items
        } label: {
            HeaderPillFace(content: Label("More", systemImage: "ellipsis").labelStyle(.iconOnly), tone: .neutral,
                           isHovered: isHovered, isPressed: false)
        }
        .pillMenuStyle()
        .controlFocusRing(around: Capsule(style: .circular))
        .onHover { isHovered = $0 }
        .help("More")
        // Outermost, so VoiceOver reads no hint — not the tooltip a second time (the `IconChip` rule).
        .accessibilityHint("")
    }
}
