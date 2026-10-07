#if DEBUG
    import AppKit
    import SwiftUI

    // MARK: - Picture-sheet renderer

    /// Debug-only picture-sheet renderer (S10.8 glass sweep, decision 9 / PR A4).
    ///
    /// `AdaptiveSound -ASRenderSheets <dir>` — or `make sheets` — renders whole app screens offscreen
    /// from `SheetFixture` models, every tab × appearance × reference size, into
    /// `<tab>-<appearance>-<w>x<h>.png`, then exits: 0 when every sheet was written, 1 otherwise. It runs
    /// first thing in `AdaptiveSound.init()`, BEFORE `SingleInstanceGuard`, so it works beside a running
    /// copy of the app without taking its lock, and it never opens the library store, the audio engine
    /// or device, or `UserDefaults.standard` (see `SheetFixture`).
    ///
    /// Out of reach (plan §E A4 — those cells stay founder-only): system-drawn surfaces (menus, sheets,
    /// popovers, alerts), and anything blended with what is behind the window.
    @MainActor
    enum SheetRenderer {
        /// The scene's default window size (`AdaptiveSound.body`'s `.defaultSize`) and the hard minimum.
        private static let sizes = [
            NSSize(width: 1000, height: 720),
            NSSize(width: DesignSystem.ShellMetrics.windowMinWidth, height: DesignSystem.ShellMetrics.windowMinHeight),
        ]
        /// The renderer's private defaults suite — wiped before and after every run.
        private static let defaultsSuite = "AdaptiveSound.SheetRenderer"

        /// Renders and exits when the command line asks for sheets; returns at once otherwise.
        static func runIfRequested() {
            guard let request = SheetRequest.parse(ProcessInfo.processInfo.arguments) else { return }
            run(request)
        }

        private static func run(_ request: SheetRequest) -> Never {
            let total = request.appearances.count * request.tabs.count * sizes.count
            guard total > 0 else { SheetRequest.usage("the selection renders no sheets") }
            NSApplication.shared.setActivationPolicy(.prohibited) // no Dock icon, never frontmost
            do {
                try FileManager.default.createDirectory(at: request.directory, withIntermediateDirectories: true)
            } catch {
                fail("can't create \(request.directory.path): \(error.localizedDescription)")
            }
            guard let defaults = UserDefaults(suiteName: defaultsSuite) else { fail("no defaults suite") }
            defaults.removePersistentDomain(forName: defaultsSuite)
            let fixture = SheetFixture(defaults: defaults)
            var failures: [String] = []
            for appearance in request.appearances {
                failures += render(appearance, tabs: request.tabs, fixture: fixture, into: request.directory)
            }
            defaults.removePersistentDomain(forName: defaultsSuite)
            print("sheets: \(total - failures.count) of \(total) written to \(request.directory.path)")
            failures.forEach { print("sheets: FAILED \($0)") }
            exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        /// Every tab at every size in one appearance; returns the sheets that could not be written.
        private static func render(_ appearance: SheetAppearance, tabs: [TabSelection], fixture: SheetFixture,
                                   into directory: URL) -> [String] {
            guard let windowAppearance = appearance.makeAppearance() else {
                return tabs.flatMap { tab in
                    sizes.map { "\(fileName(tab, appearance, $0)): this macOS can't build the appearance" }
                }
            }
            var failures: [String] = []
            for tab in tabs {
                fixture.audio.selectedTab = tab
                for size in sizes {
                    let name = fileName(tab, appearance, size)
                    if let reason = snapshot(fixture.root(for: appearance), appearance: windowAppearance, size: size,
                                             to: directory.appending(path: name)) {
                        failures.append("\(name): \(reason)")
                    }
                }
            }
            return failures
        }

        private static func fileName(_ tab: TabSelection, _ appearance: SheetAppearance, _ size: NSSize) -> String {
            "\(SheetRequest.slug(for: tab))-\(appearance.rawValue)-\(Int(size.width))x\(Int(size.height)).png"
        }

        /// Hosts `view` in a borderless window that is never ordered on screen, lets SwiftUI settle
        /// (`.task`s run, Monitoring's poll ticks), and writes the hosting view's own drawing as a PNG at
        /// the screen's backing scale, in sRGB — the cached bitmap carries the DISPLAY's profile, so
        /// raw pixel values (and sheet-to-sheet diffs) would otherwise differ from Mac to Mac.
        /// Returns why it failed, or `nil` on success.
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
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return "no bitmap" }
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
