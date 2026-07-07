# EQ controls bar — single-row redesign (design)

Status: **UI designed** (ui-designer, 2026-07-07) + **founder refinement** (order override, below). Lightweight control-bar redesign only — no new state, no model deltas, no Swift written here. Grounded on the current `EQControlsSection`/`EQTabView` code + the `macos-design` HIG skill. Every value is a `DesignSystem` token or a proposed inline literal.

## 0. Founder refinement (2026-07-07) — ORDER OVERRIDE

**Interpolation is the leftmost control.** The leading cluster order is **Interpolation → Preset** (not Preset → Interpolation). "Save as Custom…" stays trailing. This supersedes the Preset-first order shown in the §2 sketch, §3 description, §5 view tree, and §9 focus order below — read those with Interpolation and Preset swapped.

Final order: `[ Interpolation  Smooth | Discrete ]   [ Preset  Flat ▾ ]  ·····  [ Save as Custom… ]`

## 1. Problem

Below the full-width frequency-response graph, the three controls stack as a 3-row `Grid` with a leading uppercase label column (PRESET / INTERPOLATION / CUSTOM). The controls hug the left; the wide space under the graph (content ≈ 848pt at the 880 window-min) is wasted, and the uppercase-tracked labels read as three section headers rather than one control strip. Founder: "given the amount of space available we can make Interpolation, Presets appear in a single row in a nice way."

## 2. Before → after

**Before** (3 label-prefixed rows):
```
┌─ EQ tab content ───────────────────────────────────────────────┐
│  ┌──────────────── Frequency-response graph ─────────────────┐  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  PRESET          [ Flat                    ▾ ]                   │
│  INTERPOLATION   [ Smooth Curve | Discrete Steps ]              │
│  CUSTOM          [ Save as Custom… ]  (disabled)                │
└──────────────────────────────────────────────────────────────────┘
        ↑ controls trapped left · large right gap wasted · labels shout
```

**After** (one bar — leading control cluster · flexible gap · trailing action):
```
┌─ EQ tab content ───────────────────────────────────────────────┐
│  ┌──────────────── Frequency-response graph ─────────────────┐  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                  │
│  Preset [ Flat ▾ ]    Interpolation [ Smooth Curve | Discrete ] ····· [ Save as Custom… ] │
└──────────────────────────────────────────────────────────────────┘
   └── leading cluster (browse/shape) ──┘        └ spacer ┘  └ trailing commit ┘
```

The bar's leading/trailing edges align with the graph's edges above it (same horizontal inset). The `Spacer` between the leading cluster and the Save action absorbs the surplus width, so the strip reads as a purposeful toolbar rather than a left-crammed row.

## 3. Layout & distribution

**Pattern: leading control cluster + trailing action** (the macOS toolbar idiom — browsing/shaping controls left, the create/commit action anchored trailing). Chosen over a fully-justified spread (three controls spaced edge-to-edge feels disconnected at ~848pt) and over centering (wastes the width the founder wants used).

- **Leading cluster** = Preset + Interpolation, grouped because they belong together (what curve, and how it's drawn). Separated from each other by `Spacing.large` (24) so they read as two distinct fields, not one run-on.
- **Trailing action** = "Save as Custom…", pushed to the trailing edge by a flexible `Spacer(minLength: Spacing.large)`. Save is the natural companion to the Preset picker: you edit bands → picker flips to "Custom" → Save lights up.

## 4. Labeling: use `LabeledContent` inline labels (recommended — see §8)

Drop the uppercase micro-tracked header labels. Use `LabeledContent("Preset") { picker }` and `LabeledContent("Interpolation") { segmented }` — the idiomatic macOS inline-field container. It gives correct baseline alignment, Dynamic Type, and — critically — **auto-associates the visible label as the control's VoiceOver label**, so there is no double-read. The Save button stays unlabeled (its title is the action). Label text styled `Font.caption` / `Color.labelSecondary`, sentence case, no tracking — quiet, not a header.

## 5. View tree (after)

```
EQControlsSection
└─ ViewThatFits(in: .horizontal)                       // §7 responsive
   ├─ singleRow  (preferred)
   │   HStack(alignment: .firstTextBaseline, spacing: 0)
   │   ├─ HStack(spacing: Spacing.large)               // leading cluster (Interpolation leftmost — §0)
   │   │  ├─ LabeledContent("Interpolation") { EQInterpolationPickerView(...) } // .segmented + .fixedSize
   │   │  └─ LabeledContent("Preset")   { EQPresetPickerView(...) }        // .menu, minWidth ~140
   │   ├─ Spacer(minLength: Spacing.large)
   │   └─ saveButton                                    // .disabled(selectedPreset != nil)
   │
   └─ twoRow  (fallback)
       VStack(alignment: .leading, spacing: Spacing.medium)
       ├─ HStack(spacing: Spacing.large) { LabeledContent("Interpolation"…); LabeledContent("Preset"…) }  // §0 order
       └─ HStack { Spacer(); saveButton }               // action stays trailing
   ── padding: .horizontal (graph inset) · .bottom 20 · .sheet(SaveCustomPresetView)
```

The three child views (`EQPresetPickerView`, `EQInterpolationPickerView`, `SaveCustomPresetView`, and the `showSaveSheet`/`selectedPreset` gating) are unchanged — this is a container reshuffle. Two child tweaks only: the interpolation picker already `.labelsHidden()` (keep — the `LabeledContent` supplies the label); and with `LabeledContent` in place, remove the now-redundant `.accessibilityLabel` on each picker (the label provides it) but **keep** `.accessibilityValue(selectedPresetName)` on the preset picker.

## 6. Tokens & spacing

| Slot | Value | Token |
|---|---|---|
| Label → control gap | (system, via `LabeledContent`) | — |
| Preset group → Interpolation group | 24 | `Spacing.large` |
| Leading cluster → Save (flexible) | ≥ 24 | `Spacer(minLength: Spacing.large)` |
| Two-row vertical gap | 16 | `Spacing.medium` |
| Bar horizontal inset | match graph (`.padding(.horizontal)`, currently 16) | see note |
| Bar bottom padding | 20 | `LayoutMetrics.sectionGap` (unchanged) |
| Label type / color | 12 regular / secondary | `Font.caption` · `Color.labelSecondary` |
| Preset menu min width | ~140 (`.frame(minWidth:)`, prevents jump as preset name length changes) | inline |
| Segmented control | intrinsic (`.fixedSize()` — hug 2 segments, don't stretch) | — |
| Control height | 28 (system default) | — |

Note on inset: the graph and the current controls both use the default `.padding(.horizontal)` (16), not the `LayoutMetrics.screenInsetH` (20) token. Keep the bar's inset **equal to the graph's** so their edges align. Optional cleanup (out of scope): promote both to `screenInsetH` for consistency.

## 7. Responsive / min-width

At the 880 window-min the content region (≈ 848pt) comfortably holds the single row: Preset (~200 incl. label) + `Spacing.large` + Interpolation (~260 incl. label) + Save (~140) ≈ 620pt, leaving the `Spacer` a healthy ≥ 200pt — no clipping. So the single row is the normal case.

`ViewThatFits(in: .horizontal)` guards the edge cases (a future narrower content region, or large Dynamic Type inflating the segment titles): when the single row can't fit its intrinsic width, it swaps to the **two-row fallback** — Preset + Interpolation on row 1, Save trailing on row 2 — *before* the segmented control's titles truncate. This is the SwiftUI-native reflow; nothing clips, the action stays trailing, and the segmented control regains full width on its own line.

## 8. States

- **Save enabled** ⇔ `selectedPreset == nil` (bands were edited → picker shows "Custom" → there's something to name+save). `.help("Save the current band state as a named custom preset.")`.
- **Save disabled** ⇔ `selectedPreset != nil` (a named preset is active). System dimmed styling; `.help("Edit the EQ bands first, then save.")`; skipped in the keyboard focus order (correct).
- **Preset vs custom** reflection: the picker's read-only "Custom" tag (existing behavior) is what pairs with Save lighting up — no extra visual state needed in the bar. Interpolation segmented control shows its two-way selection as today.

## 9. Accessibility

- **VoiceOver:** `LabeledContent` associates "Preset"/"Interpolation" as each control's label (no double-read); keep `.accessibilityValue(selectedPresetName)` on the preset picker. Add to Save: `.accessibilityLabel("Save as Custom Preset")` + `.accessibilityHint` mirroring the disabled `.help` ("Edit the EQ bands first, then save.").
- **Dynamic Type:** label uses `Font.caption` (scales); controls scale with the system; `ViewThatFits` reflows to two rows at large sizes so segment titles never truncate. No hard clamp.
- **Focus order:** left→right, top→bottom = Preset → Interpolation → Save, matching the visual order. Full Keyboard Access: menu opens on Space, segmented moves on arrows, button activates on Space/Return; disabled Save is skipped. System focus rings not suppressed.

## 10. Fork — labeling approach (recommended first)

- **A. `LabeledContent` inline labels (RECOMMENDED).** Identifies Preset & Interpolation (matches the founder's own mental model — they named the controls), auto-associates VoiceOver labels, quiet secondary styling, minimal chrome. Save stays unlabeled/trailing.
- **B. Fully unlabeled, self-describing.** Cleanest, most toolbar-like: the menu shows the preset name, the segments are self-describing, the button is an action. Slight ambiguity (a bare "Flat ▾" menu doesn't say *preset*); relies on VoiceOver `accessibilityLabel`s for non-sighted parity. Good fallback if A feels busy in `make run`.
- **C. Titled `GroupBox` ("Equalizer Controls").** More chrome — a bordered container directly under the already-bordered graph is redundant and heavier than the strip warrants. Not recommended.

Also recommended (distribution): **leading cluster + trailing action** over a fully-justified spread — related controls stay adjacent, the commit action lands where trailing actions are expected, and the flexible `Spacer` uses the width without looking scattered.

---

*Next: swiftui-pro implements the container reshuffle in `EQControlsSection.swift` (child views + `showSaveSheet` gating unchanged), behind build/lint/test/periphery; founder `make run` verifies the single-row look + the two-row reflow at window-min / large Dynamic Type.*
