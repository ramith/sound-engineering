import Darwin
import Foundation

// MARK: - AudioViewModel folder monitoring (private extension)

extension AudioViewModel {
    func startFolderMonitoring(_ folderURL: URL) {
        let fileDescriptor = open(folderURL.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: monitoringQueue
        )

        // The event handler runs on `monitoringQueue` (a BACKGROUND queue), so it must be a
        // genuinely non-isolated `@Sendable` closure and must NOT touch any @MainActor state
        // directly: doing so runs a main-actor-isolated body on a non-main executor, which
        // Swift 6 traps at runtime (EXC_BREAKPOINT on this queue, seen on every quit when a
        // final FS event fires). Hop to the main actor first, then debounce.
        source.setEventHandler { @Sendable [weak self] in
            // Back on the main actor, drop the event if monitoring was torn down in the meantime:
            // cancel() only suppresses FUTURE handler invocations, not one already enqueued on
            // monitoringQueue. Without this guard a straggling event could re-arm a reload after
            // stopFolderMonitoring() niled the source — a reload racing teardown.
            Task { @MainActor [weak self] in
                guard let self, self.folderMonitorSource != nil else { return }
                self.scheduleFolderReload()
            }
        }

        // Same rule as the event handler: the cancel handler runs on `monitoringQueue`, so it
        // must be `@Sendable` (non-isolated). Without it the closure inherits this @MainActor
        // function's isolation and Swift 6 traps the executor mismatch when the source is
        // cancelled on `monitoringQueue` (SIGTRAP in _dispatch_source_cancel_callout, on quit).
        // The body only closes a captured fd — no actor state — so @Sendable is trivially safe.
        source.setCancelHandler { @Sendable in close(fileDescriptor) }
        folderMonitorSource = source
        source.resume()
    }

    /// Debounced reload trigger (main-actor): coalesce a burst of folder-monitor events into a
    /// single reload 100 ms after the last one. Extracted so the DispatchSource event handler
    /// touches NO @MainActor state on its background queue (Swift 6 isolation safety).
    private func scheduleFolderReload() {
        folderMonitorDebounceTask?.cancel()
        folderMonitorDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let self else { return }
            if let url = self.musicFolderURL {
                await self.loadMusicFolder(url)
            }
        }
    }

    func stopFolderMonitoring() {
        folderMonitorDebounceTask?.cancel()
        folderMonitorSource?.cancel()
        folderMonitorSource = nil
    }
}
