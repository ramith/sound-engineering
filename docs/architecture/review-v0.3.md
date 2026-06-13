# Architecture v0.3 — Full Team Review & Synthesis

**Date:** 2026-06-13 · **Reviewers:** Product Management, Business Analysis, Machine Learning, Real-Time Systems (C++), Security & Privacy · **Participants:** Audio DSP Engineering (knowledge base), QA Strategy, UX Guidelines, Design System

**Input:** PRD v0.3, requirements v0.6, backlog v2.1, architecture v0.3, prior-art.md, all delivered documentation.

**Net verdict:** Documentation set is SUBSTANTIALLY MATURE and INTERNALLY ALIGNED. The settled spine (control/data-plane, RT-safety rules, fidelity anchor, BRIR-first spatialization, typed-macro NL, ERB masking subset, per-stem re-sum discipline, MLX-primary separation, 4-phase roadmap) has survived full-team review with no material contradictions. **However, three HIGH-CONFIDENCE blocker gaps remain that must be resolved before engineering starts:** (1) ML artifact-gate signal entirely unspecified; (2) Hearing-data-at-rest hardening regressed to hand-wavy; (3) Lock-free param-bus wire protocol has no concrete type/memory-order contract. Additionally, 7 SHOULD-FIX gaps (mostly traceability and numeric specification) and ~20 POLISH items (minor clarifications, missing acceptance criteria, numeric bounds). No showstoppers; three must-fixes are resolvable in < 2 weeks.

---

## Panel Verdicts

### Product Management (coherence)
"Documentation is **largely coherent** with **moderate alignment drift** — primarily version-update lag in PRD §0 LD table vs. architecture amendments, plus 3 orphaned Personas/goals and 2 uncovered backlog enabler spikes. No critical blockers; all high-severity gaps are traceability/pointer issues, not functional contradictions. Safe to proceed to Phase 0 engineering with the listed refinements."

### Business Analysis (requirements & traceability)
"The documentation set is **substantially mature and internally aligned**; the settled spine is respected throughout. However, **four testability/measurability gaps directly threaten acceptance-test authoring**, two architectural mechanisms lack requirement anchors, and three OQs listed as open are actually already decided in architecture.md — creating stale noise that could mislead sprint planning."

### Machine Learning (separation + NL + placement)
"v0.3 is substantially improved from v0.2 — all five expert-panel items landed in some form — but **three underspecification issues remain build-blocking** in the separation pipeline, and one dangerous overclaim survived in both prior-art.md and requirements.md."

### Real-Time Systems / C++ (implementation-readiness)
"The control-plane/data-plane spine and the RT-rules list are sound, but **five implementation-blocking gaps remain** — particularly in the lock-free param-bus wire protocol, IR hot-swap mechanics, and sample-rate/device-switch handling — that would force a builder to make consequential synchronization decisions not covered by the spec."

### Security & Privacy (breach/supply-chain risk)
"C9's tap-as-capability landed cleanly and the LLM/cloud-allowlist intent is well-captured in prose, but the spec is **not yet build-safe** — the two named hardening items (hearing-data-at-rest, model-weight integrity) regressed to hand-wavy, the safety/security clamps live only as adjectives with no normative bounds, and there is no enforced 'stems-only-from-local-files' invariant — all must-fix before development."

---

## Consolidated High-Confidence Blocker Findings

| ID | Severity | Panel | Title | Fix | Phase Gate |
|---|---|---|---|---|---|
| **BLK-1** | 🔴 Blocker | ML | Artifact-gate signal ENTIRELY UNSPECIFIED — no concrete metric, no threshold | Promote one concrete proxy signal into architecture §6 (e.g., "inter-stem energy leakage in 2–5 kHz + transient-smear index, thresholded before clamping Reimagine ceiling"). Move 6s→4s→mix fallback ladder + per-track ceiling clamp mapping from review-v0.2 into FR-STEM-05. Even if thresholds are marked "to be calibrated in SPIKE-SEP-QUALITY," the signal shape must be normative. | Phase 1 start |
| **BLK-2** | 🔴 Blocker | CPP | Lock-free param-bus wire protocol UNDERDEFINED — no concrete type, width, or memory-order contract | Specify the concrete synchronization idiom by name — e.g., "triple-buffer with `std::atomic<uint8_t>` slot index, release-store on publish, acquire-load on consume; RT thread copies full `DSPSnapshot` struct by value before use; struct must be trivially copyable and fit in one cache line." Specify which memory order is required (e.g., `memory_order_acquire/release`). | Phase 0 start |
| **BLK-3** | 🔴 Blocker | SEC | Hearing-data-at-rest REGRESSED to hand-wavy — v0.2 P1 fix (FileVault + Keychain/Data-Protection + crypto-shred, never cloud-synced guarantee) did NOT land | Mandate Data-Protection class (key in Keychain/Secure Enclave, FileVault-at-rest assumed), crypto-shred on profile delete, explicit "never written to any iCloud/cloud-sync container" rule, resolve the backup-exclusion-vs-data-loss trade-off explicitly. Update NFR-PRIV-03 and FR-HEAR-02 with concrete mechanism names. | Phase 0 start |
| **BLK-4** | 🔴 Blocker | ML | Demucs weights license OVERCLAIM in prior-art.md & requirements.md DEP-14 — still says "MIT (incl. weights)" | Change both DEP-14 and prior-art.md §4 to: "code MIT; weights NC-trained — auto-downloaded on first run, not redistributed." One-line edit in each document. This is a latent legal/compliance trap. | Pre-Phase 0 |
| **BLK-5** | 🔴 Blocker | CPP | IR hot-swap (double-buffer + crossfade) mentioned in review-v0.2 but NOT in v0.3 architecture spec | Write concrete object-lifetime section: pre-allocate N=2 convolver slots at init; publish the "active slot" index atomically; the old slot is returned to the non-RT plane via SPSC retire queue; non-RT plane reloads it with new IR and re-publishes. Specify crossfade duration (~20 ms) and policy for overlapping requests. | Phase 1 start |
| **BLK-6** | 🔴 Blocker | BA | FR-TONAL-03 acceptance criterion is UNTESTABLE — specifies "fraction of the equal-loudness contour difference" but never defines what fraction | Lock the fraction (e.g., "50% of ISO 226 contour difference between 83 dB SPL reference and actual playback SPL, ±cap of +12 dB"). Make SPL calibration step explicit precondition. Update band-level numbers to reflect fractional calculation. Confirm the fraction with OQ-15c resolution or as a separate founder decision. | Phase 1 start |
| **BLK-7** | 🔴 Blocker | BA | FR-SPAT-01 acceptance criterion relies on undefined "statistically significant rate" ABX test with NO statistical design | Replace vague ABX clause with concrete criterion, e.g., "In a within-subjects ABX test with ≥10 listeners, ≥10 trials each, BRIR mode scores correct identification at p < 0.05 (binomial test); or equivalently, a subjective rating improvement of ≥1 point on a 5-point externalisation scale." | Phase 1 start |
| **BLK-8** | 🔴 Blocker | SEC | "Hearing-safety limits" and protective clamps are ADJECTIVES, not numbers — no normative bounds anywhere | State concrete per-band gain bounds, an absolute output-SPL/true-peak ceiling that the clamp enforces post-interpretation. Make the clamp a hard FR (not prose). Verify the numeric bounds with the audio-engineering team. | Phase 0 start |
| **BLK-9** | 🔴 Blocker | SEC | No integrity/signature/pinning on the FIRST-RUN model-weight download | Pin the download to a known URL + verify a hard-coded SHA-256 (ideally code-signed manifest) before load; fail closed on mismatch; document the trusted host. Add to ADR-007. | Phase 1.5 start |
| **BLK-10** | 🔴 Blocker | BA | OQ-15b and OQ-15c are founder-decision blockers with no engineering path yet, but not gated in Phase 0/1 sprint plan | Promote SPIKE-OQ15BC to a mandatory Phase 1 pre-sprint gate in the epic ordering table, with a stated deadline ("must be completed before Phase 1 Sprint 1 planning"). The Open Items table already flags it "High — before profile-delta storage design," which is correct; the sprint ordering must echo that urgency. | Phase 1 start |

---

## Should-Fix Findings (Moderate Severity, Must Resolve Before Engineering)

- **[PM-1]** Persona naming inconsistent across documents (PRD A/B/C vs. backlog generic "developer"). Impact: stories reference personas inconsistently, making persona→requirement traceability unmappable. Fix: Audit all story "As a [actor]" clauses, replace generic with "Ramith/Marcus/Tom/system" per persona matrix.

- **[ML-2]** MLX-vs-Core-ML path decision has no buildable decision criteria. Specify: "MLX is used unconditionally; Core ML conversion is attempted only as a pre-release optimization if MLX runtime is unavailable on target OS; fallback to mix-only (no separation) is the safe default." Add measured sec/track per hardware tier to SPIKE-SEP-QUALITY.

- **[ML-3]** NL validation harness specified as an intent but has no structure. Add one paragraph describing: (a) the JSON schema that every NL interpreter output must satisfy; (b) the monotonicity smoke-test (~10 descriptor pairs that must pass before shipping); (c) reference to SPIKE-NL-VALIDATION for full calibration.

- **[CPP-3]** Sample-rate change and device-switch mid-stream handling is unspecified. Specify the quiesce contract: "on device change, the AU host (non-RT) calls `kernel.prepareForReset()`, which atomically sets `renderingEnabled` flag to false; the render block returns silence; non-RT side reconstructs filters at new SR, publishes snapshot, re-enables rendering."

- **[CPP-4]** Seqlock/ring-buffer upward meter path lacks defined producer/consumer role assignment and overflow policy. State explicitly: "RT thread is sole producer; if ring is full, RT thread discards frame (non-blocking drop); UI timer reads without blocking."

- **[BA-2]** FR-TONAL-05 (adaptive multi-band dynamics) maps to no architecture mechanism name. Architecture §9 says "no program DRC by default; if any, prefer dynamic EQ." FR-TONAL-05 permits the compressor *in loud ambient conditions* but there is no ADR or architecture section describing the dynamic-EQ vs. multiband-compressor implementation path. Add a design section for conditional dynamics.

---

## Polish Findings (Clarification & Minor Specification)

- **[CPP-5]** Audio Workgroup fan-out model for per-stem parallelism is unnamed. Name the primitive: "`os_workgroup_parallel_t` with `os_workgroup_parallel_start`/`finish`; worker threads pre-created, permanently joined, signaled via atomic store + `os_sync_wait_on_address` with deadline."

- **[CPP-6]** Bit-exact intensity-0 bypass insertion point and SRC interaction not specified. Specify the bypass as a hard wire in render block: "if `bypassActive`, `memcpy(output, input, byteCount)` and return; assert no SRC in chain at intensity 0."

- **[CPP-7]** Swift/C++ interop boundary ownership and RT-path calling convention not documented. Specify: facade is plain C header (extern "C"); ownership held by Swift AU class via `std::unique_ptr` managed on main thread; render block receives raw (non-owning) pointer captured at `allocateRenderResources` time.

- **[ML-4]** NL context field-allowlist described but not enumerated. Add positive enumeration: "context MAY contain: (1) current typed macro state (numeric only); (2) active profile EQ curve (numeric); (3) Reimagine intensity (0–100); (4) device category (headphones/speakers only, not device name); (5) submitted phrase text. Context MUST NOT contain: audio, hearing profile, track identity, artist/album, listening history, user identifiers."

- **[ML-5]** "~seconds/track" separation time estimate unanchored and misleading. Replace with "estimated 10–60 seconds per track depending on hardware tier and track length (to be measured in SPIKE-SEP-QUALITY); UI must show progress and allow cancellation."

- **[ML-6]** Stem count per hardware tier and QualityProfile scaling unspecified. Add provisional table: "Floor (M1 Pro/AC): up to 6 stems; M1 Pro/battery or thermal-throttled: reduce to 4 stems; fallback: 2 stems before dropping to mix-only."

- **[ML-7]** Reimagine knob dead-band above 0% lacks specified width. Add spec: "The dead-band spans 0–X% (exact value from user test; provisional: 5%); within this range, original mix only is rendered; stem engine activates and crossfade begins at dead-band exit."

- **[ML-8]** LRU stem cache has no specified size bound. Add default bound: "LRU cache default ceiling: 4 GB (user-configurable); at ceiling, evict least-recently-played tracks first."

- **[BA-3]** ADR-004 status inconsistent (Accepted vs. Proposed vs. contingent). Pick one status uniformly: "Accepted (dormant — no current RT ML workload; reserved for future use if needed)."

- **[BA-4]** NFR-QUAL-02 references "MacBook Pro M3" in acceptance criterion but floor hardware is M1 Pro (LD-18). Replace "MacBook Pro M3" with "the target hardware floor (Apple-Silicon Pro-class, M1 Pro, ≥16 GB, per LD-18)."

- **[BA-5]** The "imperceptible-as-motion" Phase-0 KPI gate has no acceptance criterion or verification method. Add explicit NFR or FR-ADAPT sub-criterion: e.g., "In a forced-choice listening test, fewer than 20% of listeners can identify which of two 60-second passages has adaptive parameter changes active (vs. static reference)."

- **[SEC-4]** Prompt-injection via track metadata / file contents is an unaddressed threat. Classify all file-derived metadata as untrusted; never place in interpreter prompt, or sanitize+escape it.

- **[SEC-5]** "Stems-only-from-local-files" is stated as intent, not enforced code invariant. Elevate to named invariant with enforcement point (separation pipeline accepts only local-file-handle source type) + test asserting tap path cannot reach separator.

- **[SEC-6]** Info.plist usage-description key + min-OS still unverified. Verify exact key + min-OS in `<CoreAudio/AudioHardwareTapping.h>` and record it; confirm whether tap and mic are distinct TCC services.

- **[SEC-7]** No update-channel / app-distribution integrity spec. State distribution/update channel; if Sparkle, require EdDSA-signed appcast; if App-Store-only, state and drop the HAL-plug-in-installer path.

- **[SEC-8]** Cloud-context allowlist contradictory across docs and not enumerated. Define one canonical allowlist FR enumerating exactly what cloud `context` may contain.

- **[SEC-9]** Crash-log / diagnostic leakage of user text and metadata not addressed. Add NL text + file paths/metadata to diagnostic-redaction list; gate any crash SDK on scrubbing.

- **[SEC-10]** Tapped-audio "never persists" lacks transient-buffer/scratch boundary. State tap path uses only ephemeral RAM buffers, no disk/cache/temp, and excludes tapped mix from pre-analysis/transparency caches.

- **[PM-2]** KPI target for Phase 1 NL "phrase success rate" (>75%) not defined operationally. Operationalize as "75% of submitted phrases that reach a confirmation card are not undone within 60 s of confirmation."

- **[PM-3]** "Perceptual-domain decisions" constraint not explicitly mapped to Arbiter design. Add explicit AC to US-PERC-01: "Arbiter's masking-relief contribution computed using ERB/Bark excitation-pattern subset model per LD-12, not raw dB magnitude curve."

- **[PM-4]** Phase 1.5 SPIKE-PERF-BUDGET gates the phase but is not listed in critical-path "Definition of Ready". Add note at top of Phase 1.5 in backlog.

- **[PM-5]** Hearing profile "non-medical positioning" rule (LD-7) but no acceptance criterion in backlog story US-HEAR-01. Add explicit AC: "All UI copy...uses term 'listening preference', explicitly disclaims medical device status."

- **[PM-6]** Reimagine knob intensity→parameter mapping curve (OQ-21) deferred but PRD hardcodes "default sits low-to-lower-mid" without numeric. Add SPIKE-REIMAGINE-MAP to backlog with concrete acceptance.

- **[PM-7]** Adaptivity Signal → Decision Matrix (requirements §5) NLT row lacks "governing principle clamp" detail. Expand "Direction / Rule" column to spell out the subordination rule.

- **[PM-8]** Backlog is missing explicit spikes for three open decisions (OQ-11, OQ-16, OQ-17) that block feature shipping. Create SPIKE-NLT-ARCH, SPIKE-IPREVIEW, SPIKE-LIBBS2B with each containing AC, effort estimate, and phase-gate status.

- **[PM-9]** Auditing trail for LD-18 (hardware floor) impact on risk register is incomplete. Add footnote to PRD §7 Risk R-1 and R-2: "Likelihood further reduced by LD-18 (M1 Pro floor, sole-occupancy): adaptive cadence can be conservative given large compute/memory headroom."

- **[PM-10]** No explicit "gates" defined between phases in backlog or PRD roadmap. Add "Phase Gates" section in backlog header defining go/no-go criteria and dependencies.

- **[BA-6]** FR-ADAPT-04 (ambient sensing) and OQ-03 are in unresolved conflict. In FR-ADAPT-04, mark timing values as "provisional — subject to SPIKE-AMBNOISE output" inline.

- **[BA-7]** NFR-REL-01 crash-free rate ≥99.5% has no verification method. Add parenthetical verification method: "Measured via crash-reporting SDK selected by SPIKE-TELEMETRY; a 'session' is defined as continuous app invocation from launch to quit."

- **[BA-8]** FR-NLT-09 protective reduction specifies ≥−6 dB but the discomfort keyword list is never defined. Add informative normative minimum list to FR-NLT-09.

- **[BA-9]** NFR-ACC-03 (Dynamic Type) has no acceptance criterion while every other NFR-ACC does. Add minimal Given/When/Then for text-size legibility test.

---

## Findings That Landed Clean (Solid Spine — Do Not Re-Litigate)

- **Locked decisions spine (LD-1…LD-19)** are consistently threaded through all three docs. PRD §0, requirements §0, architecture §0 all cross-reference the amendments. The v0.3 → v0.6 alignment is explicit in change notes. This spine is rock-solid.

- **Stem object engine (LD-15 / FR-STEM / US-STEM-*)** is coherent end-to-end. Phase 1.5 scope, acceptance, dependencies, and risks are well-defined. The re-sum mixbus (ADR-011, v0.3 amendment) is clearly traced through to US-STEM-02.

- **Conversational Tuning (FR-NLT / US-NLT-*)** is fully specified at the behavioral level, even though the mechanism (OQ-11) is deferred. All phrase types map to a unified DSP action-space per LD-8. The requirements §3.9.1 phrase-mapping table is comprehensive and the backlog stories implement each row. This is production-ready despite the mechanism being TBD.

- **Privacy posture (NFR-PRIV, hearing-profile storage, mic on-demand, telemetry opt-in)** is consistent across all docs. The tap-path high-consent framing (TCC + purple indicator + auto-exclude comms apps) is correctly reflected in requirements FR-SYS-07/08 and backlog US-SYSW-TAP.

- **OQ-11 deferral discipline** is well-executed. All FR-NLT-* requirements are specified at the behavioral/interface level (input → output) with the mechanism explicitly excluded. The SPIKE-NLT-ARCH output specification is complete enough to unblock behavioral story authoring.

- **Reimagine intensity-0 bit-faithful anchor** is thoroughly specified and consistently cross-referenced: FR-REIMAGINE-02, NFR-QUAL-03, US-RMG-01, architecture §5. This is the fidelity contract and the anchor is tight.

- **Patent/IP risk management** for FR-TONAL-04 (CON-11, OQ-16, SPIKE-IPREVIEW) is handled correctly: engineering is unblocked with the mono-sum design, the release gate is explicit, the legal task is scoped, and the requirement text names the specific patent numbers. This is a model for how to manage IP risk without blocking velocity.

- **Tap consent model (C9 core)** — high-consent framing, purple indicator, auto-exclude comms apps, explicit pre-prompt, graceful denial→fallback, and the "never persisted/never feeds stems" rule are all present and consistent across §13, FR-SYS-07/08, and Journey 2.6.

- **On-device-first NL posture** — rules-floor → on-device-LLM-primary → cloud-opt-in-only, with monotonicity validation mandated; the privacy default (no cloud unless opted in) is correct.

- **Control-plane/data-plane spine** (off-RT Realizer→RT kernel, lock-free param bus, intensity-0 bit-exact bypass, no program DRC by default, BRIR-first + exemptions, typed-macro NL, ERB masking subset, per-stem re-sum discipline, MLX-primary separation + weights download-on-first-run, 4-phase roadmap) has survived two expert-panel passes with no structural contradictions. It is the correct architecture and is ready to implement.

---

## Action Items for Product & Engineering

### Pre-Phase-0 Fixes (Week 1)
1. **BLK-4 (License)**: Fix DEP-14 and prior-art.md to remove "MIT (incl. weights)" overclaim.
2. **BLK-2 (Param-bus wire protocol)**: Write the concrete synchronization spec in architecture §14.
3. **BLK-8 (Hearing-safety bounds)**: Work with audio-engineering team to define numeric clamps.
4. **BLK-3 (Hearing-data-at-rest)**: Write concrete mechanism names into NFR-PRIV-03 and FR-HEAR-02.

### Phase-0 Gate Fixes (Must Resolve Before Phase 0 Sprint Kickoff)
1. **BLK-1 (Artifact-gate signal)**: Promote concrete proxy signal into architecture §6; move fallback ladder into FR-STEM-05.
2. **BLK-5 (IR hot-swap)**: Write object-lifetime section for hot-swap mechanics.
3. **BLK-6 (Loudness compensation fraction)**: Lock the fraction with audio-engineering team.
4. **BLK-7 (ABX test statistical design)**: Define the protocol (sample size, threshold, population).
5. **CPP-3**: Specify sample-rate/device-switch quiesce contract.
6. **SEC-5**: Define stems-only-from-local-files as enforced code invariant.
7. All PM/BA SHOULD-FIX traceability items: Update personas, phase gates, OQ-15bc gating, SPIKE shortlist.

### Phase-1 Gate Fixes (Must Resolve Before Phase 1 Sprint Kickoff)
1. **BLK-10 (OQ-15bc)**: Promote SPIKE-OQ15BC to mandatory Phase 1 pre-sprint gate.
2. All ML SHOULD-FIX items (MLX/Core ML decision tree, NL validation harness structure, stem count tiers, NL context allowlist).
3. All CPP POLISH items (Workgroup primitive naming, Swift/C++ interop boundary, QualityProfile scaling policy).
4. UX & Design System reviews (cross-check with ux-guidelines.md and design-system.md).

### Phase-1.5 Gate Fixes
1. **BLK-9 (Model-weight download integrity)**: Implement SHA-256 pinning and fail-closed verification.

### Ongoing / Not Blocking Engineering
- All remaining POLISH items (accept as tech-debt for post-Phase-0 refinement).
- All OQ resolutions that are not pre-conditions (e.g., OQ-21 on Reimagine mapping curve, OQ-22 on masking SPIKE output).

---

## How to Use This Review

1. **For Engineering Team**: Use the Blocker and Should-Fix sections as a checklist. Each item names the exact section/FR to update and the fix required. Work through blockers in the order listed; should-fixes before Phase kickoff.

2. **For Product / Architecture**: The Polish section and the "Solid Spine" section are for context and confidence. The solid spine should be protected as the invariant structure; the polish items can be batch-updated over time.

3. **For QA/Testing**: Read the new test-and-qa-strategy.md document. It defines the signal-correctness test catalog, RT-safety verification, and phase gates. Use this to author test plans and acceptance criteria.

4. **For UX/Design**: Read the new ux-guidelines.md and design-system.md documents. They define the interaction standards and visual tokens that the implementation must satisfy.

5. **For Next Review Round**: This review-v0.3.md will be superseded once the blocker and should-fix items are resolved. Plan a v0.4 review round after fixes are merged, focusing on the updated requirement/architecture consistency and the design-system implementation plan.
