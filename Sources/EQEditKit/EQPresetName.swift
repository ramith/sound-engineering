// EQPresetName — what a My Preset may be called (Sprint EQ, EQ4; break-it N1/N2). The Save and Rename
// sheet checks a name as it is typed and shows why one won't do; Save and Rename refuse the same names.
//
// - Spaces and line breaks at either end don't count, and a line break inside becomes a space (a
//   pasted name stays one line). Nothing left is no name (N2).
// - A built-in's name is taken, in any case: "warm" would read exactly like Warm next to it (N1).
// - My Presets' names are unique in any case: saving onto one replaces it under its own name; renaming
//   onto another is refused.

import Foundation

public enum EQPresetName {
    /// The verdict on a typed name.
    public enum Check: Equatable, Sendable {
        /// A new name: the preset is stored under it.
        case new(String)
        /// Save only: it names one of My Presets (in any case), which the save replaces, keeping its name.
        case replaces(String)
        /// Refused, and why.
        case invalid(Problem)
    }

    /// Why a name is refused.
    public enum Problem: Equatable, Sendable {
        case empty
        /// A built-in preset's name (its display name).
        case builtIn(String)
        /// Rename only: another of My Presets has it.
        case taken(String)

        /// The sheet's inline copy.
        public var message: String {
            switch self {
            case .empty: "Type a name — spaces alone don't make one."
            case let .builtIn(name): "“\(name)” is a built-in preset. Choose another name."
            case let .taken(name): "You already have a preset named “\(name)”."
            }
        }
    }

    /// `typed` checked against the built-ins and `myPresets`' names. `renaming` is the preset being
    /// renamed: its own name (in another case, too) is fine, and another preset's is taken.
    public static func check(_ typed: String, among myPresets: some Collection<String>,
                             renaming original: String? = nil) -> Check {
        let name = normalized(typed)
        guard !name.isEmpty else { return .invalid(.empty) }
        let builtIn = EQBuiltInPreset.allCases.first { matches(name, $0.displayName) || matches(name, $0.rawValue) }
        if let builtIn {
            return .invalid(.builtIn(builtIn.displayName))
        }
        let existing = myPresets.first { $0 != original && matches(name, $0) }
        guard let existing else { return .new(name) }
        return original == nil ? .replaces(existing) : .invalid(.taken(existing))
    }

    /// The name as it is stored: one line, with no spaces or line breaks at either end.
    static func normalized(_ typed: String) -> String {
        typed.components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The same name, in any case.
    private static func matches(_ name: String, _ other: String) -> Bool {
        name.caseInsensitiveCompare(other) == .orderedSame
    }
}
