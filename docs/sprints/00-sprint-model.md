# Sprint Model & Development Process — AdaptiveSound

**Document ID:** SPRINT-ASE-001
**Version:** 2.0 — rewritten 2026-10-25 to the process the project actually runs (S10.8 → R1 → R1.1-A → the test-rig redesign → the 2026-10-23 roadmap reconciliation). *(1.0, 2026-06-13: a generic Kanban template — 5–10 SP one-week sprints, Slack stand-ups, coverage percentages, a dependency graph that named since-removed epics. It never matched practice; git history keeps it.)*
**Status:** Authoritative. Governs **how** every sprint runs. [sprint-plan.md](sprint-plan.md) says **what** runs next; [roadmap.md](../product/roadmap.md) holds the arc and [the sound plan](../product/roadmap.md#the-sound-plan-decided-2026-10-23); [DEVELOPMENT.md](../development/DEVELOPMENT.md) and [testing.md](../development/testing.md) hold the tools, the gate and the test rules.

---

## 1. Principles

- **The founder decides; the coordinator coordinates; specialists build.** Nothing ships the founder has not checked, and no founder decision is made for them.
- **Quality first.** Compute is abundant; spend it where it buys a better result, reject complexity that buys artifacts. For sound, options are ranked by **what the listener hears**, never by cost or delivery date ([the reconciliation](../product/roadmap-reconciliation-2026-10/README.md)). A fresh launch plays the file as recorded.
- **Correct order over an early demo.** Enablers before the features that need them; the architecturally correct topology even when an intermediate step cannot be heard.
- **Every change leaves the code more coherent.** Read the neighbouring code first; reuse an existing seam or refactor to a cleaner one; never bolt on.
- **The gate is the floor; trying to break it is the bar.** Green gates have repeatedly passed bugs an adversarial tester found in minutes.
- **Status lives in code and git.** Documents hold the plan and the reasons, never a second status narrative.

---

## 2. Roles

| Who | Does | Never |
|---|---|---|
| **The founder** | Sets direction; decides at the gates from a plain-language recommendation; does the by-ear, by-eye and by-hand checks on their own gear; merges every PR by hand. | — |
| **The coordinator** (the Claude Code session) | Writes the plan check; briefs the agents; combines their work; runs the gate on the combined branch; **verifies every agent claim against the code and the gate's real exit code**; writes the sprint record; keeps the documents and the project memory current, including a resume point whenever work pauses. | Labels anything a founder decision that the founder did not make; reports "green" from a log that merely looks fine. |
| **Specialist agents** | One job each, from a short brief, in their own worktree. Roster (2026-10-23): project — audio-DSP, SwiftUI, QA, architect reviewer, modern C++, refactoring, UI design, product manager; user — Swift, research, code review, competitive analysis, accessibility, test automation. | Play audio; push, merge or commit outside their lane; add any Claude attribution. |

---

## 3. The shape of a sprint

- **One sprint = one PR**, linear history (cherry-picks, no merge commits) so "rebase and merge" works. Lanes run on their own branches; the coordinator combines them before asking the founder to merge. *(The founder may choose two PRs for one sprint at its start — R1.1-B has that choice.)*
- **A 2-week cap** per sprint or structural slice, and **finish-or-revert**: a sprint never ends with two live owners of one job; an item that cannot finish is reverted, not left half-built.
- **No standalone refactor waves.** Restructuring ships only with the feature that needs it, or when its trigger fires. The Engine sprint is the one named exception.
- **Stay inside the sprint.** A feature belongs to the sprint the plan gives it; small fixes the founder points at while testing are fine, another sprint's features are not.
- **Sizing:** story points per the backlog's Fibonacci scale. The sprint record notes points planned, points done, actual duration and surprises — the only velocity data kept.

---

## 4. Choosing the routine (at the plan check)

| Work | Routine |
|---|---|
| The audio path, DSP, the library store and its migrations, concurrency and threading, algorithms, anything that changes what the listener hears | **The full loop** (§5) |
| Visual polish, sweeps across screens, copy, layout | **The lighter routine** (§6) |
| A release close-out | Either, **plus a whole-app break-it** |

The coordinator names the routine at the plan check and asks the founder before re-expanding a lighter sprint into the full loop.

---

## 5. The full loop

| # | Step | Owner | Output |
|---|---|---|---|
| 0 | **Plan check.** The routine; **one owner for every shared helper and every cross-lane seam**; for a UI-over-store or a cross-lane split, the API signature and a stub file agreed first; **the Kit that will own each new rule** (rules live in pure Kit targets, the app is a thin adapter); the lanes and their waves; for any product-visible rule change, its counter-examples listed before coding; the founder check written from the sprint's scope. For a large effort the objective is echoed to the founder in plain words and waits for "yes". | Coordinator → founder | The plan check, in the sprint record |
| 1 | **Design**, vetted. Algorithms get the **blind three-reviewer panel**: a breaker re-implements from the papers, a state-of-the-art challenger measures alternatives, the architect reviewer with the-fool checks contracts, threading and failure modes — none sees the others; every claim cites a source opened in that session (papers, other players' actual code). | Specialists | A design doc + the panel's reports |
| 2 | **Review gate** — the architect reviewer and the-fool on the design. | Specialists | Findings, ranked |
| 3 | **Founder decisions** — plain-language options with pros and cons, the recommendation first; many at once go as one consolidated list. | Coordinator → founder | Decisions recorded in the design and the sprint record |
| 4 | **Build in lanes** — each lane in its own worktree and branch; **at most two agents at once** (the founder's usage rule) unless the founder says otherwise; tests on the real code; commit early. A lane is "done" at **T2 `make check`**; lanes touching C++, the engine or the store also run their domain verifiers. | Specialists | Lane branches |
| 5 | **Combine, then gate once** — linear cherry-picks onto the integration branch; cross-lane conflicts re-resolved there; **T3 `make combine-check`** once on the combined branch. Never edit a worktree while a gate runs in it. | Coordinator | The integration branch, T3 green |
| 6 | **The slow real checks first** — performance, a live keyboard pass on the 10k test library (`make run-test-library`), anything that needs the running app. | Coordinator + specialists | Measured results ("End 15.1 s → 0.04 s"), not activity |
| 7 | **Review and break-it.** Code review plus the domain specialist; then **the QA agent and the-fool try to break it** — edge cases, races, boundary values, malformed input, interruption paths, invariant violations. Review, break-it and live findings are collected together. | Specialists | One findings list |
| 8 | **One fix round**, split by file. Every breaker's failing test is committed as a regression test, never left in a worktree. | Specialists | Fixes on the integration branch |
| 9 | **The full gate** — **T4 `make strict-gate`** locally, or CI on the pushed branch when the founder says so. Green only from the real exit code of a run that completed (§7). | Coordinator | T4 green |
| 10 | **The founder's check** — a short checklist written from the sprint's diff: by ear (on the founder's gear; the output device checked first, never playing into their ears unannounced), by eye, by hand. Sound sprints add the blind A/B where their row names it (§7). | Founder | Pass / fail per item |
| 11 | **Merge** — the founder merges by hand. **Main's CI run on the merge commit is the real gate**: a red main run is fixed forward at once, and nothing is tagged on a red main. | Founder; coordinator fixes forward | Main green |
| 12 | **Close-out** — the sprint record with a five-line retro; known issues updated; the [sprint-plan §Status](sprint-plan.md#status) line; documents reconciled (plan and reasons only); memory updated; lane worktrees removed only after the PR merged, the fix rounds are done, and no running app uses them. | Coordinator | The sprint closed |

**One fix round, not a loop.** Findings after the fix round that are not blockers go to known issues with a forward; the founder decides whether a blocker reopens the sprint.

---

## 6. The lighter routine

For polish and sweep work (glass sweep decision 18, 2026-10-07):

1. A short plan check — the routine, the pieces, the owners.
2. One agent per piece, in parallel worktrees (the two-at-once rule still holds).
3. The coordinator combines the pieces and runs **one** gate on the combined branch.
4. Code review only for logic, data or store changes. Picture sheets (offscreen renders, `make sheets`) only for screens that changed.
5. Break-it only for keyboard / focus, data-changing or store work.
6. A few-minute founder check, then a five-line mini-retro in the ledger.

---

## 7. The quality bar

**The gate.** One registry of checks drives every tier, so the founder's Mac and CI cannot disagree ([DEVELOPMENT.md — Quality Gates](../development/DEVELOPMENT.md#quality-gates)):

| Tier | Command | When |
|---|---|---|
| T0 | pre-commit hook | every commit — staged files: format, lint, clang-tidy |
| T1 | pre-push hook | every push — toolchain parity, format, lint, semgrep, suppressions, posture guards |
| T2 | `make check` | a lane says "done" |
| T3 | `make combine-check` | before pushing an integration branch |
| T4 | `make strict-gate` = `make ci` = CI | the sprint's full gate; CI runs it as five parallel jobs |

- **The pinned toolchain** (`scripts/toolchain/install.sh`, its bin directory first on `PATH`) and **every submodule initialised** (`git submodule update --init` — libebur128, googletest) in every checkout and worktree; T1 refuses a push otherwise. A hook is never bypassed.
- **Green means the real exit code** of a gate run that finished: read the `exit:` line (or `EXIT=`), never a piped tail or a background task's wrapper. The same holds for an agent's "green".
- **Tests** follow [testing.md](../development/testing.md)'s four rules — time only ever breaks a hang (wait for a state, cap loudly); measure the component, never the machine; each test owns its world; every run has a ceiling. Rules are tested in their Kit; app glue in `AdaptiveSoundTests` against the real view model; never a mirror. A new timing-sensitive test is stressed under load (`make stress`) before it merges.
- **A flaky test is fixed at its root immediately** — never quarantined, never retried.
- **A linter finding is fixed at its root**, never suppressed to get past it; suppressions carry the metadata DEVELOPMENT.md requires.
- **Sound.** Every processing stage ends its sprint with **the founder's blind, level-matched A/B** on their own gear — [the adaptive-tone ladder](../design/adaptive-tone/README.md#6-how-we-would-prove-it-the-evaluation-ladder), about 23 trials, capped at 60, matched within 0.2 dB over every level change the engine adds; "can't tell" for anything that plays by default, "prefer" for anything Enhance turns on; a stage that does not win ships off and hidden ([sound plan §9](../product/roadmap.md#the-sound-plan-decided-2026-10-23)). Offline measurements (null tests, sweeps, the loudness oracle, the limiter's gain-reduction meter) prove correctness; the ear decides preference. Agents never play audio.
- **Data.** The founder's own library is never used for break-it or performance work — the 10k test library is. Store migrations are additive only; the library database is never wiped.

---

## 8. Working with agents

**Every brief says:**
- the goal, what is already ruled out, and the files to read — the brief is the agent's only context;
- the agent's working directory (its own worktree) and **the files or folders it owns** — one owner per file when lanes run in parallel;
- read-only or write; never commit, push or merge unless the brief says so;
- initialise the submodules; put the pinned toolchain first on `PATH`;
- the tier to run at "done" (T2, plus domain verifiers for C++, engine or store work);
- **commit early** (usage limits kill agents; commits make the resume clean);
- tests on the real code; a breaker's red test is committed, not left behind;
- no Claude attribution anywhere (commits, PR text, documents, comments);
- never label anything a founder decision unless the founder made it;
- where its report goes (a file in the session scratchpad) and what its final message must contain.

**Running them:**
- A **fresh agent per job**, never one agent reused for several jobs (its context and cost grow without bound). Check an agent's `model:` frontmatter before choosing it; the audio-DSP agent stays on the session's model.
- **At most two at once** unless the founder says otherwise.
- **Monitoring:** rely on the completion notification. Never judge an agent stalled by its transcript's size or modification time — it writes only between tool rounds. A stall ladder: check the deliverable → nudge → resume by raw agent ID → the coordinator does the step.
- **Resuming across sessions** works by the agent's raw ID, not its name; active IDs are recorded only under the active initiative's resume heading in memory and deleted when the work closes.
- **Keep an agent's worktree until its sprint closes** — a fix round may need to resume it.
- **Verify, don't relay.** Check every agent claim on the combined branch, live; read the gate's exit code yourself.

---

## 9. Decisions and documents

- **Founder decisions** come as plain-language options with pros and cons and the recommendation first, in small batches. The answer is read literally, including free text. A gate is never passed while its question is unanswered.
- **Cross-cutting decisions** use the reconciliation's method ([2026-10-23 record](../product/roadmap-reconciliation-2026-10/README.md)): blind independent reviewers on the plan *and* the code → one merged, ranked synthesis → decision cards (options, pros and cons, what the listener would hear) → an impact map (what each answer changes in the plan) → a pre-mortem by the-fool → the founder decides card by card → the plan rewritten → a cross-check of every changed document against the decisions and each other.
- **Where things live:** the forward schedule and the one prose status line — [sprint-plan.md](sprint-plan.md); the arc and the sound model — [roadmap.md](../product/roadmap.md); stories and acceptance — [backlog.md](../product/backlog.md); open defects with forwards — [known-issues.md](../product/known-issues.md); sprint records, ledgers and break-it reports — `docs/sprints/`; reviews and panels — `docs/reviews/`; design packages — `docs/design/<topic>/`; release notes — `docs/releases/<tag>.md`.
- **A changed decision is annotated** ("amended YYYY-MM-DD: …") or marked **superseded**, never silently rewritten or deleted — it stops the same question being re-litigated.
- Documents describe behaviour; they do not cite drift-prone file paths or line numbers as status, and never carry commit hashes or counts as status.

---

## 10. Done-done

Copied into each sprint record at the plan check and ticked at close-out:

```
Sprint <id> — <title> · routine: full | lighter · SP <n> · cap 2 weeks
Plan check   ☐ routine named ☐ owners and seams named (stubs agreed) ☐ Kits named
             ☐ lanes and waves ☐ counter-examples for rule changes ☐ founder check written
Build        ☐ every acceptance line of the roadmap row met by its named measurement
             ☐ tests on the real code ☐ every breaker's red test committed
Gates        ☐ T3 combine-check exit 0 ☐ T4 strict-gate / CI exit 0, run complete
             ☐ break-it findings fixed, or logged in known issues with a forward
Founder      ☐ checklist passed (by ear / eye / hand) ☐ blind A/B where the row names it
Merge        ☐ one PR (or the two the founder chose), merged by the founder
             ☐ main CI green on the merge commit
Close        ☐ sprint record + five-line retro ☐ known issues ☐ sprint-plan §Status line
             ☐ documents reconciled (plan + reasons only) ☐ memory updated
             ☐ worktrees removed (no running app inside) ☐ points and duration recorded
```

---

## 11. Releases

- The founder decides when a release is due. A release is a **`v*` tag**: CI builds it from the tag, attaches build provenance, and requires the macOS 26 run to pass first; the release notes live in `docs/releases/<tag>.md`.
- **Every release close-out gets a whole-app break-it** (Sprint G's found thirteen R1 blockers in older code). The last sprint before a release — R1.1-B for R1.1 — carries it.
- Public-release chores (licence file, notarization, diagnostics) wait until the founder calls for a release beyond their own Mac (FD-7).

---

## 12. Cadence

There are no fixed weekday rituals. Work runs in sessions:
- **Sprint start** = the plan check with the founder (§5 step 0), including any choice the sprint row leaves open.
- **During the sprint**, the founder is asked only at decision gates and for checks; progress is reported as measured results.
- **Pause and resume:** before any pause the coordinator records the resume point in memory — the state, what is uncommitted, the next step, and the raw IDs of agents to resume.
- **Sprint end** = the founder's check, the merge, main green, the retro.

---

## 13. Sequencing

Enablers come before the features that depend on them, and every sprint is independently done-done; an epic may span sprints. The order and each sprint's dependencies live in [sprint-plan.md](sprint-plan.md) (its "Depends on" column) and the [roadmap](../product/roadmap.md)'s sprint tables — not here. *(The 2026-06-13 dependency graph that stood here named epics since removed — natural-language tuning — or parked — stems, system-wide; it is superseded by the sprint plan.)*

---

## Related documents

- [sprint-plan.md](sprint-plan.md) — what runs next, and the one status line.
- [roadmap.md](../product/roadmap.md) — the arc and [the sound plan](../product/roadmap.md#the-sound-plan-decided-2026-10-23).
- [DEVELOPMENT.md](../development/DEVELOPMENT.md) — tools, the gate tiers, real-time audio rules, suppressions.
- [testing.md](../development/testing.md) — the four test rules, the rigs, how to write a waiting test.
- [validation-strategy.md](../architecture/validation-strategy.md) — how each decision is verified.
- [The 2026-10-23 roadmap reconciliation](../product/roadmap-reconciliation-2026-10/README.md) — the decision method in practice.

---

**Last updated:** 2026-10-25
