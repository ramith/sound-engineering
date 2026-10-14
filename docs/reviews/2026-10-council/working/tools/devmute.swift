import CoreAudio
import Foundation
// devmute <deviceID> <0|1>  |  devmute <deviceID>  (read)
let args = CommandLine.arguments
var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
let id = AudioObjectID(args[1])!
if args.count > 2 { var v = UInt32(args[2])!; let s = AudioObjectSetPropertyData(id, &a, 0, nil, 4, &v); print("set id=\(id) mute=\(v) status=\(s)") }
var r: UInt32 = 0; var size = UInt32(4); AudioObjectGetPropertyData(id, &a, 0, nil, &size, &r); print("id=\(id) mute=\(r)")
