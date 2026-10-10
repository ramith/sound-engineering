// EQPlayed — the curve the EQ PLAYS (Sprint EQ, EQ3; engine-plan §8, decision 26). EQ1a's designer
// reads it back from the cascade it solves, so the graph draws what is heard, never a Swift copy of
// the fitter. Two views of one design: the played dB at the 31 band centres (the readout's "plays")
// and on the graph's fixed response grid (the solid curve). Headroom, peak and loudness are not part
// of it (decision 26: the EQ keeps the song's loudness).

import Foundation

public struct EQPlayed: Equatable, Sendable {
    /// The graph's response grid: 256 log-spaced frequencies, 20 Hz · 1000^(i/255), so 20 Hz to
    /// 20 kHz — the grid EQ1a's C++ gate measures (`eqUiGrid`). Below Nyquist at every design rate.
    public static let frequencies: [Double] = (0 ..< gridCount).map { 20 * pow(1000, Double($0) / 255) }

    /// The response grid's length.
    private static let gridCount = 256

    /// The played dB at each band centre, one per band.
    public let centreDb: [Float]

    /// The played dB at each of `frequencies`.
    public let responseDb: [Float]

    /// A read-back of one design; `nil` unless it has one finite value per band and per grid point.
    public init?(centreDb: [Float], responseDb: [Float]) {
        guard centreDb.count == EQBands.count, responseDb.count == Self.gridCount,
              (centreDb + responseDb).allSatisfy(\.isFinite) else { return nil }
        self.centreDb = centreDb
        self.responseDb = responseDb
    }
}
