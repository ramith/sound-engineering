import EQEditKit
import SwiftUI

// MARK: - EQ "Bring back edits" (Sprint EQ, EQ3 — decision 27, ui-plan §4.5)

/// The capsule a preset switch raises when it set edits aside: "Edits to Warm set aside · Bring back
/// edits", at the bottom of the graph card. It shows for 6 s (the playlist restore message's time),
/// paused while it is hovered or holds keyboard focus, and re-armed by every further switch; Bring back
/// restores the whole slot. VoiceOver hears the switch and the offer as it appears. Keyboard and
/// VoiceOver users keep the offer with no time limit in the presets list (context menu, VoiceOver
/// action) until the next edit. The recipe is the queue toast's: `.overlay` glass and a hairline.
struct EQBringBackMessage: View {
    @Environment(EQViewModel.self) private var eq
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the capsule shows, unpaused.
    private static let lifetime: Duration = .seconds(6)

    /// The offer on show; nil once its time ran out (the offer itself lives on in the view model).
    @State private var shownOffer: Int?
    /// What is left of this offer's time.
    @State private var remaining = lifetime
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            if let bringBack = eq.bringBack, shownOffer == bringBack.offer {
                capsule(setAside: bringBack.edits.preset.displayName)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: shownOffer)
        // Initially (a return to the tab) the offer still on shows, unannounced: it was announced when
        // it was made.
        .onChange(of: eq.bringBack?.offer, initial: true) { old, offer in arm(offer, announce: old != offer) }
        .task(id: countdown) { await run(countdown) }
    }

    /// The offer on show and whether its time is paused: hovered, or its button holding keyboard focus.
    private var countdown: Countdown {
        Countdown(offer: shownOffer, isPaused: isHovered || isFocused)
    }

    private func capsule(setAside name: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Text("Edits to \(name) set aside")
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.label)
            Button("Bring back edits", action: eq.bringBackEdits)
                .buttonStyle(.plain)
                .font(DesignSystem.Font.caption.weight(.semibold))
                .foregroundStyle(DesignSystem.Color.accentForeground)
                .focused($isFocused)
        }
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        // Regime A/`.overlay` (S10.7 §3.1): a transient message over the graph — the queue toast's recipe.
        .glassPanel(.overlay(.ultraThin), in: Capsule())
        .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: DesignSystem.ShellMetrics.hairline))
        .onHover { isHovered = $0 }
    }

    /// A new offer shows for the full time and is announced; a cleared one hides. The hover starts
    /// clear: a capsule that went away under the pointer (its button clicked) never sends the exit.
    private func arm(_ offer: Int?, announce: Bool) {
        shownOffer = offer
        remaining = Self.lifetime
        isHovered = false
        guard announce, offer != nil, let setAside = eq.bringBack?.edits.preset.displayName else { return }
        let switched = eq.current.preset.displayName
        AccessibilityNotification.Announcement("Switched to \(switched). Edits to \(setAside) can be brought back.")
            .post()
    }

    /// Runs the offer's remaining time unless paused; a pause (or a new offer) cancels it, keeping what
    /// is left of THIS offer's time.
    private func run(_ countdown: Countdown) async {
        guard let offer = countdown.offer, !countdown.isPaused else { return }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await Task.sleep(for: remaining)
            shownOffer = nil
        } catch {
            if shownOffer == offer {
                remaining = max(remaining - (clock.now - start), .zero)
            }
        }
    }
}

extension EQBringBackMessage {
    /// The countdown's identity: a new offer or a pause change restarts it.
    private struct Countdown: Equatable {
        let offer: Int?
        let isPaused: Bool
    }
}
