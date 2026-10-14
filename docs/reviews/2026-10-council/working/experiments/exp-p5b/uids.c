#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
static UInt32 streams(AudioDeviceID d, AudioObjectPropertyScope s) {
    AudioObjectPropertyAddress a = {kAudioDevicePropertyStreams, s, kAudioObjectPropertyElementMain};
    UInt32 size = 0; AudioObjectGetPropertyDataSize(d, &a, 0, NULL, &size); return size / sizeof(AudioStreamID);
}
int main(void) {
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0; AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size);
    AudioDeviceID *ids = malloc(size); AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, ids);
    for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); ++i) {
        CFStringRef name = NULL, uid = NULL; UInt32 s = sizeof(CFStringRef);
        AudioObjectPropertyAddress n = {kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioObjectGetPropertyData(ids[i], &n, 0, NULL, &s, &name); s = sizeof(CFStringRef);
        AudioObjectPropertyAddress u = {kAudioDevicePropertyDeviceUID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioObjectGetPropertyData(ids[i], &u, 0, NULL, &s, &uid);
        char nb[128] = "", ub[256] = ""; if (name) CFStringGetCString(name, nb, sizeof nb, kCFStringEncodingUTF8); if (uid) CFStringGetCString(uid, ub, sizeof ub, kCFStringEncodingUTF8);
        // TranslateUIDToDevice back
        AudioObjectPropertyAddress t = {kAudioHardwarePropertyTranslateUIDToDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioDeviceID back = 0; UInt32 bs = sizeof back;
        AudioObjectGetPropertyData(kAudioObjectSystemObject, &t, sizeof(CFStringRef), &uid, &bs, &back);
        printf("id=%-4u %-28s out-streams=%u in-streams=%u uid=%s → translates to id %u\n", ids[i], nb, streams(ids[i], kAudioObjectPropertyScopeOutput), streams(ids[i], kAudioObjectPropertyScopeInput), ub, back);
    }
    return 0;
}
