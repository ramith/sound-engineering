import AppKit
import Foundation
import LibraryScan

// MARK: - AudioViewModel volume monitor (S8.4 slice 5b — eject/remount handling)

//
// FSEvents pauses when a watched external/NAS volume unmounts and does not reliably announce a
// remount. NSWorkspace mount/unmount notifications are the responsiveness trigger: on any volume
// change we re-point the watcher at the now-available roots, RE-STAMP the on-disk (dev,inode)
// identity of any root that became reachable (a remount may reassign st_dev — keeps addRoot's
// identity-dedup correct), and kick a catch-up reconcile. An unreachable root is left paused by
// the reconcile precheck. The data-loss SAFETY does not depend on any of this — it is the
// empty-walk backstop (slice 3); this layer is responsiveness + identity hygiene.

extension AudioViewModel {
    /// Subscribe to NSWorkspace mount/unmount. Called once from `makeLibraryStore`; tokens are
    /// removed in `shutdown()`. The block is non-isolated `@Sendable` (AudioViewModel is a
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
    /// for each root that is now reachable re-stamp its `(dev,inode)` identity (a remount may have
    /// reassigned st_dev) and schedule a catch-up reconcile. Unreachable roots stay paused.
    private func handleVolumeChange() async {
        await refreshWatchedRoots()
        guard let store else { return }
        for root in watchedRoots where RootReachabilityProbe.isReachable(root.url) {
            let signature = LibraryScanner.deviceInode(of: root.url)
            try? await store.restampRoot(id: root.folderID, dev: signature.dev, inode: signature.inode)
            scheduleReconcile(folderID: root.folderID, root: root.url)
        }
    }
}
