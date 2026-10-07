import SwiftUI

// MARK: - Keyboard focus visibility → environment (S10.8 A-review)

/// Starts the app's single `KeyboardFocusVisibility` monitor and publishes its `showsFocus` as
/// the plain `showsKeyboardFocus` environment Bool. A modifier (not an inline `.environment` in
/// the scene) so the read sits in a view body, where observation re-publishes every change.
struct KeyboardFocusVisibilityPublisher: ViewModifier {
    let visibility: KeyboardFocusVisibility

    func body(content: Content) -> some View {
        content
            .environment(\.showsKeyboardFocus, visibility.showsFocus)
            .onAppear { visibility.start() }
    }
}

extension View {
    /// Window-root hook for the keyboard-focus ring rule — see `KeyboardFocusVisibility`.
    func publishesKeyboardFocusVisibility(_ visibility: KeyboardFocusVisibility) -> some View {
        modifier(KeyboardFocusVisibilityPublisher(visibility: visibility))
    }
}
