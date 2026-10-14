import CoreGraphics
import Foundation
import ImageIO
@testable import LibraryBrowseKit
import Testing
import UniformTypeIdentifiers

// P5b council panel — adversarial / property / model tests of the browse kit (uncommitted, panel
// worktree only). Expected values come from the spec or an independent oracle, never from the kit.

/// SplitMix64, so every run is reproducible.
private struct Mix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ range: Range<Int>) -> Int {
        Int.random(in: range, using: &self)
    }

    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

@Suite("P5b browse — selection vs NSTableView, moves, grid, writer, epoch, thumbnails, layout")
struct P5bBrowseBreakTests {
    // MARK: N83 ListSelection against the real NSTableView (measured on this Mac, macOS 26)

    /// Vectors measured by the panel's NSTableView harness (exp-p5b/nstable/oracle.swift): a 10-row
    /// `NSTableView`, `allowsMultipleSelection`, clicks and keys sent as real NSEvents.
    @Test("N83 macOS reference: ⇧ after ⌘ keeps the ⌘-built rows (NSTableView T1/T2/T6)")
    func shiftAfterCommandKeepsBase() {
        let rows = Array(0 ..< 10)
        var s = ListSelection<Int>()
        s.click(1, extend: false, toggle: false, in: rows)
        s.click(4, extend: false, toggle: true, in: rows)
        s.click(7, extend: true, toggle: false, in: rows)
        #expect(s.ids == [1, 4, 5, 6, 7], "T1 NSTableView → {1,4,5,6,7}; kit → \(s.ids.sorted())")

        var t = ListSelection<Int>()
        t.click(1, extend: false, toggle: false, in: rows)
        t.click(5, extend: false, toggle: true, in: rows)
        t.move(.step(1), extend: true, in: rows)
        #expect(t.ids == [1, 5, 6], "T6 NSTableView → {1,5,6}; kit → \(t.ids.sorted())")
    }

    @Test("N83 the kit's own claim (break-it 7): ⇧-arrow after ⌘A narrows, never collapses — with an anchor")
    func selectAllThenShiftArrow() {
        let rows = Array(0 ..< 10)
        var s = ListSelection<Int>()
        s.click(9, extend: false, toggle: false, in: rows) // any earlier click leaves an anchor
        s.selectAll(in: rows)
        s.move(.step(-1), extend: true, in: rows)
        // NSTableView (measured): {0…8}. The kit's doc: "narrows the range instead of collapsing it".
        #expect(s.ids.count >= 9, "⌘A then ⇧↑ collapsed the select-all to \(s.ids.sorted())")

        var m = ListSelection<Int>()
        m.click(4, extend: false, toggle: false, in: rows)
        m.selectAll(in: rows)
        m.move(.step(1), extend: true, in: rows)
        #expect(m.ids.count >= 9, "⌘A then ⇧↓ from a middle anchor collapsed to \(m.ids.sorted())")
    }

    @Test("N83 informational: ⇧⌘-click, Home/End, arrow at an edge — where the kit and NSTableView differ")
    func documentedDifferences() {
        let rows = Array(0 ..< 10)
        var a = ListSelection<Int>()
        a.click(5, extend: false, toggle: false, in: rows)
        a.click(7, extend: true, toggle: true, in: rows)
        var b = ListSelection<Int>()
        b.click(2, extend: false, toggle: false, in: rows)
        b.move(.first, extend: false, in: rows)
        var c = ListSelection<Int>()
        c.click(1, extend: false, toggle: false, in: rows)
        c.move(.step(-1), extend: true, in: rows)
        let moved = c.move(.step(-1), extend: false, in: rows)
        print("P5b N83: ⇧⌘-click 7 after 5 → kit \(a.ids.sorted()) (NSTableView {5,7}); Home after 2 → kit \(b.ids.sorted()) (NSTableView {2}, scroll only); ↑ at the top with {0,1} → kit \(c.ids.sorted()) moved=\(String(describing: moved)) (NSTableView {0})")
    }

    // MARK: N83 random model test — invariants under filters, re-sorts and reloads

    @Test("N83 invariants over 20 000 random operation sequences (filters, re-sorts, reloads)")
    func selectionInvariants() {
        var rng = Mix(state: 83)
        let universe = Array(0 ..< 12)
        var collapses = 0
        var selectAllShiftCases = 0
        for _ in 0 ..< 20000 {
            var s = ListSelection<Int>()
            var visible = universe
            var present = universe // what a reload left
            var justSelectedAll = false
            for _ in 0 ..< 14 {
                let before = s
                let op = rng.int(0 ..< 13)
                let target = visible.isEmpty ? 0 : visible[rng.int(0 ..< visible.count)]
                switch op {
                case 0, 1:
                    guard !visible.isEmpty else { continue }
                    s.click(target, extend: false, toggle: false, in: visible)
                    #expect(s.ids == [target] && s.anchor == target && s.cursor == target)
                case 2:
                    guard !visible.isEmpty else { continue }
                    let anchorVisible = s.anchor.map(visible.contains) ?? false
                    let anchor = s.anchor
                    s.click(target, extend: true, toggle: false, in: visible)
                    if anchorVisible, let anchor, let i = visible.firstIndex(of: anchor),
                       let j = visible.firstIndex(of: target) {
                        #expect(s.ids == Set(visible[min(i, j) ... max(i, j)]))
                        #expect(s.anchor == anchor && s.cursor == target)
                    } else {
                        #expect(s.ids == [target])
                    }
                case 3:
                    guard !visible.isEmpty else { continue }
                    s.click(target, extend: false, toggle: true, in: visible)
                    #expect(s.ids == before.ids.symmetricDifference([target]))
                    #expect(s.anchor == target && s.cursor == target)
                case 4, 5, 6, 7:
                    let extend = op >= 6
                    let delta = op.isMultiple(of: 2) ? 1 : -1
                    let anchorBefore = s.anchor
                    let landed = s.move(.step(delta), extend: extend, in: visible)
                    if landed == nil {
                        #expect(s.ids == before.ids && s.anchor == before.anchor && s.cursor == before.cursor)
                    } else if extend, justSelectedAll, visible.count >= 3 {
                        selectAllShiftCases += 1
                        if s.ids.count < visible.count - 1 {
                            collapses += 1
                        }
                    }
                    if let landed, extend, let anchorBefore, let i = visible.firstIndex(of: anchorBefore),
                       let j = visible.firstIndex(of: landed) {
                        #expect(s.ids == Set(visible[min(i, j) ... max(i, j)]))
                    }
                case 8:
                    s.selectAll(in: visible)
                    #expect(s.ids == Set(visible))
                case 9: // a filter: hide some rows (order kept)
                    visible = present.filter { _ in rng.int(0 ..< 4) != 0 }
                case 10: // a re-sort
                    visible.shuffle(using: &rng)
                case 11: // a reload: rows go away for good
                    present = universe.filter { _ in rng.int(0 ..< 5) != 0 }
                    visible = present
                    s.keepOnly(present)
                    #expect(s.ids.isSubset(of: Set(present)))
                    #expect(s.anchor.map(present.contains) ?? true)
                    #expect(s.cursor.map(present.contains) ?? true)
                default:
                    s.clear()
                    #expect(s.ids.isEmpty && s.anchor == nil && s.cursor == before.cursor)
                }
                justSelectedAll = op == 8
                // Global invariants.
                let ring = s.keyboardCursor(in: visible)
                #expect((ring == nil) == visible.isEmpty)
                if let ring {
                    #expect(visible.contains(ring.id))
                }
                let targets = s.actionTargets(in: visible, ringVisible: true)
                #expect(Set(targets).count == targets.count && targets.allSatisfy(visible.contains))
                let shownSelected = visible.filter(s.ids.contains)
                if !shownSelected.isEmpty {
                    #expect(targets == shownSelected)
                }
                for row in visible {
                    let menu = s.menuActsOnSelection(clicked: row, in: visible)
                    #expect(menu == (s.ids.contains(row) && shownSelected.count >= 2))
                }
            }
        }
        print("P5b N83: ⇧-arrow right after ⌘A on ≥ 3 rows: \(selectAllShiftCases) cases, \(collapses) collapsed (> 1 row lost)")
        #expect(collapses == 0, "⇧-arrow after ⌘A collapsed the selection in \(collapses)/\(selectAllShiftCases) cases")
    }

    // MARK: N79 ListMove — exhaustive spec check, n ≤ 8, every subset, every move

    @Test("N79 every subset of up to 8 rows, every move: spec placement, block, relative orders, availability")
    func listMoveExhaustive() {
        var checked = 0
        for n in 0 ... 8 {
            let rows = Array(0 ..< n)
            for mask in 0 ..< (1 << n) {
                let selected = Set(rows.filter { mask & (1 << $0) != 0 })
                let positions = rows.filter(selected.contains)
                for move in ListMove.allCases {
                    checked += 1
                    let result = move.reordering(rows, moving: selected)
                    #expect((result != nil) == move.isAvailable(forRowsAt: positions, count: n))
                    guard let first = positions.first, let last = positions.last else {
                        #expect(result == nil)
                        continue
                    }
                    let isBlock = last - first + 1 == positions.count
                    let atEdge: Bool = switch move {
                    case .toTop, .up: isBlock && first == 0
                    case .down, .toBottom: isBlock && last == n - 1
                    }
                    #expect((result == nil) == atEdge, "n=\(n) mask=\(mask) \(move)")
                    guard let result else { continue }
                    #expect(result.sorted() == rows)
                    #expect(result.filter(selected.contains) == positions)
                    #expect(result.filter { !selected.contains($0) } == rows.filter { !selected.contains($0) })
                    let start = result.firstIndex(of: positions[0])!
                    #expect(Array(result[start ..< start + positions.count]) == positions)
                    switch move {
                    case .toTop: #expect(start == 0)
                    case .toBottom: #expect(start + positions.count - 1 == n - 1)
                    case .up: #expect(start == max(0, first - 1))
                    case .down: #expect(start + positions.count - 1 == min(n - 1, last + 1))
                    }
                }
            }
        }
        #expect(checked > 2000)
    }

    // MARK: N84 grid cursor — exhaustive against a 2-D (row, column) oracle

    @Test("N84 every grid of 0…40 tiles × 1…9 columns, every position, every key, anchored and seeded")
    func gridCursorExhaustive() {
        var checked = 0
        for count in 0 ... 40 {
            let tiles = Array(100 ..< 100 + count)
            for columns in 1 ... 9 {
                let lastRow = count == 0 ? 0 : (count - 1) / columns
                let keys: [GridKeyboardCursor<Int>.Move] = [.left, .right, .up, .down, .first, .last,
                                                            .pageUp(rows: 0), .pageUp(rows: 2), .pageUp(rows: 1000),
                                                            .pageDown(rows: -3), .pageDown(rows: 2), .pageDown(rows: 1000)]
                // Anchored, every position.
                for position in 0 ..< count {
                    let cursor = GridKeyboardCursor.resolve(rows: tiles, anchor: tiles[position], columns: columns)!
                    let (row, column) = (position / columns, position % columns)
                    for key in keys {
                        checked += 1
                        let want: Int? = switch key {
                        case .left: position > 0 ? position - 1 : nil
                        case .right: position < count - 1 ? position + 1 : nil
                        case .up: row > 0 ? position - columns : nil
                        case .down: row < lastRow ? min((row + 1) * columns + column, count - 1) : nil
                        case .first: 0
                        case .last: count - 1
                        case let .pageUp(rows): max(0, row - max(1, rows)) * columns + column
                        case let .pageDown(rows): min(min(lastRow, row + max(1, rows)) * columns + column, count - 1)
                        }
                        let got = cursor.target(of: key, in: tiles).map { $0 - 100 }
                        #expect(got == want, "n=\(count) c=\(columns) p=\(position) \(key): got \(String(describing: got)) want \(String(describing: want))")
                    }
                }
                // The unanchored seed (tile 0): an arrow that would leave the grid claims it in place.
                if count > 0 {
                    let seed = GridKeyboardCursor.resolve(rows: tiles, anchor: nil, columns: columns)!
                    #expect(seed.id == 100)
                    #expect(seed.target(of: .left, in: tiles) == 100)
                    #expect(seed.target(of: .up, in: tiles) == 100)
                    #expect(seed.target(of: .right, in: tiles) == (count > 1 ? 101 : 100))
                    #expect(seed.target(of: .down, in: tiles) == (lastRow > 0 ? 100 + min(columns, count - 1) : 100))
                } else {
                    #expect(GridKeyboardCursor.resolve(rows: tiles, anchor: nil, columns: columns) == nil)
                }
            }
        }
        #expect(checked > 50000)
    }

    // MARK: N85 / N86 grid layout math

    @Test("N85/N86 columns are the most that fit; tile fills the width; hostile inputs stay sane")
    func gridLayoutProperties() {
        var rng = Mix(state: 85)
        for index in 0 ..< 200_000 {
            let integral = index.isMultiple(of: 2)
            let width = integral ? Double(rng.int(0 ..< 4000)) : rng.unit() * 4000
            let minimum = integral ? Double(rng.int(1 ..< 400)) : rng.unit() * 400 + 0.01
            let spacing = integral ? Double(rng.int(0 ..< 40)) : rng.unit() * 40
            let columns = GridLayoutMath.columnsThatFit(width: width, minimum: minimum, spacing: spacing)
            // Oracle: the largest c ≥ 1 with c·m + (c − 1)·s ≤ w, by counting.
            var fit = 1
            while Double(fit + 1) * minimum + Double(fit) * spacing <= width, fit < 1000 {
                fit += 1
            }
            let ratio = (width + spacing) / (minimum + spacing)
            if abs(ratio - ratio.rounded()) > 1e-9 {
                #expect(columns == fit, "w=\(width) m=\(minimum) s=\(spacing): \(columns) vs \(fit)")
            }
            for minimumColumns in [1, 2, 3] {
                let layout = FillGridLayout(width: width, minimumTile: minimum, spacing: spacing,
                                            minimumColumns: minimumColumns)
                #expect(layout.columns == max(minimumColumns, columns))
                #expect(layout.tileWidth.isFinite && layout.tileWidth >= 0)
                let used = Double(layout.columns) * layout.tileWidth + Double(layout.columns - 1) * spacing
                if layout.tileWidth > 0 {
                    #expect(abs(used - width) < 1e-6 * max(1, width), "ragged right edge")
                }
                if columns >= minimumColumns, minimum <= width, abs(ratio - ratio.rounded()) > 1e-9 {
                    #expect(layout.tileWidth >= minimum - 1e-9, "tile below its minimum")
                }
            }
        }
        for hostile in [Double.nan, -.infinity, .infinity, -1, 0, 1e308, .leastNonzeroMagnitude] {
            for m in [Double.nan, 0, -5, 160] {
                let c = GridLayoutMath.columnsThatFit(width: hostile, minimum: m, spacing: 12)
                #expect((1 ... 1000).contains(c))
                let layout = FillGridLayout(width: hostile, minimumTile: m, spacing: 12, minimumColumns: 2)
                #expect(layout.tileWidth.isFinite && layout.tileWidth >= 0)
                #expect((1 ... 1000).contains(GridLayoutMath.rowsPerPage(viewportHeight: hostile, rowPitch: m)))
            }
        }
    }

    // MARK: N80 CoalescingWriter — a model test over random submit / completion schedules

    @MainActor
    @Test("N80 random schedules: one write in flight, FIFO turns, newest per key, no stale after newer, nothing lost")
    func coalescingWriterModel() async {
        var rng = Mix(state: 80)
        for trial in 0 ..< 300 {
            let gate = GatedSink()
            var counter = 0
            var modelTurns: [Int] = []
            var modelWaiting: [Int: Int] = [:]
            var lastSubmitted: [Int: Int] = [:]
            var processedStarts = 0
            var writingNow: (Int, Int)?
            func settle() async {
                for _ in 0 ..< 400 {
                    await Task.yield()
                }
                #expect(gate.started.count - processedStarts <= 1)
                while processedStarts < gate.started.count {
                    let (key, value) = gate.started[processedStarts]
                    processedStarts += 1
                    let want = modelTurns.isEmpty ? nil : modelTurns.removeFirst()
                    #expect(key == want, "trial \(trial): write started for \(key), FIFO turn says \(String(describing: want))")
                    #expect(value == modelWaiting.removeValue(forKey: key), "trial \(trial): not the newest value")
                    writingNow = (key, value)
                }
                if gate.pending == nil {
                    writingNow = nil // nothing in flight: the last write returned
                }
                for key in 0 ..< 3 {
                    let want = modelWaiting[key] ?? (writingNow?.0 == key ? writingNow?.1 : nil)
                    #expect(gate.writer.unsavedValue(for: key) == want, "trial \(trial) key \(key)")
                }
            }
            for _ in 0 ..< 30 {
                if rng.int(0 ..< 10) < 6 {
                    let key = rng.int(0 ..< 3)
                    counter += 1
                    if modelWaiting[key] == nil {
                        modelTurns.append(key)
                    }
                    modelWaiting[key] = counter
                    lastSubmitted[key] = counter
                    gate.writer.submit(counter, for: key)
                } else {
                    gate.completeOne()
                }
                await settle()
            }
            var guardSteps = 0
            while gate.pending != nil || !modelWaiting.isEmpty, guardSteps < 200 {
                gate.completeOne()
                await settle()
                guardSteps += 1
            }
            await gate.writer.flush()
            #expect(gate.maxInFlight <= 1)
            for key in 0 ..< 3 {
                let values = gate.written.filter { $0.0 == key }.map(\.1)
                #expect(values == values.sorted() && Set(values).count == values.count, "older after newer: \(values)")
                #expect(values.last == lastSubmitted[key], "trial \(trial): key \(key) final write lost")
                #expect(gate.writer.unsavedValue(for: key) == nil)
            }
        }
    }

    // MARK: N72 SearchEpoch — the reload path

    @Test("N72 two reads under ONE epoch (a filtered reload, then another) finishing out of order: the older wins")
    func searchEpochSameEpochReads() {
        // LibraryBrowseModel.runFilter captures `searchEpoch.value` and publishes when still current;
        // only an EDIT invalidates (searchQuery didSet). reloadIfScanChanged calls runFilter with no edit,
        // and LibraryTabView starts each reload in its own unstructured Task; the store reads on a
        // DatabasePool (concurrent readers), so two reads can complete in either order.
        var epoch = SearchEpoch()
        epoch.invalidate() // the user typed the query once
        let olderRead = epoch.value // reload for revision N (snapshot without the new song)
        let newerRead = epoch.value // reload for revision N+1 (snapshot with it)
        var published: Set<Int64>?
        let newerResult: Set<Int64> = [1, 2, 3]
        let olderResult: Set<Int64> = [1, 2]
        if epoch.isCurrent(newerRead) {
            published = newerResult // the newer read lands first
        }
        if epoch.isCurrent(olderRead) {
            published = olderResult // the older read lands last and overwrites it
        }
        #expect(published == newerResult, "the stale snapshot \(String(describing: published)) was published last")
    }

    // MARK: N73 / N81 — non-Latin queries (cross-check of P5A-04 on the UI side)

    @Test("N73/N81 the 2-character gate and the type-select match on Sinhala and CJK")
    func nonLatinGateAndTypeSelect() {
        let oneSyllable = "කා" // ka + the aa vowel sign: 2 scalars, 2 keystrokes, 1 grapheme
        let oneIdeograph = "愛" // a whole word
        print("P5b N73: shouldQuery(\"කා\") = \(SearchQueryGate.shouldQuery(oneSyllable)) (\(oneSyllable.unicodeScalars.count) scalars, \(oneSyllable.count) grapheme); shouldQuery(\"愛\") = \(SearchQueryGate.shouldQuery(oneIdeograph))")
        // Type-select: "මා" (maa) must not land on "මිල" (mila, price) before "මාල" (maala, necklace).
        let titles = ["මිල", "මාල"]
        let match = TypeSelectBuffer.firstMatch(for: "මා", in: titles, title: { $0 })
        #expect(match == "මාල", "type-select \"මා\" landed on \(String(describing: match))")
    }

    // MARK: N88 ThumbnailUpgrade — with the REAL ImageIO decode the app uses

    @Test("N88 ImageIO can come out 1 px under the request from a larger source → 'whole image' → never upgraded")
    func thumbnailUndershoot() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("p5b-thumb-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A stored thumbnail exactly as ArtworkCache keeps a cover smaller than 512 px (measured case).
        let url = folder.appendingPathComponent("stored.jpg")
        let (width, height) = (506, 185)
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        // ArtworkThumbnailStore.decode's exact options.
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let request = 64
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: request,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        let decoded = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary))
        let side = max(decoded.width, decoded.height)
        let servesUpTo = ThumbnailUpgrade.servesUpTo(decodedSide: side, requested: request)
        print("P5b N88: \(width)x\(height) source, request \(request) → \(decoded.width)x\(decoded.height); servesUpTo = \(servesUpTo)")
        // The source is 506 px: a later 320-px grid tile must NOT be served the \(side)-px decode.
        #expect(!ThumbnailUpgrade.serves(servesUpTo, request: 320), "a \(side)-px decode is served for a 320-px tile, for good")
    }

    // MARK: N87 FixedRowReveal — reveals, and moves as little as possible

    @Test("N87 FixedRowReveal: the span ends up in view, by the minimal move; nil only when already in view")
    func fixedRowRevealProperties() {
        var rng = Mix(state: 87)
        for _ in 0 ..< 200_000 {
            let rowHeight = Double(rng.int(10 ..< 60))
            let inset = Double(rng.int(0 ..< 20))
            let height = Double(rng.int(20 ..< 1200))
            let index = rng.int(0 ..< 2000)
            let visibleTop = Double(rng.int(0 ..< 80000))
            let top = Double(index) * rowHeight
            let bottom = top + rowHeight + 2 * inset
            let offset = FixedRowReveal.offset(revealing: index, rowHeight: rowHeight, inset: inset,
                                               visibleTop: visibleTop, visibleHeight: height)
            let inView = top >= visibleTop && bottom <= visibleTop + height
            #expect((offset == nil) == inView)
            if let offset, bottom - top <= height {
                #expect(top >= offset && bottom <= offset + height, "not revealed")
                let minimalMove = top < visibleTop ? visibleTop - top : bottom - (visibleTop + height)
                #expect(abs(abs(offset - visibleTop) - minimalMove) < 1e-9, "not the minimal move")
            }
        }
    }

    // MARK: N75 / N77 — album order is input-order free; row spans match the drawn items

    @Test("N75/N77 AlbumTrackOrder ignores read order (distinct titles); spans = an item-by-item height walk")
    func detailLayoutOracle() {
        var rng = Mix(state: 77)
        let metrics = DetailListMetrics(rowHeight: 30, albumHeaderHeight: 52, discHeaderHeight: 24)
        for trial in 0 ..< 3000 {
            let count = rng.int(1 ..< 30)
            var songs: [DetailTestSong] = []
            for index in 0 ..< count {
                let album = rng.int(0 ..< 5)
                songs.append(DetailTestSong(
                    id: Int64(index), title: "t\(rng.int(0 ..< 1000))-\(index)",
                    albumID: album == 0 ? nil : Int64(album), albumName: album == 0 ? nil : "A\(album)",
                    year: rng.int(0 ..< 3) == 0 ? nil : 1990 + rng.int(0 ..< 4),
                    discNo: rng.int(0 ..< 3) == 0 ? nil : rng.int(-1 ..< 3),
                    trackNo: rng.int(0 ..< 4) == 0 ? nil : rng.int(-1 ..< 12)
                ))
            }
            let albumSongs = songs.filter { $0.albumID == 1 }
            if !albumSongs.isEmpty {
                let once = AlbumTrackOrder.playing(albumSongs).map(\.track.id)
                let shuffled = AlbumTrackOrder.playing(albumSongs.shuffled(using: &rng)).map(\.track.id)
                #expect(once == shuffled, "trial \(trial): order depends on the read")
            }
            for arrangement in [DetailTrackArrangement.byAlbum, .flat] {
                let layout = DetailTrackLayout(tracks: songs, arrangement: arrangement)
                #expect(layout.rows.map(\.id).sorted() == songs.map(\.id).sorted(), "rows are not the songs")
                var y = 0.0
                var lead = 0.0
                var rowIndex = 0
                for item in layout.items {
                    switch item {
                    case .header:
                        y += metrics.albumHeaderHeight
                        lead += metrics.albumHeaderHeight
                    case .discHeader:
                        y += metrics.discHeaderHeight
                        lead += metrics.discHeaderHeight
                    case let .row(track, _, _):
                        let span = layout.span(ofRow: rowIndex, metrics: metrics)
                        #expect(abs(span.top + lead - y) < 1e-9 && abs(span.height - metrics.rowHeight - lead) < 1e-9,
                                "trial \(trial) row \(rowIndex)")
                        #expect(layout.index(of: track.id) == rowIndex)
                        y += metrics.rowHeight
                        lead = 0
                        rowIndex += 1
                    }
                }
            }
        }
    }

    // MARK: N89 PlaylistAddDecision / drop router

    @Test("N89 dedupe keeps first-seen order (vs NSOrderedSet)")
    func addDecisionOracle() {
        var rng = Mix(state: 89)
        for _ in 0 ..< 5000 {
            let ids = (0 ..< rng.int(0 ..< 30)).map { _ in Int64(rng.int(0 ..< 10)) }
            let oracle = NSOrderedSet(array: ids).array.compactMap { $0 as? Int64 }
            #expect(PlaylistAddDecision.trackIDsToAdd(ids) == oracle)
            #expect(PlaylistDropRouter.route(droppedTrackIDs: ids) == .addTracks(oracle))
        }
    }
}

/// A sink that holds each write open until the test completes it.
@MainActor
private final class GatedSink {
    var pending: CheckedContinuation<Void, Never>?
    var started: [(Int, Int)] = []
    var written: [(Int, Int)] = []
    var inFlight = 0
    var maxInFlight = 0
    var writer: CoalescingWriter<Int, Int>!

    init() {
        writer = CoalescingWriter { [unowned self] key, value in
            await self.write(key, value)
        }
    }

    private func write(_ key: Int, _ value: Int) async {
        inFlight += 1
        maxInFlight = max(maxInFlight, inFlight)
        started.append((key, value))
        await withCheckedContinuation { continuation in
            pending = continuation
        }
        written.append((key, value))
        inFlight -= 1
    }

    func completeOne() {
        if let continuation = pending {
            pending = nil
            continuation.resume()
        }
    }
}
