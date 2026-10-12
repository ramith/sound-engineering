import Foundation
import LibraryStore

// MARK: - LibraryTrackDisplay + DetailTrack (S10.8 E2/E3)

/// A library song is a detail page's row as it is: it already has an id, an album, a disc and a
/// track number.
extension LibraryTrackDisplay: DetailTrack {
    /// The disc its folder names, by the store's own disc-folder rule (`AlbumGrouping`, the one that
    /// folds "CD 1" and "CD 2" into one album): "Live Set/CD 2/01.flac" → disc 2 of "Live Set".
    public var discFolder: DiscFolder? {
        let folder = url.deletingLastPathComponent()
        guard let disc = AlbumGrouping.discNumber(ofFolderName: folder.lastPathComponent), disc > 0 else {
            return nil
        }
        return DiscFolder(disc: disc, albumFolder: folder.deletingLastPathComponent().path)
    }
}
