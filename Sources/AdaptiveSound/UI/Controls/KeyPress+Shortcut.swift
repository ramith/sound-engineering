import SwiftUI

// MARK: - Shortcut key presses (S10.8 grid-fix)

extension KeyPress {
    /// The press is a SHORTCUT: it carries ⌘, ⌥ or ⌃. A custom list's navigation keys and
    /// type-to-select let it pass, so the shortcut reaches its own handler — ⌘← / ⌘→ skip tracks,
    /// ⌥⌘↑ / ↓ move a playlist entry (E4). A focused list that took them would act on its own rows
    /// instead (the rail switched playlists on ⌥⌘↓). ⇧ alone is not a shortcut: it types capitals.
    var isShortcut: Bool {
        !modifiers.isDisjoint(with: [.command, .option, .control])
    }
}
