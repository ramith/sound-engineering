// READ-ONLY: presentation latency per output device, Cog's formula (DeviceOutput.swift:1269-1287).
import CoreAudio
import Foundation
func u32(_ o: AudioObjectID, _ s: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32 {
    var a = AudioObjectPropertyAddress(mSelector: s, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var v: UInt32 = 0; var size = UInt32(4); _ = AudioObjectGetPropertyData(o, &a, 0, nil, &size, &v); return v
}
var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
var size: UInt32 = 0; AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4); AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
for d in ids {
    var sa = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    var ss: UInt32 = 0; AudioObjectGetPropertyDataSize(d, &sa, 0, nil, &ss); if ss == 0 { continue }
    var streams = [AudioObjectID](repeating: 0, count: Int(ss) / 4); AudioObjectGetPropertyData(d, &sa, 0, nil, &ss, &streams)
    var na = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var name: CFString = "" as CFString; var ns = UInt32(MemoryLayout<CFString>.size); AudioObjectGetPropertyData(d, &na, 0, nil, &ns, &name)
    var ra = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyNominalSampleRate, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var rate: Float64 = 0; var rs = UInt32(8); AudioObjectGetPropertyData(d, &ra, 0, nil, &rs, &rate)
    let lat = u32(d, kAudioDevicePropertyLatency, kAudioDevicePropertyScopeOutput), so = u32(d, kAudioDevicePropertySafetyOffset, kAudioDevicePropertyScopeOutput)
    let buf = u32(d, kAudioDevicePropertyBufferFrameSize, kAudioDevicePropertyScopeOutput), sl = u32(streams[0], kAudioStreamPropertyLatency, kAudioObjectPropertyScopeGlobal)
    let total = lat + so + buf + sl
    print("\(name): device \(lat) + safety \(so) + buffer \(buf) + stream \(sl) = \(total) frames = \(String(format: "%.1f", Double(total) / rate * 1000)) ms @ \(Int(rate))")
}
