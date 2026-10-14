# Player engine evidence notes (2026-10-14)
## Local
- Music.app (macOS 26, /System/Applications/Music.app): otool -L lines 2 (AVFoundationCF), 18 AVFoundation, 21 AudioUnit, 22 AudioToolbox, 42 MediaToolbox, 43 CoreAudio, 64 MediaPlaybackCore(weak), 79 AVFAudio. nm -u: OBJC_CLASS_$_MPCPlaybackEngine, MPCQueueController, AVPlayerItem, AVURLAsset. dyld_info -imports MediaPlaybackCore: AVQueuePlayer, AVPlayer, AVPlayerItem (from AVFoundation).
- VLC 3.0.23 installed: MacOS/plugins/libauhal_plugin.dylib (AUHAL output).
## Cog (losnoco/Cog main, last commit 2026-10-07)
- Audio/Engine/Output/DeviceOutput.swift:14-15 "The device side of the engine: an AUHAL output unit whose render callback pulls from a CogRenderer." :39-42 hog mode + IOProc.
- 72210c67e4 2022-01-11 "Replaced AudioQueue output with AUAudioUnit"
- dccb7f8b47 2022-06-23 "Replace Core Audio output with Core Media runtime" -> "The output now uses AVSampleBufferAudioRenderer to play all formats"; Spatial Audio bug FB10441301 (192k stereo limit) broke DSD64
- 7ab2a8305a 2023-10-02 "Revert to previous low latency output system" "reverts usage of the AVFoundation output ... Fixes several issues with playback and seeking latency."
- 9c05d60d63 2026-09-30 "Render through the C AudioUnit API" (not AUAudioUnit; 55-68 ms gaps from ObjC lock)
- Plugins: FFMPEG, CoreAudio, Flac, Vorbis, Opus, WavPack, minimp3, Musepack, ... gapless commits (ed882e25cb etc.)
## IINA
- README "IINA uses mpv for media playback."
- iina/MPVController.swift:577-579 ao = avfoundation if pref else coreaudio; Preference.swift:1161 audioDriverEnableAVFoundation: false (default coreaudio); :1178 gaplessAudio weak
- mpv DOCS/man/ao.rst:121-123 coreaudio "using AudioUnits and the CoreAudio sound server"; 147-149 coreaudio_exclusive; 151-153 avfoundation AVSampleBufferAudioRenderer
## SFBAudioEngine
- README: "SFBAudioPlayer uses an AVAudioEngine processing graph driven by AVAudioSourceNode for playback."
## Doppler
- brushedtype.co/docs/doppler/gapless-playback: "Doppler will play songs without a gap between them, but it does not remove silences."
- supported-file-types: MP3,WAV,FLAC,ALAC,AAC,AIF,M4A; "Newer versions of iOS and macOS may support additional formats not listed here." (implies system decoders)
- change-speakers: Mac BT/headphones "you will need to select this from your Mac's audio settings"; in-app AirPlay button. Engine UNVERIFIED.
## Swinsian
- swinsian.com: formats list incl DSF, APE, WMA, Opus; "Gapless playback"; "Automatic changing of device sample rate"
- changelog_3.0.0_609: build 590 "Adds support for audio device 'hog' mode."; 598 "Fixes issues with gapless playback in AirTunes mode."
- desktopinsights.com/apps/swinsian (3rd-party scan of 3.0.8): FFmpeg avcodec/avformat/avutil, FLAC, ogg, vorbis, opus, opusfile, GME, mp4v2...
## VOX
- vox.rocks/vox-player-premium: "have designed a powerful BASS Audio Engine that makes the most out of Hi-Res music"; Hog mode; sample-rate sync; Audio Units; BS2B
## Audirvana
- help.audirvana.com upsampling article: SoX and r8brain. desktopinsights (3rd party, v3.5.50): libsox, iZotope_Resampler, dsd2pcm, wavpack. Forum debug dump: "Local Audio Engine: CoreAudio, Exclusive access: ON, Integer mode: ON"
## Roon
- help.roonlabs.com audio-on-osx: "Roon supports two output mechanisms on Mac OS X: CoreAudio and *ASIO*." "Both are capable of bit-perfect playback."
- help.roonlabs.com raat: "RAAT (Roon Advanced Audio Transport) is the backbone of Roon's audio distribution technology." "Audio devices must own the audio clock."
- brian 2016-08-25: "For non-windows platforms, we use a community-developed .NET implementation called mono."
- Paul Argue 2026-07-23: "The reference Roon Ready code shared with partners to include in their products is written in c"
## Plexamp
- Elan Feingold, Medium "Plexamp v3" (2020-04-16): "a new audio player library we call TREBLE, built on top of a low-level commercial audio engine" ... "sample-accurate gapless playback, high quality resampling"; React Native + react-native-web + Electron for desktop
- forums.plex.tv/t/.../942503: 4.50.6 AppImage packages libbass_aac.so, libbassflac.so, libbassdsd.so...; elan 2026-09-18: "none of the BASS decoder plug-ins have loaded since the 4.50 rewrite"
## foobar2000 mac (foobar2000.org/changelog-mac)
- 2.5 (2023-04-26): "Exclusive audio output support." "Apple Audio Unit DSP support." "Updated internal FFmpeg to version 6.0." "Updated libFLAC to version 1.4.2"; "libvorbis is now used for decoding Vorbis"
- 2.25 FFmpeg 8.0; 2.26 resamplers ARDFTSRC + Speex; 2.6 HE-AAC gapless fix
## Extra
- Colibri App Store (v2.2.0 2024-05-04): "Colibri is a native macOS audio player built from scratch on top of the BASS playback technology"; hog mode; DoP
- Pine Player App Store: "Exclusive Mode minimizes interference from macOS system audio mixing"; engine unnamed
- Fidelia: iZotope SRC (thewelltemperedcomputer / macworld, 3rd party; product dormant)
- Elmedia: bundled ffmpeg binary (FFmpeg trac #5141, 2016)
- Strawberry src/engine/gstengine.cpp:86 kOSXAudioSink = "osxaudiosink"; :186 gapless by queuing URI
- Clementine src/engines/osxdevicefinder.cpp (osxaudiosink)
- DeaDBeeF plugins/coreaudio/coreaudio.c:301 AudioDeviceCreateIOProcID
- Musique musique.pro:41 DEFINES += MEDIA_MPV MEDIA_AUDIOONLY (libmpv)
- Sonora README:12 "thanks to SFBAudioEngine" (2015, dead)
- Petrichor (1.7k stars) -> CrescendoKit (proprietary Crescendo engine, FFmpeg LGPL + TagLib; Lite = CoreAudio-only)
- HiFidelity repo desc: "built with BASS audio library and Taglib"
- Plexamp v4.50.3 (elan 2026-09-01): Electron->Tauri; WASAPI exclusive (Windows); elan 2026-09-18 BASS decoder plug-ins
- Roon 2.0 (Sep 2022): "Implementation of native .NET framework on macOS"
