// ruleid: cpp-no-session-agc
std::unique_ptr<LoudnessModule> loudnessModule_;
// ruleid: cpp-no-session-agc
const LoudnessParams params{};
// ok: cpp-no-session-agc
// The session normaliser (LoudnessModule) was deleted in R1.1-B.
// ok: cpp-no-session-agc
TrackLoudnessGain gain(48000.0);
