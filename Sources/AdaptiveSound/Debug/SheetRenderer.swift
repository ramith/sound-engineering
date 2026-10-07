#if DEBUG
    import AppKit
    import SwiftUI

    // MARK: - Picture-sheet renderer

    /// Debug-only picture-sheet renderer (S10.8 glass sweep, decision 9 / PR A4).
    ///
    /// `AdaptiveSound -ASRenderSheets <dir>` — or `make sheets` — renders whole app screens offscreen
    /// from `SheetFixture` models, every tab × appearance × reference size, into
    /// `<tab>-<appearance>-<w>x<h>.png`, plus the cheap `SheetVariant` extras (keyboard ring, empty
    /// states) as `<tab>-<appearance>-<variant>-<w>x<h>.png`, then exits: 0 when every sheet was
    /// written, 1 otherwise. It runs
    /// first thing in `AdaptiveSound.init()`, BEFORE `SingleInstanceGuard`, so it works beside a running
    /// copy of the app without taking its lock, and it never opens the library store, the audio engine
    /// or device, or the app's settings (see `SheetFixture`).
    ///
    /// Out of reach (plan §E A4 — those cells stay founder-only): system-drawn surfaces (menus, sheets,
    /// popovers, alerts), and anything blended with what is behind the window.
    @MainActor
    enum SheetRenderer {
        /// The renderer's private defaults suite — wiped before and after every run.
        private static let defaultsSuite = "AdaptiveSound.SheetRenderer"

        /// Renders and exits when the command line asks for sheets; returns at once otherwise.
        static func runIfRequested() {
            guard let request = SheetRequest.parse(ProcessInfo.processInfo.arguments) else { return }
            run(request)
        }

        private static func run(_ request: SheetRequest) -> Never {
            let total = SheetVariant.allCases.reduce(0) { $0 + $1.sheetCount(for: request) }
            guard total > 0 else { SheetRequest.usage("the selection renders no sheets") }
            NSApplication.shared.setActivationPolicy(.prohibited) // no Dock icon, never frontmost
            do {
                try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
            } catch {
                fail("can't create \(request.directory.path): \(error.localizedDescription)")
            }
            guard let defaults = UserDefaults(suiteName: defaultsSuite) else { fail("no defaults suite") }
            defaults.removePersistentDomain(forName: defaultsSuite)
            if NSScreen.main?.backingScaleFactor != scale {
                // Text and AppKit controls rasterize for the WINDOW's screen even in the 2x bitmap.
                print("sheets: WARNING the main screen is not 2x — text rasterizes for it; don't diff these "
                    + "against sheets rendered with a Retina main screen")
            }
            var failures: [String] = []
            for variant in SheetVariant.allCases where variant.sheetCount(for: request) > 0 {
                let fixture = SheetFixture(defaults: defaults, variant: variant)
                for appearance in variant.appearances(of: request) {
                    failures += render(appearance, tabs: variant.tabs(of: request), fixture: fixture,
                                       into: request.directory)
                }
            }
            defaults.removePersistentDomain(forName: defaultsSuite)
            print("sheets: \(total - failures.count) of \(total) written to \(request.directory.path)")
            failures.forEach { print("sheets: FAILED \($0)") }
            exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        /// Every tab at each of the fixture variant's sizes in one appearance; returns the sheets that
        /// could not be written.
        private static func render(_ appearance: SheetAppearance, tabs: [TabSelection], fixture: SheetFixture,
                                   into directory: URL) -> [String] {
            let variant = fixture.variant
            guard let windowAppearance = appearance.makeAppearance() else {
                let names = tabs.flatMap { tab in variant.sizes.map { fileName(tab, appearance, variant, $0) } }
                return names.map { "\($0): this macOS can't build the appearance" }
            }
            var failures: [String] = []
            for tab in tabs {
                fixture.audio.selectedTab = tab
                for size in variant.sizes {
                    let name = fileName(tab, appearance, variant, size)
                    if let reason = snapshot(fixture.root(for: appearance), appearance: windowAppearance, size: size,
                                             to: directory.appending(path: name)) {
                        failures.append("\(name): \(reason)")
                    }
                }
            }
            return failures
        }

        private static func fileName(_ tab: TabSelection, _ appearance: SheetAppearance, _ variant: SheetVariant,
                                     _ size: NSSize) -> String {
            let dimensions = "\(Int(size.width))x\(Int(size.height))"
            let parts = [SheetRequest.slug(for: tab), appearance.rawValue, variant.slug, dimensions]
            return parts.compactMap(\.self).joined(separator: "-") + ".png"
        }

        /// Sheets always render at Retina density, composited in Display P3 (a Retina panel's space,
        /// where the live app composites). The main screen is not a fixed fact: with a 1x external
        /// display set as main, the screen-derived bitmap wrote 1000×720 sheets in that display's
        /// profile, which no earlier sheet can be diffed against (S10.8 B2a). Text and AppKit
        /// controls still rasterize for the main screen (an offscreen window's), hence the warning.
        private static let scale: CGFloat = 2

        /// Hosts `view` in a borderless window that is never ordered on screen, lets SwiftUI settle
        /// (`.task`s run, Monitoring's poll ticks), and writes the hosting view's own drawing as a PNG:
        /// drawn at `scale` into a Display P3 bitmap, then converted to sRGB — never the attached
        /// display's density or colour profile, so sheet-to-sheet diffs hold across displays (text
        /// aside: see `scale`). Returns why it failed, or `nil` on success.
        private static func snapshot(_ view: some View, appearance: NSAppearance, size: NSSize,
                                     to url: URL) -> String? {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = appearance
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            defer { window.contentView = nil }
            for _ in 0 ..< 6 {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            }
            guard host.bounds.size == size else { return "laid out at \(host.bounds.size), not \(size)" }
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            )?.retagging(with: .displayP3) else { return "no bitmap" }
            bitmap.size = size // points; the pixel dimensions above set the density
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let srgb = bitmap.converting(to: .sRGB, renderingIntent: .default) else { return "no sRGB bitmap" }
            guard let png = srgb.representation(using: .png, properties: [:]) else { return "PNG encoding failed" }
            do {
                try png.write(to: url)
            } catch {
                return error.localizedDescription
            }
            return nil
        }

        private static func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data("sheets: \(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
#endif
