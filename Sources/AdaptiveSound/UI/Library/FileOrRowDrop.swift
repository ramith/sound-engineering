import CoreTransferable
import Foundation

// MARK: - A drop of the app's own rows, or of files from Finder (R1.1-B, US-LIB-02 / US-PLIST-02)

/// What a row that takes the app's own drags — a library song onto a playlist in the rail, a playlist
/// entry or a queue slot onto its list — makes of a drop: one of those rows, or files dragged in from
/// Finder. The row drags travel as plain text (a custom type undeclared in Info.plist would never match,
/// `LibraryTrackDragItem`); Finder's carry file URLs (and may carry the file's name as text too). The FILE
/// representation is listed first, so a Finder drag is read as its files and never as a row id, while a
/// row drag — which carries no URL — is read as the row. Without it a row drop target swallowed a Finder
/// drag as a garbage id and no-oped, and the file drop around it never fired.
enum FileOrRowDrop<Row: Transferable & Sendable>: Transferable {
    case file(URL)
    case row(Row)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in FileOrRowDrop.file(url) })
        ProxyRepresentation(importing: { (row: Row) in FileOrRowDrop.row(row) })
    }

    /// The files of a drop (a Finder drag), in order.
    static func files(_ drops: [Self]) -> [URL] {
        drops.compactMap { drop in
            if case let .file(url) = drop, url.isFileURL {
                url
            } else {
                nil
            }
        }
    }

    /// The rows of a drop (one of the app's own drags), in order.
    static func rows(_ drops: [Self]) -> [Row] {
        drops.compactMap { drop in
            if case let .row(row) = drop {
                row
            } else {
                nil
            }
        }
    }
}
