import LibraryStore
import SwiftUI

// MARK: - Songs column catalog (§11.1/§11.2 — shared by the table + the Columns menu)

/// The stable `customizationID` set + menu metadata for the Songs columns. Single source for the
/// `SongsHeader` "Columns" menu list, the default-visibility merge, and the `SongsTable` sort-clear
/// reconcile — so the menu, the native header context-menu, and the persisted `@AppStorage` state
/// can never drift. `SongsTable` owns the matching `.customizationID`/`.defaultVisibility` per
/// column; keep this in step (and bump the `"songs.columns.vN"` key on any change).
enum SongsColumns {
    /// A hideable column in the "Columns" menu (Title/Artwork are locked-out, so absent here).
    struct Item: Identifiable {
        let id: String
        let label: String
    }

    /// Columns that carry `.defaultVisibility(.hidden)` in the table (§11.2). Needed because the
    /// `TableColumnCustomization[visibility:]` subscript returns `.automatic` for an untouched
    /// column — NOT its default — so a raw `!= .hidden` read would mis-report these as visible.
    static let defaultHidden: Set<String> = [
        "trackNo", "format", "discNo", "fileSize", "albumArtist", "genre", "playCount",
    ]

    /// The hideable columns, in physical column order (default-visible first, then default-hidden).
    static let hideable: [Item] = [
        Item(id: "artist", label: "Artist"),
        Item(id: "album", label: "Album"),
        Item(id: "time", label: "Time"),
        Item(id: "dateAdded", label: "Date Added"),
        Item(id: "quality", label: "Quality"),
        Item(id: "year", label: "Year"),
        Item(id: "trackNo", label: "Track #"),
        Item(id: "format", label: "Format"),
        Item(id: "discNo", label: "Disc #"),
        Item(id: "fileSize", label: "File Size"),
        Item(id: "albumArtist", label: "Album Artist"),
        Item(id: "genre", label: "Genre"),
        Item(id: "playCount", label: "Play Count"),
    ]

    /// The column's DEFAULT visibility — the SINGLE SOURCE that the table's per-column
    /// `.defaultVisibility(...)` modifiers read (via `SongsColumns.defaultVisibility(for:)`), so they
    /// can never drift from `defaultHidden` (which `isVisible` also uses). Adding a column to
    /// `defaultHidden` is the ONLY switch needed; a hardcoded `.hidden` in the table would be the bug.
    static func defaultVisibility(for id: String) -> Visibility {
        defaultHidden.contains(id) ? .hidden : .automatic
    }

    /// The EFFECTIVE visibility of a column: merges the stored `[visibility:]` override with the
    /// column's default (§11.2). `.automatic` follows the default; `.visible`/`.hidden` are explicit.
    static func isVisible(
        _ id: String, in custom: TableColumnCustomization<LibraryTrackDisplay>
    ) -> Bool {
        switch custom[visibility: id] {
        case .visible: true
        case .hidden: false
        default: !defaultHidden.contains(id) // .automatic (and any future case) → follow the default
        }
    }
}
