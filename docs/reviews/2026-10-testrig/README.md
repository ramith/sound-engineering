# 2026-10 test-rig reviews: the panel, the lanes and the architecture review

These are the working papers behind the [test-rig redesign sprint](../../sprints/testrig-redesign.md): why the gate and the test rig were rebuilt, the decisions, and each lane's evidence. The sprint record holds the summary. These files hold the detail, with file:line references and reproduction steps.

Paths are relative to the repository root. `<worktree name>/` and `scratchpad/` refer to the coordinator's working copies, which are not in the repo.

| File | What it is |
|---|---|
| [SYNTHESIS.md](SYNTHESIS.md) | The three reviews combined: the diagnosis, the four rules, the resolved conflicts, the phased plan |
| [PLAN.md](PLAN.md) | The sprint plan from the founder's seven decisions: lanes, done-means |
| [qa-expert.md](qa-expert.md) | The 57-hazard inventory (S*, R*, N*, V*, P*), the taxonomy, what swift-testing, Point-Free, XCTest and GoogleTest support (sources opened) |
| [refactoring.md](refactoring.md) | The primitives (RigKit, the C++ `rig::`), the product seams, the migration plan, retiring the mirrors onto one FakeEngine |
| [architect.md](architect.md) | The gate as a registry, collect-all CI jobs, one toolchain manifest with parity, combination checks, determinism as architecture |
| [lane-a-report.md](lane-a-report.md) | Lane A: the step registry, the runner, CI, the toolchain manifest; the step map from the old gate |
| [lane-b-report.md](lane-b-report.md) | Lane B: GoogleTest, the watchdog, the tiers, hazards N2–N21 with their mutation checks |
| [lane-c-report.md](lane-c-report.md) | Lane C: RigKit, the view-model seams, the analyser decode off the cooperative pool, hazards S1–S14 / R1–R10 |
| [lane-c2-report.md](lane-c2-report.md) | Lane C2: the verifiers, and the main-thread-stall check judged by behaviour (V1–V9) |
| [lane-d-report.md](lane-d-report.md) | Lane D: one FakeEngine; the coverage map for every deleted mirror test; where the mirror had drifted from the app |
| [testrig-review.md](testrig-review.md) | The architecture review of the combined redesign: blocking, high, medium and low findings |
| [lane-a-review-fixes.md](lane-a-review-fixes.md) | How each review finding was fixed and proven |
| [ffmpeg-research.md](ffmpeg-research.md) | How to make FFmpeg work with any installed version: what Firefox, Audacity, Qt and others do; licensing; options (backlog US-R1F-17) |
