import SwiftUI

// MARK: - Monitoring Tab

/// Dedicated signal-monitoring tab (Sprint 5 M3). v1 shows per-channel before/after spectra;
/// designed to host additional live monitors over time (see the design doc).
struct MonitoringTabView: View {
    @Environment(AudioViewModel.self) private var viewModel

    var body: some View {
        // Placeholder — replaced by the before/after spectrum layout in Step C.
        VStack {
            Spacer()
            Text("Monitoring")
                .font(DesignSystem.Font.sectionTitle)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Color.window)
    }
}
