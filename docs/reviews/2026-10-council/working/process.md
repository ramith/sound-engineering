# Council: sprint / process review (S10.8 glass sweep → R1)

Reviewer: sprint / process. Read-only. Scope: how the work was delivered from the sweep plan (PR #67, 2026-10-06)
to R1 (PR #87, 2026-10-13): Sprints A–G, the behaviour pull-forward, Sprint EQ, the Sprint G break-it fixes, and the
disconnect-freeze fix. Code findings belong to the architecture and area reviewers. This file only covers code where
it explains a process gap, and it hands those items over in §8.

**Evidence used:** `docs/sprints/s10-8-sweep-ledger.md` (every sprint record and mini-retro),
`docs/sprints/s10-8-glass-sweep-plan.md` §D/§G, `docs/sprints/sprint-plan.md` §Status, the two Sprint G break-it
reports, the coordinator's memory (`feedback-*`, `reference-subagent-monitoring`, `project-s10-8-glass-sweep`),
`git log`, `gh pr list` (#48–#87), `gh run list`, per-stage timings from CI logs (runs 37934130983 for Sprint D and
38356081216 for Sprint G), the failed main run 38399071177, the CI workflow, and the GitHub repo settings.

---

## 0. The short version

1. **The process corrects itself, and it works.** Each mini-retro produced a rule that the next sprint used, and
   the founder's "never-ending loop" complaint led to the risk-tiered lighter routine (decision 18). After that,
   sprints closed in about a day each. Break-it, the live pass and the bounded adversarial panel found almost every
   serious bug before the founder did.
2. **The gates guard the wrong layer.** About 77 % of the 87-minute CI run is C++ sanitizer runs of the DSP kernel.
   All 13 Sprint G blockers and the freeze were in **Swift app logic, concurrency and real-hardware behaviour**.
   There the gate runs no tests of the real code, because the playback view model sits in the executable target and
   its tests use a mirror. The gate also never runs Swift under TSan and has no hang detector.
3. **No rule enforces "CI is the gate".** `main` has no branch protection and auto-merge is off. Through Sprint F
   the agreed gate was the local strict gate, so merging a few minutes after opening a PR was fine. Sprint G switched
   to "CI is the gate" but merge habits stayed the same: #85, #86 and #87 merged mid-CI. `cancel-in-progress` also
   cancels **main** runs, so the freeze-fix commit (dd5e02d) never got its own main verdict (its run was cancelled at
   66 min). The next main run failed.
4. **Timing-sensitive tests are now a pattern, not an incident.** There were five or more timing flakes in seven
   days, and the latest one blocks the R1 tag. A required check alone would not have stopped it: the same test
   passed on #86's PR run. Timing tests need a stress-under-load rule.
5. **The founder is acting as the process's control loop.** Each founder intervention (stopping the agents to ask
   whether they were useful, "one PR please", "is every gate stage needed?", pausing to confirm the council's
   objective) marked a gap the coordinator should have closed itself. Fix this with an echo-back rule for large
   efforts, a fixed ask-vs-decide list, a single decision digest, and a short "Now" status.

---

## 1. What worked: keep it

| Practice | Evidence |
|---|---|
| **Ledger + five-line mini-retro that changes the next sprint** | A → "live FKA keyboard pass" (used from B on); C → "agents run Periphery", "list counter-examples"; pull-forward → "live pass before review" (D found Esc focus loss that way); E → "name cross-owner seams". |
| **Risk-tiered lighter routine (decision 18)** | Sprint A: 10 feature to 22 fix commits, plus the founder's "never-ending loop". From C on: review + break-it only for keyboard / data / store / audio work. D, E and F each closed in about a day with one fix round. |
| **Break-it as first-class** | Every break-it found something material: A (⌫ deleted the playing track under FKA), C (the open path would show an empty library on any migration failure), EQ engine (NaN latch, wrong glide key), E (disc interleave), G (13 R1 blockers). |
| **Coordinator's live pass with real CGEvents on the 10k stress library, before code review** | It found the End-key freeze (15.1 s → 0.04 s) that no test could find, and it let three sources feed ONE fix round in Sprint E. |
| **Isolated test library + 10k stress library** | Its first scan found the FLAC album-artist bug, and every repro ran off the founder's data. |
| **Real-library upgrade protocol** | Backup, verified copy, compare: v6 → v7 with playlists and every user column identical. |
| **Adversarial 3-reviewer panel with opened evidence, capped at 1 revision + 1 verify** | The EQ panel found the Intensity-blend blocker before any code existed. All three freeze-fix reviewers independently found the stale-`ended` regression, and the breaker found a crash. Both loops stayed bounded. |
| **`sample` + an independent audit walled off from the fix** | It turned "I thought it crashed" into a stack and a fix in hours, and the audit found five main-thread engine paths, not just the one reproduced. |
| **Root-cause flake fixes, not re-runs** | EQ_Cpu at 768 kHz (scaled per rate), ANALYZER-05 (contract documented, test made deterministic, ANALYZER-06 added). |
| **Parallel lanes split by file, agreed API + stub, one consolidated PR** | Merges stayed nearly conflict-free. The founder reviews one PR. |
| **Decisions numbered, recommendation first, founder check under 10 min scripted from the diff** | 22 decisions (16–37) in seven days, each recorded with its why. |
| **Read the gate's real exit code** | Adopted after the July Periphery masking. Every ledger gate line now reads "EXIT 0". |

---

## 2. What hurt

### 2.1 Time

- **CI went from about 20 min to about 80–87 min at Sprint EQ.** The C++ null test grew from 122 to 198 tests.
  Per-stage times:

  | Stage | Sprint D (10-09) | Sprint G (10-13) |
  |---|---|---|
  | Static checks (format, lint, semgrep, clang-tidy, cppcheck) | 1.5 min | 2.7 min |
  | Periphery | 3.5 min | 4.1 min |
  | `make gate` (null test debug + VerifyAUGraph + VerifyLibraryStore) | 2.2 min | 9.5 min |
  | Sanitizers (ASan/UBSan null, TSan null, store ASan) | 10.8 min | **66.9 min** |
  | Leaks | 0.5 min | 1 min |
  | **Total** | **~20 min** | **~87 min** |

  Two silent stretches of the null test account for about **52 min** across its three builds: debug 6 min, ASan
  17 min, TSan 29 min. One sits between the FileDecode block and the first Realizer re-initialisation, the other is
  the tail after the last loudness line. They are almost certainly the EQ-era accuracy, CPU-budget and soak tests.
  Sanitizers find memory errors and races. They add nothing to an arithmetic accuracy sweep or a CPU budget (the
  CPU tripwire even flaked under TSan in Sprint E). The suite already has `--parallel` and parallel-safe flags, but
  the gate runs it serially, one long job.
- **The local strict gate takes about 45 min**, and the sweep re-ran it per merge until batching (B retro).
  Renders slowed from about 1.5 to about 40 min while the Mac sat idle (B retro).
- **Sprint G was planned at "about 4–5 hours wall-clock".** It ran from about 17:00 on 10-12 to #85 merging at 07:38
  on 10-13, then the freeze fix until 11:36. The plan had no reserve for what the whole-app break-it would find.
- **Flake re-runs:** ANALYZER-05 re-runs stretched #81 and #82 to about 10.5 h wall-clock.

### 2.2 Quality escapes
These are covered in §3: 13 R1 blockers in older code, found only by the final whole-app pass, and a 3–7 s freeze
found only by the founder on real hardware. Smaller escapes: a format error reached a merged branch (the worktree
swiftformat hole), Periphery leftovers after a merge, a merge-resolution commit that skipped the pre-commit hook.

### 2.3 Founder load
- **22 founder decisions in seven days** (16–37), about 10 founder checks, 15 PR merges, plus permission prompts.
- **Process interventions by the founder:** "never-ending loop" (A/B); stopping the agents to ask whether they were
  useful (pull-forward); "one consolidated PR please" (G); "is every gate stage needed?" (G); "pause" four times
  (10-08, 10-09 ×2, 10-10); pausing the coordinator to confirm the council's objective (today). Each of these is
  the founder doing process control.
- **The status line is one ~900-word paragraph** (`sprint-plan.md` line 74). It is accurate, but it is not a
  glance-able "what's happening and what do you need from me".

### 2.4 Rework
- **Fix to feature ratio in the sweep: 142 `fix` : 84 `feat` commits** (317 commits since 10-06). Much of this is
  healthy: old bugs found and fixed, for example 42 `fix(s10.8 G)` commits. But Sprint A's 22 fix commits and
  Sprint C's three fix rounds were partly self-inflicted.
- **Fix rounds caused the next MAJORs.** "Year out of identity" fixed compilations and merged Weezer's two albums;
  v7 was amended in place twice and left dev stores un-openable. The "counter-examples before coding" rule (C retro)
  is the right cure. Keep it.
- **Lost agent context.** A worktree deleted too early meant a fresh agent had to relearn about 500k tokens of
  context (C).

### 2.5 Agent operations

| Incident | Count | Status today |
|---|---|---|
| Usage limits killed agents mid-work | ≥ 5 (EQ ×2, E ×3) | Resumed by raw ID, nothing lost. Rule: commit early. |
| Permission prompts silently declined ("stream closed") | 3 agents (10-10), 4 agents (10-12) | Recovered by founder "resume". No structural fix. |
| Claude Code restarts | 2 (10-12, 10-13) | Resumed by raw ID; a gate process survived. |
| Agent compiled with the main checkout as cwd → stray build files in the repo root | **2 (57 files 10-08, 40 files 10-12)** | A brief line was added after the first one, and it **recurred**. A memory note was not enough. |
| Worktree deleted under a running app → VoiceOver said "not responding" | 1 (10-13) | Memory rule added. |
| Worktree-only tool holes: swiftlint crash on `.claude/worktrees`; swiftformat skips everything in a worktree (`--exclude .claude` matches the worktree's own path); submodule missing in worktrees; agents not running Periphery | 4 | Worked around with briefs and "lint on main after merge". The root cause (directory-walk + exclude globs) is not fixed. |
| Unchanged agent worktrees auto-removed on stop | several (G) | Recreated from branches. |

---

## 3. Quality escapes: why the gates and reviews missed them, and what would catch the next ones

### 3.1 Root causes

| Escape | Where it lived | Why every layer missed it |
|---|---|---|
| **8 playback / device / gain blockers (B1–B8)** | `AudioViewModel` and its ~10 extension files, in the **executable target** | No test target can import the app. `AudioViewModelTests` tests a **"state-machine mirror"** (`MockAdvanceController.swift`, per the Package.swift comment), not the real code. Breaker B had to copy the real sources verbatim into a harness, and 10 of 11 scenarios failed on main. The gate has no test that runs the real transport logic, and no Swift TSan. |
| **G-LIB-01 concurrent same-folder walks deleting on-disk songs (data loss), G-LIB-06** | App-side scan scheduling (`LibraryModel`), outside `VerifyLibraryStore`'s reach | **Known and deferred:** the C2 record (ledger, Sprint C "Deferred" item 4) says the app-side `scanTask` guard and `removeLibraryFolder` "have no automated proof (the app is an executable target…)". The deferral had no owner and no sprint, and four days later the same area produced data loss. |
| **G-LIB-05 no launch catch-up** | Launch path | **A debug convenience masked it:** the test library's launch rescan hid it in every live pass (G retro). |
| **.aif not scanned** | Extension list | No table test of "every format we claim" against a real fixture. |
| **B8 Master Gain launch value never sent** | Launch path | Same class as G-LIB-05: the launch path was never exercised as production runs it. |
| **3–7 s disconnect freeze** | Main thread → AVFAudio → HAL device lock during teardown | Visible only with **real hardware teardown**. Agents can't unplug devices; the G live pass used silent aggregates and device-level mute, and logged "device lost while playing = founder's check". Tests use fakes. Sanitizers don't see waits. No hang detector runs in debug builds. The fix added a semgrep guard + `make main-thread-stall` for **this** class only. |

**Two underlying causes:**
1. **Gate effort is allocated by history, not by risk.** The DSP kernel is the most-gated code and was stable. The
   Swift app layer holds the state machines, the scheduling and the device handling, and it is the least gated.
2. **Break-it was scoped to each sprint's diff** (decision 18), and the sweep's diffs were mostly UI. Old behaviour
   code (S10.x, July) got its only adversarial pass at the S10.7 close (which found "end of queue never stops") and
   then again at Sprint G. So risk built up in code that no diff touched, and it all landed on the day before R1.

### 3.2 Cheap structural checks

| Check | Cost | Would have caught |
|---|---|---|
| **Make the real transport / scan logic testable, and adopt breaker B's VM harness into CI.** The harness exists today on `breakit/s10-8-g-playback-shell`, pushed but **not merged and not in any gate**. Stopgap: run it in CI as-is (it copies the real sources). Real fix: move the view-model logic into an importable target (design → architecture reviewer, §8). | S (stopgap) / M–L (real) | B1–B8 and regressions of their fixes |
| **Add `swift test --sanitize=thread` to the gate** for the Kits and view-model tests. The freeze verify already used it. | S, plus minutes | Swift data races (e.g. the logged `SpectrumDoubleBuffer` race) |
| **A main-thread hang watchdog in DEBUG builds.** A background thread pings the main queue every 50 ms. If there is no reply within 250 ms, it writes `[HANG] main blocked N ms` to a file in the app's data folder (an `open`-launched app's NSLog never reaches `log show`, per memory) and, once per episode, runs `/usr/bin/sample <pid> 1`. It is off in release. | S (~100 lines) | The End-key freeze (10-08) **and** the disconnect freeze. It turns every live pass and every day of the founder's daily use into a hang detector, with a stack, without asking the founder to reproduce under a recorder. It covers unknown hang classes, where the existing self-test covers only the engine-lock class. |
| **A hardware-in-the-loop (HIL) checklist for any change touching audio output, devices or transport** (5–10 min, founder, watchdog on). Pass = right behaviour **and** an empty hang log. | founder 5–10 min per audio/device sprint | The freeze, B3/B4/B5 on real devices |
| **A rotating area break-it each sprint** (see §3.3) | ~1–2 agent-hours / sprint | The 13 blockers, spread over earlier sprints instead of landing the day before R1 |
| **The production launch path in every live pass.** One `make run`-style launch on a copy of a real-shaped store, not only `-ASTestLibrary`. Or the rule "debug hooks must mirror production" (G retro), enforced in review. | S | G-LIB-05, B8 |
| **Deferred testability gaps become tickets** with an owner and a sprint, checked at the next plan check | S | G-LIB-01/06 (flagged 10-08, found as data loss 10-12) |
| **Format table test:** every extension the scanner claims × a real fixture | S | .aif |
| **Instruments "Hangs" / `xctrace`** in the release pass (G2 used Instruments only for scroll) | S | Hitches under 1 s that people don't report |

### 3.3 Break-it: per sprint, per release, or both?

**Recommendation: both, plus rotation.**
- **Keep the per-sprint scoped break-it** for keyboard / focus / data / store / audio / device / concurrency work.
  It found something real every time.
- **Add one rotating whole-area pass per sprint**, regardless of the diff, cycling through: playback / transport →
  output devices / Pure → library / scan / store → EQ / DSP → shell / lifecycle / launch. Every area gets attacked
  at least once every ~5 sprints, and each pass's harness and red tests are **merged as regression tests**, not left
  on a reference branch.
- **Keep the whole-app pass on the release candidate.** With rotation it should find little. If it finds a lot, the
  rotation is too slow.
- **Budget a fix reserve in every plan** (say 30 % of the sprint) for what break-it finds. Sprint G's "4–5 hours"
  had none.

---

## 4. Definition of Done and merge policy

### 4.1 Definition of Done

**Every change (PR)**
1. The objective and acceptance criteria are written in the brief or PR. For a large effort, the founder has said
   "yes" to an echo-back (§6.1).
2. The fast check is green locally, with the real exit code read.
3. Logic is tested against the **real** code path, not a mirror. A product-visible rule change lists its
   counter-examples as tests.
4. **A new concurrency or timing test** was run ~200 times under CPU load and once under TSan before landing, with
   the result in the PR (§4.4).
5. Review fits the risk tier (§4.3).
6. **The required CI checks are green on the PR head. It merges by auto-merge, never by hand mid-CI.**
7. No deferred testability gap without a ticket (owner + sprint).

**Every sprint**
1. Every PR meets the DoD; the founder gets one consolidated PR.
2. The coordinator's live pass runs on the 10k stress library **and** the production launch path, before code review.
3. Scoped break-it per risk + the rotating area pass; their harnesses are merged as tests.
4. Audio / device / transport changes: the founder's HIL checklist with the hang watchdog on.
5. Founder check under 10 min, scripted from the diff.
6. Mini-retro. **Each retro rule becomes an enforced check (script, semgrep, gate step or brief template) within one
   sprint.** A memory note alone is not enough: the stray-build-files rule was a note and recurred.
7. Main's push-CI is green after the merge.

**Every release**
1. Whole-app break-it on the release candidate.
2. The full HIL checklist + an Instruments Hangs pass.
3. A first-launch smoke test on an empty data folder (not the test-library hook).
4. **Tag only a SHA whose main push-CI is green, and make `release.yml` check it** (query the SHA's check runs; fail
   if `strict-gate` isn't `success`). Today this is a coordinator habit, not a rule.
5. Known-issues updated.

### 4.2 Merge policy

What the record shows:
- **Through Sprint F, PRs merged 0–11 min after opening**: #68 2 min, #69 11, #71 2, #72 0, #74 1, #75 3. The local
  strict gate on the merged branch was the agreed gate (EXIT 0 read), so this was by design. Only #70 and #73 had a
  finished PR CI at merge.
- **Sprint G changed the model to "CI is the gate" but enforced nothing.** #85 merged ~8 min before its PR CI
  finished; #86 ~66 min before; #87 ~8 min into an ~80-min run.
- **`concurrency: cancel-in-progress: true` applies to main too.** 7 main runs were cancelled by a later push in
  the window, including **dd5e02d, the freeze fix, cancelled at 66 min.** The freeze-fix code never had a main
  verdict of its own.
- **Main run 38399071177 on 7d7c2cd then failed:** `RenderGate_ConcurrentNeverOverlaps` — "close() timed out at
  seek 1304" in the debug null test, 18 min in. #87 changed no C++ code. **The same test passed on #86's PR run in
  both debug and ASan (201/201).** So it is a timing flake: a 1 s wall-clock `close()` deadline
  (`Tests/RenderGateTests.inc:197`) on a spin-race test, on a small shared hosted runner. It now blocks the R1 tag.

What this means: requiring the check before merge is **necessary**. It would have stopped #87 merging blind and kept
CI as the gate. It is **not sufficient**: one green run cannot exclude a timing flake. The stress-under-load rule
(§4.4) would have caught this one. Both are needed.

**Recommended policy**
1. **Turn on a GitHub ruleset for `main`** (free, the repo is public; it has no protection today): require the CI
   status checks, no direct pushes (the coordinator's closing-docs commits go into the sprint PR or a docs PR),
   founder bypass for emergencies only.
2. **Turn on auto-merge** (`allow_auto_merge` is `false` today). The founder clicks "Enable auto-merge" when done
   reviewing and walks away; it merges only when the checks pass. This removes both the waiting and the mid-CI merge.
3. **Never cancel main runs:** `cancel-in-progress: ${{ github.event_name == 'pull_request' }}`. Every main commit
   gets a verdict.
4. **Tag only a green main SHA**, enforced in `release.yml`.
5. **A red main is a stop-the-line event.** It is fixed at the root the same day, and no tag or new sprint merges
   until main is green again.

### 4.3 Which changes need which checks

Detect changed paths in a first job, and give heavy jobs a job-level `if:`. **Gotcha:** a workflow skipped by
workflow-level `paths:` filters leaves a required check stuck "Pending" and blocks the merge. A *job* skipped by
`if:` reports success. So use one workflow, a "changes" job and job-level conditions.

| Change touches | Local before push | CI jobs (parallel runners) |
|---|---|---|
| `docs/**`, `*.md` only | none | `docs` (link / markdown check, ~1 min) |
| Swift UI (views, design system, UI-only Kits) | **fast check**: swiftformat + swiftlint + semgrep + periphery + build + `swift test`, + sheets for changed screens (~5–10 min) | `fast` |
| Swift logic (view model, library model / scan, store, bridge Swift, device policy) | fast check + `VerifyLibraryStore` + `make main-thread-stall` + Swift TSan on touched tests | `fast` + `swift-logic` (VerifyLibraryStore, stall self-test, Swift TSan, VM harness) |
| C++ / `.mm` / AudioDSP / C-ABI | full local gate (as Sprint G did for engine / store lanes) | `fast` + `cpp-debug` (null test, -O2, VerifyAUGraph) + `asan` + `tsan` + `leaks` |
| `Package.swift`, `scripts/strict-gate.sh`, `Makefile`, workflows | full local gate | **all jobs** |
| Push to `main`, and nightly | — | **all jobs, never cancelled** |

**Faster CI with no loss of coverage:**
1. **Split the serial job into parallel jobs.** Wall time becomes the longest job (TSan, ~40 min today) instead of
   the sum (87 min).
2. **Print elapsed time per null test**, then run accuracy sweeps and CPU-budget tests only in the debug and -O2
   builds, not under ASan or TSan. These blocks are ~52 of the 87 min. Expect sanitizer stages to fall back toward
   Sprint D's ~3 min ASan / ~6 min TSan (to be measured, not assumed).
3. **Use the existing `--parallel` runner** for the parallel-safe tests in the debug and ASan builds.

Likely result (to verify): a UI PR at ~10 min, a C++ PR at ~25–40 min wall-clock, main at the same. This answers
the founder's "is every stage needed for every change?": **no for PRs** (tiered by risk), **yes for main and
nightly**.

### 4.4 Timing-sensitive tests and flakes

Five or more timing flakes in seven days: `EQ_Cpu_7_1_AboveSupportedRates` (TSan, E), ANALYZER-05 (CI interleaving,
two PRs, G), `Snapshot_Seqlock_ConcurrentNoTear_RACE1` (`--parallel`, G), G-RACE-2 (3/100 on main, logged),
`RenderGate_ConcurrentNeverOverlaps` (1 s deadline, main CI), and the `eq-light-folded` sheet-renderer flake.

Rules:
1. **No wall-clock deadline a busy scheduler can hit.** Use count-based progress, or a generous timeout (≥ 10× the
   expected time) that fails with diagnostics. A real timing assertion scales with the environment, as the EQ_Cpu
   fix did.
2. **Stress before landing:** `make stress-test TEST=<name> N=200` runs the test under `--filter` with every core
   loaded by a background CPU hog, then once under TSan. Results go in the PR.
3. **Flake ledger:** every CI flake gets a line (test, run, cause, fix commit). Fix at the root (already the habit).
   Re-run only for information.

---

## 5. Agent-operations playbook

**Brief template (mandatory fields):**
1. Objective + acceptance criteria + non-goals. The agent's report starts with "acceptance list → done / not done".
2. **Absolute worktree path as cwd.** First command: `git rev-parse --show-toplevel` must equal it. Never build with
   the main checkout as cwd.
3. `git submodule update --init third_party/libebur128`.
4. **One command for the fast check (`make check`)**, defined in the Makefile from the same scripts as the strict
   gate. Agents never hand-assemble their own subset (that is how Periphery and swiftformat got skipped).
5. File ownership + named cross-owner seams + who owns shared helpers.
6. "If a tool call is declined or a prompt fails: stop, report the exact command and why. Don't retry or work
   around it."
7. For timing / concurrency tests: the §4.4 stress rule.
8. Commit early (a WIP commit keeps the worktree from being auto-removed and makes resumes clean). Write
   `.lane/STATE.md` (last step done, next step, gate-log path) at each stage.

**Fix the tool holes at the root (fix the lint, don't fight it):**
- **Lint the tracked file list, not a directory walk with exclude globs.** Run `git ls-files '*.swift' | xargs
  swiftformat --lint` (same for swiftlint). That closes the swiftlint worktree crash **and** the swiftformat
  "skips everything in a worktree" hole at the source, and ends the "lint on main after every merge" workaround.
- **Fail the gate if the repo root holds untracked compiler outputs** (`*.d`, `*.dia`, `*.swiftdeps`,
  `*.swiftmodule`). The brief line didn't stop the second incident; a check will.
- **One heavy-job lock:** wrap `swift build`, the strict gate and `make sheets` in `flock` so at most N (say 2) run
  at once on the Mac. Six concurrent builds + renders + a gate slowed renders 1.5 → 40 min, stretched the local gate,
  and make timing tests flaky locally.

**Lifecycle:**
- **A lane table, written at dispatch, not at pause:** raw agent ID, branch, worktree, state, waiting-on. Put it in
  the "Now" status (§6.3).
- Keep worktrees until the sprint closes. Before removing one, check that no running app was launched from it
  (existing memory rule; add it to a `make clean-worktrees` script that checks for you).
- Resume by raw ID (existing). After a restart, re-read `.lane/STATE.md`, not memory.
- Verify agents' claims on the merged branch, live (D retro).

**Permission prompts:** prompts that silently fail stopped 7 agents across two episodes. The founder may want to
review and pre-approve a narrow allow-list for worktree-confined, non-destructive operations (build, test and lint
inside `.claude/worktrees/*`; read-only git), so routine steps don't depend on a prompt reaching them. **This is the
founder's call to make in their own settings.** I can't change permission settings, and an agent's suggestion isn't
consent. Until then, the coordinator should batch declined operations into one founder question rather than letting
lanes stall one by one.

---

## 6. Founder load

### 6.1 Echo back the objective before any large effort (new, from today)

Before any effort above roughly one agent-hour, more than two agents, anything touching the founder's data, or
anything outward-facing (release, tag, public push), the coordinator sends **at most 10 lines**:
- the objective in its own words;
- scope and non-goals;
- deliverables and where they land;
- cost (agents × hours) and expected wall-clock;
- how success will be checked;
- the decisions it expects to need.

**Then it waits for an explicit "yes".** The founder paused the council today to do exactly this by hand; the
rule makes the coordinator do it. Agents get the same at lower cost: their brief carries acceptance criteria, and
their report opens by checking against them.

### 6.2 Ask the founder vs decide alone

| Ask the founder (with a recommendation, simple words, recommended option first) | Decide alone, and log it as "coordinator default, revisable" |
|---|---|
| Product-visible behaviour and taste (e.g. the Master Gain law, Settings wording, Genres as a grid) | Engineering method: tests, gate stages, lanes, fix approach, naming |
| Scope changes: add, cut, pull forward, a recorded exception | Triage under the agreed rule (R1 blocker vs post-R1), routing pre-existing bugs |
| Anything touching the real library, real settings or real devices | Process changes inside an agreed policy (retro rules) |
| Releases, tags, public pushes, deleting anything shared | Order of work inside a sprint |
| Checks only the founder can do: by-ear, HIL, colours, the walk | Re-running, re-splitting or restarting agents |
| Hearing-safety trade-offs | Stopping a loop at the agreed cap (1 revision + 1 verify) |
| Large efforts (the §6.1 echo-back) | |

**Batch the asks:** one **decision digest** per sprint checkpoint (plan check, before the founder check, before the
PR). Interrupt mid-sprint only for blockers. Report each agent's **measurable result**, not its activity (pull-forward
retro).

### 6.3 Keep the status visible

The rules say `sprint-plan.md` §Status is the one prose status, and that stays. But it is a ~900-word history, not a
dashboard. Options:
- **A (recommended):** trim §Status to five lines (shipped / now / next / waiting on founder / main CI) and move the
  history into the ledgers. Add a **pinned GitHub issue "Now"** that the coordinator edits at each boundary: lane
  table, waiting-on-founder list, main CI state, the next founder action. It is live operations, not a doc, so it
  doesn't compete with the docs rule, and the founder can read it on a phone.
- **B:** a "Now" block at the top of the sweep ledger instead of an issue.
- **C:** keep things as they are.

---

## 7. Decision list for the founder

Each decision lists the recommended option first.

1. **Merge policy.** **Recommended:** a `main` ruleset that requires the CI checks, plus auto-merge, plus never
   cancelling main runs, plus a tag allowed only on a green main enforced in `release.yml`. Options: (b) require the
   checks without auto-merge (you wait for CI); (c) as today (main CI checks after the fact).
2. **CI shape.** **Recommended:** parallel jobs + checks tiered by changed path for PRs + everything, uncancelled, on
   main and nightly. Options: (b) parallel jobs only, every check on every PR; (c) keep one serial 87-min job.
3. **Heavy tests under sanitizers.** **Recommended:** time each test, then run accuracy sweeps and CPU budgets only
   in the debug and -O2 builds. Option: (b) keep everything under ASan and TSan.
4. **Timing tests and flakes.** **Recommended:** no short wall-clock deadlines; stress 200× under load + TSan before
   landing; a flake ledger; a red main stops the line. Option: (b) fix flakes as they appear (today).
5. **Break-it cadence.** **Recommended:** scoped per sprint + one rotating area per sprint + a whole-app pass per
   release + a ~30 % fix reserve; harnesses merged as tests. Options: (b) per release only (what produced 13 blockers
   on the last day); (c) a whole-app pass every sprint (costly).
6. **Test the real playback logic.** **Recommended:** adopt breaker B's VM harness into CI now as a stopgap, and ask
   the architecture review to design an importable target for the view-model logic. Options: (b) the stopgap only;
   (c) neither.
7. **Hang detection.** **Recommended:** a DEBUG main-thread watchdog with auto-`sample`, plus a 5–10 min HIL
   checklist for audio / device / transport changes. Option: (b) Instruments only, at release.
8. **How the founder is involved.** **Recommended:** the echo-back for large efforts, the ask-vs-decide table, one
   decision digest per checkpoint. Option: (b) as today.
9. **Status surface.** **Recommended:** a five-line §Status + a pinned "Now" issue. Options: (b) a "Now" block in
   the ledger; (c) as today.
10. **Agent permissions.** **Recommended:** you review and pre-approve a narrow allow-list for worktree-confined,
    non-destructive operations. Option: (b) keep prompting, with the coordinator batching declined operations.
11. **Lint and worktree hygiene.** **Recommended:** lint the tracked file list, a stray-build-output check, and a
    heavy-job lock. Option: (b) keep the brief-line workarounds.

---

## 8. Handed to other reviewers

- **Architecture:** the playback view model's real logic is untestable outside the app target, and its tests run
  against a mirror (`MockAdvanceController` "state-machine mirror"); breaker B's harness copies sources to reach it.
  The same applies to app-side scan scheduling (`LibraryModel`). Needs a structural remedy (an importable core
  target, an explicit transport state machine). The charter names this exact brittleness.
- **Test infrastructure / DSP:** the per-test cost of the EQ-era C++ tests under sanitizers;
  `RenderGate_ConcurrentNeverOverlaps`'s 1 s `close()` deadline (`Tests/RenderGateTests.inc:197`); the
  main-thread-stall self-test being looser than the breaker harness (already logged post-R1).
- **Docs:** the S10.8 row in `sprint-plan.md` still reads "~45" points; the sweep actually carried Sprint EQ (~20)
  plus the G fix wave.
