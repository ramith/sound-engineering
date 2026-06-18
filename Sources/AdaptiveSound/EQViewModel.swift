import Foundation

// MARK: - EQViewModel

/// Manages 31-band EQ state and dispatches gain changes to the DSP kernel.
///
/// Preset shapes live in `EQPreset.gains` (the single source of truth).
/// All mutations go through `applyBandGain(_:_:)` or `selectPreset(_:)`,
/// both of which call `dispatchAllBands()` exactly once per user action.
///
/// Presets are typed as `EQPreset`; "Custom" is represented by setting
/// `selectedPreset` to `nil`.
@MainActor
@Observable
final class EQViewModel {
    // MARK: - State

    /// Per-band gains in dB, indexed 0–30 for ISO 266 1/3-octave bands.
    /// Range: -20 to +12 dB per band. Observed by the canvas and sliders.
    var bandGains: [Float] = .init(repeating: 0.0, count: 31)

    /// The active named preset, or `nil` when the user has made custom edits.
    var selectedPreset: EQPreset? = .flat

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
    }

    // MARK: - Preset Selection

    /// Apply a named preset: updates `bandGains` and dispatches all 31 bands
    /// to the DSP kernel in a single pass.
    func selectPreset(_ preset: EQPreset) {
        logUX("EQ preset → '\(preset.displayName)'")
        selectedPreset = preset
        bandGains = preset.gains
        dispatchAllBands()
    }

    // MARK: - Per-Band Editing

    /// Update a single band gain and dispatch the full band array to the kernel.
    ///
    /// Clamps `gain` to [-20, +12] dB. Marks `selectedPreset` as `nil` so
    /// the UI reflects that the current state no longer matches a named preset.
    func applyBandGain(_ band: Int, _ gain: Float) {
        guard band >= 0, band < bandGains.count else { return }
        bandGains[band] = max(-20.0, min(12.0, gain))
        selectedPreset = nil
        dispatchAllBands()
    }

    /// Commit canvas-drawn ("custom") edits. The `FrequencyResponseCanvas` mutates
    /// `bandGains` in place during a drag, then calls this to **defensively clamp
    /// every band to the DSP range [-20, +12] dB**, mark the preset custom, and
    /// dispatch once. Centralizes the DSP-range guarantee that direct `bandGains`
    /// writes would otherwise bypass.
    func commitCustomBandEdits() {
        for index in bandGains.indices {
            bandGains[index] = max(-20.0, min(12.0, bandGains[index]))
        }
        selectedPreset = nil
        dispatchAllBands()
    }

    // MARK: - Reset

    /// Resets all bands to 0 dB and selects the Flat preset.
    func resetToFlat() {
        logUX("EQ reset → flat")
        selectPreset(.flat)
    }

    // MARK: - Dispatch

    /// Publish the full 31-band gain vector to the live DSP AU (Sprint 5 M2). Called exactly
    /// once per user action — never in a per-band loop. Used by `selectPreset`, `applyBandGain`,
    /// and `commitCustomBandEdits` (the canvas commits drags through the latter, never writing
    /// `bandGains`/dispatching directly).
    ///
    /// The published gains pass through `EQSafetyClamp` (Sprint 4 M5): if the summed band gains
    /// exceed the cumulative hearing-safety ceiling, all bands are proportionally scaled down
    /// before reaching the kernel. `bandGains` itself is left untouched, so sliders/canvas keep
    /// showing the user's intent while the kernel only ever receives a hearing-safe shape.
    ///
    /// Guarded on engine readiness: a no-op until the AU is live, which also closes the
    /// (very narrow) teardown race against `shutdown()`.
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
