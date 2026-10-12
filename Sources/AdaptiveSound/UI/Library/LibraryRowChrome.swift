import SwiftUI

// MARK: - Library row chrome (S10.8 PR-D's Songs row look; shared with the detail pages in E2)

/// The card a Library song row sits on — Songs and the album, artist and genre pages: a fixed-height
/// rounded row (`LibraryRowSize`) with its content 12 pt in from the ends; filled when it is playing
/// (`rowNowPlaying`), selected (`rowSelected`) or hovered (`controlHover`); a faint teal edge on the
/// playing row; and the keyboard cursor's ring (A3). The rows' contents differ — Songs' columns, a
/// page's number, title and time — the card is one.
struct LibraryRowChrome: ViewModifier {
    let size: LibraryRowSize
    let isNowPlaying: Bool
    let isSelected: Bool
    /// The list holds key focus and this is the row its keys act on — passed in, so the row reads no
    /// environment object.
    let isKeyboardCursor: Bool

    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, LibraryRowMetrics.horizontalPadding)
            .frame(height: size.cardHeight)
            .background(fill, in: RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous))
            .overlay {
                if isNowPlaying {
                    RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                        .strokeBorder(DesignSystem.Color.accent.opacity(0.36), lineWidth: 1)
                }
            }
            .keyboardCursorRing(isKeyboardCursor, cornerRadius: size.cornerRadius)
            // The seam between two compact rows' cards (none at Songs' size) — INSIDE the hit shape,
            // so the row takes a click over its whole pitch (card + seam) and the rows tile the list
            // with no dead gap between them (S10.8 E break-it 8), as the queue's rows do.
            .padding(.vertical, size.seam / 2)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }

    private var fill: Color {
        if isNowPlaying {
            DesignSystem.Color.rowNowPlaying
        } else if isSelected {
            DesignSystem.Color.rowSelected
        } else if hover {
            DesignSystem.Color.controlHover
        } else {
            .clear
        }
    }
}

extension View {
    /// Sit a song row on the Library rows' card (`LibraryRowChrome`) — Songs' size unless told otherwise.
    func libraryRowChrome(_ size: LibraryRowSize = .regular, isNowPlaying: Bool, isSelected: Bool,
                          isKeyboardCursor: Bool) -> some View {
        modifier(LibraryRowChrome(size: size, isNowPlaying: isNowPlaying, isSelected: isSelected,
                                  isKeyboardCursor: isKeyboardCursor))
    }
}
