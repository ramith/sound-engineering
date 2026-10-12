import Foundation

// MARK: - AlbumTrackOrder (S10.8 E3 — an album's songs in playing order)

/// The order of one album's songs on a detail page — an album's page, and each album of an artist's
/// page: by disc, then track number, then title. The pages order their own rows rather than trust
/// the read's (which puts an untagged song first), so every page of an album agrees.
enum AlbumTrackOrder {
    /// An album's songs in playing order. A song with a track number but no disc counts as disc 1 (a
    /// single-disc album rarely tags it); one with no track number follows its disc's numbered songs,
    /// and one with neither ends the album. Ties — and the untagged — go by title, then stay as read.
    static func playing<Track: DetailTrack>(_ tracks: [Track]) -> [Track] {
        tracks.enumerated().sorted { left, right in
            let (leftPlace, rightPlace) = (place(of: left.element), place(of: right.element))
            if leftPlace.disc != rightPlace.disc {
                return leftPlace.disc < rightPlace.disc
            }
            if leftPlace.track != rightPlace.track {
                return leftPlace.track < rightPlace.track
            }
            return titleOrder(left, right)
        }.map(\.element)
    }

    /// Songs with no album between them (an artist's loose singles): by title — their track numbers
    /// belong to albums the library doesn't have, so they order nothing here.
    static func byTitle<Track: DetailTrack>(_ tracks: [Track]) -> [Track] {
        tracks.enumerated().sorted { titleOrder($0, $1) }.map(\.element)
    }

    /// Where a song sits in its album: its disc and track, the missing ones last.
    private static func place(of track: some DetailTrack) -> (disc: Int, track: Int) {
        let trackNo = track.trackNo ?? .max
        return (track.discNo ?? (track.trackNo == nil ? .max : 1), trackNo)
    }

    /// Title order as the Finder sorts names (case-blind, "Track 2" before "Track 10"); equal titles
    /// keep the order they were read in.
    private static func titleOrder<Track: DetailTrack>(
        _ left: EnumeratedSequence<[Track]>.Element, _ right: EnumeratedSequence<[Track]>.Element
    ) -> Bool {
        let order = left.element.title.localizedStandardCompare(right.element.title)
        return order == .orderedSame ? left.offset < right.offset : order == .orderedAscending
    }
}
