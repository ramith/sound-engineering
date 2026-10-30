@testable import AdaptiveSound
import AppKit
import SettingsKit
import SwiftUI
import Testing

// MARK: - The shared note fits its card (R1.1-B fix round, F4: review-ui S6)

//
// The note's words were `.fixedSize()` on both axes in both of its layouts. In the stacked layout — the narrow rail
// cards, about 210 pt, and anything narrower at a larger text size — the words could not wrap, and `ViewThatFits`
// falls back to its last child even when that child doesn't fit: the words ran past the card's edge. Stacked, they
// wrap; on one line they stay whole.

@MainActor
@Suite("The shared note wraps in a narrow card (S6)", .timeLimit(.minutes(1)))
struct BitPerfectRowNoteTests {
    private static func width(of row: DSPRow, offered width: CGFloat) -> CGFloat {
        let note = BitPerfectRowNote(row: row, availability: .notInBitPerfectMode(leaving: false), leavePure: {})
        return NSHostingController(rootView: note).sizeThatFits(in: CGSize(width: width, height: 400)).width
    }

    @Test("NOTE-01: offered less than its words need, the note wraps within the width — never past it",
          arguments: DSPRow.allCases)
    func noteWrapsInANarrowCard(row: DSPRow) {
        let natural = Self.width(of: row, offered: 2000)
        let narrow = (natural * 0.6).rounded()
        #expect(Self.width(of: row, offered: narrow) <= narrow, "\(row): the note ran past a \(narrow) pt card")
    }
}
