import Foundation

/// A track file's identity: its path, size and modification time (Sprint EQ, EQ1c; amendments
/// item 3, "a cache keyed by file identity"). The same bytes at the same path keep the same
/// identity across plays, so a profile is analysed once; an edited or replaced file gets a new one.
///
/// `token` is the 64-bit name the engine knows the track by (`setCurrentTrack`,
/// `publishTrackLoudnessProfile`): FNV-1a over the three fields, never 0 (the engine's "no track").
public struct TrackIdentity: Hashable, Sendable {
    public let path: String
    public let size: UInt64
    public let modified: Double // seconds since 1970

    /// The identity of the file at `url`, or nil when its attributes cannot be read.
    public init?(url: URL) {
        let path = url.standardizedFileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        self.path = path
        self.size = size
        self.modified = modified.timeIntervalSince1970
    }

    /// The engine's token for this track (FNV-1a 64 of "path|size|mtime"; never 0).
    public var token: UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in "\(path)|\(size)|\(modified.bitPattern)".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash == 0 ? 1 : hash
    }
}
