// HOR — the horizon rule (level-and-fold "The store and the scheduler", §12 F-8; the founder, 2026-10-26): the
// current slot's album, then what starts within ~2 hours, then at least three albums — never a library sweep.

import LevelingKit
import Testing

private typealias Entry = LevelingHorizon.Entry

/// `count` songs of album `album`, `seconds` each, keyed "<album>-<n>".
private func songs(_ album: Int64?, _ count: Int, seconds: Double? = 600) -> [Entry] {
    let name = album.map(String.init) ?? "loose"
    return (0 ..< count).map { Entry(key: "\(name)-\($0)", album: album, durationSeconds: seconds) }
}

@Suite("The horizon: the current album, the next ~2 hours, at least 3 albums")
struct LevelingHorizonTests {
    @Test("HOR-01: the current slot's album first and due now; the rest by when they start")
    func order() {
        let needs = LevelingHorizon.needs(upcoming: songs(1, 2) + songs(2, 1) + songs(3, 1), elapsed: 100)
        #expect(needs.map(\.target) == [.album(1), .album(2), .album(3)])
        #expect(needs.map(\.startsIn) == [0, 1100, 1700])
    }

    @Test("HOR-02: within 2 hours every album; past it, only until three albums are covered")
    func span() {
        // 10-minute songs: album 1 fills 1 h 40 min, album 2 starts at 1:40, album 3 at 2:20, album 4 at 2:30.
        let queue = songs(1, 10) + songs(2, 4) + songs(3, 1) + songs(4, 1) + songs(5, 1)
        #expect(LevelingHorizon.needs(upcoming: queue).map(\.target) == [.album(1), .album(2), .album(3)])
        // Short albums: every one starting within 2 hours, even past three.
        let short = (1 ... 6).flatMap { songs(Int64($0), 2, seconds: 300) }
        #expect(LevelingHorizon.needs(upcoming: short).count == 6)
    }

    @Test("HOR-03: a loose song is its own target within the span, and nothing past it")
    func looseSongs() {
        let queue = songs(nil, 1) + songs(1, 12) + songs(nil, 1) + songs(2, 1) + songs(3, 1)
        let needs = LevelingHorizon.needs(upcoming: queue).map(\.target)
        #expect(needs == [.track("loose-0"), .album(1), .album(2), .album(3)]) // the second loose song is past 2 h
    }

    @Test("HOR-04: an album met again (shuffle) is one target, at its first start")
    func duplicates() {
        let queue = [Entry(key: "a", album: 1, durationSeconds: 300), Entry(key: "b", album: 2, durationSeconds: 300),
                     Entry(key: "c", album: 1, durationSeconds: 300)]
        let needs = LevelingHorizon.needs(upcoming: queue)
        #expect(needs == [.init(target: .album(1), startsIn: 0), .init(target: .album(2), startsIn: 300)])
    }

    @Test("HOR-05: a length not known counts as 4 minutes, so 10,000 such songs never make a sweep")
    func unknownLengths() throws {
        let queue = (0 ..< 10000).map {
            Entry(key: "\($0)", album: Int64($0), durationSeconds: $0.isMultiple(of: 2) ? nil : 0)
        }
        let needs = LevelingHorizon.needs(upcoming: queue)
        #expect(needs.count == 30) // 2 h / 4 min
        let last = try #require(needs.last)
        #expect(last.startsIn == 29 * 240)
    }

    @Test("HOR-06: an empty queue needs nothing; the current slot is due even past its own length")
    func edges() {
        #expect(LevelingHorizon.needs(upcoming: []).isEmpty)
        let late = LevelingHorizon.needs(upcoming: songs(1, 1, seconds: 60), elapsed: 90)
        #expect(late == [.init(target: .album(1), startsIn: 0)])
    }
}
