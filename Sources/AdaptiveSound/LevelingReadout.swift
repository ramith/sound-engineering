import AudioDSP

// MARK: - What the song playing plays at (R1.1-B W5, lane 3-B; US-R1F-10 item 2, US-R1F-08 item 6)

/// The song playing's leveling plan as the engine made it — the one planner's answer (`asPlanTrack`), never a
/// second computation of it here — and the name of the layout it was planned for: what the Settings row's "This
/// song" line and the fold badge's "· measuring" read. `snapshot()` fills it on Enhanced (`SignalPathInfo.leveling`).
struct LevelingReadout: Equatable {
    /// How the plan levels.
    enum Mode: Equatable {
        /// No leveling gain (Leveling Off, or no decision).
        case off
        /// Leveled to −18 LUFS from the numbers.
        case leveled
        /// The loudness is unknown: the fixed −5 dB rule.
        case unknownCut
    }

    var mode: Mode
    /// g: the leveling gain the effects unit applies (dB).
    var gainDb: Double
    /// The fold's trim came from the track's measured fold; false: the matrix's worst case — the first play of a
    /// surround track nobody has measured yet ("· measuring").
    var foldMeasured: Bool
    /// The source's layout as the fold names it: its main channels and its LFE — "5.1", "7.1", "5.0". Nil when
    /// the source's roles are not known.
    var sourceLayout: String?
    /// Whether a measurement of the song is on its way while its plan lacks one: false when its analysis failed or
    /// cannot happen — the file cannot be identified, opened or analysed, or the analysis store would not open.
    /// The engine does not know it: the view model lays its own knowledge over the engine's readout
    /// (`AudioViewModel.levelingReadout(_:)`). "· measuring" is said only while it is true.
    var measurementComing = true
}

extension LevelingReadout {
    /// The readout of `plan`, planned against `output`.
    init(plan: AsTrackPlan, output: AsOutputState) {
        mode = switch Int(plan.mode) {
        case Int(AsLevelingModeLeveled.rawValue): .leveled
        case Int(AsLevelingModeUnknownCut.rawValue): .unknownCut
        default: .off
        }
        gainDb = plan.levelGainDb
        foldMeasured = plan.foldFromAnalysis != 0
        sourceLayout = Self.layoutName(roles: Self.roles(of: output))
    }

    /// "mains.lfe" from the channels' roles: "5.1" for L R C LFE Ls Rs; nil when no role is known.
    static func layoutName(roles: [UInt8]) -> String? {
        let unknown = UInt8(AsChannelRoleUnknown.rawValue)
        guard !roles.isEmpty, roles.contains(where: { $0 != unknown }) else { return nil }
        let lfe = roles.count { $0 == UInt8(AsChannelRoleLfe.rawValue) }
        return "\(roles.count - lfe).\(lfe)"
    }

    /// The source's roles, as many as it has channels.
    private static func roles(of output: AsOutputState) -> [UInt8] {
        let count = min(Int(output.sourceChannels), Int(AS_MAX_CHANNELS))
        return withUnsafeBytes(of: output.sourceRoles) { Array($0.prefix(count)) }
    }
}

extension EngineLevelingState {
    /// The audible track's plan, read for the main thread's snapshot with the output it was planned against — one
    /// read under the leveling lock, held only to copy (N12), so the layout's name is always the plan's own; nil
    /// before any track became audible.
    var readout: LevelingReadout? {
        audiblePlanned.map { LevelingReadout(plan: $0.plan, output: $0.output) }
    }
}
