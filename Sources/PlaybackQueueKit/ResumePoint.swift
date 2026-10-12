// PlaybackQueueKit — where a paused song resumes (D2; S10.8 G).
//
// Pure and generic over the queue slot's identity, so the ownership rule — the place belongs to the
// SONG's slot, never to a row number — is unit-tested without the engine or the view model
// (`ResumePointTests`).

/// Where Play resumes a paused song: the queue slot the song sits in, and the offset in it.
///
/// Keyed by the slot's identity, not its row. Removing or moving OTHER rows shifts the paused song's
/// row but keeps its place; removing the paused song slides another slot into its row, and the place
/// applies to no other slot — so that song starts from the top.
public struct ResumePoint<SlotID: Equatable & Sendable>: Sendable {
    private let slot: SlotID
    private var seconds: Double

    /// The place of the song in `slot`, paused at `seconds`.
    public init(slot: SlotID, seconds: Double) {
        self.slot = slot
        self.seconds = seconds
    }

    /// The offset to resume `selected` from: this place's offset when `selected` is its slot, else nil.
    public func seconds(resuming selected: SlotID?) -> Double? {
        selected == slot ? seconds : nil
    }

    /// A scrub while paused: only where Play resumes moves.
    public mutating func move(to seconds: Double) {
        self.seconds = seconds
    }
}
