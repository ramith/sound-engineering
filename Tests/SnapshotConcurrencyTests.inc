// SnapshotConcurrencyTests.inc — concurrency regression for DoubleBufferSnapshot<T>, the wait-free
// SPSC triple-buffer parameter transport (S6 RACE-1, hardened 2026-07-10). A concurrent off-RT
// producer (publish) and RT consumer (tryCopySnapshot) must NEVER hand back a TORN snapshot mixing
// two generations, and (under ThreadSanitizer) must contain NO data race. All synchronization rides
// named atomics (no standalone fence), so `make tsan` models every ordering edge.
//
// TWO independent tear detectors (the transport is generic, so we verify it from two angles):
//   1. RACE1 (below) — a REALISTIC TargetState payload; the producer stamps a monotonic generation
//      into several fields (sequenceNumber = gen, intensityLinear = gen, loudness.makeupGainLinear =
//      2·gen, eq.numBiquads = gen%11) and every accepted copy must satisfy those relations for a
//      SINGLE gen. Generation 0 is the constructor's IDENTITY seed (default members, e.g.
//      intensityLinear = 1.0 — NOT zeros), which a reader may legitimately claim before it observes
//      the first real publish; a gen-0 accept is therefore validated against the seed ITSELF (a
//      partial / torn seed still fails). *** This gen-0 branch is the fix for the 2026-07-09 CI red:
//      the old check assumed "gen 0 ⇒ every field 0" and mis-decoded the identity seed (intensity
//      1.0) as a torn read — a FALSE POSITIVE in the test, not a real tear in the transport. ***
//   2. WholePayload (Snapshot_TripleBuffer_WholePayloadNoTear) — a WIDE synthetic payload whose
//      EVERY word must equal the generation, run over several FRESH rounds. It catches a tear in ANY
//      word (not just sampled fields) and hammers the start-of-life window (the seed-vs-first-publish
//      interleaving that exposed the false positive). Its all-zero default IS a self-consistent
//      generation 0, so it needs no seed special-case — a clean, independent cross-check.

#include "DoubleBufferSnapshot.h"

// Is an accepted RACE1 copy internally consistent for a SINGLE generation? gen 0 is the constructor's
// IDENTITY seed (default TargetState — intensityLinear=1.0, NOT zeros), validated against the seed's
// own members; gen >= 1 is producer-stamped and must satisfy the linear field relations. A torn copy
// (fields from >1 generation, or a partially-written seed) fails BOTH branches. Extracted as a free
// helper so the reader stays under the cognitive-complexity gate.
static auto acceptedTargetStateConsistent(const AdaptiveSound::TargetState& out) -> bool
{
    const uint64_t gen = out.sequenceNumber;
    if (gen == 0U)
    {
        const AdaptiveSound::TargetState seed{};
        return (out.intensityLinear == seed.intensityLinear) &&
               (out.loudness.makeupGainLinear == seed.loudness.makeupGainLinear) &&
               (out.eq.numBiquads == seed.eq.numBiquads);
    }
    return (out.intensityLinear == static_cast<float>(gen)) &&
           (out.loudness.makeupGainLinear == static_cast<float>(2U * gen)) &&
           (out.eq.numBiquads == static_cast<uint8_t>(gen % 11U));
}

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
            // gen-0 identity-seed vs gen>=1 stamped check lives in the helper (keeps this reader under
            // the complexity gate); a torn/partial copy fails it. See the file header for the CI story.
            if (!acceptedTargetStateConsistent(out))
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

// ---------------------------------------------------------------------------
// Verifier #2 (hardening, 2026-07-10): WHOLE-PAYLOAD tear detection on the GENERIC transport.
//
// RACE1 above stamps a realistic TargetState and samples a few fields. This test instead drives
// DoubleBufferSnapshot<T> on a WIDE synthetic payload whose EVERY 8-byte word must carry the SAME
// generation, so a torn / mixed read is caught in ANY word — the strongest possible check for a
// whole-struct `memcpy` transport (a real tear would leave some words on the old generation and some
// on the new). It repeats the concurrent scenario over several FRESH snapshots to multiply the
// start-of-life window — the seed-vs-first-publish interleaving that produced the 2026-07-09 red.
// The default payload is all-zero, which is itself a self-consistent "generation 0", so — unlike the
// realistic TargetState whose seed carries identity defaults — this test needs NO seed special-case.
struct GenStampedPayload
{
    static constexpr size_t kWords = 40U; // ~320 B, on the order of TargetState's footprint
    std::array<uint64_t, kWords> words;   // producer sets EVERY word == the generation
};
static_assert(std::is_trivially_copyable_v<GenStampedPayload>,
              "the transport publishes/consumes each slot by a plain memcpy of a trivially-copyable T");

// Scan an accepted whole-payload copy: every word must equal words[0] (the generation). A torn read
// leaves some words on the old generation and some on the new, so a mismatch in ANY word is a tear.
struct PayloadWordScan
{
    bool consistent;      // every word == refGen
    uint64_t refGen;      // words[0]
    uint64_t tornWordGen; // the first word != refGen (0 when consistent)
};
static auto scanWholePayload(const GenStampedPayload& out) -> PayloadWordScan
{
    const uint64_t refGen = out.words[0];
    for (size_t w = 1U; w < GenStampedPayload::kWords; ++w)
    {
        if (out.words[w] != refGen)
        {
            return PayloadWordScan{false, refGen, out.words[w]};
        }
    }
    return PayloadWordScan{true, refGen, 0U};
}

// One concurrent round on a FRESH snapshot: an RT reader hammers tryCopySnapshot while the producer
// publishes `publishes` distinct all-words-equal generations. Returns the round's tallies.
struct WholePayloadRoundResult
{
    uint64_t accepted;
    uint64_t torn;      // accepted copies spanning >1 generation (must be 0)
    uint64_t backwards; // accepted words[0] generation went backwards (must be 0)
    uint64_t firstTornRefGen;
    uint64_t firstTornWordGen;
};
static auto runWholePayloadRound(uint64_t publishes) -> WholePayloadRoundResult
{
    AdaptiveSound::DoubleBufferSnapshot<GenStampedPayload> snapshot;

    std::atomic<bool> readerStop{false};
    std::atomic<uint64_t> accepted{0U};
    std::atomic<uint64_t> torn{0U};
    std::atomic<uint64_t> backwards{0U};
    std::atomic<uint64_t> firstTornRefGen{0U};
    std::atomic<uint64_t> firstTornWordGen{0U};

    std::thread reader([&] {
        GenStampedPayload out{};
        uint64_t last = 0U;
        while (!readerStop.load(std::memory_order_relaxed))
        {
            if (!snapshot.tryCopySnapshot(out))
            {
                continue;
            }
            accepted.fetch_add(1U, std::memory_order_relaxed);
            const PayloadWordScan scan = scanWholePayload(out);
            if (!scan.consistent && torn.fetch_add(1U, std::memory_order_relaxed) == 0U)
            {
                firstTornRefGen.store(scan.refGen, std::memory_order_relaxed);
                firstTornWordGen.store(scan.tornWordGen, std::memory_order_relaxed);
            }
            if (scan.refGen < last)
            {
                backwards.fetch_add(1U, std::memory_order_relaxed);
            }
            last = scan.refGen;
        }
    });

    for (uint64_t gen = 1U; gen <= publishes; ++gen)
    {
        GenStampedPayload state{};
        state.words.fill(gen);
        snapshot.publish(state);
    }
    readerStop.store(true, std::memory_order_relaxed);
    reader.join();

    return WholePayloadRoundResult{accepted.load(), torn.load(), backwards.load(),
                                   firstTornRefGen.load(), firstTornWordGen.load()};
}

static auto testSnapshotTripleBufferWholePayloadNoTear() -> void
{
    static const char* const kName = "Snapshot_TripleBuffer_WholePayloadNoTear";

    constexpr uint64_t kPublishesPerRound = 150000U; // bounded for TSan; ×rounds below
    constexpr int kRounds = 8;                        // 8 fresh snapshots → 8× the start-of-life race

    uint64_t totalAccepted = 0U;
    for (int round = 0; round < kRounds; ++round)
    {
        const WholePayloadRoundResult r = runWholePayloadRound(kPublishesPerRound);
        if (r.torn != 0U)
        {
            logInfo("  [tear] round=" + std::to_string(round) +
                    " refGen(word0)=" + std::to_string(r.firstTornRefGen) +
                    " tornWordGen=" + std::to_string(r.firstTornWordGen) + "\n");
            logFail(kName, "torn read: " + std::to_string(r.torn) +
                               " accepted copy(ies) spanned >1 generation (transport tears)");
            return;
        }
        if (r.backwards != 0U)
        {
            logFail(kName, "word0 generation went backwards on " + std::to_string(r.backwards) +
                               " accepted read(s)");
            return;
        }
        if (r.accepted == 0U)
        {
            logFail(kName, "reader accepted zero snapshots in round " + std::to_string(round) +
                               " — did not exercise the transport");
            return;
        }
        totalAccepted += r.accepted;
    }

    logInfo("  [info] " + std::string(kName) + ": rounds=" + std::to_string(kRounds) +
            " publishes/round=" + std::to_string(kPublishesPerRound) +
            " totalAccepted=" + std::to_string(totalAccepted) + " torn=0\n");
    logPass(kName);
}
