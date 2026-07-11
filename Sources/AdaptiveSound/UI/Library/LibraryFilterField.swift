import SwiftUI

// MARK: - Library filter field (S9.6 — the Apple Music "Filter field", per-section)

/// A reusable in-view filter field that narrows the CURRENT section's list in place (distinct from a
/// global search that navigates away — the Apple Music "Filter field" pattern; market-research vetted).
/// Extracted so Albums / Artists / Genres share one styling + ⌘F-focus + Escape-clear behavior. Owns
/// its focus; a hidden ⌘F button keeps the shortcut installed regardless of field state.
struct LibraryFilterField: View {
    @Binding var query: String
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xSmall) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(DesignSystem.Color.labelTertiary)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.label)
                .focused($focused)
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

// MARK: - Library filter header (count + filter field)

/// The header band each browse section (Albums / Artists / Genres) shows above its content: a leading
/// count on the left and the `LibraryFilterField` on the right — the same layout the Songs header uses.
struct LibraryFilterHeader: View {
    let count: String
    @Binding var filter: String
    let placeholder: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Text(count)
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
            Spacer(minLength: DesignSystem.Spacing.small)
            LibraryFilterField(query: $filter, placeholder: placeholder)
        }
        .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        .frame(height: DesignSystem.SongsList.headerHeight)
    }
}
