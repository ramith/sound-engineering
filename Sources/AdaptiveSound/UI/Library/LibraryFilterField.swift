import SwiftUI

// MARK: - Library filter field (S9.6 — the Apple Music "Filter field", per-section)

/// A reusable in-view filter field that narrows the CURRENT list in place (distinct from a global
/// search that navigates away — the Apple Music "Filter field" pattern; market-research vetted). Owns
/// its focus; a hidden ⌘F button keeps the shortcut installed regardless of field state. Now only
/// the playlist picker's: the Library card headers moved to the shared `FilterPill` (S10.8 D2), which
/// the picker adopts next.
struct LibraryFilterField: View {
    @Binding var query: String
    let placeholder: String
    /// Focus the field when it appears (e.g. a picker sheet that should be type-ready). Default off:
    /// the in-tab filters focus on ⌘F / click, not on every tab visit.
    var focusesOnAppear = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignSystem.Color.labelTertiary)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.label)
                // Focus + the transport-Space gate (S4 SW1) in one place.
                .suppressesTransportSpace(while: $focused)
                .onAppear {
                    if focusesOnAppear {
                        focused = true
                    }
                }
                .onExitCommand { // macOS Cancel (Escape): clear then defocus
                    query = ""
                    focused = false
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignSystem.Color.labelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.small)
        .frame(height: 28)
        .frame(
            minWidth: DesignSystem.SongsList.searchFieldMinWidth,
            idealWidth: DesignSystem.SongsList.searchFieldIdealWidth
        )
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control).fill(DesignSystem.Color.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                .stroke(DesignSystem.Color.hairline, lineWidth: 0.5)
        )
        .background {
            Button("Filter") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        }
    }
}
