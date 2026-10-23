/// PLANTED — the CI proof of the test-rig redesign (draft PR, never merged): a declaration nothing uses,
/// which Periphery (the static job; not in the commit or push hooks) must name.
enum PlantedUnused {
    static func neverCalled() -> Int {
        1
    }
}
