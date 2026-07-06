// MetadataProgress — the S8.3 metadata-pass progress tick (mirrors ScanProgress §5).
//
// Sendable, scalars only, so it crosses from the off-main pass to the VM's @MainActor.
// A per-file "a tag was read" signal: the VM publishes it (non-nil while the pass runs,
// nil at start/end) to drive the coarse "Reading tags…" indicator. It carries no counts
// today — the UI only observes presence, not progress magnitude.

import Foundation

public struct MetadataProgress: Sendable, Equatable {}
