// Schema+TrackIDs — the v11 → v12 migration (R1.1-B fix round; break-it BI-P01 / BI-P02): a song's id is
// never handed to another song.
//
// `tracks.id` is the song's durable identity — the queue's resume record names a library song by it alone
// (`QueueSlotRef.track(id:)`), the live queue re-reads its songs by it when the library changes, and a play
// is counted by it. But `tracks.id` is a plain `INTEGER PRIMARY KEY`, and SQLite gives a new row the
// highest id in use plus one — so when the newest songs leave (a sweep, Remove Folder, "Use this drive"
// not finding them) the next song added takes a removed song's id, and the queue's slot, its resume point
// and its play count land on a song the listener never queued.
//
// SQLite's own remedy, AUTOINCREMENT, is a table property: adding it means rebuilding `tracks`, the table
// every foreign key points at. Instead, additively:
//   • `track_id_high_water` — one row: the highest id a removed song had, seeded at the upgrade with the
//     highest id in use and the highest library id the queue's resume record names (a song that left
//     before the upgrade may still be named there);
//   • `tracks_id_high_water` — after a song's row goes, its id raises the mark;
//   • every insert takes the next id above the mark and above every id in use
//     (`Schema.nextTrackIDExpression`, the store's one insert path, `LibraryStore+DAO`);
//   • `tracks_id_never_reused` — a row inserted at or below the mark by any other path is refused: the
//     store never hands out a used id, whatever its caller does.
// So a removed song's id stays gone, and "a stored track id that is gone is dropped" (Schema+QueueState)
// holds.
//
// ADDITIVE and data-preserving: one new table and two triggers; no row of any existing table changes, and
// nothing a foreign key checks is touched.

import Foundation
import GRDB

public extension Schema.MigrationID {
    /// v11 → v12: track ids are never reused (R1.1-B fix round, BI-P01 / BI-P02).
    static let v12 = "v12-track-ids-never-reused"
}

public extension Schema {
    /// The id the next `tracks` row takes: one above every id ever used — the high-water mark of removed
    /// songs' ids, and every id in use. An SQL expression for an INSERT's `id` value.
    static let nextTrackIDExpression = """
    (SELECT MAX(w.high_water, COALESCE((SELECT MAX(t.id) FROM tracks t), 0)) + 1
     FROM track_id_high_water w WHERE w.id = 1)
    """

    /// The v12 statements: the high-water table, its seed, and the two triggers.
    static let createV12Statements: [String] = [
        """
        CREATE TABLE track_id_high_water (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            high_water INTEGER NOT NULL CHECK (high_water >= 0));
        """,
        // The seed: every id in use, and every library song the queue's resume record names — its slots
        // are `{"track":{"id":N}}` (`QueueSlotRef`, a frozen form). A record that is not JSON names none.
        """
        INSERT INTO track_id_high_water(id, high_water)
        SELECT 1, MAX(
            COALESCE((SELECT MAX(id) FROM tracks), 0),
            COALESCE((SELECT MAX(CAST(j.value AS INTEGER))
                      FROM queue_state q,
                           json_tree(CASE WHEN json_valid(q.record) THEN q.record ELSE '{}' END) j
                      WHERE j.key = 'id' AND j.path LIKE '%.track' AND j.type = 'integer'), 0));
        """,
        """
        CREATE TRIGGER tracks_id_high_water AFTER DELETE ON tracks
        WHEN OLD.id > (SELECT high_water FROM track_id_high_water WHERE id = 1)
        BEGIN
            UPDATE track_id_high_water SET high_water = OLD.id WHERE id = 1;
        END;
        """,
        """
        CREATE TRIGGER tracks_id_never_reused AFTER INSERT ON tracks
        WHEN NEW.id <= (SELECT high_water FROM track_id_high_water WHERE id = 1)
        BEGIN
            SELECT RAISE(ABORT, 'tracks.id is never reused: a removed song''s id was given to a new row');
        END;
        """,
    ]

    /// Migrate v11 → v12: track ids are never reused. Additive; every existing row keeps its data.
    static func migrateV11toV12(_ db: Database, appBuild: String?, timestamp: Int64) throws {
        for statement in createV12Statements {
            try db.execute(sql: statement)
        }
        try writeSchemaInfo(db, version: 12, appBuild: appBuild,
                            createdAt: timestamp, migratedAt: timestamp)
    }
}
