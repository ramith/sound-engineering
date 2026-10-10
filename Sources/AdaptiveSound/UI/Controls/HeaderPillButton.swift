import SwiftUI

// MARK: - Header pill button (Sprint EQ, EQ3)

/// A labelled header pill that runs an action — the EQ header's Reset, and EQ4's "Used on" pin: a
/// plain button whose whole capsule is the hit shape (built inside the button, so it is), with the
/// hover wash, the press dim and the app's keyboard ring (`controlFocusRing`) in place of the system
/// focus effect. A Tab stop under Full Keyboard Access, pressed with Return; Space stays play / pause.
struct HeaderPillButton: View {
    private let title: String
    private let systemImage: String
    private let help: String
    private let action: () -> Void

    @State private var isHovered = false

    /// `help` is the tooltip and the VoiceOver hint: what pressing does, where the title doesn't say.
    init(_ title: String, systemImage: String, help: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.help = help
        self.action = action
    }

    var body: some View {
        Button(title, systemImage: systemImage, action: action)
            .buttonStyle(PillStyle(isHovered: isHovered))
            .controlFocusRing(around: Capsule())
            .onHover { isHovered = $0 }
            .help(help)
    }
}

extension HeaderPillButton {
    /// The face as a style, since the pressed state is the style's.
    private struct PillStyle: ButtonStyle {
        let isHovered: Bool

        func makeBody(configuration: Configuration) -> some View {
            HeaderPillFace(content: configuration.label, tone: .neutral, isHovered: isHovered,
                           isPressed: configuration.isPressed)
        }
    }
}
