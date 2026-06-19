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

        source.setEventHandler { [weak self] in
            self?.folderMonitorDebounceTask?.cancel()
            self?.folderMonitorDebounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled, let self else { return }
                if let url = self.musicFolderURL {
                    await self.loadMusicFolder(url)
                }
            }
        }

        source.setCancelHandler { close(fileDescriptor) }
        folderMonitorSource = source
        source.resume()
    }

    func stopFolderMonitoring() {
        folderMonitorDebounceTask?.cancel()
        folderMonitorSource?.cancel()
        folderMonitorSource = nil
    }
}
