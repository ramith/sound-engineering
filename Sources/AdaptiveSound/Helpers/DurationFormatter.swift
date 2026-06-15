import Foundation

/// Formats a duration in seconds as "m:ss" — e.g. 73 → "1:13".
func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return "\(minutes):\(secs.formatted(.number.precision(.integerLength(2))))"
}
