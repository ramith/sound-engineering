import Foundation

/// "FLAC · 24/96": `FORMAT` plus a "bitDepth/kHz" suffix when both sample rate and bit
/// depth are known (a real PCM source), else the bare format (e.g. "AAC" for a compressed
/// file with no PCM depth). Mirrors `TrackInfoCard`'s kHz-rounding rule (whole kHz when
/// exact, else one decimal) so the two surfaces read consistently. Renders as plain text,
/// not a colored badge (S9.5 §10.1/§11.1 — badge noise at scale; the badge stays in the
/// Info popover/footer, `FormatBadgeView`).
func qualityString(format: String, sampleRate: Int?, bitDepth: Int?) -> String {
    guard let sampleRate, sampleRate > 0, let bitDepth, bitDepth > 0 else { return format }
    let kHz = Double(sampleRate) / 1000.0
    let rateText = kHz.truncatingRemainder(dividingBy: 1) < 0.001
        ? "\(Int(kHz))" : String(format: "%.1f", kHz)
    return "\(format) · \(bitDepth)/\(rateText)"
}
