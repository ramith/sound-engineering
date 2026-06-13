#pragma once

#include <atomic>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <cstdint>
#include <memory>
#include <vector>

namespace AdaptiveSound
{

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
        static constexpr size_t CAPACITY = 16;

        explicit ControlMessageRing();
        ~ControlMessageRing();

        bool tryPush(const DeviceChangeMessage& msg);
        bool tryPop(DeviceChangeMessage& msg);

      private:
        struct
        {
            DeviceChangeMessage messages[CAPACITY];
            std::atomic<size_t> writeIndex{0};
            std::atomic<size_t> readIndex{0};
        } ring_;
    };

    // Real-time safe audio engine
    class AudioEngine
    {
      public:
        static constexpr uint32_t DEFAULT_SAMPLE_RATE = 48000;
        static constexpr uint32_t DEFAULT_BUFFER_FRAMES = 512;
        static constexpr uint32_t MAX_BUFFER_FRAMES = 4096;
        static constexpr uint32_t MAX_CHANNELS = 2;

        AudioEngine();
        ~AudioEngine();

        // Lifecycle
        bool initialize(uint32_t preferredBufferFrames = DEFAULT_BUFFER_FRAMES);
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
        void* outputUnit_; // AVAudioEngine* (opaque to C++ header)
        void* outputBus_;  // AUAudioUnitBus* (opaque to C++ header)
        AudioStreamBasicDescription streamFormat_;
        std::atomic<bool> isRunning_{false};

        // Device state
        std::atomic<AudioDeviceID> currentDeviceID_{kAudioObjectUnknown};
        std::atomic<AudioDeviceID> pendingDeviceID_{kAudioObjectUnknown};
        uint32_t sampleRate_;
        uint32_t bufferFrameSize_;

        // Pre-allocated RT buffers
        std::vector<float> workBuffer_; // Sized to MAX_BUFFER_FRAMES × MAX_CHANNELS
        std::vector<float> filterState_;

        // Control messaging (lock-free)
        std::unique_ptr<ControlMessageRing> deviceChangeRing_;

        // Non-copyable
        AudioEngine(const AudioEngine&) = delete;
        AudioEngine& operator=(const AudioEngine&) = delete;
    };

} // namespace AdaptiveSound
