import Foundation

/// Formats a duration in seconds as "m:ss" — e.g. 73 → "1:13".
func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds) / 60
    let secs = Int(seconds) % 60
    return "\(minutes):\(secs.formatted(.number.precision(.integerLength(2))))"
}

/// A humane running total, e.g. "3 hr 14 min" (S9.5 Songs count line). Hours + minutes only,
/// zero units hidden, so a short library reads "14 min". Distinct from `formatDuration` (which
/// is the exact "m:ss" of a SINGLE track); this is the rounded "how much music" summary.
func humaneTotalDuration(_ seconds: Double) -> String {
    Duration.seconds(max(0, seconds))
        .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
}

/// A compact "MMM d, yyyy" date (e.g. "Jul 7, 2026") for the Songs "Date Added" column, built
/// from whole Unix seconds. A non-positive value (0 = never stamped / unknown) renders blank —
/// the design's nil/0 → empty-cell rule. Locale-aware via `Date.FormatStyle`.
func compactDate(_ unixSeconds: Int64) -> String {
    guard unixSeconds > 0 else { return "" }
    return Date(timeIntervalSince1970: TimeInterval(unixSeconds))
        .formatted(.dateTime.month(.abbreviated).day().year())
}
