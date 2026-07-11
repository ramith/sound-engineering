# Stage 3 — Swift review (non-GUI app core + kits)

**Theme:** architectural elegance · reuse · best practices
**Scope:** `Sources/AdaptiveSound/*.swift` (the `AudioEngineBridge` + `AudioViewModel` families, `LibraryBrowseModel(+Facets)`, `EQViewModel(+Persistence)`, `AudioPlaybackEngine`, `PureModeSession`, `SignalPathInfo`, `Models/`, `Spectrum/`, `Helpers/`, `Monitoring/`, `Loudness/`) plus the kits `LibraryScan`, `LibraryBrowseKit`, `PlaybackQueueKit`, `AudioFormatKit`. **Excluded** (later stages): `UI/*` (Stage 4), `LibraryStore` (Stage 5), SQL (Stage 6), `Verify*` harnesses.
**Method:** two independent SME lenses — `swift-expert` (language/concurrency) + `architect-reviewer` (boundaries/reuse) — then a `the-fool` adversarial pass that read the actual code to confirm/refute each finding, then main-agent reconciliation. No build was run by the reviewers; the main agent verified the top finding against source.

---

## Executive summary

This is **unusually disciplined** code. The two structural pillars are, verbatim, "the strongest boundary in the codebase" (the Swift↔C++ `AudioPlaybackEngine` seam) and "cohesive-type-split-for-length done right" (the `AudioEngineBridge` extension family). **Do not touch them.**

The adversarial pass **downgraded both SME HIGH findings**:
- the concurrency HIGH (`dspAudioUnit` off-domain race) is a **real but narrow MEDIUM** — and is *broader* than first scoped (it also affects `avEngine`/`playerNode`);
- the architecture HIGH (`AudioViewModel` "God-object") is a **LOW/MED judgment call whose stated justification was false** (the `@Observable` over-invalidation claim doesn't hold — `@Observable` tracks per-keypath).

The genuinely actionable, cheap wins are a **single small cluster of concurrency-hygiene fixes on the DSP-publish/handle path**. Everything else is either deferred-with-rationale or a doc-accuracy nit.

### Verdict table

| # | Finding | SME call | the-fool verdict | **Final** | Action |
|---|---------|----------|------------------|-----------|--------|
| F1 | `dspAudioUnit` read off-domain by the 3 publishers | HIGH | CONFIRMED, MED (UAF not torn-read; narrow window) | **MED** | Fix now |
| BS1 | `avEngine`/`playerNode` have the *same* off-domain exposure | (missed) | CONFIRMED, MED | **MED** | Fix now (with F1) |
| F4 | fire-and-forget `Task{}` + gratuitous `async` on publishers | MED | OVERSTATED → LOW (smell real, hazard not reachable) | **LOW** | Fix now (with F1) |
| F3 | `withPureEngine` holds `stateLock` across file open | MED | CONFIRMED, LOW-MED (network volumes only) | **LOW-MED** | Fix soon |
| F2 | `SpectrumDoubleBuffer` missing acquire/release, 2 slots | MED | OVERSTATED → LOW (cosmetic; slot-lap unreachable) | **LOW** | Defer (see note) |
| BS2 | tap blocks do ARC (`weak self` load + retain) on tap thread | (missed) | CONFIRMED, LOW (contradicts the class's own doc) | **LOW** | Doc/optional |
| BS3 | `SpectrumAnalyzer.swift:11` doc claims a `ManagedAtomic` that doesn't exist | (missed) | doc-only | **trivial** | Fix with F2 if touched |
| F5 | `AudioViewModel` God-object → extract `LibraryModel` | HIGH | OVERSTATED → LOW/MED (invalidation rationale FALSE) | **LOW-MED** | Defer (founder call) |
| F6 | 4 facet loaders not DRY'd + ~10 parallel play-verbs | MED | OVERSTATED → not a defect (judgment call) | **LOW** | Optional (twins only) |
| LOW-a | duplicated `AVAudioFile` duration compute (2 sites) | LOW | — | **LOW** | Fix with F-cluster |
| LOW-b | `reconcileDebounce` retains completed Task handles | LOW | — | **LOW** | Trivial |
| LOW-c | boundary value types rely on implicit `Sendable` | LOW | — | **LOW** | Optional hardening |

---

## Fix now — one small PR (all touch the publish/handle path)

### F1 + BS1 — off-domain reads of engine reference-typed state (MEDIUM)
`publishEQGains` (`AudioEngineBridge+EQControl.swift:11-14,31`), `publishIntensity` (`+IntensityControl.swift:21`), `publishCrossfeed` (`+CrossfeedControl.swift:26`) read `dspAudioUnit` on the **caller's MainActor thread** via `dspAudioUnitHandle` (a `dspAudioUnit?.auAudioUnit` load-retain). `dspAudioUnit` is *written* on the `AVAudioUnit.instantiate` completion (`+Graph.swift:28`) and *nil'd* on `engineQueue` (`+Lifecycle.swift:141`) — so it is neither queue-confined nor `stateLock`-guarded, violating the class's own `@unchecked Sendable` invariant doc (`AudioEngineBridge.swift:14-27`). `setParameter` (`+Playback.swift:246`) already models the correct pattern (`engineQueue.async`).

- **Not** a torn read (aligned pointer load is atomic on arm64). The real UB is **load-retain vs teardown-nil**: if `dspAudioUnit = nil` drops the last strong ref between the reader's load and its retain → use-after-free.
- **First-init is provably safe** (the `instantiate` completion → `initialize()` continuation is a happens-before barrier); **fire-before-init is a safe no-op** (handle is nil → early return). The one real window is **teardown-nil racing a MainActor publish during device-loss `retryInitialization`**, made reachable because the VM `didSet`s (`AudioViewModel.swift:89-95,101-115`) have **no `isEngineReady` gate**.
- **BS1:** `avEngine`/`playerNode` (`AudioEngineBridge.swift:29-30`, written on `engineQueue`) are read off-domain without sync from `+ConfigChange.swift:16,19,75`, `+Devices.swift:152`, `+PureModeDeviceMonitor.swift:92-96`. Same load-retain-vs-nil race class.

**Fix:** route the three publishers' handle read through `engineQueue.async` (mirror `setParameter`), or read under `stateLock`. Bring the `avEngine`/`playerNode` off-domain reads under the same discipline. Converts a prose invariant into an enforced one. **Effort S-M.**

### F4 — gratuitous `Task{}` / `async` on the publishers (LOW)
The VM `didSet`s spawn `Task { engine.publish… }` (`AudioViewModel.swift:93,104,113`). `publishEQGains`/`publishIntensity` are **synchronous** and MainActor-safe — the `Task{}` only defers to a later actor turn (the sole reason the theoretical reorder exists). `publishCrossfeed` is declared `async` (`+CrossfeedControl.swift:25`) with **no suspension point** — pointless `async` that is the only reason the crossfeed `didSet` needs a `Task`. (The "stale value applied" hazard is **not reachable** today: same-actor, same-priority unstructured Tasks execute FIFO.)

**Fix:** drop `async` from `publishCrossfeed`; call all three publishers **synchronously** in the `didSet`s (no `Task`). Simplifies and removes the theoretical reorder. Pairs naturally with F1 (both touch the publish path). **Effort S.**

### LOW-a — duplicated duration compute
`AudioViewModel+Playback.swift:65-77` and `+AutoAdvance.swift:51-61` are byte-identical `AVAudioFile → Double(length)/sampleRate` detached-then-hop-to-main. Fold into one `refreshDuration(for:)`. **Effort S.**

---

## Fix soon — isolated, real UX win on network volumes

### F3 — file open under the leaf lock (LOW-MED)
`setNextTrack` Pure branch calls `pureModeEngineSetNextTrack` inside `withPureEngine` (`+Gapless.swift:68-70`), which holds `stateLock` (`+SharedState.swift:167-174`); the C++ side pre-opens the next file under that lock (admitted at `+Gapless.swift:60-64`). The MainActor 20 Hz poll contends the same lock → UI hitch on slow/network/spun-down volumes (local SSD opens are sub-ms; `os_unfair_lock` priority donation bounds it; once per track-arm, Pure path only).

**Fix:** open the file / build the decoder **outside** `stateLock`, take the lock only to hand the opened resource to the C++ session — exactly the "slow work outside the leaf lock" rule already stated at `+SharedState.swift:26-28`. **Effort M.**

---

## Deferred — with rationale (founder call where noted)

### F2 — `SpectrumDoubleBuffer` memory ordering (LOW, cosmetic)
`generation`/`publishedGeneration` are plain `Int` with no acquire/release (`SpectrumDoubleBuffer.swift:31,39,66-80`). Worst case on arm64's weak model: the reader observes the new `publishedGeneration` before the slot store propagates → **one visually-wrong spectrum frame, corrected ~85 ms later**. The "2-slot overwrite mid-copy" path is effectively **unreachable** (writes at ~11.7 Hz = one per ~85 ms; would need a ~170 ms MainActor stall mid-176-byte copy). **Do not build a triple-buffer for a 20 Hz visualizer.** If touched at all, swap the two counters for a `ManagedAtomic<Int>` acquire/release (matches the codebase's own `reference-tsan-standalone-fence-gap` precedent) and fix **BS3** (the `SpectrumAnalyzer.swift:11` comment advertises a `ManagedAtomic<Int>` that the buffer does not actually use).

### F5 — `AudioViewModel` "God-object" → `LibraryModel` extraction (LOW-MED, defer)
Factually true: ~20 library fields + ~26 methods (store/scan/metadata/FSEvents-reconcile/volume-monitor/play-tracking, `AudioViewModel.swift:176-247`) live on the audio VM, and `LibraryBrowseModel` reaches *through* it for library state (`LibraryBrowseModel.swift:164,177-179,352`). **But** the driving justification is false: `@Observable` tracks access **per keypath**, so co-locating fields causes **no** extra re-renders. The concerns are already physically separated across ~10 concern-named extensions, and extracting a `LibraryModel` **relocates** coupling (browse still needs the play verbs) more than it removes it — churn in a single-window app with one composition root. **Recommendation: defer.** If pursued, do it for **testability / file-cohesion**, keep the play-verb seam on the audio/queue side, and wire all three VMs in the existing composition root (`AdaptiveSound.swift:19-24`). *Founder sign-off before doing this.*

### F6 — facet-loader DRY (LOW, optional; contradicts a prior gate)
The four loaders (`LibraryBrowseModel.loadAlbums/loadSongs`, `+Facets.loadArtists/loadGenres`) share a **second-await epoch re-guard** the author deliberately kept explicit (`+Facets.swift:12-16`, gate R1). the-fool's adjudication: the copies are **correct** (no correctness finding); only **artists+genres are true twins** (albums also calls `ensureArtwork`; songs' setter drives `refreshVisible()` via `didSet`). A blanket generic would need artwork/songs hooks that erode the DRY win and obscure the two special loaders. **Recommendation: fold only the artists/genres twins into one `loadSimpleFacet(...)`, or nothing.** The ~10 play-verbs are already partly shared via `facetTracks(_:)`; the album variants are a minor, optional consolidation. *Contradicts an explicit gate decision — founder call.*

### LOW-b / LOW-c
- `reconcileDebounce` never removes completed Task handles (`+Reconcile.swift:105`) — bounded by root count, not a leak; clear the entry at the tail of `runReconcile`.
- Boundary value types (`SignalPathInfo`, `LoudnessSnapshot`, `AudioFile`, `OutputPathKind`, `CrossfeedStrength`) cross the `@unchecked Sendable` seam on **implicit** `Sendable`; add explicit `: Sendable` as intent + future-proofing before any is promoted `public` into a kit.

---

## Doc accuracy (near-free)
- **BS2:** the three `installTap` closures start with `guard let … = self?.…analyzers` (`+Graph.swift:148,184,204`) — a `weak self` load (side-table lock) + ARC retain **on the tap thread**, contradicting the class doc's claim that the taps "only read pre-allocated, lock-free state" (`AudioEngineBridge.swift:22-24`) and the `+Graph.swift:140-143` "no ARC touches the audio thread" boast. LOW today (taps run on a dedicated non-render thread), but the invariant is **false as written** — either capture the analyzers `unowned`/unmanaged like the meter handle, or soften the doc.
- **BS3:** see F2.

---

## What is structurally GOOD — do not "fix"
- **The Swift↔C++ `AudioPlaybackEngine` seam** — the DI boundary traffics only in domain DTOs + primitives; `AVFoundation`/CoreAudio do **not** leak across the protocol (`@preconcurrency` import confined to the bridge). Real `MockAudioEngine` injection; gapless contract documented as protocol invariants. The strongest boundary in the codebase.
- **The `AudioEngineBridge` extension split** — all ~40 stored fields declared once (each annotated with its owning queue/lock); the entire lock discipline centralized in `+SharedState.swift` behind accessors; 19-file split by coherent sub-capability. Cohesive-type-split done right.
- **The module/target graph** — clean, acyclic, strictly top-down (App → kits → LibraryStore/AudioDSP; AudioDSP depends on no Swift target). The "extract the decision core so tests can `@testable import` it" rationale for the kits is principled.
- **`PlaybackQueueKit`** — pure, `Sendable`, deterministic (injected `randomPick` makes shuffle testable); app holds thin delegating wrappers. Textbook decision-core extraction.
- **RAII C-handle wrappers** (`LoudnessMeterHandle`, `PureModeSession`) — immutable `let handle`, NULL-safe/idempotent destroy, `deinit` backstop, slow HAL teardown *outside* the lock. Leak-safe/double-free-safe.
- **Cross-queue `.sync` is provably acyclic** (all `.sync` target the leaf `resampleQueue`; zero `engineQueue.sync`/`configChangeQueue.sync`), the `*Locked`/non-`*Locked` re-entrancy convention, generation/epoch cancellation, `MainActor.assumeIsolated` in the timers, `SingleInstanceGuard` (`flock`), ordered async teardown at quit, and the explicitly-avoided `@Observable` self-assign traps. All correct — leave them.
- No RT-render-path violation, no listener double-free (the F5 queue-identity removal is correct), and no config-change re-entrancy hole (`isReestablishing` is confined to `configChangeQueue`).

---

## Recommended plan
1. **PR A (fix now):** F1 + BS1 (route `dspAudioUnit`/`avEngine`/`playerNode` off-domain reads through `engineQueue`/`stateLock`) + F4 (drop `async`/`Task` on the publishers) + LOW-a (duration fold) + LOW-b (debounce cleanup). One coherent "concurrency-hygiene on the control-plane" PR. Gate: `swift build` (Swift 6 data-race checking) + `swift test` + full strict-gate.
2. **PR B (soon):** F3 (file-open outside `stateLock`).
3. **Optional / founder call:** F2 (real atomic + BS3 doc), BS2 (tap-capture or doc), F5 (`LibraryModel` — testability, not invalidation), F6 (twin fold), LOW-c (explicit `Sendable`).

**PAUSE — boundary.** Per cadence, no fixes applied yet. Awaiting go-ahead on the plan (and founder calls on F5/F6) before implementing.
