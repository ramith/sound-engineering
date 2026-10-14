#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
static void desc(const char* tag, AudioStreamBasicDescription f) {
    printf("    %s %g Hz %s%s %u-bit ch=%u\n", tag, f.mSampleRate, (f.mFormatFlags & kAudioFormatFlagIsFloat) ? "float" : "int",
           (f.mFormatID == kAudioFormatLinearPCM) ? "" : "(non-PCM)", f.mBitsPerChannel, f.mChannelsPerFrame);
}
int main(void) {
    AudioObjectPropertyAddress a = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0; AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &a, 0, NULL, &size);
    AudioDeviceID *ids = malloc(size); AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &size, ids);
    for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); ++i) {
        CFStringRef name = NULL; UInt32 s = sizeof(name);
        AudioObjectPropertyAddress n = {kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioObjectGetPropertyData(ids[i], &n, 0, NULL, &s, &name);
        char buf[256] = ""; if (name) CFStringGetCString(name, buf, sizeof buf, kCFStringEncodingUTF8);
        AudioObjectPropertyAddress st = {kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
        UInt32 ss = 0; if (AudioObjectGetPropertyDataSize(ids[i], &st, 0, NULL, &ss) || ss == 0) continue;
        AudioStreamID *streams = malloc(ss); AudioObjectGetPropertyData(ids[i], &st, 0, NULL, &ss, streams);
        printf("%s\n", buf);
        AudioObjectPropertyAddress pf = {kAudioStreamPropertyPhysicalFormat, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        AudioStreamBasicDescription cur; UInt32 cs = sizeof cur;
        if (!AudioObjectGetPropertyData(streams[0], &pf, 0, NULL, &cs, &cur)) desc("CURRENT", cur);
        AudioObjectPropertyAddress av = {kAudioStreamPropertyAvailablePhysicalFormats, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        UInt32 as = 0; AudioObjectGetPropertyDataSize(streams[0], &av, 0, NULL, &as);
        AudioStreamRangedDescription *r = malloc(as ? as : 1); AudioObjectGetPropertyData(streams[0], &av, 0, NULL, &as, r);
        for (UInt32 k = 0; k < as / sizeof *r && k < 12; ++k) desc("avail  ", r[k].mFormat);
    }
    return 0;
}
