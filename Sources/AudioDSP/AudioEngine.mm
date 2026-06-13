#include "AudioEngine.h"
#include "CoreAudioDevice.h"
#include <cstring>
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

namespace AdaptiveSound {

// MARK: - ControlMessageRing Implementation

ControlMessageRing::ControlMessageRing() {
    // Already zero-initialized via in-class initializer
}

ControlMessageRing::~ControlMessageRing() = default;

bool ControlMessageRing::tryPush(const DeviceChangeMessage& msg) {
    size_t writeIdx = ring_.writeIndex.load(std::memory_order_acquire);
    size_t nextIdx = (writeIdx + 1) % CAPACITY;
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
    ring_.readIndex.store((readIdx + 1) % CAPACITY, std::memory_order_release);
    return true;
}

// MARK: - AudioEngine Implementation

AudioEngine::AudioEngine()
    : outputUnit_(nullptr),
      outputBus_(nullptr),
      sampleRate_(DEFAULT_SAMPLE_RATE),
      bufferFrameSize_(DEFAULT_BUFFER_FRAMES),
      deviceChangeRing_(std::make_unique<ControlMessageRing>()) {
    std::memset(&streamFormat_, 0, sizeof(streamFormat_));
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
        if (!engine) {
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

        // Store the engine pointer (as void* to keep C++ header clean)
        outputUnit_ = (__bridge_retained void*)engine;

        // Set up audio format
        AudioStreamBasicDescription asbd;
        asbd.mSampleRate = sampleRate_;
        asbd.mFormatID = kAudioFormatLinearPCM;
        asbd.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
        asbd.mBitsPerChannel = 32;
        asbd.mChannelsPerFrame = 2;
        asbd.mBytesPerFrame = asbd.mChannelsPerFrame * asbd.mBitsPerChannel / 8;
        asbd.mBytesPerPacket = asbd.mBytesPerFrame;
        asbd.mFramesPerPacket = 1;
        asbd.mReserved = 0;

        streamFormat_ = asbd;

        // Start the audio engine
        NSError* error = nil;
        [engine startAndReturnError:&error];
        if (error) {
            fprintf(stderr, "[AudioEngine] Failed to start audio engine: %s\n",
                    error.description.UTF8String);
            // Release the engine via bridge transfer (cleanup on error)
            (void)(__bridge_transfer AVAudioEngine*)outputUnit_;
            outputUnit_ = nullptr;
            return false;
        }

        // Pre-allocate buffers (RT-safe)
        size_t bufferSamples = MAX_BUFFER_FRAMES * MAX_CHANNELS;
        workBuffer_.resize(bufferSamples, 0.0f);
        filterState_.resize(MAX_CHANNELS * 2, 0.0f);  // bi-quad state per channel

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

    @autoreleasepool {
        if (outputUnit_) {
            AVAudioEngine* engine = (__bridge_transfer AVAudioEngine*)outputUnit_;
            [engine stop];
            engine = nil;  // Bridge transfer releases it
            outputUnit_ = nullptr;
        }
    }

    outputBus_ = nullptr;
    workBuffer_.clear();
    filterState_.clear();
}

bool AudioEngine::isRunning() const {
    return isRunning_.load(std::memory_order_acquire);
}

std::vector<std::string> AudioEngine::getOutputDeviceNames() const {
    std::vector<std::string> names;
    auto devices = CoreAudioDevice::enumerateOutputDevices();
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
    DeviceChangeMessage msg;
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

}  // namespace AdaptiveSound
