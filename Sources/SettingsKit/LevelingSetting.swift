// LevelingSetting — Leveling as the listener chooses it (R1.1-B, US-R1F-10 item 1): the value `ListeningSettings`
// keeps and reads back. It is the leveling rules' own mode (LevelingKit's `LevelingMode`, which the decision builder
// reads), not a second enum mapped onto it (review N6): one set of cases, stored by its raw value — a word, so
// reordering the cases can never change what a stored setting reads as; a value this build can't read is Off
// (`ListeningSettings.init(from:)`).

import LevelingKit

/// Leveling: whether the app evens out track levels, and over what — Off (the faithful default, FD-2), Auto, Album,
/// Track. The settings' name for LevelingKit's `LevelingMode`.
public typealias LevelingSetting = LevelingMode
