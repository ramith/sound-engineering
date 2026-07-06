import AppKit
import Darwin

/// Guarantees a single running instance of AdaptiveSound.
///
/// Acquires an exclusive advisory lock (`flock`) on a file in Application Support, held open for
/// the whole process lifetime. The OS releases the lock when the process exits — even on a crash
/// — so a fresh launch can always reacquire; there is no stale-lock-file problem. If another
/// instance already holds the lock, this process is a duplicate: we best-effort raise the existing
/// instance and the caller exits before building any state or touching the audio engine.
enum SingleInstanceGuard {
    /// Held open for the process lifetime so the `flock` stays acquired — closing the descriptor
    /// releases the lock. Written once at launch on the main thread; never mutated concurrently.
    private nonisolated(unsafe) static var lockDescriptor: Int32 = -1

    /// Returns `true` if this is the sole instance, `false` if another already holds the lock.
    static func acquire() -> Bool {
        // Idempotent within a process: SwiftUI may build the `App` value more than once. A second
        // `open`+`flock` from the SAME process would be DENIED by our own held lock (flock treats
        // descriptors independently), which would falsely read as "duplicate" and kill the real
        // app — so short-circuit once we already hold it.
        if lockDescriptor >= 0 { return true }

        let descriptor = open(lockFilePath(), O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { return true } // can't create the lock file → don't block launch
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            lockDescriptor = descriptor // keep open — do NOT close
            return true
        }
        close(descriptor)
        raiseExistingInstance()
        return false
    }

    private static func lockFilePath() -> String {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("AdaptiveSound", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("instance.lock").path
    }

    /// Bring the already-running instance forward. Requires a bundle identifier (present in a
    /// packaged `.app`); a bare `swift run` executable has none, in which case the duplicate still
    /// exits — it just can't raise the original.
    private static func raiseExistingInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let selfPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            where app.processIdentifier != selfPID {
            app.activate()
        }
    }
}
