import Foundation
import LibraryStore
import SwiftUI

// MARK: - Music Folders management popover (S9 IA change)

/// The Library's folder list with a per-root remove (confirmed via `.alert`). Adding lives on the
/// sidebar footer's "+" — NOT here: an `.fileImporter` hosted inside this transient popover would
/// be torn down when the `NSOpenPanel` steals focus (review S1). The footer's "+" stays visible
/// below the upward-opening popover, so it's the single always-available add path. Reachable from
/// the sidebar footer's "Music Folders" button.
struct MusicFoldersView: View {
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(AudioViewModel.self) private var audio
    @State private var removeTarget: LibraryFolder?

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text("Music Folders")
                .font(DesignSystem.Font.sectionTitle)
                .foregroundStyle(DesignSystem.Color.label)

            if model.roots.isEmpty {
                Text("No folders in your library yet. Use ＋ below to add one.")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(model.roots) { root in
                            rootRow(root)
                            if root.id != model.roots.last?.id {
                                Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
                            }
                        }
                    }
                }
                .frame(maxHeight: 280) // bound the popover height; long libraries scroll (review S4)
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .frame(width: 340)
        .task { await model.loadRoots() }
        // Re-read as scans/adds/removes land: a freshly-added root (and its per-row "Scanning…"
        // hint) appears once its scan starts; libraryRevision covers completion.
        .onChange(of: audio.scanProgress?.folderID) { _, _ in Task { await model.loadRoots() } }
        .onChange(of: audio.libraryRevision) { _, _ in Task { await model.loadRoots() } }
        .alert(
            removeTarget.map { "Remove \"\(abbreviatedPath($0.path))\" from your library?" } ?? "",
            isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
            presenting: removeTarget
        ) { root in
            Button("Remove", role: .destructive) { Task { await model.removeFolder(id: root.id) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The audio files on disk aren't deleted. Songs from this folder leave your "
                + "library unless they're in a playlist.")
        }
    }

    private func rootRow(_ root: LibraryFolder) -> some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Image(systemName: "folder")
                .foregroundStyle(DesignSystem.Color.labelSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(abbreviatedPath(root.path))
                    .font(DesignSystem.Font.body)
                    .foregroundStyle(DesignSystem.Color.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if model.scanningRootID == root.id {
                    Text("Scanning…")
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                }
            }
            Spacer(minLength: DesignSystem.Spacing.small)
            Button {
                removeTarget = root
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DesignSystem.Color.labelSecondary)
            .help("Remove from Library")
            .accessibilityLabel("Remove \(abbreviatedPath(root.path)) from library")
        }
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        // `.contain` (not `.combine`): keep the Remove button a first-class, directly-activatable
        // VoiceOver element rather than demoting it to an Actions-rotor custom action (review S3).
        .accessibilityElement(children: .contain)
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
