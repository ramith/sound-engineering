import AVFoundation
import Foundation

// MARK: - Loose-file embedded metadata (S10.4 D2 / FN-5)

/// A loose (non-library) file's embedded tags, read from the file itself for the Now Playing path.
/// Artwork is carried as `Data` (Sendable) so nothing non-Sendable crosses the actor boundary — the
/// `NSImage` is built on the main actor by the controller (design §5).
struct LooseTrackMetadata {
    let artist: String?
    let album: String?
    let artworkData: Data?
}

/// Reads embedded ID3/MP4 common metadata (artist / album / cover) from a file URL. Used ONLY for
/// loose files (`trackID == nil`), where there's no library row to resolve — library tracks go
/// through the store instead. `nonisolated`/off-main: `AVAsset` loading runs off the caller's actor.
enum EmbeddedMetadataReader {
    static func read(_ url: URL) async -> LooseTrackMetadata? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata), !items.isEmpty else { return nil }

        let artist = await string(from: items, key: .commonKeyArtist)
        let album = await string(from: items, key: .commonKeyAlbumName)
        let artworkData = await data(from: items, key: .commonKeyArtwork)
        // Nothing usable found → nil so the caller keeps title-only rather than an empty card.
        guard artist != nil || album != nil || artworkData != nil else { return nil }
        return LooseTrackMetadata(artist: artist, album: album, artworkData: artworkData)
    }

    /// The first item for `key`, loaded as a trimmed non-empty string (nil = absent/empty, so the
    /// footer falls back to "Unknown Artist").
    private static func string(from items: [AVMetadataItem], key: AVMetadataKey) async -> String? {
        guard let item = items.first(where: { $0.commonKey == key }),
              let value = try? await item.load(.stringValue) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The first item for `key`, loaded as raw data (embedded cover art).
    private static func data(from items: [AVMetadataItem], key: AVMetadataKey) async -> Data? {
        guard let item = items.first(where: { $0.commonKey == key }) else { return nil }
        return try? await item.load(.dataValue)
    }
}
