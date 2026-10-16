@preconcurrency import AVFoundation
import CoreAudio
import EQEditKit
import Foundation

// MARK: - AudioEngineBridge Master Gain (S10.8 G, break-it G-GAIN-1; R1.1-A, C-29)

/// Master Gain on each path (founder decisions 2026-10-12, "Show the real level", and 2026-10-15,
/// "turn the Mac's volume down instead"):
///
/// - **Enhanced** — the app's own level, in dB (`masterGainDecibels`), plays as the player's
///   linear volume (`MasterGainLaw.linearGain`). The player applies it at the mixer's input
///   bus, after the DSP AUs (so after their limiter: turn-down only, it can't make an over). It
///   is applied whenever it is published, whenever a player is built, and at every Enhanced start.
/// - **Pure** — the bit-perfect stream is never scaled, so Master Gain turns the output device's own
///   volume down instead, by the same amount: the same loudness, the file untouched. The rule is
///   `MasterGainOnPure` (EQEditKit): entering Pure lowers the device from the level it found — or, on a
///   device with no volume the app can set, Pure waits while Master Gain is turned down; the slider
///   moves the device, never above that level; the listener's own change stands; leaving Pure puts
///   the level back. Pure's hold on the device lasts while Pure is its path, not only while a session
///   renders: a pause keeps it, a stop that ends playback, Enhanced starting or the output moving
///   leaves it (`pureVolumeEvent`, founder decision 2026-10-16) — and the device's volume is followed
///   for as long as it is held. The rule and every HAL call it makes live on `deviceVolumeQueue`
///   (never the main thread). `engineQueue` waits on it for the entry and the leaving, so the device
///   is lowered before Pure renders and put back once Pure has stopped. The loans not yet put back
///   ride in the snapshot, and the view model keeps them with the listener's settings (crash-safe).
extension AudioEngineBridge {
    // MARK: - Enhanced: the app's gain on the player

    /// Publish the app's Master Gain (dB). Hops onto `engineQueue`, so the player sees each value in
    /// the order the slider sent it (no per-tick `Task`s racing each other — S3 finding F4); on Pure the
    /// device follows (`steerPureVolume`).
    func publishMasterGain(decibels: Float) {
        engineQueue.async {
            self.masterGainDecibels = decibels
            self.applyMasterGain()
            self.steerPureVolume(gain: decibels)
        }
    }

    /// Set the player to the stored Master Gain. Runs on `engineQueue` (the player's owning domain).
    func applyMasterGain() {
        playerNode?.volume = MasterGainLaw.linearGain(decibels: masterGainDecibels)
    }

    // MARK: - Pure: the output device's own volume

    /// See `AudioPlaybackEngine.returnPureVolumeLoans`. Returns at once: the rule takes the loans in and
    /// puts back those whose devices are here, on `deviceVolumeQueue`.
    func returnPureVolumeLoans(_ loans: [PureVolumeLoan]) {
        deviceVolumeQueue.async {
            self.masterGainOnPure.adopt(loans)
            self.masterGainOnPure.returnUnreturned { HALDeviceVolume(uid: $0) }
            self.publishPureVolumeLoans()
        }
    }

    /// Take the device's volume for Pure, before Pure renders: lower it by Master Gain, or say that Pure
    /// waits (a device with no volume the app can set, Master Gain turned down). A hold still on another
    /// device (Pure moved, or a pause there) is given back first; the same device's hold — a resume, a
    /// new song — carries on untouched. Then the device is followed while the hold lasts. On
    /// `engineQueue`; the rule runs on `deviceVolumeQueue`.
    func enterPureVolume(deviceID: UInt32) -> MasterGainOnPure.Entry {
        let gain = masterGainDecibels
        let uid = Self.deviceUID(deviceID)
        let (entry, ended, held) = deviceVolumeQueue.sync {
            let ended = masterGainOnPure.handle(.outputMoved(toUID: uid)) { HALDeviceVolume(uid: $0) }
            pureGain = gain
            let entry = masterGainOnPure.enter(deviceUID: uid, gain: gain, device: HALDeviceVolume(deviceID: deviceID))
            publishPureVolumeLoans()
            return (entry, ended, masterGainOnPure.loan != nil)
        }
        if ended || !held {
            unwatchDeviceVolume()
        }
        if held {
            watchDeviceVolume(deviceID: deviceID)
        }
        return entry
    }

    /// A transport event that may end Pure's hold on the device's volume (`PureVolumeEvent`): when it
    /// does, the device gets its own level back and stops being followed. On `engineQueue`, after any
    /// render stopped; the rule runs on `deviceVolumeQueue`. A device that is gone keeps its loan.
    func pureVolumeEvent(_ event: PureVolumeEvent) {
        let ended = deviceVolumeQueue.sync {
            let ended = masterGainOnPure.handle(event) { HALDeviceVolume(uid: $0) }
            if ended {
                publishPureVolumeLoans()
            }
            return ended
        }
        if ended {
            unwatchDeviceVolume()
        }
    }

    /// Master Gain moved: on Pure the device follows. Latest value wins (the Realizer's pending-slot
    /// pattern): a drag stores its newest level and posts at most one drain, so a slow or dying device
    /// never builds a backlog of stale levels to replay. On `engineQueue`.
    private func steerPureVolume(gain: Float) {
        let post = withStateLock { () -> Bool in
            pendingPureGain = gain
            defer { pureGainDrainPosted = true }
            return !pureGainDrainPosted
        }
        guard post else { return }
        deviceVolumeQueue.async { self.drainPureGain() }
    }

    /// Apply the newest Master Gain to the Pure device until none is pending. On `deviceVolumeQueue`.
    private func drainPureGain() {
        while let gain = withStateLock({ () -> Float? in
            let level = pendingPureGain
            pendingPureGain = nil
            if level == nil {
                pureGainDrainPosted = false
            }
            return level
        }) {
            pureGain = gain
            guard let held = masterGainOnPure.loan else { continue }
            let device = HALDeviceVolume(uid: held.deviceUID)
            masterGainOnPure.gainChanged(to: gain, device: device)
            storeDeviceVolume(DeviceHardwareVolume.read(device.deviceID))
            publishPureVolumeLoans()
        }
    }

    /// Follow the volume of the device Pure holds, while the hold lasts — through a pause too, so the
    /// listener's own change is never undone. Idempotent for the device already followed; one watch at
    /// a time. On `engineQueue` (`enterPureVolume`).
    private func watchDeviceVolume(deviceID: UInt32) {
        let device = AudioObjectID(deviceID)
        guard withStateLock({ deviceVolumeWatch?.deviceID }) != device else { return }
        unwatchDeviceVolume()
        var address = DeviceHardwareVolume.scalarAddress
        // On `deviceVolumeQueue`, serialized with the rule — never the main queue: the read is a HAL
        // call, and the HAL announces volume changes while it tears a device down.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.deviceVolumeChanged(device)
        }
        let added = AudioObjectAddPropertyListenerBlock(device, &address, deviceVolumeQueue, block) == noErr
        if !added {
            // The slider still sets the device; only a change made elsewhere goes unseen.
            NSLog("[PureMode] could not follow the volume of device \(deviceID)")
        }
        withStateLock { deviceVolumeWatch = DeviceVolumeWatch(deviceID: device, listener: added ? block : nil) }
    }

    /// Stop following the device's volume. Idempotent: the watch is taken under the lock, so exactly
    /// one caller removes it. Removal passes the exact (device, address, queue, block) the add used (F5).
    func unwatchDeviceVolume() {
        let taken = withStateLock { () -> DeviceVolumeWatch? in
            let watch = deviceVolumeWatch
            deviceVolumeWatch = nil
            return watch
        }
        guard let watch = taken, let listener = watch.listener else { return }
        var address = DeviceHardwareVolume.scalarAddress
        AudioObjectRemovePropertyListenerBlock(watch.deviceID, &address, deviceVolumeQueue, listener)
    }

    /// The Pure device's volume changed (the listener, on `deviceVolumeQueue`): Pure's own set changes
    /// nothing; the listener's own change stands, and the rule re-anchors to it.
    private func deviceVolumeChanged(_ device: AudioObjectID) {
        masterGainOnPure.deviceChanged(gain: pureGain, device: HALDeviceVolume(deviceID: device))
        storeDeviceVolume(DeviceHardwareVolume.read(device))
        publishPureVolumeLoans()
    }

    /// Put a device reading into the snapshot — only while the path is Pure, so a late listener
    /// call after teardown can't paint a device volume onto Enhanced.
    private func storeDeviceVolume(_ volume: DeviceVolume) {
        mutateSignalPath { info in
            guard info.path == .pure else { return }
            info.deviceVolume = volume
        }
    }

    /// The loans not yet put back, for the snapshot (and so the listener's settings). On
    /// `deviceVolumeQueue`.
    private func publishPureVolumeLoans() {
        let loans = masterGainOnPure.allLoans
        withStateLock { publishedPureVolumeLoans = loans }
    }
}

// MARK: - Device volume watch

/// The device Pure plays on, whose volume Master Gain shows and sets, and the listener following it
/// (`nil` if CoreAudio refused it). Held under `stateLock`.
struct DeviceVolumeWatch {
    let deviceID: AudioObjectID
    let listener: AudioObjectPropertyListenerBlock?
}

// MARK: - The device's volume control

/// The output device's main volume control, in dB (CoreAudio `AudioHardware.h`: the device
/// properties "implemented via AudioControl objects"). Only the MAIN element is used: a device
/// whose volume exists only per channel reads as `.fixed`, its level set on the device. HAL calls:
/// on `deviceVolumeQueue` (or `engineQueue` at a Pure start), never the main thread.
enum DeviceHardwareVolume {
    /// The change notification to follow: every volume change moves the scalar.
    static var scalarAddress: AudioObjectPropertyAddress {
        address(kAudioDevicePropertyVolumeScalar)
    }

    /// The device's volume as it reads now: `.decibels` when it has a main output volume the app
    /// can set, else `.fixed`.
    static func read(_ device: AudioObjectID) -> DeviceVolume {
        reading(device).map { .decibels($0.level) } ?? .fixed
    }

    /// The device's level and settable range in dB, or nil when it has no main output volume the app
    /// can set (or it is gone).
    static func reading(_ device: AudioObjectID) -> DeviceVolumeReading? {
        var address = address(kAudioDevicePropertyVolumeDecibels)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return nil
        }
        var decibels: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &decibels) == noErr else { return nil }
        var rangeAddress = Self.address(kAudioDevicePropertyVolumeRangeDecibels)
        var range = AudioValueRange()
        size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(device, &rangeAddress, 0, nil, &size, &range) == noErr,
              range.mMinimum <= range.mMaximum else { return nil }
        return DeviceVolumeReading(level: decibels, range: Float(range.mMinimum) ... Float(range.mMaximum))
    }

    /// Set the device's volume, clamped to its own dB range and to 0 dB at most (turn-down only — the
    /// hearing-safety clamp); a level that is not a number sets nothing. The device takes the nearest
    /// value it can select. False when the device refused (or is gone).
    @discardableResult
    static func set(_ device: AudioObjectID, decibels: Float) -> Bool {
        guard let current = reading(device) else { return false }
        let ceiling = min(current.range.upperBound, MasterGainLaw.unity)
        var target = Float32(min(max(decibels, current.range.lowerBound), ceiling))
        guard target.isFinite else { return false }
        var address = address(kAudioDevicePropertyVolumeDecibels)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &target)
        if status != noErr {
            NSLog("[PureMode] device volume set failed (\(status))")
        }
        return status == noErr
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

// MARK: - The rule's seam, through the HAL

/// One device's own volume through the HAL (`DeviceHardwareVolume`): the seam `MasterGainOnPure` steers.
/// Used only on `deviceVolumeQueue`.
struct HALDeviceVolume: DeviceVolumeControl {
    let deviceID: AudioObjectID

    init(deviceID: UInt32) {
        self.deviceID = AudioObjectID(deviceID)
    }

    /// The device with this UID, as it is connected now (its id can change across a reconnect); one
    /// that isn't here reads as no volume, so its loan stays unreturned.
    init(uid: String) {
        deviceID = AudioEngineBridge.deviceID(forUID: uid) ?? AudioObjectID(kAudioObjectUnknown)
    }

    func read() -> DeviceVolumeReading? {
        DeviceHardwareVolume.reading(deviceID)
    }

    func set(_ decibels: Float) -> Bool {
        DeviceHardwareVolume.set(deviceID, decibels: decibels)
    }
}
