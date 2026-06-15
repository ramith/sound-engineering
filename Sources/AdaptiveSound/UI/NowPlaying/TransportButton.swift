import SwiftUI

// MARK: - Transport Button

/// Reusable circular skip/transport button shared by Previous and Next.
struct TransportButton: View {
    let accessibilityLabel: String
    let systemImage: String
    let symbolSize: CGFloat
    let containerSize: CGFloat
    let action: () -> Void

    var body: some View {
        Button(accessibilityLabel, action: action)
            .buttonStyle(
                TransportButtonStyle(
                    systemImage: systemImage,
                    symbolSize: symbolSize,
                    containerSize: containerSize
                )
            )
            .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Transport Button Style

private struct TransportButtonStyle: ButtonStyle {
    let systemImage: String
    let symbolSize: CGFloat
    let containerSize: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: symbolSize, weight: .medium))
            .foregroundStyle(Color.asLabel)
            // contentShape ensures the full circle area is hittable,
            // not just the symbol's bounding box.
            .frame(width: containerSize, height: containerSize)
            .background(Color.asCard)
            .clipShape(Circle())
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
