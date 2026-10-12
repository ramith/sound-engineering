// S10.8 G break-it - what the engine is told at engine-ready (see main.swift for the harness).

import Foundation

/// G-GAIN-1: the Master Gain slider reads +4.0 dB at launch. Is that gain sent to the engine?
@MainActor
func masterGainAtLaunch() async {
    let engine = AudioEngineBridge()
    let defaults = UserDefaults(suiteName: "breakit.g.vmharness.unused") ?? .standard
    let model = AudioViewModel(defaults: defaults, engine: engine)
    model.initializeEngine()
    await settle()
    model.stopSpectrumTimer()
    let sent = engine.parameters[0]
    // MasterGainSliderView reads gain * 20 - 10 dB, the bridge applies playerNode.volume = gain (linear).
    let readout = Double(model.masterGain) * 20 - 10
    let applied = sent.map { 20 * log10(Double($0)) }
    let sentText = sent.map { "\($0)" } ?? "nil"
    report(both(model.isEngineReady, sent == model.masterGain), "G-GAIN-1",
           "the Master Gain the inspector shows at launch is the gain that plays",
           expected: "setParameter(0, \(model.masterGain)) at engine-ready, and a readout of what it applies",
           actual: "nothing sent (volume stays 1.0 = 0 dB until a move: \(sentText)), "
               + "the readout says \(String(format: "%+.1f", readout)) dB, and once moved, volume=gain plays "
               + "\(String(format: "%+.1f", applied ?? 20 * log10(Double(model.masterGain)))) dB")
}
