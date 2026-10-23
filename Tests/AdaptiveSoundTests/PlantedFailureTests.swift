import Testing

/// PLANTED — the CI proof of the test-rig redesign (draft PR, never merged): a failing test the gate's
/// summary must name.
@Suite("PLANTED: the CI proof")
struct PlantedFailureTests {
    @Test("PLANTED: a failing test the summary must name")
    func plantedFailure() {
        #expect(1 == 2, "planted: the gate's summary must name this failing test")
    }
}
