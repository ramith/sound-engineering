import Foundation
import LibraryStore
import SwiftUI

// MARK: - Music Folders section (S9 IA → S10.8 inline rail section)

/// The Library's folder list with a per-root remove (confirmed via `.alert`). Rendered inline in
/// the Twin Panels navigation rail (`LibrarySidebar`), under the "Music Folders" section header, as
/// plain rows inside the rail card's OWN ScrollView (S10.8 PR-C retired the earlier footer
/// accordion, so a nested scroll here would fight the card's scroll). Adding lives on the section
/// header's "+" — NOT here — kept there for the one-click add UX (§6).
///
/// `.task`/`.onChange` refresh `model.roots` and the per-row "Scanning…" hint while the rail is
/// mounted (i.e. while the Library tab is open).
struct MusicFoldersSection: View {
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @State private var removeTarget: LibraryFolder?

    var body: some View {
        Group {
            if model.roots.isEmpty {
                Text("No folders in your library yet. Use ＋ above to add one.")
                    .font(DesignSystem.Font.caption)
                    .foregroundStyle(DesignSystem.Color.labelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // Plain VStack (no inner ScrollView): the rows are items in the rail card's own
                // ScrollView now (S10.8 inline folders), so a nested scroll would fight it.
                VStack(spacing: 0) {
                    ForEach(model.roots) { root in
                        rootRow(root)
                        if root.id != model.roots.last?.id {
                            Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
                        }
                    }
                }
            }
        }
        // Align with the rail's nav-row content inset (S10.8 inline folders).
        .padding(.horizontal, DesignSystem.LayoutMetrics.railRowInset)
        .padding(.vertical, DesignSystem.Spacing.xSmall)
        .task { await model.loadRoots() }
        // Re-read as scans/adds/removes land: a freshly-added root (and its per-row "Scanning…"
        // hint) appears once its scan starts; libraryRevision covers completion.
        .onChange(of: library.scanProgress?.folderID) { _, _ in Task { await model.loadRoots() } }
        .onChange(of: library.libraryRevision) { _, _ in Task { await model.loadRoots() } }
        .alert(
            removeTarget.map { "Remove \"\(abbreviatedPath($0.path))\" from your library?" } ?? "",
            isPresented: Binding(get: { removeTarget != nil }, set: {
                if !$0 {
                    removeTarget = nil
                }
            }),
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
        .frame(minHeight: 34)
        // `.contain` (not `.combine`): keep the Remove button a first-class, directly-activatable
        // VoiceOver element rather than demoting it to an Actions-rotor custom action (review S3).
        .accessibilityElement(children: .contain)
    }

    private func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
