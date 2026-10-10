#if DEBUG
    import SwiftUI

    extension EnvironmentValues {
        /// Picture-sheet renderer only: the EQ graph's drag and keyboard cursor. None in a normal run.
        @Entry var sheetEQGraph = SheetEQGraph()
    }
#endif
