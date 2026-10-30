// MARK: - SignalPathInfo: the fold, as the hero and the Headphones section show it (R1.1-B W5, lane 3-B)

extension SignalPathInfo {
    /// The badge while the fold plays (US-R1F-08 item 6): "5.1 → stereo" ("7.1 → stereo"), and "… · measuring" on
    /// the first play of a surround track nobody has measured yet — its trim the matrix's worst case, quieter and
    /// clean, until the analysis lands (founder, 2026-10-26). Nil when nothing folds (and always on Pure).
    var foldBadge: String? {
        guard path == .enhanced, let fold else { return nil }
        let badge = "\(Self.layoutName(fold: fold, readout: leveling)) → stereo"
        return foldIsMeasuring ? badge + " · measuring" : badge
    }

    /// The badge as VoiceOver reads it: "5.1 folded to stereo, measuring".
    var spokenFoldBadge: String? {
        guard path == .enhanced, let fold else { return nil }
        let spoken = "\(Self.layoutName(fold: fold, readout: leveling)) folded to stereo"
        return foldIsMeasuring ? spoken + ", measuring" : spoken
    }

    /// The fold plays its track's plan, and that plan's trim is the worst case: the track was not measured.
    private var foldIsMeasuring: Bool {
        fold?.fromPlan == true && leveling?.foldMeasured == false
    }

    /// The source's layout name: from its channels' roles when the plan knows them ("5.0", "5.1"), else by its
    /// count, read as the role resolver's WAV-order fallback does (6: 5.1, 8: 7.1, 7: 6.1; fewer: no LFE).
    static func layoutName(fold: FoldState, readout: LevelingReadout?) -> String {
        if let named = readout?.sourceLayout {
            return named
        }
        let channels = fold.sourceChannels
        return channels >= 6 ? "\(channels - 1).1" : "\(channels).0"
    }

    /// Crossfeed is chosen and plays on this output, but the file playing folds to stereo, where the engine
    /// bypasses it (stereo-only until the fold moves into the engine — KI-SND-06): the Headphones section says so.
    var crossfeedHeldBySurround: Bool {
        path == .enhanced && fold != nil && crossfeedStrength != nil
    }
}
