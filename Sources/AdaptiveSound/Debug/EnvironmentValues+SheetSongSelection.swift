#if DEBUG
    import LibraryStore
    import SwiftUI

    extension EnvironmentValues {
        /// Picture-sheet renderer only: the Songs rows its fixture draws as selected. `SongsListView`
        /// keeps its selection in view-local `@State`, so it can't arrive through the browse model.
        @Entry var sheetSongSelection: Set<LibraryTrackDisplay.ID> = []
    }
#endif
