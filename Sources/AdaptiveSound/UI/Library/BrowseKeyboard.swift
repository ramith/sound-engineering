import LibraryBrowseKit
import SwiftUI

// MARK: - Browse keyboard (S10.8 decision 20 + D6 — wired once for every browse root)

/// The keyboard and the scroll memory of a browse grid or list, wired ONCE for Albums, Artists and
/// Genres: one focus stop (the system focus effect off — the cursor tile's teal ring is the cue),
/// the navigation keys, Return, type-to-select, and the place it returns to (D6). The state and
/// the rules live in `BrowseNavigator` and the Kit; this attaches them to the scroll view. Applied
/// inside the scroll view's `ScrollViewReader`.
///
/// Keys: ←/→ the previous / next tile (grids only), ↑/↓ a row, Home / End the first / last tile,
/// Page Up / Down a viewport of rows, letters type-to-select on the title, Return opens. A
/// shortcut (`KeyPress.isShortcut`: ⌘, ⌥ or ⌃ held) bubbles, as does ⇧ on the navigation keys
/// (reserved for a multi-select), so the app's shortcuts (⌘← / ⌘→ track skip) keep working.
struct BrowseKeyboard<Item: Identifiable>: ViewModifier where Item.ID == Int64 {
    let category: LibraryCategory
    /// The visible tiles, in display order.
    let items: [Item]
    /// The type-to-select key (the tile's title).
    let title: (Item) -> String
    let navigator: BrowseNavigator
    let focused: FocusState<Bool>.Binding
    let proxy: ScrollViewProxy
    let open: (Item) -> Void

    @Environment(LibraryBrowseModel.self) private var model
    @Environment(\.showsKeyboardFocus) private var showsKeyboardFocus

    /// Printable characters only — never Space (the app-wide play / pause key, matched first), Tab,
    /// Return or the arrows (control and private-use characters).
    private static var typeSelectCharacters: CharacterSet {
        CharacterSet.alphanumerics.union(.punctuationCharacters).union(.symbols)
    }

    func body(content: Content) -> some View {
        content
            // No tile = no cursor = no focus stop (the root shows "no results" instead).
            .focusable(!items.isEmpty)
            .focused(focused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .home, .end, .pageUp, .pageDown]) {
                navigate($0)
            }
            .onKeyPress(keys: [.return]) { $0.isShortcut ? .ignored : openCursorTile() }
            .onKeyPress(characters: Self.typeSelectCharacters, phases: .down) { typeSelect($0) }
            .onChange(of: focused.wrappedValue) { _, isFocused in navigator.focusChanged(isFocused) }
            .onAppear(perform: restorePlace)
            .onDisappear(perform: rememberPlace)
    }

    private var rows: [Int64] {
        items.map(\.id)
    }

    // MARK: Keys

    private func navigate(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut, !press.modifiers.contains(.shift),
              let move = arrowMove(press.key) ?? jumpMove(press.key),
              navigator.move(move, in: rows, proxy: proxy) else { return .ignored }
        return .handled
    }

    private func arrowMove(_ key: KeyEquivalent) -> GridKeyboardCursor<Int64>.Move? {
        let isGrid = navigator.arrangement == .grid
        switch key {
        case .leftArrow: return isGrid ? .left : nil
        case .rightArrow: return isGrid ? .right : nil
        case .upArrow: return .up
        case .downArrow: return .down
        default: return nil
        }
    }

    private func jumpMove(_ key: KeyEquivalent) -> GridKeyboardCursor<Int64>.Move? {
        switch key {
        case .home: .first
        case .end: .last
        case .pageUp: .pageUp(rows: navigator.pageRows)
        case .pageDown: .pageDown(rows: navigator.pageRows)
        default: nil
        }
    }

    /// Return opens the cursor tile — under `ListKeyboardCursor`'s rule: the anchored tile always,
    /// the unanchored first tile only while the ring marks it.
    private func openCursorTile() -> KeyPress.Result {
        let rows = rows
        let ringVisible = navigator.ringID(in: rows, focused: focused.wrappedValue,
                                           keyboardMode: showsKeyboardFocus) != nil
        guard let id = navigator.cursor(in: rows)?.activationTarget(ringVisible: ringVisible),
              let item = items.first(where: { $0.id == id }) else { return .ignored }
        open(item)
        return .handled
    }

    private func typeSelect(_ press: KeyPress) -> KeyPress.Result {
        guard !press.isShortcut else { return .ignored }
        navigator.typeSelect(press.characters, in: items, title: title, proxy: proxy)
        return .handled // a miss keeps the cursor; the letter is still the grid's, not a beep
    }

    // MARK: The place (D6)

    /// Coming back to this category's root: the place it left from — the scroll position, the
    /// cursor, and key focus if it had it. Used once.
    private func restorePlace() {
        guard let place = model.browsePlace, place.category == category else { return }
        model.browsePlace = nil
        navigator.restore(place, rows: rows, proxy: proxy)
        if place.wasFocused {
            focused.wrappedValue = true
        }
    }

    /// Leaving the screen while still this category's root — another tab, or "no results" while
    /// filtering: remember where it is. Opening a tile already saved its place (the route is pushed
    /// by then), and a rail jump to another category starts that root fresh.
    private func rememberPlace() {
        guard model.selectedCategory == category, model.path.isEmpty else { return }
        model.browsePlace = navigator.place(category: category, rows: rows, focused: focused.wrappedValue)
    }
}
