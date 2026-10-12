// MARK: - Channel Labels

/// Maps a 0-based channel index to its drawn label and its spoken name.
///
/// Follows the conventional channel ordering used by AVAudioChannelLayout / ITU-R BS.775:
///   0=L, 1=R, 2=C, 3=LFE, 4=Ls, 5=Rs, 6=Lss, 7=Rss
/// A non-standard layout falls back to "Ch 1", "Ch 2", … (spoken "Channel 1", …).
enum ChannelLabels {
    /// One channel: the short label a lens draws and the name VoiceOver reads (S10.8 G1).
    private typealias Name = (label: String, spoken: String)

    private static let mono: [Name] = [("M", "Mono")]
    private static let stereo: [Name] = [("L", "Left"), ("R", "Right")]
    private static let surround51: [Name] = stereo + [
        ("C", "Centre"), ("LFE", "Low-frequency effects"), ("Ls", "Left surround"), ("Rs", "Right surround"),
    ]
    private static let surround71: [Name] = surround51 + [("Lss", "Left side surround"), ("Rss", "Right side surround")]

    /// The short label drawn in the channel's lens, e.g. "L", "LFE", "Ch 3".
    static func label(for index: Int, total: Int) -> String {
        name(for: index, total: total)?.label ?? "Ch \(index + 1)"
    }

    /// The channel as VoiceOver names it, e.g. "Left channel", "Low-frequency effects channel", "Channel 3".
    static func spokenName(for index: Int, total: Int) -> String {
        name(for: index, total: total).map { "\($0.spoken) channel" } ?? "Channel \(index + 1)"
    }

    private static func name(for index: Int, total: Int) -> Name? {
        let table: [Name] = switch total {
        case 1: mono
        case 2: stereo
        case 6: surround51
        case 8: surround71
        default: []
        }
        return table.indices.contains(index) ? table[index] : nil
    }
}
