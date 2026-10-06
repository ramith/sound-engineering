# AdaptiveSound — Library screen (Twin Panels) handoff

**For: a Claude session (Opus) in VS Code, repo `ramith/sound-engineering`.**
This package redesigns the **Library** screen to match the Liquid Glass language already shipped on Now Playing. The visual truth is the **Twin Panels** design in this folder. Match it; don't invent a new layout.

## What is in this folder

```
README.md                     ← you are here
LIBRARY_GUIDE.md              ← the instructions. Follow top to bottom, one PR at a time.
LIBRARY_GUIDE_ADDENDUM.md     ← READ BEFORE PR-D. Resolves the customizable-columns conflict.
png/00-full-window.png        ← the whole target screen, 1440×920
png/01-rail.png               ← left glass sidebar
png/02-list-card.png          ← right glass list card (the big change)
png/03-list-header.png        ← list-card header row (title + filter + sort)
png/04-playing-row.png        ← the currently-playing row treatment
png/05-normal-row.png         ← a normal row
html/Library - Twin Panels.dc.html  ← live interactive mock. Open in a browser;
html/*.dc.html, support.js             keep ALL files in this folder together.
```

To view the mock: open `html/Library - Twin Panels.dc.html` in any browser. The other `.dc.html` files are its shared chrome pieces (title bar, toolbar, transport, nav item) — the same components used by Now Playing.

## The core idea (say it in one sentence)

The Library becomes **two floating glass cards side by side** — a narrow navigation rail on the left and the song list on the right — both sitting on the dark window over one soft teal glow. Same glass, same teal, same top/bottom bars as Now Playing.

## Opening prompt (paste this into the Claude session)

> Redesign the Library screen to match the target in `docs/design/library-twin-panels/`. Read `README.md`, `LIBRARY_GUIDE.md`, and `LIBRARY_GUIDE_ADDENDUM.md` first (the addendum governs PR-D — the song list keeps its customizable columns), and look at every PNG in `png/` before writing code. Work one PR at a time in order (PR-A through PR-F), one branch/commit per PR. Rules: reuse the existing glass/teal design tokens from the Now Playing work (do NOT add new colors); the two panels are floating cards (content sits ON the window, with a glow behind), not full-bleed regions; respect Reduce Motion (the playing-row equalizer freezes) and Reduce Transparency (swap the glass material for an opaque fill); keep all existing Library data bindings, sorting, filtering, column customization, and accessibility labels; `scripts/strict-gate.sh` must pass before each commit.

## Ground rules (repeated because they matter)

- **Reuse, don't reinvent.** The Now Playing PRs already added `DesignSystem+Realign.swift` (teal tokens, `StyledGlassBar`, the mini-equalizer). Import those. If they aren't in the repo yet, do the Now Playing PR-A first.
- **Colors** — teal family only: `#3FD0BA` bright, `#1FA893` mid, `#14897A` deep, teal text `#6FE0D0` / playing title `#7EE8D8`, dark-on-teal `#0C1413`. Non-lossless format tags (FLAC/WAV) use a muted gold `#CBB26A` — that is the ONLY non-teal accent, and it is optional.
- **Glass** — the rail and the list are BOTH real material cards (`.ultraThinMaterial` tinted dark ~70%, 1px top highlight, hairline ring, big soft shadow). The top and bottom bars stay "styled glass" (no blur) exactly as Now Playing.
- **One shared glow** sits behind BOTH cards (see `png/00-full-window.png`) — a single blurred teal radial, not one per card.
