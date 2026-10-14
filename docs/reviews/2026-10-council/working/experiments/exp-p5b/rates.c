#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
int main(void) {
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0; AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size);
    AudioDeviceID *ids = malloc(size); AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, ids);
    for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); ++i) {
        CFStringRef name = NULL; UInt32 s = sizeof(name);
        AudioObjectPropertyAddress n = {kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioObjectGetPropertyData(ids[i], &n, 0, NULL, &s, &name);
        char buf[256] = ""; if (name) CFStringGetCString(name, buf, sizeof buf, kCFStringEncodingUTF8);
        UInt32 transport = 0; s = sizeof transport;
        AudioObjectPropertyAddress t = {kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioObjectGetPropertyData(ids[i], &t, 0, NULL, &s, &transport);
        AudioObjectPropertyAddress r = {kAudioDevicePropertyAvailableNominalSampleRates, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        UInt32 rs = 0; AudioObjectGetPropertyDataSize(ids[i], &r, 0, NULL, &rs);
        AudioValueRange *ranges = malloc(rs ? rs : 1); AudioObjectGetPropertyData(ids[i], &r, 0, NULL, &rs, ranges);
        printf("%-40s transport=%c%c%c%c ranges:", buf, (char)(transport>>24), (char)(transport>>16), (char)(transport>>8), (char)transport);
        for (UInt32 k = 0; k < rs / sizeof(AudioValueRange); ++k) printf(" [%g-%g]", ranges[k].mMinimum, ranges[k].mMaximum);
        printf("\n");
    }
    return 0;
}
