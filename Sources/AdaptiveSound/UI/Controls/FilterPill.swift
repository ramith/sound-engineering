import SwiftUI

// MARK: - Filter pill (S10.8 D2 — the app's one in-place filter field)

/// The filter field: a capsule pill holding a magnifier, the text field and, while there is text,
/// a clear button. One component for every in-place filter — the Library card headers (Songs,
/// Albums, Artists, Genres) today; the queue and the playlist picker adopt it next.
///
/// It owns its focus and the transport-Space gate (`suppressesTransportSpace`), so a typed space
/// is a space, not play / pause. Escape (the macOS cancel command) clears the text, gives up focus,
/// then runs `onCancel` — where a host hands key focus back to the list it filters.
/// `focusShortcut` (the card headers pass ⌘F) focuses it from anywhere in its window. The pill
/// fills the width its host gives it; its height grows with the text size.
struct FilterPill: View {
    @Binding var text: String
    /// The placeholder, which is also the field's VoiceOver label ("Filter Albums").
    let prompt: String
    var focusShortcut: KeyboardShortcut?
    var onCancel: () -> Void = {}

    @FocusState private var focused: Bool
    /// 30 pt at the default text size (the shipped Songs pill).
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 30

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(DesignSystem.Font.caption)
                .foregroundStyle(DesignSystem.Color.labelTertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(DesignSystem.Font.body)
                .foregroundStyle(DesignSystem.Color.label)
                .suppressesTransportSpace(while: $focused)
                .onExitCommand(perform: cancel)
            if !text.isEmpty {
                Button("Clear Filter", systemImage: "xmark.circle.fill", action: clear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .help("Clear Filter")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(DesignSystem.Color.card, in: Capsule())
        .overlay(Capsule().stroke(DesignSystem.Color.hairline, lineWidth: 0.5))
        .background {
            // A hidden button keeps the shortcut installed whatever the field's state.
            if let focusShortcut {
                Button(prompt, action: focus)
                    .keyboardShortcut(focusShortcut)
                    .hidden()
            }
        }
    }

    private func focus() {
        focused = true
    }

    private func clear() {
        text = ""
    }

    private func cancel() {
        text = ""
        focused = false
        onCancel()
    }
}
