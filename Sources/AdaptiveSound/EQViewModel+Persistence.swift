import Foundation

// MARK: - EQViewModel Persistence

/// UserDefaults-backed persistence for saved custom presets and the
/// per-output-device preset recall map. All keys are versioned so a future
/// schema change can migrate or discard stale data without a crash.
///
/// Format v1:
///   `eqCustomPresetsV1`   — JSON-encoded `[String: [Float]]`
///   `eqOutputPresetMapV1` — JSON-encoded `[String: String]`
///   `eqLiveStateV1`       — JSON-encoded `EQLiveState` (active preset + 31-band gains)
extension EQViewModel {
    // MARK: - UserDefaults keys

    private enum UDKey {
        static let customPresets = "eqCustomPresetsV1"
        static let outputPresetMap = "eqOutputPresetMapV1"
        static let liveState = "eqLiveStateV1"
    }

    // MARK: - Load

    /// Load all persisted collections from UserDefaults and restore the last live EQ state.
    /// Called once from `init`; tolerates missing or corrupted data silently.
    func loadPersistedState() {
        savedCustomPresets = loadCustomPresets()
        outputPresetMap = loadOutputPresetMap()
        restoreLiveState()
        logUX("EQ persistence: loaded \(savedCustomPresets.count) custom preset(s), "
            + "\(outputPresetMap.count) device mapping(s), live='\(selectedPresetName)'")
    }

    // MARK: - Custom Presets

    /// Persist `savedCustomPresets` to UserDefaults as JSON.
    func persistCustomPresets() {
        guard let data = try? JSONEncoder().encode(savedCustomPresets) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.customPresets)
    }

    private func loadCustomPresets() -> [String: [Float]] {
        guard
            let data = UserDefaults.standard.data(forKey: UDKey.customPresets),
            let decoded = try? JSONDecoder().decode([String: [Float]].self, from: data)
        else { return [:] }
        // Validate: each array must be exactly 31 bands.
        return decoded.filter { $0.value.count == 31 }
    }

    // MARK: - Output Preset Map

    /// Persist `outputPresetMap` to UserDefaults as JSON.
    func persistOutputPresetMap() {
        guard let data = try? JSONEncoder().encode(outputPresetMap) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.outputPresetMap)
    }

    private func loadOutputPresetMap() -> [String: String] {
        guard
            let data = UserDefaults.standard.data(forKey: UDKey.outputPresetMap),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return decoded
    }

    // MARK: - Live State ("remember last setting")

    /// Persist the CURRENT active EQ (selected preset + band gains) to UserDefaults as JSON.
    /// Called after every committed mutation (`selectPreset` / `selectCustomPreset` /
    /// `commitCustomBandEdits`). `presetRaw = selectedPreset?.rawValue` — `nil` means Custom.
    func persistLiveState() {
        let state = EQLiveState(presetRaw: selectedPreset?.rawValue, bandGains: bandGains)
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: UDKey.liveState)
    }

    /// Restore the last live EQ state into `bandGains` + `selectedPreset`.
    ///
    /// Defense-in-depth (matching `commitCustomBandEdits`): the decoded gains must be exactly
    /// 31 bands, and every band is clamped to the DSP range `[-12, +12]` dB. Missing / corrupt /
    /// wrong-count data leaves the current defaults untouched (`.flat` / zeros) — never crashes,
    /// mirroring `loadCustomPresets`' 31-band filter.
    ///
    /// Preset mapping: `presetRaw == nil` ⇒ Custom (`selectedPreset = nil`); a known rawValue ⇒
    /// that `EQPreset`; an unknown/renamed rawValue degrades to Custom (`flatMap` → `nil`) while
    /// keeping the validated curve, so the user's last-heard shape is preserved.
    private func restoreLiveState() {
        guard let state = loadLiveState(), state.bandGains.count == 31 else { return }
        bandGains = state.bandGains.map { max(-12.0, min(12.0, $0)) }
        selectedPreset = state.presetRaw.flatMap(EQPreset.init(rawValue:))
    }

    private func loadLiveState() -> EQLiveState? {
        guard
            let data = UserDefaults.standard.data(forKey: UDKey.liveState),
            let decoded = try? JSONDecoder().decode(EQLiveState.self, from: data)
        else { return nil }
        return decoded
    }
}
