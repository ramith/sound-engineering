#if DEBUG
    import SwiftUI

    extension EnvironmentValues {
        /// Picture-sheet renderer only: the browse tiles drawn hovered and with the keyboard ring.
        /// None in a normal run.
        @Entry var sheetGridStates = SheetGridStates()
    }
#endif
