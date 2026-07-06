import SwiftUI

/// How a `Screen` occupies the content region.
///
/// - `stack`: a vertical section stack with standard insets that scrolls on overflow and
///   fills on underflow (EQ, Settings, Monitoring).
/// - `fill`: hands the child the whole region edge-to-edge; the child owns its own
///   scrolling / panes (Now Playing, Library).
enum ScreenMode {
    case stack
    case fill
}
