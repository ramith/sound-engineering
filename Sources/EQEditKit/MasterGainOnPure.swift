// MasterGainOnPure — Master Gain on Pure is the output device's own volume (R1.1-A, founder decision
// 2026-10-15: "turn the Mac's volume down instead"; council C-29).
//
// Pure never scales the bit-perfect stream, so on Pure the one gain is the device's own (analog or
// device-side) volume. The rule, as the listener meets it:
//
// - ENTERING PURE with Master Gain below 0 dB engages Pure at once and lowers the device by the Master
//   Gain amount, from the level it found — so the music is exactly as loud as it was on Enhanced, and
//   the file stays bit-perfect. At 0 dB nothing is touched. The level found is remembered as the loan's
//   CEILING: Pure never sets the device above it.
// - WHILE PURE PLAYS, the Master Gain slider moves the device: the level found, lowered by Master Gain,
//   within the device's range (Silent is its minimum), never above the ceiling.
// - THE LISTENER'S OWN CHANGE STANDS (the volume keys, Control Center, another app): the app sets
//   nothing in answer. It reads the change as a change to the Mac's own volume, with Master Gain's cut
//   still on top: the loan's ANCHOR — the level Master Gain's 0 dB stands for — moves to the new level
//   plus the cut (never above the ceiling), and the slider moves from there.
// - LEAVING PURE puts the anchor back, and Master Gain plays in the app again — the same loudness. Only
//   while the device still reads what Pure last set; otherwise the listener changed it since, and their
//   level stands. The hold lasts while Pure is the device's PATH, not only while a Pure session renders
//   (founder decision 2026-10-16; `PureVolumeEvent`): a pause keeps the level Pure set (the session is
//   torn down, but playback resumes there), as does a device that went away; Pure is left by a stop
//   that ends playback (Stop, the end of the queue, the queue cleared, quit), Enhanced starting, or the
//   output moving to another device.
// - A DEVICE WITH NO VOLUME THE APP CAN SET (many DACs, HDMI): turned down, Pure waits — Enhanced keeps
//   playing at the listener's level until Master Gain is back at 0 dB (`waitsForMasterGain`).
// - NEVER LOUDER THAN MASTER GAIN SAYS (R1.1-A close-out break-it, H-1): a cut deeper than the device's own
//   range can't be made on the device, so Pure waits (`waitsBelowDeviceRange`) rather than stop at the
//   device's floor; Silent is silence — the device is muted if it has a mute the app can set (and the mute
//   is given back with the volume), else Pure waits. While Pure already plays, the slider moved below the
//   floor (or to Silent) mutes a device that has a mute; one without holds its floor, and the next start
//   waits.
// - CRASH-SAFE: every loan not yet settled (`allLoans`) is kept — WRITTEN AHEAD (`writeAhead`, the
//   engine's journal, `PureVolumeLoanJournal`): the level Pure is about to set (`pending`), or the mute
//   it is about to make, is kept before the device is asked, and the record after every change — so a
//   crash at any instant leaves the next launch a record that names Pure's level (H-2: it used to be kept
//   only by a 20 Hz tick, which sleeps while paused). A loan a device couldn't take back (it went away)
//   or that a crash left is put back when the device is seen again (`returnUnreturned`: at launch, at a
//   transport event, when the device list changes) — by the same rule: only if it still reads what Pure
//   set, or was setting.
//
// The HAL calls go through `DeviceVolumeControl` — a seam: the engine implements it with CoreAudio on its
// device-volume queue (never the main thread); the tests with a fake device. A plain value, confined to
// that one queue.

import Foundation

/// The output device's own volume as Pure reads it: its level and the range it can be set in, in dB on
/// the device's own scale.
public struct DeviceVolumeReading: Equatable, Sendable {
    public let level: Float
    public let range: ClosedRange<Float>

    public init(level: Float, range: ClosedRange<Float>) {
        self.level = level
        self.range = range
    }
}

/// The HAL calls Master Gain on Pure makes, for one device.
public protocol DeviceVolumeControl {
    /// The device's volume now, or nil when it has none the app can set (or it is gone).
    func read() -> DeviceVolumeReading?
    /// Pure's lowering: set the level, in dB within the device's range and never above 0 dB (turn-down
    /// only). False when the device refused or is gone.
    func set(_ decibels: Float) -> Bool
    /// The give-back: set the level Pure found, within the device's own range only — a device may sit
    /// above 0 dB (H-4). False when the device refused or is gone.
    func restore(_ decibels: Float) -> Bool
    /// Whether the device is muted, or nil when it has no mute the app can set.
    func isMuted() -> Bool?
    /// Mute or unmute it. False when it has no mute the app can set, refused, or is gone.
    func setMuted(_ mute: Bool) -> Bool
}

public extension DeviceVolumeControl {
    /// A device whose range ends at 0 dB gives back as it sets.
    func restore(_ decibels: Float) -> Bool {
        set(decibels)
    }

    /// No mute the app can set.
    func isMuted() -> Bool? {
        nil
    }

    func setMuted(_: Bool) -> Bool {
        false
    }
}

/// Pure's loan of a device's volume: what to put back when Pure stops. Kept with the listener's settings
/// while it is out, so a crash puts it back at the next launch.
public struct PureVolumeLoan: Codable, Equatable, Sendable {
    /// The device (its UID: the HAL's id changes across reconnects).
    public let deviceUID: String
    /// The level Pure found the device at: it never sets it higher, nor puts back more.
    public let ceiling: Float
    /// The level Master Gain's 0 dB stands for — the listener's own level: the ceiling, moved by any
    /// change the listener made since (never above it). What leaving Pure puts back.
    public var anchor: Float
    /// What the device read right after Pure last set it: a reading that matches is Pure's own.
    public var lastSet: Float
    /// Pure muted the device (Silent, or a cut below its range while playing — H-1): the mute is given
    /// back with the volume. A mute the listener made is never touched.
    public var mutedByPure: Bool
    /// The level Pure is setting the device to right now — kept before the device is asked (H-2), so a
    /// reading that matches it is Pure's own too, even if the app died before the set was read back.
    public var pending: Float?

    /// Whether the record can be trusted (R1.1-A close-out break-it, SET-3 / SET-4): a device, three
    /// levels that are numbers, and an anchor no higher than the ceiling — what Pure itself writes. A
    /// damaged one (a kept value edited, a bug) is never put back: the device stays where it is, never
    /// louder than Pure left it.
    public var isSound: Bool {
        let pendingSound = pending.map { $0.isFinite && $0 <= ceiling + MasterGainOnPure.sameLevel } ?? true
        return !deviceUID.isEmpty && ceiling.isFinite && anchor.isFinite && lastSet.isFinite
            && anchor <= ceiling + MasterGainOnPure.sameLevel && pendingSound
    }

    public init(deviceUID: String, ceiling: Float, anchor: Float, lastSet: Float, mutedByPure: Bool = false,
                pending: Float? = nil) {
        self.deviceUID = deviceUID
        self.ceiling = ceiling
        self.anchor = anchor
        self.lastSet = lastSet
        self.mutedByPure = mutedByPure
        self.pending = pending
    }

    private enum CodingKeys: String, CodingKey {
        case deviceUID, ceiling, anchor, lastSet, mutedByPure, pending
    }

    /// A kept record, as written; one from before the mute or the write-ahead reads as none made, nothing
    /// pending.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            deviceUID: container.decode(String.self, forKey: .deviceUID),
            ceiling: container.decode(Float.self, forKey: .ceiling),
            anchor: container.decode(Float.self, forKey: .anchor),
            lastSet: container.decode(Float.self, forKey: .lastSet),
            mutedByPure: container.decodeIfPresent(Bool.self, forKey: .mutedByPure) ?? false,
            pending: container.decodeIfPresent(Float.self, forKey: .pending)
        )
    }
}

/// Something that may end Pure's hold on a device's volume (founder decision 2026-10-16): the hold lasts
/// while Pure is that device's path, not only while a Pure session renders.
public enum PureVolumeEvent: Equatable, Sendable {
    /// Playback paused: it resumes on this device, so the device keeps the level Pure set.
    case paused
    /// The device went away mid-Pure: nothing is asked of a dying device; the loan stays held, and
    /// is given back when the device is seen again — or kept for the next launch.
    case deviceLost
    /// Playback stopped for good: the Stop command, the end of the queue, the queue cleared, quit.
    case stopped
    /// Enhanced starts: Pure is left.
    case enhancedStarted
    /// The app's output moved to the device `toUID`: Pure is left on any other device.
    case outputMoved(toUID: String)
}

/// Master Gain on Pure: the loan Pure holds now, and those it could not yet put back.
public struct MasterGainOnPure: Sendable {
    /// What entering Pure does.
    public enum Entry: Equatable, Sendable {
        /// Pure plays (the device lowered by Master Gain, when it was turned down).
        case engaged
        /// Pure waits: Master Gain is turned down and the device has no volume the app can set.
        case waitsForMasterGain
        /// Pure waits: Master Gain asks for less than the device's own range can give — a cut below its
        /// floor, or Silent on a device with no mute the app can set (H-1).
        case waitsBelowDeviceRange
    }

    /// Two readings this close are the same level (a device's read-back is exact; this absorbs float noise).
    static let sameLevel: Float = 0.05

    /// The loan of the device Pure plays on, or nil (off Pure, or a device with no volume to steer).
    public private(set) var loan: PureVolumeLoan?
    /// Loans not yet put back: the device went away first, or a crash left them.
    public private(set) var unreturned: [PureVolumeLoan]
    /// The Master Gain the device was last steered to: what a listener's change it hasn't seen yet is read
    /// against (H-5).
    private var steeredGain: Float = MasterGainLaw.unity

    /// Every loan not yet settled — what the listener's settings keep.
    public var allLoans: [PureVolumeLoan] {
        (loan.map { [$0] } ?? []) + unreturned
    }

    /// Where every loan not yet settled is kept, synchronously (the engine's journal): called with
    /// `allLoans` before each change Pure makes to a device and after every change to the record (H-2).
    public var writeAhead: @Sendable ([PureVolumeLoan]) -> Void

    /// Start with the loans a previous run left (`allLoans`, as kept): all unreturned until put back.
    public init(unreturned: [PureVolumeLoan] = [],
                writeAhead: @escaping @Sendable ([PureVolumeLoan]) -> Void = { _ in }) {
        self.unreturned = unreturned
        self.writeAhead = writeAhead
    }

    /// Keep the record as it stands now.
    private func keep() {
        writeAhead(allLoans)
    }

    /// Take in loans a previous run left (kept with the listener's settings) as unreturned — except
    /// for a device whose loan is held or already kept: what this run knows is newer.
    public mutating func adopt(_ kept: [PureVolumeLoan]) {
        defer { keep() }
        for kept in kept where kept.isSound && !allLoans.contains(where: { $0.deviceUID == kept.deviceUID }) {
            unreturned.append(kept)
        }
    }

    /// Pure is about to play on the device `deviceUID` (`device`) with Master Gain at `gain` dB.
    public mutating func enter(deviceUID: String, gain: Float, device: some DeviceVolumeControl) -> Entry {
        defer { keep() }
        if var held = loan, held.deviceUID == deviceUID {
            // Pure starts again on the device it already holds (a new song): the loan carries on — from a
            // change of the listener's, if they made one — unless Master Gain now asks for less than the
            // device can give (then Pure waits; Enhanced starting gives the hold back).
            if let reading = device.read(), abs(reading.level - held.lastSet) > Self.sameLevel {
                held = Self.reanchored(held, to: reading.level, gain: steeredGain)
                loan = held
            }
            guard Self.reaches(gain, anchor: held.anchor, ceiling: held.ceiling, on: device) else {
                return .waitsBelowDeviceRange
            }
            gainChanged(to: gain, device: device)
            return .engaged
        }
        if let other = loan {
            remember(other) // a device left without being put back: return it when it is seen
            loan = nil
        }
        returnLoan(of: deviceUID, device: device) // put back what an earlier session left, first
        guard let reading = device.read() else {
            return Self.isTurnedDown(gain) ? .waitsForMasterGain : .engaged
        }
        guard Self.reaches(gain, anchor: reading.level, ceiling: reading.level, on: device) else {
            return .waitsBelowDeviceRange // nothing touched: Enhanced plays the cut
        }
        loan = PureVolumeLoan(
            deviceUID: deviceUID, ceiling: reading.level, anchor: reading.level, lastSet: reading.level
        )
        gainChanged(to: gain, device: device)
        return .engaged
    }

    /// Whether Master Gain `gain` can be played on `device` from `anchor`: a level within its own range,
    /// or Silent on a device with a mute the app can set (H-1).
    private static func reaches(_ gain: Float, anchor: Float, ceiling: Float, on device: some DeviceVolumeControl)
        -> Bool {
        guard let reading = device.read() else { return true }
        return reachesByLevel(gain, anchor: anchor, ceiling: ceiling, range: reading.range)
            || (!isAudible(gain) && device.isMuted() != nil)
    }

    /// Whether Master Gain `gain` is a level within `range` from `anchor` (not Silent, not below the floor).
    private static func reachesByLevel(_ gain: Float, anchor: Float, ceiling: Float, range: ClosedRange<Float>)
        -> Bool {
        isAudible(gain) && min(anchor + min(gain, MasterGainLaw.unity), ceiling) >= range.lowerBound - sameLevel
    }

    /// Master Gain moved to `gain` while Pure plays: the device follows.
    public mutating func gainChanged(to gain: Float, device: some DeviceVolumeControl) {
        defer { keep() }
        guard var held = loan, let reading = device.read() else { return }
        // The device first: a change of the listener's that Pure hasn't been told of yet (its notice still
        // queued behind this move, or no notice at all) stands — the move is made from it, never over it
        // (R1.1-A close-out break-it, H-5: a 1 dB step had put a −45 dB volume-down back to −29 dB).
        if abs(reading.level - held.lastSet) > Self.sameLevel {
            held = Self.reanchored(held, to: reading.level, gain: steeredGain)
            loan = held
        }
        steeredGain = gain
        // Silent, or below the device's own floor: silence on a device with a mute — never louder than
        // Master Gain says (H-1). One without holds its floor (the next start waits).
        if !Self.reachesByLevel(gain, anchor: held.anchor, ceiling: held.ceiling, range: reading.range),
           device.isMuted() != nil {
            if device.isMuted() == false {
                held.mutedByPure = true // written ahead: a crash leaves the mute to give back
                loan = held
                keep()
                if !device.setMuted(true) {
                    held.mutedByPure = false
                    loan = held
                }
            }
            return
        }
        if held.mutedByPure, device.setMuted(false) { // back within range: the mute Pure made goes
            held.mutedByPure = false
            loan = held
        }
        let target = Self.level(anchor: held.anchor, ceiling: held.ceiling, gain: gain, range: reading.range)
        guard abs(target - reading.level) > Self.sameLevel else { return } // already there
        held.pending = target // written ahead: a crash before the read-back still names Pure's level
        loan = held
        keep()
        if device.set(target), let answer = device.read() {
            held.lastSet = answer.level
        }
        held.pending = nil
        loan = held
    }

    /// The device reports a change while Pure plays with Master Gain at `gain`. Pure's own set changes
    /// nothing; anything else is the listener's: their level stands, and the anchor follows it.
    public mutating func deviceChanged(gain: Float, device: some DeviceVolumeControl) {
        defer { keep() }
        guard let held = loan, let reading = device.read(),
              abs(reading.level - held.lastSet) > Self.sameLevel else { return }
        loan = Self.reanchored(held, to: reading.level, gain: gain)
    }

    /// `held` after the listener set the device to `reading` with Master Gain at `gain`: their level stands,
    /// read as the Mac's own volume with the cut on top — the anchor moves to it, never above the ceiling.
    private static func reanchored(_ held: PureVolumeLoan, to reading: Float, gain: Float) -> PureVolumeLoan {
        var moved = held
        let cut = isAudible(gain) ? min(gain, MasterGainLaw.unity) : MasterGainLaw.unity // Silent: none on top
        moved.anchor = min(reading - cut, held.ceiling)
        moved.lastSet = reading
        return moved
    }

    /// Whether `event` ends the hold Pure has on the device `heldUID`.
    public static func ends(_ event: PureVolumeEvent, heldOn heldUID: String) -> Bool {
        switch event {
        case .paused, .deviceLost: false
        case .stopped, .enhancedStarted: true
        case let .outputMoved(toUID): toUID != heldUID
        }
    }

    /// Apply `event`: when it ends Pure's hold, put the level back (`leave`) on the held device
    /// (`device(uid)`). And every loan not yet put back whose device is here again is put back too — a
    /// device lost mid-Pure and back in the same session gets its level back at the next transport event,
    /// not only at the next launch (H-3). True when the hold ended — the engine stops following the device.
    @discardableResult
    public mutating func handle<Device: DeviceVolumeControl>(_ event: PureVolumeEvent,
                                                             device: (String) -> Device) -> Bool {
        defer { returnUnreturned { device($0) } }
        guard let held = loan, Self.ends(event, heldOn: held.deviceUID) else { return false }
        leave(device: device(held.deviceUID))
        return true
    }

    /// Pure stops on its device: put the anchor back.
    public mutating func leave(device: some DeviceVolumeControl) {
        defer { keep() }
        guard let held = loan else { return }
        loan = nil
        if !settle(held, device: device) {
            remember(held)
        }
    }

    /// Put back every unreturned loan whose device is here (`device(uid)`, nil while it is absent).
    public mutating func returnUnreturned<Device: DeviceVolumeControl>(device: (String) -> Device?) {
        defer { keep() }
        unreturned = unreturned.filter { loan in
            guard let control = device(loan.deviceUID) else { return true }
            return !settle(loan, device: control)
        }
    }

    // MARK: - The rule's pieces

    /// The device level for Master Gain `gain`: the anchor lowered by it, within the device's range,
    /// never above the ceiling. Silent (−∞, or a bad value) is the device's minimum.
    static func level(anchor: Float, ceiling: Float, gain: Float, range: ClosedRange<Float>) -> Float {
        guard isAudible(gain) else { return range.lowerBound }
        let lowered = min(anchor + min(gain, MasterGainLaw.unity), ceiling)
        return min(max(lowered, range.lowerBound), range.upperBound)
    }

    /// Whether Master Gain is below 0 dB (NaN reads as a cut, the law's safe reading).
    static func isTurnedDown(_ gain: Float) -> Bool {
        !(gain >= MasterGainLaw.unity)
    }

    /// A level that plays: a number above −∞.
    private static func isAudible(_ gain: Float) -> Bool {
        gain > -.infinity
    }

    /// Put `held` back on `device`: true when it is settled — put back, the listener's level stands (the
    /// device reads something other than Pure's last set), or the record is damaged and nothing is touched.
    /// False when the device can't be read or set (it is gone): the loan stays out. What is put back is the
    /// anchor, never above the ceiling — the level Pure found — within the device's range; never a level
    /// that is not a number (SET-4).
    private func settle(_ held: PureVolumeLoan, device: some DeviceVolumeControl) -> Bool {
        guard held.isSound else { return true }
        guard let reading = device.read() else { return false }
        if held.mutedByPure, device.isMuted() == true { // the mute Pure made goes back with the volume
            _ = device.setMuted(false)
        }
        // Pure's own level: what it last set, or what it was setting when the app died (H-2).
        let pureSet = [held.lastSet] + (held.pending.map { [$0] } ?? [])
        guard reading.level.isFinite, pureSet.contains(where: { abs(reading.level - $0) <= Self.sameLevel }) else {
            return true
        }
        let target = min(max(min(held.anchor, held.ceiling), reading.range.lowerBound), reading.range.upperBound)
        guard target.isFinite else { return true }
        return abs(target - reading.level) <= Self.sameLevel || device.restore(target)
    }

    /// Put back an unreturned loan of `deviceUID`, if there is one, before a new one is taken.
    private mutating func returnLoan(of deviceUID: String, device: some DeviceVolumeControl) {
        unreturned = unreturned.filter { $0.deviceUID != deviceUID || !settle($0, device: device) }
    }

    /// Keep `held` until its device can take it back — one per device, the newest.
    private mutating func remember(_ held: PureVolumeLoan) {
        unreturned.removeAll { $0.deviceUID == held.deviceUID }
        unreturned.append(held)
    }
}
