import AudioDSP
@preconcurrency import AVFoundation
import Foundation
import TrackLoudnessKit

// MARK: - AudioEngineBridge track loudness (Sprint EQ, EQ1c part 2)

/// Caseless-enum namespace holding the loudness C-ABI, so the extension's own methods never
/// shadow the free functions (the `CIntensityABI` pattern). Immutable C-function pointers.
private enum CTrackLoudnessABI {
    static let publish: @Sendable (UnsafeMutableRawPointer?, UInt64, OpaquePointer?) -> Bool =
        publishTrackLoudnessProfile
    static let fail: @Sendable (UnsafeMutableRawPointer?, UInt64) -> Void = reportTrackLoudnessFailure
}

/// The loudness-neutral EQ gain follows the AUDIBLE track (amendments item 3), and so does the
/// loudness readout's "Integrated" (council C-46). The bridge is the only place that knows when a
/// track becomes audible — a fresh start in `playFile`, or a gapless seam at `bumpTransitionCount`
/// — and the only caller of `applyTrackPlan` (through the planner, `planAudible`) and
/// `loudnessMeterBeginTrack`; the analyzer is the only caller of `publishTrackLoudnessProfile` /
/// `reportTrackLoudnessFailure` (through this sink). The EQ view model never touches either. Enhanced
/// path only: Pure Mode bypasses the EQ, so it analyses nothing, and installs no meter.
extension AudioEngineBridge: TrackLoudnessSink {
    /// `url` became the audible track: by a fresh start, or at a gapless seam (`gaplessSeam`) —
    /// never when it is merely scheduled. The planner plans it once and both units get the plan — a
    /// resume of it keeps the plan it has, a new play is planned afresh (`planAudible`,
    /// AudioEngineBridge+Leveling); the engine switches the gain to it, the readout's "Integrated"
    /// measures it — from its start when it is a new track, carrying on when the same one is announced
    /// again — and the analyzer profiles it (promoting the next-track prefetch, or re-publishing a
    /// cached profile).
    func trackBecameAudible(_ url: URL, gaplessSeam: Bool) {
        let identity = TrackIdentity(url: url)
        let token = identity?.token ?? 0
        // The plan, once, to both units (R1.1-B, B1): the request's decision, its saved profile first.
        let savedProfile = planAudible(url, token: token, gaplessSeam: gaplessSeam)
        if let meter = tapAnalysis.meter {
            withExtendedLifetime(meter) { loudnessMeterBeginTrack(meter.handle, token) }
        }
        // A saved profile is final (C2): nothing for the analyzer to do. Otherwise it profiles the track as today —
        // on the file's own layout, so a folded first play's −ΔL is the decoded basis's, not §7's fold with the LFE
        // omitted (review N15, a recorded deviation: the profiler is TrackLoudnessKit's; with the EQ on, about 1 dB
        // of ΔL on that first play only — the next one has the saved fold profile).
        if let identity, !savedProfile {
            loudnessAnalyzer.analyze(url, identity: identity, as: .current, sink: self)
        }
    }

    /// Prefetch the profile of the track armed for the gapless seam (`nil`: none armed).
    func prefetchTrackLoudness(_ url: URL?) {
        guard let url, let identity = TrackIdentity(url: url) else {
            loudnessAnalyzer.cancel(.next)
            return
        }
        loudnessAnalyzer.analyze(url, identity: identity, as: .next, sink: self)
    }

    // MARK: TrackLoudnessSink (called by the analyzer, from its own threads)

    func publishLoudnessProfile(_ profile: TrackLoudnessProfileHandle, token: UInt64) {
        withLoudnessAU { _ = CTrackLoudnessABI.publish($0, token, profile.pointer) }
    }

    func reportLoudnessAnalysisFailure(token: UInt64) {
        withLoudnessAU { CTrackLoudnessABI.fail($0, token) }
    }

    /// Run `body` with the live AU's borrowed handle (`withEffectsAU`); a no-op when the AU is not
    /// live.
    private func withLoudnessAU(_ body: (UnsafeMutableRawPointer) -> Void) {
        _ = withEffectsAU(body)
    }
}
