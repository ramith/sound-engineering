import SwiftUI

// MARK: - EQ Tab View

/// The EQ tab: the response graph over the preset / save controls. Per-output memory no longer lives
/// here — the composition root's Edge 5 switches the slot with any tab (or no window) showing, and the
/// shell's `EQOutputToast` says so.
struct EQTabView: View {
    @Environment(EQViewModel.self) private var eqViewModel

    var body: some View {
        // `.fill` (not `.stack`): the graph is an interactive drag surface, so it must NOT
        // live in a ScrollView (drag-to-edit vs scroll is a real conflict — plan §1). The
        // graph flexes to fill instead; at the window min it shrinks toward its 220 min and
        // the content still fits the content region, so no scrolling is needed.
        Screen(mode: .fill) {
            VStack(spacing: 20) {
                VisualizerSurface(
                    minHeight: DesignSystem.Visualizer.responseGraphMinHeight,
                    idealHeight: DesignSystem.Visualizer.responseGraphIdealHeight,
                    maxHeight: DesignSystem.Visualizer.responseGraphMaxHeight
                ) {
                    FrequencyResponseCanvas(eqViewModel: eqViewModel)
                }
                .padding(.top, 20)
                .padding(.horizontal)

                EQControlsSection(eqViewModel: eqViewModel)
            }
        }
    }
}
