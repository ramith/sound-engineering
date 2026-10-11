import SwiftUI

// MARK: - Library card header (S10.8 D4 — Songs, Albums, Artists, Genres; E4 — a playlist)

/// The header of the Library card, one for the four categories so it stays put as the rail
/// switches between them (`png/03`): the title, the mono count line under it, the Filter pill
/// (⌘F focuses it; Esc clears it and hands key focus to the list or grid below, K1) and the
/// category's own pills after it — Songs' Sort and Columns; none on the grids for R1. A hairline
/// under it, inset with the text. A playlist's page wears it too, with no Filter (S10.8 E4): its own
/// pills alone.
struct LibraryCardHeader<Controls: View>: View {
    let title: String
    /// "857 albums", "379 songs · 41 hrs", or "N results" while filtering. VoiceOver reads it whole.
    let count: String
    /// Stands in for `count` where that would not fit on one line (Songs at 880×640, D6).
    let compactCount: String?
    /// The Filter pill, or nil on a page with no Filter.
    private let filterPill: FilterPill?
    let controls: Controls

    /// A category's header: the Filter pill, then the category's own pills. `focus` is the card's one
    /// focus value (`CardFocus`), owned by the category root: the pill is `.filter`.
    init(title: String, count: String, compactCount: String? = nil, filter: Binding<String>, filterPrompt: String,
         focus: FocusState<CardFocus?>.Binding, @ViewBuilder controls: () -> Controls) {
        self.title = title
        self.count = count
        self.compactCount = compactCount
        filterPill = FilterPill(text: filter, prompt: filterPrompt, focus: focus, focusShortcut: KeyboardShortcut("f"))
        self.controls = controls()
    }

    /// A page's header with no Filter — its own pills alone (a playlist, played and moved in its own
    /// order).
    init(title: String, count: String, compactCount: String? = nil, @ViewBuilder controls: () -> Controls) {
        self.title = title
        self.count = count
        self.compactCount = compactCount
        filterPill = nil
        self.controls = controls()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    // One line: a playlist's name is the user's own, and may be long.
                    Text(title)
                        .font(.system(.title3, weight: .heavy))
                        .foregroundStyle(DesignSystem.Color.label)
                        .lineLimit(1)
                    countLine
                }
                Spacer(minLength: DesignSystem.Spacing.small)
                if let filterPill {
                    filterPill.filterPillWidth(.library)
                }
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
