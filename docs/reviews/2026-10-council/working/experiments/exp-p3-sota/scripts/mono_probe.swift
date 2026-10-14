// Exp G: the Enhanced reference tone is a MONO buffer (AudioEngineBridge+ReferenceTone.swift:19)
// scheduled on the player whose output is the STEREO graph format (+Lifecycle.swift:46). Header
// (AVAudioPlayerNode.h "ERRORS"): schedule can fail if the buffer's channel count != the node's.
import AVFAudio
import Foundation
let stereo = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
let mono = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
let engine = AVAudioEngine(); let player = AVAudioPlayerNode()
engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: stereo)
try! engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: 512)
try! engine.start()
let buf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 4800)!; buf.frameLength = 4800
print("scheduling a mono buffer on a stereo player…"); fflush(stdout)
player.play()
player.scheduleBuffer(buf, at: nil)
print("scheduled without exception")
