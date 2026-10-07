#if DEBUG
    import Foundation

    // MARK: - Picture-sheet command line

    /// The renderer's command line. `-ASRenderSheets <dir>` turns it on; `-ASSheetTabs np,library` and
    /// `-ASSheetAppearances dark,light` narrow the matrix (default: every tab, every appearance).
    struct SheetRequest {
        let directory: URL
        let tabs: [TabSelection]
        let appearances: [SheetAppearance]

        /// The tab's slug — on the command line and in file names.
        static func slug(for tab: TabSelection) -> String {
            switch tab {
            case .nowPlaying: "np"
            case .library: "library"
            case .eq: "eq"
            case .monitoring: "monitoring"
            case .settings: "settings"
            }
        }

        /// `nil` when `-ASRenderSheets` is absent (a normal launch). A malformed flag exits with a usage
        /// error instead: falling through would launch the real app on a typo.
        static func parse(_ arguments: [String]) -> SheetRequest? {
            guard let flag = arguments.firstIndex(of: "-ASRenderSheets") else { return nil }
            guard let path = value(after: flag, in: arguments) else {
                usage("-ASRenderSheets needs an output directory")
            }
            return SheetRequest(
                directory: URL(filePath: path, directoryHint: .isDirectory),
                tabs: select(TabSelection.allCases, flag: "-ASSheetTabs", slug: slug(for:), in: arguments),
                appearances: select(SheetAppearance.allCases, flag: "-ASSheetAppearances", slug: \.rawValue,
                                    in: arguments)
            )
        }

        private static func value(after index: Int, in arguments: [String]) -> String? {
            let next = index + 1
            guard next < arguments.count, !arguments[next].hasPrefix("-") else { return nil }
            return arguments[next]
        }

        /// The members named by `flag`'s comma-separated slugs, kept in matrix order; all when absent.
        /// A list naming nothing (`-ASSheetTabs ""`) is a usage error, not a run that renders zero
        /// sheets and exits 0.
        private static func select<Member>(_ all: [Member], flag: String, slug: (Member) -> String,
                                           in arguments: [String]) -> [Member] {
            guard let index = arguments.firstIndex(of: flag) else { return all }
            guard let list = value(after: index, in: arguments) else { usage("\(flag) needs a comma-separated list") }
            let wanted = Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                .subtracting([""])
            let valid = all.map(slug)
            guard !wanted.isEmpty else { usage("\(flag) names nothing (valid: \(valid.joined(separator: ",")))") }
            if let unknown = wanted.subtracting(valid).sorted().first {
                usage("\(flag): unknown '\(unknown)' (valid: \(valid.joined(separator: ",")))")
            }
            return all.filter { wanted.contains(slug($0)) }
        }

        static func usage(_ message: String) -> Never {
            FileHandle.standardError.write(Data("sheets: \(message)\n".utf8))
            exit(EX_USAGE)
        }
    }
#endif
