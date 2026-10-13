@preconcurrency import AVFoundation
import CoreAudio
import EQEditKit
import Foundation

// MARK: - AudioEngineBridge Master Gain (S10.8 G, break-it G-GAIN-1)

/// Master Gain on each path (founder decision 2026-10-12, "Show the real level"):
///
/// - **Enhanced** — the app's own level, in dB (`masterGainDecibels`), plays as the player's
///   linear volume (`MasterGainLaw.linearGain`). The player applies it at the mixer's input
///   bus, after the DSP AUs (so after their limiter: turn-down only, it can't make an over). It
///   is applied whenever it is published, whenever a player is built, and at every Enhanced start.
/// - **Pure** — the bit-perfect stream is never scaled. The one gain on that path is the output
///   device's own volume, which Master Gain shows and sets there: read when Pure starts (never
///   written — engaging Pure must not change how loud the device is), kept current by a listener on
///   the device (the volume keys and the menu bar move it too), and set only when the user moves
///   the slider.
extension AudioEngineBridge {
    // MARK: - Enhanced: the app's gain on the player

    /// Publish the app's Master Gain (dB). Hops onto `engineQueue`, so the player sees each value in
    /// the order the slider sent it (no per-tick `Task`s racing each other — S3 finding F4).
    func publishMasterGain(decibels: Float) {
        engineQueue.async {
            self.masterGainDecibels = decibels
            self.applyMasterGain()
        }
    }

    /// Set the player to the stored Master Gain. Runs on `engineQueue` (the player's owning domain).
    func applyMasterGain() {
        playerNode?.volume = MasterGainLaw.linearGain(decibels: masterGainDecibels)
    }

    // MARK: - Pure: the output device's own volume

    /// See `AudioPlaybackEngine.requestDeviceVolume`. Returns at once: the set and its read-back run
    /// on `deviceVolumeQueue` — HAL calls, which can wait while macOS reconfigures a device, never on
    /// the main thread. The device's volume listener runs on that queue too, so a listener read can
    /// never land between this write and its read-back and leave an older level in the snapshot.
    func requestDeviceVolume(decibels: Float) {
        deviceVolumeQueue.async {
            guard let device = self.withStateLock({ self.deviceVolumeWatch?.deviceID }) else { return }
            DeviceHardwareVolume.set(device, decibels: decibels)
            let volume = DeviceHardwareVolume.read(device)
            self.storeDeviceVolume(volume, answering: decibels)
        }
    }

    /// Read the volume of the device Pure has just started on and begin following it. Called by
    /// `startPure` (engineQueue) once the session runs; the reading goes into the snapshot that
    /// turns the path Pure, so the view never sees Pure without its level.
    func watchDeviceVolume(deviceID: UInt32) -> DeviceVolume {
        unwatchDeviceVolume() // one watch at a time (a Pure restart re-registers)
        let device = AudioObjectID(deviceID)
        var address = DeviceHardwareVolume.scalarAddress
        // On `deviceVolumeQueue`, serialized with `requestDeviceVolume` — never the main queue: the
        // read is a HAL call, and the HAL announces volume changes while it tears a device down.
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.storeDeviceVolume(DeviceHardwareVolume.read(device))
        }
        let added = AudioObjectAddPropertyListenerBlock(device, &address, deviceVolumeQueue, block) == noErr
        if !added {
            // The slider still sets the device; only a change made elsewhere goes unseen.
            NSLog("[PureMode] could not follow the volume of device \(deviceID)")
        }
        withStateLock { deviceVolumeWatch = DeviceVolumeWatch(deviceID: device, listener: added ? block : nil) }
        return DeviceHardwareVolume.read(device)
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

    /// Put a device reading into the snapshot — only while the path is Pure, so a late listener
    /// call after teardown can't paint a device volume onto Enhanced. A reading taken right after the
    /// user set `answering` dB is recorded as that request's answer (`deviceVolumeSet`).
    private func storeDeviceVolume(_ volume: DeviceVolume, answering decibels: Float? = nil) {
        mutateSignalPath { info in
            guard info.path == .pure else { return }
            info.deviceVolume = volume
            if let decibels {
                info.deviceVolumeSet = DeviceVolumeRequest(decibels: decibels, answer: volume)
            }
        }
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
/// whose volume exists only per channel reads as `.fixed`, its level set on the device.
enum DeviceHardwareVolume {
    /// The change notification to follow: every volume change moves the scalar.
    static var scalarAddress: AudioObjectPropertyAddress {
        address(kAudioDevicePropertyVolumeScalar)
    }

    /// The device's volume as it reads now: `.decibels` when it has a main output volume the app
    /// can set, else `.fixed`.
    static func read(_ device: AudioObjectID) -> DeviceVolume {
        var address = address(kAudioDevicePropertyVolumeDecibels)
        guard AudioObjectHasProperty(device, &address) else { return .fixed }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
            return .fixed
        }
        var decibels: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &decibels) == noErr else {
            return .fixed
        }
        return .decibels(decibels)
    }

    /// Set the device's volume, clamped to its own dB range and to 0 dB at most (turn-down only);
    /// silence (−∞) is its minimum. The device takes the nearest value it can select.
    static func set(_ device: AudioObjectID, decibels: Float) {
        var rangeAddress = address(kAudioDevicePropertyVolumeRangeDecibels)
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        guard AudioObjectGetPropertyData(device, &rangeAddress, 0, nil, &size, &range) == noErr else { return }
        let ceiling = min(Float(range.mMaximum), MasterGainLaw.unity)
        var target = Float32(min(max(decibels, Float(range.mMinimum)), ceiling))
        guard target.isFinite else { return }
        var address = address(kAudioDevicePropertyVolumeDecibels)
        let status = AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &target)
        if status != noErr {
            NSLog("[PureMode] device volume set failed (\(status))")
        }
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}
