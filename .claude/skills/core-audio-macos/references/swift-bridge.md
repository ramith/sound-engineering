# Swift/SwiftUI ↔ C++ Bridge for the Audio Engine

How to connect a SwiftUI app to the C++ Core Audio engine. Two documented
approaches; pick ONE per project and keep the bridge layer thin.

Sources: Apple, "Mixing Swift and C++"
(https://developer.apple.com/documentation/swift/mixingswiftandc++) and
Swift.org C++ interoperability documentation
(https://www.swift.org/documentation/cxx-interop/). Both are JS-rendered —
when details are needed beyond this file, prefer the Swift.org page (it has
a static mirror in the swift.org repo) or verify against a small test target
in Xcode rather than reconstructing rules from memory.

## Design rules (apply to both approaches)

- Keep the bridge surface small and boring: plain functions or one wrapper
  class with value-type parameters (Int, Float, Double, Bool, simple
  structs). No templates, no STL containers, no exceptions across the
  boundary.
- The bridge is a control plane, not a data plane. UI calls like
  setBandGain(band, dB) write to std::atomic parameters inside the C++
  engine (see code-samples.md §8); the audio thread reads those atomics. The
  audio thread must NEVER call back into Swift/Objective-C — both runtimes
  can lock and allocate, which violates the real-time rules in SKILL.md.
- For engine→UI data (e.g. level meters, FFT for a spectrum view), the audio
  thread writes into a lock-free ring buffer or a seqlock-style snapshot;
  the Swift side polls it from a Timer/CADisplayLink on the main thread.
  Push notifications from the audio thread are not real-time safe.

## Approach A — Objective-C++ wrapper (classic, maximally compatible)

Wrap the C++ engine in an Objective-C class implemented in a .mm file;
Swift sees plain Objective-C through the bridging header. Works with any
Swift version and keeps all C++ types out of Swift's view.

AudioEngineBridge.h (pure Objective-C — no C++ types here):

```objc
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioEngineBridge : NSObject
- (BOOL)start;
- (void)stop;
- (void)setBandGain:(NSInteger)band decibels:(float)dB;
- (float)currentOutputLevel;   // polled by the UI, never pushed
@end

NS_ASSUME_NONNULL_END
```

AudioEngineBridge.mm (Objective-C++ — owns the C++ engine):

```objc
#import "AudioEngineBridge.h"
#include "AudioEngine.hpp"   // your C++ Core Audio engine
#include <memory>

@implementation AudioEngineBridge {
    std::unique_ptr<AudioEngine> _engine;
}

- (instancetype)init {
    if ((self = [super init])) _engine = std::make_unique<AudioEngine>();
    return self;
}

- (BOOL)start { return _engine->start(); }
- (void)stop { _engine->stop(); }

- (void)setBandGain:(NSInteger)band decibels:(float)dB {
    _engine->setBandGain((int)band, dB);   // writes a std::atomic<float>
}

- (float)currentOutputLevel {
    return _engine->currentOutputLevel();  // reads an atomic/snapshot
}
@end
```

Expose to Swift via the target's bridging header
(`#import "AudioEngineBridge.h"`), or for SPM/framework targets via a module
map. SwiftUI usage:

```swift
@Observable final class EngineModel {
    private let engine = AudioEngineBridge()
    var bandGains: [Float] = Array(repeating: 0, count: 10) {
        didSet {
            for (i, g) in bandGains.enumerated() {
                engine.setBandGain(i, decibels: g)
            }
        }
    }
    func start() { _ = engine.start() }
}
```

## Approach B — Direct Swift/C++ interop (Swift 5.9+, less glue)

Xcode build setting "C++ and Objective-C Interoperability" → "C++", or in
SPM: `swiftSettings: [.interoperabilityMode(.Cxx)]`. Swift then imports the
C++ module directly and can instantiate C++ classes without a wrapper.

Constraints to respect (per the Swift.org interop documentation — verify
there when in doubt): expose only simple value/reference types and member
functions; avoid templates, raw pointers, and STL types in the API Swift
sees; mark non-copyable engine types appropriately or hold them behind a
small C++ facade class. In practice, even with direct interop, keeping a
single `EngineFacade` C++ class as the only type Swift touches gives the
same isolation as Approach A with less boilerplate.

## Choosing

- Team knows Objective-C, needs to support older toolchains, or wants a
  hard ABI wall → Approach A.
- Greenfield, recent Xcode, minimal glue preferred → Approach B with a
  facade class.
- Either way, the GUI never links against CoreAudio directly; all audio
  work stays behind the bridge in C++.

## Menu-bar app note

Audio utilities of this kind are typically menu-bar apps: SwiftUI's
`MenuBarExtra` scene (macOS 13+) is the first-class API. The engine object
should be created once at app launch (e.g. as a @State object on the App
struct or an app-level singleton), not per-view — the AUHAL and driver
connections must outlive any window.
