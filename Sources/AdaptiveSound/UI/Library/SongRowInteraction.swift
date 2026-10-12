import AppKit
import LibraryStore
import SwiftUI

// MARK: - Song row interaction (S10.8 E — one behaviour for Songs' rows and the pages' rows)

/// Everything a Library song row DOES, in one place for Songs and the album, artist and genre pages
/// — the rows differ only in what they draw. The row is a plain button (a `List(selection:)` row
/// races a double-click and drops clicks on macOS):
/// - a click selects — ⇧ extends from the anchor, ⌘ toggles — and gives the list key focus;
/// - a double-click plays the row (`SongRowContext.play`: the song on Songs, the page from that song
///   on a page);
/// - it drags onto a sidebar playlist (US-PLIST-03) — a reference-add by id, never a file move;
/// - the song menu (`LibrarySongMenu`), on the selection when this row is one of several selected;
/// - ONE VoiceOver element: play as its default action, then Play Next, Add to Queue, Add to
///   Playlist… and Info as named actions, so every verb the menu has is reachable without it.
/// It is no focus stop of its own: the LIST is the one Tab stop and the cursor ring its cue.
struct SongRowInteraction: ViewModifier {
    let track: LibraryTrackDisplay
    let context: SongRowContext
    /// The row's spoken name and value — composed by its list from the track, not the visible cells.
    let label: String
    let value: String

    func body(content: Content) -> some View {
        let isSelected = context.selection.wrappedValue.contains(track.id)
        Button(action: click) {
            content
        }
        .buttonStyle(.plain)
        .focusable(false)
        .draggable(LibraryTrackDragItem(trackID: track.id))
        .simultaneousGesture(TapGesture(count: 2).onEnded { play() })
        .contextMenu {
            LibrarySongMenu(clicked: track,
                            actsOnSelection: context.selection.wrappedValue.menuActsOnSelection(clicked: track.id),
                            selectedTracks: context.selectedTracks, playClicked: play,
                            showInfo: context.showInfo, choosePlaylist: context.choosePlaylist)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, play)
        .accessibilityAction(named: Text("Play Next"), playNext)
        .accessibilityAction(named: Text("Add to Queue"), addToQueue)
        .accessibilityAction(named: Text("Add to Playlist…"), addToPlaylist)
        .accessibilityAction(named: Text("Info"), showInfo)
    }

    /// A click: the list takes key focus, and the selection follows the modifier keys held.
    private func click() {
        context.focus.wrappedValue = .content
        context.selection.wrappedValue.click(track.id, modifiers: NSEvent.modifierFlags,
                                             in: context.rows.lazy.map(\.id))
    }

    private func play() {
        context.play(track)
    }

    private func playNext() {
        context.model.playNext([track])
    }

    private func addToQueue() {
        context.model.append([track])
    }

    private func addToPlaylist() {
        context.choosePlaylist([track.id])
    }

    private func showInfo() {
        context.showInfo(track)
    }
}

extension View {
    /// Make this row's content a Library song row (`SongRowInteraction`): click, double-click, drag,
    /// menu and VoiceOver.
    func songRowInteraction(_ track: LibraryTrackDisplay, in context: SongRowContext, label: String,
                            value: String) -> some View {
        modifier(SongRowInteraction(track: track, context: context, label: label, value: value))
    }
}
