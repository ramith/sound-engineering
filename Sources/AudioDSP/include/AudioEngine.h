#pragma once

#include "AudioConstants.h"
#include <array>
#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <cstdint>
#include <memory>
#include <vector>

namespace AdaptiveSound
{

    // Opaque forward declarations for Objective-C++ implementation details
    class AVAudioEngineImpl;

    // Device change message for lock-free parameter passing
    struct DeviceChangeMessage
    {
        AudioDeviceID deviceID;
        uint64_t timestamp;
    };

    // Ring buffer for control messages (SPSC)
    class ControlMessageRing
    {
      public:
        static constexpr size_t kCapacity = 16;

        explicit ControlMessageRing();
        ~ControlMessageRing() = default;
        ControlMessageRing(const ControlMessageRing&) = delete;
        ControlMessageRing& operator=(const ControlMessageRing&) = delete;
        ControlMessageRing(ControlMessageRing&&) = delete;
        ControlMessageRing& operator=(ControlMessageRing&&) = delete;

        bool tryPush(const DeviceChangeMessage& msg);
        bool tryPop(DeviceChangeMessage& msg);

      private:
        struct
        {
            std::array<DeviceChangeMessage, kCapacity> messages{};
            std::atomic<size_t> writeIndex{0};
            std::atomic<size_t> readIndex{0};
        } ring_;
    };

    // Real-time safe audio engine
    class AudioEngine
    {
      public:
        static constexpr uint32_t kDefaultSampleRate = AdaptiveSound::kDefaultSampleRate;
        static constexpr uint32_t kDefaultBufferFrames = AdaptiveSound::kDefaultMaxFrames;
        static constexpr uint32_t kMaxBufferFrames = 4096;
        static constexpr uint32_t kMaxChannels = 2;

        AudioEngine();
        ~AudioEngine();
        AudioEngine(const AudioEngine&) = delete;
        AudioEngine& operator=(const AudioEngine&) = delete;
        AudioEngine(AudioEngine&&) = delete;
        AudioEngine& operator=(AudioEngine&&) = delete;

        // Lifecycle
        bool initialize(uint32_t preferredBufferFrames = kDefaultBufferFrames);
        void shutdown();
        bool isRunning() const;

        // Device management (off-thread safe)
        std::vector<std::string> getOutputDeviceNames() const;
        AudioDeviceID getCurrentDeviceID() const;
        bool selectOutputDevice(AudioDeviceID deviceID);

        // RT-safe control messaging
        void enqueueDeviceChange(const DeviceChangeMessage& msg);

        // Query state (atomic reads)
        uint32_t getSampleRate() const;
        uint32_t getBufferFrameSize() const;

      private:
        // Helper: Query device properties
        bool queryDeviceProperties(AudioDeviceID deviceID);

        // Device listener callback (called off-RT when device changes)
        static void onDeviceChanged(AudioDeviceID deviceID, void* context);

        // State
        std::unique_ptr<AVAudioEngineImpl> outputUnit_;
        void* outputBus_ = nullptr; // AUAudioUnitBus* (platform-specific detail)
        AudioStreamBasicDescription streamFormat_{};
        std::atomic<bool> isRunning_{false};

        // Device state
        std::atomic<AudioDeviceID> currentDeviceID_{kAudioObjectUnknown};
        std::atomic<AudioDeviceID> pendingDeviceID_{kAudioObjectUnknown};
        uint32_t sampleRate_ = kDefaultSampleRate;
        uint32_t bufferFrameSize_ = kDefaultBufferFrames;

        // Pre-allocated RT buffers
        std::vector<float> workBuffer_; // Sized to kMaxBufferFrames × kMaxChannels
        std::vector<float> filterState_;

        // Control messaging (lock-free)
        std::unique_ptr<ControlMessageRing> deviceChangeRing_;
    };

} // namespace AdaptiveSound
