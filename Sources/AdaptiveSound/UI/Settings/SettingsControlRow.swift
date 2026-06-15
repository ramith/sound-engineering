import SwiftUI

// MARK: - Settings Control Row

struct SettingsControlRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.asLabelTertiary)
                .frame(width: 24)

            Text(title)
                .font(.body)
                .foregroundStyle(Color.asLabelTertiary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(Color.asLabelTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.asCard)
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9).stroke(Color.asHairline, lineWidth: 0.5)
        }
        .opacity(0.5)
    }
}
