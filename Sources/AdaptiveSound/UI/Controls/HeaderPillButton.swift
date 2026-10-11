import SwiftUI

// MARK: - Header pill button (Sprint EQ, EQ3 — and the dialogs' buttons)

/// A labelled pill that runs an action — the EQ header's Reset, and the dialogs' Cancel and Delete
/// (`AppDialog`): a plain button whose whole capsule is the hit shape (built inside the button, so it
/// is), with the hover wash, the press dim and the app's keyboard ring (`controlFocusRing`) in place of
/// the system focus effect. A Tab stop under Full Keyboard Access, pressed with Return; Space stays
/// play / pause. Its tone is the pill's: neutral, or destructive (the error family, never system red).
struct HeaderPillButton: View {
    private let title: String
    private let systemImage: String?
    private let tone: HeaderPillChrome.Tone
    private let role: ButtonRole?
    private let help: String?
    private let action: () -> Void

    @State private var isHovered = false

    /// `help` is the tooltip and the VoiceOver hint: what pressing does, where the title doesn't say.
    init(_ title: String, systemImage: String? = nil, tone: HeaderPillChrome.Tone = .neutral,
         role: ButtonRole? = nil, help: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tone = tone
        self.role = role
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(PillStyle(tone: tone, isHovered: isHovered))
        .controlFocusRing(around: Capsule(style: .circular))
        .onHover { isHovered = $0 }
        .help(help ?? "")
    }
}

extension HeaderPillButton {
    /// The face as a style, since the pressed state is the style's.
    private struct PillStyle: ButtonStyle {
        let tone: HeaderPillChrome.Tone
        let isHovered: Bool

        func makeBody(configuration: Configuration) -> some View {
            HeaderPillFace(content: configuration.label, tone: tone, isHovered: isHovered,
                           isPressed: configuration.isPressed)
        }
    }
}
