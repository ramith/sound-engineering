import SwiftUI

// MARK: - App dialog (S10.8 EQ fix — the founder's "match the UI theme")

/// The app's one themed dialog: a title, an optional message, optional content (a name field), and the
/// buttons — the app's pills, never the system's blue default button or red destructive one.
///
/// - **Buttons:** Cancel is the neutral header pill; the primary action is the teal pill (`.pill`), or,
///   when destructive, the destructive pill (the error family's tint and text). Each carries the app's
///   keyboard ring, drawn only in keyboard mode. A notice (`init(notice:message:dismiss:)`, S10.8 E4)
///   has no Cancel: its one button, OK, is the teal pill.
/// - **Keyboard:** Esc cancels. Return runs the default action — the primary one, or Cancel when
///   `cancelIsDefault` (a destructive dialog, as macOS's own alerts make Cancel the default there). A
///   notice's OK takes both keys.
/// - **VoiceOver:** the dialog is one container named by its title; the buttons keep their roles.
///
/// Presented as a sheet by its owner (the window's native modality: focus stays in it, VoiceOver treats
/// it as modal, the window can't be used behind it). It paints the app's window colour itself, so the
/// sheet reads as the app's own surface.
struct AppDialog<Content: View>: View {
    let title: String
    var message: String?
    let primary: AppDialogAction
    /// Return cancels instead of acting (a destructive dialog).
    var cancelIsDefault = false
    /// Cancel — nil for a notice, whose one button is the primary.
    let cancel: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text(title)
                .font(DesignSystem.Font.sectionTitle)
                .foregroundStyle(DesignSystem.Color.label)
                .fixedSize(horizontal: false, vertical: true)
            if let message {
                Text(message)
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            HStack(spacing: ControlMetrics.pillGap) {
                Spacer(minLength: 0)
                if let cancel {
                    HeaderPillButton("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                }
                AppDialogPrimaryButton(action: primary, isDefault: !cancelIsDefault)
            }
        }
        .padding(ControlMetrics.dialogPadding)
        .frame(width: ControlMetrics.dialogWidth)
        .background(DesignSystem.Color.window)
        .background {
            // The key no visible button carries, on a hidden button (the `FilterPill` precedent; hidden,
            // it is out of the accessibility tree): Return cancels a destructive dialog, and Esc presses
            // a notice's OK.
            if let cancel {
                if cancelIsDefault {
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.defaultAction)
                        .hidden()
                }
            } else {
                Button(primary.title, action: primary.perform)
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

extension AppDialog where Content == EmptyView {
    /// A dialog with a title and message only (a confirmation).
    init(title: String, message: String?, primary: AppDialogAction, cancelIsDefault: Bool = false,
         cancel: @escaping () -> Void) {
        self.init(title: title, message: message, primary: primary, cancelIsDefault: cancelIsDefault,
                  cancel: cancel) { EmptyView() }
    }

    /// A notice: a title, a message and one OK, which Return and Esc both press — an alert with nothing to
    /// choose (a failure).
    init(notice title: String, message: String?, dismiss: @escaping () -> Void) {
        self.init(title: title, message: message, primary: AppDialogAction(title: "OK", perform: dismiss),
                  cancel: nil) { EmptyView() }
    }
}
