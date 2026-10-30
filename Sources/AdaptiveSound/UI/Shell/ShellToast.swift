import SwiftUI

// MARK: - Shell toast slot (the model side)

/// One transient shell message: its owner raises it, the shell shows it (`ShellToastHost`), and it
/// clears itself after `lifetime`. Shared by the queue-add toast (`LibraryBrowseModel.queueToast`)
/// and the EQ's output-switch toast (`EQViewModel.outputToast`).
///
/// A raise REPLACES the message on show and restarts the timer through ONE cancellable task (not
/// one per raise): the post-sleep `!Task.isCancelled` guard stops a superseded timer clearing the
/// newer message (review swiftui #3). The `token` is monotonic, so the host re-announces and
/// re-renders a replace even with an IDENTICAL message (review swiftui #1/#5). No `didSet`, so no
/// @Observable self-assign trap.
@MainActor
@Observable
final class ShellToastSlot {
    /// A raised message, keyed by the token the host announces and animates on.
    struct Toast: Equatable {
        let message: String
        let token: Int
    }

    /// The message on show, or `nil`.
    private(set) var toast: Toast?

    @ObservationIgnored private var token = 0
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    private let lifetime: Duration
    /// The clock the lifetime runs on: `ContinuousClock` in the app, a test clock in a test.
    private let clock: any Clock<Duration>

    init(lifetime: Duration, clock: any Clock<Duration> = ContinuousClock()) {
        self.lifetime = lifetime
        self.clock = clock
    }

    /// Show `message` for `lifetime`, replacing any message on show.
    func show(_ message: String) {
        token &+= 1
        toast = Toast(message: message, token: token)
        dismissTask?.cancel()
        dismissTask = Task { [weak self, lifetime, clock] in
            try? await clock.sleep(for: lifetime)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    /// Clear the message now (a tap-through, or a tab where it has no meaning).
    func dismiss() {
        dismissTask?.cancel()
        toast = nil
    }
}

// MARK: - Shell toast host (the view side)

/// One `ShellToastSlot`'s confirmation capsule, in the shell's bottom stack (`ShellToasts`) on every
/// tab. Tapping it runs `open`, which takes the user to what the toast is about.
///
/// A **persistent host** (as `ErrorBanner`): the VoiceOver announcement is keyed on the toast's
/// token, so a coalesced replace re-fires it. A toast already up when the host appears was raised while
/// no window showed it — an output switch with the window closed, a menu-bar action — so on reopen it is
/// neither shown nor spoken (break-it 7). Idle, the host takes no room (the stack closes up) and never
/// intercepts clicks to the content beneath (review swiftui #8). Recipe: ultra-thin glass + a hairline
/// (Regime A/`.overlay`, S10.7 §3.1). Motion honours Reduce Motion.
struct ShellToastHost: View {
    /// The toast to show; `nil` when none is raised or its owner hides it here.
    let toast: ShellToastSlot.Toast?
    let systemImage: String
    /// VoiceOver's hint for the tap, e.g. "Opens Now Playing".
    let hint: String
    let open: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The token of a toast already up when the host was created: stale, never shown or spoken.
    @State private var staleToken: Int?

    init(toast: ShellToastSlot.Toast?, systemImage: String, hint: String, open: @escaping () -> Void) {
        self.toast = toast
        self.systemImage = systemImage
        self.hint = hint
        self.open = open
        // A State's initial value is taken once, when the host is created: whatever toast is up then
        // was raised while no window showed it.
        _staleToken = State(initialValue: toast?.token)
    }

    var body: some View {
        let shown = toast.flatMap { $0.token == staleToken ? nil : $0 }
        ZStack {
            if let shown {
                capsule(shown.message)
                    .transition(reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .allowsHitTesting(shown != nil)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: shown != nil)
        .onChange(of: toast?.token) { _, _ in announce() }
    }

    /// Speak a newly raised message even though VoiceOver focus is elsewhere (the toast is non-modal and
    /// never steals focus).
    private func announce() {
        guard let toast, toast.token != staleToken else { return }
        AccessibilityNotification.Announcement(toast.message).post()
    }

    private func capsule(_ message: String) -> some View {
        Button(action: open) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: systemImage)
                    .foregroundStyle(DesignSystem.Color.accentForeground)
                Text(message)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.label)
                Image(systemName: "chevron.forward")
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            // Regime A/`.overlay` (S10.7 §3.1): transient toast floating over variable content.
            .glassPanel(.overlay(.ultraThin), in: Capsule())
            .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: DesignSystem.ShellMetrics.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        // A Tab stop under Full Keyboard Access: the app's teal ring around the capsule, never the system's one.
        .controlFocusRing(around: Capsule())
        .pointerStyle(.link)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityHint(hint)
    }
}
