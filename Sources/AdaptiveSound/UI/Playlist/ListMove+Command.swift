import LibraryBrowseKit
import SwiftUI

// MARK: - ListMove + command (S10.8 E4 — the playlist's Move titles and shortcuts)

/// Each move's menu title and shortcut — ONE table, read by the row context menu (which shows the
/// shortcut) and by the playlist list's key handler (which matches it), so the two can't drift.
///
/// ⌥⌘↑ / ⌥⌘↓ move one place; adding ⇧ goes all the way (⌥⇧⌘↑ / ⌥⇧⌘↓). ⌘↑ / ⌘↓ is the Mac's "to the
/// start / end" family and ⌥ its alternate, act-on-the-item form. No chord is taken by the app's
/// menus (Controls: Space, ⌘← / ⌘→, ⌘., ⌘0) or by macOS, whose arrow chords sit elsewhere:
/// ⌃-arrows are Mission Control and Spaces, window tiling is 🌐⌃-arrows, VoiceOver is ⌃⌥-arrows.
extension ListMove {
    var title: String {
        switch self {
        case .toTop: "Move to Top"
        case .up: "Move Up"
        case .down: "Move Down"
        case .toBottom: "Move to Bottom"
        }
    }

    var arrow: KeyEquivalent {
        switch self {
        case .toTop, .up: .upArrow
        case .down, .toBottom: .downArrow
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .up, .down: [.option, .command]
        case .toTop, .toBottom: [.option, .shift, .command]
        }
    }

    /// The move a key press asks for — its exact chord on ↑ or ↓ — else nil. Only the four chord
    /// modifiers are compared: an arrow key's event also carries the numeric-pad flag, and Caps
    /// Lock must not matter.
    init?(_ press: KeyPress) {
        let chord = press.modifiers.intersection([.shift, .control, .option, .command])
        guard let move = Self.allCases.first(where: { $0.arrow == press.key && $0.modifiers == chord }) else {
            return nil
        }
        self = move
    }
}
