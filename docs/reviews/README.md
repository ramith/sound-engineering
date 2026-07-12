# Codebase review initiative — records

A staged, whole-codebase review for **architectural elegance · reuse · best practices** (each stage: independent SME lenses → a `the-fool` adversarial pass that read the actual source → main-agent reconciliation → fixes landed on `main`).

These docs are kept for their **findings and the rejected/deferred/reverted rationale** — the "why we did / didn't do it" that the code does not carry. They are not a status board; whether a fix landed is in the source + git.

| Stage | Doc | Scope | Note |
|---|---|---|---|
| 1 | [stage-1-dsp.md](stage-1-dsp.md) | `Sources/AudioDSP` — DSP + algorithm correctness | Do-not-lose: the EQ-fitter AC-1 known-limitation, the **F1a revert** rationale, the F3 crossfeed depth-ladder override. |
| 2 | [stage-2-cpp.md](stage-2-cpp.md) | C++/Obj-C++ language-level quality (RAII, ownership, RT-safety, modern C++20/23) | |
| 3 | [stage-3-swift.md](stage-3-swift.md) | Swift app core + kits (non-GUI) | |
| 4 | [stage-4-gui.md](stage-4-gui.md) | SwiftUI view layer (+ accessibility) | Do-not-lose: the A-H1 EQ-curve-a11y open decision + the "genuinely good — do not fix" list. |
| 5 | *(no stage doc)* | `LibraryStore` | **Stage 5 became a full GRDB.swift adoption** — the DAO was rebuilt on GRDB rather than reviewed in place. See the current `Sources/LibraryStore/` + the SUPERSEDED note in [`../sprints/s8-1-persistent-store-design.md`](../sprints/s8-1-persistent-store-design.md). |
| 6 | *(no stage doc)* | SQL | **Subsumed** by the Stage-5 GRDB adoption (GRDB owns schema/migration/query). |

All stages merged to `main` — see the git log for the exact PRs.
