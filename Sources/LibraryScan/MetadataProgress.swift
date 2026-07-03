// MetadataProgress — the S8.3 metadata-pass progress tick (mirrors ScanProgress §5).
//
// Sendable, scalars only, so it crosses from the off-main pass to the VM's @MainActor.
// Unlike the scan (a lazy single-pass walk → indeterminate), the metadata pass starts
// from a KNOWN id list, so `totalToProcess` is populated → a determinate progress bar.

import Foundation

public struct MetadataProgress: Sendable, Equatable {
    /// Tracks whose metadata attempt has completed so far this pass.
    public let filesProcessedSoFar: Int
    /// Total tracks the pass will attempt (known up front), or nil if indeterminate.
    public let totalToProcess: Int?

    public init(filesProcessedSoFar: Int, totalToProcess: Int?) {
        self.filesProcessedSoFar = filesProcessedSoFar
        self.totalToProcess = totalToProcess
    }
}
