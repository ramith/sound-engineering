#include "AudioEngine.h"
#include "CoreAudioDevice.h"
#include <cstdint>
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>

namespace AdaptiveSound {

// Opaque implementation class (definition only in .mm)
class AVAudioEngineImpl {
 public:
  explicit AVAudioEngineImpl(AVAudioEngine* engine) : engine_(engine) {}

  ~AVAudioEngineImpl() noexcept {
    if (engine_ != nullptr) {
      [engine_ stop];
      engine_ = nil;
    }
  }

  AVAudioEngineImpl(const AVAudioEngineImpl&) = delete;
  auto operator=(const AVAudioEngineImpl&) -> AVAudioEngineImpl& = delete;
  AVAudioEngineImpl(AVAudioEngineImpl&&) = delete;
  auto operator=(AVAudioEngineImpl&&) -> AVAudioEngineImpl& = delete;

  [[nodiscard]] auto get() const noexcept -> AVAudioEngine* { return engine_; }

 private:
  AVAudioEngine* engine_;
};


// Helper: Create AudioStreamBasicDescription for linear PCM float audio
static auto makeStreamFormat(uint32_t sampleRate, uint32_t channels) noexcept
    -> AudioStreamBasicDescription {
  AudioStreamBasicDescription asbd{};
  asbd.mSampleRate = sampleRate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
  asbd.mBitsPerChannel = 32;
  asbd.mChannelsPerFrame = channels;
  asbd.mBytesPerFrame = channels * 4;
  asbd.mBytesPerPacket = channels * 4;
  asbd.mFramesPerPacket = 1;
  asbd.mReserved = 0;
  return asbd;
}

// MARK: - ControlMessageRing Implementation

ControlMessageRing::ControlMessageRing() {
    // Already zero-initialized via in-class initializers
}

bool ControlMessageRing::tryPush(const DeviceChangeMessage& msg) {
    size_t writeIdx = ring_.writeIndex.load(std::memory_order_acquire);
    size_t nextIdx = (writeIdx + 1) % kCapacity;
    size_t readIdx = ring_.readIndex.load(std::memory_order_acquire);

    if (nextIdx == readIdx) {
        return false;  // Ring is full
    }

    ring_.messages[writeIdx] = msg;
    ring_.writeIndex.store(nextIdx, std::memory_order_release);
    return true;
}

bool ControlMessageRing::tryPop(DeviceChangeMessage& msg) {
    size_t readIdx = ring_.readIndex.load(std::memory_order_acquire);
    size_t writeIdx = ring_.writeIndex.load(std::memory_order_acquire);

    if (readIdx == writeIdx) {
        return false;  // Ring is empty
    }

    msg = ring_.messages[readIdx];
    ring_.readIndex.store((readIdx + 1) % kCapacity, std::memory_order_release);
    return true;
}

// MARK: - AudioEngine Implementation

AudioEngine::AudioEngine()
    : outputUnit_(nullptr), deviceChangeRing_(std::make_unique<ControlMessageRing>()) {
    // All other members use in-class default member initializers.
}

AudioEngine::~AudioEngine() {
    shutdown();
}

bool AudioEngine::initialize(uint32_t preferredBufferFrames) {
    if (isRunning_.load()) {
        return true;
    }

    fprintf(stderr, "[AudioEngine] Initializing with %u buffer frames\n", preferredBufferFrames);

    @autoreleasepool {
        // Create AVAudioEngine
        AVAudioEngine* engine = [[AVAudioEngine alloc] init];
        if (engine == nullptr) {
            fprintf(stderr, "[AudioEngine] Failed to create AVAudioEngine\n");
            return false;
        }

        // Get default output device
        AudioDeviceID deviceID = CoreAudioDevice::getDefaultOutputDevice();
        if (deviceID == kAudioObjectUnknown) {
            fprintf(stderr, "[AudioEngine] No output device found\n");
            return false;
        }

        currentDeviceID_.store(deviceID, std::memory_order_release);

        // Query device properties
        if (!queryDeviceProperties(deviceID)) {
            fprintf(stderr, "[AudioEngine] Failed to query device properties\n");
            return false;
        }

        // Store the engine in the opaque implementation wrapper
        outputUnit_ = std::make_unique<AVAudioEngineImpl>(engine);

        // Set up audio format (linear PCM float, 32-bit)
        streamFormat_ = makeStreamFormat(sampleRate_, kMaxChannels);

        // Start the audio engine
        NSError* error = nil;
        [engine startAndReturnError:&error];
        if (error != nil) {
            fprintf(stderr, "[AudioEngine] Failed to start audio engine: %s\n",
                    error.description.UTF8String);
            // unique_ptr destructor will clean up on error
            outputUnit_.reset();
            return false;
        }

        // Pre-allocate buffers (RT-safe)
        size_t bufferSamples = static_cast<size_t>(kMaxBufferFrames) * kMaxChannels;
        workBuffer_.resize(bufferSamples, 0.0F);
        filterState_.resize(static_cast<size_t>(kMaxChannels) * 2, 0.0F);  // bi-quad state per channel

        // Register device change listener (called off-RT)
        CoreAudioDevice::addDefaultDeviceListener(AudioEngine::onDeviceChanged, this);

        isRunning_.store(true, std::memory_order_release);
        fprintf(stderr, "[AudioEngine] Audio engine initialized: %u Hz, %u frames\n",
                sampleRate_, bufferFrameSize_);
        return true;
    }
}

void AudioEngine::shutdown() {
    if (!isRunning_.load()) {
        return;
    }

    fprintf(stderr, "[AudioEngine] Shutting down\n");

    isRunning_.store(false, std::memory_order_release);

    // Remove device listener
    CoreAudioDevice::removeDefaultDeviceListener();

    // unique_ptr will call AVAudioEngineImpl destructor which handles cleanup
    outputUnit_.reset();

    outputBus_ = nullptr;
    workBuffer_.clear();
    filterState_.clear();
}

bool AudioEngine::isRunning() const {
    return isRunning_.load(std::memory_order_acquire);
}

// NOLINTNEXTLINE(readability-convert-member-functions-to-static) -- instance API; future impls will read member device state.
std::vector<std::string> AudioEngine::getOutputDeviceNames() const {
    std::vector<std::string> names;
    auto devices = CoreAudioDevice::enumerateOutputDevices();
    names.reserve(devices.size());
    for (const auto& device : devices) {
        names.push_back(device.name);
    }
    return names;
}

AudioDeviceID AudioEngine::getCurrentDeviceID() const {
    return currentDeviceID_.load(std::memory_order_acquire);
}

bool AudioEngine::selectOutputDevice(AudioDeviceID deviceID) {
    if (!queryDeviceProperties(deviceID)) {
        fprintf(stderr, "[AudioEngine] Invalid device ID: %u\n", deviceID);
        return false;
    }

    // Enqueue device change for RT thread to apply
    DeviceChangeMessage msg{};
    msg.deviceID = deviceID;
    msg.timestamp = 0;

    return deviceChangeRing_->tryPush(msg);
}

void AudioEngine::enqueueDeviceChange(const DeviceChangeMessage& msg) {
    deviceChangeRing_->tryPush(msg);
}

uint32_t AudioEngine::getSampleRate() const {
    return sampleRate_;
}

uint32_t AudioEngine::getBufferFrameSize() const {
    return bufferFrameSize_;
}

bool AudioEngine::queryDeviceProperties(AudioDeviceID deviceID) {
    if (deviceID == kAudioObjectUnknown) {
        return false;
    }

    AudioDevice device = CoreAudioDevice::queryDevice(deviceID);
    sampleRate_ = device.sampleRate;
    bufferFrameSize_ = device.bufferFrameSize;
    return true;
}

// MARK: - Device Listener Callback

void AudioEngine::onDeviceChanged(AudioDeviceID deviceID, void* context) {
    if (context == nullptr) {
        return;
    }

    AudioEngine* self = static_cast<AudioEngine*>(context);

    // Enqueue device change for RT thread to process
    DeviceChangeMessage msg{};
    msg.deviceID = deviceID;
    msg.timestamp = 0;

    if (!self->deviceChangeRing_->tryPush(msg)) {
        fprintf(stderr, "[AudioEngine] Device change ring buffer full, dropping message\n");
    } else {
        fprintf(stderr, "[AudioEngine] Device change enqueued: %u\n", deviceID);
    }
}

// NOLINTEND(cppcoreguidelines-pro-type-vararg)

}  // namespace AdaptiveSound
