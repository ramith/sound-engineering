import AppKit
import Foundation

// MARK: - LibraryModel volume monitor (S8.4 slice 5b — was AudioViewModel+VolumeMonitor)

//
// FSEvents pauses when a watched external/NAS volume unmounts and does not reliably announce a
// remount. NSWorkspace mount/unmount notifications are the responsiveness trigger: on any volume
// change we re-point the watcher at the roots and ask for a catch-up reconcile of EVERY root. The
// scanner decides what each walk is: a reachable root's walk re-stamps its identity; a root whose
// drive just left, or whose path now holds another drive (two same-named drives, R1), is refused
// (`SweepRefusal`) and paused — so its Music Folders row says so at once, instead of reading
// "watching" until something else walks it (R1.1-A, KI-LIB-02). The data-loss SAFETY does not depend
// on any of this layer — it is the scanner's; this is responsiveness.

extension LibraryModel {
    /// Subscribe to NSWorkspace mount/unmount. Called once from `makeLibraryStore`; tokens are
    /// removed in `shutdown()`. The block is non-isolated `@Sendable` (LibraryModel is a
    /// @MainActor class, hence Sendable) and hops to @MainActor before touching any state.
    func startVolumeMonitor() {
        guard volumeMonitorTokens.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        let onChange: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in await self?.handleVolumeChange() }
        }
        volumeMonitorTokens = [
            center.addObserver(forName: NSWorkspace.didMountNotification, object: nil,
                               queue: .main, using: onChange),
            center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil,
                               queue: .main, using: onChange),
        ]
    }

    /// Remove the NSWorkspace observers (ordered teardown, from `shutdown()`).
    func stopVolumeMonitor() {
        let center = NSWorkspace.shared.notificationCenter
        for token in volumeMonitorTokens {
            center.removeObserver(token)
        }
        volumeMonitorTokens = []
    }

    /// A volume mounted or unmounted: re-point the watcher at the roots, then schedule a catch-up
    /// reconcile of every root. A reachable root's walk re-stamps its identity, or refuses another
    /// drive at its path; an unreachable root's walk is refused at once, and the root is paused with
    /// that reason — the pause ends with the first walk that is evidence again. (Internal for the
    /// tests: the NSWorkspace observers are its only production caller.)
    func handleVolumeChange() async {
        await refreshWatchedRoots()
        for root in watchedRoots {
            scheduleReconcile(folderID: root.folderID)
        }
    }
}
