// RootValidation — reject nested / overlapping scan roots (design §6, M-A, O-2).
//
// S8.2b. A new root must NOT be an ancestor-or-descendant of an existing root:
// overlapping roots would ping-pong a shared file's `folder_id` between them under
// `UNIQUE(url)` and confuse each root's end-of-walk sweep (design §6). This validates
// BEFORE any walk (and before `addRoot`), throwing a typed error that CARRIES the
// conflicting root — mirroring `URLConflict`'s shape so callers can surface exactly
// which existing root clashed and how (ancestor vs descendant).
//
// The compare is a NORMALIZED-PATH COMPONENT-BOUNDARY test via `PathNormalizer` — the
// same discipline `RelativePathResolver` uses — never a naive string prefix, so
// `/Music/Rock` and `/Music/RockAndRoll` are correctly SIBLINGS (not nested). An
// EXACT-duplicate path is NOT a conflict here: it stays the idempotent `addRoot`
// no-op (design §6), so `validateNewRoot` treats equal paths as allowed.

import Foundation
import LibraryStore

/// How a proposed new root overlaps an existing one (the two rejected relationships).
public enum RootConflictKind: Sendable, Equatable {
    /// The new root is an ANCESTOR of the existing root (the new root would contain it).
    case ancestorOfExisting
    /// The new root is a DESCENDANT of the existing root (nested inside it).
    case descendantOfExisting
}

/// A typed rejection: the proposed root overlaps `existingRoot`. Mirrors
/// `URLConflict` (design §4, M6) — a typed error carrying the conflicting entity so
/// the caller can report it precisely rather than parsing a generic message.
/// `Sendable` — plain strings only, no handle.
public struct NestedRootConflict: Error, Sendable, Equatable {
    /// The normalized path of the proposed new root.
    public let newRoot: String
    /// The normalized path of the EXISTING root it overlaps.
    public let existingRoot: String
    /// Whether the new root is an ancestor of, or a descendant of, `existingRoot`.
    public let kind: RootConflictKind

    public init(newRoot: String, existingRoot: String, kind: RootConflictKind) {
        self.newRoot = newRoot
        self.existingRoot = existingRoot
        self.kind = kind
    }
}

public extension LibraryScanner {
    /// Validate a proposed new scan root against the `existing` roots (design §6).
    /// Throws `NestedRootConflict` (carrying the clashing existing root) when `root`
    /// is an ancestor-or-descendant of any existing root. An EXACT-duplicate path is
    /// allowed (it is the idempotent `addRoot` no-op). Call BEFORE `addRoot` + walk.
    ///
    /// The compare is COMPONENT-BOUNDARY on normalized paths (via `PathNormalizer`),
    /// so `/Music/Rock` vs `/Music/RockAndRoll` are siblings, never nested.
    ///
    /// - Parameters:
    ///   - root: the URL the user is trying to register.
    ///   - existing: the URLs of the roots already registered (`store.roots()` paths).
    func validateNewRoot(_ root: URL, against existing: [URL]) throws {
        let newPath = PathNormalizer.normalizedString(for: root)
        for existingURL in existing {
            let existingPath = PathNormalizer.normalizedString(for: existingURL)
            if newPath == existingPath {
                continue // exact duplicate → idempotent addRoot no-op, not a conflict.
            }
            if Self.isDescendant(newPath, of: existingPath) {
                throw NestedRootConflict(
                    newRoot: newPath, existingRoot: existingPath, kind: .descendantOfExisting
                )
            }
            if Self.isDescendant(existingPath, of: newPath) {
                throw NestedRootConflict(
                    newRoot: newPath, existingRoot: existingPath, kind: .ancestorOfExisting
                )
            }
        }
    }

    /// `true` iff `candidate` is strictly BELOW `ancestor` at a path-COMPONENT
    /// boundary — `candidate` begins with `ancestor + "/"`. A bare string prefix is
    /// deliberately NOT enough (that is the `/Music/Rock` ⊄ `/Music/RockAndRoll` fix).
    /// Equal paths are not descendants (handled as the duplicate no-op by the caller).
    private static func isDescendant(_ candidate: String, of ancestor: String) -> Bool {
        let ancestorWithSeparator = ancestor.hasSuffix("/") ? ancestor : ancestor + "/"
        return candidate.hasPrefix(ancestorWithSeparator)
    }
}
