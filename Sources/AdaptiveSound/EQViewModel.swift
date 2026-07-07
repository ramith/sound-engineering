import Foundation

// MARK: - EQViewModel

/// Manages 31-band EQ state and dispatches gain changes to the DSP kernel.
///
/// Preset shapes live in `EQPreset.gains` (the single source of truth).
/// All mutations go through `commitCustomBandEdits()` or `selectPreset(_:)`,
/// both of which call `dispatchAllBands()` exactly once per user action.
///
/// Presets are typed as `EQPreset`; "Custom" is represented by setting
/// `selectedPreset` to `nil`. User-saved custom presets (`savedCustomPresets`)
/// and per-output-device preset recall (`outputPresetMap`) are persisted to
/// `UserDefaults`; see `EQViewModel+Persistence.swift`.
@MainActor
@Observable
final class EQViewModel {
    // MARK: - State

    /// Per-band gains in dB, indexed 0–30 for ISO 266 1/3-octave bands.
    /// Range: -12 to +12 dB per band. Observed by the canvas and sliders.
    var bandGains: [Float] = .init(repeating: 0.0, count: 31)

    /// The active named preset, or `nil` when the user has made custom edits.
    var selectedPreset: EQPreset? = .flat

    // MARK: - Custom presets

    /// User-saved custom presets: a name → 31-band gain array map.
    /// Persisted to UserDefaults; loaded on init.
    var savedCustomPresets: [String: [Float]] = [:]

    // MARK: - Per-output recall

    /// Device ID (UInt32) → preset identifier (raw value string or custom-preset name).
    /// Persisted to UserDefaults; loaded on init.
    var outputPresetMap: [String: String] = [:]

    // MARK: - Banner

    /// Non-nil when an auto-recall banner should be shown. Cleared by the view after display.
    var recallBannerMessage: String?

    // MARK: - Derived state

    /// Display name shown in preset picker and accessibility values.
    var selectedPresetName: String {
        selectedPreset?.displayName ?? "Custom"
    }

    // MARK: - Private

    private let audioViewModel: AudioViewModel

    // MARK: - Init

    init(audioViewModel: AudioViewModel) {
        self.audioViewModel = audioViewModel
        loadPersistedState()
        // "Remember last setting" — HEADLESS re-dispatch of the restored curve.
        //
        // `dispatchAllBands()` no-ops until `audioViewModel.isEngineReady`, which is still false
        // here at init. So we hook the engine-ready lifecycle transition to re-dispatch once the
        // AU is live — even with the EQ tab closed (the DSP graph runs regardless of which tab is
        // visible). This is a lifecycle hook (analogous to the engine's `onOutputDevicesChanged`),
        // NOT the F3-forbidden device-recall callback. `[weak self]` — no retain cycle.
        audioViewModel.onEngineReady = { [weak self] in self?.dispatchAllBands() }
        // Also dispatch once now: idempotent — no-ops if the engine isn't ready yet (the hook
        // above will fire), dispatches immediately if the engine is already up.
        dispatchAllBands()
    }

    // MARK: - Preset Selection

    /// Apply a named preset: updates `bandGains` and dispatches all 31 bands
    /// to the DSP kernel in a single pass.
    func selectPreset(_ preset: EQPreset) {
        logUX("EQ preset → '\(preset.displayName)'")
        selectedPreset = preset
        bandGains = preset.gains
        dispatchAllBands()
        persistLiveState()
    }

    /// Apply a saved custom preset by name. No-op if the name is not found.
    func selectCustomPreset(named name: String) {
        guard let gains = savedCustomPresets[name] else { return }
        logUX("EQ custom preset → '\(name)'")
        selectedPreset = nil
        bandGains = gains
        dispatchAllBands()
        persistLiveState()
    }

    // MARK: - Per-Band Editing

    /// Commit canvas-drawn ("custom") edits. The `FrequencyResponseCanvas` mutates
    /// `bandGains` in place during a drag, then calls this to **defensively clamp
    /// every band to the DSP range [-12, +12] dB**, mark the preset custom, and
    /// dispatch once. Centralizes the DSP-range guarantee that direct `bandGains`
    /// writes would otherwise bypass.
    ///
    /// Called once PER DRAG SAMPLE (~60-120 Hz) — dispatch-only, deliberately. Persisting the
    /// live state here would JSON-encode + UserDefaults-write on every pointer move during the
    /// most latency-sensitive interaction in the app. The canvas persists once via
    /// `persistLiveState()` from `DragGesture.onEnded` instead (architect review).
    func commitCustomBandEdits() {
        for index in bandGains.indices {
            bandGains[index] = max(-12.0, min(12.0, bandGains[index]))
        }
        selectedPreset = nil
        dispatchAllBands()
    }

    // MARK: - Save Custom Preset

    /// Save the current band state as a named custom preset.
    ///
    /// Overwrites silently if `name` already exists. Persists to UserDefaults.
    /// Only meaningful when `selectedPreset == nil` (i.e. user has made custom edits)
    /// but the caller is responsible for gating the UI control.
    func saveCustomPreset(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        logUX("EQ save custom preset '\(trimmed)'")
        savedCustomPresets[trimmed] = bandGains
        persistCustomPresets()
    }

    // MARK: - Per-Output Recall

    /// Recall the preset previously mapped to `device`, if any.
    ///
    /// Called from `onChange(of: selectedDevice)` in the view (F3: view-driven, no
    /// cross-VM callback). Shows a non-modal banner on successful recall.
    func recallPresetForDevice(_ device: AudioDeviceModel) {
        let key = String(device.id)
        guard let presetID = outputPresetMap[key] else { return }

        // Try named EQPreset first; fall back to saved custom.
        if let preset = EQPreset(rawValue: presetID) {
            logUX("EQ recall: device '\(device.name)' → preset '\(presetID)'")
            selectPreset(preset)
            recallBannerMessage = "\(presetID) loaded for \(device.name)"
        } else if savedCustomPresets[presetID] != nil {
            logUX("EQ recall: device '\(device.name)' → custom '\(presetID)'")
            selectCustomPreset(named: presetID)
            recallBannerMessage = "\(presetID) loaded for \(device.name)"
        } else {
            // Mapping references a preset that no longer exists; remove stale entry.
            logUX("EQ recall: stale map for device '\(device.name)' (preset '\(presetID)' gone)")
            outputPresetMap.removeValue(forKey: key)
            persistOutputPresetMap()
        }
    }

    // MARK: - Dispatch

    /// Publish the full 31-band gain vector to the live DSP AU. Called exactly
    /// once per user action — never in a per-band loop. Used by `selectPreset`
    /// and `commitCustomBandEdits`.
    ///
    /// The published gains pass through `EQSafetyClamp`: if the summed band gains
    /// exceed the cumulative hearing-safety ceiling, all bands are proportionally
    /// scaled down before reaching the kernel. `bandGains` itself is left untouched,
    /// so sliders/canvas keep showing the user's intent while the kernel only ever
    /// receives a hearing-safe shape.
    ///
    /// Guarded on engine readiness: a no-op until the AU is live, which also closes
    /// the (very narrow) teardown race against `shutdown()`.
    func dispatchAllBands() {
        guard audioViewModel.isEngineReady else { return }
        let safeGains = EQSafetyClamp.clamped(bandGains)
        let maxBoost = safeGains.max() ?? 0
        let maxCut = safeGains.min() ?? 0
        logUX("EQ dispatch: preset='\(selectedPresetName)' "
            + "maxBoost=\(String(format: "%+.1f", maxBoost))dB "
            + "maxCut=\(String(format: "%+.1f", maxCut))dB")
        audioViewModel.publishEQGains(safeGains)
    }

    /// Log an interpolation-mode change. Called from the EQ tab view's onChange handler
    /// so the log remains in the view model (which already imports Foundation).
    func logInterpolationModeChange(_ discrete: Bool) {
        logUX("EQ interpolation → \(discrete ? "discrete" : "smooth")")
    }
}
