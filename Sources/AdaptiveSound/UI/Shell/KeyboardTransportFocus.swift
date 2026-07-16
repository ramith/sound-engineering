import SwiftUI

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
/// ## Why a single flag is safe
/// These fields are never focused simultaneously — the Library filter fields live in mutually
/// exclusive tabs/sections and the Save-Preset field is a modal sheet — so there is never a second
/// focused field whose state a shared flag could clobber.
///
/// ## Wiring
/// Fields wire this via the `.suppressesTransportSpace(while:)` modifier (see
/// `TransportSpaceSuppressing`), which owns the `.focused` + `.onChange` + `.onDisappear` trio in one
/// place so a field can't half-wire it. (A later hardening could make this a `Set<FieldID>` or derive
/// it from the AppKit first responder to also close the focus-handoff transposition race — focus-audit.)
@MainActor
@Observable
final class KeyboardTransportFocus {
    /// True while a text-entry field holds keyboard focus. Driven by `.suppressesTransportSpace(while:)`.
    var isTextEntryFocused = false
}
