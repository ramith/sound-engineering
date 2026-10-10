import SwiftUI

// MARK: - Carved slider focus look (EQ3t — `CarvedSlider.usesAppFocusRing`)

/// How a focused `CarvedSlider` shows its key focus: the system focus effect, as the inspector's
/// sliders have always shown it; or, opted in, the app's keyboard ring (`controlFocusRing`) — drawn
/// only while the window is keyboard-driven, like every other Tab stop since S10.8 D3. Apply after
/// `.focusable()`, so the ring binds the slider's own focus.
struct CarvedSliderFocusLook: ViewModifier {
    let usesAppFocusRing: Bool

    func body(content: Content) -> some View {
        if usesAppFocusRing {
            content.controlFocusRing(around: Capsule())
        } else {
            content
        }
    }
}
