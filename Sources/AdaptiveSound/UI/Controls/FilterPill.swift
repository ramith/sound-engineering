import DesignTokenKit
import SwiftUI

// MARK: - Filter pill (S10.8 D2 — the app's one in-place filter field)

/// The filter field: a capsule pill holding a magnifier, the text field and, while there is text,
/// a clear button. One component for every in-place filter — the Library card headers (Songs,
/// Albums, Artists, Genres), the Now Playing queue and the playlist picker. Semgrep
/// `ui-no-raw-text-field` keeps a second filter field from appearing.
///
/// Its focus is ONE value of its host's `CardFocus` (K1): the pill is focused while `focus` is
/// `.filter`; the list or grid it filters binds `.content`. Escape (the macOS cancel command)
/// clears the text and hands key focus to `.content` with a single write, one main-actor turn
/// later — after the cleared filter has re-mounted a list that "no results" had replaced — so the
/// arrows work at once and focus never strands on the window. It owns the transport-Space gate
/// (`suppressesTransportSpace`), so a typed space is a space, not play / pause, and draws the app's
/// keyboard ring while it is focused in keyboard mode. `focusShortcut` (the card headers and the
/// picker pass ⌘F) focuses it from anywhere in its window; `focusesOnAppear` makes it type-ready as
/// it appears (the picker sheet). It wears the header pills' capsule (`headerPillChrome(.neutral)`,
/// like Sort beside it) and fills the width its host gives it (`filterPillWidth`); its height grows
/// with the text size. Its horizontal geometry is Kit data (`FilterPillMetrics`), so SLOT-06 can
/// hold each host's narrowest width to the whole placeholder.
struct FilterPill: View {
    @Binding var text: String
    /// The placeholder, which is also the field's VoiceOver label ("Filter Albums").
    let prompt: String
    /// The host's one focus value: `.filter` is this pill, `.content` the list it filters.
    let focus: FocusState<CardFocus?>.Binding
    var focusShortcut: KeyboardShortcut?
    /// Take key focus on appearing — for a sheet that opens to type in. Off by default: an in-tab
    /// filter is focused by ⌘F or a click, not on every visit.
    var focusesOnAppear = false

    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus

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
                .suppressesTransportSpace(while: focus, equals: .filter)
                .onExitCommand(perform: cancel)
                .onAppear {
                    if focusesOnAppear {
                        focus.wrappedValue = .filter
                    }
                }
            if !text.isEmpty {
                // Not a Tab stop of its own: the field is the pill's one stop, and Esc clears.
                Button("Clear Filter", systemImage: "xmark.circle.fill", action: clear)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .focusable(false)
                    .foregroundStyle(DesignSystem.Color.labelTertiary)
                    .help("Clear Filter")
            }
        }
        .headerPillChrome(.neutral)
        .keyboardFocusRing(focus.wrappedValue == .filter && showsKeyboardFocus, around: Capsule())
        .background {
            // A hidden button keeps the shortcut installed whatever the field's state.
            if let focusShortcut {
                Button(prompt, action: focusField)
                    .keyboardShortcut(focusShortcut)
                    .hidden()
            }
        }
    }

    private func focusField() {
        focus.wrappedValue = .filter
    }

    private func clear() {
        text = ""
    }

    /// Escape: clear now; hand focus to the content on the next main-actor turn (the
    /// `jumpToNowPlaying` idiom) — ONE focus write, after the cleared text has re-mounted the list.
    private func cancel() {
        text = ""
        Task { @MainActor in
            focus.wrappedValue = .content
        }
    }
}
