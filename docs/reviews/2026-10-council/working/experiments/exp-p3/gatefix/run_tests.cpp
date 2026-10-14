// Runs the fix branch's Tests/RenderGateTests.inc verbatim (one test per process, chosen by argv[1]).
#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <format>
#include <string>
#include <thread>
static void logPass(const char* n) { std::printf("PASS %s\n", n); std::fflush(stdout); }
static void logFail(const char* n, const std::string& e) { std::printf("FAIL %s: %s\n", n, e.c_str()); std::fflush(stdout); }
static void logInfo(const std::string& s) { std::printf("%s", s.c_str()); std::fflush(stdout); }
#include "RenderGateTests_new.inc"
int main(int, char** argv) {
    const char* t = argv[1];
    if (!std::strcmp(t, "closed")) testRenderGateClosedGateTurnsRenderAway();
    if (!std::strcmp(t, "waits")) testRenderGateCloseWaitsForRenderInside();
    if (!std::strcmp(t, "pending")) testRenderGatePendingCloseBarsReentry();
    if (!std::strcmp(t, "race")) testRenderGateConcurrentNeverOverlaps();
}
