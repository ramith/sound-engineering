import PlaybackQueueKit
import Testing

// MARK: - SeekTarget — the one rule for where a seek lands (council C-25 / DUP-1) (VM-ST)

//
// Imports the shipped `PlaybackQueueKit` target: the rule under test is the one the view model's seek,
// the bridge's seek entry and every Enhanced start / restart run.

@Suite("PlaybackQueueKit — SeekTarget, where a seek lands (VM-ST)")
struct SeekTargetTests {
    static let rates: [Double] = [22050, 32000, 44100, 48000, 88200, 96000, 176_400, 192_000, 352_800, 384_000]

    /// A seeded SplitMix64 stream, so a failure names its case.
    struct Seeded {
        var state: UInt64

        mutating func next(_ range: ClosedRange<Int64>) -> Int64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            mixed ^= mixed >> 31
            return range.lowerBound + Int64(mixed % UInt64(range.upperBound - range.lowerBound + 1))
        }
    }

    @Test("VM-ST-01: the scrubber at 100 % (seconds == length / rate) is the end, for every length")
    func theDurationIsTheEnd() {
        // The breaker measured 93 % of lengths truncating to exactly `length` — and being refused.
        var random = Seeded(state: 1)
        for rate in Self.rates {
            for _ in 0 ..< 2000 {
                let length = random.next(Int64(rate * 60) ... Int64(rate * 900)) // 1 to 15 minutes
                let duration = Double(length) / rate // the view model's duration
                #expect(SeekTarget(seconds: duration, length: length, sampleRate: rate) == .end,
                        "rate \(rate), length \(length)")
            }
        }
    }

    @Test("VM-ST-02: a place that IS frame k lands on frame k — rounded, never truncated one short")
    func anExactFrameLandsOnItself() {
        var random = Seeded(state: 2)
        for rate in Self.rates {
            for _ in 0 ..< 2000 {
                let length = Int64(rate * 600)
                let frame = random.next(0 ... length - 1)
                #expect(SeekTarget(seconds: Double(frame) / rate, length: length, sampleRate: rate) == .frame(frame),
                        "rate \(rate), frame \(frame)")
            }
        }
    }

    @Test("VM-ST-03: the last frame is still a place; one frame on is the end; far past is the end")
    func theEdge() {
        let rate = 44100.0
        let length: Int64 = 132_300
        #expect(SeekTarget(seconds: Double(length - 1) / rate, length: length, sampleRate: rate) == .frame(length - 1))
        #expect(SeekTarget(seconds: Double(length + 1) / rate, length: length, sampleRate: rate) == .end)
        #expect(SeekTarget(seconds: 1e300, length: length, sampleRate: rate) == .end, "no Int64 overflow trap")
        #expect(SeekTarget(seconds: 0, length: 0, sampleRate: rate) == .end, "an empty track is over")
    }

    @Test("VM-ST-04: not a number is not a place; nothing comes before the top", arguments: [
        Double.nan, .infinity, -.infinity, .signalingNaN,
    ])
    func notAPlace(_ seconds: Double) {
        #expect(SeekTarget(seconds: seconds, length: 48000, sampleRate: 48000) == nil)
        #expect(SeekTarget.place(seconds) == nil)
        #expect(SeekTarget.place(seconds, duration: 240) == nil)
    }

    @Test("VM-ST-05: a negative place is the top")
    func negativeIsTheTop() {
        #expect(SeekTarget(seconds: -3, length: 48000, sampleRate: 48000) == .frame(0))
        #expect(SeekTarget(seconds: -0.0, length: 48000, sampleRate: 48000) == .frame(0))
        #expect(SeekTarget.place(-3) == 0)
    }

    @Test("VM-ST-06: a track with no usable rate has no places")
    func noRateNoPlace() {
        #expect(SeekTarget(seconds: 1, length: 48000, sampleRate: 0) == nil)
        #expect(SeekTarget(seconds: 1, length: 48000, sampleRate: .nan) == nil)
        #expect(SeekTarget(seconds: 1, length: 48000, sampleRate: -48000) == nil)
    }

    @Test("VM-ST-07: in seconds, a known duration bounds the place; 0 (not known yet) bounds only below")
    func secondsAgainstADuration() {
        #expect(SeekTarget.place(300, duration: 240) == 240)
        #expect(SeekTarget.place(120, duration: 240) == 120)
        #expect(SeekTarget.place(-1, duration: 240) == 0)
        #expect(SeekTarget.place(300, duration: 0) == 300)
        #expect(SeekTarget.place(300, duration: .nan) == 300)
        #expect(SeekTarget.place(300) == 300)
    }
}
