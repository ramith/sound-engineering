// LevelingSetting — Leveling as the listener chooses it (R1.1-B, US-R1F-10 item 1): the value
// `ListeningSettings` keeps and reads back. The app maps it to the leveling rules' scope (LevelingKit) when it
// builds each track's decision (`AudioViewModel+Leveling`); a value this build can't read is Off.

/// Leveling: whether the app evens out track levels, and over what. Off is the faithful default (FD-2): the
/// music plays as recorded. The raw value is what is stored — a word, so reordering the cases can never change
/// what a stored setting reads as.
public enum LevelingSetting: String, CaseIterable, Identifiable, Sendable {
    /// No leveling gain: the music as recorded.
    case off
    /// The album's level when the song beside it — the one just played, or the next — is from the same album;
    /// else the song's own.
    case auto
    /// Every song at its album's level.
    case album
    /// Every song at its own level (a run of songs that join without a pause shares one).
    case track

    public var id: String {
        rawValue
    }
}
