# R1.1-B — sprint record

**Sprint:** R1.1-B — the decided medium items · **Routine:** the full loop, plus the whole-app break-it (it closes the R1.1 release) · **Size:** ~3 weeks as sized against the 2-week cap · **Branch:** `r1.1b/integration`
**What to build and how each item is proven:** [roadmap — R1.1-B](../product/roadmap.md#r11-b-the-decided-medium-items) · [the sound plan](../product/roadmap.md#the-sound-plan-decided-2026-10-23) · **How it runs:** [sprint plan — R1.1-B, how it runs](sprint-plan.md#r11-b--how-it-runs-the-plan-check) · **Process:** [00-sprint-model.md](00-sprint-model.md)

*This record holds the plan check, the founder's decisions at the gates, measured results, the done-done checklist and the retro. Status stays in code and git.*

---

## Plan check (step 0)

The full draft — seams S1–S5 with signatures, the Kit per rule, one owner per file, the design-note questions P1–P6, the counter-examples, the test plan per lane, risks, lane briefs — is [r1-1b-plan-check.md](r1-1b-plan-check.md), drafted read-only from `main` @ 0215f777. Its §0 found nine places where the plan as written did not match the code (Pure declines Bluetooth; album gain has no data source; the fold's peak arithmetic ignored the leveling gain; the engine cannot tell Compare from EQ Off; crash restore is not `QueueRestorePoint`; loose slots cannot persist; "Use this drive" cannot reuse the move-match; the search rule's two halves disagree; size). The answers below settle the founder-facing ones; the rest are design inputs the lanes carry.

## Decisions at the gates

**Plan check — the founder, 2026-10-25** (asked in plain language with options; "≠ R" where the answer differs from the recommendation):

1. **Leveling in Pure is deferred until the USB DAC arrives.** A correction came first: Pure declines Bluetooth, so the XM4 always plays Enhanced; the 2026-10-23 premise that Pure is the founder's daily mode was wrong. R1.1-B ships leveling in Enhanced; Pure shows "Leveling off (bit-perfect)"; the Pure cut on the device volume lands with the USB-DAC check, verified there. The "Volume restored" toast stays — it belongs to Master Gain's existing loan.
2. **Two PRs: the player PR first, then the sound PR.**
3. **The sound parts get a design note and the blind three-reviewer panel** before their code (the one analysis pass, the leveling gain and turn-down, the fold's arithmetic); the state rules and the player lanes get the normal architect + the-fool review.
4. **The founder names a few surround albums and loud masters; the coordinator runs a read-only analysis tool on them**; agents never read the founder's library; the founder does the LFE listen.
5. **Search: one word-start rule everywhere** — each tab keeps its own sort, ⌘F ranked; "eyon" no longer finds "Beyoncé" in the tab filters (accepted).
6. **"Use this drive": rebind silently; songs not on the new drive are removed with their history (≠ R); refused when none are found** — the founder kept the R1 "never wipe on an empty walk" floor when asked about a wrong drive.
7. **Shuffle: Previous at the first song of a pass** — Repeat All goes back into the last pass, Repeat off restarts the song; Up Next keeps the queue's own order this sprint.
8. **The Leveling setting lives in Settings (≠ R)**; S14-lite's Level card is built there too unless the founder decides otherwise then.

**Decided as recommended, unless the founder objects:** track analysis persists in a rebuildable derived-data file beside the library (keyed by file identity), never in the library DB; an album's tracks are analysed in the background once any of its tracks is queued; no library-wide sweep this sprint. Album mode before an album is fully analysed: album tags if every track has them, else the track's own gain until the next seam across silence — the level never steps at a continuous seam. A Leveling mode change mid-song applies at once with a short glide. Sinhala zero-width joiners are folded away in the index and the query (one additive index rebuild).

## How it runs (revised after the plan check)

At most two agents at once. The player PR comes first.

| Step | Slot A | Slot B |
|---|---|---|
| Before the lanes | **Coordinator:** the integration branch's first commit — the new targets in `Package.swift` (LevelingKit + tests, empty), the S5 slot type `QueueSlotRef`, migration numbers assigned (v10 queue state → lane 4; v11 search re-index → lane 5) | — |
| W1 — player | **Lane 4 — transport** (Swift): shuffle permutation + history; the atomic crash-restore record `QueueResumeRecord` with one coalescing writer; loose slots persisted by path (S5) | **Lane 5 — library** (Swift): `SearchRule` + ⌘F; loose files (Open…, drop, Open With, into a playlist); "Use this drive" (S4: re-root by relative path, missing removed, refused at none found) |
| W2 — player close-out ∥ sound design | **Player PR:** combine → T3 → slow checks (10k library, ⌘F with FKA; 100 kills) → review + break-it (QA agent + the-fool: store/library, transport) → one fix round → T4 → founder's check → **PR 1** | **The design note** (audio-DSP): `docs/design/level-and-fold/` — the analysis pass, album pooling (P2), the cap and turn-down with the leveling gain and the N-channel peak (P1, P3, P5), the LFE rule (P4), Compare (P6) |
| W3 — the panel | Reviewer 1 — the breaker; then reviewer 3 — architect + the-fool | Reviewer 2 — the state-of-the-art challenger; then the author's one revision |
| W4 — sound build | **Lane 1 — sound core** (audio-DSP): the analysis pass + persistence, the level stage, the turn-down, Compare matched, the old leveller deleted | **Lane 2 — fold** (a fresh audio-DSP): the matrix from roles, the per-track trim with the leveling gain, the LFE gain, the backstop + meter, the crossfeed-bypass signal (S2) |
| W5 — sound UI | **Lane 3 — leveling app side + sound UI** (Swift, SwiftUI review): LevelingKit (Auto, sources, album scope), the coordinator, the Leveling row in Settings, the shared "Not in bit-perfect mode" state, the "5.1 → stereo" badge, the Pure reason, the XF chip from S2, "Volume restored" | — |
| Sound close-out | **Sound PR:** combine → T3 → slow checks (the founder's corpus via the read-only tool; the gain-reduction meter) → review + break-it (audio) + **the whole-app break-it** (release close-out) → one fix round → T4 → founder's check incl. the two LFE albums → **PR 2** → the R1.1 release decision | — |

Lane 3 is one lane again: with the Pure loan deferred, the plan check's 3a / 3b split no longer pays.

## Measured results

*(filled as lanes land: the measurement named by each acceptance line, as a number)*

## Done-done

```
Sprint R1.1-B — the decided medium items · routine: full · SP 8+8+player items · cap 2 weeks (≈3 as sized)
Plan check   ☐ routine named ☐ owners and seams named (stubs agreed) ☐ Kits named
             ☐ lanes and waves ☐ counter-examples for rule changes ☐ founder check written
Build        ☐ every acceptance line of the roadmap row met by its named measurement
             ☐ tests on the real code ☐ every breaker's red test committed
Gates        ☐ T3 combine-check exit 0 ☐ T4 strict-gate / CI exit 0, run complete
             ☐ break-it findings fixed, or logged in known issues with a forward
             ☐ the whole-app break-it (release close-out)
Founder      ☐ checklist passed (by ear / eye / hand) ☐ the two LFE albums, pass / fail
Merge        ☐ PR 1 (player) merged by the founder ☐ PR 2 (sound) merged by the founder
             ☐ main CI green on the merge commit
Close        ☐ this record + five-line retro ☐ known issues ☐ sprint-plan §Status line
             ☐ documents reconciled (plan + reasons only) ☐ memory updated
             ☐ worktrees removed (no running app inside) ☐ points and duration recorded
```

## Retro

*(at close-out)*
