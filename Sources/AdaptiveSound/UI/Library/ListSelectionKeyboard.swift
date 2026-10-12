import AppKit
import LibraryBrowseKit
import SwiftUI

// MARK: - Selectable list keyboard (S10.8 E1 on Songs; shared with the detail pages in E2)

/// The keyboard of a selectable custom list — Songs and the album, artist and genre pages — wired
/// once: one focus stop (the system focus effect off — the cursor row's ring is the cue, A3), and
/// the full set on the selection kit (`ListSelection`, SEL-01…08): ↑/↓ and ⇧↑/⇧↓, Home / End and
/// Page Up / Down (⇧ extends), ⌘A (Edit ▸ Select All), Esc, type-to-select on the shown title, and
/// Return, which activates the cursor row. VoiceOver hears each change of the selection's size,
/// which only the row tint shows.
///
/// The row menu's verbs have keys too, so they need neither the pointer nor VoiceOver: ⌘↩ Play
/// Next, ⇧⌘↩ Add to Queue, ⌘I Info — on the selection, or else the cursor row
/// (`ListSelection.actionTargets`). Return and its ⌘ forms act once per press: a held key does not
/// repeat them.
///
/// Any other key held with ⌘, ⌥ or ⌃ is a shortcut (`KeyPress.isShortcut`) and bubbles, as does a
/// key that moves nothing. The list supplies its rows in display order — ids and a title, nothing
/// of its columns or sort (COL-01) — and what it alone knows: its page size, how to bring the cursor
/// row into view, and what the verbs do.
struct ListSelectionKeyboard<Row: Identifiable>: ViewModifier {
    @Binding var selection: ListSelection<Row.ID>
    /// The rows shown, in display order — what every verb acts on.
    let rows: [Row]
    /// The title type-to-select matches: the one the row shows.
    let title: KeyPath<Row, String>
    /// The card's one focus value: the list is its `.content` stop.
    let focus: FocusState<CardFocus?>.Binding
    /// The cursor's ring is drawn (Return's rule: an unanchored cursor activates only while ringed).
    let ringVisible: Bool
    /// The rows a Page Up (−1) or Page Down (+1) moves — asked when the key is pressed: the visible
    /// height is not state, and a list with headers pages by what fits from the cursor's row.
    let pageRows: (_ direction: Int) -> Int
    /// Scroll the cursor row into view, after a key moved it.
    let revealCursor: () -> Void
    /// Return on row `id`: play it.
    let activate: (Row.ID) -> Void
    /// ⌘↩ — Play Next, for these rows.
    let playNext: ([Row]) -> Void
    /// ⇧⌘↩ — Add to Queue, for these rows.
    let addToQueue: ([Row]) -> Void
    /// ⌘I — Info, for this row.
    let showInfo: (Row) -> Void

    /// The keys that move the cursor.
    private static var navigationKeys: Set<KeyEquivalent> {
        [.upArrow, .downArrow, .home, .end, .pageUp, .pageDown]
    }

    /// Type-to-select keys: letters, digits, punctuation and symbols. Not Space — the app-wide play /
    /// pause key (§H) — so a search never starts or goes on with it.
    private static var typeSelectCharacters: CharacterSet {
        CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols)
    }

    func body(content: Content) -> some View {
        content
            // An empty list has no cursor row — and so is no focus stop.
            .focusable(!rows.isEmpty)
            .focused(focus, equals: .content)
            // The system effect would outline the whole list; the cursor row's ring replaces it (A3).
            .focusEffectDisabled()
            .onKeyPress(keys: Self.navigationKeys) { navigate($0) }
            // On the key-down only: a held Return must not play, or queue, again and again.
            .onKeyPress(.return, phases: .down) { returnKey($0) }
            .onKeyPress(characters: Self.typeSelectCharacters, phases: .down) { typeSelect($0) }
            .onKeyPress(keys: ["i", "I"], phases: .down) { infoKey($0) }
            // ⌘A and Edit ▸ Select All: the standard `selectAll:` action, sent to the focused list.
            .onCommand(#selector(NSStandardKeyBindingResponding.selectAll(_:))) {
                selection.selectAll(in: rowIDs)
            }
            .onExitCommand { selection.clear() } // Esc — the macOS cancel command
            // VoiceOver hears a count change it cannot see: ⇧-arrows, ⌘A and Esc change only the tint.
            .onChange(of: selection.ids.count) { _, count in
                AccessibilityNotification.Announcement(SongsAccessibility.selectionAnnouncement(count: count)).post()
            }
    }

    /// The shown rows' ids in display order, without copying them.
    private var rowIDs: LazyMapCollection<[Row], Row.ID> {
        rows.lazy.map(\.id)
    }

    /// ↑/↓, Home / End, Page Up / Down — with ⇧, extending the range from the anchor — then the
    /// cursor row into view.
    private func navigate(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut,
              selection.move(key: press.key, extend: press.modifiers.contains(.shift), in: rowIDs,
                             pageRows: pageRows)
        else { return .ignored }
        revealCursor()
        return .handled
    }

    /// Return plays the cursor row; ⌘↩ queues the targets next; ⇧⌘↩ adds them to the queue. With
    /// any other modifier it is someone else's key.
    private func returnKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.modifiers.intersection([.command, .shift, .option, .control]) {
        case []: activateCursorRow()
        case .command: act(playNext)
        case [.command, .shift]: act(addToQueue)
        default: .ignored
        }
    }

    /// ⌘I: Info for the first target. A plain "i" is type-to-select's.
    private func infoKey(_ press: KeyPress) -> KeyPress.Result {
        guard press.modifiers.intersection([.command, .shift, .option, .control]) == .command else {
            return .ignored
        }
        return act { targets in
            if let first = targets.first {
                showInfo(first)
            }
        }
    }

    /// Return: the cursor row — the ring row, or the selected cursor row while the ring is hidden
    /// (`ListSelection.activate`, which claims a ring-only row first).
    private func activateCursorRow() -> KeyPress.Result {
        guard let id = selection.activate(in: rowIDs, ringVisible: ringVisible) else { return .ignored }
        activate(id)
        return .handled
    }

    /// Runs a keyboard verb on its targets — the shown selection, or else the cursor row
    /// (`ListSelection.actionTargets`). With no target the key bubbles.
    private func act(_ verb: ([Row]) -> Void) -> KeyPress.Result {
        let ids = Set(selection.actionTargets(in: rowIDs, ringVisible: ringVisible))
        guard !ids.isEmpty else { return .ignored }
        verb(rows.filter { ids.contains($0.id) })
        return .handled
    }

    /// Type-to-select over the shown titles, in display order — on the key-down only (a held key
    /// does not repeat into the search). A key that matches nothing is still consumed, so it doesn't
    /// beep.
    private func typeSelect(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut else { return .ignored }
        if selection.typeSelect(press.characters, at: .now, in: rows, title: { $0[keyPath: title] }) != nil {
            revealCursor()
        }
        return .handled
    }
}
