# Council algorithm-correctness panel brief (Stage 4): read fully before starting

Charter criterion 4: **"Algorithmic correctness: every algorithm checked against a reference (literature / spec / an
oracle) and PROVEN by tests."** Criterion 5: **state of the art.** Read `CHARTER.md` and §8 of `00-map.md` (the
algorithm inventory: D-rows = DSP, N-rows = non-DSP; each row has file:line, what it computes, its cited reference and
its test coverage) in this directory. The repo is `/Users/ramith/code/sound-engineering` @ main (a206107).

## Method: adversarial and independent
- You are one of several independent panelists. Don't assume the code, its comments, its tests or earlier reviews are
  right. Earlier evidence exists (`docs/design/eq-lens/evidence/` for the Sprint EQ panels, and
  `docs/architecture/evidence/main-thread-stall-2026-10/`). You may read it AFTER forming your own view, and must
  say where you agree or disagree.
- For each algorithm in your panel:
  1. **Specify it:** what it must compute, and its invariants (from the literature or spec, not from the code). Open
     the reference (standard, paper, vendor doc, an established implementation) and cite it with a link or section.
  2. **Check the implementation against the spec:** read the code (file:line); derive or recompute independently.
  3. **Try to FALSIFY it:**
     - **Breaker role:** build your OWN prototype or oracle (Python / numpy, or a small C++ / Swift harness) and
       compare it against the real implementation's output, or drive the real code through its existing harness with
       adversarial inputs: edge cases, extreme parameters, boundary sample rates, 1 / 2 / 6 / 8 channels, long
       durations, degenerate data, interleavings.
     - Build and run only in your own worktree
       (`git -C /Users/ramith/code/sound-engineering worktree add --detach .claude/worktrees/panel-<you> origin/main`,
       then `git submodule update --init third_party/libebur128`), with scratch files in
       `scratchpad/council/exp-<you>/`. Never launch the app or play audio to a device. Never edit the repo's
       Sources / Tests on main.
  4. **Judge the existing tests:** do they PROVE the property (an independent oracle, a tolerance justified by the
     spec), or do they just mirror the implementation / pin today's output (a golden hash)?
  5. **State of the art:** is this the right algorithm today? Name the better-established alternative, if any, and its
     cost.
- **Verdict per algorithm:**
  - **PROVEN-CORRECT** (a spec'd and independently verified test exists);
  - **CORRECT-UNPROVEN** (looks right; no adequate test; say which test is missing);
  - **DEFECT** (wrong: evidence + repro);
  - **QUESTIONABLE** (the right answer depends on a product decision, or the algorithm choice is dated).

## Output
Write the report to the file named in your prompt: a table (row ID → verdict → evidence → missing proof), then details
for every DEFECT / QUESTIONABLE, in this format: ID, title, STRUCTURAL | SIGNIFICANT | LOCAL, the evidence, the
root cause, the remedy, effort / risk. Return a summary of under 500 words: the counts per verdict, every DEFECT
with its evidence, and the top missing proofs. Skip any context-manager step.

(scratchpad = /private/tmp/claude-501/-Users-ramith-code-sound-engineering/737ceb91-aaa1-4ae6-bf56-9f296592de83/scratchpad)
