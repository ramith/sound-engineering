#if DEBUG
    import SwiftUI

    extension EnvironmentValues {
        /// Picture-sheet renderer only: the album, artist or genre page's content (`SheetFixture+Detail`),
        /// shown in place of the store read the renderer has no store for. None in a normal run.
        @Entry var sheetDetailPage: LibraryDetailContent?
    }
#endif
