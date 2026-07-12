# QW1 — Quick-Win Differentiators: Sprint Design

**Document ID:** QW1-DESIGN-001
**Version:** 0.2 — team-reviewed; **architect verdict: GO-WITH-CHANGES** (all required changes applied, §9).
**Status:** ✅ SHIPPED (QW1) — design record (crossfeed DSP + UI, Reimagine-intensity UI, tonal presets). Founder by-ear verification still pending. Inserted as a one-off **exception** in [sprint-plan.md](sprint-plan.md): a differentiator burst before resuming the maturity arc at S8 (founder decision 2026-06-19).
**Authored by:** AdaptiveSound team — audio-dsp-agent (crossfeed DSP), modern-cplus-plus-expert (C++ integration), swiftui-pro (UI/UX); test strategy by qa-expert (§7); structure review by refactoring-specialist (§8); **final verdict by architect-reviewer (§9)**.

---

## 1. Strategic frame

The founder's call: make an **exception** to the maturity-first arc and ship a few **quick-win differentiators now**, then resume the maturity arc at S8. Rationale: S6 over-delivered — the **control-plane Realizer** and the **steerable equal-power wet/dry intensity** primitive already exist — so these are mostly "wire + one small DSP stage," not new infrastructure.

**Three deliverables, each leaning on the S6 spine:**
- **QW-A — Reimagine intensity knob** (the signature steerable control; kernel + `publishIntensity` C-ABI already shipped → UI wiring only).
- **QW-B — Tonal presets / house curves** (curated EQ curves via the already-live 31-band EQ → `publishEQGains`).
- **QW-C — Crossfeed** (a real headphone-soundstage DSP stage in the wet region, scaled by the Reimagine knob).

**The unifying idea:** the Reimagine knob = "how much of ALL the enhancement" (EQ + presets + crossfeed) is blended in. At 0 % it's the bit-perfect bypass anchor (everything off); rising blends the wet, enhanced chain. That *is* the Adaptive Sound thesis in miniature, demoable now.

---

## 2. Crossfeed — DSP design (audio-dsp lens)

**Algorithm (Bauer / bs2b, Linkwitz 1971; reference: bs2b 3.1.0).** Symmetrical stereo crossfeed: each channel is fed into the other through a **one-pole low-pass** (cross path only) + a small **inter-aural delay (ITD ≈ 0.318 ms)** + attenuation, restoring the natural cross-path headphones remove. Direct path is unfiltered/undelayed.

```
Lout = g_direct·L + g_cross·H(z)·z^−D·R
Rout = g_direct·R + g_cross·H(z)·z^−D·L
```

- **One-pole LPF (exact-RC form, recomputed per sample rate):** `p = exp(−2π·fc/fs)`, `y[n] = (1−p)·x[n] + p·y[n−1]`. Single first-order section (3 coeffs), **not** a biquad — scalar per-sample, no `vDSP_biquad`.
- **Gain-neutral:** `g_direct = 1/(1+α)`, `g_cross = α/(1+α)` → mono (L=R) sum is unity (loudness-neutral). Downstream Loudness absorbs any residual.
- **ITD:** `delayFrames = round(0.0003178·fs)` (14 @ 44.1 k, 15 @ 48 k; ≤ 61 @ 192 k). Fixed `std::array<float, 64>` delay line per cross path covers all supported rates (`assert delayFrames < 64`).
- **Stereo-only:** `channels() != 2` → pass-through (untouched).

**User-facing presets** (names from the UI lens; coefficients from bs2b):

| UI name | fc (Hz) | cross-level (dB / α) | character |
|---|---|---|---|
| **Relaxed** | 650 | −9.5 / 0.335 | subtlest (bs2b "Jmeier") |
| **Default** | 700 | −9.0 / 0.355 | Bauer original — the safe default |
| **Strong** | 700 | −6.0 / 0.501 | most spacious (bs2b "Cmoy") |

**Chain placement: in the wet region, adjacent to BRIR's slot** → `EQ → Clarity → Crossfeed → BRIR → [intensity blend] → Loudness → Limiter`. Rationale (architect-corrected): crossfeed must be in the wet/coloration region (before the blend, so **the Reimagine knob scales it** — intended) and before Loudness+Limiter (so the limiter stays the last guard and loudness measures what's heard). The crossfeed-vs-BRIR *order* is moot because **crossfeed and a future binaural BRIR are mutually exclusive** (both synthesize the head-related cross-path; running both would double-apply) — crossfeed sits next to BRIR's slot purely for locality, not because it "preserves BRIR's ITD" (it would in fact blur it; they simply never run together).

> **Invariant (record now; enforce at S18):** crossfeed and binaural BRIR are mutually-exclusive output-rendering modes; the control layer (Realizer/VM) must never enable both. No arbitration code in QW1 (`BRIRModule` is an empty stub — nothing to arbitrate). When S18 BRIR ships, treat `crossfeed.enabled && brir.active` as a control-layer bug and deterministically prefer one (document which).

**Known DSP risks (flagged):** (1) mild mono LPF coloration (~+1.3 dB <fc) — inherent to crossfeed, benign, headphone-gated; (2) the **read-both-then-write-both** trap (compute newL/newR from current L/R before writing either — the #1 crossfeed implementation bug); (3) recompute coeffs on sample-rate change (same trigger as EQ); (4) **do NOT link the LGPL bs2b library** — implement the ~20 lines of math from first principles.

**Headphone gating + Pure path:** crossfeed is Enhanced-path-only (Pure bypasses the kernel entirely → automatically absent). Active only on headphones; speakers → transparent. Decision rule lives in the control layer (see §6). Default **off** → golden master unchanged.

---

## 3. Crossfeed — C++ integration (modern-C++ lens)

- **`CrossfeedModule`** (`Sources/AudioDSP/Spatial/CrossfeedModule.h/.mm`) — house `initialize(sr,maxFrames)` / `process(const CrossfeedParams&, MultichannelView&)` shape (mirrors `EQModule`; all copy/move deleted, named params). Pre-allocated per-path delay line + one-pole state + a `ParameterRamp mixRamp_` (32 ms τ) for click-free enable/level; `mixRamp_.snap()` to the initial (off) value in `initialize()`. Top-of-`process` early return on `enabled==0 || channels()!=2` → **bit-exact pass-through**. No RT allocation.
- **`CrossfeedParams` POD** added to `TargetState` (between `brir` and `limiter`). **Concrete layout (F2 — protects the golden master):** intent fields `uint8_t enabled = 0; uint8_t preset = 0; std::array<uint8_t,2> _pad = {};` then derived (off-RT computed) `float gDirect = 1.0F; float gCross = 0.0F; float lpfB0 = 0.0F; float lpfPole = 0.0F; int32_t delayFrames = 0;` — all trivial, every field explicitly defaulted so `canonical_{}` zero/identity-inits to "off". The two `TargetState` static_asserts (trivially-copyable + standard-layout) continue to hold. **Lock the layout with `static_assert(sizeof(TargetState) == N)`** where **N is the MEASURED post-insertion size — NOT the current size.** (Architect ruling F2: inserting ~24 B into a struct already ~276 B of members will cross the `alignas(64)` boundary, so `sizeof` is expected to grow, very likely 320 → 384 B. **This size growth is expected and golden-master-NEUTRAL** — the hash is over audio output + default field values, not `sizeof`. Do NOT claim/assert the size is unchanged. If a *future* change trips the assert: re-measure N, then re-confirm CF-1's hash still holds — never silently bump N.) Default `enabled=0` (every field explicitly defaulted) → `canonical_{}` inits to off → **golden master `0xE7267654BA01D315` unchanged**.
- **Chain insertion** in `DSPKernel::process` at the two wet-chain points (settled-x==1 branch and the crossfade branch), after BRIR-adjacent placement per §2; **Branch 1 (settled x==0) unchanged** (early-returns before any module).
- **Realizer + C-ABI:** new `publishCrossfeed(void* auUnit, uint32_t enabled, float level, uint32_t preset)` declared **once** in `AudioUnitRegistrationBridge.h` (the duplicate-declaration lint trap — a breadcrumb comment only in `AudioUnitBridge.h`). A `PendingCrossfeed` coalescing slot + `setPendingCrossfeed(...)` (clamps via `std::clamp`, posts a drain on clean→dirty) + a synchronously-callable `applyCrossfeed(...)` (testability) — exactly the `publishIntensity` pattern. The `drain()` adds a third read-and-clear block before the single `sequenceNumber++ / publishCanonical()` (multi-surface RMW; no clobber). Coeffs derived **off-RT** in the Realizer from `{preset, level, fs}`, packed into the POD.
- **No `RtSwappableResource`** — coeffs are a tiny POD on the existing `DoubleBufferSnapshot<TargetState>` transport (the Clarity/Limiter model, not the EQ heap-setup model). Argued in the lens.

---

## 4. UI / UX (swiftui-pro lens)

**QW-A — Reimagine intensity:** a **horizontal slider** (not a dial — macOS) in the Now Playing left panel (replacing the "No module selected" placeholder), matching the `MasterGainSlider` pattern: `[INTENSITY] … [23 %]` + slider `0…1` + "Bypass / Full Blend" end-labels. **Default 0.20** (low-to-lower-mid). Dead-band communicated via a `help()` tooltip at 0 ("0 % = bit-perfect bypass") — **not** a range clamp. Disabled + "Pure (bypassed)" when `pureModeEngaged` (the *live* path, not the intent flag). Owner: **`AudioViewModel.intensity`** → `publishIntensity` C-ABI (already exists). Reflects into the signal-path badge (`… · 23%`).

**QW-B — Tonal presets:** extend the existing `EQPreset` (add `loudness`, `vocal`, `studio` to `flat/presence/clarity/warm`); switch `EQPresetPickerView` from `.segmented` to **`.menu`** (>4 cases) with a `Divider()` before "Custom" (decide intended menu order/dividers at impl — F6). **"Save as Custom…"** button (enabled when edited) persists the 31-band array to `UserDefaults`. **Per-output recall** (deviceID→preset name): **wire via `onChange(of: selectedDevice)` in the view / composition root** (NOT a cross-VM callback — F3: the reverse `AudioViewModel→EQViewModel` callback risks a MainActor-isolation violation + a hidden cycle) → `EQViewModel.recallPresetForDevice(_:)`. Owner: **`EQViewModel`**; dispatch unchanged (`publishEQGains`). A non-modal banner on auto-recall ("Studio loaded for USB DAC").

**QW-C — Crossfeed toggle:** a new **"Headphones" section** in the Now Playing left panel (below intensity): `.switch` Toggle + a `.menu` strength picker (Relaxed/Default/Strong) shown when on. **Disabled + dimmed on non-headphone devices** (`deviceIsHeadphones = type ∈ {wireless, usb}` — heuristic; see risk) with "Connect headphones to enable." Auto-disables on switch to a speaker device. Owner: **`AudioViewModel.crossfeedEnabled/Strength`** → new `publishCrossfeed`. Reflects into the signal-path badge (`… · XF:Relaxed`).

**Wiring discipline:** both new global controls' **stored props live in base `AudioViewModel.swift`** (`@MainActor`; consistent with the existing all-state-in-base pattern — base reaches ~360 lines, under the 400 limit, F5), with the **operations in new bridge extensions `+IntensityControl` / `+CrossfeedControl`** called from `didSet` → `Task` → the bridge's `engineQueue` (the `masterGain.didSet → setParameter` path). Protocol gets `publishIntensity` / `publishCrossfeed` with no-op defaults. **Signal-path reflection (F4):** extend `SignalPathInfo` with `intensityLinear` + `crossfeedStrength` fields, copied from the VM in `tickSpectrum` — the badge stays a pure function of the value snapshot (don't have the badge read `AudioViewModel` directly).

**UX risks flagged:** (1) intensity dead-band confusion (1–3 % feels like no change while the ramp departs zero) — mitigated by the "Bypass" label + tooltip; (2) **crossfeed device-type heuristic false-positive** (USB interface→monitors reads as headphones) — known limitation; precise detection needs `kAudioDevicePropertyTransportType`/`DataSource` (future story); (3) use `pureModeEngaged` not `pureModeEnabled` for the intensity disable.

**Intensity↔crossfeed semantic (important):** crossfeed is a *wet-region* stage, so the knob scales it — at 0 % (bypass) crossfeed is also off. The UI presents crossfeed as a toggle, but its audible depth = `crossfeed × intensity`. This is intended ("intensity = how much of all enhancement"); the UI copy should not imply crossfeed is independent of intensity. *(Architect to confirm this is the right model vs. crossfeed-always-on — §9.)*

---

## 5. Naming / preset mapping (reconciliation)

User-facing crossfeed names **Relaxed / Default / Strong** map to the bs2b coefficient sets **Jmeier / Default / Cmoy** respectively (§2 table). The `CrossfeedPreset` enum in C++ uses the user-facing order — but **the middle case is named `CrossfeedPreset::Bauer` (= 1), not `Default`** (F8: avoid the `default:` keyword clash / clang-tidy + switch-readability); the Swift-facing label stays "Default". So `{ Relaxed = 0, Bauer = 1, Strong = 2 }`; the Realizer resolves each to (fc, α).

---

## 6. Testing strategy & automation (qa-expert)

**Automatable vs not (honest split):** the **crossfeed DSP is fully gated** in the C++ harness; the **Swift UI (knob/presets/crossfeed controls) is NOT** (`swift test` is broken, no AVAudioEngine in the harness) — it's verified by clean build + swiftlint + the founder's by-ear/by-hand checklist. The kernel contract the UI depends on (steerable intensity) is already pinned by `IntensityTests.inc`.

**Crossfeed automated suite (new `Tests/CrossfeedTests.inc` + extensions; all `parallelSafe` except the soak):**
- **CF-1 bypass bit-exact when disabled** — re-asserts the golden-master hash `0xE7267654BA01D315` with the module present-but-off (the canary; zero tolerance).
- **CF-2 non-stereo pass-through** (N=1/N=6, byte-identical).
- **CF-3 mono level-neutral** (|Δ| ≤ 0.1 dB Default, ≤ 0.3 dB Strong).
- **CF-4 channel-separation** (cross/direct = α: −9 dB ±1.5 Default, −9.5 Relaxed, −6 Strong; both directions).
- **CF-5 LPF characteristic** (−3 dB at fc; ≥9 dB down at 8 kHz).
- **CF-6 no NaN/Inf** (noise/transient/DC).
- **CF-7 click-free enable/disable** (boundaryStep ≤ 3× settledMaxStep, the EQ-swap bound).
- **CF-8 coeff recompute on sample-rate change** (separation consistent ±0.5 dB across 44.1/48/192k; assert delayFrames<64).
- **CF-9 read-both-then-write-both** guard (the #1 crossfeed bug — distinct L/R tones, measured vs analytic ±1 dB).
- **CF-10 libebur128 level-neutral** (crossfeed on vs off ≤ 0.3 LUFS, real stereo) — in `LoudnessOracleTests.inc`.
- **CF-11 4-surface Realizer RMW** (EQ+intensity+crossfeed, no clobber, sequenceNumber strictly +1, clamp check) — extends `RealizerTests.inc`.
- **CF-12 RT-alloc soak with crossfeed on** (rtAllocs==0) — extends `SoakRtAllocTests.inc`.

**Swift testable seams (pure functions, pull out so they're checkable):** preset gain arrays (length-31, in-clamp, non-identity cascade), the `deviceIsHeadphones(type)` truth table, the per-output recall map. **Everything else → the by-hand/by-ear checklist** (knob blends + bit-perfect@0%; presets audible + Save-as-Custom persists + per-output recall banner; crossfeed out-of-head on headphones, transparent on speakers, absent on Pure).

**Gates / done-done:** null-test all green incl. golden master held; clang-tidy clean on the new module; `TargetState` static_asserts compile; Swift builds + swiftlint green; founder by-ear checklist signed off. **Regression safety:** default-off + zero-init + the disabled early-return make the default path byte-identical (CF-1 + the golden master are the dual fence); Branch-1 (x==0) untouched; POD-on-existing-transport (no new RtSwappable); single sequenceNumber++ (CF-11); zero RT alloc (CF-12); Pure path structurally unaffected. **Golden master must NOT be re-baselined this sprint** — a mismatch is a build-blocking regression.

---

## 7. Implementation order (proposed; gate-verified, committed per sub-step)

1. **Crossfeed DSP stage** (C++): `CrossfeedModule` + `CrossfeedParams` + chain insertion + Realizer/`publishCrossfeed` + null tests → C++ gate (golden master held) + commit.
2. **Reimagine knob** (Swift UI): slider + `AudioViewModel.intensity` + `+IntensityControl` + signal-path badge → build + lint + commit. (Founder by-ear.)
3. **Crossfeed UI** (Swift): Headphones section + strength + gating + `+CrossfeedControl` → build + lint + commit.
4. **Tonal presets** (Swift): EQPreset cases + `.menu` picker + Save-as-Custom + per-output recall → build + lint + commit.

DSP first (the foundation the knob scales); UI after. Each sub-step independently gated.

---

## 8. Structure / maintainability review (refactoring-specialist)

Endorsed as structurally sound: the `Spatial/` placement, no-RtSwappableResource, single-C-ABI-declaration, `+IntensityControl`/`+CrossfeedControl` extension cuts, default-off golden-master safety, `pureModeEngaged` gate, off-RT coeff derivation. Findings (2 resolved into the design **before coding**; rest are implementation-phase):

- **F2 (resolved → §3):** `CrossfeedParams` must have a concrete field list (named, explicitly defaulted) + a `static_assert(sizeof(TargetState) == N)` to lock the layout and protect the golden master (a wrong padding/size silently changes the hash). *Applied in §3.*
- **F3 (resolved → §4):** drop the `onDeviceChanged` cross-VM callback (reverse dependency + MainActor-isolation hazard); wire per-output recall via `onChange(of: selectedDevice)` in the view/composition root instead. *Applied in §4.*
- **F4 (should — §4):** extend `SignalPathInfo` with `intensityLinear` + `crossfeedStrength` (copied in `tickSpectrum`) rather than having the badge read `AudioViewModel` directly — keeps the badge a pure function of the value snapshot. *Applied in §4.*
- **F5 (should):** declare the new stored props in base `AudioViewModel.swift` (ops in the extensions), per the existing pattern; base reaches ~360 lines (under the 400 limit — watch it next sprint).
- **F1 (structural-risk, defer — tracked):** the Realizer `drain()` is now 3 near-verbatim per-intent blocks. **Do NOT** factor a `PendingSlot<T>` template inside QW1 (re-touching load-bearing concurrency code mid-burst is the wrong risk/reward). Instead add a `// TODO` at the new slot naming the explicit trigger: *"extract `PendingSlot<T>` if a 5th feed-forward surface is added, OR before S8 maturity work next touches the Realizer."* This makes it scheduled debt, not rot.
- **F6/F7/F8 (nice):** decide `EQPreset` menu order + divider placement; add a compile-time `static_assert(kMaxCrossfeedDelayFrames < 64)`; **rename the C++ enum `CrossfeedPreset::Default` → `Bauer`** (avoids the `default:` keyword clash) while the Swift-facing name stays "Default". *Rename applied in §5.*

---

## 9. Final verdict (architect-reviewer)

**VERDICT: GO-WITH-CHANGES.** The plan is architecturally sound, respects the two-path engine + the S6 spine + the gate discipline, is well-scoped as a contained burst (every expensive primitive already shipped in S6), and protects the golden master with a genuine dual fence (default-off zero-init + CF-1 hash re-assertion). The required changes are doc-level (no design rework) and are **applied** in this revision:

**Rulings:** (1) crossfeed placement ✅ correct (wet region, before blend/Loudness/Limiter) — rationale corrected (§2). (1b) crossfeed↔BRIR **mutually exclusive** — invariant recorded (§2), no code now. (2) intensity-scales-crossfeed (wet-region) ✅ correct — always-on would break the bit-perfect 0% anchor + the limiter-last topology + founder intent. (3) 4th Realizer surface ✅ clean enough; **defer** the `PendingSlot<T>` template (don't re-touch load-bearing concurrency code mid-burst) — tracked TODO required (§8 F1). (4) `TargetState` layout — mitigation idea right, the *stated arithmetic was wrong*; **fixed** (§3): assert the MEASURED size, size-growth is expected + golden-master-neutral. (5) scope/risk ✅ genuinely "quick" (≈20 lines of first-principles DSP + one POD + one copied Realizer slot + 12 tests); DSP-first sequencing ✅ correct; the 12 tests are appropriate (crossfeed sits in the loudness-safety chain).

**Required-before-coding (all applied here):** ① §3 sizing claim corrected; ② §2 BRIR-order rationale corrected; ③ §2 crossfeed↔BRIR mutual-exclusivity invariant recorded; ④ §8 `PendingSlot<T>` deferral made a tracked TODO with an explicit trigger.

**Nice-to-have (non-blocking):** gate the `XF:…` signal-path badge on intensity > 0 (don't show an inaudible-chain badge at 0%); state the device-heuristic false-positive's *audible* consequence in user terms (mild centre-image collapse on speakers — benign, user-reversible, crossfeed is *offered* not auto-applied).

**Bottom line (architect):** "GO once the TargetState sizing claim is corrected … the design itself is right, contained, and faithful to the spine." → corrected; **plan is GO, pending founder sign-off.**

---

## 10. Acceptance / done-done (draft)

- Crossfeed: null-test gate green (bypass bit-exact, level-neutral, separation/LPF correct, no-NaN, click-free), golden master `0xE7267654BA01D315` held; by-ear on headphones (soundstage out-of-head, vocals centred, no narrowing on speakers).
- Reimagine knob: audibly blends dry↔enhanced; 0 % bit-perfect; reflected in signal-path; by-ear intensity sweep (the founder's deferred test) unlocked.
- Tonal presets: ≥6 named curves + Save-as-Custom + per-output recall; all via the live EQ.
- All Swift builds clean + swiftlint/clang-tidy green; no regression in existing tests.

---

**Maintained by:** AdaptiveSound team · **Feeds:** [sprint-plan.md](sprint-plan.md) (QW1 exception, before S8).
