#if DEBUG
    import AppKit
    import SwiftUI

    extension EnvironmentValues {
        /// Picture-sheet renderer only: the fixture's covers by artwork key (`SheetArtwork`), drawn
        /// in place of the store's thumbnails. Empty in a normal run.
        @Entry var sheetArtwork: [String: NSImage] = [:]
    }
#endif
