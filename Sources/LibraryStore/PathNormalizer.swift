// PathNormalizer — canonical `tracks.url` string form (locked founder default).
//
// S8.1a. The store keys tracks on `url` (UNIQUE). To make that key stable across
// equivalent spellings of the same file, the URL string is normalized on the way
// in:
//   • NFC-precomposed  — HFS+/APFS can hand back decomposed Unicode (NFD) in
//     filenames; two byte-different-but-equivalent spellings must collapse to one
//     row, so we precompose to NFC.
//   • standardized absolute path — resolve "." / ".." and a leading "~", producing
//     an absolute path (a relative or tilde path would otherwise be a distinct key).
//   • symlinks are NOT resolved — a symlink and its target are legitimately
//     distinct library entries (founder decision); resolving them would merge rows
//     that the user may want separate.
//
// Pure and side-effect free (no filesystem access) so the harness can exercise it
// deterministically and it never asserts file existence (design §2a).

import Foundation

/// Canonicalizes a file URL into the string form stored in `tracks.url`.
public enum PathNormalizer {
    /// Normalize `url` to the canonical stored path string:
    /// standardized-absolute + NFC-precomposed, symlinks left intact.
    public static func normalizedString(for url: URL) -> String {
        // `standardizedFileURL` resolves "." / ".." and normalizes the path WITHOUT
        // resolving symlinks (unlike `resolvingSymlinksInPath`). It leaves a
        // relative URL relative, so make it absolute first.
        let absolute = url.isFileURL ? url : URL(fileURLWithPath: url.path)
        let standardized = absolute.standardizedFileURL
        return normalizedString(forPath: standardized.path)
    }

    /// Normalize a raw filesystem path string. A leading "~" is expanded; the path
    /// is made absolute against the current directory if needed, standardized, and
    /// NFC-precomposed. Symlinks are not resolved.
    public static func normalizedString(forPath path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        // standardizingPath yields a relative result for a relative input; anchor
        // it to an absolute path so equivalent inputs share one key.
        let absolute: String
        if standardized.hasPrefix("/") {
            absolute = standardized
        } else {
            let base = FileManager.default.currentDirectoryPath
            absolute = (base as NSString).appendingPathComponent(standardized)
        }
        return absolute.precomposedStringWithCanonicalMapping
    }

    /// `path` terminated with exactly one trailing "/", so it can serve as a
    /// path-COMPONENT-boundary prefix. Centralized here so the one safety-critical
    /// boundary construction lives in a SINGLE place — shared by `RelativePathResolver`
    /// (relative-path strip) and `RootValidation` (nested-root reject), which must
    /// never drift apart (both are the `/Music/Rock` ⊄ `/Music/RockAndRoll` rule).
    public static func directoryPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// `true` iff `candidate` is strictly BELOW `ancestor` at a path-COMPONENT boundary
    /// (`candidate` begins with `ancestor + "/"`) — never a bare string prefix. Equal
    /// paths are NOT descendants. Inputs are expected already-normalized (see
    /// `normalizedString`).
    public static func isComponentBoundaryDescendant(_ candidate: String, of ancestor: String) -> Bool {
        candidate.hasPrefix(directoryPrefix(ancestor))
    }
}
