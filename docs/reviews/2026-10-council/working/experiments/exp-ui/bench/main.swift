// Council UI reviewer experiment (read-only on the repo): relative main-thread cost of a
// spectrum frame as 88 SwiftUI views (the shape of UI/Spectrum/SpectrumAnalyzerView.swift:50-84)
// versus one Canvas pass (the shape of UI/Monitoring/SpectrumMiniView.swift:36-66).
// Offscreen NSHostingView, never ordered on screen; no audio, no app code.
import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class Model {
    var bars: [Float] = .init(repeating: 0, count: 88)
    var caps: [Float] = .init(repeating: 0, count: 88)
    var isPlaying = true
}

struct CapOpacity: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View { content.opacity(colorScheme == .dark ? 0.5 : 0.85) }
}

let fills: [LinearGradient] = (0 ..< 88).map { i in
    let t = Double(i) / 87
    return LinearGradient(colors: [Color(.sRGB, red: 0.2 + 0.6 * t, green: 0.8, blue: 0.7 - 0.5 * t, opacity: 1),
                                   Color(.sRGB, red: 0.1 + 0.5 * t, green: 0.6, blue: 0.6 - 0.4 * t, opacity: 1)],
                          startPoint: .top, endPoint: .bottom)
}

struct ViewPerBar: View {
    let model: Model
    var body: some View {
        let bars = model.bars
        let caps = model.caps
        GeometryReader { geo in
            let maxBarHeight = geo.size.height
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0 ..< bars.count, id: \.self) { index in
                    let barHeight = CGFloat(min(max(bars[index], 0), 1)) * maxBarHeight
                    let capValue = CGFloat(min(max(caps[index], 0), 1))
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(fills[index])
                            .frame(height: barHeight)
                            .animation(.easeOut(duration: 0.08), value: bars[index])
                        if capValue * maxBarHeight > barHeight + 1 {
                            RoundedRectangle(cornerRadius: 1, style: .continuous)
                                .fill(fills[index])
                                .modifier(CapOpacity())
                                .frame(height: 2)
                                .offset(y: -(capValue * maxBarHeight + 4))
                                .animation(.easeOut(duration: 0.08), value: caps[index])
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
        .opacity(model.isPlaying ? 1 : 0.4)
    }
}

struct CanvasBars: View {
    let model: Model
    var body: some View {
        let bars = model.bars
        let caps = model.caps
        Canvas { context, size in
            let count = bars.count
            let spacing: CGFloat = 2
            let width = max(1, (size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            for index in 0 ..< count {
                let h = CGFloat(min(max(bars[index], 0), 1)) * size.height
                let x = CGFloat(index) * (width + spacing)
                let rect = CGRect(x: x, y: size.height - h, width: width, height: h)
                context.fill(Path(roundedRect: rect, cornerRadius: 2),
                             with: .linearGradient(Gradient(colors: [.teal, .green]),
                                                   startPoint: CGPoint(x: x, y: rect.minY),
                                                   endPoint: CGPoint(x: x, y: rect.maxY)))
                let capY = size.height - CGFloat(min(max(caps[index], 0), 1)) * size.height - 4
                if capY < rect.minY - 1 {
                    context.fill(Path(roundedRect: CGRect(x: x, y: capY, width: width, height: 2), cornerRadius: 1),
                                 with: .color(.teal.opacity(0.5)))
                }
            }
        }
        .opacity(model.isPlaying ? 1 : 0.4)
    }
}

func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
}

@MainActor func measure(_ name: String, frames: Int, _ make: (Model) -> AnyView) {
    let model = Model()
    let size = NSSize(width: 480, height: 90)
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                          backing: .buffered, defer: false)
    let host = NSHostingView(rootView: make(model))
    host.frame = NSRect(origin: .zero, size: size)
    window.contentView = host
    // settle
    for _ in 0 ..< 5 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05)) }
    var seed: UInt64 = 42
    func rnd() -> Float { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Float(seed >> 40) / Float(1 << 24) }
    var wall: [Double] = []
    let cpu0 = cpuSeconds()
    for _ in 0 ..< frames {
        var bars = model.bars
        var caps = model.caps
        for i in 0 ..< 88 { bars[i] = rnd(); caps[i] = min(1, bars[i] + 0.1) }
        let t0 = CFAbsoluteTimeGetCurrent()
        model.bars = bars
        model.caps = caps
        // one main run-loop turn: SwiftUI's update (body, diff, layout, display list) runs here
        CFRunLoopRunInMode(.defaultMode, 0, false)
        host.layoutSubtreeIfNeeded()
        CATransaction.flush()
        wall.append(CFAbsoluteTimeGetCurrent() - t0)
        // let in-flight implicit animations tick as they would between 20 Hz frames
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
    }
    let cpu = cpuSeconds() - cpu0
    wall.sort()
    let median = wall[wall.count / 2] * 1000
    let p95 = wall[Int(Double(wall.count) * 0.95)] * 1000
    print(String(format: "%-14@ frames=%d  update median=%.3f ms  p95=%.3f ms  process CPU total=%.3f s (%.3f ms/frame)",
                 name as NSString, frames, median, p95, cpu, cpu / Double(frames) * 1000))
    window.contentView = nil
}

@main struct Bench {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let frames = 300
        measure("view-per-bar", frames: frames) { AnyView(ViewPerBar(model: $0)) }
        measure("canvas", frames: frames) { AnyView(CanvasBars(model: $0)) }
        measure("view-per-bar", frames: frames) { AnyView(ViewPerBar(model: $0)) }
        measure("canvas", frames: frames) { AnyView(CanvasBars(model: $0)) }
    }
}
