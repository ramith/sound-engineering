import io

# --- 1) LibraryStore+DAO.swift : upsertOne — bind dev, add to SET, keep out of WHERE ---
dao = "Sources/LibraryStore/LibraryStore+DAO.swift"
with io.open(dao, "r", encoding="utf-8") as fh:
    text = fh.read()

old_sql = """            INSERT INTO tracks(
                url, folder_id, relative_path, name, format,
                file_size, mtime, inode, date_added, last_seen_scan)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path,
                name = excluded.name,
                format = excluded.format,
                file_size = excluded.file_size,
                mtime = excluded.mtime,
                inode = excluded.inode,
                last_seen_scan = excluded.last_seen_scan
            WHERE tracks.file_size <> excluded.file_size
               OR tracks.mtime <> excluded.mtime
               OR tracks.name <> excluded.name
               OR tracks.format <> excluded.format
               OR tracks.relative_path <> excluded.relative_path
               OR tracks.folder_id IS NOT excluded.folder_id;"""

new_sql = """            INSERT INTO tracks(
                url, folder_id, relative_path, name, format,
                file_size, mtime, inode, dev, date_added, last_seen_scan)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                folder_id = excluded.folder_id,
                relative_path = excluded.relative_path,
                name = excluded.name,
                format = excluded.format,
                file_size = excluded.file_size,
                mtime = excluded.mtime,
                inode = excluded.inode,
                dev = excluded.dev,
                last_seen_scan = excluded.last_seen_scan
            WHERE tracks.file_size <> excluded.file_size
               OR tracks.mtime <> excluded.mtime
               OR tracks.name <> excluded.name
               OR tracks.format <> excluded.format
               OR tracks.relative_path <> excluded.relative_path
               OR tracks.folder_id IS NOT excluded.folder_id;"""
assert old_sql in text, "upsertOne SQL anchor not found"
text = text.replace(old_sql, new_sql, 1)

old_binds = """        try statement.bind(file.inode, at: 8)
        try statement.bind(dateAdded, at: 9) // real epoch; first insert only (out of the conflict SET)
        try statement.bind(generation, at: 10) // last_seen_scan"""
new_binds = """        try statement.bind(file.inode, at: 8)
        // dev + inode are move-signature (M-B): bound on insert AND set on the conflict
        // UPDATE (a replaced file at this url can have a different dev/inode), but they
        // are DELIBERATELY absent from the no-bump WHERE predicate above — that predicate
        // gates on CONTENT (size/mtime/name/format/path/folder), not the move-signature.
        try statement.bind(file.dev, at: 9)
        try statement.bind(dateAdded, at: 10) // real epoch; first insert only (out of the conflict SET)
        try statement.bind(generation, at: 11) // last_seen_scan"""
assert old_binds in text, "upsertOne binds anchor not found"
text = text.replace(old_binds, new_binds, 1)

with io.open(dao, "w", encoding="utf-8") as fh:
    fh.write(text)
print("DAO upsertOne patched (dev bound at 9; date_added->10, last_seen_scan->11)")

# --- 2) LibraryStore+Reads.swift : trackColumns + mapTrackRow read/pass dev ---
reads = "Sources/LibraryStore/LibraryStore+Reads.swift"
with io.open(reads, "r", encoding="utf-8") as fh:
    rtext = fh.read()

old_cols = ('    internal static let trackColumns =\n'
            '        "id, url, folder_id, relative_path, name, format, file_size, mtime, inode, "\n'
            '            + "album_id, artist_id, title, track_no, disc_no, year, duration_ms, artwork_key"')
new_cols = ('    internal static let trackColumns =\n'
            '        "id, url, folder_id, relative_path, name, format, file_size, mtime, inode, dev, "\n'
            '            + "album_id, artist_id, title, track_no, disc_no, year, duration_ms, artwork_key"')
assert old_cols in rtext, "trackColumns anchor not found"
rtext = rtext.replace(old_cols, new_cols, 1)

# mapTrackRow: insert dev after inode (index 9), shift the rest by +1.
old_map = """        LibraryTrack(
            id: statement.columnInt64(0),
            url: URL(fileURLWithPath: statement.columnText(1) ?? ""),
            folderID: statement.columnIsNull(2) ? nil : statement.columnInt64(2),
            relativePath: statement.columnText(3) ?? "",
            name: statement.columnText(4) ?? "",
            format: statement.columnText(5) ?? "",
            fileSize: statement.columnInt64(6),
            mtime: statement.columnInt64(7),
            inode: statement.columnIsNull(8) ? nil : statement.columnInt64(8),
            albumID: statement.columnIsNull(9) ? nil : statement.columnInt64(9),
            artistID: statement.columnIsNull(10) ? nil : statement.columnInt64(10),
            title: statement.columnText(11),
            trackNo: statement.columnIsNull(12) ? nil : statement.columnInt(12),
            discNo: statement.columnIsNull(13) ? nil : statement.columnInt(13),
            year: statement.columnIsNull(14) ? nil : statement.columnInt(14),
            durationMs: statement.columnInt64(15),
            artworkKey: statement.columnText(16)
        )"""
new_map = """        LibraryTrack(
            id: statement.columnInt64(0),
            url: URL(fileURLWithPath: statement.columnText(1) ?? ""),
            folderID: statement.columnIsNull(2) ? nil : statement.columnInt64(2),
            relativePath: statement.columnText(3) ?? "",
            name: statement.columnText(4) ?? "",
            format: statement.columnText(5) ?? "",
            fileSize: statement.columnInt64(6),
            mtime: statement.columnInt64(7),
            inode: statement.columnIsNull(8) ? nil : statement.columnInt64(8),
            dev: statement.columnIsNull(9) ? nil : statement.columnInt64(9),
            albumID: statement.columnIsNull(10) ? nil : statement.columnInt64(10),
            artistID: statement.columnIsNull(11) ? nil : statement.columnInt64(11),
            title: statement.columnText(12),
            trackNo: statement.columnIsNull(13) ? nil : statement.columnInt(13),
            discNo: statement.columnIsNull(14) ? nil : statement.columnInt(14),
            year: statement.columnIsNull(15) ? nil : statement.columnInt(15),
            durationMs: statement.columnInt64(16),
            artworkKey: statement.columnText(17)
        )"""
assert old_map in rtext, "mapTrackRow anchor not found"
rtext = rtext.replace(old_map, new_map, 1)

with io.open(reads, "w", encoding="utf-8") as fh:
    fh.write(rtext)
print("Reads trackColumns + mapTrackRow patched (dev at column 9; rest shifted +1)")
