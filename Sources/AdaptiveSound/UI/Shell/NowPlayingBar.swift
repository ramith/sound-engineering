import SwiftUI

/// The persistent transport footer — L2 stub.
///
/// For L2 this is an idle placeholder only; the real transport (play controls +
/// scrubber, relocated from the Now Playing left panel) lands in L3. `AppShell`
/// reserves the 64pt band, paints the panel background, and draws the top hairline,
/// so this view just fills the reserved space quietly — no height, background, or
/// `AudioViewModel` coupling yet.
struct NowPlayingBar: View {
    var body: some View {
        Text("Nothing playing")
            .font(DesignSystem.Font.caption)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Transport. Nothing playing.")
    }
}
