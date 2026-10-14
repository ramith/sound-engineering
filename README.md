# Adaptive Sound — macOS Audio Enhancement Engine

A personal, open-source music player for macOS — bit-perfect playback of your own library first, then adaptive sound: a perceptually-tuned, spatially-rendered mix you steer with one *Reimagine* control. *(The "steerable via plain language" goal was cut from scope on 2026-07-12.)*

[![Strict CI](https://github.com/ramith/sound-engineering/actions/workflows/strict-ci.yml/badge.svg)](https://github.com/ramith/sound-engineering/actions/workflows/strict-ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS_26_(Apple_Silicon)-blue)
![Swift](https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white)
![C++](https://img.shields.io/badge/C%2B%2B-23-00599C?logo=cplusplus&logoColor=white)
![Tests](https://img.shields.io/badge/tests-202_null_%2B_700%2B_Swift-brightgreen)
![Coverage](https://img.shields.io/badge/coverage-not_tracked-lightgrey)
![License](https://img.shields.io/badge/license-TBD-lightgrey)
![Last commit](https://img.shields.io/github/last-commit/ramith/sound-engineering)

**Status:** **R1 = v1.0.0-alpha — shipped 2026-10-14** ([download](https://github.com/ramith/sound-engineering/releases/tag/v1.0.0-alpha); [release notes](docs/releases/v1.0.0-alpha.md)). A **bit-perfect macOS audiophile player** first, then the adaptive-sound differentiation (masking-aware clarity, steerable *Reimagine*, spatial rendering). The one prose status line is [`docs/sprints/sprint-plan.md` §Status](docs/sprints/sprint-plan.md#status); the phase/release plan is [`docs/product/roadmap.md`](docs/product/roadmap.md).

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
│   ├── AdaptiveSound/       # SwiftUI app (UI, view models, AudioEngineBridge — the only code that touches AVFAudio/CoreAudio)
│   ├── AudioDSP/            # C++ real-time DSP + the two AUs, the Realizer, the Pure HAL engine, decode (Apple-first, FFmpeg dlopen fallback)
│   ├── AudioDSPTestBridge/  # C++ test seam for the Swift EQ tests
│   ├── AudioFormatKit/      # device-width multichannel format resolver (shared with VerifyAUGraph)
│   ├── DesignTokenKit/      # Liquid Glass design tokens + layout maths
│   ├── EQEditKit/           # EQ editing model, presets, per-output pins, Master Gain law
│   ├── LibraryBrowseKit/    # browse / list / selection decisions
│   ├── LibraryScan/         # folder scan + FSEvents watch + metadata/artwork
│   ├── LibraryStore/        # persistent library store (GRDB.swift over the system SQLite)
│   ├── OutputDeviceKit/     # the output-device rule (pin / follow / device loss)
│   ├── PlaybackQueueKit/    # queue, order, resume, transport snapshot
│   ├── StoreSQLiteShim/     # one C SQLite option Swift can't call
│   ├── TrackLoudnessKit/    # load-time track loudness analysis (loudness-neutral EQ)
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
make dist           # Release bundle: ad-hoc-signed .app, zip, disk image, SHA256SUMS.txt (dist/)
make profile        # Build + profile with Instruments
make run-test-library    # Debug copy on an isolated test library (~10k generated tracks), beside your own
make reset-test-library  # Start the test library over (never touches your own library or settings)
make help           # Show all targets
```

---

## Testing & CI

The **DSP correctness gate** is a C++ null-test harness — [`scripts/build-null-test.sh`](scripts/build-null-test.sh) — that compiles the real production kernel and asserts a stable golden master (`0xE7AF0C67F9340785`, re-baselined in Sprint EQ) plus bit-exact bypass at intensity 0 with the EQ flat or off. The Swift suites run headless via `swift test` (native swift-testing) and in Xcode. `VerifyAUGraph` and `VerifyLibraryStore` are `swift run` integration gates for the audio graph and the library store. **[Strict CI](.github/workflows/strict-ci.yml)** runs `make strict-gate` (with FFmpeg present) on GitHub-hosted `macos-26` on every push to `main` and every PR; **[release](.github/workflows/release.yml)** builds and publishes a `v*` tag with build-provenance attestations.

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
- *(ASan / UBSan / TSan, leak detection and the main-thread stall self-test run in `make strict-gate`, not the hook)*

---

## Roadmap

**Strategy:** reach competitive parity as a *player* first, then build the Adaptive Sound differentiation on a credible base. Authoritative plan: [`docs/product/roadmap.md`](docs/product/roadmap.md) · [`docs/sprints/sprint-plan.md`](docs/sprints/sprint-plan.md).

**Shipped (on `main`, released as R1 = v1.0.0-alpha):** loudness safety (Sprint 4) · N-channel multichannel + Monitoring (Sprint 5/5b) · bit-perfect **Pure Mode** + gapless playback · S6 architecture-review gate · S7 DSP regression gate · QW1 differentiators (crossfeed, Reimagine intensity knob, tonal presets) · the GRDB library spine + browse/search (S8–S9) · queue, playlists, Recently Played, media keys (S10.1–S10.6) · the Liquid Glass UI in dark and light (S10.7–S10.8) · an honest, loudness-neutral 31-band EQ (Sprint EQ) · the output-device and app↔engine threading rules (Sprint G) · the R1 blocker fixes from the 2026-10 council (PR #88).

**Phase 1 — player maturity / parity (S8–S14):** library spine (S8 ✅) → browse/search (S9 ✅) → queue/playlists/media keys + the release UX (S10.x ✅) → CUE + format hardening (S11) → parametric EQ + AutoEq (S12) → device-correction EQ (S13) → loudness compensation (S14). → release **R1** after S10 (v1.0.0-alpha, shipped 2026-10-14), **R2** ("audiophile-credible") after S14.

**Phase 2 — the Adaptive Sound differentiation (S15–S18):** masking model → clarity / Arbiter → full Reimagine mapping → BRIR spatial render. → release **R3** after S17.

**Won't, this horizon (long-horizon vision):** stem separation / object engine (Phase 1.5) · system-wide capture via Core Audio process taps (Phase 2) · generative re-imagination. **Cut (2026-07-12):** natural-language tuning and hearing personalization.

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

The shipped UI is **Liquid Glass** on a teal `DesignSystem` (token fills, dark and light) — see [`Sources/AdaptiveSound/DesignSystem.swift`](Sources/AdaptiveSound/DesignSystem.swift), `DesignSystemGlass.swift` and [`Sources/DesignTokenKit/`](Sources/DesignTokenKit/); designs in [`docs/design/`](docs/design/). The earlier *Flux* / Sunset-gradient / Space-Grotesk concept kit (in [`assets/`](assets/)) was **superseded**; its integration plan is archived at [`docs/session-notes/brand-integration-plan.md`](docs/session-notes/brand-integration-plan.md) for provenance.

---

## License

License deferred to post-MVP (personal / open-source). See docs for details.

---

**Built with:** Swift 6.2 · Xcode 26 · macOS 26 Tahoe · CoreAudio · Accelerate · C++23
