import SwiftUI

// MARK: - Error Banner

/// Shell-level, non-modal surface for `AudioViewModel.errorMessage`. Overlaid at the top of the
/// content region (below the chrome) on every tab, so engine-init / device-loss / playback / scan
/// failures — previously set on the model but shown in NO UI — are now visible and recoverable.
///
/// Visual language matches `EQRecallBanner` (ultra-thin material + a hairline stroke), sized as a
/// rounded card rather than a pill because it carries an icon, wrapping text, and up to two actions.
///
/// Behaviour:
/// - **Dismiss (✕)** clears `errorMessage` — always available.
/// - **Retry** is shown ONLY when `!isEngineReady` (the engine failed to init / was lost) and calls
///   `retryInitialization()`. For a transient error while the engine is alive (e.g. "Playback
///   failed"), there is nothing to re-initialize, so only Dismiss is offered.
/// - Errors persist until dismissed or resolved — deliberately NOT auto-timed like the transient EQ
///   recall banner, since a silently vanishing failure is what this view exists to prevent.
struct ErrorBanner: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // A persistent host so `.onChange` fires reliably on the nil → message transition and can
        // drive the VoiceOver announcement; the card itself is inserted/removed with a transition.
        ZStack(alignment: .top) {
            if let message = viewModel.errorMessage {
                card(message: message)
                    .padding(.top, DesignSystem.Spacing.medium)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        // When idle the host renders nothing; make sure it can never intercept hit-tests on the
        // top strip of the active tab (defensive — an empty ZStack is already zero-height).
        .allowsHitTesting(viewModel.errorMessage != nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.errorMessage)
        .onChange(of: viewModel.errorMessage) { _, message in announce(message) }
        .onAppear {
            // `.onChange` only fires on a LATER change; if an error is already set when the banner
            // first mounts, announce it here so VoiceOver still learns of it.
            announce(viewModel.errorMessage)
        }
    }

    /// Speak a failure even though VoiceOver focus is elsewhere — the banner is non-modal and
    /// never steals focus, so an announcement is how a non-sighted user learns of it.
    private func announce(_ message: String?) {
        guard let message else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private func card(message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignSystem.Color.statusWarning)
                .accessibilityHidden(true) // the message Text carries the meaning

            Text(message)
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.label)
                .fixedSize(horizontal: false, vertical: true) // wrap long localizedDescriptions
                .accessibilityLabel("Error: \(message)")

            Spacer(minLength: DesignSystem.Spacing.small)

            if !viewModel.isEngineReady {
                Button("Retry") { viewModel.retryInitialization() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesignSystem.Color.accent)
                    .help("Retry starting the audio engine")
            }

            Button("Dismiss", systemImage: "xmark") { viewModel.errorMessage = nil }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .help("Dismiss")
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        // Regime A/`.overlay` (S10.7 §3.1): a transient banner floating OVER variable tab
        // content — the one Material-sanctioned role; substrate/fallbacks owned by the token
        // layer, shape + hairline stay site-owned.
        .glassPanel(.overlay(.ultraThin), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.container))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.container)
                .stroke(DesignSystem.Color.hairline, lineWidth: DesignSystem.ShellMetrics.hairline)
        )
        .frame(maxWidth: DesignSystem.LayoutMetrics.readableMaxWidth)
    }
}
