#if DEBUG
    import SwiftUI

    extension EnvironmentValues {
        /// Picture-sheet renderer only: the lists that take keyboard focus on appear (ring variants).
        /// Empty — no list touched — in a normal run and in the standard sheets.
        @Entry var sheetFocusedLists: Set<SheetFocusedList> = []
    }
#endif
