// QueueHeaderWidths — the Now Playing queue header's width policy (S10.8 D2 fix round), with the
// header's parts measured as the app draws them. AppKit measures here (the TEST target); the Kit
// stays UI-free. The part metrics are the app's — the 28pt chips 4pt apart, the switch's 10pt title
// insets inside a 2pt track with 2pt gaps, the 12pt header spacing, the filter's 190pt ideal — and
// are literals because those views live in the app target; if one changes, update it here too.
// NSFont metrics ≈ (not ==) SwiftUI's, which is fine for a policy test: it asserts the rule, not
// a pixel.

import AppKit
import DesignTokenKit
import Testing

@Suite("Queue header width policy (QueueHeaderWidths)")
struct QueueHeaderWidthsTests {
    /// The queue column at the 880pt window (508) and at the default 1000pt one (628), from the
    /// Now Playing layout data, and one width between them.
    static let minimumWindow = column(window: NowPlayingLayout.windowMinWidth)
    static let defaultWindow = column(window: 1000)
    static let widths = [minimumWindow, 560, defaultWindow]

    /// The count as `FacetCountLabel` shows it: whole, else the grouped number alone.
    static let counts = [("9 tracks", "9"), ("1,234 tracks", "1,234"), ("12,345 tracks", "12,345")]

    private static func column(window: Double) -> Double {
        window - 2 * NowPlayingLayout.contentInset - NowPlayingLayout.regionGap - NowPlayingLayout.inspectorWidth
    }

    @Test("the columns under test are the design's: 508 at the 880pt window, 628 at 1000")
    func columns() {
        #expect(Self.minimumWindow == 508)
        #expect(Self.defaultWindow == 628)
    }

    @Test("Up Next at default text: one row that fits, the count whole whenever the filter can make room")
    func policyAtDefaultText() {
        let header = Header(scale: 1)
        for width in Self.widths {
            for (full, compact) in Self.counts {
                let count = header.count(full, compact)
                let plan = header.upNext(width, count)
                let countWidth = plan.widths[1]
                let filterWidth = plan.widths[4]
                let room = width - 4 * Header.spacing - header.rigid(history: false)
                let label = "\(Int(width))pt, '\(full)'"
                #expect(!plan.filterOnOwnRow, "\(label): the filter left the row")
                // Nothing overlaps: the parts and their gaps fit the column.
                #expect(plan.requiredWidth <= width + 0.001, "\(label): needs \(plan.requiredWidth)")
                #expect((Header.filterMinimum ... Header.filterIdeal).contains(filterWidth),
                        "\(label): filter \(filterWidth)")
                if count.whole + Header.filterMinimum <= room {
                    // The filter compressed first: the count is whole.
                    #expect(countWidth == count.whole, "\(label): count \(countWidth) of \(count.whole)")
                } else {
                    // The count gave way, and the filter has what it left, up to its ideal.
                    #expect(countWidth < count.whole, "\(label)")
                    #expect(abs(filterWidth - min(Header.filterIdeal, room - countWidth)) < 0.001, "\(label)")
                }
            }
        }
    }

    @Test("the default window shows every count whole; the 880pt window shows the compact or truncated form")
    func countsAtTheDesignWidths() {
        let header = Header(scale: 1)
        for (full, compact) in Self.counts {
            let count = header.count(full, compact)
            #expect(header.upNext(Self.defaultWindow, count).widths[1] == count.whole, "1000pt window, '\(full)'")
        }
        // "9": the compact form, and the filter takes back what the count doesn't use.
        let nine = header.count("9 tracks", "9")
        let narrowNine = header.upNext(Self.minimumWindow, nine)
        #expect(narrowNine.widths[1] == nine.compact)
        #expect(narrowNine.widths[4] > Header.filterMinimum)
        // "12,345": no room for even the compact form beside the filter's minimum — truncated, and
        // the filter holds its minimum (its whole placeholder).
        let large = header.count("12,345 tracks", "12,345")
        let narrowLarge = header.upNext(Self.minimumWindow, large)
        #expect(narrowLarge.widths[1] < large.compact)
        #expect(narrowLarge.widths[4] == Header.filterMinimum)
        #expect(!narrowLarge.filterOnOwnRow)
    }

    @Test("History mode (no filter, no Clear chip): the count is whole at every width")
    func historyMode() {
        let header = Header(scale: 1)
        for width in Self.widths {
            for (full, compact) in Self.counts {
                let count = header.count(full, compact)
                let plan = header.history(width, count)
                #expect(plan.widths[1] == count.whole, "\(Int(width))pt, '\(full)'")
                #expect(plan.requiredWidth <= width, "\(Int(width))pt, '\(full)'")
                #expect(!plan.filterOnOwnRow)
            }
        }
    }

    @Test("large text: the filter takes its own row instead of overlapping or widening the column")
    func largeText() {
        let header = Header(scale: 1.5)
        for width in Self.widths {
            for (full, compact) in Self.counts {
                let count = header.count(full, compact)
                let plan = header.upNext(width, count)
                let label = "\(Int(width))pt at 1.5×, '\(full)'"
                let room = width - 4 * Header.spacing - header.rigid(history: false)
                // Own row exactly when the filter's minimum no longer fits beside the rest.
                #expect(plan.filterOnOwnRow == (room < Header.filterMinimum), "\(label)")
                #expect(plan.requiredWidth <= width + 0.001, "\(label): needs \(plan.requiredWidth)")
                if plan.filterOnOwnRow {
                    // Its own row: its ideal width; the count has the first row's room to itself.
                    #expect(plan.widths[4] == Header.filterIdeal, "\(label)")
                    let firstRowRoom = width - 3 * Header.spacing - header.rigid(history: false)
                    #expect(plan.widths[1] <= max(firstRowRoom, 0) + 0.001, "\(label)")
                }
            }
        }
        // At the 880pt window the larger text does need the second row.
        let nine = header.count("9 tracks", "9")
        #expect(header.upNext(Self.minimumWindow, nine).filterOnOwnRow)
    }

    @Test("the ideal arrangement (an unbounded width): every part at its ideal, on one row")
    func idealArrangement() {
        let header = Header(scale: 1)
        let count = header.count("1,234 tracks", "1,234")
        let plan = header.upNext(.infinity, count)
        #expect(plan.widths[1] == count.whole)
        #expect(plan.widths[4] == Header.filterIdeal)
        #expect(!plan.filterOnOwnRow)
        let ideal = header.rigid(history: false) + count.whole + Header.filterIdeal + 4 * Header.spacing
        #expect(abs(plan.requiredWidth - ideal) < 0.001)
    }
}

// MARK: - The header's parts, measured

extension QueueHeaderWidthsTests {
    /// The count: its whole width and its compact width, and how it answers an offer — the first
    /// form that fits, else the compact one truncated to the offer (`ViewThatFits`).
    struct Count {
        let whole: Double
        let compact: Double

        func takes(_ offer: Double) -> Double {
            if whole <= offer {
                whole
            } else if compact <= offer {
                compact
            } else {
                min(offer, compact)
            }
        }
    }

    /// The queue header's parts at a text scale (1 = the default size), measured in the fonts the
    /// app draws them with; the chips and switch heights scale with the text, as their scaled
    /// metrics do.
    struct Header {
        static let spacing = 12.0
        static let filterMinimum = SlotWidths.queueFilter
        static let filterIdeal = 190.0

        let scale: Double

        func count(_ whole: String, _ compact: String) -> Count {
            Count(whole: mono(whole), compact: mono(compact))
        }

        /// Title + chips + switch: the parts that never give way.
        func rigid(history: Bool) -> Double {
            title(history ? "RECENTLY PLAYED" : "QUEUE") + chips(history ? 3 : 4) + switchWidth
        }

        /// Up Next: title, count, four chips, switch, filter.
        func upNext(_ width: Double, _ count: Count) -> QueueHeaderWidths {
            QueueHeaderWidths(available: width, spacing: Self.spacing,
                              idealWidths: [title("QUEUE"), count.whole, chips(4), switchWidth, Self.filterIdeal],
                              count: 1, filter: 4, filterMinimum: Self.filterMinimum, countTakes: count.takes)
        }

        /// Recently Played: no filter, and no Clear Queue chip.
        func history(_ width: Double, _ count: Count) -> QueueHeaderWidths {
            QueueHeaderWidths(available: width, spacing: Self.spacing,
                              idealWidths: [title("RECENTLY PLAYED"), count.whole, chips(3), switchWidth],
                              count: 1, filter: nil, filterMinimum: 0, countTakes: count.takes)
        }

        private func title(_ text: String) -> Double {
            measure(text, .body, .heavy, kern: 1)
        }

        private func chips(_ count: Int) -> Double {
            Double(count) * 28 * scale + Double(count - 1) * 4
        }

        private var switchWidth: Double {
            let segments = measure("Up Next", .callout, .bold) + measure("Recent", .callout, .semibold) + 4 * 10
            return segments + 2 + 2 * 2
        }

        private func mono(_ text: String) -> Double {
            let size = NSFont.preferredFont(forTextStyle: .subheadline).pointSize * scale
            let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            return NSAttributedString(string: text, attributes: [.font: font]).size().width
        }

        private func measure(_ text: String, _ style: NSFont.TextStyle, _ weight: NSFont.Weight,
                             kern: Double = 0) -> Double {
            let font = NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: style).pointSize * scale,
                                         weight: weight)
            return NSAttributedString(string: text, attributes: [.font: font, .kern: kern]).size().width
        }
    }
}
