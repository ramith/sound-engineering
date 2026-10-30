@preconcurrency import AVFoundation
import Foundation

/// A file's loudness tags as written (R1.1-B W5, lane 3-A; US-R1F-10 item 4): ReplayGain 2.0 and EBU R128, read
/// from FLAC and Ogg Vorbis comments (AVFoundation's `vorb/…` items), ID3 `TXXX` user frames (MP3, and the ID3 chunk
/// of WAV and AIFF; the name is the frame's description) and MP4 freeform `----:com.apple.iTunes:…` atoms (its
/// `itlk/com.apple.iTunes.…` items). Names match in any case. Raw values only: the conversion to the −18 LUFS target
/// is LevelingKit's (`GainTags`), which these map onto field by field.
public struct TrackGainTags: Sendable, Equatable {
    /// `REPLAYGAIN_TRACK_GAIN` (dB, relative to −18 LUFS).
    public var replayGainTrack: Double?
    /// `REPLAYGAIN_TRACK_PEAK` (linear, 1.0 = full scale).
    public var replayGainTrackPeak: Double?
    /// `REPLAYGAIN_ALBUM_GAIN` (dB).
    public var replayGainAlbum: Double?
    /// `REPLAYGAIN_ALBUM_PEAK` (linear).
    public var replayGainAlbumPeak: Double?
    /// `R128_TRACK_GAIN` (Q7.8 dB, relative to −23 LUFS).
    public var r128Track: Int?
    /// `R128_ALBUM_GAIN` (Q7.8 dB).
    public var r128Album: Int?

    public init(replayGainTrack: Double? = nil, replayGainTrackPeak: Double? = nil, replayGainAlbum: Double? = nil,
                replayGainAlbumPeak: Double? = nil, r128Track: Int? = nil, r128Album: Int? = nil) {
        self.replayGainTrack = replayGainTrack
        self.replayGainTrackPeak = replayGainTrackPeak
        self.replayGainAlbum = replayGainAlbum
        self.replayGainAlbumPeak = replayGainAlbumPeak
        self.r128Track = r128Track
        self.r128Album = r128Album
    }

    /// Whether the file carries none of the tags.
    public var isEmpty: Bool {
        self == TrackGainTags()
    }

    /// The tags of the file at `url`; empty when it has none or cannot be read. Reads the file's metadata (no
    /// decode); call it off the main thread. The first readable value of each tag counts; one that does not parse
    /// ("loud", a fractional R128 gain) is left out.
    public static func read(from url: URL) async -> TrackGainTags {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        guard let items = try? await AVURLAsset(url: url).load(.metadata) else { return TrackGainTags() }
        var tags = TrackGainTags()
        for item in items {
            guard let name = await name(of: item), let field = Field(named: name),
                  let value = try? await item.load(.stringValue) else { continue }
            tags.take(value, for: field)
        }
        return tags
    }
}

extension TrackGainTags {
    /// The tags read, by their lower-case names.
    private enum Field: String, CaseIterable {
        case replayGainTrack = "replaygain_track_gain"
        case replayGainTrackPeak = "replaygain_track_peak"
        case replayGainAlbum = "replaygain_album_gain"
        case replayGainAlbumPeak = "replaygain_album_peak"
        case r128Track = "r128_track_gain"
        case r128Album = "r128_album_gain"

        /// The field an item's name says, whatever its key space's prefix ("com.apple.iTunes.", a mean and ':').
        init?(named name: String) {
            let lowered = name.lowercased()
            let found = Self.allCases.first { field in
                lowered == field.rawValue || lowered.hasSuffix("." + field.rawValue)
                    || lowered.hasSuffix(":" + field.rawValue)
            }
            guard let found else { return nil }
            self = found
        }
    }

    /// The ID3 user-text frame, whose description names its value.
    private static let id3UserText = AVMetadataIdentifier(rawValue: "id3/TXXX")

    /// An item's name: a `TXXX` frame's description, else its key.
    private static func name(of item: AVMetadataItem) async -> String? {
        if item.identifier == id3UserText {
            return (try? await item.load(.extraAttributes))??[.info] as? String
        }
        return item.key as? String
    }

    /// Keep `text` as `field`'s value unless one was read already or it does not parse.
    private mutating func take(_ text: String, for field: Field) {
        switch field {
        case .replayGainTrack: replayGainTrack = replayGainTrack ?? Self.decibels(text)
        case .replayGainTrackPeak: replayGainTrackPeak = replayGainTrackPeak ?? Self.number(text)
        case .replayGainAlbum: replayGainAlbum = replayGainAlbum ?? Self.decibels(text)
        case .replayGainAlbumPeak: replayGainAlbumPeak = replayGainAlbumPeak ?? Self.number(text)
        case .r128Track: r128Track = r128Track ?? Int(text.trimmingCharacters(in: .whitespaces))
        case .r128Album: r128Album = r128Album ?? Int(text.trimmingCharacters(in: .whitespaces))
        }
    }

    /// A ReplayGain gain ("+6.00 dB", "-7.53 dB", "-7.53"): the number before the unit.
    private static func decibels(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.lowercased().hasSuffix("db") ? String(trimmed.dropLast(2)) : trimmed
        return Self.number(number)
    }

    /// A finite number.
    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces)).flatMap { $0.isFinite ? $0 : nil }
    }
}
