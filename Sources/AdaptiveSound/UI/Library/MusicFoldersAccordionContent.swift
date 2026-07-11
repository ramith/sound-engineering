import Foundation
import LibraryStore
import SwiftUI

// MARK: - Music Folders accordion content (S9 IA change → inline-accordion redesign)

/// The Library's folder list with a per-root remove (confirmed via `.alert`). Reachable by
/// expanding the sidebar footer's "Music Folders" trigger row (`LibrarySidebar`), which renders
/// this view inline below the trigger instead of inside a `.popover` (design:
/// docs/sprints/music-folders-accordion.md). Adding still lives on the trigger row's "+" — NOT
/// here — kept there for UX reasons (one-click add without an expand-then-add detour, §6), not
/// because of any popover-lifecycle constraint: this content is part of the sidebar's persistent
/// view hierarchy now, so an `.fileImporter` would be perfectly safe to host here too.
///
/// `.task`/`.onChange` below only run while this view is mounted, i.e. only while the accordion
/// is expanded — the data they refresh (`model.roots`, the per-row "Scanning…" hint) is invisible
/// while collapsed, so there's no reason to keep re-reading it in the background; expanding always
/// re-triggers the `.task` for a fresh read.
struct MusicFoldersAccordionContent: View {
    @Environment(LibraryBrowseModel.self) private var model
    @Environment(LibraryModel.self) private var library
    @State private var removeTarget: LibraryFolder?

    var body: some View {
        Group {
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
                .frame(maxHeight: 280) // bound the accordion height; long libraries scroll (review S4)
            }
        }
        // Same horizontal rhythm as the trigger row above (no nested indent — the sidebar column
        // is narrow, review §4) plus a little vertical breathing room off the hairline.
        .padding(.horizontal, DesignSystem.Spacing.medium)
        .padding(.vertical, DesignSystem.Spacing.small)
        .task { await model.loadRoots() }
        // Re-read as scans/adds/removes land: a freshly-added root (and its per-row "Scanning…"
        // hint) appears once its scan starts; libraryRevision covers completion.
        .onChange(of: library.scanProgress?.folderID) { _, _ in Task { await model.loadRoots() } }
        .onChange(of: library.libraryRevision) { _, _ in Task { await model.loadRoots() } }
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
