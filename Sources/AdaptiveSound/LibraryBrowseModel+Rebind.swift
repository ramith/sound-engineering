import Foundation
import LibraryBrowseKit
import LibraryStore

// MARK: - LibraryBrowseModel + "Use this drive" (R1.1-B, US-R1F-03 LIB-VOL-1)

@MainActor
extension LibraryBrowseModel {
    /// A refusal of "Use this drive" (`MusicFolderStatus.rebindMessage`), said in a dialog; a done rebind is
    /// said in the toast instead.
    struct RebindNotice: Equatable, Identifiable {
        let message: String

        var id: String {
            message
        }
    }

    /// Point the paused music folder `folder` at `newRoot`, the folder that holds its songs on another
    /// drive (`LibraryModel.useDrive`), then refresh the Music Folders list. Returns what to say: a done
    /// rebind's toast words, or a refusal's notice — nil when there is nothing to say.
    func useDrive(_ newRoot: URL, for folder: LibraryFolder) async -> RebindNotice? {
        guard let outcome = await library.useDrive(newRoot, forFolder: folder.id) else { return nil }
        await loadRoots()
        let name = (folder.path as NSString).lastPathComponent
        guard let message = MusicFolderStatus.rebindMessage(outcome, folderName: name) else { return nil }
        if case .rebound = outcome {
            showToast(message)
            return nil
        }
        return RebindNotice(message: message)
    }
}
