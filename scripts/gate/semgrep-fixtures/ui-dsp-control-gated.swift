// One file, so its gates hold file-wide: crossfeed and Leveling are gated here, the EQ and Intensity are not.
struct Fixture: View {
    var body: some View {
        // ruleid: ui-dsp-control-gated
        Toggle("Equalizer", isOn: $eq.isOn)
        // ruleid: ui-dsp-control-gated
        Button("Warm") { eq.choose(.builtIn(.warm)) }
        // ruleid: ui-dsp-control-gated
        HeaderPillButton("Reset", systemImage: "arrow.counterclockwise", help: "", action: eq.reset)
        // ruleid: ui-dsp-control-gated
        CarvedSlider(value: $bvm.intensity, accessibilityLabel: "Reimagine Intensity", accessibilityValueText: "")
        // ok: ui-dsp-control-gated
        // Button("Warm") { eq.choose(.builtIn(.warm)) }
        // ok: ui-dsp-control-gated
        Toggle("Crossfeed", isOn: Binding(get: { bvm.crossfeedPlays }, set: { bvm.crossfeedEnabled = $0 }))
            .bitPerfectGate(.crossfeed, availability)
        // ok: ui-dsp-control-gated
        CapsuleSwitch("Leveling", selection: $audioViewModel.leveling, options: LevelingSetting.allCases, title: title)
            .bitPerfectGate(.leveling, availability)
        // ok: ui-dsp-control-gated
        Button("Cancel") { eq.cancelStroke(); eq.endStroke() }
        // The gate in a comment is no gate: .bitPerfectGate(.equalizer, availability)
        // .bitPerfectGate(.intensity, availability)
    }
}
