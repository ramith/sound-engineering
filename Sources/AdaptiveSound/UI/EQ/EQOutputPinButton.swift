import EQEditKit
import SwiftUI

// MARK: - The "Used on <output>" pin (Sprint EQ, EQ4 — decision 28, amendment 13)

/// Per-output memory, under the preset's name. Pressing it pins the current output: it keeps exactly
/// what plays now and, from then on, its own edits and Tone; every other output plays on as before.
/// Pressed again, the shared EQ takes the pin's sound over, so nothing audible changes.
///
/// - **Unpinned:** "Use on MacBook Pro Speakers", an outline pin in the secondary label colour.
/// - **Pinned:** "Used on MacBook Pro Speakers", a filled teal pin.
/// - **Shared with its model** (a second pair of pinned AirPods — the model-UID fallback, amendment 13,
///   for the founder check): "Used on AirPods Pro · same model", and the tooltip says so plainly.
///
/// Hidden with no output, or one that can't be pinned (a private aggregate). A Tab stop with the app's
/// keyboard ring, pressed with Return; VoiceOver hears a toggle, "Use on <output>", on or off.
struct EQOutputPinButton: View {
    let pin: EQOutputPin
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: toggle) {
            Label(title, systemImage: pin.isPinned ? "pin.fill" : "pin")
                .font(DesignSystem.Font.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(foreground)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .controlFocusRing(around: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
        .onHover { isHovered = $0 }
        .help(tooltip) // also VoiceOver's hint
        .accessibilityLabel("Use on \(pin.output.name)")
        .accessibilityValue(pin.isPinned ? "on" : "off")
        .accessibilityAddTraits(.isToggle)
    }

    private var title: String {
        switch pin {
        case let .unpinned(output): "Use on \(output.name)"
        case let .pinned(output): "Used on \(output.name)"
        case let .sharedWith(pinned, on: _): "Used on \(pinned.name) · same model"
        }
    }

    private var tooltip: String {
        switch pin {
        case let .unpinned(output):
            "Keep this EQ for \(output.name): it plays whenever you listen there, and the other outputs keep theirs."
        case let .pinned(output):
            output.modelUID == nil
                ? "This EQ is kept for \(output.name), with your edits. Click to share one EQ across outputs again."
                : "This EQ is kept for \(output.name) — and plays on any other output of the same model. "
                + "Click to share one EQ across outputs again."
        case let .sharedWith(pinned, on: output):
            "\(output.name) is the same model as \(pinned.name), so it plays and edits that output's pinned EQ. "
                + "Click to unpin it from both."
        }
    }

    private var foreground: Color {
        if pin.isPinned {
            DesignSystem.Color.accentText
        } else {
            isHovered ? DesignSystem.Color.label : DesignSystem.Color.labelSecondary
        }
    }
}
