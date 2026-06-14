# Adaptive Sound — macOS Audio Enhancement Engine

A personal, open-source audio enhancement app for macOS that turns any good-quality song into a personal, perceptually-tuned, spatially-rendered mix steerable via plain language.

**Status:** Sprint 1 — Audio engine + device management + branded UI ✅

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

---

## Requirements

- **macOS**: 14 (Sonoma) or later
- **Hardware**: Apple Silicon Mac (M1 Pro / 16 GB minimum, LD-18)
- **Xcode**: 15.0 or later (Swift 6.2+)

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

### Option 1: Xcode (Recommended)

Open the project using Swift Package:
```bash
open -a Xcode .
```

Build and run in Xcode: **Product > Run** (`Cmd+R`)

Expected output:
```
[AdaptiveSound] Audio engine initialized ✓
```

### Option 2: Swift Package (Command Line)

Build and run as proper macOS app bundle:
```bash
bash build-app.sh
```

This builds the app and launches it as a native macOS application (appears in Dock, Command+Tab switcher).

Manual build:
```bash
swift build -c debug
swift run AdaptiveSound
```

---

## Development Workflow

### Editing (VS Code)
```bash
code .
```

### Formatting

C++ code:
```bash
clang-format -i Sources/AudioDSP/*.{h,cpp}
```

Swift code:
```bash
swiftformat Sources/AdaptiveSound/
```

### Debugging in VS Code

1. Press `F5` or go to **Run > Start Debugging**
2. Set breakpoints (left margin) and inspect variables
3. Use the Debug Console for variable inspection

### Profiling & Performance Analysis (Xcode)

1. **Product > Profile** (`Cmd+I`)
2. Select **System Trace** for real-time audio metrics
3. Select **Time Profiler** for CPU usage per function
4. Monitor XRuns and render thread latency

---

## Roadmap

- **Phase 0** (Current): Player MVP — playback + audio thread safety ✅
- **Phase 1**: Mix-based core — EQ, clarity, loudness, BRIR spatialization
- **Phase 1.5**: Stem-based object engine — 6-stem separation, per-stem chains
- **Phase 2**: System-wide enhancement via Core Audio process taps

---

## Architecture & Planning

See `docs/` for complete architecture, requirements, and design decisions:
- `docs/architecture/architecture.md` — technical design
- `docs/product/requirements.md` — functional requirements
- `docs/sprints/00-sprint-model.md` — sprint model & methodology
- `docs/sprints/01-engine-plan.md` — Sprint 1 implementation plan

---

## License

License deferred to post-MVP. See docs for full details.

---

**Built with:** Swift 6.2 · Xcode 15 · CoreAudio · Accelerate · C++17
