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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showFolderImporter = false

    /// Music Folders accordion expand/collapse — persisted across launches and across this view
    /// being recreated mid-session (design §8), matching the `.v1`-key-versioned `@AppStorage`
    /// convention `EQTabView` already uses for its interpolation-mode toggle.
    @AppStorage("library.foldersExpanded.v1") private var isFoldersExpanded = false

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedCategory) {
            ForEach(LibraryCategory.allCases) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
        }
        // Source-list appearance — set explicitly now that the enclosing NavigationSplitView is
        // gone (the split view used to imply it). Standalone `.sidebar` is just a list style; it
        // does NOT recreate the split view's under-the-titlebar coordination.
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) { footer }
        .fileImporter(isPresented: $showFolderImporter, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result { model.addFolder(url) }
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
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        isFoldersExpanded.toggle()
                    }
                } label: {
                    // A shared `.font` on the HStack (not just the `Text`) so the chevron scales
                    // in step with the label at larger Dynamic Type sizes (design §10) instead of
                    // staying a fixed-size glyph next to growing text.
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "chevron.forward")
                            .rotationEffect(.degrees(isFoldersExpanded ? 90 : 0))
                            .accessibilityHidden(true)
                        Image(systemName: "folder")
                            .accessibilityHidden(true)
                        Text("Music Folders")
                    }
                    .font(DesignSystem.Font.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(DesignSystem.Color.labelSecondary)
                .accessibilityValue(isFoldersExpanded ? "Expanded" : "Collapsed")
                .accessibilityHint("Show or hide your music folders.")
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
            if isFoldersExpanded {
                VStack(spacing: 0) {
                    Rectangle().fill(DesignSystem.Color.hairline).frame(height: 0.5)
                    MusicFoldersAccordionContent()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // A material (not an opaque fill) so the translucent sidebar shows through; the hairline
        // above is the separator (review S5).
        .background(.bar)
    }
}
