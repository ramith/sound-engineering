import SwiftUI

// MARK: - Format Badge

/// Small rounded badge showing a track's file format (e.g. "FLAC", "MP3").
/// Shared by the playlist row and the track-info card so the styling lives in one place.
struct FormatBadgeView: View {
    let format: String
    var isSelected: Bool = false

    var body: some View {
        Text(format)
            .font(DesignSystem.Font.micro)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(isSelected ? Color.asAccent.opacity(0.2) : Color.asCard)
            .foregroundStyle(isSelected ? Color.asAccent : Color.asLabelSecond)
            .clipShape(.rect(cornerRadius: 4, style: .continuous))
    }
}
