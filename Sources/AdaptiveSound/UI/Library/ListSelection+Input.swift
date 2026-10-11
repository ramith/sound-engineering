import AppKit
import LibraryBrowseKit
import SwiftUI

// MARK: - ListSelection ← keys and clicks (S10.8 E1; shared with the detail pages in E2)

extension ListSelection {
    /// A click on row `id`, with the current event's modifier keys: ⇧ extends from the anchor, ⌘
    /// toggles the row (`click(_:extend:toggle:in:)`).
    mutating func click(_ id: ID, modifiers: NSEvent.ModifierFlags, in rows: some Collection<ID>) {
        click(id, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command), in: rows)
    }

    /// The move a navigation key makes over `rows` (`extend` = ⇧ held): ↑/↓ a row, Page Up / Down
    /// `pageRows` rows, Home / End the first / last row. False when the key is none of them or moves
    /// nothing (an arrow past either end, an empty list), so it can bubble. The one path a key press
    /// (`ListSelectionKeyboard`) and the Songs perf run (`SongsListProbe`) both take.
    mutating func move(key: KeyEquivalent, extend: Bool, in rows: some BidirectionalCollection<ID>,
                       pageRows: Int) -> Bool {
        let movement: Movement? = switch key {
        case .upArrow: .step(-1)
        case .downArrow: .step(1)
        case .pageUp: .page(-pageRows)
        case .pageDown: .page(pageRows)
        case .home: .first
        case .end: .last
        default: nil
        }
        guard let movement else { return false }
        return move(movement, extend: extend, in: rows) != nil
    }
}
