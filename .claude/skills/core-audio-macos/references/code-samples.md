# Core Audio Code Samples (C/C++, macOS)

## Provenance rule (read first)

Every sample below is derived from an Apple primary source, named in its
"Source" line. When adapting or extending a sample, do not fill gaps from
model memory. Instead:

1. Fetch the cited Apple Documentation Archive page (archive pages are static
   HTML and fetchable; modern developer.apple.com/documentation pages are
   JS-rendered and will return nothing useful to a fetcher).
2. For the modern APIs not covered by archive documents, the canonical Apple
   documentation is the SDK header comments. Read them on the user's machine:
   `xcrun --show-sdk-path` then
   `$SDK/System/Library/Frameworks/CoreAudio.framework/Headers/AudioHardware.h`
   (also `AudioHardwareBase.h`, `AudioServerPlugIn.h`,
   `AudioToolbox/AUComponent.h`, `Accelerate/.../vDSP.h`).
3. Keep the `Source:` comment in any code you hand to the user so the
   provenance survives.

Primary sources used here:
- TN2091 "Device input using the HAL Output Audio Unit" —
  https://developer.apple.com/library/archive/technotes/tn2091/_index.html
- QA1811 "AudioServerPlugIn_MachServices" —
  https://developer.apple.com/library/archive/qa/qa1811/_index.html
- Core Audio Essentials (ASBD, audio unit concepts) —
  https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/CoreAudioEssentials/CoreAudioEssentials.html
- Apple sample code: CAPlayThrough, "Core Audio User-Space Driver Examples"
  (AudioDriverExamples) — linked from TN2091 / QA1811.
- macOS SDK headers (AudioHardware.h et al.) — Apple's reference docs for the
  AudioObject property API.

All samples compile with:

```
clang++ -std=c++17 file.cpp -framework CoreAudio -framework AudioToolbox -framework Accelerate
```

## Table of contents

- §1 The AudioObject property pattern (device enumeration)
- §2 Get / set the default output device
- §3 Listen for device changes
- §4 Opening an AUHAL output unit and registering a render callback
- §5 Device input with AUHAL (TN2091, steps 1–7)
- §6 DSP with vDSP (biquad, FFT) — header-verified pattern
- §7 Sample-rate / format conversion with AudioConverter
- §8 Real-time-safe communication patterns
- §9 AudioServerPlugIn (virtual device)

---

## §1 The AudioObject property pattern (device enumeration)

Source: `AudioHardware.h` header documentation (AudioObjectGetPropertyDataSize /
AudioObjectGetPropertyData on `kAudioObjectSystemObject` with
`kAudioHardwarePropertyDevices`). Note: TN2091 (2014) shows the older
`AudioHardwareGetProperty`, which `AudioHardware.h` marks deprecated; the
AudioObject functions below are its documented replacement. Verify constant
names against the local header before use.

```cpp
// Source: AudioHardware.h — kAudioHardwarePropertyDevices returns an array of
// AudioObjectIDs; size is variable, so query the size first.
#include <CoreAudio/CoreAudio.h>
#include <vector>

std::vector<AudioObjectID> copyAllDeviceIDs() {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDevices,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain   // pre-macOS 12 SDKs: ...ElementMaster
    };
    UInt32 dataSize = 0;
    OSStatus err = AudioObjectGetPropertyDataSize(kAudioObjectSystemObject,
                                                  &address, 0, NULL, &dataSize);
    if (err != noErr) return {};

    std::vector<AudioObjectID> devices(dataSize / sizeof(AudioObjectID));
    err = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address,
                                     0, NULL, &dataSize, devices.data());
    if (err != noErr) return {};
    devices.resize(dataSize / sizeof(AudioObjectID));
    return devices;
}

// Source: AudioHardwareBase.h — kAudioObjectPropertyName returns a CFStringRef
// the caller is responsible for releasing.
CFStringRef copyDeviceName(AudioObjectID device) {
    AudioObjectPropertyAddress address = {
        kAudioObjectPropertyName,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    CFStringRef name = NULL;
    UInt32 dataSize = sizeof(name);
    AudioObjectGetPropertyData(device, &address, 0, NULL, &dataSize, &name);
    return name;   // caller calls CFRelease(name)
}
```

To know whether a device does input or output, query
`kAudioDevicePropertyStreamConfiguration` with scope
`kAudioObjectPropertyScopeOutput` or `...ScopeInput` (per `AudioHardware.h`,
the property is scoped; the result is an `AudioBufferList` whose buffers'
`mNumberChannels` you sum).

## §2 Get / set the default output device

Source: `AudioHardware.h` — `kAudioHardwarePropertyDefaultOutputDevice`
(read/write `AudioObjectID` on the system object). TN2091 Listing 4 shows the
same operation for the default *input* device using the legacy call; below is
the header-documented modern form.

```cpp
// Source: AudioHardware.h, kAudioHardwarePropertyDefaultOutputDevice
AudioObjectID getDefaultOutputDevice() {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    AudioObjectID device = kAudioObjectUnknown;
    UInt32 dataSize = sizeof(device);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &address,
                               0, NULL, &dataSize, &device);
    return device;
}

OSStatus setDefaultOutputDevice(AudioObjectID device) {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &address,
                                      0, NULL, sizeof(device), &device);
}
```

A system-wide processor routes system audio into its virtual device with
`setDefaultOutputDevice`, while opening the physical device itself. Remember
the previous default and restore it on quit.

## §3 Listen for device changes

Source: `AudioHardware.h` — `AudioObjectAddPropertyListenerBlock`. The header
documents that the block is invoked on the supplied dispatch queue (not the
real-time thread), and listeners must be removed with
`AudioObjectRemovePropertyListenerBlock`.

```cpp
// Source: AudioHardware.h, AudioObjectAddPropertyListenerBlock
#include <dispatch/dispatch.h>

void watchDefaultOutputChanges() {
    AudioObjectPropertyAddress address = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMain
    };
    dispatch_queue_t queue = dispatch_queue_create("audio.listener", NULL);
    AudioObjectAddPropertyListenerBlock(
        kAudioObjectSystemObject, &address, queue,
        ^(UInt32 inNumberAddresses,
          const AudioObjectPropertyAddress* inAddresses) {
            // Runs on `queue` — safe to reconfigure audio units here.
            AudioObjectID newDevice = getDefaultOutputDevice();
            (void)newDevice;
        });
}
```

Other addresses documented for this use in `AudioHardware.h`:
`kAudioHardwarePropertyDevices` (device list changed) on the system object,
`kAudioDevicePropertyNominalSampleRate` on a device.

## §4 Opening an AUHAL output unit and registering a render callback

Source: TN2091, Listing 1 ("How to open an AudioOutputUnit 10.6 and later")
for the component lookup, reproduced in Apple's structure below; callback
registration per `AudioUnitProperties.h`
(`kAudioUnitProperty_SetRenderCallback`); the connection topology per TN2091
Table 1 — to output audio to a device, your source feeds "AUHAL (input scope,
element 0)".

```cpp
#include <AudioToolbox/AudioToolbox.h>

// Source: TN2091 Listing 1 — component lookup for the AUHAL.
AudioComponent comp;
AudioComponentDescription desc;
AudioComponentInstance auHAL;

//There are several different types of Audio Units.
//Some audio units serve as Outputs, Mixers, or DSP
//units. See AUComponent.h for listing
desc.componentType = kAudioUnitType_Output;

//Every Component has a subType, which will give a clearer picture
//of what this components function will be.
desc.componentSubType = kAudioUnitSubType_HALOutput;

//all Audio Units in AUComponent.h must use
//"kAudioUnitManufacturer_Apple" as the Manufacturer
desc.componentManufacturer = kAudioUnitManufacturer_Apple;
desc.componentFlags = 0;
desc.componentFlagsMask = 0;

//Finds a component that meets the desc spec's
comp = AudioComponentFindNext(NULL, &desc);
if (comp == NULL) exit (-1);

//gains access to the services provided by the component
AudioComponentInstanceNew(comp, &auHAL);
```

Registering a render callback so the AUHAL pulls audio from your application
(per TN2091 "A quick word on Audio Unit connections": when an audio unit gets
its data from your application, it invokes a callback function in your
application). The render proc signature is `AURenderCallback` from
`AUComponent.h`:

```cpp
// Source: AUComponent.h (AURenderCallback) +
// AudioUnitProperties.h (kAudioUnitProperty_SetRenderCallback).
static OSStatus RenderProc(void* inRefCon,
                           AudioUnitRenderActionFlags* ioActionFlags,
                           const AudioTimeStamp* inTimeStamp,
                           UInt32 inBusNumber,
                           UInt32 inNumberFrames,
                           AudioBufferList* ioData) {
    // Fill ioData->mBuffers[...] with inNumberFrames frames.
    // REAL-TIME THREAD: apply the rules in SKILL.md.
    return noErr;
}

void registerRenderCallback(AudioUnit unit, void* refCon) {
    AURenderCallbackStruct callback;
    callback.inputProc = RenderProc;
    callback.inputProcRefCon = refCon;
    AudioUnitSetProperty(unit,
                         kAudioUnitProperty_SetRenderCallback,
                         kAudioUnitScope_Input,
                         0,                 // element 0 = output, per TN2091
                         &callback, sizeof(callback));
}
```

Set your stream format on (input scope, element 0). Per TN2091 ("What about
the audio data format?"): for outputting data to an audio device the device
format is expressed on the output scope of Element 0 and is NEVER writeable —
you set your *client* format on the input scope and the AUHAL's built-in
AudioConverter handles the translation. The ASBD fields are documented in
Core Audio Essentials ("AudioStreamBasicDescription", CoreAudioTypes.h).
Then, per TN2091 Listing 8: `AudioUnitInitialize` followed by
`AudioOutputUnitStart`.

To address a specific device rather than the default, set
`kAudioOutputUnitProperty_CurrentDevice` (Global scope, element 0) — TN2091,
"Setting the current device of the AudioOutputUnit"; note its requirement that
devices can only be set on the AUHAL after enabling IO.

## §5 Device input with AUHAL (TN2091, steps 1–7)

Source: TN2091 in full. Apple's documented sequence: 1. Open an AUHAL,
2. Enable the AUHAL for input, 3. Set the input device as current device,
4. Obtain the device format and specify the desired format, 5. Create and
register the input callback, 6. Allocate buffers, 7. Initialize & start.

Step 2 — TN2091 Listing 3, reproduced (input is element 1, output element 0):

```cpp
UInt32 enableIO;

//When using AudioUnitSetProperty the 4th parameter in the method
//refer to an AudioUnitElement. When using an AudioOutputUnit
//the input element will be '1' and the output element will be '0'.

enableIO = 1;
AudioUnitSetProperty(InputUnit,
    kAudioOutputUnitProperty_EnableIO,
    kAudioUnitScope_Input,
    1, // input element
    &enableIO,
    sizeof(enableIO));

enableIO = 0;
AudioUnitSetProperty(InputUnit,
    kAudioOutputUnitProperty_EnableIO,
    kAudioUnitScope_Output,
    0,   //output element
    &enableIO,
    sizeof(enableIO));
```

Step 3 — TN2091 Listing 4 shows obtaining the default input device and setting
it via `kAudioOutputUnitProperty_CurrentDevice` (Global scope, element 0).
TN2091's `AudioHardwareGetProperty` call is deprecated per AudioHardware.h;
obtain the device with the §2 pattern using
`kAudioHardwarePropertyDefaultInputDevice`, then:

```cpp
// TN2091 Listing 4 (device assignment portion, unchanged):
err = AudioUnitSetProperty(InputUnit,
    kAudioOutputUnitProperty_CurrentDevice,
    kAudioUnitScope_Global,
    0,
    &inputDevice,
    sizeof(inputDevice));
```

Step 4 — per TN2091: for input, the device format is expressed on the input
scope of Element 1; you set your desired format on the *output scope of
Element 1*, matching the device's sample rate (the AUHAL's converter handles
any simple PCM variant, but not rate conversion). TN2091 Listing 5 reads the
device format with `AudioUnitGetProperty(..., kAudioUnitProperty_StreamFormat,
kAudioUnitScope_Input, 1, ...)`, copies `mSampleRate` into the desired format,
and sets it with `kAudioUnitScope_Output, 1`.

Step 5 — TN2091 Listing 7, reproduced:

```cpp
void MyInputCallbackSetup()
{
    AURenderCallbackStruct input;
    input.inputProc = InputProc;
    input.inputProcRefCon = 0;

    AudioUnitSetProperty(
        InputUnit,
        kAudioOutputUnitProperty_SetInputCallback,
        kAudioUnitScope_Global,
        0,
        &input,
        sizeof(input));
}
```

Steps 6–7 and acquiring data — TN2091 Listing 9: inside the input proc, call
`AudioUnitRender` propagating the proc's action flags, time stamp, bus number
(will be '1' for input data) and frame count, supplying your own allocated
`AudioBufferList` (the proc's `ioData` is NULL):

```cpp
AudioBufferList * theBufferList;
/* allocated to hold buffer data  */

OSStatus InputProc(
    void *inRefCon,
    AudioUnitRenderActionFlags *ioActionFlags,
    const AudioTimeStamp *inTimeStamp,
    UInt32 inBusNumber,
    UInt32 inNumberFrames,
    AudioBufferList * ioData)
{
    OSStatus err = noErr;

    err = AudioUnitRender(InputUnit,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,     //will be '1' for input data
        inNumberFrames,  //# of frames requested
        theBufferList);

    return err;
}
```

Allocate `theBufferList` at init time, sized for the device's maximum buffer
frame size (`kAudioDevicePropertyBufferFrameSizeRange`, AudioHardware.h) —
never allocate inside the proc. TN2091 also documents channel mapping
(`kAudioOutputUnitProperty_ChannelMap`, Listing 6) for non-1:1 channel
routing, and notes that connecting input to output of two different devices
requires two AUHALs with a buffering mechanism between them — Apple's
CAPlayThrough sample (linked from TN2091) demonstrates exactly that and is
the reference for play-through/processing apps.

Microphone capture triggers the TCC permission prompt; add
`NSMicrophoneUsageDescription` to the app's Info.plist.

## §6 DSP with vDSP (biquad, FFT) — header-verified pattern

Source: `vDSP.h` header documentation in the Accelerate framework, and the
vDSP Programming Guide (Documentation Archive). The function contracts below
must be verified against the local `vDSP.h` before shipping code — in
particular coefficient ordering and setup/teardown pairing.

Per `vDSP.h`: `vDSP_biquad_CreateSetup(coeffs, sections)` takes double
coefficients ordered b0, b1, b2, a1, a2 per section (normalized by a0) and is
NOT real-time safe (it allocates); `vDSP_biquad(setup, delays, in, 1, out, 1,
n)` is the per-buffer call, with a caller-owned delay array of 2*sections + 2
floats; destroy with `vDSP_biquad_DestroySetup`. Coefficient *design* (e.g.
peaking EQ from center frequency, gain, Q) is not part of Apple's API — use
the Audio EQ Cookbook (W3C-hosted; link in resources.md) and keep the design
math off the audio thread.

Per `vDSP.h` and the vDSP Programming Guide ("Performing Fourier Transforms"):
real FFT flow is `vDSP_create_fftsetup(log2n, kFFTRadix2)` at init,
`vDSP_ctoz` to pack real input into a `DSPSplitComplex`, `vDSP_fft_zrip` for
the in-place real FFT (packed output: DC in realp[0], Nyquist in imagp[0]),
`vDSP_zvmags` for magnitudes, `vDSP_destroy_fftsetup` at teardown. All
buffers and the setup are created at init time; the transform calls themselves
do not allocate.

When writing a concrete EQ/FFT implementation for the user, read the local
`vDSP.h` for exact signatures rather than reconstructing them, and cite the
header in the code comments.

## §7 Sample-rate / format conversion with AudioConverter

Source: `AudioConverter.h` (AudioToolbox) header documentation; concepts in
Core Audio Essentials ("Data Format Conversion", "AudioConverterRef").
TN2091 also documents the division of labor: the AUHAL's internal converter
handles simple PCM-variant conversion but NOT rate conversion — "If sample
rate conversion is needed, it can be accomplished by buffering the input and
converting the data on a separate thread with another AudioConverter."

Per `AudioConverter.h`: create with `AudioConverterNew(&inASBD, &outASBD,
&converter)`; same-rate, fixed-ratio conversions can use
`AudioConverterConvertBuffer`; rate conversion requires
`AudioConverterFillComplexBuffer` with an input data proc; dispose with
`AudioConverterDispose`. Creation allocates — init time only, never on the
audio thread. Quality is tunable via
`kAudioConverterSampleRateConverterQuality`.

## §8 Real-time-safe communication patterns

Source for the constraint itself: Apple's real-time context documentation —
`AudioServerPlugIn.h` documents that IO operations run in a real-time
constraint context, and TN2091's proc model implies the same for AUHAL procs.
The patterns below are standard real-time practice (see Ross Bencina's
article in resources.md) — they are not Apple listings, and should be
presented to users as such.

Parameters (UI → audio thread): a `std::atomic<float>` written by the UI and
read with `memory_order_relaxed` in the proc, smoothed per-sample to avoid
zipper noise.

Sample data across threads: a single-producer/single-consumer lock-free ring
buffer — pre-allocated, power-of-two capacity, acquire/release ordering on
the read/write indices, and drop-on-full rather than block. Apple's
CAPlayThrough sample (linked from TN2091) ships a `CARingBuffer` class in the
Core Audio Utility Classes that serves this exact purpose between two AUHALs;
prefer pointing users at that Apple-provided implementation, or the
well-tested open-source TPCircularBuffer, over hand-rolling one.

## §9 AudioServerPlugIn (virtual device)

Source: QA1811 and `AudioServerPlugIn.h`. A full driver is thousands of lines
of property-handling boilerplate; never write one from scratch — start from
Apple's current "Creating an Audio Server Driver Plug-in" sample, the
"Building an Audio Server Plug-in and Driver Extension" sample, or BlackHole /
Background Music (resources.md). (QA1811's "AudioDriverExamples" link is
retired.) Per Apple's WWDC21 guidance and Developer Forums responses,
AudioDriverKit entitlements are not granted for virtual devices —
AudioServerPlugIn is the required model for a virtual device.

Constraints, per QA1811 (quoting the documented rules in paraphrase):
- The plug-in may not call the client HAL API in CoreAudio.framework —
  undefined behavior.
- The host process is sandboxed: the plug-in may only read files in its own
  bundle plus system libraries/frameworks; no user documents; writes only to
  cache/temp directories derived through Apple API; persistent storage goes
  through the host-provided storage mechanism.
- IPC with other processes is allowed only for mach services listed in the
  bundle's Info.plist under `AudioServerPlugIn_MachServices`. QA1811's plist
  form:

```xml
<key>AudioServerPlugIn_MachServices</key>
<array>
    <string>com.yourcompanynamehere.audio.HypotheticalAudioDriverXPCService</string>
</array>
```

Per `AudioServerPlugIn.h`: the driver is a CFPlugIn bundle implementing the
COM-style `AudioServerPlugInDriverInterface` vtable — property functions
(`HasProperty`, `IsPropertySettable`, `GetPropertyDataSize`,
`GetPropertyData`, `SetPropertyData`) describing the plug-in/device/stream/
control object tree, plus the IO functions (`StartIO`, `StopIO`,
`GetZeroTimeStamp`, `WillDoIOOperation`, `BeginIOOperation`, `DoIOOperation`,
`EndIOOperation`). `DoIOOperation` runs in a real-time context — all
real-time rules apply. The loopback pattern used by virtual devices: store
frames in `DoIOOperation` for `kAudioServerPlugInIOOperationWriteMix`, return
them for `kAudioServerPlugInIOOperationReadInput`.

Install location is `/Library/Audio/Plug-Ins/HAL/`; reload during development
with `sudo killall coreaudiod` (briefly interrupts all system audio — warn the
user). Verify with Audio MIDI Setup or `system_profiler SPAudioDataType`;
check Console.app filtered on `coreaudiod` for load failures. Distribution
requires Developer ID signing and notarization. Read `AudioServerPlugIn.h` on
the user's machine for the authoritative interface before modifying driver
code.
