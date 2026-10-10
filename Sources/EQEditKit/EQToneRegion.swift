// EQToneRegion — the five Tone macros of decision 24 (Bass <150 Hz, Body 150–500 Hz, Mids
// 0.5–2 kHz, Presence 2–6 kHz, Air >6 kHz). A Tone value moves the 31 points by its region's
// weight at each band; it adds no filter of its own, so the macros stay inside the one
// accurate graphic EQ.
//
// The weights are a raised-cosine partition of unity on log₂ f (McGrath, Baird & Jackson,
// AES 2004; literature survey §6): a C¹ step rises over one octave at each crossover, and each
// region is the difference of the steps at its two edges. The sum telescopes to exactly 1, so
// all five regions at +x give a flat +x — the Baxandall "level at mid" property.

import Foundation

public enum EQToneRegion: Int, CaseIterable, Identifiable, Sendable {
    case bass, body, mids, presence, air

    public var id: Int {
        rawValue
    }

    /// The weight of every region at every band: `bandWeights[region.rawValue][band]`,
    /// computed once at the exact band centres.
    static let bandWeights: [[Float]] = allCases.map { region in
        EQBands.centreHz.map { Float(region.weight(atHz: $0)) }
    }

    /// Width of each crossover's rise, in octaves.
    private static let crossoverOctaves = 1.0

    /// This region's weight at `hz`, in 0…1: how much of a Tone move reaches that frequency (the graph
    /// shades the region by it). The five weights sum to 1 at every frequency.
    public func weight(atHz hz: Double) -> Double {
        let (lower, upper) = edgesHz
        let below = lower.map { Self.rise(atHz: hz, crossoverHz: $0) } ?? 1
        let above = upper.map { Self.rise(atHz: hz, crossoverHz: $0) } ?? 0
        return below - above
    }

    /// The crossovers this region sits between; `nil` is open-ended (Bass down, Air up).
    private var edgesHz: (lower: Double?, upper: Double?) {
        switch self {
        case .bass: (nil, 150)
        case .body: (150, 500)
        case .mids: (500, 2000)
        case .presence: (2000, 6000)
        case .air: (6000, nil)
        }
    }

    /// The raised-cosine step at a crossover: 0 an octave-half below it, 1 an octave-half
    /// above it, ½ on it, smooth (C¹) in between.
    private static func rise(atHz hz: Double, crossoverHz: Double) -> Double {
        let octaves = log2(hz / crossoverHz) / crossoverOctaves
        return 0.5 * (1 + sin(.pi * min(max(octaves, -0.5), 0.5)))
    }
}

// MARK: - Names (the Tone card's rows, the graph's region labels and Tone readout, VoiceOver)

/// One set of region names for the whole screen: the Tone card's rows and the graph's labels above the
/// plot are these five, over these spans, so the two always agree.
public extension EQToneRegion {
    /// The region's span on the graph's 20 Hz – 20 kHz axis: crossover to crossover, an open end
    /// running to the axis's end. The graph centres the region's name over it.
    var spanHz: ClosedRange<Double> {
        (edgesHz.lower ?? EQBands.nominalHz[0]) ... (edgesHz.upper ?? EQBands.nominalHz[EQBands.count - 1])
    }

    /// The region's name: "Presence".
    var name: String {
        switch self {
        case .bass: "Bass"
        case .body: "Body"
        case .mids: "Mids"
        case .presence: "Presence"
        case .air: "Air"
        }
    }

    /// Where the region sits on the graph's own frequency axis — its crossovers (`edgesHz`):
    /// "<150 Hz", "2–6 kHz", ">6 kHz". The Tone card prints it under the name; the graph's readout
    /// follows the name with it ("Tone · Presence 2–6 kHz +3.0 dB").
    var span: String {
        switch self {
        case .bass: "<150 Hz"
        case .body: "150–500 Hz"
        case .mids: "0.5–2 kHz"
        case .presence: "2–6 kHz"
        case .air: ">6 kHz"
        }
    }

    /// `span` as VoiceOver speaks it: "below 150 hertz", "2 to 6 kilohertz".
    var spokenSpan: String {
        switch self {
        case .bass: "below 150 hertz"
        case .body: "150 to 500 hertz"
        case .mids: "500 hertz to 2 kilohertz"
        case .presence: "2 to 6 kilohertz"
        case .air: "above 6 kilohertz"
        }
    }
}
