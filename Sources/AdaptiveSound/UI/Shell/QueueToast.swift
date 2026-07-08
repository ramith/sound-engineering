import SwiftUI

// MARK: - Queue Toast

/// Shell-level, bottom-center confirmation capsule for queue adds (S9.5 §10.4) — a sibling of the top
/// `ErrorBanner`, overlaid on the content region. Reads `LibraryBrowseModel.queueToast`, gated to hide
/// on the Now Playing tab (whose right panel already IS the queue). Tapping opens Now Playing.
///
/// Mirrors `ErrorBanner`'s **persistent-host** pattern so the VoiceOver announcement re-fires on a
/// coalesced replace (keyed on the toast `token`, not `.onAppear`), and matches the `EQRecallBanner`
/// capsule recipe (ultra-thin material + hairline stroke). Motion honors Reduce Motion.
struct QueueToast: View {
    @Environment(LibraryBrowseModel.self) private var library
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Shown only when a toast exists AND we're not on Now Playing (whose panel is the queue).
    private var isVisible: Bool {
        library.queueToast != nil && viewModel.selectedTab != .nowPlaying
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isVisible, let toast = library.queueToast {
                capsule(toast.message)
                    .padding(.bottom, DesignSystem.Spacing.medium)
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Idle host must never intercept clicks to the content beneath (the Songs table's bottom
        // rows) — hit-testable only while a toast is actually shown (review swiftui #8).
        .allowsHitTesting(isVisible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isVisible)
        // Announce keyed on the token so a coalesced replace (even an identical string) re-fires;
        // `.onAppear` catches an already-set toast at mount (mirrors ErrorBanner's persistent host).
        .onChange(of: library.queueToast?.token) { _, _ in announce() }
        .onAppear { announce() }
        // Clear on entering Now Playing by ANY route (tap or manual tab switch) so a stale toast
        // can't reappear on return to a gated tab within the ~2 s window (review swiftui #2).
        .onChange(of: viewModel.selectedTab) { _, tab in
            if tab == .nowPlaying { library.dismissQueueToast() }
        }
    }

    /// Speak the add even though VoiceOver focus is elsewhere (the toast is non-modal, never steals
    /// focus). Suppressed on Now Playing / when there's nothing to show.
    private func announce() {
        guard isVisible, let message = library.queueToast?.message else { return }
        AccessibilityNotification.Announcement(message).post()
    }

    private func capsule(_ message: String) -> some View {
        Button {
            viewModel.selectedTab = .nowPlaying
            library.dismissQueueToast() // clear now; don't rely on the render gate (review swiftui #2)
        } label: {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "text.badge.plus")
                    .foregroundStyle(DesignSystem.Color.accent)
                Text(message)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.label)
                Image(systemName: "chevron.forward")
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(.ultraThinMaterial, in: .capsule)
            .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: DesignSystem.ShellMetrics.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityHint("Opens Now Playing")
    }
}
