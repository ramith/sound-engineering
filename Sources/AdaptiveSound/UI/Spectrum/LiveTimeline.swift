import SwiftUI

// MARK: - The live visuals' one clock (council C-52; VM-3, UI-2)

/// The clock every live visual draws on — the Now Playing lens, the EQ's silhouette, Monitoring: the
/// display's own (`TimelineView(.animation)`), running only while a song plays and the window can be
/// seen. A view on another tab or in a closed window is not in the view tree, so nothing ticks for
/// it; a minimised, hidden or covered window pauses it (`windowIsVisible`). Paused, the timeline
/// draws its content once and stops. The content reads what to draw from `SpectrumSampler` at the
/// timeline's instant, so the stream never passes through Observation.
///
/// Before R1.1 the visuals ran on clocks of their own — a 20 Hz main-thread timer, and Monitoring's
/// 20 Hz task — from engine-ready to quit, paused or not, shown or not.
struct LiveTimeline<Content: View>: View {
    /// How often a live visual redraws while it runs.
    enum Cadence {
        /// Motion between frames — the lens's easing bars and falling caps: up to 60 times a second.
        case motion
        /// Each new frame as it comes — the silhouette, Monitoring: 20 times a second, as shipped.
        case frames

        var interval: TimeInterval {
            switch self {
            case .motion: 1.0 / 60
            case .frames: 1.0 / 20
            }
        }
    }

    private let cadence: Cadence
    private let isRunning: Bool
    private let content: (Date) -> Content
    @Environment(\.windowIsVisible) private var windowIsVisible

    /// Draw `content` for each instant at `cadence` while `running` (a song plays) and the window can
    /// be seen; otherwise once.
    init(_ cadence: Cadence, running: Bool, @ViewBuilder content: @escaping (Date) -> Content) {
        self.cadence = cadence
        isRunning = running
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: cadence.interval, paused: !(isRunning && windowIsVisible))) {
            content($0.date)
        }
    }
}
