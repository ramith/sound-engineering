import DesignTokenKit
import SwiftUI

// MARK: - Filter pill (S10.8 D2 — the app's one in-place filter field)

/// The filter field: a capsule pill holding a magnifier, the text field and, while there is text,
/// a clear button. One component for every in-place filter — the Library card headers (Songs,
/// Albums, Artists, Genres), the Now Playing queue and the playlist picker. Semgrep
/// `ui-no-raw-text-field` keeps a second filter field from appearing.
///
/// It owns its focus and the transport-Space gate (`suppressesTransportSpace`), so a typed space
/// is a space, not play / pause. Escape (the macOS cancel command) clears the text, gives up focus,
/// then runs `onCancel` — where a host hands key focus back to the list it filters.
/// `focusShortcut` (the card headers and the picker pass ⌘F) focuses it from anywhere in its
/// window; `focusesOnAppear` makes it type-ready as it appears (the picker sheet). The pill fills
/// the width its host gives it; its height grows with the text size. Its horizontal geometry is Kit
/// data (`FilterPillMetrics`), so SLOT-06 can hold each host's narrowest width to the whole
/// placeholder.
struct FilterPill: View {
    @Binding var text: String
    /// The placeholder, which is also the field's VoiceOver label ("Filter Albums").
    let prompt: String
    var focusShortcut: KeyboardShortcut?
    /// Take key focus on appearing — for a sheet that opens to type in. Off by default: an in-tab
    /// filter is focused by ⌘F or a click, not on every visit.
    var focusesOnAppear = false
    var onCancel: () -> Void = {}

    @FocusState private var focused: Bool
    /// 30 pt at the default text size, like the header pills beside it.
    @ScaledMetric(relativeTo: .body) private var height = ControlMetrics.pillHeight

    var body: some View {
        HStack(spacing: CGFloat(FilterPillMetrics.itemSpacing)) {
            // SLOT-06 measures this glyph at the callout size and the text at the body size (the
            // two fonts below): change either and update the test with it.
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
                .onAppear {
                    if focusesOnAppear {
                        focused = true
                    }
                }
            if !text.isEmpty {
                Button("Clear Filter", systemImage: "xmark.circle.fill", action: clear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .help("Clear Filter")
            }
        }
        .padding(.horizontal, CGFloat(FilterPillMetrics.horizontalInset))
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
