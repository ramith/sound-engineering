#include "AudioEngine.h"
#include <iostream>

namespace AdaptiveSound {

AudioEngine::AudioEngine() : initialized_(false) {
}

AudioEngine::~AudioEngine() {
    shutdown();
}

bool AudioEngine::initialize() {
    if (initialized_) return true;
    
    std::cout << "[AudioEngine] Initializing..." << std::endl;
    
    // TODO: Initialize AVAudioEngine here in Sprint 1
    initialized_ = true;
    
    std::cout << "[AudioEngine] Audio engine ready" << std::endl;
    return true;
}

void AudioEngine::shutdown() {
    if (!initialized_) return;
    
    std::cout << "[AudioEngine] Shutting down..." << std::endl;
    initialized_ = false;
}

bool AudioEngine::isRunning() const {
    return initialized_;
}

} // namespace AdaptiveSound
