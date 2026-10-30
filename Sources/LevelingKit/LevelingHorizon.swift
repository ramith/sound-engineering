// LevelingKit — the horizon rule (R1.1-B W5, lane 3-A; level-and-fold "The store and the scheduler", §12 F-8;
// US-R1F-10 item 17): which albums are analysed ahead of play. The founder's rule (2026-10-26): albums are measured
// only within the next ~2 hours of the queue, never as a library sweep.

/// What is analysed ahead of play, and when each is needed.
public enum LevelingHorizon {
    /// How far ahead of the current slot the queue is looked at (seconds of play).
    public static let span = 2.0 * 3600
    /// At least this many albums are analysed ahead, however long they are.
    public static let minimumAlbums = 3
    /// The length assumed for a track whose length is not known yet (seconds), so an unknown length never makes
    /// the horizon endless.
    public static let assumedTrackSeconds = 240.0

    /// One slot of the upcoming play order.
    public struct Entry: Sendable, Equatable {
        /// The track's key (`LevelingLibrary.tracks`).
        public var key: String
        /// The library's album id; nil for a loose file or a song with no album title.
        public var album: Int64?
        /// The track's length (seconds); nil or 0 when unknown.
        public var durationSeconds: Double?

        public init(key: String, album: Int64?, durationSeconds: Double?) {
            self.key = key
            self.album = album
            self.durationSeconds = durationSeconds
        }
    }

    /// What one analysis job covers: a whole album, or one track that belongs to none.
    public enum Target: Sendable, Hashable {
        case album(Int64)
        case track(String)
    }

    /// A target and how soon it plays: the time from now until its first slot starts (0 for the current slot).
    public struct Need: Sendable, Equatable {
        public var target: Target
        public var startsIn: Double

        public init(target: Target, startsIn: Double) {
            self.target = target
            self.startsIn = startsIn
        }
    }

    /// The targets to analyse, most urgent first, for the upcoming play order `upcoming` (its first entry is the
    /// current slot; the rest in play order, shuffle's permutation and Repeat's wrap included): the current slot's
    /// album, then every album and loose track starting within `span`, then further albums until at least
    /// `minimumAlbums`. `elapsed` is how far into the current slot play is (seconds). An album met again is one
    /// target, at its first start.
    public static func needs(upcoming: [Entry], elapsed: Double = 0) -> [Need] {
        var needs: [Need] = []
        var seen = Set<Target>()
        var albums = 0
        var start = -max(0, elapsed)
        for (index, entry) in upcoming.enumerated() {
            let startsIn = max(0, start)
            let within = index == 0 || startsIn < span
            if !within, albums >= minimumAlbums {
                break
            }
            start += length(of: entry)
            let target: Target? = if let album = entry.album {
                .album(album)
            } else {
                within ? .track(entry.key) : nil // past the span, only albums count
            }
            guard let target, seen.insert(target).inserted else { continue }
            needs.append(Need(target: target, startsIn: startsIn))
            if entry.album != nil {
                albums += 1
            }
        }
        return needs
    }

    /// How long `entry` plays: its length, or `assumedTrackSeconds` when that is not known.
    private static func length(of entry: Entry) -> Double {
        guard let seconds = entry.durationSeconds, seconds > 0, seconds.isFinite else { return assumedTrackSeconds }
        return seconds
    }
}
