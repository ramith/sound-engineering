# AdaptiveSound — Now Playing realignment package

**For: a Claude session (Opus) in VS Code, repo `ramith/sound-engineering`.**
This package supersedes the earlier DEVIATIONS.md plan. The visual truth is NOT the old 7a mock anymore — it is the **Realigned Target**, which keeps the layout the app already has and applies the designed styling on top of it. Do not restructure the layout.

## What is in this folder

```
README.md                     ← you are here
REALIGN_GUIDE.md              ← the instructions. Follow it top to bottom, one PR at a time.
png/00-full-window.png        ← the whole target screen, 1440×920
png/01-toolbar.png            ← PR-B + PR-G target
png/02-badges.png             ← PR-F target
png/03-queue-header.png       ← PR-C target
png/04-playing-row.png        ← PR-D target
png/05-inspector.png          ← PR-E target
png/06-transport.png          ← PR-G target
html/Now Playing - Realigned Target.dc.html  ← live interactive mock (open in a browser,
html/support.js                                  keep both files in the same folder)
```

## How to use this package

1. Copy this whole folder into the repo at `docs/design/now-playing-realigned/`.
2. Open `png/00-full-window.png` and keep it visible while you work. Every pixel decision is answered by a PNG before it is answered by prose.
3. Follow `REALIGN_GUIDE.md`. It is ordered PR-A → PR-G. **One PR = one commit/branch.** Do not combine PRs.
4. After every PR: build, run both light and dark appearance, run `scripts/strict-gate.sh`.

## Opening prompt (paste this into the Claude session)

> Restyle the Now Playing screen to match the target design in `docs/design/now-playing-realigned/`. Read `README.md` and `REALIGN_GUIDE.md` first, and look at every PNG in `png/` before writing code. Work one PR at a time in the order the guide gives (PR-A through PR-G), one branch/commit per PR. Rules: do NOT change the layout structure (toolbar / hero+analyzer / queue+inspector / transport bar stays exactly where it is); every new color goes through `DesignSystem` tokens with a light-mode variant; respect Reduce Motion (no pulsing dot, no equalizer animation, no spectrum animation) and Reduce Transparency (opaque fallback fills); keep all existing accessibility labels and bindings; `scripts/strict-gate.sh` must pass before each commit.

## Ground rules (repeated because they matter)

- **Styling only.** The current build's layout skeleton is correct. If a change requires moving a view to a different parent, stop and re-read the guide — only PR-E (inspector hugging its content) changes any frame behavior.
- **Colors**: teal family only — `#3FD0BA` (bright), `#1FA893` (mid), `#14897A` (deep), text-on-teal `#0C1413`, teal text `#6FE0D0` / `#7EE8D8`. Amber warning `#F0B429`. Never introduce a new hue.
- **"Glass" here is styled, not blurred** for the top and bottom bars (nothing scrolls behind them). Only the floating inspector card uses a real material/blur.
