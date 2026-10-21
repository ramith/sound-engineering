// A defaults suite of a test's own (test-rig redesign, rule 3: each test owns its world).
//
// A fixed suite name is process-wide state: tests of different suites run at the same time, and what one
// sets another reads (the OnDeck rigs shared one suite across five suites). This is a suite named by a
// UUID, emptied when the test is done with it — so nothing leaks into the next test, or onto the disk.

import Foundation

/// A `UserDefaults` suite no other test can see. Keep it alive as long as the test uses `defaults`: the
/// suite is removed when this is released.
public final class IsolatedDefaults: @unchecked Sendable { // UserDefaults is documented thread-safe
    /// The suite's defaults.
    public let defaults: UserDefaults
    /// The suite's name, for tests that reopen the same suite (`UserDefaults(suiteName:)`).
    public let suiteName: String

    /// A new empty suite whose name begins with `label`, so a stray file on disk says whose it was.
    public init(_ label: String) {
        let name = "\(label).\(UUID().uuidString)"
        suiteName = name
        // `UserDefaults(suiteName:)` is nil only for the app's own bundle id or the global domain.
        defaults = UserDefaults(suiteName: name) ?? UserDefaults()
        defaults.removePersistentDomain(forName: name)
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
