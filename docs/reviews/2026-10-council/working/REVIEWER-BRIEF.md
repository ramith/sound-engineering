# Council code reviewer brief (Stage 2): read fully before starting

1. Read **CHARTER.md** (the bar: six criteria, severity, rules) and **00-map.md** (the shared codebase map) in this
   directory. The repo is `/Users/ramith/code/sound-engineering` @ main (7d7c2cd). READ-ONLY on Sources/Tests/scripts.
   Never launch the app or play audio. If you must build or run an experiment, make your own worktree
   (`git -C /Users/ramith/code/sound-engineering worktree add --detach .claude/worktrees/rev-<you> origin/main`) and
   put scratch files under `scratchpad/council/exp-<you>/`.
2. **Your job:** judge DESIGN MATURITY in your area against all six charter criteria:
   1. elegance (not brittle, not tactical);
   2. design patterns where required (including over-engineering);
   3. no duplicated code or capability;
   4. algorithmic correctness;
   5. state of the art (OPEN sources and cite links);
   6. maturity (testability, error handling, trust-me escapes).

   Passing lint means nothing here. Drop lint-level nits.
3. **For every finding, use this format:**

   ### <ID> <short title>, STRUCTURAL | SIGNIFICANT | LOCAL. Criteria: <1–6>
   - **Evidence:** file:line (several where it is a pattern), with a short quote.
   - **Root cause:** the design choice that allows it (not the symptom).
   - **Why it matters:** the concrete failure, cost, or what it blocks (e.g. testability, R2 features).
   - **Structural remedy:** the target design (the pattern, the ownership, the type that enforces the rule), not
     "patch line X". Name the state-of-the-art reference if one applies.
   - **Effort:** S / M / L. **Risk of the change:** low / med / high. **Depends on:** other findings, if any.
4. **Also report:**
   - **What is GOOD:** the designs to keep and copy elsewhere, a short list.
   - **Duplicated capability** you noticed (it feeds the duplication pass).
   - **Algorithms** you think need a correctness panel (reference the map's D-/N- row IDs).
   - **Open questions** for the founder.
5. **Don't re-report known items without new insight:** the main-thread audit and its evidence, the G break-it
   reports, and the ledger's "Logged post-R1" lists. Reference them by name. Prior council findings worth knowing:
   - **product.md:** Pure isn't persisted; Intensity's wet stages are placeholders; the session-wide leveller; cross-library
     search exists but is never used by the app.
   - **memory-review side notes:** `scripts/build-eq-clamp-test.sh` compiles deleted files; `SpatialRenderKernel.h`
     points at a renamed file.
   - **process.md:** the app target can't be imported by tests (testability design is handed to the architecture reviewer).
6. **Output:** write your full report to `scratchpad/council/<your-file>.md`. Return a summary of under 600 words:
   the counts by severity, the top findings (ID, title, one line each), the good designs, and the open questions.
   Skip any context-manager step.

(scratchpad = /private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad)
