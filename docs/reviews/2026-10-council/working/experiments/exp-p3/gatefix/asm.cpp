#include "RenderGate.h"
AdaptiveSound::RenderGate g;
bool enter() { return g.tryEnter(); }
void leave() { g.leave(); }
bool req() { return g.requestClose(); }
