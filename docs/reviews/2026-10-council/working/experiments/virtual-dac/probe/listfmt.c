// Read-only: list output devices, transport, nominal rates, and every output stream's
// current/available physical + virtual formats. Never starts IO, never sets a property.
#include <CoreAudio/CoreAudio.h>
#include <stdio.h>
#include <stdlib.h>
static void fcc(UInt32 v, char *o){o[0]='\'';for(int i=0;i<4;i++){char c=(char)((v>>(24-8*i))&0xff);o[1+i]=(c>=32&&c<127)?c:'?';}o[5]='\'';o[6]=0;}
static void pasbd(const char*lbl,const AudioStreamBasicDescription*a,double mn,double mx){
  UInt32 f=a->mFormatFlags; char id[8]; fcc(a->mFormatID,id);
  printf("    %-6s %s rate=%.0f [%.0f..%.0f] ch=%u bits=%u B/frame=%u %s%s%s%s%s%s\n",lbl,id,a->mSampleRate,mn,mx,a->mChannelsPerFrame,a->mBitsPerChannel,a->mBytesPerFrame,
    (f&kAudioFormatFlagIsFloat)?"float ":"", (f&kAudioFormatFlagIsSignedInteger)?"sint ":"", (f&kAudioFormatFlagIsPacked)?"packed ":"",
    (f&kAudioFormatFlagIsAlignedHigh)?"alignedHigh ":"", (f&kAudioFormatFlagIsNonInterleaved)?"nonInterleaved ":"", (f&kAudioFormatFlagIsNonMixable)?"NONMIXABLE ":"");
}
int main(void){
  AudioObjectPropertyAddress a={kAudioHardwarePropertyDevices,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
  UInt32 sz=0; AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,&a,0,NULL,&sz);
  UInt32 n=sz/sizeof(AudioDeviceID); AudioDeviceID *d=malloc(sz); AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&sz,d);
  for(UInt32 i=0;i<n;i++){
    AudioObjectPropertyAddress sa={kAudioDevicePropertyStreams,kAudioObjectPropertyScopeOutput,kAudioObjectPropertyElementMain};
    UInt32 ssz=0; if(AudioObjectGetPropertyDataSize(d[i],&sa,0,NULL,&ssz)||ssz==0) continue;
    CFStringRef nm=NULL; UInt32 s=sizeof(nm); AudioObjectPropertyAddress na={kAudioObjectPropertyName,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    AudioObjectGetPropertyData(d[i],&na,0,NULL,&s,&nm); char name[256]="?"; if(nm){CFStringGetCString(nm,name,sizeof name,kCFStringEncodingUTF8);CFRelease(nm);}
    UInt32 tt=0; s=sizeof tt; AudioObjectPropertyAddress ta={kAudioDevicePropertyTransportType,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain}; AudioObjectGetPropertyData(d[i],&ta,0,NULL,&s,&tt);
    Float64 r=0; s=sizeof r; AudioObjectPropertyAddress ra={kAudioDevicePropertyNominalSampleRate,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain}; AudioObjectGetPropertyData(d[i],&ra,0,NULL,&s,&r);
    pid_t hog=0; s=sizeof hog; AudioObjectPropertyAddress ha={kAudioDevicePropertyHogMode,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain}; OSStatus hs=AudioObjectGetPropertyData(d[i],&ha,0,NULL,&s,&hog);
    UInt32 bf=0; s=sizeof bf; AudioObjectPropertyAddress ba={kAudioDevicePropertyBufferFrameSize,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain}; AudioObjectGetPropertyData(d[i],&ba,0,NULL,&s,&bf);
    char t[8]; fcc(tt,t); printf("DEVICE %u '%s' transport=%s nominal=%.0f hog=%d(st=%d) bufFrames=%u\n",d[i],name,t,r,hog,(int)hs,bf);
    AudioObjectPropertyAddress ar={kAudioDevicePropertyAvailableNominalSampleRates,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
    UInt32 rsz=0; AudioObjectGetPropertyDataSize(d[i],&ar,0,NULL,&rsz); AudioValueRange *rr=malloc(rsz?rsz:1); AudioObjectGetPropertyData(d[i],&ar,0,NULL,&rsz,rr);
    printf("  rates:"); for(UInt32 k=0;k<rsz/sizeof(AudioValueRange);k++) printf(" %.0f%s",rr[k].mMinimum, rr[k].mMinimum==rr[k].mMaximum?"":"..range"); printf("\n"); free(rr);
    AudioStreamID *st=malloc(ssz); AudioObjectGetPropertyData(d[i],&sa,0,NULL,&ssz,st);
    for(UInt32 k=0;k<ssz/sizeof(AudioStreamID);k++){
      printf("  STREAM %u\n",st[k]);
      AudioStreamBasicDescription cur; s=sizeof cur;
      AudioObjectPropertyAddress pa={kAudioStreamPropertyPhysicalFormat,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain};
      if(!AudioObjectGetPropertyData(st[k],&pa,0,NULL,&s,&cur)) pasbd("CURphy",&cur,0,0);
      pa.mSelector=kAudioStreamPropertyVirtualFormat; s=sizeof cur; if(!AudioObjectGetPropertyData(st[k],&pa,0,NULL,&s,&cur)) pasbd("CURvir",&cur,0,0);
      for(int which=0;which<2;which++){
        pa.mSelector= which? kAudioStreamPropertyAvailableVirtualFormats: kAudioStreamPropertyAvailablePhysicalFormats;
        UInt32 fsz=0; if(AudioObjectGetPropertyDataSize(st[k],&pa,0,NULL,&fsz)) continue;
        AudioStreamRangedDescription *f=malloc(fsz?fsz:1); AudioObjectGetPropertyData(st[k],&pa,0,NULL,&fsz,f);
        for(UInt32 j=0;j<fsz/sizeof(*f);j++) pasbd(which?"avVIR":"avPHY",&f[j].mFormat,f[j].mSampleRateRange.mMinimum,f[j].mSampleRateRange.mMaximum);
        free(f);
      }
    }
    free(st);
  }
  return 0;
}
