import CoreAudio
func addr(_ s: AudioObjectPropertySelector) -> AudioObjectPropertyAddress { AudioObjectPropertyAddress(mSelector: s, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain) }
for id: AudioObjectID in [82, 94, 109] {
    var a = addr(kAudioDevicePropertyMute); var settable: DarwinBoolean = false
    let has = AudioObjectHasProperty(id, &a); AudioObjectIsPropertySettable(id, &a, &settable)
    var v = addr(kAudioDevicePropertyVolumeScalar); let hasVol = AudioObjectHasProperty(id, &v)
    print("id=\(id) mute=\(has) settable=\(settable.boolValue) volume=\(hasVol)")
}
