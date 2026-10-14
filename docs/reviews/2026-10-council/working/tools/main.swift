// gfc-silent-devices.swift — live-check helper for the Sprint G device fixes (NOT run by the agent).
// Two silent, default-capable outputs built over "Microsoft Teams Audio" (a loopback driver: silent),
// a way to make either the system default (what Control Center ▸ Sound does), and a way to delete
// one (what unplugging does). Teams Audio itself can't be the default (can-be-default = 0, measured),
// which is why the aggregates are needed for the Enhanced checks.
//
//   swift gfc-silent-devices.swift list
//   swift gfc-silent-devices.swift create            # makes "AS Silent A" and "AS Silent B"
//   swift gfc-silent-devices.swift default <name>    # e.g. default "AS Silent B" / "MacBook Pro Speakers"
//   swift gfc-silent-devices.swift destroy <A|B>     # "unplug" one
//
// Public aggregates persist until destroyed: run `destroy A` and `destroy B` when done.

import CoreAudio
import Foundation

let teamsUID = "MSLoopbackDriverDevice_UID"
let aggregates = ["A": "com.adaptivesound.gfc.silent-a", "B": "com.adaptivesound.gfc.silent-b"]

func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
    -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}

func devices() -> [AudioDeviceID] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size)
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids)
    return ids
}

func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String {
    var addr = address(selector)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let value else { return "?" }
    return value.takeRetainedValue() as String
}

func uint(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32? {
    var addr = address(selector, scope)
    var value: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
}

func defaultOutput() -> AudioDeviceID {
    uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
         kAudioObjectPropertyScopeGlobal) ?? 0
}

func find(uid: String) -> AudioDeviceID? { devices().first { string($0, kAudioDevicePropertyDeviceUID) == uid } }
func find(name: String) -> AudioDeviceID? { devices().first { string($0, kAudioObjectPropertyName) == name } }

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "list":
    let current = defaultOutput()
    for id in devices() {
        let canDefault = uint(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioObjectPropertyScopeOutput) ?? 0
        print("\(id == current ? "*" : " ") id=\(id) canDefault=\(canDefault) '\(string(id, kAudioObjectPropertyName))' "
            + "uid=\(string(id, kAudioDevicePropertyDeviceUID))")
    }
case "create":
    for (letter, uid) in aggregates.sorted(by: { $0.key < $1.key }) where find(uid: uid) == nil {
        let description: [String: Any] = [
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceNameKey: "AS Silent \(letter)",
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: teamsUID]],
            kAudioAggregateDeviceMainSubDeviceKey: teamsUID,
        ]
        var id: AudioObjectID = 0
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        print("create AS Silent \(letter): status=\(status) id=\(id)")
    }
case "default":
    guard let name = args.dropFirst().first, var id = find(name: name) else { print("no such device"); exit(1) }
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                            UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    print("default → '\(name)' id=\(id): status=\(status); now \(defaultOutput())")
case "defaultid":
    guard let raw = args.dropFirst().first, var id = AudioDeviceID(raw) else { print("usage: defaultid <id>"); exit(1) }
    var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
    let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                            UInt32(MemoryLayout<AudioDeviceID>.size), &id)
    print("default → id=\(id): status=\(status); now \(defaultOutput())")
case "destroy":
    guard let letter = args.dropFirst().first, let uid = aggregates[letter], let id = find(uid: uid) else {
        print("no such aggregate"); exit(1)
    }
    print("destroy AS Silent \(letter) id=\(id): status=\(AudioHardwareDestroyAggregateDevice(id))")
default:
    print("usage: list | create | default <name> | destroy <A|B>")
}
