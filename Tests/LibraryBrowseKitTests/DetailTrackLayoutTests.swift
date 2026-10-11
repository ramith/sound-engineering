import LibraryBrowseKit
import Testing

// MARK: - DetailTrackLayout (S10.8 E2/E3 — a detail page's song list, as shown)

/// PLAY-01: on an album, artist or genre page, a row's double-click, Return or Play plays the PAGE in
/// the order shown, from that row on (decision 11). PLAY-02: an artist page's queue is its shown order.
@Suite("DetailTrackLayout — the shown order, the numbers, and what a row plays")
struct DetailTrackLayoutTests {
    /// A minimal song: the layout is generic over `DetailTrack`, so no `LibraryTrackDisplay` fixture.
    /// (Its optionals default to nil in the memberwise init.)
    private struct Song: DetailTrack, Equatable {
        let id: Int64
        var albumID: Int64?
        var albumName: String?
        var year: Int?
        var trackNo: Int?
    }

    /// An album's read: disc / track order, one song untagged (no track number).
    private let album = [
        Song(id: 11, albumID: 1, albumName: "Roja", year: 1992, trackNo: 1),
        Song(id: 12, albumID: 1, albumName: "Roja", year: 1992, trackNo: 2),
        Song(id: 13, albumID: 1, albumName: "Roja", year: 1992, trackNo: nil),
        Song(id: 14, albumID: 1, albumName: "Roja", year: 1992, trackNo: 4),
    ]

    private func shown(_ layout: DetailTrackLayout<Song>) -> [Int64] {
        layout.items.compactMap { item in
            if case let .row(song, _) = item {
                return song.id
            }
            return nil
        }
    }

    private func numbers(_ layout: DetailTrackLayout<Song>) -> [Int?] {
        layout.items.compactMap { item in
            if case let .row(_, number) = item {
                return number
            }
            return nil
        }
    }

    // MARK: Album (E2)

    @Test("an album shows its read order, each song led by its track number — its place when untagged")
    func albumOrderAndNumbers() {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        #expect(layout.rows.map(\.id) == [11, 12, 13, 14])
        #expect(shown(layout) == [11, 12, 13, 14])
        #expect(numbers(layout) == [1, 2, 3, 4])
    }

    @Test("PLAY-01 album: a row plays the whole album from that row on", arguments: [
        (Int64(11), 0), (Int64(13), 2), (Int64(14), 3),
    ])
    func albumPlaysFromRow(id: Int64, start: Int) throws {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        let request = try #require(layout.playFromRow(id))
        #expect(request.tracks.map(\.id) == [11, 12, 13, 14])
        #expect(request.startIndex == start)
        #expect(request.tracks[request.startIndex].id == id)
    }

    @Test("PLAY-01 a row not on the page plays nothing")
    func foreignRowPlaysNothing() {
        let layout = DetailTrackLayout(tracks: album, arrangement: .album)
        #expect(layout.playFromRow(99) == nil)
        #expect(layout.index(of: 99) == nil)
    }

    @Test("an empty page has no rows and plays nothing")
    func emptyPage() {
        let layout = DetailTrackLayout(tracks: [Song](), arrangement: .album)
        #expect(layout.rows.isEmpty)
        #expect(layout.items.isEmpty)
        #expect(layout.playFromRow(11) == nil)
    }

    @Test("the selection survives the page reloading under it, by id (SEL-08 on a page)")
    func selectionSurvivesReload() {
        var selection = ListSelection<Int64>()
        let before = DetailTrackLayout(tracks: album, arrangement: .album)
        selection.click(12, extend: false, toggle: false, in: before.rows.map(\.id))
        selection.click(13, extend: true, toggle: false, in: before.rows.map(\.id))
        // A rescan: a song joins at the top, one that was not selected leaves.
        let reloaded = DetailTrackLayout(
            tracks: [Song(id: 10, albumID: 1, trackNo: 0)] + album.filter { $0.id != 14 }, arrangement: .album
        )
        let rows = reloaded.rows.map(\.id)
        #expect(selection.ids == [12, 13])
        #expect(selection.keyboardCursor(in: rows)?.id == 13)
        selection.move(.step(1), extend: true, in: rows) // ⇧↓ from the same anchor, in the new rows
        #expect(selection.ids == [12, 13]) // 13 is now last: nothing below it
        selection.move(.step(-1), extend: true, in: rows)
        #expect(selection.ids == [12])
    }
}
