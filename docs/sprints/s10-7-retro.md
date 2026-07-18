# S10.7 retro — Liquid Glass release UX (closed 2026-07-19)

8 build milestones, all founder-accepted per-PR; break-it round run and fixed; PR #61 merged
with hosted CI green on the pinned toolchain. 205 headless tests / 34 suites / 0 known
issues at close. Decision record + acceptance evidence: `s10-7-visual-matrix.md` (the
ledger); build contract: `s10-7-liquid-glass-design.md`.

## What worked (keep doing)

1. **The R4 geometric contrast audit is the sprint's best artifact.** Pure WCAG math over
   the same Kit data the render reads. It caught 4+ real design defects before pixels
   shipped (tertiary/panel 4.46, badge secondary-text 4.26, teal-core 3.98 → placement
   rule, bleed-stratum 4.18 at the break-it round), and the withKnownIssue pin mechanism
   flipped "loud" exactly as designed when D10 fixed the dark pairs. The D8 clamp-lattice
   extension proves art-sampling can never break contrast — by construction, not sampling.
2. **Per-chunk SME reviews before founder rounds** paid for themselves every time: the
   jump-vs-filter blocker (PR 5), the D8 cache-key blocker + audit-domination hole (PR 7),
   the seam-fix stale-session hole. Founder tuning rounds were never spent on
   reviewer-catchable defects.
3. **The founder screenshot loop caught what NOTHING else could**: the Menu-label readout
   that never rendered, the wrong-song-after-device-switch bug, the stale-binary trap,
   footer truncation, the perception trap of a teal album cover. Runtime eyes are
   irreplaceable in this rig.
4. **The break-it round (qa-expert + the-fool) was worth its cost**: one empirically-proven
   pre-existing BLOCKER (end-of-queue never stopped), two MAJOR engine races, the Pure-lens
   freeze, the audit-domain drift, and the honest re-scoping of "0 known issues."
5. **Strictly incremental founder-verifiable milestones** kept a design-from-scratch sprint
   controllable; the frozen-tokens stopping rule (PR 2) bounded the tuning loop as intended.

## What failed (fix the process)

1. **Every RUNTIME bug was founder-caught; every STATIC bug was rig-caught.** The rig has no
   runtime eyes (views untestable by target structure; no snapshot tests — deliberately
   rejected; no launch automation). Survivable for one tab with per-PR founder rounds; it
   will NOT scale to S10.8's 4 tabs. → The R3 snapshot decision moved BEFORE S10.8 (was
   bound to its DoD — too late).
2. **Ledger discipline leaked once**: PR 5's required Instruments row was silently dropped
   (no result, no TEMP entry). Corrected retroactively; the founder ran it at close-out
   ("perf test is ok", 2026-07-19). Matrix cell debt has no automated expiry
   (docs/ is outside check-suppressions.sh) — remains a manual risk.
3. **Tool-version skew broke the "identical hosted CI" promise on first contact** (CI brewed
   SwiftFormat 0.62.1 vs local 0.61.1 → 74 phantom failures). Fixed durably: pinned release
   binaries in CI + the gate ASSERTS the pins. Lesson: any promise of environment identity
   needs an enforcing assertion, not an intention.
4. **Mechanical acceptance lines aren't diffed against code**: PR 3's "ONE overlay view (not
   88 diffed siblings)" was violated in the very PR it gated, through SME review + gate +
   founder sign-off. Founder's perf run says it doesn't matter in practice — but the class
   (design-table claims nobody re-checks) is real; reviews now get the acceptance row
   pasted into the brief.
5. **The branch lived 50+ commits on one laptop before CI/backup** — push + draft PR should
   happen at the FIRST commit of a sprint branch, not the close-out.

## Changes adopted for S10.8

- Sprint branch → push + draft PR on day one (CI per commit).
- R3 snapshot-test decision taken at sprint OPEN (a text-free decoration snapshot per the
  recorded NSHostingView recipe is the candidate), because founder-only runtime verification
  won't scale to 4 tabs.
- Reviews receive the design-table acceptance row verbatim (mechanical-conformance check).
- External design audits (DEVIATIONS.md pattern) are useful but MUST be triaged against the
  decision ledger before becoming work — half of the first one was already-shipped/by-design
  (`s10-8-deviations-plan.md`).
- Light-mode gets equal dwell time in founder rounds (every light defect this sprint was
  found late).
