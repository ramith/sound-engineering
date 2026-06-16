import Foundation

// Standalone test harness for EQSafetyClamp (Sprint 4, Milestone 5).
//
// `swift test` is unusable on this machine (swift-testing macro/framework skew),
// so — mirroring the C++ null-test harness philosophy — this compiles the REAL
// production source (`Sources/AdaptiveSound/EQSafetyClamp.swift`) together with
// these assertions via `swiftc`. See `scripts/build-eq-clamp-test.sh`.

@main
enum EQSafetyClampTest {
    static var failures = 0

    static func check(_ condition: Bool, _ label: String) {
        if condition {
            print("  ok:   \(label)")
        } else {
            failures += 1
            print("  FAIL: \(label)")
        }
    }

    static func approxEqual(_ lhs: [Float], _ rhs: [Float], tolerance: Float = 1.0e-3) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { abs($0 - $1) <= tolerance }
    }

    static func summed(_ values: [Float]) -> Float {
        values.reduce(0, +)
    }

    static func main() {
        print("EQSafetyClamp tests")

        // Spec test 1 — proportional scaling: {+20×5} sum +100 → scale 0.12 → {+2.4×5} sum +12.
        let test1 = EQSafetyClamp.clamped([20, 20, 20, 20, 20])
        check(approxEqual(test1, [2.4, 2.4, 2.4, 2.4, 2.4]), "uniform +20×5 scales to +2.4×5")
        check(abs(summed(test1) - 12) <= 1.0e-3, "uniform boost sums to exactly +12 after clamp")

        // Spec test 2a — direction preservation, no clamp: {+8,−3,+5,−1,+2} sum +11 ≤ 12 → unchanged.
        let underInput: [Float] = [8, -3, 5, -1, 2]
        let test2a = EQSafetyClamp.clamped(underInput)
        check(approxEqual(test2a, underInput), "mixed shape summing to +11 is left unchanged")

        // Spec test 2b — direction preservation, clamp: {+20,−3,+5,−1,+2} sum +23 → scale 12/23.
        let overInput: [Float] = [20, -3, 5, -1, 2]
        let test2b = EQSafetyClamp.clamped(overInput)
        let scale2b: Float = 12.0 / 23.0
        check(approxEqual(test2b, overInput.map { $0 * scale2b }), "mixed shape summing to +23 scaled by 12/23")
        check(abs(summed(test2b) - 12) <= 1.0e-3, "clamped mixed shape sums to exactly +12")
        check(test2b[0] > 0 && test2b[2] > 0 && test2b[4] > 0, "boosts stay positive after clamp")
        check(test2b[1] < 0 && test2b[3] < 0, "cuts stay negative after clamp")

        // Shape preservation — inter-band ratios survive a uniform scale.
        check(abs(test2b[0] / test2b[2] - overInput[0] / overInput[2]) <= 1.0e-3, "inter-band ratio preserved")

        // Edge: all zeros → unchanged (no divide-by-zero, no spurious scaling).
        check(approxEqual(EQSafetyClamp.clamped([0, 0, 0]), [0, 0, 0]), "all-zero input unchanged")

        // Edge: net cut (negative sum) → unchanged.
        let netCut: [Float] = [-5, -5, 3]
        check(approxEqual(EQSafetyClamp.clamped(netCut), netCut), "net-cut shape unchanged")

        // Edge: exactly at the limit → unchanged (guard is strictly greater-than).
        let atLimit: [Float] = [6, 6]
        check(approxEqual(EQSafetyClamp.clamped(atLimit), atLimit), "sum exactly at +12 is unchanged")

        // Edge: full 31-band worst case (every band at the +12 per-band ceiling).
        let allMax = [Float](repeating: 12, count: 31)
        let test31 = EQSafetyClamp.clamped(allMax)
        check(abs(summed(test31) - 12) <= 1.0e-3, "31 bands at +12 each clamp to +12 cumulative")
        check(test31.allSatisfy { $0 > 0 }, "all 31 bands remain positive after clamp")

        if failures == 0 {
            print("ALL EQSafetyClamp TESTS PASSED")
            exit(0)
        } else {
            print("\(failures) EQSafetyClamp TEST(S) FAILED")
            exit(1)
        }
    }
}
