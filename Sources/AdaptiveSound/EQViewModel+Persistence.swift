import Foundation

// MARK: - EQViewModel Persistence

/// UserDefaults-backed persistence for saved custom presets and the
/// per-output-device preset recall map. All keys are versioned so a future
/// schema change can migrate or discard stale data without a crash.
///
/// Format v1:
///   `eqCustomPresetsV1`   — JSON-encoded `[String: [Float]]`
///   `eqOutputPresetMapV1` — JSON-encoded `[String: String]`
extension EQViewModel {
    // MARK: - UserDefaults keys

    private enum UDKey {
        static let customPresets = "eqCustomPresetsV1"
        static let outputPresetMap = "eqOutputPresetMapV1"
    }

    // MARK: - Load

    /// Load both persisted collections from UserDefaults.
    /// Called once from `init`; tolerates missing or corrupted data silently.
    func loadPersistedState() {
        savedCustomPresets = loadCustomPresets()
        outputPresetMap = loadOutputPresetMap()
        logUX("EQ persistence: loaded \(savedCustomPresets.count) custom preset(s), "
            + "\(outputPresetMap.count) device mapping(s)")
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
}
