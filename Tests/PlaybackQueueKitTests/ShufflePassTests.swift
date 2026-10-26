import Foundation
import PlaybackQueueKit
import Testing

// MARK: - ShufflePass — shuffle as a permutation with history (R1.1-B; council C-16, KI-PB-03) (VM-SP)

//
// The shipped `ShufflePass`, seeded, so each case reproduces. Slots are the queue's rows (Ints). The
// plan check's §6 "Shuffle with history, Repeat off" counter-examples are named where they are proven;
// the view model's wiring of the same rules is `ShuffleTransportTests` in AdaptiveSoundTests.

/// Repeat modes, as `AudioViewModel.repeatMode` numbers them.
private let repeatOff = 0
private let repeatAll = 1
private let repeatOne = 2

/// Let a pass play itself out under `repeatMode`: every song that starts, in order, beginning with the
/// one playing — `limit` songs at most.
private func playOut(_ pass: inout ShufflePass<Int>, repeatMode: Int, limit: Int) -> [Int] {
    var heard = [pass.current].compactMap(\.self)
    while heard.count < limit, let next = pass.peekNext(repeatMode: repeatMode) {
        pass.arrive(at: next)
        heard.append(next)
    }
    return heard
}

@Suite("PlaybackQueueKit — ShufflePass, a permutation with history (VM-SP)")
struct ShufflePassTests {
    private let hundred = Array(0 ..< 100)

    @Test("VM-SP-01 (§6 shuffle 1): a 100-song pass plays each song exactly once, then the queue ends")
    func onePassPlaysEachSongOnce() {
        for seed in [UInt64(0xC16), 1, 0xFFFF_FFFF_FFFF_FFFF] {
            var pass = ShufflePass(beginningAt: 37, among: hundred, seed: seed)
            let heard = playOut(&pass, repeatMode: repeatOff, limit: 1000)
            #expect(heard.count == 100, "seed \(seed): \(heard.count) songs started")
            #expect(Set(heard) == Set(hundred), "seed \(seed): a song repeated or was skipped")
            #expect(heard.first == 37)
            #expect(pass.peekNext(repeatMode: repeatOff) == nil, "Repeat off: nothing after the pass")
        }
        // The order is a shuffle, not the queue's: 100 songs in order would be a 1-in-100! draw.
        var pass = ShufflePass(beginningAt: 0, among: hundred, seed: 0xC16)
        #expect(playOut(&pass, repeatMode: repeatOff, limit: 1000) != hundred)
    }

    @Test("VM-SP-02 (§6 shuffle 2): Previous ×N gives the last N in reverse; Next after it resumes the pass")
    func previousWalksBackAndNextResumes() {
        var pass = ShufflePass(beginningAt: 5, among: hundred, seed: 7)
        let heard = playOut(&pass, repeatMode: repeatOff, limit: 41)
        let order = pass.permutation
        for count in 1 ... 40 {
            pass.stepBack(repeatMode: repeatOff)
            #expect(pass.current == heard[heard.count - 1 - count], "Previous ×\(count)")
        }
        #expect(pass.previous(repeatMode: repeatOff) == heard[0], "at the pass's first song: a restart")
        // Next, from there, plays the same songs again in the same order, then the songs not yet heard.
        let again = playOut(&pass, repeatMode: repeatOff, limit: 1000)
        #expect(Array(again.prefix(41)) == heard, "Next after Previous re-rolled")
        #expect(again.count == 100 && pass.permutation == order, "the pass's order changed")
    }

    @Test("VM-SP-03 (§6 shuffle 3): at a pass's first song, Previous restarts it (off) or enters the last pass (All)")
    func previousAtThePassStart() throws {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 10), seed: 99)
        let first = playOut(&pass, repeatMode: repeatAll, limit: 10) // the first pass, whole
        try pass.arrive(at: #require(pass.peekNext(repeatMode: repeatAll)))
        let secondStart = pass.current
        #expect(pass.history == first, "the last pass is kept as it played")

        // Repeat off: a restart — Previous names the song itself and leaves the pass as it is.
        #expect(pass.previous(repeatMode: repeatOff) == secondStart)
        let before = pass
        pass.stepBack(repeatMode: repeatOff)
        #expect(pass == before)

        // Repeat All: back into the last pass, all the way to its first song; there, a restart.
        for count in 1 ... 10 {
            pass.stepBack(repeatMode: repeatAll)
            #expect(pass.current == first[first.count - count], "Previous ×\(count) into the last pass")
        }
        #expect(pass.previous(repeatMode: repeatAll) == first[0], "nothing kept before the last pass")
        // Next walks forward through the last pass and back into this one, which kept its order.
        let order = pass.permutation
        let forward = playOut(&pass, repeatMode: repeatOff, limit: 1000)
        #expect(forward == first + order, "Next after Previous into the last pass re-rolled")
    }

    @Test("VM-SP-04 (§6 shuffle 10): Repeat All never begins a new pass with the song that just ended")
    func repeatAllNewPassNeverBeginsWithTheEndedSong() throws {
        for size in [2, 3, 10] {
            var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< size), seed: UInt64(size))
            for passNumber in 1 ... 200 {
                let ended = playOut(&pass, repeatMode: repeatOff, limit: 1000).last
                #expect(Set(pass.permutation) == Set(0 ..< size), "pass \(passNumber) is not a permutation")
                let named = pass.peekNext(repeatMode: repeatAll)
                try pass.arrive(at: #require(named))
                #expect(pass.current == named && pass.position == 0, "the new pass began elsewhere than named")
                #expect(named != ended, "size \(size), pass \(passNumber + 1) began with the song that just ended")
            }
        }
        // A one-song queue under Repeat All plays its song again: there is no other.
        let single = ShufflePass(beginningAt: 4, among: [4], seed: 1)
        #expect(single.peekNext(repeatMode: repeatAll) == 4)
        #expect(single.peekNext(repeatMode: repeatOff) == nil)
    }

    @Test("VM-SP-05 (§6 shuffle 4): shuffle turned on mid-song begins the pass at the song playing")
    func shuffleOnBeginsAtTheSongPlaying() {
        let pass = ShufflePass(beginningAt: 42, among: hundred, seed: 3)
        #expect(pass.current == 42 && pass.position == 0 && pass.history.isEmpty)
        #expect(pass.permutation.count == 100 && Set(pass.permutation) == Set(hundred))
    }

    @Test("VM-SP-06 (§6 shuffle 5): an append goes to a random place after the song armed next, and plays once")
    func appendGoesAfterTheArmedSong() throws {
        var places: Set<Int> = []
        for seed in UInt64(0) ..< 200 {
            var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 20), seed: seed)
            _ = playOut(&pass, repeatMode: repeatOff, limit: 5)
            let armed = pass.peekNext(repeatMode: repeatOff)
            pass.follow(Array(0 ... 20)) // song 20 appended
            #expect(pass.peekNext(repeatMode: repeatOff) == armed, "seed \(seed): the armed pick moved")
            let place = try #require(pass.permutation.firstIndex(of: 20))
            #expect(place > pass.position + 1, "seed \(seed): the append landed among the played or the armed")
            places.insert(place)
            let rest = playOut(&pass, repeatMode: repeatOff, limit: 1000)
            #expect(rest.count(where: { $0 == 20 }) == 1 && rest.count == 17, "seed \(seed)")
        }
        #expect(places.count > 10, "the append's place is not random: \(places.sorted())")
        // Playing the pass's last song, an append plays next.
        var last = ShufflePass(beginningAt: 0, among: Array(0 ..< 3), seed: 1)
        _ = playOut(&last, repeatMode: repeatOff, limit: 1000)
        last.follow([0, 1, 2, 3])
        #expect(last.peekNext(repeatMode: repeatOff) == 3)
    }

    @Test("VM-SP-07 (§6 shuffle 5): a removed song leaves history and pass; the next one removed, the one after it")
    func removals() throws {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 10), seed: 11)
        let heard = playOut(&pass, repeatMode: repeatOff, limit: 4)
        let after = pass.permutation[pass.position + 2]
        // A played song removed: Previous skips it.
        pass.follow(Array(0 ..< 10).filter { $0 != heard[2] })
        #expect(pass.current == heard[3])
        #expect(pass.previous(repeatMode: repeatOff) == heard[1], "Previous went to a removed song")
        // The next song removed: the one after it is next.
        let next = try #require(pass.peekNext(repeatMode: repeatOff))
        pass.follow(Array(0 ..< 10).filter { $0 != heard[2] && $0 != next })
        #expect(pass.peekNext(repeatMode: repeatOff) == after)
        // The song playing removed: the song that was next is still next, and nothing is current but
        // the song before it.
        let playing = try #require(pass.current)
        pass.follow(Array(0 ..< 10).filter { ![heard[2], next, playing].contains($0) })
        #expect(pass.current == heard[1] && pass.peekNext(repeatMode: repeatOff) == after)
        // Removing the only song played leaves a pass before its first song: the next is the first left.
        var fresh = ShufflePass(beginningAt: 3, among: [1, 2, 3], seed: 2)
        let second = fresh.permutation[1]
        fresh.follow([1, 2])
        #expect(fresh.current == nil && fresh.peekNext(repeatMode: repeatOff) == second)
    }

    @Test("VM-SP-08 (§6 shuffle 6): Play Next plays next and counts as played")
    func playNextCountsAsPlayed() {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 10), seed: 5)
        _ = playOut(&pass, repeatMode: repeatOff, limit: 3)
        pass.insertNext([10, 11]) // two new songs, in order
        #expect(pass.peekNext(repeatMode: repeatOff) == 10)
        var heard = playOut(&pass, repeatMode: repeatOff, limit: 1000)
        #expect(Array(heard.prefix(3).dropFirst()) == [10, 11])
        heard.removeFirst()
        #expect(heard.count == 9 && Set(heard).count == 9, "a Play Next song or another played twice")
        // A song not yet played, played next: it moves, and is not played again in the pass.
        var moved = ShufflePass(beginningAt: 0, among: Array(0 ..< 10), seed: 6)
        let later = moved.permutation[7]
        moved.insertNext([later])
        let rest = playOut(&moved, repeatMode: repeatOff, limit: 1000)
        #expect(rest[1] == later && rest.count == 10 && Set(rest).count == 10)
    }

    @Test("VM-SP-09 (§6 shuffle 7): Repeat One repeats the song and leaves the pass unchanged")
    func repeatOneLeavesThePass() throws {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 10), seed: 8)
        _ = playOut(&pass, repeatMode: repeatOff, limit: 4)
        let before = pass
        #expect(pass.peekNext(repeatMode: repeatOne) == pass.current)
        for _ in 0 ..< 5 {
            try pass.arrive(at: #require(pass.peekNext(repeatMode: repeatOne)))
        }
        #expect(pass == before)
    }

    @Test("VM-SP-10: a picked song plays now and counts as played; after the pass ran out it begins a new one")
    func pickedSongs() {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 10), seed: 12)
        let heard = playOut(&pass, repeatMode: repeatOff, limit: 3)
        let ahead = pass.permutation[8]
        let restBefore = pass.permutation.dropFirst(3).filter { $0 != ahead }
        pass.arrive(at: ahead)
        #expect(pass.current == ahead && pass.previous(repeatMode: repeatOff) == heard[2])
        #expect(Array(pass.permutation.dropFirst(4)) == restBefore, "a pick reordered the rest of the pass")
        // A song already played, picked: it plays now; the rest of the pass is still ahead.
        pass.arrive(at: heard[0])
        let rest = playOut(&pass, repeatMode: repeatOff, limit: 1000)
        #expect(rest.first == heard[0] && Array(rest.dropFirst()) == restBefore)
        // The pass ran out (Repeat off): a pick begins a new pass at it, the old one becomes the history.
        let finished = pass.permutation
        pass.arrive(at: heard[1])
        #expect(pass.current == heard[1] && pass.position == 0 && pass.history == finished)
        #expect(playOut(&pass, repeatMode: repeatOff, limit: 1000).count == 10)
    }

    @Test("VM-SP-11: back in the last pass, a Play Next plays there and the next pass holds every song")
    func editsWhileBackInTheLastPass() throws {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 6), seed: 13)
        _ = playOut(&pass, repeatMode: repeatAll, limit: 6)
        try pass.arrive(at: #require(pass.peekNext(repeatMode: repeatAll)))
        pass.stepBack(repeatMode: repeatAll)
        pass.stepBack(repeatMode: repeatAll) // two songs back into the last pass
        pass.insertNext([6])
        #expect(pass.peekNext(repeatMode: repeatOff) == 6)
        pass.follow(Array(0 ... 7)) // and 7 appended
        let heard = playOut(&pass, repeatMode: repeatOff, limit: 1000)
        #expect(heard.count(where: { $0 == 6 }) == 1 && heard.count(where: { $0 == 7 }) == 1)
        // The pass after this one holds all eight.
        try pass.arrive(at: #require(pass.peekNext(repeatMode: repeatAll)))
        #expect(Set(pass.permutation) == Set(0 ... 7))
    }

    @Test("VM-SP-12: following the queue — a reorder changes nothing, membership always matches")
    func followIsMembership() {
        var pass = ShufflePass(beginningAt: 2, among: Array(0 ..< 8), seed: 14)
        _ = playOut(&pass, repeatMode: repeatOff, limit: 3)
        let before = pass
        pass.follow(Array((0 ..< 8).reversed()))
        #expect(pass == before, "a reorder of the queue moved the pass")
        pass.follow([1, 3, 5, 8, 9])
        #expect(Set(pass.permutation + pass.history) == [1, 3, 5, 8, 9])
    }

    @Test("VM-SP-13: a seed reproduces its pass; the stored form round-trips and refuses a broken pass")
    func seededAndStored() throws {
        let one = ShufflePass(beginningAt: 1, among: hundred, seed: 0xDEAD_BEEF)
        #expect(one == ShufflePass(beginningAt: 1, among: hundred, seed: 0xDEAD_BEEF))
        #expect(one != ShufflePass(beginningAt: 1, among: hundred, seed: 0xDEAD_BEF0))
        var played = ShufflePass(beginningAt: 0, among: Array(0 ..< 5), seed: .max)
        _ = playOut(&played, repeatMode: repeatAll, limit: 7)
        let data = try JSONEncoder().encode(played)
        #expect(try JSONDecoder().decode(ShufflePass<Int>.self, from: data) == played)
        let broken = Data(#"{"permutation":[1,1],"history":[],"position":0,"seed":3}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ShufflePass<Int>.self, from: broken) }
        let outOfRange = Data(#"{"permutation":[1,2],"history":[],"position":2,"seed":3}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ShufflePass<Int>.self, from: outOfRange) }
    }

    @Test("VM-SP-14: relabeling keeps the pass; a slot with no new label leaves it as a removal does")
    func relabeling() throws {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 6), seed: 15)
        _ = playOut(&pass, repeatMode: repeatOff, limit: 3)
        let names = try #require(pass.relabeled { "s\($0)" })
        #expect(names.permutation == pass.permutation.map { "s\($0)" } && names.position == pass.position)
        let gone = try #require(pass.current)
        let without = try #require(pass.relabeled { $0 == gone ? nil : $0 })
        var removed = pass
        removed.follow(Array(0 ..< 6).filter { $0 != gone })
        #expect(without == removed)
        #expect(pass.relabeled { _ in 1 } == nil, "two slots relabeled as one")
    }

    @Test("VM-SP-15: every order is drawn about equally often (Fisher–Yates, not a biased swap)")
    func ordersAreUniform() {
        var counts: [[Int]: Int] = [:]
        for seed in UInt64(0) ..< 24000 {
            let pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 5), seed: seed)
            counts[Array(pass.permutation.dropFirst()), default: 0] += 1
        }
        // 24 orders of the four songs after the first, 1000 expected each; 4.5σ either side.
        #expect(counts.count == 24)
        #expect(counts.values.allSatisfy { (860 ... 1140).contains($0) }, "\(counts.values.sorted())")
    }
}

@Suite("PlaybackQueueKit — ShufflePass, many songs at once (VM-SP, review S3)")
struct ShufflePassBulkEditTests {
    @Test("VM-SP-16 (S3): 20,000 songs appended, or played next, write the line at most once — not once a song")
    func bulkEditsAreLinear() {
        var pass = ShufflePass(beginningAt: 0, among: Array(0 ..< 12), seed: 16)
        _ = playOut(&pass, repeatMode: repeatOff, limit: 4)
        let queued = Array(0 ..< 20012)
        let appended = ShufflePassTally()
        ShufflePassTally.$current.withValue(appended) { pass.follow(queued) }
        // One insert per song shifts the line each time: about 10⁸ slots here. Built once, it is at most the line.
        #expect(appended.slotsMoved <= queued.count, "an Add to Queue moved \(appended.slotsMoved) slots")
        #expect(Set(pass.permutation + pass.history) == Set(queued) && pass.position == 3)
        let next = Array(20012 ..< 40012)
        let playedNext = ShufflePassTally()
        ShufflePassTally.$current.withValue(playedNext) { pass.insertNext(next) }
        #expect(playedNext.slotsMoved <= queued.count + next.count,
                "a Play Next moved \(playedNext.slotsMoved) slots")
        #expect(Array(pass.permutation[4 ..< 20004]) == next && pass.position == 3, "Play Next is not next, in order")
    }

    @Test("VM-SP-17 (S3): songs added at once land exactly where adding them one at a time puts them")
    func bulkFollowIsOneAtATime() throws {
        for seed in UInt64(0) ..< 60 {
            var base = ShufflePass(beginningAt: 0, among: Array(0 ..< 10), seed: seed)
            // Every place the listener can be: early, mid-pass, on the pass's last song (nothing after it:
            // the first added plays next), and — every third seed — two songs back in the last pass.
            _ = playOut(&base, repeatMode: repeatAll, limit: Int(seed % 10) + 1)
            if seed % 3 == 0 {
                try base.arrive(at: #require(base.peekNext(repeatMode: repeatAll)))
                base.stepBack(repeatMode: repeatAll)
                base.stepBack(repeatMode: repeatAll)
            }
            var atOnce = base
            atOnce.follow(Array(0 ..< 30))
            var oneByOne = base
            for size in 11 ... 30 {
                oneByOne.follow(Array(0 ..< size))
            }
            #expect(atOnce == oneByOne, "seed \(seed): a batch landed elsewhere than one at a time")
        }
    }
}
