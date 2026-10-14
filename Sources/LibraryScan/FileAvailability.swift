// FileAvailability — whether a library song can be played now, and when it can't, whether it is GONE
// (R1.1-A, KI-LIB-01).
//
// A file that is not at its path is not evidence that it is gone: its drive may be unplugged, another
// drive with the same name may be mounted at its path, or the app may not be allowed to look. A walk's
// sweep already refuses to delete on such evidence (`SweepRefusal`); a playlist's "Remove Missing…" must
// judge by the same rule, or an unplugged drive empties playlists for good. So a song is MISSING only
// when nothing is at its path (`FileSignature.isAbsent`) AND the folder that should hold it is there:
//   • a song in a music folder — that folder passes the check a walk makes before it starts
//     (`LibraryScanner.rootAtPath`: there, on its own drive; unbound, holding some of its songs);
//   • a song in no music folder (a loose one, a relocated one, a removed folder's playlist song) — the
//     folder it was in is there.
// Otherwise it is UNREACHABLE: unplayable now, and nothing offers to remove it.

import Foundation
import LibraryStore

/// Whether a library song's file can be played now — and if not, whether that is evidence it is gone.
public enum FileAvailability: Sendable, Equatable {
    /// The file is at its path.
    case available
    /// The file can't be reached now — its drive is away, another drive is at its path, or the app may
    /// not look — and that is no evidence it is gone.
    case unreachable
    /// The folder that holds the file is there, on its own drive, and the file is not: moved or deleted.
    case missing
}

public extension LibraryScanner {
    /// The availability of each file in `urls` now (see the file header): looks at each file, and at
    /// each music folder of an absent one once. `store` supplies the music folders and their drives.
    func availability(of urls: [URL], in store: LibraryStore) async throws -> [URL: FileAvailability] {
        let roots = try await store.roots()
        var rootIsThere: [Int64: Bool] = [:]
        var availability: [URL: FileAvailability] = [:]
        for url in urls where availability[url] == nil {
            availability[url] = try await self.availability(of: url, roots: roots, rootIsThere: &rootIsThere,
                                                            in: store)
        }
        return availability
    }
}

private extension LibraryScanner {
    /// One file's availability. `rootIsThere` remembers each music folder already looked at.
    func availability(of url: URL, roots: [LibraryFolder], rootIsThere: inout [Int64: Bool],
                      in store: LibraryStore) async throws -> FileAvailability {
        if FileManager.default.fileExists(atPath: url.path) {
            return .available
        }
        guard FileSignature.isAbsent(url) else { return .unreachable }
        let key = PathNormalizer.normalizedString(for: url)
        guard let root = roots.first(where: { PathNormalizer.isComponentBoundaryDescendant(key, of: $0.path) }) else {
            // In no music folder: gone only if the folder it was in is there.
            return RootReachabilityProbe.isReachable(url.deletingLastPathComponent()) ? .missing : .unreachable
        }
        if rootIsThere[root.id] == nil {
            let found = try await rootAtPath(URL(fileURLWithPath: root.path), folderID: root.id, in: store)
            if case .own = found {
                rootIsThere[root.id] = true
            } else {
                rootIsThere[root.id] = false
            }
        }
        return rootIsThere[root.id] == true ? .missing : .unreachable
    }
}
