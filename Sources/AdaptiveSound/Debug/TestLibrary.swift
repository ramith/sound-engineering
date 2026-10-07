#if DEBUG
    import Foundation

    // MARK: - Isolated test library

    /// Debug-only isolated test library (S10.8 C1). `AdaptiveSound -ASTestLibrary [<music folder>]` —
    /// or `make run-test-library` — moves everything the app persists (`AppDataLocation`) at once:
    /// - the library store and its artwork cache → `~/Library/Application Support/AdaptiveSound Test
    ///   Library/`; the watched music folders, playlists, the queue and play history live in the store,
    ///   so they move with it;
    /// - the settings → the `AdaptiveSound.TestLibrary` defaults suite (the view models and, through
    ///   `.defaultAppStorage`, every `@AppStorage`);
    /// - the single-instance lock → that folder, so the test copy runs beside the user's own.
    ///
    /// With a music folder, the library scans it on every launch: an exact root re-adds as a no-op, so
    /// a re-run only picks up changed files. Without one, the test library starts empty.
    ///
    /// AppKit keeps its own state — window and split-view frames, the open panel's last folder, saved
    /// window state — under the BUNDLE identifier, which no in-process switch can move. So the switch
    /// refuses to run inside the user's bundle, and `make run-test-library` bundles the test copy under
    /// its own identifier (a bare `swift build` binary has none, so it never reaches the user's domain).
    enum TestLibrary {
        private static let flag = "-ASTestLibrary"
        private static let folderName = "AdaptiveSound Test Library"
        private static let defaultsSuite = "AdaptiveSound.TestLibrary"
        /// `Info.plist`'s `CFBundleIdentifier`: the bundle whose AppKit state must never see a test run.
        private static let userBundleIdentifier = "com.adaptivesound.app"

        /// The test library's location, or `nil` when `-ASTestLibrary` is absent (a normal launch). A
        /// bad launch exits with a usage error instead: falling through would open the user's library.
        static func location(from arguments: [String]) -> AppDataLocation? {
            guard let index = arguments.firstIndex(of: flag) else { return nil }
            if Bundle.main.bundleIdentifier == userBundleIdentifier {
                usage("\(flag) can't run inside the user's app bundle — AppKit would save its window state "
                    + "into the user's settings. Use `make run-test-library`.")
            }
            guard let defaults = UserDefaults(suiteName: defaultsSuite) else { usage("no defaults suite") }
            return AppDataLocation(directory: AppDataLocation.applicationSupport(folderName), defaults: defaults,
                                   testMusicFolder: musicFolder(after: index, in: arguments))
        }

        /// The folder named after the flag (any argument not starting with `-`), which must exist.
        private static func musicFolder(after index: Int, in arguments: [String]) -> URL? {
            let next = index + 1
            guard next < arguments.count, !arguments[next].hasPrefix("-") else { return nil }
            let folder = URL(filePath: arguments[next], directoryHint: .isDirectory).absoluteURL.standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                usage("\(flag): no folder at \(folder.path) (make stress-library writes one)")
            }
            return folder
        }

        private static func usage(_ message: String) -> Never {
            FileHandle.standardError.write(Data("test library: \(message)\n".utf8))
            exit(EX_USAGE)
        }
    }
#endif
