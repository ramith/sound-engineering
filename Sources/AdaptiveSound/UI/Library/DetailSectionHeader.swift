import SwiftUI

// MARK: - Detail page album header (S10.8 E3 — an artist page's album sections)

/// An album's header on an artist's page: its title and year over its songs, aligned with the rows'
/// content. A fixed height, so the list scrolls a row into view by arithmetic (`FixedRowReveal`), and
/// a VoiceOver heading ("Bombay, 1995").
struct DetailSectionHeader: View {
    let title: String
    /// A bare year ("1995"), or nil when unknown.
    let year: String?

    /// The header's height: the gap above an album, then its title line.
    static let height: CGFloat = 44

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xSmall) {
            Text(title)
                .font(DesignSystem.Font.sectionTitle)
                .foregroundStyle(DesignSystem.Color.label)
                .lineLimit(1)
            if let year {
                Text("· \(year)")
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
            Spacer(minLength: 0)
        }
        // The rows' content starts this far into their card.
        .padding(.horizontal, LibraryRowMetrics.horizontalPadding)
        .padding(.bottom, 6)
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(year.map { "\(title), \($0)" } ?? title)
        .accessibilityAddTraits(.isHeader)
    }
}
