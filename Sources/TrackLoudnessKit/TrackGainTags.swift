import Foundation

/// A file's loudness tags as written (R1.1-B W5, lane 3-A; US-R1F-10 item 4): ReplayGain 2.0 and EBU R128, read
/// from FLAC and Ogg Vorbis comments, MP3 `TXXX` frames and MP4 freeform (`----:com.apple.iTunes:…`) atoms. Raw
/// values only: the conversion to the −18 LUFS target is LevelingKit's (`GainTags`), which these map onto field by
/// field.
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
    /// decode); call it off the main thread. Lane 3-A's reader (stub until it lands).
    public static func read(from _: URL) async -> TrackGainTags {
        TrackGainTags()
    }
}
