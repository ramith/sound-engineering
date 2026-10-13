import AppKit
import Foundation
import LibraryScan

// MARK: - LibraryModel volume monitor (S8.4 slice 5b — was AudioViewModel+VolumeMonitor)

//
// FSEvents pauses when a watched external/NAS volume unmounts and does not reliably announce a
// remount. NSWorkspace mount/unmount notifications are the responsiveness trigger: on any volume
// change we re-point the watcher at the now-available roots and kick a catch-up reconcile of each
// root that is reachable. The reconcile's walk re-stamps the root's identity — or, when the drive
// now at its path is not the root's own (two same-named drives mount at the same path, R1), refuses
// to walk, sweep or re-stamp it and leaves it paused (`LibraryScanner.scan`). The data-loss SAFETY
// does not depend on any of this layer — it is the scanner's (`SweepRefusal`); this is responsiveness.

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

    /// A volume mounted or unmounted: re-point the watcher at the currently-available roots, then
    /// schedule a catch-up reconcile of each root that is now reachable — its walk re-stamps the
    /// root's identity, or refuses another drive at its path. Unreachable roots stay paused.
    private func handleVolumeChange() async {
        await refreshWatchedRoots()
        for root in watchedRoots where RootReachabilityProbe.isReachable(root.url) {
            scheduleReconcile(folderID: root.folderID)
        }
    }
}
