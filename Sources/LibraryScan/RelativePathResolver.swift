// RelativePathResolver — the root-relative folder path for a scanned file (§4).
//
// S8.2a. Computes `tracks.relative_path`: the containing-directory of a file,
// relative to its scan root, e.g. root=/Music, file=/Music/Indie/2024/x.flac →
// "Indie/2024/" (trailing slash); a root-level file → "".
//
// Two corrections over today's `AudioFileEnumerator` (design §4):
//   (1) BOTH the root path and the file's containing-directory are normalized
//       through `PathNormalizer` first — so an NFC/NFD spelling difference between
//       the two can never leak a wrong prefix (and the result matches the stored
//       `tracks.url` key form).
//   (2) a COMPONENT-BOUNDARY strip (equal, or the file path has `root + "/"` as a
//       prefix) — fixing the live `/Music/Rock` vs `/Music/RockAndRoll` bug where a
//       raw `dropFirst(root.count)` would fold a sibling root's files into the
//       wrong root (AudioFileEnumerator.swift:51).
//
// Pure + side-effect free (no filesystem access) so the walk stays cheap and it is
// deterministically testable.

import Foundation
import LibraryStore

/// Derives a file's root-relative folder path (`tracks.relative_path`).
public enum RelativePathResolver {
    /// The containing-directory of `fileURL`, relative to `rootURL`, as
    /// `"Sub/Deep/"` (trailing slash) or `""` for a root-level file.
    ///
    /// If `fileURL` is not actually under `rootURL` (no component-boundary prefix
    /// match) the result is `""` — a defensive fallback; the walk only ever passes
    /// files enumerated beneath the root, so this cannot mis-attribute a sibling.
    public static func relativePath(forFile fileURL: URL, root rootURL: URL) -> String {
        let rootPath = PathNormalizer.normalizedString(for: rootURL)
        let dirPath = PathNormalizer.normalizedString(for: fileURL.deletingLastPathComponent())

        // Component-boundary: the containing dir IS the root → root-level file.
        if dirPath == rootPath {
            return ""
        }
        // Component-boundary: the dir must start with `root + "/"`, never a bare
        // string prefix (that is the /Music/Rock ⊄ /Music/RockAndRoll fix).
        let rootWithSeparator = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard dirPath.hasPrefix(rootWithSeparator) else {
            return ""
        }
        let suffix = dirPath.dropFirst(rootWithSeparator.count)
        let trimmed = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "" : trimmed + "/"
    }
}
