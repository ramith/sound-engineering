#ifndef ADAPTIVE_SOUND_AUDIO_ENGINE_H
#define ADAPTIVE_SOUND_AUDIO_ENGINE_H

namespace AdaptiveSound {

class AudioEngine {
public:
    AudioEngine();
    ~AudioEngine();
    
    bool initialize();
    void shutdown();
    bool isRunning() const;
    
private:
    bool initialized_ = false;
};

} // namespace AdaptiveSound

#endif // ADAPTIVE_SOUND_AUDIO_ENGINE_H
