// SnapshotConcurrencyTests.inc — S6 RACE-1 regression: DoubleBufferSnapshot<TargetState> is a
// lock-free SPSC seqlock, so a concurrent off-RT producer (publish) and RT consumer
// (tryCopySnapshot) must NEVER hand back a TORN snapshot mixing two parameter generations, and
// (under ThreadSanitizer) must contain NO data race.
//
// The producer stamps a monotonic generation into several fields so a torn read is detectable:
//   sequenceNumber = gen, intensityLinear = gen, masterGainLinear = 2·gen, eq.numBiquads = gen%11.
// Every ACCEPTED copy (tryCopySnapshot == true) must satisfy those field relations for a SINGLE
// gen. A mismatch is a torn read. Run this under `make tsan` to also prove the transport is
// race-free (all shared accesses are atomic → TSan-clean, unlike a fence-based seqlock).

#include "DoubleBufferSnapshot.h"

static auto testSnapshotSeqlockConcurrentNoTear() -> void
{
    static const char* const kName = "Snapshot_Seqlock_ConcurrentNoTear_RACE1";

    AdaptiveSound::DoubleBufferSnapshot<AdaptiveSound::TargetState> snapshot;

    // Bounded run: enough interleaving to exercise straddles, short enough for the gate + TSan.
    constexpr uint64_t kPublishCount = 200000U;

    std::atomic<bool> readerStop{false};
    std::atomic<uint64_t> acceptedReads{0U};
    std::atomic<uint64_t> tornReads{0U};    // accepted-but-inconsistent (must stay 0)
    std::atomic<uint64_t> staleForward{0U}; // accepted seq went backwards (must stay 0)

    // Diagnostic (TSan torn-read investigation): capture the SHAPE of the first few torn accepts —
    // the reference gen (out.sequenceNumber) vs the generation each OTHER field actually carries — so
    // a re-run reveals WHICH field/word tore and by how many generations. Fires ONLY on the rare
    // failure path and is printed AFTER join(), so it never perturbs the seqlock timing.
    struct TearSample
    {
        uint64_t refGen;       // out.sequenceNumber
        uint64_t intensityGen; // out.intensityLinear decoded back to a gen
        uint64_t makeupGen;    // out.loudness.makeupGainLinear / 2 decoded to a gen
        uint32_t numBiquads;   // out.eq.numBiquads (a later payload word)
    };
    std::array<TearSample, 16> tearSamples{};
    std::atomic<size_t> tearSampleCount{0U};

    // RT consumer: hammer tryCopySnapshot and verify each accepted copy is internally consistent
    // and monotonically non-decreasing in sequenceNumber.
    std::thread reader([&] {
        AdaptiveSound::TargetState out{};
        uint64_t lastSeq = 0U;
        while (!readerStop.load(std::memory_order_relaxed))
        {
            if (!snapshot.tryCopySnapshot(out))
            {
                continue; // straddled beyond the retry budget → caller keeps last good (fine)
            }
            acceptedReads.fetch_add(1U, std::memory_order_relaxed);

            const uint64_t gen = out.sequenceNumber;
            const bool consistent =
                (out.intensityLinear == static_cast<float>(gen)) &&
                (out.loudness.makeupGainLinear == static_cast<float>(2U * gen)) &&
                (out.eq.numBiquads == static_cast<uint8_t>(gen % 11U));
            if (!consistent)
            {
                tornReads.fetch_add(1U, std::memory_order_relaxed);
                const size_t idx = tearSampleCount.fetch_add(1U, std::memory_order_relaxed);
                if (idx < tearSamples.size())
                {
                    tearSamples[idx] =
                        TearSample{gen, static_cast<uint64_t>(out.intensityLinear),
                                   static_cast<uint64_t>(out.loudness.makeupGainLinear / 2.0F),
                                   static_cast<uint32_t>(out.eq.numBiquads)};
                }
            }
            if (gen < lastSeq)
            {
                staleForward.fetch_add(1U, std::memory_order_relaxed);
            }
            lastSeq = gen;
        }
    });

    // Off-RT producer: publish distinct, self-consistent generations as fast as possible.
    for (uint64_t gen = 1U; gen <= kPublishCount; ++gen)
    {
        AdaptiveSound::TargetState state{};
        state.sequenceNumber = gen;
        state.intensityLinear = static_cast<float>(gen);
        state.loudness.makeupGainLinear = static_cast<float>(2U * gen);
        state.eq.numBiquads = static_cast<uint8_t>(gen % 11U);
        snapshot.publish(state);
    }

    readerStop.store(true, std::memory_order_relaxed);
    reader.join();

    if (tornReads.load() != 0U)
    {
        size_t sampleCount = tearSampleCount.load();
        if (sampleCount > tearSamples.size())
        {
            sampleCount = tearSamples.size();
        }
        for (size_t i = 0; i < sampleCount; ++i)
        {
            const auto& s = tearSamples[i];
            logInfo("  [tear] refGen=" + std::to_string(s.refGen) +
                    " intensityGen=" + std::to_string(s.intensityGen) +
                    " makeupGen=" + std::to_string(s.makeupGen) +
                    " numBiquads=" + std::to_string(s.numBiquads) + " (expected " +
                    std::to_string(s.refGen % 11U) + ")\n");
        }
        logFail(kName, "torn read: " + std::to_string(tornReads.load()) +
                           " accepted snapshot(s) mixed parameter generations (seqlock broken)");
        return;
    }
    if (staleForward.load() != 0U)
    {
        logFail(kName, "sequenceNumber went backwards on " +
                           std::to_string(staleForward.load()) + " accepted read(s)");
        return;
    }
    // Sanity: the reader must actually have observed some snapshots (else the test proves nothing).
    if (acceptedReads.load() == 0U)
    {
        logFail(kName, "reader accepted zero snapshots — test did not exercise the transport");
        return;
    }

    logInfo("  [info] " + std::string(kName) +
            ": acceptedReads=" + std::to_string(acceptedReads.load()) +
            " publishes=" + std::to_string(kPublishCount) + " tornReads=0\n");
    logPass(kName);
}
