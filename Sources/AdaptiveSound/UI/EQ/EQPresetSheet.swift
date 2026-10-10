import EQEditKit

// MARK: - EQ preset sheet (Sprint EQ, EQ4)

/// The preset sheet the EQ screen has open (`SaveCustomPresetView`): Save — holding what played when it
/// opened and the slot it played in, so an output switch while it is up never changes what is saved or
/// where (break-it C1) — or Rename one of My Presets.
enum EQPresetSheet: Identifiable {
    case save(EQSaveSource)
    case rename(String)

    var id: String {
        switch self {
        case .save: "save"
        case let .rename(name): "rename " + name
        }
    }
}
