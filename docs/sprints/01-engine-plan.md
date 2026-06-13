# Sprint 1 Implementation Plan — US-ENG-01: Real Audio Engine

**Story:** US-ENG-01 — Real AVAudioEngine with Core Audio device integration  
**Estimate:** 8 sp / 3–4 days  
**Team Review:** Complete (Core Audio, QA, UI/UX experts)  
**Status:** Ready for Implementation

---

## Executive Summary

Sprint 1 establishes the audio foundation: enumerate devices, initialize AUHAL (Audio Unit Hardware Abstraction Layer), and run a real render callback loop. No playback/DSP yet—just the kernel booting.

**Goal:** By sprint end, the app enumerates output devices, displays them in the UI, lets the user select one, and the audio engine runs silence to that device with zero XRuns on M1 Pro.

**Acceptance Criteria (from story):**
- ✅ Core Audio device enumeration (list input/output, detect changes)
- ✅ AUHAL output unit initialized and running
- ✅ Render callback established (no-op, produces silence)
- ✅ Audio thread safe (pre-allocated, lock-free, no I/O)
- ✅ Device change listeners (hot-plug support)
- ✅ Zero XRuns on M1 Pro (512-frame buffer, 48 kHz)
- ✅ Unit + integration tests pass
- ✅ Manual testing (device enumeration, hot-swap, 10-min stability) signed off

---

## Architecture & Design

### C++ Audio Engine (Real-Time Safe)

**Class Structure:**
```cpp
// Sources/AudioDSP/include/AudioEngine.h
class AudioEngine {
public:
    // Lifecycle
    bool initialize(uint32_t preferredBufferFrames = 512);
    void shutdown();
    bool isRunning() const;
    
    // Device management (off-thread)
    std::vector<AudioDevice> enumerateOutputDevices();
    bool selectOutputDevice(AudioDeviceID deviceID);
    AudioDevice getCurrentDevice() const;
    
    // RT-safe parameter bus (lock-free)
    void enqueueDeviceChange(const DeviceChangeMessage& msg);
    
private:
    // AUHAL graph
    AUAudioUnit* outputUnit_;
    AUAudioUnitBus* outputBus_;
    AudioStreamBasicDescription streamFormat_;
    uint32_t maxBufferFrames_;
    
    // Device listener
    AudioDeviceID currentDeviceID_;
    std::atomic<AudioDeviceID> pendingDeviceID_;
    
    // Pre-allocated buffers
    std::vector<float> workBuffer_;  // Sized to maxBufferFrames_ at init
    std::vector<float> filterState_;
    
    // Ring buffer for control messages
    ControlMessageRing deviceChangeRing_;
    
    // Render callback (static, trampoline)
    static AUEventSampleTime renderCallback(
        void* inRefCon,
        const AudioTimeStamp* inTimeStamp,
        AUAudioFrameCount inNumberFrames,
        AudioBusNumber inBusNumber,
        AudioBufferList* ioData
    );
    
    AUEventSampleTime processRender(
        const AudioTimeStamp* inTimeStamp,
        AUAudioFrameCount inNumberFrames,
        AudioBufferList* ioData
    );
};

// Sources/AudioDSP/include/CoreAudioDevice.h
struct AudioDevice {
    AudioDeviceID id;
    std::string name;
    uint32_t sampleRate;
    uint32_t bufferFrameSize;
    enum Type { Builtin, USB, Wireless, Unknown };
    Type type;
};

struct DeviceChangeMessage {
    AudioDeviceID deviceID;
    uint64_t timestamp;
};

class CoreAudioDevice {
public:
    static std::vector<AudioDevice> enumerateOutputDevices();
    static bool addDeviceListener(AudioDeviceID deviceID, 
                                   AudioObjectPropertyListenerBlock listener);
    static bool removeDeviceListener(AudioDeviceID deviceID,
                                      AudioObjectPropertyListenerBlock listener);
};
```

**Real-Time Safety Guardrails:**
1. **Pre-allocated buffers:** All work buffers sized at init; zero malloc in render
2. **Lock-free device changes:** `std::atomic<AudioDeviceID>` for read; ring buffer for async changes
3. **No I/O, logging, or locks on RT thread:** Device listener is off-thread (Core Audio internal thread)
4. **Device set before Init:** AUHAL must have device ID before `Initialize()` call
5. **Handle variable frame counts:** Gracefully process whatever AUHAL hands us (≥512 frames on M1 Pro, but verify)

**Critical Implementation Details:**
- Use `AVAudioEngine` for graph management (high-level) OR raw AUHAL (low-level)
  - **Recommendation:** Start with raw AUHAL + `AudioUnitRender()` for full control
  - `AVAudioEngine` abstraction hides device selection complexity
- Device listener callback runs on **Core Audio's internal thread, NOT the render thread**
  - Safe to do light work (set atomic flags, queue messages)
  - Unsafe: mutex locks, logging, system calls
- Buffer size negotiation: Query `kAudioDevicePropertyBufferFrameSize`; accept whatever device reports

---

### Swift Control Plane (UI Thread Safe)

**ViewModel:**
```swift
// Sources/AdaptiveSound/AudioViewModel.swift
@MainActor
class AudioViewModel: ObservableObject {
    @Published var isEngineReady = false
    @Published var errorMessage: String?
    @Published var selectedDevice: AudioDevice?
    @Published var availableDevices: [AudioDevice] = []
    @Published var sampleRate: UInt32 = 0
    @Published var bufferFrameSize: UInt32 = 0
    
    private let audioEngine: AudioEngineProtocol
    
    func initializeEngine() {
        Task.detached { [weak self] in
            do {
                let devices = try await self?.audioEngine.enumerateDevices() ?? []
                let defaultDevice = devices.first
                
                try await self?.audioEngine.selectDevice(defaultDevice?.id ?? 0)
                
                await MainActor.run {
                    self?.availableDevices = devices
                    self?.selectedDevice = defaultDevice
                    self?.isEngineReady = true
                    self?.errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                    self?.isEngineReady = false
                }
            }
        }
    }
    
    func selectDevice(_ device: AudioDevice) {
        Task.detached { [weak self] in
            do {
                try await self?.audioEngine.selectDevice(device.id)
                await MainActor.run {
                    self?.selectedDevice = device
                    self?.sampleRate = device.sampleRate
                    self?.bufferFrameSize = device.bufferFrameSize
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Failed to select device: \(error.localizedDescription)"
                }
            }
        }
    }
}
```

**UI Layout:**
```swift
// Status card: engine running ✓, device name, sample rate, buffer size
VStack(spacing: 16) {
    // Status
    HStack {
        Image(systemName: "circle.fill")
            .foregroundColor(viewModel.isEngineReady ? .green : .red)
        Text("Audio Engine \(viewModel.isEngineReady ? "Ready" : "Initializing")")
            .font(.headline)
        Spacer()
    }
    .padding(12)
    .background(Color(nsColor: .controlBackgroundColor))
    .cornerRadius(8)
    
    // Current device info
    VStack(alignment: .leading, spacing: 4) {
        Text("Output Device")
            .font(.subheadline)
            .foregroundColor(.secondary)
        Text(viewModel.selectedDevice?.name ?? "Unknown")
            .font(.body)
            .fontWeight(.semibold)
        HStack(spacing: 12) {
            Text("\(viewModel.sampleRate) Hz")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("\(viewModel.bufferFrameSize) frames")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // Device selector
    VStack(alignment: .leading) {
        Text("Available Devices")
            .font(.subheadline)
            .fontWeight(.semibold)
        
        ScrollView {
            VStack(spacing: 8) {
                ForEach(viewModel.availableDevices, id: \.id) { device in
                    Button(action: { viewModel.selectDevice(device) }) {
                        HStack {
                            Image(systemName: deviceIcon(device.type))
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.body)
                                Text("\(device.sampleRate) Hz")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if device.id == viewModel.selectedDevice?.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(8)
                        .background(device.id == viewModel.selectedDevice?.id ? Color.blue.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Device: \(device.name)")
                    .accessibilityHint("Double-tap to select")
                    .accessibilityAddTraits(device.id == viewModel.selectedDevice?.id ? .isSelected : [])
                }
            }
        }
        .frame(maxHeight: 200)
    }
    
    // Error banner
    if let error = viewModel.errorMessage {
        VStack(alignment: .leading, spacing: 8) {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.body)
            Button(action: { viewModel.initializeEngine() }) {
                Text("Retry")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityRole(.alert)
    }
    
    Spacer()
}
.padding()
.onAppear {
    viewModel.initializeEngine()
}
```

**Thread Safety:**
- All ViewModel methods are `@MainActor`
- Engine calls wrapped in `Task.detached` (off-main-thread)
- No synchronous waits on audio engine (always async/await)
- Device selection message queued, not applied immediately (ring buffer pattern)

---

## Implementation Breakdown (8 sp total)

### Phase 1: C++ Foundation (2 sp)
**Task:** AUHAL bootstrap + render loop

Files:
- `Sources/AudioDSP/include/AudioEngine.h` — public interface
- `Sources/AudioDSP/src/AudioEngine.cpp` — AUHAL init, shutdown, render callback
- `Sources/AudioDSP/include/CoreAudioDevice.h` — device enumeration API
- `Sources/AudioDSP/src/CoreAudioDevice.cpp` — implement enumerateOutputDevices()

Checklist:
- [ ] Implement `AudioEngine::initialize()` → create AUHAL unit, set device, allocate buffers, start audio
- [ ] Implement `AudioEngine::shutdown()` → stop audio, release unit, clear buffers
- [ ] Implement render callback trampoline + `processRender()` (currently outputs silence)
- [ ] Implement `CoreAudioDevice::enumerateOutputDevices()` (query `kAudioHardwarePropertyDevices`)
- [ ] Verify compile with strict C++ flags (`-Werror=all`, clang-tidy)

**Key Code Sections:**
```cpp
bool AudioEngine::initialize(uint32_t preferredBufferFrames) {
    // 1. Get AUHAL output unit from AVAudioEngine (or create directly)
    // 2. Query default output device ID
    // 3. Set device on output unit before Initialize()
    // 4. Pre-allocate work buffers (sized to maxBufferFrames_)
    // 5. Set render callback via AudioUnitSetParameter() or AUAudioUnit delegate
    // 6. Call AudioUnitInitialize()
    // 7. Call AudioOutputUnitStart()
    // 8. Store currentDeviceID_, mark engineRunning_ = true
    // 9. Return true
}

AUEventSampleTime AudioEngine::renderCallback(...) {
    // 1. Dequeue any pending device changes from ring buffer
    // 2. Fill ioData with silence (memset to 0)
    // 3. Return the sample time + frame count
}
```

---

### Phase 2: Device Management (2 sp)
**Task:** Device enumeration, listener setup, device selection

Files:
- `Sources/AudioDSP/src/CoreAudioDevice.cpp` — listener + hot-plug detection
- Update `AudioEngine.cpp` — integrate listener, handle device changes

Checklist:
- [ ] Implement `enumerateOutputDevices()` — query all devices, extract name/sampleRate/bufferSize
- [ ] Implement device listener callback (off-thread, sets atomic flag / queues message)
- [ ] Implement `selectOutputDevice()` — validate device, enqueue change for RT thread to apply
- [ ] Add device listener registration in `initialize()`, cleanup in `shutdown()`
- [ ] Handle device unplugged → fallback to system default
- [ ] Verify zero crashes on device hot-plug

**Key Code Sections:**
```cpp
std::vector<AudioDevice> CoreAudioDevice::enumerateOutputDevices() {
    // 1. Query kAudioHardwarePropertyDevices → array of device IDs
    // 2. For each ID, query:
    //    - kAudioObjectPropertyName (device name)
    //    - kAudioDevicePropertyNominalSampleRate
    //    - kAudioDevicePropertyBufferFrameSize
    //    - Determine Type (builtin speaker vs. USB vs. wireless)
    // 3. Return vector<AudioDevice>
}

bool AudioEngine::selectOutputDevice(AudioDeviceID deviceID) {
    // 1. Validate deviceID (query its properties)
    // 2. Enqueue DeviceChangeMessage to ring buffer
    // 3. Return true if enqueue succeeded
    // (RT thread applies change asynchronously)
}

// Device listener callback (off-thread, safe for atomics + logging)
void devicePropertyListenerBlock(
    uint32_t inNumberAddresses,
    const AudioObjectPropertyAddress inAddresses[]
) {
    // If property == kAudioHardwarePropertyDefaultOutputDevice:
    //   audioEngine->pendingDeviceID_.store(newDefault)
    // If property == kAudioDevicePropertyDeviceIsAlive:
    //   if !alive, trigger fallback logic
}
```

---

### Phase 3: Swift Integration (2 sp)
**Task:** ViewModel, UI layout, error handling

Files:
- `Sources/AdaptiveSound/AudioViewModel.swift` — ViewModel implementation
- `Sources/AdaptiveSound/AdaptiveSound.swift` — UI layout + onAppear

Checklist:
- [ ] Create `AudioViewModel` with device enumeration + selection logic
- [ ] Implement `initializeEngine()` → calls C++ engine, populates device list
- [ ] Implement `selectDevice()` → async device switch
- [ ] Build status card UI (engine running indicator + current device info)
- [ ] Build device picker UI (scrollable list, tap to select, checkmark indicator)
- [ ] Add error banner (inline, with retry button)
- [ ] Add a11y labels (VoiceOver support)
- [ ] Verify no blocking calls (all `Task.detached`)

**Key UI Interactions:**
- App launch → `onAppear` → `viewModel.initializeEngine()` → enumerate devices, select default, show in UI
- User taps device → `selectDevice(device)` → async message to C++ ring buffer → RT thread applies

---

### Phase 4: Real-Time Safety & Testing (2 sp)
**Task:** Unit/integration tests, real-time safety validation

Files:
- `Tests/AdaptiveSound/AudioEngineTests.swift` — unit tests
- `Tests/AdaptiveSound/DeviceEnumerationTests.swift` — device logic
- `Tests/AdaptiveSound/RenderCallbackTests.swift` — RT safety gates

Checklist:
- [ ] **Unit tests (6 total):**
  - [ ] Device enumeration returns non-empty list
  - [ ] Device properties populated (name, sampleRate, bufferFrameSize)
  - [ ] Current device is default device after init
  - [ ] Pre-allocated buffers are sized correctly (ASAN validates)
  - [ ] Listener registration succeeds (no crashes)
  - [ ] Ring buffer enqueue/dequeue works

- [ ] **Integration tests (6 total):**
  - [ ] Engine initializes without crash
  - [ ] Render callback fires at 512-frame intervals (verify via mock buffer fill)
  - [ ] Device selection message is processed (mock RT thread, verify atomic reads)
  - [ ] No heap allocations during render (ASAN in RT mode)
  - [ ] No locks in render (ThreadSanitizer clean)
  - [ ] Silence output verified (AudioBufferList contains zeros)

- [ ] **Manual testing (Friday sprint review):**
  - [ ] Launch app → device list populated ✓
  - [ ] Select AirPods → audio routed to AirPods (silent, but system shows it) ✓
  - [ ] Plug/unplug AirPods → app doesn't crash, falls back to speaker ✓
  - [ ] 10-minute stability test → zero XRuns (System Trace verification)
  - [ ] Instruments: Allocations (zero malloc on RT), Thread State (zero preemptions)

**Test Instrumentation:**
```bash
# Run unit tests
swift test -c debug

# Manual testing with ASAN enabled
swift build -c debug  # (already enabled in Package.swift)
swift run AdaptiveSound

# System Trace (Instruments)
# Product → Profile → System Trace → look for XRun warnings
```

---

## Dependencies & Blockers

**None.** Sprint 0 complete; Sprint 1 is self-contained.

**Pre-requisites (already met):**
- ✅ Swift Package project structure
- ✅ C++/Swift interop (bridging header)
- ✅ Compiler guardrails (-Werror, clang-tidy)
- ✅ Code formatting + pre-commit hooks

---

## Risk Mitigation

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Device listener callback data race | High | Code review gate: ensure `weak self`, no strong captures; use atomics only |
| AUHAL device set after Init | High | Document: "Device must be set **before** AudioUnitInitialize()" |
| Buffer size mismatch (256 vs 512 frames) | Medium | Query device buffer size at init; log if ≠ 512; accept whatever AUHAL provides |
| No device detected on startup | Medium | Graceful error banner; allow user to open System Settings; retry button |
| Device hot-plug during init | Low | Core Audio is resilient; test with actual AirPods plug/unplug during app launch |
| Memory leak in device listener | High | Verify cleanup in `shutdown()`; remove listener before destroying engine |
| UI blocks on device enumeration | Medium | Always async; pre-populate cache in background; timeout after 5 sec |

**Code Review Gates (before merging to main):**
1. Device listener callback has no strong self references
2. Render callback: zero I/O, logging, or malloc (grep + code review)
3. All ViewModel methods are @MainActor; engine calls are Task.detached
4. clang-tidy passes (no data races, core guidelines violations)
5. ThreadSanitizer clean on integration tests
6. ASAN clean (zero heap allocs on RT thread)

---

## Definition of Done (Sprint 1)

Sprint 1 is complete when:

**Code:**
- [ ] All files committed to `main`
- [ ] Zero compiler warnings (`-Werror` gate)
- [ ] clang-tidy passes
- [ ] Code review checklist signed off

**Testing:**
- [ ] All 6 unit tests pass
- [ ] All 6 integration tests pass
- [ ] ASAN output clean (zero violations)
- [ ] ThreadSanitizer clean
- [ ] Manual testing checklist complete (device enum, hot-swap, 10-min stability)
- [ ] System Trace log shows zero XRuns

**Documentation:**
- [ ] Inline code comments (why, not what) on device listener + render callback
- [ ] README updated with "How to run" for Sprint 1 (device enumeration test)

**Retro:**
- [ ] 30-min retrospective (Slack or sync call)
  - What went well?
  - What was harder than expected?
  - What do we want to improve for Sprint 2?

---

## Files Created/Modified

**New Files:**
- `Sources/AudioDSP/src/AudioEngine.cpp` (complete implementation)
- `Sources/AudioDSP/include/CoreAudioDevice.h` (device API)
- `Sources/AudioDSP/src/CoreAudioDevice.cpp` (enumeration + listener)
- `Sources/AdaptiveSound/AudioViewModel.swift` (ViewModel)
- `Tests/AdaptiveSound/AudioEngineTests.swift` (unit tests)
- `Tests/AdaptiveSound/DeviceEnumerationTests.swift` (device tests)
- `Tests/AdaptiveSound/RenderCallbackTests.swift` (RT safety tests)

**Modified:**
- `Sources/AudioDSP/include/AudioEngine.h` (add full API)
- `Sources/AdaptiveSound/AdaptiveSound.swift` (update UI, add ViewModel)
- `Package.swift` (add test targets if not present)
- `README.md` (update with Sprint 1 status)

---

## Timeline

- **Day 1 (2 sp):** C++ foundation (AUHAL init, render callback, pre-allocation)
- **Day 2 (2 sp):** Device management (enumeration, listener, hot-plug)
- **Day 3 (2 sp):** Swift integration (ViewModel, UI, error handling)
- **Day 4 (2 sp):** Testing (unit/integration, ASAN, manual, retro)

**Daily stand-ups:** ~15 min (async updates in team Slack)  
**Code review:** ~1 hour (gate before merge)  
**Manual testing:** Friday afternoon (1–2 hours)  
**Sprint retro:** Friday EOD (30 min)

---

## Next Steps (Sprint 2 Preview)

Once Sprint 1 is done:
- **US-ENG-02:** Audio Workgroups + multi-threaded DSP scheduling (optional for Phase 1, but foundation for Phase 1.5)
- **US-ENG-03:** SPSC ring buffer + lock-free parameter bus (required for Phase 1 tuning)
- **US-PERC-01:** First DSP story (simple tone-shaping EQ)

---

**Prepared By:** Team (Core Audio, QA, UI/UX experts)  
**Date:** 2026-06-13  
**Status:** Ready for Implementation ✅
