import SwiftUI

/// Minimal section header below the toolbar.
///
/// Displays the app title "Adaptive Sound" centered at 44pt height,
/// separated from tab content by a hairline bottom border.
struct FixedHeaderView: View {
    var body: some View {
        Text("Adaptive Sound")
            .font(.headline)
            .foregroundStyle(Color.asLabel)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.asWindow)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.asHairline)
                    .frame(height: 0.5)
            }
    }
}
