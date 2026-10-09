import Foundation
import Observation

// MARK: - Global transport focus gate (S4 GUI review — SW1)

/// Tracks whether a text-entry field currently holds keyboard focus, so the app's global Space
/// play/pause accelerator (the `Controls` menu key-equivalent in `AdaptiveSound`) can suppress
/// itself while the user is typing.
///
/// ## Why this exists
/// macOS matches a modifier-less menu key-equivalent in `performKeyEquivalent:` BEFORE the focused
/// field editor receives the character. Without this gate, a space typed into a Library filter
/// field (or the Save-Preset name field) is swallowed by the `Controls` → Play/Pause item and
/// toggles playback instead of inserting a space — silently breaking multi-word filtering
/// ("pink floyd"). The fix is the canonical AppKit remedy: `.disabled` the menu item while a text
/// field is being edited, so the key equivalent doesn't match and the event falls through to the
/// field editor. The `Controls` menu reads `isTextEntryFocused` in its `.disabled` condition.
///
/// ## One token per field, not a shared flag (S10.8 D fix round)
/// Fields CAN overlap: the playlist picker's pill lives in a sheet over the Songs card, whose pill
/// may hold focus underneath. With one shared Bool, the sheet's field closing wrote `false` and
/// re-enabled Space while the Songs pill still had focus. Each field now holds its own token
/// (`suppressesTransportSpace`), and Space is suppressed while ANY token is in.
@MainActor
@Observable
final class KeyboardTransportFocus {
    /// The tokens of the text fields holding key focus right now.
    private var focusedFields: Set<UUID> = []

    /// True while any text-entry field holds keyboard focus. Driven by `.suppressesTransportSpace`.
    var isTextEntryFocused: Bool {
        !focusedFields.isEmpty
    }

    /// The field holding `token` gained (`true`) or lost (`false`) key focus, or went away.
    func field(_ token: UUID, isFocused: Bool) {
        if isFocused {
            focusedFields.insert(token)
        } else {
            focusedFields.remove(token)
        }
    }
}
