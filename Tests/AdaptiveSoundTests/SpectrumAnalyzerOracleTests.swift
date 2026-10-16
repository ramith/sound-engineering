// R1.1-A (council C-51; panel P1 D53, D54): the spectrum analyser tells the truth. An independent
// oracle — a sine of known frequency and level, the definition of dBFS — fed to the real
// `SpectrumAnalyzer` the way AVAudioEngine delivers a tap (100 ms buffers, Apple's floor), at every
// sample rate the app plays: the sine must light ITS band at ITS level. The bands tile the audible
// range, 20 Hz – 20 kHz, in 44 equal log steps (founder decision 2026-10-16: the lens's "20 Hz – 20 kHz"
// axis is true); the oracle derives them itself (`band(holding:)`). Before R1.1 a 0 dBFS sine read
// +3…+4.26 dB (the window's gain counted twice), the analyser looked at the first 4096 frames of each
// buffer only (21 % of the audio at 192 kHz), at high rates bands shared bins and took in DC, and the
// bands stopped at 6 kHz: nothing above showed.

@testable import AdaptiveSound
import AVFoundation
import Testing

@Suite("The spectrum analyser tells the truth (C-51)")
struct SpectrumAnalyzerOracleTests {
    /// Every rate the app plays at, the two families and their multiples.
    static let rates: [Double] = [44100, 48000, 88200, 96000, 176_400, 192_000]

    /// Bands across the display, from the bass to the top band (centres by `SpectrumConstants`).
    private static let bands = [8, 14, 20, 26, 32, 38, 43]

    /// Tones across the whole range, deep bass to the top octave (founder decision 2026-10-16).
    private static let rangeTones: [Double] = [30, 1000, 10000, 18000]

    /// A sine's reading may miss its dBFS by this much: the window's scalloping, not its gain.
    private static let levelTolerance = 0.5

    // MARK: The oracle

    @Test("a full-scale sine reads 0 dBFS, in its own band, at every rate", arguments: rates)
    func fullScaleSine(rate: Double) {
        for band in Self.bands {
            let hertz = Double(SpectrumConstants.bandCentreHz(Float(band)))
            let reading = Self.steadyReading(rate: rate) { Self.sine(hertz, amplitude: 1, at: $0, rate: rate) }
            #expect(reading.loudestBand == band,
                    "\(hertz) Hz at \(rate) Hz lit band \(reading.loudestBand), not \(band)")
            #expect(abs(reading.decibels(band)) <= Self.levelTolerance,
                    "\(hertz) Hz at \(rate) Hz read \(reading.decibels(band)) dB, not 0 dBFS")
        }
    }

    @Test("tones from 30 Hz to 18 kHz each read 0 dBFS in the band that holds them, at every rate", arguments: rates)
    func wholeRange(rate: Double) {
        for hertz in Self.rangeTones {
            let band = Self.band(holding: hertz)
            let reading = Self.steadyReading(rate: rate) { Self.sine(hertz, amplitude: 1, at: $0, rate: rate) }
            #expect(reading.loudestBand == band,
                    "\(hertz) Hz at \(rate) Hz lit band \(reading.loudestBand), not \(band)")
            #expect(abs(reading.decibels(band)) <= Self.levelTolerance,
                    "\(hertz) Hz at \(rate) Hz read \(reading.decibels(band)) dB in band \(band), not 0 dBFS")
        }
    }

    @Test("a −20 dBFS sine between band centres reads −20 dB in the band that holds it", arguments: rates)
    func quieterSine(rate: Double) {
        let hertz = 997.0 // the AES17 test tone: never on a bin
        let band = Self.band(holding: hertz)
        let amplitude = Float(pow(10.0, -20.0 / 20.0))
        let reading = Self.steadyReading(rate: rate) { Self.sine(hertz, amplitude: amplitude, at: $0, rate: rate) }
        #expect(reading.loudestBand == band, "997 Hz at \(rate) Hz lit band \(reading.loudestBand), not \(band)")
        #expect(abs(reading.decibels(band) + 20) <= Self.levelTolerance,
                "997 Hz at −20 dBFS read \(reading.decibels(band)) dB at \(rate) Hz")
    }

    @Test("the whole tap buffer is analysed: a burst at its end shows", arguments: rates)
    func burstAtTheEndOfABuffer(rate: Double) {
        let hertz = Double(SpectrumConstants.bandCentreHz(30)) // the upper midrange
        let frames = Self.tapFrames(rate: rate)
        let burstStart = frames * 4 / 5 // the buffer's last fifth: past the first 4096 frames at ≥ 88.2 kHz
        let analyzer = Self.makeAnalyzer(rate: rate)
        var loudest = -Double.infinity
        for buffer in 0 ..< 5 {
            Self.feed(analyzer, rate: rate) { index in
                buffer == 2 && index >= burstStart ? Self.sine(hertz, amplitude: 1, at: index, rate: rate) : 0
            }
            loudest = max(loudest, Self.latest(analyzer).decibels(30))
        }
        #expect(loudest > -20, "a 0 dBFS burst in the buffer's last fifth peaked at \(loudest) dB at \(rate) Hz")
    }

    @Test("DC lights no band", arguments: rates)
    func directCurrentIsNotMusic(rate: Double) {
        // −12 dBFS of offset, for long enough that the step at its start has fallen away.
        let reading = Self.steadyReading(rate: rate, buffers: 40) { _ in 0.25 }
        let lit = reading.values.indices.filter { reading.decibels($0) > -79 }
        #expect(lit.isEmpty, "a DC offset lit bands \(lit) at \(rate) Hz")
    }

    // MARK: The geometry behind it

    @Test("the window keeps the shipped 85 ms at every rate, as a power of two")
    func windowFollowsTheRate() {
        let expected: [Double: Int] = [44100: 4096, 48000: 4096, 88200: 8192, 96000: 8192,
                                       176_400: 16384, 192_000: 16384, 352_800: 32768, 384_000: 32768]
        for (rate, length) in expected {
            #expect(SpectrumAnalyzer.windowLength(sampleRate: rate) == length, "at \(rate) Hz")
        }
    }

    @Test("every band owns bins of its own, from 20 Hz to 20 kHz, and none holds DC",
          arguments: rates + [352_800, 384_000])
    func bandsOwnTheirBins(rate: Double) {
        let spans = SpectrumAnalyzer.bandLayout(sampleRate: rate)
        #expect(SpectrumConstants.bandEdgeHz(0) == 20 && SpectrumConstants.bandEdgeHz(spans.count) == 20000)
        var previousLast = 0 // bin 0 is DC: the first band starts above it
        for (band, span) in spans.enumerated() {
            guard let bins = span.bins else {
                let centre = SpectrumConstants.bandCentreHz(Float(band))
                Issue.record("band \(band) (\(centre) Hz) owns no bin at \(rate) Hz")
                continue
            }
            #expect(bins.lowerBound > previousLast, "band \(band) shares bin \(bins.lowerBound) at \(rate) Hz")
            previousLast = bins.upperBound
        }
    }

    // MARK: Feeding the real analyser

    /// What the analyser published: one value per band in 0…1 over its dB range.
    struct Reading {
        let values: [Float]

        var loudestBand: Int {
            values.indices.max { values[$0] < values[$1] } ?? -1
        }

        /// Band `band`'s reading in dBFS.
        func decibels(_ band: Int) -> Double {
            let floor = Double(SpectrumConstants.noiseFloorDB)
            return Double(values[band]) * -floor + floor
        }
    }

    private static func makeAnalyzer(rate: Double) -> SpectrumAnalyzer {
        SpectrumAnalyzer(sampleRate: rate)
    }

    /// The latest frame the analyser handed the main thread.
    private static func latest(_ analyzer: SpectrumAnalyzer) -> Reading {
        var values = [Float](repeating: 0, count: SpectrumConstants.bandCount)
        analyzer.frames.read(into: &values)
        return Reading(values: values)
    }

    /// The frames AVAudioEngine hands a tap at `rate`: 100 ms, Apple's documented floor.
    private static func tapFrames(rate: Double) -> Int {
        Int(rate / 10)
    }

    /// Feed one tap buffer of stereo `signal(frameIndex)` on both channels.
    private static func feed(_ analyzer: SpectrumAnalyzer, rate: Double, signal: (Int) -> Float) {
        let frames = tapFrames(rate: rate)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            Issue.record("no buffer at \(rate) Hz")
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        for index in 0 ..< frames {
            let sample = signal(index)
            channels[0][index] = sample
            channels[1][index] = sample
        }
        analyzer.processTapBuffer(buffer.mutableAudioBufferList, frameCount: buffer.frameLength, channelCount: 2)
    }

    /// `buffers` tap buffers (0.6 s by default) of a steady signal — the meter settled — then what the
    /// analyser shows. `signal` takes the frame index from the start of the stream, so a sine runs on
    /// across buffers.
    private static func steadyReading(rate: Double, buffers: Int = 6, signal: (Int) -> Float) -> Reading {
        let analyzer = makeAnalyzer(rate: rate)
        let frames = tapFrames(rate: rate)
        for buffer in 0 ..< buffers {
            feed(analyzer, rate: rate) { signal(buffer * frames + $0) }
        }
        return latest(analyzer)
    }

    private static func sine(_ hertz: Double, amplitude: Float, at index: Int, rate: Double) -> Float {
        amplitude * Float(sin(2 * Double.pi * hertz * Double(index) / rate))
    }

    /// The band that holds `hertz`: the bands tile 20 Hz – 20 kHz in 44 equal log steps, band k
    /// spanning [20·1000^(k/44), 20·1000^((k+1)/44)) Hz.
    private static func band(holding hertz: Double) -> Int {
        let step = log(1000.0) / Double(SpectrumConstants.bandCount)
        return Int((log(hertz / 20) / step).rounded(.down))
    }
}
