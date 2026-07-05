import LibraryStore
import SwiftUI

// MARK: - Shared library track row (S9.4)

/// One track row for the library surfaces (album detail now; Songs + search in S9.5). Renders
/// from `LibraryTrackDisplay` — Title + a caller-chosen secondary line (Artist·Album for
/// Songs/search; empty in album detail, where the disc/track number leads) + duration. NEVER
/// shows `relativePath` (that filesystem-path habit belongs to the raw playlist, not the library).
struct TrackRow: View {
    let track: LibraryTrackDisplay
    /// Leading number column (track number in album detail; nil elsewhere).
    var leadingNumber: Int?
    /// Secondary line under the title ("" hides it).
    var secondary: String = ""

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            if let leadingNumber {
                Text("\(leadingNumber)")
                    .font(DesignSystem.Font.monoSmall)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .frame(width: 24, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.label)
                    .lineLimit(1)
                if !secondary.isEmpty {
                    Text(secondary)
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: DesignSystem.Spacing.small)
            Text(formatDuration(track.durationSeconds))
                .font(DesignSystem.Font.monoSmall)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [track.title]
        if !secondary.isEmpty { parts.append(secondary) }
        parts.append(formatDuration(track.durationSeconds))
        return parts.joined(separator: ", ")
    }
}
