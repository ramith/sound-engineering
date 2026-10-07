#if DEBUG
    import SwiftUI

    // MARK: - Picture-sheet focus seed

    /// Runs `perform` once on appear when the picture-sheet fixture asks `list` to take keyboard
    /// focus (`sheetFocusedLists`); a no-op otherwise. Keeps the debug environment read out of the
    /// list views themselves.
    struct SheetFocusSeed: ViewModifier {
        let list: SheetFocusedList
        let perform: () -> Void
        @Environment(\.sheetFocusedLists) private var focusedLists

        func body(content: Content) -> some View {
            content.onAppear {
                if focusedLists.contains(list) {
                    perform()
                }
            }
        }
    }

    extension View {
        /// Picture-sheet renderer only: see `SheetFocusSeed`.
        func sheetFocusSeed(_ list: SheetFocusedList, perform: @escaping () -> Void) -> some View {
            modifier(SheetFocusSeed(list: list, perform: perform))
        }
    }
#endif
