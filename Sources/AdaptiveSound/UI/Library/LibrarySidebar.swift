import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library sidebar (S9.4 + S9 IA change: Music Folders footer)

/// The category list plus a pinned footer for library-source management. Category selection
/// binds to the injected model (`selectedCategory`), so it survives tab teardown; `.tag(category)`
/// makes the `List` selection a `LibraryCategory?`. The footer (a `.safeAreaInset`, so it never
/// scrolls with the categories and survives category switches) hosts the ambient scan-status
/// strip and the "Music Folders" management entry — the canonical macOS home for library sources.
struct LibrarySidebar: View {
    @Environment(LibraryBrowseModel.self) private var model
    @State private var showManageFolders = false
    @State private var showFolderImporter = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedCategory) {
            ForEach(LibraryCategory.allCases) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
        }
        .navigationTitle("Library")
        .safeAreaInset(edge: .bottom) { footer }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { model.addFolder(url) }
        }
        .popover(isPresented: $showManageFolders, arrowEdge: .bottom) {
            MusicFoldersView()
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            if let status = model.scanStatusText {
                HStack(spacing: DesignSystem.Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(DesignSystem.Font.caption)
                        .foregroundStyle(DesignSystem.Color.labelSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.small)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
            }
            HStack(spacing: DesignSystem.Spacing.small) {
                Button {
                    showManageFolders = true
                } label: {
                    Label("Music Folders", systemImage: "folder")
                        .font(DesignSystem.Font.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .accessibilityHint("Add or remove the folders in your library")
                Spacer(minLength: 0)
                Button("Add Music Folder", systemImage: "plus") { showFolderImporter = true }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DesignSystem.Color.accent)
                    .disabled(!model.isStoreReady)
                    .help("Add a music folder")
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
        }
        // A material (not an opaque fill) so the translucent sidebar shows through; the hairline
        // above is the separator (review S5).
        .background(.bar)
    }
}
