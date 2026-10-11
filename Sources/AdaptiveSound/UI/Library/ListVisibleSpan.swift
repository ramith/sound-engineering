import CoreGraphics

// MARK: - List visible span (S10.8 E1; shared with the detail pages in E2)

/// A selectable list's visible span, in its content's coordinates — what its keys need to scroll the
/// cursor row into view (`FixedRowReveal`) and to size a Page Up / Down. A REFERENCE kept in `@State`:
/// it is written on every scroll frame but read only when a key moves the cursor, so scrolling never
/// re-renders the list (a value in `@State` would, frame by frame, over every visible row).
final class ListVisibleSpan {
    var rect = CGRect.zero
}
