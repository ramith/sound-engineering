#if DEBUG
    import AppKit
    import LibraryStore
    import SwiftUI

    // MARK: - Songs list performance run (S10.8 E1 — the End-key hang)

    /// `AdaptiveSound -ASSongsPerf` (`make songs-perf`): the Songs list over `songCount` fixture songs,
    /// hosted offscreen at the default window size, with the keyboard keys pressed through the list's
    /// own navigation path (`SongsListProbe`). Each key is timed until the list settles — no new list
    /// pass or row build for `quietPeriod` — and reported with the passes and row builds it cost and
    /// the rows it built. Exits 0 when every key settles within `bound`, builds at most `rowBudget`
    /// rows and brings its cursor row on screen (built), at the row it must reach; then a user scroll
    /// must not re-run the list per frame. Exits 1 otherwise; 2 from the watchdog if the main thread
    /// hangs (the founder's End press ran for minutes).
    ///
    /// Like the picture sheets it runs before the single-instance lock and touches no library store,
    /// audio device or app setting: storeless models, the hardware-free `SheetEngine`, a private
    /// defaults suite wiped before and after.
    @MainActor
    enum SongsPerfRun {
        /// The S9.5 hard gate's library size and bound: click-select and arrow-move under 100 ms at
        /// 20k songs (`s9-5-songs-search-design.md`, OD-1) — here for every key, End and Home too.
        static let songCount = 20000
        static let bound: Duration = .milliseconds(100)
        /// The most row views a key may build — a few screenfuls; thousands means the list realized
        /// rows it never shows.
        static let rowBudget = 400
        private static let quietPeriod: Duration = .milliseconds(250)
        /// Rows a simulated user scroll moves, one per frame.
        private static let scrollFrames = 20
        private static let watchdogSeconds: TimeInterval = 120
        private static let windowSize = NSSize(width: 1000, height: 720)
        private static let defaultsSuite = "AdaptiveSound.SongsPerf"

        /// A key, and the row its cursor must land on (nil: wherever the key takes it).
        private struct Step {
            let name: String
            let key: KeyEquivalent
            let reaches: Int?
        }

        private static let steps = [
            Step(name: "End", key: .end, reaches: songCount),
            Step(name: "Home", key: .home, reaches: 1),
            Step(name: "Page Down", key: .pageDown, reaches: nil),
            Step(name: "↓", key: .downArrow, reaches: nil),
            Step(name: "End", key: .end, reaches: songCount),
            Step(name: "Page Up", key: .pageUp, reaches: nil),
            Step(name: "↑", key: .upArrow, reaches: nil),
        ]

        static func runIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-ASSongsPerf") else { return }
            run()
        }

        private static func run() -> Never {
            NSApplication.shared.setActivationPolicy(.prohibited) // no Dock icon, never frontmost
            startWatchdog()
            guard let defaults = UserDefaults(suiteName: defaultsSuite) else { fail("no defaults suite") }
            defaults.removePersistentDomain(forName: defaultsSuite)
            defer { defaults.removePersistentDomain(forName: defaultsSuite) }
            let probe = SongsListProbe()
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: windowSize), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            let host = NSHostingView(rootView: root(defaults: defaults, probe: probe))
            host.frame = NSRect(origin: .zero, size: windowSize)
            window.contentView = host
            let opened = settle(host, probe: probe)
            print("songs-perf: \(songCount) songs; open \(report(opened, probe: probe))")
            guard let press = probe.press else { fail("the Songs list never registered its keys") }
            var failures: [String] = []
            for step in steps {
                probe.reset()
                let cursorRow = press(step.key)
                let elapsed = settle(host, probe: probe)
                print("songs-perf: \(step.name.padding(toLength: 10, withPad: " ", startingAt: 0)) "
                    + report(elapsed, probe: probe) + ", cursor row \(cursorRow.map(String.init) ?? "none")")
                failures += check(step, cursorRow: cursorRow, elapsed: elapsed, probe: probe)
            }
            failures += userScroll(host, probe: probe)
            window.contentView = nil
            failures.forEach { print("songs-perf: FAILED \($0)") }
            print("songs-perf: \(failures.isEmpty ? "PASS" : "FAIL") (bound \(bound), \(rowBudget) rows)")
            exit(failures.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        /// The Songs card as the Library tab shows it, focused with the ring drawn (as after a key).
        private static func root(defaults: UserDefaults, probe: SongsListProbe) -> some View {
            let audio = AudioViewModel(defaults: defaults, engine: SheetEngine(before: [], after: []))
            let library = LibraryModel(storeless: ())
            let browse = LibraryBrowseModel(audio: audio, library: library)
            let songs = songs()
            browse.seedRenderFixture(songs: songs)
            audio.queue = [QueueItem(file: AudioFile(songs[songs.count / 2]))] // a playing row mid-list
            audio.selectedTrackIndex = 0
            audio.isPlaying = true
            return SongsView()
                .environment(audio)
                .environment(library)
                .environment(browse)
                .environment(PlaylistsModel(library: library, audio: audio))
                .environment(KeyboardTransportFocus())
                .environment(\.showsKeyboardFocus, true)
                .environment(\.sheetFocusedLists, [.songs])
                .environment(\.songsListProbe, probe)
                .defaultAppStorage(defaults)
        }

        /// Lays out and runs the main run loop until the list has been quiet for `quietPeriod`;
        /// returns the time to its last pass or row build.
        private static func settle(_ host: NSView, probe: SongsListProbe) -> Duration {
            let start = ContinuousClock.now
            var lastWork = start
            var seen = -1
            while lastWork.duration(to: .now) < quietPeriod {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
                let work = probe.listPasses + probe.rowBuilds
                if work != seen {
                    seen = work
                    lastWork = .now
                }
            }
            return start.duration(to: lastWork)
        }

        private static func report(_ elapsed: Duration, probe: SongsListProbe) -> String {
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            return "settled in \(seconds.formatted(.number.precision(.fractionLength(3)))) s — "
                + "\(probe.listPasses) list passes, \(probe.rowBuilds) rows built (rows \(probe.builtRowRuns))"
        }

        private static func check(_ step: Step, cursorRow: Int?, elapsed: Duration,
                                  probe: SongsListProbe) -> [String] {
            var failures: [String] = []
            if elapsed > bound {
                failures.append("\(step.name): \(elapsed) > \(bound)")
            }
            if probe.rowBuilds > rowBudget {
                failures.append("\(step.name): \(probe.rowBuilds) rows built > \(rowBudget)")
            }
            if let target = step.reaches, cursorRow != target {
                failures.append("\(step.name): the cursor is on row \(cursorRow ?? 0), not \(target)")
            }
            if let cursorRow, !probe.builtRows.contains(cursorRow) {
                failures.append("\(step.name): cursor row \(cursorRow) never built — not scrolled into view")
            }
            return failures
        }

        /// A user scroll: the row area's own platform scroll view moved a row per frame, as a wheel or
        /// trackpad moves it, towards the top. Rows come into view, but the list itself must not run
        /// again per frame — the keys' `scrollPosition` binding must not write back on every frame.
        private static func userScroll(_ host: NSView, probe: SongsListProbe) -> [String] {
            guard let scrollView = rowAreaScrollView(in: host), let document = scrollView.documentView else {
                return ["user scroll: the row area's scroll view was not found"]
            }
            probe.reset()
            let clip = scrollView.contentView
            let start = clip.bounds.origin.y
            for _ in 0 ..< scrollFrames {
                var origin = clip.bounds.origin
                origin.y += document.isFlipped ? -SongRow.height : SongRow.height
                clip.scroll(to: origin)
                scrollView.reflectScrolledClipView(clip)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
            }
            let elapsed = settle(host, probe: probe)
            let moved = Int(abs(clip.bounds.origin.y - start) / SongRow.height)
            print("songs-perf: scroll     \(moved) rows up by frame, \(report(elapsed, probe: probe))")
            var failures: [String] = []
            if moved < scrollFrames {
                failures.append("user scroll: moved \(moved) rows, not \(scrollFrames)")
            }
            if probe.listPasses > 1 {
                failures.append("user scroll: \(probe.listPasses) list passes — the list re-runs as it scrolls")
            }
            return failures
        }

        /// The row area's platform scroll view: the one whose document is many screens tall.
        private static func rowAreaScrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView, let document = scrollView.documentView,
               document.frame.height > 10 * scrollView.contentView.bounds.height {
                return scrollView
            }
            return view.subviews.lazy.compactMap { rowAreaScrollView(in: $0) }.first
        }

        /// A library large enough to show the hang: grouped by artist like a real one, every title
        /// distinct.
        private static func songs() -> [LibraryTrackDisplay] {
            (1 ... songCount).map { index in
                let id = Int64(index)
                let artist = "Artist \(index / 40 + 1)"
                return LibraryTrackDisplay(
                    id: id, url: URL(filePath: "/fixture/\(id).flac"), title: "Song \(index)",
                    artistID: 100_000 + id / 40, artistName: artist, albumID: 200_000 + id / 10,
                    albumName: "Album \(index / 10 + 1)", format: "FLAC", trackNo: index % 10 + 1,
                    durationMs: 240_000, year: 2000 + index % 25, artworkKey: nil, dateAdded: 0,
                    sampleRate: 48000, bitDepth: 24, discNo: 1, fileSize: 30_000_000, playCount: 0,
                    lastPlayed: nil, albumArtistName: artist, genreName: "Fixture"
                )
            }
        }

        /// Exits the process if the main thread is still busy after `watchdogSeconds` — a hang can't
        /// be timed from the thread it is hanging.
        private static func startWatchdog() {
            let seconds = watchdogSeconds
            Thread.detachNewThread {
                Thread.sleep(forTimeInterval: seconds)
                FileHandle.standardError.write(Data("songs-perf: TIMEOUT — still busy after \(seconds) s\n".utf8))
                exit(2)
            }
        }

        private static func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data("songs-perf: \(message)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }
#endif
