// READ-ONLY HAL queries (no IO, no property writes): what the Pure policy's inputs look like on real devices.
import CoreAudio
import Foundation
func prop<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ v: inout T) -> Bool {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<T>.size)
    return AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr
}
func arr<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope, _ zero: T) -> [T] {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    var out = [T](repeating: zero, count: Int(size) / MemoryLayout<T>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &out) == noErr else { return [] }
    return out
}
func fourcc(_ v: UInt32) -> String { String(bytes: [24, 16, 8, 0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "\(v)" }
func desc(_ f: AudioStreamBasicDescription) -> String {
    let fl = f.mFormatFlags
    return "\(f.mSampleRate == 0 ? "any" : String(Int(f.mSampleRate))) \(f.mChannelsPerFrame)ch \(f.mBitsPerChannel)b/\(f.mBytesPerFrame / max(f.mChannelsPerFrame, 1))B " +
        "\(fl & kAudioFormatFlagIsFloat != 0 ? "float" : "int")\(fl & kAudioFormatFlagIsPacked != 0 ? " packed" : "")\(fl & kAudioFormatFlagIsAlignedHigh != 0 ? " hi" : "")\(fl & kAudioFormatFlagIsNonMixable != 0 ? " NONMIX" : "")"
}
let devices: [AudioObjectID] = arr(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, AudioObjectID(0))
for d in devices {
    let streams: [AudioObjectID] = arr(d, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, AudioObjectID(0))
    if streams.isEmpty { continue }
    var name: CFString = "" as CFString; _ = prop(d, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, &name)
    var transport: UInt32 = 0; _ = prop(d, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, &transport)
    var nominal: Float64 = 0; _ = prop(d, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, &nominal)
    let ranges: [AudioValueRange] = arr(d, kAudioDevicePropertyAvailableNominalSampleRates, kAudioObjectPropertyScopeOutput, AudioValueRange())
    var hog: pid_t = 0; _ = prop(d, kAudioDevicePropertyHogMode, kAudioObjectPropertyScopeGlobal, &hog)
    print("\(name) transport=\(fourcc(transport)) nominal=\(nominal) hog=\(hog) streams=\(streams.count) rates=\(ranges.map { $0.mMinimum == $0.mMaximum ? "\(Int($0.mMinimum))" : "[\(Int($0.mMinimum))-\(Int($0.mMaximum))]" })")
    for s in streams.prefix(2) {
        var phys = AudioStreamBasicDescription(); _ = prop(s, kAudioStreamPropertyPhysicalFormat, kAudioObjectPropertyScopeGlobal, &phys)
        var virt = AudioStreamBasicDescription(); _ = prop(s, kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal, &virt)
        let avail: [AudioStreamRangedDescription] = arr(s, kAudioStreamPropertyAvailablePhysicalFormats, kAudioObjectPropertyScopeGlobal, AudioStreamRangedDescription())
        print("   stream \(s): physical=\(desc(phys)) | virtual=\(desc(virt)) | \(avail.count) physical formats; at 44100/48000: " +
              avail.filter { [44100, 48000].contains(Int($0.mFormat.mSampleRate)) || $0.mFormat.mSampleRate == 0 }.map { desc($0.mFormat) + ($0.mFormat.mSampleRate == 0 ? " range[\(Int($0.mSampleRateRange.mMinimum))-\(Int($0.mSampleRateRange.mMaximum))]" : "") }.joined(separator: "; "))
    }
}
