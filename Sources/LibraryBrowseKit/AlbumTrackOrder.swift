import Foundation

// MARK: - AlbumTrackOrder (S10.8 E3 — an album's songs in playing order)

/// The order of one album's songs on a detail page — an album's page, each album of an artist's
/// page, and each album's run on a genre's page: by disc, then track number, then title. The pages
/// order their own rows rather than trust the read's (which puts an untagged song first), so every
/// page of an album agrees.
enum AlbumTrackOrder {
    /// An album's songs in playing order, each with the disc it plays on:
    /// - the disc is its tag; without one, the disc its folder names, where the album's untagged
    ///   songs sit in two or more sibling disc folders ("CD 1", "CD 2" — a set ripped one folder per
    ///   disc, which the store folds into one album); else disc 1 for a numbered track;
    /// - within a disc, by track number; a song with no number follows its disc's numbered songs,
    ///   and one with neither disc nor number ends the album (disc nil);
    /// - ties, and the untagged, by title; then as read.
    /// A number of zero or less is no number (`taggedTrackNo` / `taggedDiscNo`).
    static func playing<Track: DetailTrack>(_ tracks: [Track]) -> [(track: Track, disc: Int?)] {
        let folderDiscs = folderDiscs(tracks)
        return tracks.enumerated().map { offset, track in
            Place(track: track, offset: offset, disc: track.taggedDiscNo ?? folderDiscs[offset]
                ?? (track.taggedTrackNo == nil ? nil : 1))
        }
        .sorted { precedes($0, $1) }
        .map { ($0.track, $0.disc) }
    }

    /// Songs with no album between them (an artist's loose singles): by title — their track numbers
    /// belong to albums the library doesn't have, so they order nothing here.
    static func byTitle<Track: DetailTrack>(_ tracks: [Track]) -> [Track] {
        tracks.enumerated().map { Place(track: $1, offset: $0, disc: nil) }
            .sorted { titleOrder($0, $1) }
            .map(\.track)
    }

    // MARK: Private

    /// A song and what orders it.
    private struct Place<Track: DetailTrack> {
        let track: Track
        /// Its place in the read: the last tie-break.
        let offset: Int
        let disc: Int?
    }

    /// The disc each song's folder names — for the songs with no disc tag, and only where those
    /// songs sit in sibling disc folders naming at least two discs; else nil for every song.
    private static func folderDiscs<Track: DetailTrack>(_ tracks: [Track]) -> [Int?] {
        let folders = tracks.map { $0.taggedDiscNo == nil ? $0.discFolder : nil }
        let named = folders.compactMap(\.self)
        guard Set(named.map(\.albumFolder)).count == 1, Set(named.map(\.disc)).count > 1 else {
            return Array(repeating: nil, count: tracks.count)
        }
        return folders.map { $0?.disc }
    }

    private static func precedes<Track: DetailTrack>(_ left: Place<Track>, _ right: Place<Track>) -> Bool {
        let (leftDisc, rightDisc) = (left.disc ?? .max, right.disc ?? .max)
        if leftDisc != rightDisc {
            return leftDisc < rightDisc
        }
        let (leftTrack, rightTrack) = (left.track.taggedTrackNo ?? .max, right.track.taggedTrackNo ?? .max)
        if leftTrack != rightTrack {
            return leftTrack < rightTrack
        }
        return titleOrder(left, right)
    }

    /// Title order as the Finder sorts names (case-blind, "Track 2" before "Track 10"); equal titles
    /// keep the order they were read in.
    private static func titleOrder<Track: DetailTrack>(_ left: Place<Track>, _ right: Place<Track>) -> Bool {
        let order = left.track.title.localizedStandardCompare(right.track.title)
        return order == .orderedSame ? left.offset < right.offset : order == .orderedAscending
    }
}
