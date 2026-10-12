import LibraryBrowseKit
import LibraryStore
import SwiftUI

// MARK: - Song row context (S10.8 E — what a song list hands every row for its interactions)

/// What a Library song list — Songs, or an album, artist or genre page — hands each of its rows so
/// they all behave alike (`SongRowInteraction`): the list's rows and selection, its focus, and the
/// verbs. Built ONCE per list pass and shared by every row, so a row does only O(1) work of its own.
struct SongRowContext {
    /// The browse model, as a plain value: a row reads no environment object.
    let model: LibraryBrowseModel
    /// The rows shown, in display order — what a click's ⇧-range and the menu's selection act on.
    let rows: [LibraryTrackDisplay]
    let selection: Binding<ListSelection<LibraryTrackDisplay.ID>>
    /// The card's one focus value: a click gives the list key focus (`.content`).
    let focus: FocusState<CardFocus?>.Binding
    /// A row's own play — double-click, the menu's Play, VoiceOver's default action: on Songs, just
    /// that song; on a page, the page from that song on (decision 11).
    let play: (LibraryTrackDisplay) -> Void
    /// Opens the Info popover for a song.
    let showInfo: (LibraryTrackDisplay?) -> Void
    /// "Add to Playlist…": the host's searchable picker, for these songs.
    let choosePlaylist: ([Int64]) -> Void

    /// The selected songs in display order — resolved when a menu item is CHOSEN: an O(N) walk, never
    /// run while a row is built (the S10.8 End-key hang).
    func selectedTracks() -> [LibraryTrackDisplay] {
        SongsRowResolver.orderedSelection(in: rows, selection: selection.wrappedValue.ids)
    }
}
