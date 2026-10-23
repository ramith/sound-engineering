# Sprint EQ: architecture review (Reviewer 3, the Architect)

*2026-10-09. Read-only review of `feat/s10-8-eq` @ f563437 (via the main checkout, nothing built or
edited), `dsp/dsp-plan-check.md`, `ui/ui-plan-check.md`, `research/players-implementation.md`,
`research/literature.md`, the eq-lens README and sweep-plan §B/§D. The-fool modes used: pre-mortem and
evidence audit (chosen by me, since a subagent cannot ask). Severity: **P0** = decide before EQ1b
starts; **P1** = must be in the plan; **P2** = should be in the plan; **P3** = note.*

## 0. Verdict: **APPROVED WITH AMENDMENTS**

The engine choice is sound and well evidenced: WLS-ACGE solved off-RT, a double TPT SVF, and one shared
dB ramp that carries the preamp. The same goes for the Tone layer and for the move to engine-side
automatic headroom. Deleting `EQSafetyClamp` is safe, and the replacement is stronger (§6).

The plans are not yet one design, though. Five things must change before code starts:
1. **The Reimagine Intensity blend sits around the EQ**, so the sprint's founding promise, "the graph
   draws what plays", is false at any intensity below 100 %. The UI already says 20 % (F1, P0).
2. The two plans use **`points` with opposite meanings**, and each invents its own engine protocol
   when one already exists (F2).
3. The plans' **per-output recall fix still fails** when the window is closed (the app keeps playing
   from the menu bar) (F4).
4. The **AU re-allocation fix is incomplete**: there is also a data race and a stale crossfeed (F3).
5. **Two PRs both own `EQViewModel`** and its persistence (F14).

Every amendment except F1 is mechanical. F1 needs one founder answer (Q1). With these folded in,
the plan supports "one revision, one verify".

## 1. Findings

| # | Sev | Area | Finding (evidence) | Required change |
|---|---|---|---|---|
| F1 | **P0** | Chain / honesty | The EQ runs **inside** the intensity wet/dry blend. The dry copy is taken before `runColorationChain`, which starts with the EQ (`DSPKernel.cpp:197-205`, `:259`). The output is then `cos(rπ/2)·dry + sin(rπ/2)·wet` (`:226-244`). The UI default is 20 % (`AudioViewModel.swift:104`). At r = 0.2, Warm (+10.1 drawn) plays as a ~+1.6 dB tilt, and its peak sits **+2.0 dB above the source**, which breaks decision 23. At r = 0.5 the peak is +3 dB. Neither plan mentions this. **Separately (an existing bug):** intensity is published only from `didSet` (`:111`), so at launch the engine runs at `TargetState` default 1.0 (`TargetState.h:114`) while Now Playing shows "20 %". Today the EQ is honest only by accident. | Founder Q1. Recommended: move the EQ **ahead of the intensity split** (EQ → dry snapshot → Clarity/BRIR/Crossfeed → blend → Loudness → Limiter). The intensity-0 early return (`:158-164`) then requires the EQ to be bypassed and settled; otherwise run EQ → safety chain, so an EQ'd signal never skips the limiter. Publish every intent (intensity included) on engine-ready. Gate: `EQ_ResponseIndependentOfIntensity` at r ∈ {0, 0.2, 0.5, 1}. Annotate `architecture.md` §2.5/LD-16. |
| F2 | P1 | Contract | The plans conflict. UI §3: `points` = pre-Tone, `effective` = sent, and `played`/`headroomDb` are **stored**. DSP §7: `base` = pre-Tone, `points` = sent, and `played(for:)` is **pure**. The two plans also add two new protocols (`EQEngineContract`, `EQEngineControlling`), although `AudioPlaybackEngine` already carries `publishEQGains` (`AudioPlaybackEngine.swift:163-165`) and already has a test mirror (`Package.swift:191`, `MockAudioEngine`) and a debug fake (`SheetEngine.swift:47`). | One contract (§2). Use DSP naming (`base`, `tone`, `points`). Extend the **existing** protocol; do not add a third. `played` is derived, never stored. |
| F3 | P1 | RT / lifecycle | **Bug confirmed:** `allocateRenderResources` calls `_kernel->initialize` (`AUAudioUnit.mm:152-170`). That calls `make_unique<EQModule>()` (`DSPKernel.cpp:53`), which starts in identity (`EQModule.cpp:22-35`). Coefficients arrive only through `publishTargetState` (`DSPKernel.cpp:97-100`), so the EQ plays flat until the next edit. **Missed by both plans:** (a) a **race**. `initialize` runs on the AU's allocate thread and replaces `eqModule_`, while the Realizer queue may be inside `publishTargetState → eqModule_->publishCoefficients` (`Realizer.mm:371`). The "never races process()" guarantee (`AUAudioUnit.mm:157-160`) covers only the RT thread. At 60–120 Hz drag publishing plus file-load reconfigures at track seams, this becomes a use-after-free window. (b) **Crossfeed** coefficients are derived at the slot's old fs (`Realizer.mm:319-322`) and never re-derived on a rate change. | `Realizer::reinitializeKernel(fs, frames)`, run **on the Realizer queue** (`dispatch_sync`). It re-initializes the kernel, re-derives every fs-dependent intent (EQ and crossfeed) and publishes once. The Realizer owns fs, so the per-slot `sampleRate` fields and the Swift bus-rate read go. Gates: `EQ_SampleRateChange_Resolves`, a new `Realizer_ReinitDuringDrain` (tsan), and `Crossfeed_RederivedOnRateChange`. |
| F4 | P1 | Per-output recall | **Bug confirmed:** recall lives in `EQTabView.onChange` (`EQTabView.swift:50-54`). The UI plan's fix moves it to `ContentView`. That still fails in **resident mode**: closing the last window keeps the app playing from the menu bar (`AppDelegate.swift:5-12`), with no view mounted. It also fires spuriously: `AudioDeviceModel` equality covers `sampleRate`/`bufferFrameSize` (`AudioDeviceModel.swift:5-9`), and `refreshDevices` reassigns `selectedDevice` (`AudioViewModel+Devices.swift:45-46`), so a rate change counts as a "device switch". | Use a **composition-root edge**, following the shipped pattern (`AdaptiveSound.swift:47-87`, Edges 1–4): `audio.onOutputIdentityChanged = { [weak eq] key in eq?.outputDidChange(to: key) }`. It fires only when the device UID changes. The toast is view-level, in the shell overlay. |
| F5 | P1 | Device identity | **Confirmed:** the key is `String(device.id)` (`EQViewModel.swift:143`), an `AudioDeviceID`. No UID reaches Swift (`DeviceBridge.h:41-54`). | Add `uid` and `modelUID` to `CDeviceInfo` and `AudioDeviceModel`, as its own small PR, parallel from day 1. Key slots by UID. Fall back to ModelUID only when exactly one stored slot has it. Store the name for display. |
| F6 | P2 | Safety | The clamp is **already ungated**. `scripts/build-eq-clamp-test.sh:11` compiles `Tests/EQSafetyClampTest.swift`, which no longer exists, and no `make` target runs the script. So the Sprint 4 "13/13" evidence is gone. The real level bound has always been the always-on −1 dBTP limiter: no control path ever writes `LimiterParams` (`TargetState.h:97-104`; `DSPKernel.cpp:268-272`). Remaining gaps: F1; pathological ramp transitions (+1.2 dB for 20 ms, caught by the limiter); the normaliser's +12 dB makeup (`LoudnessModule.h:48-50`), which slowly wins back the preamp, so long-run loudness is set by −16 LUFS plus the limiter, not by the preamp. | Compute headroom **in the Realizer**, so every future publisher (AutoEq, Arbiter) passes through it. The Realizer validates its input at the C-ABI trust boundary: it rejects non-finite values and clamps to ±12. Add gates `EQ_PublishRejectsNonFinite` and `Safety_EQStep_AfterNormaliserAdapted` (≤ −1 dBTP; log the loudness step). Delete the script and its `.gitignore:36` line, and annotate `architecture.md:100`. |
| F7 | P2 | Migration | Under UI §3's migration (points = v1 gains, preset = built-in), an **unedited** "Warm" user becomes "Warm · Edited" after the EQ4 re-voice, still playing the old voicing. In v1, `presetRaw != nil` already means unedited, because any edit sets it to nil (`EQViewModel.swift:113-118`). Separately, the restore code clamps to ±12 (`EQViewModel+Persistence.swift:90`), which would truncate a ±24 `base`. | Rules: v1 built-in → that preset's **current** points, unedited. v1 nil whose gains equal a saved preset → `.mine(name)`. Otherwise → `.builtIn(.flat)`, edited, base = v1 gains. `isOn` = true. Decode limits: base ±24, tone ±12, finite, exact counts; anything invalid → flat, never a crash. Fixture tests for each rule. |
| F8 | P2 | Persistence shape | UI §3 splits the state over `eqLiveStateV2` and `eqOutputStateV1`, two keys that can diverge. `outputPresetMap` is never written (`EQViewModel.swift:136-161` only removes entries). | Use **one aggregate** `eqStateV2 = {version, shared, pinned}`, written atomically on discrete actions and at stroke end. Keep `eqCustomPresetsV1` byte-compatible, so a downgrade still works. Drop `eqOutputPresetMapV1` with no migration. |
| F9 | P2 | Boundary / threading | `played(for:)` on a `@MainActor` *engine* protocol is the wrong boundary. It is a pure function of (points, fs), so every mock and fake would have to implement DSP. DSP §5 also says "cached per sample rate", "allocates nothing" and "any thread" at once, which is a **shared-cache data race** if the UI and the Realizer call it together. | Make it an owner-local designer: `GraphicEQDesigner` (C++) with its own per-fs cache, one instance for the Realizer and one for the VM. Behind the C-ABI handle sits `EQDesigner` (app target). The only engine dependency is `eqSampleRate()`. The VM memoizes `played` on (points, fs) and computes it lazily when the graph reads it. No fake curve is ever needed. Gate: `Designer_TwoThreads` (tsan). |
| F10 | P2 | Semantics | Compare collapses into Off. With Off = flat at L(curve), and since L(curve) ≤ 0 = L(flat) always, a held Compare (reference flat) plays exactly what Off plays. `EQListening.compare(reference:hearingReference:)` is therefore unused in R1. The UI's Off copy, "playing the original" (UI §5), is false whenever L ≠ 0. | The engine input is `isOn` only. Compare is a UI gesture: `isOn && !isComparing`. Change the Off copy (e.g. "Equalizer off · level-matched"). Add the general reference form back only if Compare later means "edits vs preset". |
| F11 | P2 | Undo | "⌘Z brings edits back" (UI Q1 A) would be the app's **first** `UndoManager` integration (no `undoManager` anywhere in `Sources`). That means Edit-menu, responder-chain and window-closed semantics. The app's established pattern is a one-level restore point plus a toast (`AudioViewModel+Queue.swift:21-46`, `QueueToast`). | Reuse it: switch at once, then a toast offers "Bring back edits" (one level). Founder Q2. |
| F12 | P2 | Drag | Today's shoulder compounds: it blends from the *current* value on every sample (`FrequencyResponseCanvas.swift:212-223`). The canvas also writes VM arrays directly (`:180, :207, :220`). UI says "verbatim"; DSP says "stroke-start". | Stroke-start, in `points` space, through a VM stroke API (`begin`/`update`/`end`/`cancel`). It is deterministic, Esc-cancel needs the snapshot anyway, and the views stop mutating model arrays. Pin the new numbers in kit tests. |
| F13 | P2 | Kit ownership | The "Edited" rule lives in `EQEditKit`, but the preset tables live in the app target (`Models/EQPreset.swift`). The raw value doubles as display name **and** persistence id (`EQPreset.swift:19-46`), hence the UI plan's "decode alias" for the Low Volume rename. | Move the built-ins into the kit, with a **stable id** separate from `displayName`. The rename then needs no alias. |
| F14 | P2 | PR split | DSP EQ2 (`EQViewModel(+Persistence)`, `EQLiveState`) and UI EQ3a (VM reshape, v2 persistence, migration) own the same files, which guarantees parallel-worktree conflicts. EQ3 ∥ EQ3t both draw Tone shading in `EQGraph+Drawing`. | VM and persistence belong to EQ3a only; EQ2 becomes the bridge cut-over. EQ3 ships the shading layer driven by `highlightedRegion: EQToneRegion?`, so EQ3t is card-only (§8). |
| F15 | P2 | Realizer debt | `Realizer.h:83-88` schedules a `PendingSlot<T>` extraction "before … next touches the Realizer". EQ1b rewrites the EQ slot and fs ownership. | Do the extraction in EQ1b, or record an explicit re-deferral. Don't let the trigger pass silently. |
| F16 | P3 | Bit-exact read-back | "Settled RT coefficients == design, bit for bit" holds only if both sides call **one** compiled coefficient function. A duplicated formula can differ under fp-contraction. | One `svfBellCoefficients(gainDb, bandConst)` in a header, used by both the design function and the module. |
| F17 | P3 | Dead infra | `RtSwappableResource<T>` has a single user, `EQModule.h:117`, and no tests. After EQ1b it is untested infrastructure. | Keep it with one direct test (it is BRIR's planned IR-swap path), or delete it. Decide in EQ1b. |
| F18 | P3 | Logging | A per-publish `[QW1]` log (`Realizer.mm:163`, `AUAudioUnit.mm:414`) plus `logUX` (`EQViewModel.swift:182`) at 120 Hz floods the log. | Log at stroke end only. |
| F19 | P3 | Existing data | Saved My Presets will play stronger (they were shrunk by the clamp). That is correct under decision 22, but it is a heard change to user data. | Mention it at the founder check; no migration of values. |

## 2. The reconciled contract (types, ownership, threading)

**Why this shape:**
- **Engine:** the engine stays a pure 31-target graphic EQ (both plans agree), and owns fs and the
  level rules.
- **The kit:** one pure Swift target owns every editing rule, with zero dependencies and tests, as in
  the `PlaybackQueueKit` and `DesignTokenKit` precedents.
- **The view model:** the app target holds only the `@MainActor` view model, the C wrapper and the
  engine adapter.
- **Seams:** the existing `AudioPlaybackEngine` seam is extended, so the mock, the sheet fake and the
  bridge change in one place.
- **No fakes:** the read-back is the real pure C++ function from the moment EQ1a lands.

```swift
// ── EQEditKit (new pure target; zero deps; EQEditKitTests, swift-testing) ─────────────────────
public enum EQBands {                                     // band index is the contract, not Hz
    public static let count = 31
    public static let centreHz: [Double]                  // exact 10^(1.3+0.1m): maths, Tone, plot
    public static let label: [String]                     // nominal ISO 266: UI text only
    public static let pointLimitDb: Float = 12, baseLimitDb: Float = 24, toneLimitDb: Float = 12
}
public enum EQToneRegion: Int, CaseIterable, Codable, Sendable {
    case bass, body, mids, presence, air
    public var rangeLabel: String                          // "2–6 kHz"
    public func weight(atHz f: Double) -> Double           // DSP §6 raised-cosine partition of unity
    public static let bandWeights: [[Float]]               // 5×31, once; ToneLayer + shading read it
}
public struct EQCurve: Equatable, Codable, Sendable {      // encodes base + tone, never points
    public private(set) var base: [Float]                  // 31, ±24 (the user's layer)
    public private(set) var tone: [Float]                  // 5, ±12
    public var points: [Float] { get }                     // 31, clamp(base + Σ tone·w, ±12): DRAWN AND SENT
    public init(points: [Float]); public static let flat: EQCurve
    public mutating func setPoint(_ band: Int, to db: Float)   // lands exactly: base = clamp(db) − T[b]
    public mutating func setTone(_ r: EQToneRegion, to db: Float)
    public mutating func resetTone()
    public func baked() -> EQCurve                         // Save: base = points, tone = 0
    public func isLimited(_ band: Int) -> Bool             // readout "set +12 (limited)"
}
public enum EQBuiltInPreset: String, CaseIterable, Codable, Sendable {   // raw = stable id forever
    case flat, presence, clarity, warm, loudness, vocal, studio          // display "Low Volume" ≠ id
    public var displayName: String { get }; public var points: [Float] { get }
}
public enum EQPresetRef: Hashable, Codable, Sendable { case builtIn(EQBuiltInPreset), mine(String) }
public struct EQState: Equatable, Codable, Sendable {     // what one slot remembers
    public var preset: EQPresetRef; public var curve: EQCurve; public var isOn: Bool
    public func isEdited(presetPoints: [Float]) -> Bool    // any |Δ| > 0.05 dB; Tone ≠ 0 counts
}
public struct EQOutputKey: Hashable, Codable, Sendable { public let uid: String; public let modelUID: String?; public let name: String }
public struct EQStore: Equatable, Codable, Sendable {      // THE persisted aggregate: "eqStateV2"
    public var version = 2
    public var shared: EQState                              // every unpinned output plays this
    public var pinned: [String: PinnedSlot]                 // keyed by DeviceUID
    public struct PinnedSlot: Equatable, Codable, Sendable { public var key: EQOutputKey; public var state: EQState }
    public func slotID(for key: EQOutputKey?) -> String?    // exact UID, else unique ModelUID, else nil (shared)
    public mutating func renamePreset(_ old: String, to new: String); public mutating func deletePreset(_ name: String)
}
public enum EQMigration { public static func store(fromV1 live: Data?, customPresets: [String: [Float]]) -> EQStore }
public struct EQStroke { public init(start: EQCurve, band: Int); public func curve(at band: Int, db: Float) -> EQCurve } // stroke-start shoulder + gap fill
public struct EQPlayed: Equatable, Sendable {               // value only; produced in the app target
    public static let frequencies: [Double]                 // 256 log points, 20 Hz–20 kHz
    public let responseDb, centreDb: [Float]; public let headroomDb, peakDb, loudnessChangeDb: Float; public let sampleRate: Double
}

// ── App target ─────────────────────────────────────────────────────────────────────────────
protocol AudioPlaybackEngine {                              // EXISTING protocol, extended (+ test mirror + SheetEngine)
    func publishEQ(points: [Float], isOn: Bool)             // replaces publishEQGains; sync, off-RT, coalesced
    func eqSampleRate() -> Double                           // kernel design fs; default 48_000
}
final class EQDesigner {                                    // owns one C `AsEqDesigner*`; MainActor-owned, not Sendable
    func played(points: [Float], sampleRate: Double) -> EQPlayed
}
@MainActor @Observable final class EQViewModel {
    private(set) var store: EQStore; private(set) var customPresets: [String: [Float]]
    var current: EQState { get }                            // store slot of the current output
    var isComparing = false                                 // transient, never persisted
    var played: EQPlayed { get }                            // memo on (current.curve.points, eqSampleRate)
    func choose(_ p: EQPresetRef); func setOn(_ on: Bool); func reset()
    func beginStroke(band: Int); func updateStroke(band: Int, db: Float); func endStroke(); func cancelStroke()
    func nudge(band: Int, by db: Float); func setTone(_ r: EQToneRegion, to db: Float); func resetTone()
    func save(as name: String); func rename(_ old: String, to new: String); func delete(_ name: String)
    func pinCurrentOutput(); func unpinCurrentOutput()      // unpin copies the slot into `shared`: no audible jump
    func outputDidChange(to key: EQOutputKey?)              // composition-root edge (F4)
    // ONE dispatch point: engine.publishEQ(points: current.curve.points, isOn: current.isOn && !isComparing)
}
```

```c
/* AudioDSP C-ABI. EQDesignBridge.h is pure; AudioUnitRegistrationBridge.h is the control plane. */
typedef struct AsEqDesigner AsEqDesigner;                   /* owner-local per-fs cache: no shared state */
AsEqDesigner* asEqDesignerCreate(void);  void asEqDesignerDestroy(AsEqDesigner*);
bool   asEqDesign(AsEqDesigner*, const float* points, uint32_t count, double fs, AsEqDesign* out);
bool   publishEQ(void* au, const float* points, uint32_t count, bool isOn); /* validates: finite, ±12 */
double eqDesignSampleRate(void* au);
/* C++: GraphicEQDesigner (WLS-ACGE, response, refined headroom, K-weighted ΔL)
   · Realizer { setPendingEq(points, isOn); reinitializeKernel(fs, frames) [on its queue] }
     on: filterGainDb = solve, outputGainDb = headroom;  off: filterGainDb = 0, outputGainDb = ΔL(points)
   · TargetState.eq { float sectionGainDb[31]; float outputGainDb; float designSampleRate; uint8_t flags; }
   · EQModule: double TPT SVF, ONE shared dB ramp (31 + output), settled-0 bypass, per-block NaN reset;
     coefficients from one shared svfBellCoefficients() (F16); designSampleRate ≠ module fs → hold bypass */
```

**Threading:**

| Context | Work | Cost |
|---|---|---|
| Main | Kit operations; `publishEQ` (a slot write under `slotMutex_`) | µs |
| Main | `played`: lazy, at most once per frame, only while the graph is visible | 0.1–0.4 ms |
| Realizer queue | The solve and the Off level, coalesced latest-wins; publish; kernel re-initialization | ≤ 0.43 ms |
| RT | Triple-buffer copy; per 32 samples, 31 `exp` + closed-form SVF coefficients, linearly interpolated per sample | 2.2 % at 192 k × 8 |
| Allocate thread | `realizer->reinitializeKernel` only, which hops with `dispatch_sync` | — |

- **Why `played` is synchronous on main:** a stale async result can never land after a newer one.
- **Escape hatch:** if the gate's `Designer_Timing` exceeds 0.25 ms on M1, switch to a `Task`
  computed on a second designer instance, latest-wins.

## 3. Threading and real-time: judgement

- **The solve on the Realizer queue, with coefficients made on RT from smoothed dB gains:** approved.
  - The "finished coefficients only" rule bends for a measured reason: interpolating finished
    coefficients overshoots by +21 dB.
  - The RT contract holds: no allocations, no locks, bounded closed-form work.
  - One condition: the RT and design coefficient code are the same function (F16).
- **The shared dB ramp carrying the preamp, in place of `masterGainLinear`'s 32 ms ramp:** approved.
  The old separate ramp's +5…+7 dB overshoot is a real safety defect (`EQModule.cpp:151`).
- **`played(for:)`:** not an engine method (F9). It is synchronous, lazy, and memoized on (points, fs).
- **New gate test, alongside the rest of DSP §8:** `Designer_TwoThreads`. It runs the design
  concurrently on two designer instances under tsan.

## 4. State and persistence: judgement

1. **Ownership.** One `@MainActor` `EQViewModel` owns one `EQStore`. Every rule lives in the kit.
2. **Persisted values.** Persisted: `base`, `tone`, the preset reference, `isOn`, per slot.
   Computed, never stored: "Edited", `points` and `played`.
3. **Persistence rule.** Everything goes through the injected `defaults` (`persist-one-location` holds).
   The Tone fold stays `@AppStorage("eq.toneFolded.v1")` with no `store:` argument; it is view
   preference, which the rule allows by reading `.defaultAppStorage`. Sheets seed it through the
   sheet suite.
4. **Per-output memory: slots, not recall.**
   - Each pinned output has its own `EQState`; unpinned outputs share one.
   - Edits write to the current slot, so a switch never destroys edits.
   - This removes the "skip the launch nil→value" hack (`EQTabView.swift:46-53`): the restored state
     *is* the current slot.
   - This is UI Q2 (A), made structural.
5. **Migration (F7, F8).**
   - Stored keys: v1 keys are read once, then `eqStateV2` is written. `eqLiveStateV1` is left in
     place for one release, for a downgrade. `eqCustomPresetsV1` is unchanged.
   - Values: the decode limits are base ±24 and tone ±12, and today's ±12 restore clamp must not
     be reused.
   - Tests: one fixture test per rule.
6. **The schema version** lives in the blob (`version: 2`) as well as in the key name. A future v3
   decodes v2 inside the kit.

## 5. The two existing bugs

| Bug | Confirmed? | The plan's fix | Verdict |
|---|---|---|---|
| Recall mounted only on the EQ tab | Yes (`EQTabView.swift:50-54`; mounted per tab) | Move to a `ContentView` `.onChange` (UI F1) | **Insufficient.** It dies in resident menu-bar mode and fires on rate changes. Use a composition-root edge keyed on UID (F4), plus the slot model (§4). |
| AU re-allocation resets the EQ to flat | Yes (`AUAudioUnit.mm:169` → `DSPKernel.cpp:53` → `EQModule.cpp:22-35`) | The AU calls `realizer->setSampleRate(fs)` (DSP §2.5) | **Right direction, incomplete.** Serialize the kernel re-initialization on the Realizer queue (the use-after-free race), and re-derive crossfeed too (F3). |

## 6. Safety with `EQSafetyClamp` deleted

**What the clamp did.**
- If the *signed sum* of band dB exceeded 12, it scaled every band.
- It let a single +12 dB band through unscaled.
- It ran only in the Swift VM, so it did not cover other publishers.
- It has had no working test since the harness source vanished (F6).
- It was never the level bound.

**The worst case the user can hear, today and after.**
- **Enhanced:** the always-on true-peak limiter at −1 dBTP is last in the chain
  (EQ → Clarity → BRIR → Crossfeed → blend → Loudness (−16 LUFS, makeup −20…+12 dB) → Limiter).
  So no EQ setting can push the digital output above −1 dBTP. The exception is the intensity-0
  early return, which today runs no EQ (F1 keeps that true or routes it through the limiter).
- **Pure Mode and intensity 0 (with the EQ off):** the source, bit-exact.
- **The EQ cannot raise the maximum level.** It can only change spectral balance and loudness steps.

**What replaces the clamp's role.**
1. **Engine-side automatic headroom** (in the Realizer, for every publisher): steady-state ≤ 0 dB at
   every frequency. This is strictly stronger than the clamp.
2. **Input validation at the C-ABI:** non-finite values rejected; each point clamped to ±12.
3. **The shared ramp:** ≤ +0.004 dB realistic transient overshoot; the limiter catches pathological
   cases.
4. **Level-matched Off and Compare:** no toggle jumps.
5. **The limiter**, unchanged.

**Residual risks, accepted with tests.**
- **Intensity blends (F1):** fixed by reordering the chain.
- **Normaliser adaptation:** a boost removed after a long session steps the loudness up, still
  bounded by the limiter. Covered by `Safety_EQStep_AfterNormaliserAdapted`.
- **Phase-driven true peaks** (ℓ1 > ℓ∞, literature §4): the limiter covers them.

## 7. Evolution: seams, without building them now

- **S12 AutoEq (parametric RBJ):**
  - The RT module consumes per-section gains with fs-fixed section constants.
  - Implement the SVF output in Cytomic's general mix form (`y = m0·x + m1·v1 + m2·v2`; +1 MAC).
    R1 uses bells only (`m0 = 1, m2 = 0`), but S12's RBJ-equivalent shelves and bells then run on
    the **same** module, driven by a parameter table instead of the ACGE solve.
  - Name the fields neutrally (`sectionGainDb`), and keep the design function separate from the
    module.
  - Do not build a PEQ path now.
- **S14 loudness compensation:**
  - It is another layer in `points` composition. The kit composes `base + tone`, and S14 adds a
    level-dependent term.
  - Auto headroom would fight a low-volume bass boost. Keeping `outputGainDb` as its own field lets
    S14 move the headroom to a downstream volume stage (Rockbox `volume += prescale`) inside the
    Realizer alone.
  - The Compare level rule already uses `loudnessChangeDb`. Feeding ΔL forward to the normaliser
    (DSP Q1b) also belongs to S14.
- **Phase-2 system-wide tap:**
  - The kernel is host-agnostic and in-place (`DSPKernel.cpp:155-157`), and the Realizer takes a
    `shared_ptr<DSPKernel>`, not the AU.
  - Reuse is clean. Only the C-ABI is keyed on the AU handle, as crossfeed already is; rekey it
    when the tap exists.
- **SGE3 or Orfanidis band formulas (literature risk 2):** the shared coefficient function (F16) is
  the single swap point, for both the design and RT.

## 8. PR split, parallelism and gates

| PR | Scope | Size | Depends on | Gates |
|---|---|---|---|---|
| **EQ0** | `EQEditKit` value types (§2): bands, Tone weights, `EQCurve`, presets with stable ids, refs, `EQState`. Add `publishEQ(points:isOn:)` and `eqSampleRate()` to `AudioPlaybackEngine`, the test mirror and `SheetEngine`. Until EQ2, the bridge maps them onto today's C-ABI (clamp kept; Off = flat). No VM change. | S 0.5 | — | Kit tests: partition of unity, exact landing, clamp, `baked`, Codable round-trip; `swift build && swift test` |
| **DEV-UID** | `uid` and `modelUID` in `CDeviceInfo`, `CoreAudioDevice` and `AudioDeviceModel`; an `onOutputIdentityChanged` hook (UID diff) on `AudioViewModel` | S 0.5 | — | VerifyAUGraph prints the default device's UID; a Swift model test |
| **EQ1a** | `GraphicEQDesigner` (pure C++, owner-local cache) + `asEqDesign` C-ABI + `EQDesigner` (app) | M 1.5 | — | C++: `EQ_ACGE_*` at 6 rates, the design-level `Headroom_NoFrequencyAboveSource`, `PresetLoudness` table, `Designer_TwoThreads` (tsan), timing |
| **EQ1b** | RT: SVF module + shared ramp; `EQParams` relayout and size re-measure; Realizer (targets + isOn, fs ownership, Off level, `reinitializeKernel`, the `PendingSlot<T>` decision); new `publishEQ` C-ABI; delete `EQModuleCoefficients`; **chain reorder if Q1 = A**; golden re-baseline (documented) | L 3.5 | EQ1a | DSP §8 table + `Realizer_ReinitDuringDrain` + `Crossfeed_RederivedOnRateChange` + `EQ_ResponseIndependentOfIntensity` + `EQ_PublishRejectsNonFinite` + `Safety_EQStep_AfterNormaliserAdapted`; `make gate`, `sanitize`, `tsan` |
| **EQ2** | Bridge cut-over to the new C-ABI; delete `EQSafetyClamp`, its script and its `.gitignore` line; annotate the docs; publish every intent on engine-ready | S 1 | EQ1b, EQ3a | `swift test` (mock), strict-gate; Compare and Off level checks on the merged branch |
| **EQ3a** | Kit logic: `EQStroke` (stroke-start), the edited rule, `EQStore` slots + resolution, `EQMigration`. The VM reshape (stroke API, single dispatch, memoized `played`) and `eqStateV2`. The composition-root recall edge and the shell toast. | M 2 | EQ0, DEV-UID | Kit: migration fixtures, slot resolution (UID / unique ModelUID / ambiguous), rename/delete fix-ups, stroke numbers; break-it (data-changing) |
| **EQ3** | The V1b screen per the UI plan, drawing the real `played` (from EQ1a), with the Tone shading layer driven by `highlightedRegion` | L 3 | EQ3a, EQ1a | R4-EQ-01…04, FOCUS-03, LAY-EQ-01, sheets, the live keyboard pass |
| **EQ3t** | The Tone card only (`EQToneCard`, `CarvedTrack(origin:)`, the fold) | M 2 | EQ3a (∥ EQ3) | `eq-tone` and `eq-folded` sheets |
| **EQ4** | My Presets rename/delete (the Save sheet's mode), the pin UI, re-voice | M 2 | EQ2, EQ3 | Kit rename/delete tests; the founder's listening check |

**Parallel lanes:**
- **DSP lane:** EQ1a → EQ1b → EQ2.
- **UI lane:** EQ3a → (EQ3 ∥ EQ3t).
- **From day 1:** DEV-UID.
- **Last:** EQ4.

**The critical path** is the DSP lane plus EQ4: about 8.5 points.

**What this removes:**
- The analytic fake curve.
- The re-render of the sheets "on EQ2's read-back".

**Routine:**
- Merge discipline is decision 18's routine: one `make strict-gate` on the merged branch, reading its
  real exit code.
- Break-it applies, because this sprint changes keyboard, data and a migration.

## 9. The-fool: premises challenged

- **Steelman.**
  - Make the engine honest: an accurate cascade, the response drawn from the real coefficients,
    automatic headroom.
  - Make the editor simple: 31 points plus a Tone macro.
  - Make Off and Compare fair, and fix two recall bugs along the way.
- **Pre-mortem (6 months on, the EQ "still lies"): the most likely cause** is the founder moving
  Now Playing's Intensity knob, or someone fixing the 20 %-at-launch bug, after which every curve
  plays at a fifth or less of its drawn strength. That is F1. The other premises:

| Premise | Challenge | Survives? |
|---|---|---|
| "The graph draws what plays" | It is false whenever intensity < 1, and the UI already displays 20 %. | **No, as planned.** Yes after F1 (EQ outside the blend). |
| "Off = flat at the curve's loudness; Pure is the true bypass" | Persistent Off plays quieter for no visible reason. But the normaliser converges long-term anyway, and the founder's check asks for a level-fair On/Off. | **Yes**, with the copy fixed (F10). |
| "Compare level-matched to the quieter side by predicted loudness" | Against flat, it equals Off, so it adds a gesture, not a sound. The prediction error (±1.2 dB) is above the JND (0.25–1 dB). | **Yes**, as a momentary Off; cut `compare(reference:)` from R1. Don't call it perceptually exact. |
| "Auto headroom: −11 dB for one +12 band" (decision 23) | "Boost = quieter" feels broken. The limiter-keeps-level alternative turns the limiter into a tone stage (quality-first says no). And the normaliser restores most of the level over minutes anyway. | **Yes** for R1, with the headroom readout. The real fix is S14's explicit ΔL feed-forward or volume-stage headroom. |
| "Tone base ±24" | Hidden excess: after the drag-to-+12-with-Bass-−6 example, that band ignores Bass from −6 to +6 ("stuck"). The ±12 alternative breaks "the point lands under the pointer". | **Yes.** It is the only invertible model. Require the "limited" readout and ±24 decode limits. |
| "Press-and-hold Compare" | Once Compare ≡ momentary Off, holding is the only thing that tells it apart from the switch. | **Yes.** Keep the keyboard/VoiceOver toggle; release on blur and on Esc. |
| "Switch preset at once; ⌘Z brings edits back" | ⌘Z is new infrastructure (no `UndoManager` in the app) for one action, and it is inconsistent unless every edit is undoable. | **Partly.** Switch at once, yes; reuse the restore toast (Q2). |
| "The read-back must come from the engine" | Evidence audit: the decision's intent is "never a Swift copy of the fitter". The same pure C++ function plus the bit-exact gate meets it, without an engine round-trip or a not-ready state. | **Yes, reframed** (F9). |
| "EQ0 needs a fake engine" | The real design function is small and pure, and a C++ reference port exists (`bench/acge_ref.cpp`). | **No.** Land EQ1a early instead. |
| "Deleting `EQSafetyClamp` loses Sprint 4 safety" | Evidence audit: the clamp is ungated, weaker, and Swift-only; the limiter was always the bound. | **No loss.** The engine-side headroom is stronger. |
| "View-driven recall (rule F3)" | Resident mode has no views. | **No.** Use a composition-root edge (the shipped pattern). |

**Overbuilt for R1:**
- `EQListening.compare(reference:)`.
- Two new engine protocols.
- The fake engine.
- Two persistence keys.

**Missing from both plans:**
- The intensity coupling.
- The kernel re-initialization race.
- Recall in resident mode.
- Migration of unedited presets after the re-voice.
- What plays on unpinned outputs.
- Whether a preset choice turns an Off EQ on. Recommend yes, like a drag.

## 10. Questions for the founder (recommended option first)

1. **Should the Intensity knob on Now Playing also weaken the EQ?**
   - **(A, recommended) No.** The EQ always plays exactly what its graph shows, and Intensity keeps
     controlling the "Reimagine" effects (crossfeed today).
   - (B) Yes. At the default 20 % you would hear a fifth or less of every EQ curve, and the graph would
     have to draw that weaker curve.
   - Either way, we fix a quiet bug: today the knob shows 20 % but the sound plays at 100 % until you
     touch it.
2. **You've edited Warm, then pick another preset. How do you get your edits back?**
   - **(A, recommended)** It switches at once, and a short notice offers "Bring back edits", the same
     way the queue offers "Restore previous queue".
   - (B) ⌘Z (Undo). This is new for the app, so it costs more, and it would have to cover every EQ
     edit to feel right.
   - (C) Ask "Save changes?" every time.

*FYI, no answer needed:* your saved My Presets will sound stronger after this sprint, because the
old safety clamp was shrinking them. That is the honest engine at work.
