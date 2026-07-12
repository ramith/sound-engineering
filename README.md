# Adaptive Sound — macOS Audio Enhancement Engine

A personal, open-source audio enhancement app for macOS that turns any good-quality song into a personal, perceptually-tuned, spatially-rendered mix steerable via plain language.

[![Strict CI](https://github.com/ramith/sound-engineering/actions/workflows/strict-ci.yml/badge.svg)](https://github.com/ramith/sound-engineering/actions/workflows/strict-ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS_26_(Apple_Silicon)-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![C++](https://img.shields.io/badge/C%2B%2B-23-00599C?logo=cplusplus&logoColor=white)
![Tests](https://img.shields.io/badge/tests-120_null_%2B_71_Swift-brightgreen)
![Coverage](https://img.shields.io/badge/coverage-not_tracked-lightgrey)
![License](https://img.shields.io/badge/license-TBD-lightgrey)
![Last commit](https://img.shields.io/github/last-commit/ramith/sound-engineering)

**Status:** In active development — building a **bit-perfect macOS audiophile player** first, then the adaptive-sound differentiation (masking-aware clarity, steerable *Reimagine*, spatial rendering). Current focus: **S8 — the library spine**. See [`docs/product/roadmap.md`](docs/product/roadmap.md) for the phase/release plan and [`docs/sprints/sprint-plan.md`](docs/sprints/sprint-plan.md) for what's next.

---

## Requirements

- **macOS**: 26 (Tahoe) or later
- **Hardware**: Apple Silicon Mac (M1 Pro / 16 GB minimum, LD-18)
- **Xcode**: 26 or later
- **Swift**: 6.2 or later (Swift 6 language mode)
- **C++**: C++23 / GNU++2b (as required by SwiftPM + Apple Clang)

---

## Project Structure

```
sound-engineering/
├── Sources/
│   ├── AdaptiveSound/       # SwiftUI app (UI, Models, Monitoring, Spectrum, Loudness, AudioEngineBridge)
│   ├── AudioDSP/            # C++ real-time DSP (AudioEngine, EQ, Limiting, Loudness, Clarity, Spatial)
│   ├── AudioFormatKit/      # decode (runtime FFmpeg-or-Apple)
│   ├── LibraryScan/         # folder scan + FSEvents watch
│   ├── LibraryStore/        # persistent SQLite library store
│   ├── SRCQualityMeasure/   # sample-rate-conversion quality harness
│   ├── VerifyAUGraph/       # headless AU-graph gate
│   └── VerifyLibraryStore/  # headless library-store gate
├── Tests/                   # C++ null-test harness + Swift @Test suites
├── docs/                    # architecture · product · sprints · session-notes
├── scripts/                 # build-null-test.sh, strict-gate.sh, bundle-app.py, …
├── Package.swift            # Swift Package manifest
└── Makefile                 # build / run / gate targets
```

---

## Build & Run

### Option 1: Xcode IDE (Recommended for Development)

Open the project in Xcode with full debugger, canvas preview, and profiling tools:
```bash
make xcode
```

Then: **Product > Run** (`Cmd+R`)

### Option 2: Makefile (Command Line / CI)

Build and launch as native macOS app bundle:
```bash
make run
```

Other targets:
```bash
make build          # Build + bundle (no launch)
make clean          # Remove build artifacts
make test           # Run the Swift test suite
make gate           # DSP correctness gate (C++ null-test + VerifyAUGraph + VerifyLibraryStore)
make strict-gate    # Full pre-merge gate (build + swift test + gate + clang-tidy + sanitizers)
make format         # Format code (Swift + C++)
make profile        # Build + profile with Instruments
make help           # Show all targets
```

---

## Testing & CI

The **DSP correctness gate** is a C++ null-test harness — [`scripts/build-null-test.sh`](scripts/build-null-test.sh) — that compiles the real production kernel and asserts a stable golden master (`0xE7267654BA01D315`) plus bit-exact bypass at intensity 0. The Swift suites run headless via `swift test` (native swift-testing) and in Xcode. `VerifyAUGraph` and `VerifyLibraryStore` are `swift run` integration gates for the audio graph and the library store. **[Strict CI](.github/workflows/strict-ci.yml)** runs `make strict-gate` (with FFmpeg present) on every push to `main` and every PR.

---

## Build System Architecture

**Why Makefile + Python bundler (not bash, not Swift Bundler)?**

| Component | Why |
|-----------|-----|
| **Makefile** | Standard build tool, clean targets, CI-friendly |
| **`swift build`** | Native SPM, handles compilation + asset processing |
| **`scripts/bundle-app.py`** | Pure Python (portable), no external dependencies, explicit bundling |
| **`make xcode`** | Xcode IDE for professional GUI development |

**Resource Management** (SPM native):
- `Assets.xcassets` declared in `Package.swift`
- SPM automatically processes and bundles assets
- No manual file copying needed for assets

**App Bundling**:
- Swift executable → macOS `.app` bundle structure
- Python script handles: Info.plist, icon, executable placement

---

## Development Workflow

For detailed setup, coding standards, pre-commit hooks, and profiling guidance, see [`docs/development/DEVELOPMENT.md`](docs/development/DEVELOPMENT.md).

**Pre-commit hooks** run automatically on `git commit` to enforce:
- C++ formatting & static analysis (clang-format, clang-tidy)
- Swift formatting & linting (swiftformat, swiftlint)
- Audio-thread safety checks (ASan, TSan)

---

## Roadmap

**Strategy:** reach competitive parity as a *player* first, then build the Adaptive Sound differentiation on a credible base. Authoritative plan: [`docs/product/roadmap.md`](docs/product/roadmap.md) · [`docs/sprints/sprint-plan.md`](docs/sprints/sprint-plan.md).

**Shipped (on `main`):** loudness safety (Sprint 4) · 31-band EQ + N-channel multichannel + Monitoring (Sprint 5/5b) · bit-perfect **Pure Mode** + gapless playback · S6 architecture-review gate · S7 DSP regression gate · QW1 differentiators (crossfeed, Reimagine intensity knob, tonal presets).

**Phase 1 — player maturity / parity (S8–S14):** library spine (**S8, current focus**) → browse/search (S9) → queue/playlists/media keys (S10) → CUE + format hardening (S11) → parametric EQ + AutoEq (S12) → device-correction EQ (S13) → loudness compensation (S14). → release **R1** after S10, **R2** ("audiophile-credible") after S14.

**Phase 2 — the Adaptive Sound differentiation (S15–S18):** masking model → clarity / Arbiter → full Reimagine mapping → BRIR spatial render. → release **R3** after S17.

**Won't, this horizon (long-horizon vision):** stem separation / object engine (Phase 1.5) · system-wide capture via Core Audio process taps (Phase 2) · natural-language tuning.

---

## Architecture & Planning

See [`docs/`](docs/) for the complete architecture, requirements, and design record ([`docs/README.md`](docs/README.md) is the map):

- [`docs/architecture/architecture.md`](docs/architecture/architecture.md) — canonical system design (signal model, locked decisions, ADRs)
- [`docs/product/roadmap.md`](docs/product/roadmap.md) — phase / release timeline
- [`docs/sprints/sprint-plan.md`](docs/sprints/sprint-plan.md) — authoritative forward sprint schedule (S6–S18); [`docs/sprints/`](docs/sprints/) holds the per-sprint records
- [`docs/product/requirements.md`](docs/product/requirements.md) — functional & non-functional requirements
- [`docs/product/backlog.md`](docs/product/backlog.md) — epics, user stories, spikes
- [`docs/architecture/validation-strategy.md`](docs/architecture/validation-strategy.md) — QA framework (per-merge gates, listening-panel protocol)
- [`docs/development/DEVELOPMENT.md`](docs/development/DEVELOPMENT.md) — coding standards, tooling, pre-commit hooks

---

## Visual identity

The shipped UI uses a **teal `DesignSystem`** (neutral surfaces, system fonts) — see [`Sources/AdaptiveSound/DesignSystem.swift`](Sources/AdaptiveSound/DesignSystem.swift). The earlier *Flux* / Sunset-gradient / Space-Grotesk concept kit (in [`assets/`](assets/)) was **superseded**; its integration plan is archived at [`docs/session-notes/brand-integration-plan.md`](docs/session-notes/brand-integration-plan.md) for provenance.

---

## License

License deferred to post-MVP (personal / open-source). See docs for details.

---

**Built with:** Swift 6.2 · Xcode 26 · macOS 26 Tahoe · CoreAudio · Accelerate · C++23
