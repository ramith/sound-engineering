// LfeRuleTests.inc
//
// The LFE rule: include or omit a track's LFE in the stereo fold, from the analysis's statistics
// (Spatial/FoldLfeRule; level-and-fold §5 and §8½ C4). #included into Tests/DSPKernelNullTest.cpp after
// TestSupport.h; its rows go in the kTests block marked "LfeRuleTests.inc" there, so the two lanes never edit the
// same lines of the table.
//
// THE CASES. kLfeRuleCases holds the statistics measured on every fixture the design and its review measured:
//   - "design …": the design's 39 cases x 3 seeds (its prototype, proto/p4_lfe_v2.py — the 117 runs of §5's
//     table), re-run with the 90th-percentile r² (C2) added;
//   - "verify …": the verify pass's fixtures (verify/lfe_v2_check.py: plain, polarity-inverted, delayed,
//     linear-phase, automated-send and tandem-filtered copies; independent, rhythm-following and octave-down
//     subs; bass redirected behind 100 Hz LR4, 80 Hz and 60 Hz BW2 high-passes; a kick-stem copy), 3 seeds;
//   - "kick sweep …": C4's kick-balance sweep — a kick-stem copy with the kick +3 … −14 dB against the bass.
// The statistics come from those prototypes' own code (Python, at 500 Hz), not from the shipped analyzer, which
// lane 1-B writes. When it lands, the same fixtures should run end to end through it (audio → statistics →
// rule); until then this table pins the RULE: its thresholds, against the numbers the design was decided on.
//
// INTENT. Omit / Include: the rule must decide it. Either: both are acceptable (a quiet independent sub).
// KnownIssue: the rule's measured limits, LOGGED, never asserted (C4; lane 2's report): a stem copy ≥ 10 dB under
// the bass reads as an independent layer and is included; bass behind a gentle 60 Hz high-pass sits on the
// +15 dB explain-gain line; a sub that sounds only part of the time is omitted.

#include "Spatial/FoldLfeRule.h"

namespace
{
    enum class LfeIntent : uint8_t
    {
        Omit,
        Include,
        Either,
        KnownIssue,
    };

    struct LfeRuleCase
    {
        const char* name;
        LfeIntent intent;
        // activeBlocks, lagMs, lagPeak, coherentShare, medianR2, p90R2, excess20Share, explainGainDb
        AsLfeStats stats;
    };

    const std::array kLfeRuleCases = std::to_array<LfeRuleCase>({
        {"design A/copy/s0", LfeIntent::Omit, {597, 8.00F, 0.9458F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 0.05F}},
        {"design A/copy/s1", LfeIntent::Omit, {597, 8.00F, 0.9425F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 0.04F}},
        {"design A/copy/s2", LfeIntent::Omit, {597, 8.00F, 0.9452F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 0.05F}},
        {"design A/lr4/s0", LfeIntent::Omit, {597, 6.00F, 0.9261F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.08F}},
        {"design A/lr4/s1", LfeIntent::Omit, {597, 6.00F, 0.9379F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.09F}},
        {"design A/lr4/s2", LfeIntent::Omit, {597, 6.00F, 0.9294F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.09F}},
        {"design A/film/s0", LfeIntent::Omit, {597, 8.00F, 0.9458F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -9.95F}},
        {"design A/film/s1", LfeIntent::Omit, {597, 8.00F, 0.9425F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -9.96F}},
        {"design A/film/s2", LfeIntent::Omit, {597, 8.00F, 0.9452F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -9.95F}},
        {"design A/eq/s0", LfeIntent::Omit, {597, 16.00F, 0.8167F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 5.75F}},
        {"design A/eq/s1", LfeIntent::Omit, {597, 8.00F, 0.8397F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, 5.52F}},
        {"design A/eq/s2", LfeIntent::Omit, {597, 16.00F, 0.8184F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 5.75F}},
        {"design A/subset/s0", LfeIntent::Omit, {597, 8.00F, 0.7229F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -3.89F}},
        {"design A/subset/s1", LfeIntent::Omit, {597, 8.00F, 0.7272F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -4.08F}},
        {"design A/subset/s2", LfeIntent::Omit, {597, 8.00F, 0.7324F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -3.12F}},
        {"design A/rare/s0", LfeIntent::Omit, {597, 8.00F, 0.8652F, 0.8978F, 0.9995F, 0.9997F, 0.1491F, 1.21F}},
        {"design A/rare/s1", LfeIntent::Omit, {597, 8.00F, 0.8634F, 0.8978F, 0.9993F, 0.9995F, 0.1591F, 1.71F}},
        {"design A/rare/s2", LfeIntent::Omit, {597, 8.00F, 0.8655F, 0.8978F, 0.9996F, 0.9998F, 0.1491F, 0.33F}},
        {"design A/frequent/s0", LfeIntent::Omit, {597, 8.00F, 0.6756F, 0.4975F, 0.7951F, 0.9955F, 0.9631F, 3.86F}},
        {"design A/frequent/s1", LfeIntent::Omit, {597, 8.00F, 0.6751F, 0.5109F, 0.8243F, 0.9963F, 0.9162F, 4.98F}},
        {"design A/frequent/s2", LfeIntent::Omit, {597, 8.00F, 0.6761F, 0.5092F, 0.8086F, 0.9957F, 0.9414F, 3.83F}},
        {"design A/lfe_only/s0", LfeIntent::Include, {597, 78.00F, 0.0126F, 0.0000F, 0.0091F, 0.0581F, 1.0000F, 43.34F}},
        {"design A/lfe_only/s1", LfeIntent::Include, {597, -44.00F, 0.0123F, 0.0000F, 0.0101F, 0.0608F, 1.0000F, 48.80F}},
        {"design A/lfe_only/s2", LfeIntent::Include, {597, -22.00F, 0.0131F, 0.0000F, 0.0119F, 0.0645F, 1.0000F, 46.20F}},
        {"design A/hp_sub/s0", LfeIntent::Include, {597, 2.00F, 0.1248F, 0.0017F, 0.0767F, 0.2699F, 1.0000F, 36.60F}},
        {"design A/hp_sub/s1", LfeIntent::Include, {597, 2.00F, 0.1311F, 0.0017F, 0.0716F, 0.1896F, 1.0000F, 39.68F}},
        {"design A/hp_sub/s2", LfeIntent::Include, {597, 2.00F, 0.1265F, 0.0017F, 0.0662F, 0.2199F, 1.0000F, 35.29F}},
        {"design A/sub_layer/s0", LfeIntent::Include, {597, 20.00F, 0.1751F, 0.0017F, 0.0685F, 0.2153F, 1.0000F, -10.63F}},
        {"design A/sub_layer/s1", LfeIntent::Include, {597, 12.00F, 0.1910F, 0.0000F, 0.0796F, 0.2483F, 1.0000F, -16.06F}},
        {"design A/sub_layer/s2", LfeIntent::Include, {597, 12.00F, 0.1923F, 0.0017F, 0.0833F, 0.2399F, 1.0000F, -15.56F}},
        {"design A/silent/s0", LfeIntent::Omit, {0, 0.00F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.00F}},
        {"design A/silent/s1", LfeIntent::Omit, {0, 0.00F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.00F}},
        {"design A/silent/s2", LfeIntent::Omit, {0, 0.00F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.00F}},
        {"design A/noise62/s0", LfeIntent::Omit, {0, 0.00F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.00F}},
        {"design A/noise62/s1", LfeIntent::Omit, {0, 0.00F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.00F}},
        {"design A/noise62/s2", LfeIntent::Omit, {0, 0.00F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.0000F, 0.00F}},
        {"design B/A/s1", LfeIntent::Omit, {597, 8.00F, 0.9349F, 1.0000F, 1.0000F, 1.0000F, 0.0017F, -5.75F}},
        {"design B/B/s1", LfeIntent::Omit, {597, 8.00F, 0.6842F, 0.9045F, 0.9355F, 0.9777F, 0.8023F, -6.70F}},
        {"design B/B2/s1", LfeIntent::Omit, {597, 8.00F, 0.9025F, 1.0000F, 0.9904F, 0.9962F, 0.0151F, -6.86F}},
        {"design B/C/s1", LfeIntent::Omit, {597, 38.00F, 0.9349F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -5.75F}},
        {"design B/C2/s1", LfeIntent::Omit, {597, 22.00F, 0.9547F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.75F}},
        {"design B/D/s1", LfeIntent::Omit, {597, 50.00F, 0.5739F, 0.9983F, 0.9944F, 0.9986F, 0.0000F, -7.28F}},
        {"design B/E/s1", LfeIntent::Omit, {597, 8.00F, 0.9164F, 1.0000F, 0.9772F, 0.9861F, 0.0017F, -22.09F}},
        {"design B/F/s1", LfeIntent::Omit, {597, 8.00F, 0.8853F, 1.0000F, 0.9996F, 0.9998F, 0.0419F, -2.47F}},
        {"design B/G/s1", LfeIntent::Omit, {597, 8.00F, 0.9349F, 1.0000F, 1.0000F, 1.0000F, 0.0017F, -5.75F}},
        {"design B/H/s1", LfeIntent::Include, {597, -138.00F, 0.0311F, 0.0151F, 0.0300F, 0.2711F, 0.9832F, -17.08F}},
        {"design B/J/s1", LfeIntent::Omit, {597, 14.00F, 0.8049F, 1.0000F, 0.9951F, 0.9968F, 0.0017F, -2.56F}},
        {"design B/B1/s1", LfeIntent::Omit, {597, 8.00F, 0.6952F, 0.3886F, 0.7457F, 0.8484F, 1.0000F, -7.96F}},
        {"design B/C3/s1", LfeIntent::Omit, {597, 28.00F, 0.9355F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -5.73F}},
        {"design B/C4/s1", LfeIntent::Omit, {597, 30.00F, 0.9354F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -5.73F}},
        {"design B/C5/s1", LfeIntent::Omit, {597, 32.00F, 0.9546F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.73F}},
        {"design B/C6/s1", LfeIntent::Omit, {597, 22.00F, 0.9398F, 1.0000F, 1.0000F, 1.0000F, 0.0017F, -5.74F}},
        {"design B/C7/s1", LfeIntent::Omit, {597, 42.00F, 0.9414F, 1.0000F, 0.9998F, 0.9999F, 0.0017F, -5.72F}},
        {"design B/D6/s1", LfeIntent::Omit, {597, 70.00F, 0.4946F, 0.8559F, 0.9893F, 0.9973F, 0.0000F, -7.42F}},
        {"design B/F2/s1", LfeIntent::Omit, {597, 8.00F, 0.8241F, 0.9782F, 0.9993F, 0.9995F, 0.0603F, 0.32F}},
        {"design B/F3/s1", LfeIntent::Omit, {597, 8.00F, 0.8154F, 0.9899F, 0.9957F, 0.9979F, 0.2479F, -3.67F}},
        {"design B/J/s1", LfeIntent::Omit, {597, 8.00F, 0.8578F, 0.7705F, 0.8399F, 0.9024F, 1.0000F, -5.28F}},
        {"design B/J2/s1", LfeIntent::Include, {597, -38.00F, 0.0075F, 0.0000F, 0.0241F, 0.1413F, 1.0000F, -9.36F}},
        {"design B/A/s2", LfeIntent::Omit, {597, 8.00F, 0.9370F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -5.81F}},
        {"design B/B/s2", LfeIntent::Omit, {597, 8.00F, 0.6922F, 0.9430F, 0.9393F, 0.9761F, 0.7705F, -7.07F}},
        {"design B/B2/s2", LfeIntent::Omit, {597, 8.00F, 0.9034F, 1.0000F, 0.9914F, 0.9964F, 0.0000F, -6.97F}},
        {"design B/C/s2", LfeIntent::Omit, {597, 38.00F, 0.9370F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -5.81F}},
        {"design B/C2/s2", LfeIntent::Omit, {597, 22.00F, 0.9562F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.81F}},
        {"design B/D/s2", LfeIntent::Omit, {597, 50.00F, 0.5659F, 1.0000F, 0.9959F, 0.9985F, 0.0000F, -7.04F}},
        {"design B/E/s2", LfeIntent::Omit, {597, 8.00F, 0.9222F, 1.0000F, 0.9810F, 0.9873F, 0.0017F, -21.81F}},
        {"design B/F/s2", LfeIntent::Omit, {597, 8.00F, 0.8879F, 1.0000F, 0.9981F, 0.9990F, 0.0452F, -1.87F}},
        {"design B/G/s2", LfeIntent::Omit, {597, 8.00F, 0.9370F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -5.81F}},
        {"design B/H/s2", LfeIntent::Include, {597, -190.00F, 0.0303F, 0.0184F, 0.0211F, 0.1799F, 0.9799F, -15.61F}},
        {"design B/J/s2", LfeIntent::Omit, {597, 14.00F, 0.7988F, 1.0000F, 0.9954F, 0.9977F, 0.0017F, -2.34F}},
        {"design B/B1/s2", LfeIntent::Omit, {597, 8.00F, 0.6983F, 0.5946F, 0.8113F, 0.8676F, 1.0000F, -6.47F}},
        {"design B/C3/s2", LfeIntent::Omit, {597, 28.00F, 0.9374F, 1.0000F, 1.0000F, 1.0000F, 0.0017F, -5.76F}},
        {"design B/C4/s2", LfeIntent::Omit, {597, 30.00F, 0.9374F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -5.76F}},
        {"design B/C5/s2", LfeIntent::Omit, {597, 32.00F, 0.9552F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.76F}},
        {"design B/C6/s2", LfeIntent::Omit, {597, 22.00F, 0.9417F, 1.0000F, 1.0000F, 1.0000F, 0.0017F, -5.77F}},
        {"design B/C7/s2", LfeIntent::Omit, {597, 42.00F, 0.9408F, 1.0000F, 0.9998F, 0.9999F, 0.0017F, -5.75F}},
        {"design B/D6/s2", LfeIntent::Omit, {597, 70.00F, 0.4721F, 0.8308F, 0.9909F, 0.9973F, 0.0000F, -6.34F}},
        {"design B/F2/s2", LfeIntent::Omit, {597, 8.00F, 0.8260F, 0.9799F, 0.9995F, 0.9996F, 0.0469F, 0.25F}},
        {"design B/F3/s2", LfeIntent::Omit, {597, 8.00F, 0.8150F, 0.9916F, 0.9996F, 0.9998F, 0.0519F, -4.87F}},
        {"design B/J/s2", LfeIntent::Omit, {597, 8.00F, 0.8648F, 0.8576F, 0.8516F, 0.8984F, 1.0000F, -5.75F}},
        {"design B/J2/s2", LfeIntent::Include, {597, 104.00F, 0.0096F, 0.0000F, 0.0312F, 0.1251F, 1.0000F, -5.81F}},
        {"design B/A/s3", LfeIntent::Omit, {597, 8.00F, 0.9342F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.70F}},
        {"design B/B/s3", LfeIntent::Omit, {597, 8.00F, 0.6766F, 0.9849F, 0.9389F, 0.9743F, 0.7822F, -7.19F}},
        {"design B/B2/s3", LfeIntent::Omit, {597, 8.00F, 0.8996F, 1.0000F, 0.9911F, 0.9961F, 0.0000F, -7.06F}},
        {"design B/C/s3", LfeIntent::Omit, {597, 38.00F, 0.9342F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.69F}},
        {"design B/C2/s3", LfeIntent::Omit, {597, 22.00F, 0.9544F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.70F}},
        {"design B/D/s3", LfeIntent::Omit, {597, 50.00F, 0.5301F, 0.9983F, 0.9958F, 0.9987F, 0.0000F, -7.08F}},
        {"design B/E/s3", LfeIntent::Omit, {597, 8.00F, 0.9224F, 1.0000F, 0.9840F, 0.9881F, 0.0017F, -21.66F}},
        {"design B/F/s3", LfeIntent::Omit, {597, 8.00F, 0.8848F, 1.0000F, 0.9996F, 0.9997F, 0.0369F, -2.38F}},
        {"design B/G/s3", LfeIntent::Omit, {597, 8.00F, 0.9342F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.70F}},
        {"design B/H/s3", LfeIntent::Include, {597, -136.00F, 0.0029F, 0.0000F, 0.0274F, 0.1428F, 1.0000F, -20.09F}},
        {"design B/J/s3", LfeIntent::Omit, {597, 14.00F, 0.7947F, 1.0000F, 0.9958F, 0.9973F, 0.0017F, -2.44F}},
        {"design B/B1/s3", LfeIntent::Omit, {597, 8.00F, 0.6809F, 0.4422F, 0.7945F, 0.8832F, 1.0000F, -5.55F}},
        {"design B/C3/s3", LfeIntent::Omit, {597, 28.00F, 0.9343F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.62F}},
        {"design B/C4/s3", LfeIntent::Omit, {597, 30.00F, 0.9342F, 1.0000F, 0.9999F, 1.0000F, 0.0017F, -5.62F}},
        {"design B/C5/s3", LfeIntent::Omit, {597, 32.00F, 0.9551F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -5.62F}},
        {"design B/C6/s3", LfeIntent::Omit, {597, 22.00F, 0.9380F, 1.0000F, 1.0000F, 1.0000F, 0.0017F, -5.63F}},
        {"design B/C7/s3", LfeIntent::Omit, {597, 42.00F, 0.9387F, 1.0000F, 0.9998F, 0.9999F, 0.0017F, -5.61F}},
        {"design B/D6/s3", LfeIntent::Omit, {597, 70.00F, 0.4668F, 0.8476F, 0.9862F, 0.9975F, 0.0017F, -6.34F}},
        {"design B/F2/s3", LfeIntent::Omit, {597, 8.00F, 0.8235F, 0.9849F, 0.9991F, 0.9994F, 0.0519F, 0.44F}},
        {"design B/F3/s3", LfeIntent::Omit, {597, 8.00F, 0.8126F, 0.9933F, 0.9990F, 0.9993F, 0.0486F, -4.68F}},
        {"design B/J/s3", LfeIntent::Omit, {597, 8.00F, 0.8583F, 0.8710F, 0.8460F, 0.8960F, 1.0000F, -1.73F}},
        {"design B/J2/s3", LfeIntent::Include, {597, -60.00F, 0.0150F, 0.0000F, 0.0117F, 0.0821F, 1.0000F, -13.41F}},
        {"design C/derived copy/s7", LfeIntent::Omit, {597, 10.00F, 0.8341F, 1.0000F, 0.9964F, 0.9973F, 0.0017F, -7.15F}},
        {"design C/independent sub layer/s7", LfeIntent::Include, {597, -100.00F, 0.0286F, 0.0000F, 0.0186F, 0.0918F, 1.0000F, -21.28F}},
        {"design C/copy + booms (1 per 1.5 s)/s7", LfeIntent::Omit, {597, 10.00F, 0.6587F, 0.4807F, 0.7798F, 0.9910F, 0.6918F, -6.63F}},
        {"design C/copy, automated send 0.3-1.0/s7", LfeIntent::Omit, {597, 10.00F, 0.7929F, 0.9983F, 0.9959F, 0.9969F, 0.0034F, -11.11F}},
        {"design C/mains HP 100 + bass in LFE/s7", LfeIntent::Include, {597, 4.00F, 0.4169F, 0.9966F, 0.9822F, 0.9898F, 1.0000F, 38.22F}},
        {"design C/derived copy/s8", LfeIntent::Omit, {597, 10.00F, 0.8318F, 1.0000F, 0.9963F, 0.9972F, 0.0017F, -7.18F}},
        {"design C/independent sub layer/s8", LfeIntent::Include, {597, 58.00F, 0.0287F, 0.0000F, 0.0162F, 0.1012F, 1.0000F, -22.95F}},
        {"design C/copy + booms (1 per 1.5 s)/s8", LfeIntent::Omit, {597, 10.00F, 0.6556F, 0.4791F, 0.7747F, 0.9909F, 0.7002F, -6.49F}},
        {"design C/copy, automated send 0.3-1.0/s8", LfeIntent::Omit, {597, 10.00F, 0.7815F, 0.9983F, 0.9957F, 0.9968F, 0.0000F, -11.62F}},
        {"design C/mains HP 100 + bass in LFE/s8", LfeIntent::Include, {597, 4.00F, 0.4184F, 0.9966F, 0.9818F, 0.9899F, 1.0000F, 38.17F}},
        {"design C/derived copy/s9", LfeIntent::Omit, {597, 10.00F, 0.8252F, 1.0000F, 0.9961F, 0.9972F, 0.0017F, -7.17F}},
        {"design C/independent sub layer/s9", LfeIntent::Include, {597, 2.00F, 0.0248F, 0.0000F, 0.0169F, 0.0886F, 1.0000F, -22.65F}},
        {"design C/copy + booms (1 per 1.5 s)/s9", LfeIntent::Omit, {597, 10.00F, 0.6471F, 0.4757F, 0.7726F, 0.9930F, 0.6801F, -7.08F}},
        {"design C/copy, automated send 0.3-1.0/s9", LfeIntent::Omit, {597, 10.00F, 0.8013F, 0.9983F, 0.9958F, 0.9969F, 0.0017F, -12.13F}},
        {"design C/mains HP 100 + bass in LFE/s9", LfeIntent::Include, {597, 4.00F, 0.4218F, 0.9966F, 0.9819F, 0.9897F, 1.0000F, 38.19F}},
        {"verify plain LR4 copy of L+R+C/s1", LfeIntent::Omit, {397, 4.00F, 0.9898F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.31F}},
        {"verify copy at +10 dB (film-level copy)/s1", LfeIntent::Omit, {397, 4.00F, 0.9898F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 9.69F}},
        {"verify polarity-inverted copy/s1", LfeIntent::Omit, {397, 4.00F, 0.9898F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.31F}},
        {"verify copy delayed 25 ms/s1", LfeIntent::Omit, {397, 30.00F, 0.9196F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.27F}},
        {"verify copy delayed 38 ms/s1", LfeIntent::Omit, {397, 42.00F, 0.9897F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.26F}},
        {"verify linear-phase 4095-tap copy (43 ms)/s1", LfeIntent::Omit, {397, 42.00F, 0.9576F, 1.0000F, 0.9999F, 0.9999F, 0.0000F, 0.01F}},
        {"verify automated send -6/0/+6 dB/s1", LfeIntent::Omit, {397, 4.00F, 0.9627F, 1.0000F, 0.9988F, 0.9995F, 0.3249F, 4.78F}},
        {"verify 6 tandem BW4 LPF at 50 Hz/s1", LfeIntent::Omit, {397, 70.00F, 0.5263F, 1.0000F, 0.9715F, 0.9932F, 0.0000F, 1.23F}},
        {"verify independent 31 Hz sub swells (quiet)/s1", LfeIntent::Either, {168, -144.00F, 0.0037F, 0.0000F, 0.0255F, 0.1546F, 0.1369F, -3.95F}},
        {"verify independent 31 Hz sub swells (strong)/s1", LfeIntent::KnownIssue, {377, -144.00F, 0.0037F, 0.0000F, 0.0249F, 0.1520F, 0.4111F, 10.03F}},
        {"verify rhythm-following 33 Hz sub/s1", LfeIntent::Include, {397, -12.00F, 0.0052F, 0.0000F, 0.0259F, 0.1372F, 1.0000F, -3.69F}},
        {"verify octave-down sub (bass envelope)/s1", LfeIntent::Include, {397, -80.00F, 0.0041F, 0.0000F, 0.0278F, 0.1398F, 1.0000F, -13.79F}},
        {"verify redirected bass, mains LR4 HP 100 Hz/s1", LfeIntent::Include, {397, 0.00F, 0.6200F, 1.0000F, 0.9996F, 0.9998F, 0.7960F, 23.66F}},
        {"verify redirected bass, mains BW2 HP 80 Hz/s1", LfeIntent::Include, {397, 0.00F, 0.7954F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, 20.22F}},
        {"verify redirected bass, mains BW2 HP 60 Hz/s1", LfeIntent::KnownIssue, {397, 0.00F, 0.9127F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 14.80F}},
        {"verify kick-stem copy, panned alike/s1", LfeIntent::Omit, {397, 4.00F, 0.7040F, 0.0378F, 0.5971F, 0.7388F, 1.0000F, -9.36F}},
        {"kick sweep kick-stem copy, kick +3 dB (low band +3.1 dB re bass)/s1", LfeIntent::Omit, {397, 4.00F, 0.8125F, 0.1738F, 0.7262F, 0.8304F, 1.0000F, -7.40F}},
        {"kick sweep kick-stem copy, kick +0 dB (low band +0.1 dB re bass)/s1", LfeIntent::Omit, {397, 4.00F, 0.7040F, 0.0378F, 0.5971F, 0.7388F, 1.0000F, -9.36F}},
        {"kick sweep kick-stem copy, kick -3 dB (low band -2.9 dB re bass)/s1", LfeIntent::Omit, {397, 4.00F, 0.5743F, 0.0101F, 0.4478F, 0.6570F, 1.0000F, -7.80F}},
        {"kick sweep kick-stem copy, kick -6 dB (low band -5.9 dB re bass)/s1", LfeIntent::Omit, {397, 4.00F, 0.4435F, 0.0000F, 0.3277F, 0.5734F, 1.0000F, -8.31F}},
        {"kick sweep kick-stem copy, kick -10 dB (low band -9.9 dB re bass)/s1", LfeIntent::KnownIssue, {397, 4.00F, 0.2952F, 0.0000F, 0.1775F, 0.4352F, 1.0000F, -12.03F}},
        {"kick sweep kick-stem copy, kick -14 dB (low band -13.9 dB re bass)/s1", LfeIntent::KnownIssue, {397, 4.00F, 0.1881F, 0.0000F, 0.0850F, 0.2913F, 0.9849F, -17.64F}},
        {"verify plain LR4 copy of L+R+C/s2", LfeIntent::Omit, {397, 4.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.27F}},
        {"verify copy at +10 dB (film-level copy)/s2", LfeIntent::Omit, {397, 4.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 9.73F}},
        {"verify polarity-inverted copy/s2", LfeIntent::Omit, {397, 4.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.27F}},
        {"verify copy delayed 25 ms/s2", LfeIntent::Omit, {397, 30.00F, 0.9173F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.29F}},
        {"verify copy delayed 38 ms/s2", LfeIntent::Omit, {397, 42.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.29F}},
        {"verify linear-phase 4095-tap copy (43 ms)/s2", LfeIntent::Omit, {397, 42.00F, 0.9562F, 1.0000F, 0.9999F, 0.9999F, 0.0000F, 0.01F}},
        {"verify automated send -6/0/+6 dB/s2", LfeIntent::Omit, {397, 4.00F, 0.9617F, 1.0000F, 0.9992F, 0.9995F, 0.2141F, 4.22F}},
        {"verify 6 tandem BW4 LPF at 50 Hz/s2", LfeIntent::Omit, {397, 70.00F, 0.4966F, 1.0000F, 0.9688F, 0.9854F, 0.0000F, 1.20F}},
        {"verify independent 31 Hz sub swells (quiet)/s2", LfeIntent::Either, {164, -124.00F, 0.0041F, 0.0000F, 0.0368F, 0.1946F, 0.1220F, -8.34F}},
        {"verify independent 31 Hz sub swells (strong)/s2", LfeIntent::KnownIssue, {360, -124.00F, 0.0041F, 0.0000F, 0.0285F, 0.1632F, 0.4056F, 5.64F}},
        {"verify rhythm-following 33 Hz sub/s2", LfeIntent::Include, {397, -6.00F, 0.0051F, 0.0000F, 0.0314F, 0.1291F, 1.0000F, -5.58F}},
        {"verify octave-down sub (bass envelope)/s2", LfeIntent::Include, {397, 36.00F, 0.0043F, 0.0000F, 0.0361F, 0.1891F, 1.0000F, -8.11F}},
        {"verify redirected bass, mains LR4 HP 100 Hz/s2", LfeIntent::Include, {397, 0.00F, 0.6343F, 1.0000F, 0.9995F, 0.9997F, 0.8615F, 23.89F}},
        {"verify redirected bass, mains BW2 HP 80 Hz/s2", LfeIntent::Include, {397, 0.00F, 0.8054F, 1.0000F, 0.9999F, 1.0000F, 0.0025F, 19.99F}},
        {"verify redirected bass, mains BW2 HP 60 Hz/s2", LfeIntent::KnownIssue, {397, 0.00F, 0.9207F, 1.0000F, 1.0000F, 1.0000F, 0.0025F, 14.68F}},
        {"verify kick-stem copy, panned alike/s2", LfeIntent::Omit, {397, 4.00F, 0.7023F, 0.0202F, 0.5605F, 0.7316F, 1.0000F, -8.10F}},
        {"kick sweep kick-stem copy, kick +3 dB (low band +2.9 dB re bass)/s2", LfeIntent::Omit, {397, 4.00F, 0.8087F, 0.1587F, 0.7033F, 0.8175F, 1.0000F, -7.53F}},
        {"kick sweep kick-stem copy, kick +0 dB (low band -0.1 dB re bass)/s2", LfeIntent::Omit, {397, 4.00F, 0.7023F, 0.0202F, 0.5605F, 0.7316F, 1.0000F, -8.10F}},
        {"kick sweep kick-stem copy, kick -3 dB (low band -3.1 dB re bass)/s2", LfeIntent::Omit, {397, 4.00F, 0.5771F, 0.0050F, 0.4188F, 0.6190F, 1.0000F, -7.54F}},
        {"kick sweep kick-stem copy, kick -6 dB (low band -6.1 dB re bass)/s2", LfeIntent::Omit, {397, 4.00F, 0.4521F, 0.0000F, 0.2909F, 0.4908F, 1.0000F, -9.47F}},
        {"kick sweep kick-stem copy, kick -10 dB (low band -10.1 dB re bass)/s2", LfeIntent::KnownIssue, {397, 4.00F, 0.3109F, 0.0000F, 0.1627F, 0.3149F, 1.0000F, -14.42F}},
        {"kick sweep kick-stem copy, kick -14 dB (low band -14.1 dB re bass)/s2", LfeIntent::KnownIssue, {397, 4.00F, 0.2087F, 0.0000F, 0.0818F, 0.2211F, 0.9798F, -20.68F}},
        {"verify plain LR4 copy of L+R+C/s3", LfeIntent::Omit, {397, 4.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.33F}},
        {"verify copy at +10 dB (film-level copy)/s3", LfeIntent::Omit, {397, 4.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, 9.67F}},
        {"verify polarity-inverted copy/s3", LfeIntent::Omit, {397, 4.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.33F}},
        {"verify copy delayed 25 ms/s3", LfeIntent::Omit, {397, 30.00F, 0.9192F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.33F}},
        {"verify copy delayed 38 ms/s3", LfeIntent::Omit, {397, 42.00F, 0.9896F, 1.0000F, 1.0000F, 1.0000F, 0.0000F, -0.32F}},
        {"verify linear-phase 4095-tap copy (43 ms)/s3", LfeIntent::Omit, {397, 42.00F, 0.9575F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, -0.05F}},
        {"verify automated send -6/0/+6 dB/s3", LfeIntent::Omit, {397, 4.00F, 0.9627F, 1.0000F, 0.9993F, 0.9996F, 0.0076F, -1.53F}},
        {"verify 6 tandem BW4 LPF at 50 Hz/s3", LfeIntent::Omit, {397, 70.00F, 0.5320F, 1.0000F, 0.9682F, 0.9896F, 0.0000F, 1.42F}},
        {"verify independent 31 Hz sub swells (quiet)/s3", LfeIntent::Either, {241, -166.00F, 0.0046F, 0.0000F, 0.0261F, 0.1463F, 0.0788F, -6.87F}},
        {"verify independent 31 Hz sub swells (strong)/s3", LfeIntent::KnownIssue, {380, -166.00F, 0.0046F, 0.0000F, 0.0259F, 0.1488F, 0.6158F, 7.11F}},
        {"verify rhythm-following 33 Hz sub/s3", LfeIntent::Include, {397, 0.00F, 0.0078F, 0.0000F, 0.0260F, 0.1531F, 1.0000F, -1.01F}},
        {"verify octave-down sub (bass envelope)/s3", LfeIntent::Include, {397, 56.00F, 0.0051F, 0.0000F, 0.0419F, 0.2027F, 1.0000F, -6.83F}},
        {"verify redirected bass, mains LR4 HP 100 Hz/s3", LfeIntent::Include, {397, 0.00F, 0.6192F, 1.0000F, 0.9995F, 0.9997F, 0.9068F, 23.52F}},
        {"verify redirected bass, mains BW2 HP 80 Hz/s3", LfeIntent::Include, {397, 0.00F, 0.7949F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, 20.85F}},
        {"verify redirected bass, mains BW2 HP 60 Hz/s3", LfeIntent::KnownIssue, {397, 0.00F, 0.9129F, 1.0000F, 0.9999F, 1.0000F, 0.0000F, 15.20F}},
        {"verify kick-stem copy, panned alike/s3", LfeIntent::Omit, {397, 4.00F, 0.6720F, 0.0076F, 0.5095F, 0.6758F, 1.0000F, -7.13F}},
        {"kick sweep kick-stem copy, kick +3 dB (low band +2.5 dB re bass)/s3", LfeIntent::Omit, {397, 4.00F, 0.7878F, 0.0856F, 0.6684F, 0.7922F, 1.0000F, -8.22F}},
        {"kick sweep kick-stem copy, kick +0 dB (low band -0.5 dB re bass)/s3", LfeIntent::Omit, {397, 4.00F, 0.6720F, 0.0076F, 0.5095F, 0.6758F, 1.0000F, -7.13F}},
        {"kick sweep kick-stem copy, kick -3 dB (low band -3.5 dB re bass)/s3", LfeIntent::Omit, {397, 4.00F, 0.5389F, 0.0000F, 0.3583F, 0.5351F, 1.0000F, -7.77F}},
        {"kick sweep kick-stem copy, kick -6 dB (low band -6.5 dB re bass)/s3", LfeIntent::Omit, {397, 4.00F, 0.4092F, 0.0000F, 0.2294F, 0.4173F, 1.0000F, -10.49F}},
        {"kick sweep kick-stem copy, kick -10 dB (low band -10.5 dB re bass)/s3", LfeIntent::KnownIssue, {397, 4.00F, 0.2664F, 0.0000F, 0.1157F, 0.2825F, 1.0000F, -15.98F}},
        {"kick sweep kick-stem copy, kick -14 dB (low band -14.5 dB re bass)/s3", LfeIntent::KnownIssue, {397, 4.00F, 0.1651F, 0.0000F, 0.0561F, 0.1909F, 0.9698F, -22.32F}},
    });

    auto lfeVerdictName(AsLfeVerdict verdict) -> const char*
    {
        switch (verdict)
        {
            case AsLfeVerdictOmitUnknown:
                return "omit (unknown)";
            case AsLfeVerdictOmitCopy:
                return "omit (copy)";
            case AsLfeVerdictIncludeRedirected:
                return "include (redirected)";
            case AsLfeVerdictIncludeIndependent:
                return "include (independent)";
            case AsLfeVerdictOmitUncertain:
                return "omit (neither)";
        }
        return "?";
    }

    auto lfeCaseLine(const LfeRuleCase& each, AsLfeVerdict verdict) -> std::string
    {
        const AsLfeStats& stats = each.stats;
        return std::format("{} -> {} (medianR2 {:.2f}, p90R2 {:.2f}, coherent {:.2f}, excess20 {:.2f}, lagPeak {:.2f}, "
                           "explainGain {:+.1f} dB)",
                           each.name, lfeVerdictName(verdict), stats.medianR2, stats.p90R2, stats.coherentShare,
                           stats.excess20Share, stats.lagPeak, stats.explainGainDb);
    }

    auto lfeStats(uint32_t active, float medianR2, float p90R2, float coherent, float excess20, float lagPeak,
                  float explainGainDb) -> AsLfeStats
    {
        AsLfeStats stats{};
        stats.activeBlocks = active;
        stats.medianR2 = medianR2;
        stats.p90R2 = p90R2;
        stats.coherentShare = coherent;
        stats.excess20Share = excess20;
        stats.lagPeak = lagPeak;
        stats.explainGainDb = explainGainDb;
        return stats;
    }
} // namespace

// ---------------------------------------------------------------------------
// LfeRule_MeasuredCases — §5's table and C4: every measured case with an intent decides it; the known limits are
// logged with their statistics.
// ---------------------------------------------------------------------------
static auto testLfeRuleMeasuredCases() -> void
{
    static const char* const kName = "LfeRule_MeasuredCases";
    std::string fail;
    uint32_t decided = 0U;
    uint32_t logged = 0U;
    for (const LfeRuleCase& each : kLfeRuleCases)
    {
        const AsLfeVerdict verdict = foldDecideLfe(each.stats);
        const bool includes = lfeVerdictIncludes(verdict);
        switch (each.intent)
        {
            case LfeIntent::Omit:
            case LfeIntent::Include:
                ++decided;
                if (includes != (each.intent == LfeIntent::Include))
                {
                    fail += "\n  " + lfeCaseLine(each, verdict);
                }
                break;
            case LfeIntent::Either:
                break;
            case LfeIntent::KnownIssue:
                ++logged;
                logInfo(std::format("{}: known limit: {}", kName, lfeCaseLine(each, verdict)));
                break;
        }
    }
    logInfo(std::format("{}: {} cases decided as intended, {} known limits logged", kName, decided, logged));
    if (!fail.empty())
    {
        logFail(kName, "decided against their intent:" + fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// LfeRule_KickBalanceSweep — C4: a kick-stem copy (kick and bass panned alike) is omitted with the kick down to
// 6 dB under the bass, on every seed — the p90 r² gate; under that it is a known limit (logged).
// ---------------------------------------------------------------------------
static auto testLfeRuleKickBalanceSweep() -> void
{
    static const char* const kName = "LfeRule_KickBalanceSweep";
    std::string fail;
    uint32_t swept = 0U;
    for (const LfeRuleCase& each : kLfeRuleCases)
    {
        if (!std::string_view(each.name).starts_with("kick sweep"))
        {
            continue;
        }
        ++swept;
        const AsLfeVerdict verdict = foldDecideLfe(each.stats);
        if (each.intent == LfeIntent::Omit && lfeVerdictIncludes(verdict))
        {
            fail += "\n  " + lfeCaseLine(each, verdict);
        }
        logInfo(std::format("{}: {}", kName, lfeCaseLine(each, verdict)));
    }
    if (swept != 18U)
    {
        fail += std::format("\n  the sweep has {} cases, not 6 balances x 3 seeds", swept);
    }
    if (!fail.empty())
    {
        logFail(kName, "a stem copy included:" + fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// LfeRule_RedirectedBass — C4: bass moved out of high-passed mains into the LFE is included behind a 100 Hz LR4
// and an 80 Hz BW2 high-pass; the 60 Hz BW2 case sits on the +15 dB line and is logged.
// ---------------------------------------------------------------------------
static auto testLfeRuleRedirectedBass() -> void
{
    static const char* const kName = "LfeRule_RedirectedBass";
    std::string fail;
    uint32_t seen = 0U;
    for (const LfeRuleCase& each : kLfeRuleCases)
    {
        const std::string_view name(each.name);
        if (!name.starts_with("verify redirected bass"))
        {
            continue;
        }
        ++seen;
        const AsLfeVerdict verdict = foldDecideLfe(each.stats);
        logInfo(std::format("{}: {}", kName, lfeCaseLine(each, verdict)));
        if (each.intent == LfeIntent::Include && verdict != AsLfeVerdictIncludeRedirected)
        {
            fail += "\n  " + lfeCaseLine(each, verdict);
        }
    }
    if (seen != 9U)
    {
        fail += std::format("\n  {} redirected-bass cases, not 3 high-passes x 3 seeds", seen);
    }
    if (!fail.empty())
    {
        logFail(kName, "redirected bass not included:" + fail);
        return;
    }
    logPass(kName);
}

// ---------------------------------------------------------------------------
// LfeRule_Thresholds — each threshold decides on its own side: 50 active blocks; the copy tests (medianR2 0.5,
// coherentShare 0.4, lagPeak 0.8); explainGain +15 dB; rule 4's coherentShare 0.2, excess20 0.5, p90R2 0.3.
// ---------------------------------------------------------------------------
static auto testLfeRuleThresholds() -> void
{
    static const char* const kName = "LfeRule_Thresholds";
    struct Edge
    {
        const char* what;
        AsLfeStats stats;
        AsLfeVerdict expected;
    };
    // An independent layer clear of every line, and a copy clear of every line, each moved onto one line.
    const AsLfeStats independent = lfeStats(200U, 0.05F, 0.1F, 0.0F, 1.0F, 0.1F, -10.0F);
    const AsLfeStats copy = lfeStats(200U, 1.0F, 1.0F, 1.0F, 0.0F, 0.95F, 0.0F);
    const auto with = [](AsLfeStats stats, auto change)
    {
        change(stats);
        return stats;
    };
    const auto edge = [](const char* what, AsLfeStats stats, AsLfeVerdict expected)
    { return Edge{.what = what, .stats = stats, .expected = expected}; };
    const std::array edges{
        edge("49 active blocks", with(independent, [](AsLfeStats& s) { s.activeBlocks = 49U; }), AsLfeVerdictOmitUnknown),
        edge("50 active blocks", with(independent, [](AsLfeStats& s) { s.activeBlocks = 50U; }),
             AsLfeVerdictIncludeIndependent),
        edge("medianR2 0.5 is copy-like", with(independent, [](AsLfeStats& s) { s.medianR2 = 0.5F; }),
             AsLfeVerdictOmitCopy),
        edge("coherentShare 0.4 is copy-like", with(independent, [](AsLfeStats& s) { s.coherentShare = 0.4F; }),
             AsLfeVerdictOmitCopy),
        edge("lagPeak 0.8 is copy-like", with(independent, [](AsLfeStats& s) { s.lagPeak = 0.8F; }),
             AsLfeVerdictOmitCopy),
        edge("a copy at explainGain +15 dB", with(copy, [](AsLfeStats& s) { s.explainGainDb = 15.0F; }),
             AsLfeVerdictOmitCopy),
        edge("a copy over +15 dB", with(copy, [](AsLfeStats& s) { s.explainGainDb = 15.01F; }),
             AsLfeVerdictIncludeRedirected),
        edge("coherentShare 0.2 is not independent", with(independent, [](AsLfeStats& s) { s.coherentShare = 0.2F; }),
             AsLfeVerdictOmitUncertain),
        edge("excess20 under 0.5", with(independent, [](AsLfeStats& s) { s.excess20Share = 0.49F; }),
             AsLfeVerdictOmitUncertain),
        edge("p90R2 0.3 (C4) is not independent", with(independent, [](AsLfeStats& s) { s.p90R2 = 0.3F; }),
             AsLfeVerdictOmitUncertain),
        edge("p90R2 just under 0.3", with(independent, [](AsLfeStats& s) { s.p90R2 = 0.299F; }),
             AsLfeVerdictIncludeIndependent),
        edge("a NaN statistic", with(copy, [](AsLfeStats& s) { s.explainGainDb = std::numeric_limits<float>::quiet_NaN(); }),
             AsLfeVerdictOmitUnknown),
        edge("an infinite statistic", with(independent, [](AsLfeStats& s) { s.p90R2 = -std::numeric_limits<float>::infinity(); }),
             AsLfeVerdictOmitUnknown),
    };
    std::string fail;
    for (const Edge& each : edges)
    {
        const AsLfeVerdict got = foldDecideLfe(each.stats);
        if (got != each.expected)
        {
            fail += std::format("\n  {}: {}, expected {}", each.what, lfeVerdictName(got), lfeVerdictName(each.expected));
        }
    }
    // The C entry: the same verdicts, NULL as unknown.
    if (asFoldDecideLfe(&copy) != AsLfeVerdictOmitCopy || asFoldDecideLfe(nullptr) != AsLfeVerdictOmitUnknown ||
        !asLfeVerdictIncludes(asFoldDecideLfe(&independent)) || asLfeVerdictIncludes(AsLfeVerdictOmitUncertain))
    {
        fail += "\n  the C entry disagrees with the rule";
    }
    if (!fail.empty())
    {
        logFail(kName, fail);
        return;
    }
    logPass(kName);
}
