import SwiftUI

// MARK: - A live reading, for VoiceOver (council C-53, UI-4)

extension View {
    /// One accessibility element for a reading that moves while it is shown — the scrubber's elapsed
    /// time, a loudness meter, the scan's progress: its LABEL names it and never changes, its VALUE
    /// carries the reading, and it has the `.updatesFrequently` trait, so assistive tech polls it when
    /// it needs the reading (Apple: "the readout of a stopwatch") instead of being told of every
    /// change. Pass `value` quantised to what is worth saying (the playhead to the second, LUFS to the
    /// dB): a value that does not change does not reach the accessibility tree.
    ///
    /// Before R1.1 each readout did this its own way, and the meters put their readings in the label,
    /// so the element's name changed up to 20 times a second.
    func liveReadout(_ label: String, value: String) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityAddTraits(.updatesFrequently)
    }
}
