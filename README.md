# Adaptive Sound — macOS Audio Enhancement Engine

A personal, open-source audio enhancement app for macOS that turns any good-quality song into a personal, perceptually-tuned, spatially-rendered mix steerable via plain language.

**Status:** Phase 1b Part A ✅ (shipped) → Phase 1b Part B (in progress) → Phase 1c Sprints 4-6 (DSP-first MVP)

---

## Brand Identity

**The Mark:** *Flux* — eighth note flag transformed into an adaptive waveform  
**Concept:** Music (note) + Adaptation (flowing wave) = the core promise

**Colors** (Sunset Gradient):
- `#F80791` Pink — gradient start, note head
- `#FF6405` Orange — gradient midpoint  
- `#FDC025` Gold — gradient end, wave tip
- `#140C0A` Dark — surfaces & dark backgrounds
- `#211510` Ink — text, single-color mark
- `#FEFBF8` Paper — light surfaces

**Typography:** [Space Grotesk](https://fonts.google.com/specimen/Space+Grotesk) (Google Fonts, weights 400/500/600/700)

**Assets:** See `assets/` folder for complete brand kit:
- SVG vectors (mark, lockup, favicon, app-icon) — *source of truth*
- PNG rasterized (512×512, 1024×1024 for macOS; favicons for web)
- Full brand guidelines in `assets/README.md`

**Brand Implementation Guide:** See [`docs/product/branding/BRAND-INTEGRATION-PLAN.md`](docs/product/branding/BRAND-INTEGRATION-PLAN.md) for SwiftUI integration (color constants, typography, app icon bundling) — scheduled for Phase 2 UI polish

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
adaptive-sound/
├── Sources/
│   ├── AdaptiveSound/          # Swift UI app
│   │   └── AdaptiveSound.swift
│   └── AudioDSP/               # C++ audio kernel
│       ├── AudioEngine.h
│       └── AudioEngine.cpp
├── Tests/                      # Unit tests (Phase 1+)
├── docs/                       # Architecture & design docs
├── Package.swift               # Swift Package manifest
├── .clang-format              # C++ code style
├── .swiftformat               # Swift code style
└── .vscode/                   # VS Code debug config
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
make test           # Run test suite
make format         # Format code (Swift + C++)
make profile        # Build + profile with Instruments
make help           # Show all targets
```

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
- Works across macOS versions (Intel + Apple Silicon)

---

## Development Workflow

For detailed setup, coding standards, pre-commit hooks, and profiling guidance, see [`docs/development/DEVELOPMENT.md`](docs/development/DEVELOPMENT.md).

Quick start:
```bash
make xcode                # Open in Xcode (recommended for development)
make run                  # Build and run from CLI
make test                 # Run test suite
make format               # Format code (Swift + C++)
make profile              # Profile with Instruments
make help                 # Show all build targets
```

**Pre-commit hooks** run automatically on `git commit` to enforce:
- C++ formatting & static analysis (clang-format, clang-tidy)
- Swift formatting & linting (swiftformat, swiftlint)
- Audio thread safety checks (ASAN, TSan)

---

## Roadmap

- **Phase 1a** ✅ SHIPPED: Audio engine core + reference tone
- **Phase 1b Part A** ✅ SHIPPED: Music playback UI + real-time spectrum
- **Phase 1b Part B** 🟡 IN PROGRESS: Progress bar, seek, auto-play, test suite
- **Phase 1c** 🟡 BACKLOG (Sprints 4–6):
  - **Sprint 4:** Loudness safety (true-peak limiter + LUFS normalization)
  - **Sprint 5:** EQ foundation (31-band wiring + device profiles)
  - **Sprint 6:** Adaptive clarity (masking-aware + conversational tuning)
- **Phase 1.5** 🔄 PLANNING: Stem separation + per-stem processing chains
- **Phase 2** 🔄 PLANNING: System-wide audio via Core Audio process taps

---

## Architecture & Planning

See `docs/` for complete architecture, requirements, and design decisions:

**Core Documents:**
- [`docs/architecture/architecture.md`](docs/architecture/architecture.md) — Complete system design (locked decisions, ADRs, §16 Sprint 4-6 overview)
- [`docs/product/roadmap.md`](docs/product/roadmap.md) — Timeline, phases, milestones
- [`docs/product/requirements.md`](docs/product/requirements.md) — Functional & non-functional requirements
- [`docs/product/backlog.md`](docs/product/backlog.md) — Prioritized features (epics, user stories, spikes)

**Current Sprint Execution:**
- [`docs/sprints/07-phase-1b-part-b-kickoff.md`](docs/sprints/07-phase-1b-part-b-kickoff.md) — Phase 1b Part B critical path (progress, seek, auto-play, test suite)

**Detailed DSP Sprint Specs (Phase 1c):**
- [`docs/sprints/04-sprint-4-loudness-safety.md`](docs/sprints/04-sprint-4-loudness-safety.md) — Limiter + LUFS normalization
- [`docs/sprints/05-sprint-5-eq-foundation.md`](docs/sprints/05-sprint-5-eq-foundation.md) — EQ wiring + device profiles
- [`docs/sprints/06-sprint-6-adaptive-clarity.md`](docs/sprints/06-sprint-6-adaptive-clarity.md) — Conversational tuning + adaptive DSP

**Quality & Validation:**
- [`docs/architecture/validation-strategy.md`](docs/architecture/validation-strategy.md) — QA framework (per-merge gates, listening panel protocol)

**Development:**
- [`docs/development/DEVELOPMENT.md`](docs/development/DEVELOPMENT.md) — Coding standards, tooling setup, pre-commit hooks

---

## License

License deferred to post-MVP. See docs for full details.

---

**Built with:** Swift 6.2 · Xcode 26 · macOS 26 Tahoe · CoreAudio · Accelerate · C++23
