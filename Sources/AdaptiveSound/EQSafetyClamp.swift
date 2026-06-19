import Foundation

// MARK: - EQSafetyClamp

/// Hearing-safety cumulative-gain clamp for the 31-band EQ.
///
/// Sits in the control path between band-gain *intent* (`EQViewModel.bandGains`,
/// driven by presets, slider/canvas edits, and the future NL macro layer) and the
/// values *published* to the DSP kernel. It enforces a ceiling on the **summed**
/// band gains so that a "boost everything" intent cannot stack into a dangerous
/// cumulative level.
///
/// Algorithm: sum the signed band gains; if the sum exceeds `cumulativeLimitDb`,
/// scale **every** band by `limit / sum`. A single uniform scale factor preserves
/// the user's intended shape (inter-band ratios) and the sign of every band —
/// boosts stay boosts, cuts stay cuts — while bringing the aggregate boost down to
/// exactly the limit.
///
/// Scope / notes:
/// - The metric is the *signed* sum, matching the spec's acceptance tests
///   (`{+8, −3, +5, −1, +2}` = +11 → no clamp). Individual bands are independently
///   bounded to `[−12, +12]` dB upstream in `EQViewModel`, so the signed sum
///   cannot be defeated by a single runaway band.
/// - Pure and side-effect free, so it leaves `bandGains` (the user-visible intent)
///   untouched — only the published copy is scaled.
/// - Confidence-gated stricter clamping is deferred to the future Arbiter / NL
///   control plane, which does not exist yet.
enum EQSafetyClamp {
    /// Cumulative boost ceiling in dB (professional standard; see Sprint 4 spec).
    static let cumulativeLimitDb: Float = 12.0

    /// Returns `gains` scaled so their signed sum does not exceed `limit` dB.
    ///
    /// If the sum is already at or below `limit` — including all-zero inputs and
    /// net-cut shapes — `gains` is returned unchanged. `limit` is expected to be
    /// positive (the default `cumulativeLimitDb`); a non-positive `limit` would
    /// scale any positive-sum shape toward/through zero, which is not a supported
    /// configuration.
    static func clamped(_ gains: [Float], limit: Float = cumulativeLimitDb) -> [Float] {
        let total = gains.reduce(0, +)
        guard total > limit else { return gains }
        let scale = limit / total
        return gains.map { $0 * scale }
    }
}
