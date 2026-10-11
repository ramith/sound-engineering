import SwiftUI

// MARK: - Library row chrome (S10.8 PR-D's Songs row look; shared with the detail pages in E2)

/// The card a Library song row sits on — Songs and the album, artist and genre pages: a fixed-height
/// rounded row with its content 12 pt in from the ends; filled when it is playing (`rowNowPlaying`),
/// selected (`rowSelected`) or hovered (`controlHover`); a faint teal edge on the playing row; and the
/// keyboard cursor's ring (A3). The rows' contents differ — Songs' columns, a page's number, title and
/// time — the card is one.
struct LibraryRowChrome: ViewModifier {
    let isNowPlaying: Bool
    let isSelected: Bool
    /// The list holds key focus and this is the row its keys act on — passed in, so the row reads no
    /// environment object.
    let isKeyboardCursor: Bool

    /// The fixed row height — also the lists' pitch (no gap between rows), from which they size a
    /// Page Up / Down and scroll a row into view by arithmetic (`FixedRowReveal`).
    static let height: CGFloat = 48
    /// The card's corner radius (fill, now-playing edge and keyboard ring share it).
    private static let cornerRadius: CGFloat = 11

    @State private var hover = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .frame(height: Self.height)
            .background(fill, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay {
                if isNowPlaying {
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(DesignSystem.Color.accent.opacity(0.36), lineWidth: 1)
                }
            }
            .keyboardCursorRing(isKeyboardCursor, cornerRadius: Self.cornerRadius)
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
    /// Sit a song row on the Library rows' card (`LibraryRowChrome`).
    func libraryRowChrome(isNowPlaying: Bool, isSelected: Bool, isKeyboardCursor: Bool) -> some View {
        modifier(LibraryRowChrome(isNowPlaying: isNowPlaying, isSelected: isSelected,
                                  isKeyboardCursor: isKeyboardCursor))
    }
}
