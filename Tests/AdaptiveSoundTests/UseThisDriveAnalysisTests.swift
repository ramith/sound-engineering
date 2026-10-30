@testable import AdaptiveSound
import AudioDSP
import Foundation
import LibraryBrowseKit
import LibraryScan
import LibraryStore
import RigKit
import Testing
@testable import TrackLoudnessKit

// MARK: - "Use this drive" keeps the songs' analyses (R1.1-B W5, lane 3-A; US-R1F-10 item 16)

//
// The real `LibraryModel` over a real store and real folders, and a real analysis store open beside them, handed to
// the library as the app hands it at launch. A paused music folder is pointed at its copy on another drive: after
// the rebind, the analysis of each song found is under the song's new path — the same size and modification time —
// so it is not measured again; a song whose copy differs (the rebind removes it) keeps its old record, and its copy
// has none. Only the store the library was handed moves.

@MainActor
@Suite("“Use this drive” — the songs' analyses follow them", .serialized, .timeLimit(.minutes(3)), .attachingLogTail)
struct UseThisDriveAnalysisTests {
    @Test("REKEY-01: after a rebind each song's analysis is at its new path; a song changed on the copy is not")
    func analysesFollowTheSongs() async throws {
        QuietLog.install()
        let fixture = try await LibraryFolderFixture.make(titled: [("One", "A"), ("Two", "A"), ("Three", "B")])
        defer { fixture.discard() }
        let library = LibraryModel(storeless: ())
        library.store = fixture.store
        let analyses = try TrackAnalysisStore(directory: fixture.base.appendingPathComponent("app-data"))
        library.analysisStore = analyses // as the composition root hands it over (Edge 6)
        for file in fixture.files {
            try await analyses.save(Self.analysis(of: #require(TrackIdentity(url: file))))
        }
        // The folder copied to another drive (copies keep their modification times); the third song re-tagged
        // there, so its size differs; the old drive gone and the folder paused for it, as a walk leaves it.
        let newRoot = fixture.base.appendingPathComponent("Music on T7 1", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.music, to: newRoot)
        let changed = newRoot.appendingPathComponent(fixture.files[2].lastPathComponent)
        let handle = try FileHandle(forWritingTo: changed)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([9]))
        try handle.close()
        try FileManager.default.removeItem(at: fixture.music)
        library.reconcileState[fixture.folderID] = .paused(.rootVanished)

        let result = await library.useDrive(newRoot, forFolder: fixture.folderID)
        #expect(result?.outcome == .rebound(kept: 2, removed: 1)) // the rebind matches on size too
        let moved = try fixture.files.prefix(2).map { file in
            try #require(TrackIdentity(url: newRoot.appendingPathComponent(file.lastPathComponent)))
        }
        #expect(try await analyses.analyses(for: moved).count == 2)
        let changedNow = try #require(TrackIdentity(url: changed))
        #expect(try await analyses.analyses(for: [changedNow]).isEmpty) // another file now: measured again
        try await until("the reconcile walk after the rebind to end") { library.walkTasks.isEmpty }
    }

    @Test("REKEY-02: the re-key reaches the store the library was handed, and no other open in the process")
    func onlyItsOwnStore() async throws {
        QuietLog.install()
        let fixture = try await LibraryFolderFixture.make(titled: [("One", "A")])
        defer { fixture.discard() }
        let library = LibraryModel(storeless: ())
        library.store = fixture.store
        // Another store open in this process (another data folder: a test library, a test), never handed to this
        // library, holding a record of the same song.
        let other = try TrackAnalysisStore(directory: fixture.base.appendingPathComponent("other-app-data"))
        let song = try #require(TrackIdentity(url: fixture.files[0]))
        try await other.save(Self.analysis(of: song))
        let newRoot = fixture.base.appendingPathComponent("Music on T7 2", isDirectory: true)
        try FileManager.default.copyItem(at: fixture.music, to: newRoot)
        try FileManager.default.removeItem(at: fixture.music)
        library.reconcileState[fixture.folderID] = .paused(.rootVanished)

        let result = await library.useDrive(newRoot, forFolder: fixture.folderID)
        #expect(result?.outcome == .rebound(kept: 1, removed: 0))
        #expect(try await other.analyses(for: [song]).count == 1, "a store the library was never given was re-keyed")
        try await until("the reconcile walk after the rebind to end") { library.walkTasks.isEmpty }
    }

    /// A minimal current-version analysis of `identity`.
    private static func analysis(of identity: TrackIdentity) -> TrackAnalysis {
        TrackAnalysis(version: Int(AS_TRACK_ANALYSIS_VERSION), identity: identity, channelCount: 2, roles: [1, 2],
                      sourceRateHz: 48000, peakRateHz: 48000, durationSeconds: 1, integratedLufs: -20,
                      truePeakDbtp: -3, headBlockLufs: -20, tailBlockLufs: -20, folds: false,
                      foldedLufs: [nil, nil, nil, nil], foldedTruePeakDbtp: [nil, nil, nil, nil],
                      lfe: .init(activeBlocks: 0, lagMs: nil, lagPeak: nil, coherentShare: nil, medianR2: nil,
                                 p90R2: nil, excess20Share: nil, explainGainDb: nil),
                      histograms: [], profiles: [])
    }
}
