import SwiftUI

// MARK: - App dialog primary button (S10.8 EQ fix)

/// A dialog's primary action as its pill: the teal pill for Save or Rename, the destructive pill for
/// Delete — with the app's keyboard ring, disabled while it can't act, and Return when it is the
/// dialog's default.
struct AppDialogPrimaryButton: View {
    let action: AppDialogAction
    let isDefault: Bool

    var body: some View {
        Group {
            switch action.tone {
            case .accent:
                Button(action.title, action: action.perform)
                    .buttonStyle(.pill)
                    .controlSize(.large)
                    .controlFocusRing(around: Capsule(style: .circular))
            case .destructive:
                HeaderPillButton(action.title, tone: .destructive, role: .destructive, action: action.perform)
            }
        }
        .keyboardShortcut(isDefault ? .defaultAction : nil)
        .disabled(!action.isEnabled)
    }
}
