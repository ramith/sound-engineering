// MARK: - AudioEngineBridge leveling (R1.1-B, the level-and-fold design §S3)

//
// Lane 1's file in W4 (docs/design/level-and-fold/README.md §9, condition C3.3). At the coordinator's commit 0
// it holds only the type of the bridge's stored `leveling` property, so that property's line in
// AudioEngineBridge.swift (lane 2's file) is settled before the lanes start and lane 2 never touches it.

/// What the bridge keeps for leveling between a start or arm and the moment its track becomes audible: the
/// decision each request carries and what the planner made of it. Lane 1 fills it. Confined to `engineQueue`.
struct EngineLevelingState {}
