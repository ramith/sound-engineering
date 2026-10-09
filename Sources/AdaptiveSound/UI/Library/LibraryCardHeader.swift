import SwiftUI

// MARK: - Library card header (S10.8 D4 — Songs, Albums, Artists, Genres)

/// The header of the Library card, one for the four categories so it stays put as the rail
/// switches between them (`png/03`): the title, the mono count line under it, the Filter pill
/// (⌘F focuses it; Esc clears it and hands key focus to the list or grid below, K1) and the
/// category's own pills after it — Songs' Sort and Columns; none on the grids for R1. A hairline
/// under it, inset with the text.
struct LibraryCardHeader<Controls: View>: View {
    let title: String
    /// "857 albums", "379 songs · 41 hrs", or "N results" while filtering. VoiceOver reads it whole.
    let count: String
    /// Stands in for `count` where that would not fit on one line (Songs at 880×640, D6).
    var compactCount: String?
    @Binding var filter: String
    let filterPrompt: String
    /// The card's one focus value (`CardFocus`), owned by the category root: the pill is `.filter`.
    let focus: FocusState<CardFocus?>.Binding
    @ViewBuilder let controls: Controls

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.title3, weight: .heavy))
                        .foregroundStyle(DesignSystem.Color.label)
                    countLine
                }
                Spacer(minLength: DesignSystem.Spacing.small)
                FilterPill(text: $filter, prompt: filterPrompt, focus: focus, focusShortcut: KeyboardShortcut("f"))
                    .frame(minWidth: DesignSystem.SongsList.searchFieldMinWidth, idealWidth: 230, maxWidth: 260)
                controls
            }
            .padding(.top, 16)
            .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
            .padding(.bottom, 14)
            Rectangle()
                .fill(DesignSystem.Color.hairline)
                .frame(height: 1)
                .padding(.horizontal, DesignSystem.LayoutMetrics.screenInsetH)
        }
    }

    /// One line, never wrapped: the compact count stands in where the full one doesn't fit.
    private var countLine: some View {
        Group {
            if let compactCount {
                ViewThatFits(in: .horizontal) {
                    Text(count)
                    Text(compactCount)
                }
            } else {
                Text(count)
            }
        }
        .lineLimit(1)
        .font(DesignSystem.Font.monoSmall)
        .foregroundStyle(DesignSystem.Color.labelTertiary)
        .accessibilityLabel(count)
    }
}

extension LibraryCardHeader where Controls == EmptyView {
    /// A header with the Filter pill alone (the browse grids).
    init(title: String, count: String, filter: Binding<String>, filterPrompt: String,
         focus: FocusState<CardFocus?>.Binding) {
        self.init(title: title, count: count, filter: filter, filterPrompt: filterPrompt, focus: focus) {
            EmptyView()
        }
    }
}
