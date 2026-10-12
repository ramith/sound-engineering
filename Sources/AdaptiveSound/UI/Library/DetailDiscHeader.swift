import SwiftUI

// MARK: - Detail page disc header (S10.8 E — an album with more than one disc)

/// A disc's sub-header in an album with more than one disc — on the album's page and under its
/// header on an artist's page: "Disc 2" over that disc's songs, whose track numbers start again at 1.
/// The songs with no disc number, which end the album, sit under "Other Songs". A fixed height (the
/// list places rows by arithmetic) and a VoiceOver heading.
struct DetailDiscHeader: View {
    /// The disc number, or nil for the songs without one.
    let disc: Int?

    /// The sub-header's height: a small gap, then its one line.
    static let height: CGFloat = 28

    var body: some View {
        Text(title)
            .font(DesignSystem.Font.micro)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .lineLimit(1)
            // The rows' content starts this far into their card.
            .padding(.horizontal, LibraryRowMetrics.horizontalPadding)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .bottomLeading)
            .frame(height: Self.height, alignment: .bottom)
            .accessibilityAddTraits(.isHeader)
    }

    private var title: String {
        disc.map { "Disc \($0)" } ?? "Other Songs"
    }
}
