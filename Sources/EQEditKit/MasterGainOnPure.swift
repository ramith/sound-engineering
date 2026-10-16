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
// - CRASH-SAFE: every loan not yet settled (`allLoans`) is kept with the listener's settings. A loan a
//   device couldn't take back (it went away) or that a crash left is put back when the device is seen
//   again (`returnUnreturned`, at launch) — by the same rule: only if it still reads what Pure set.
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
    /// Set the level, in dB within the device's range. False when the device refused or is gone.
    func set(_ decibels: Float) -> Bool
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

    public init(deviceUID: String, ceiling: Float, anchor: Float, lastSet: Float) {
        self.deviceUID = deviceUID
        self.ceiling = ceiling
        self.anchor = anchor
        self.lastSet = lastSet
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
    }

    /// Two readings this close are the same level (a device's read-back is exact; this absorbs float noise).
    static let sameLevel: Float = 0.05

    /// The loan of the device Pure plays on, or nil (off Pure, or a device with no volume to steer).
    public private(set) var loan: PureVolumeLoan?
    /// Loans not yet put back: the device went away first, or a crash left them.
    public private(set) var unreturned: [PureVolumeLoan]

    /// Every loan not yet settled — what the listener's settings keep.
    public var allLoans: [PureVolumeLoan] {
        (loan.map { [$0] } ?? []) + unreturned
    }

    /// Start with the loans a previous run left (`allLoans`, as kept): all unreturned until put back.
    public init(unreturned: [PureVolumeLoan] = []) {
        self.unreturned = unreturned
    }

    /// Take in loans a previous run left (kept with the listener's settings) as unreturned — except
    /// for a device whose loan is held or already kept: what this run knows is newer.
    public mutating func adopt(_ kept: [PureVolumeLoan]) {
        for kept in kept where !allLoans.contains(where: { $0.deviceUID == kept.deviceUID }) {
            unreturned.append(kept)
        }
    }

    /// Pure is about to play on the device `deviceUID` (`device`) with Master Gain at `gain` dB.
    public mutating func enter(deviceUID: String, gain: Float, device: some DeviceVolumeControl) -> Entry {
        if let held = loan, held.deviceUID == deviceUID {
            // Pure starts again on the device it already holds (a new song): the loan carries on.
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
        loan = PureVolumeLoan(
            deviceUID: deviceUID, ceiling: reading.level, anchor: reading.level, lastSet: reading.level
        )
        gainChanged(to: gain, device: device)
        return .engaged
    }

    /// Master Gain moved to `gain` while Pure plays: the device follows.
    public mutating func gainChanged(to gain: Float, device: some DeviceVolumeControl) {
        guard var held = loan, let reading = device.read() else { return }
        let target = Self.level(anchor: held.anchor, ceiling: held.ceiling, gain: gain, range: reading.range)
        guard abs(target - reading.level) > Self.sameLevel else { return } // already there
        if device.set(target), let answer = device.read() {
            held.lastSet = answer.level
            loan = held
        }
    }

    /// The device reports a change while Pure plays with Master Gain at `gain`. Pure's own set changes
    /// nothing; anything else is the listener's: their level stands, and the anchor follows it.
    public mutating func deviceChanged(gain: Float, device: some DeviceVolumeControl) {
        guard var held = loan, let reading = device.read(),
              abs(reading.level - held.lastSet) > Self.sameLevel else { return }
        let gain = Self.isAudible(gain) ? gain : MasterGainLaw.unity // Silent: no cut to keep on top
        held.anchor = min(reading.level - min(gain, MasterGainLaw.unity), held.ceiling)
        held.lastSet = reading.level
        loan = held
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
    /// (`device(uid)`). True when the hold ended — the engine stops following the device then.
    @discardableResult
    public mutating func handle<Device: DeviceVolumeControl>(_ event: PureVolumeEvent,
                                                             device: (String) -> Device) -> Bool {
        guard let held = loan, Self.ends(event, heldOn: held.deviceUID) else { return false }
        leave(device: device(held.deviceUID))
        return true
    }

    /// Pure stops on its device: put the anchor back.
    public mutating func leave(device: some DeviceVolumeControl) {
        guard let held = loan else { return }
        loan = nil
        if !settle(held, device: device) {
            remember(held)
        }
    }

    /// Put back every unreturned loan whose device is here (`device(uid)`, nil while it is absent).
    public mutating func returnUnreturned<Device: DeviceVolumeControl>(device: (String) -> Device?) {
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

    /// Put `held` back on `device`: true when it is settled — put back, or the listener's level stands
    /// (the device reads something other than Pure's last set). False when the device can't be read or
    /// set (it is gone): the loan stays out.
    private func settle(_ held: PureVolumeLoan, device: some DeviceVolumeControl) -> Bool {
        guard let reading = device.read() else { return false }
        guard abs(reading.level - held.lastSet) <= Self.sameLevel else { return true }
        let target = min(max(held.anchor, reading.range.lowerBound), reading.range.upperBound)
        return abs(target - reading.level) <= Self.sameLevel || device.set(target)
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
