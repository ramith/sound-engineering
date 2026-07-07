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

## 11. Robustness fix — narrow-width fallback (addendum, 2026-07-08)

Founder-reported bug: at a window width ≥ the app's enforced 880pt minimum, "Interpolation" wrapped into a vertical column of 2–4-character fragments ("Int/er/po/lat/io/n") while the segmented control and Preset menu rendered fine (both are `.fixedSize()`/`.frame(minWidth:)`-protected against compression) and "Save as Custom…" appeared to float away from the row — a `.firstTextBaseline`-alignment side effect of the now-6-line-tall label. Root cause: `controlLabel(_:)`'s `Text` has no protection against wrapping, so once available width drops below what `leadingCluster` needs, ALL the compression pressure lands on that one label. `twoRow` doesn't rescue this case because it shares the identical `leadingCluster` with `singleRow` — and `ViewThatFits` has no "give up gracefully" state; it renders its LAST candidate under the real available width even when that's narrower than the candidate's own ideal size (§11.3). This addendum closes the gap with (a) a hard non-wrap rule on the label and (b) a genuine third, structurally-safe fallback tier.

### 11.1 Hard rule: control-bar labels never wrap

`controlLabel(_:)`'s `Text` gets `.fixedSize(horizontal: true, vertical: false)` **and** `.lineLimit(1)` — belt and suspenders, applied once in the shared helper so it protects `singleRow`, `twoRow`, AND the new `threeRow` (§11.2) simultaneously. This makes the label report its own unwrapped ideal width to its parent regardless of how little space the parent proposes back; worst case under extreme compression the label clips/truncates at a fixed single-line height. Clipping is a vastly more acceptable failure than character-soup wrapping — it loses characters at one edge instead of destroying the label's legibility and blowing out the row's height (which is what cascaded into the Save button "floating").

This is a hard rule for every label in this control bar going forward, not a one-off patch: any future label added to `EQControlsSection` routes through `controlLabel(_:)` and inherits the protection automatically.

*Optional, lower-priority hardening (not required by this fix):* the "Save as Custom…" button title is the same class of risk — an unprotected `Text` inside a compressible `HStack` — though it wasn't implicated in the reported bug and `threeRow` (§11.2) removes the compression it would ever face. Flag for swiftui-pro to add `.lineLimit(1)` there too if convenient; no design decision needed.

### 11.2 A genuine third tier: `threeRow` (fully stacked, one control per row)

`ViewThatFits`'s candidate list grows from two to three:

```
ViewThatFits(in: .horizontal)
├─ singleRow   (preferred — §5, unchanged)
├─ twoRow      (first fallback — §5, unchanged)
└─ threeRow    (NEW — final fallback, this addendum)
```

**Per-row layout: label-leading, control-trailing on the SAME row** (not label stacked above control):

```
threeRow  (final fallback)
VStack(alignment: .leading, spacing: Spacing.medium)            // 16 — same rhythm as twoRow's vertical gap
├─ HStack { controlLabel("Interpolation"); Spacer(minLength: Spacing.small); EQInterpolationPickerView(...).fixedSize() }
├─ HStack { controlLabel("Preset");        Spacer(minLength: Spacing.small); EQPresetPickerView(...).frame(minWidth: 140) }
└─ HStack { Spacer(); saveButton }                                // unchanged from twoRow's save row
```

Why label-leading/control-trailing on one row, not a label-above-control stack:
- Smaller visual jump from `singleRow`/`twoRow`'s established grammar — "label sits immediately with its control" — than introducing a second, vertically-stacked idiom the bar has never shown before. One consistent motif (label+control always paired on a row) reads as one control bar that reflows; two competing motifs (paired-inline vs. stacked-tall) would read as an inconsistent redesign.
- It doubles as the native macOS "settings-row" idiom (label left, value/control right — e.g. System Settings rows), so the deepest fallback still looks like a deliberate compact layout, not a degraded/emergency state.
- Each row's `HStack` gets the FULL bar width to itself (no sibling cluster stealing space), which is exactly what makes this tier structurally safe rather than arithmetic-dependent (§11.3). As a bonus, the flexible `Spacer` before each control means the segmented control, the Preset menu, and (two rows down) the Save button all land on the same trailing edge — a clean aligned "value column," not an accident.

Save's row keeps `twoRow`'s existing treatment verbatim — `HStack { Spacer(); saveButton }`, trailing-aligned — rather than going full-width. Save is a single action with no label, so there's nothing to anchor leading; trailing preserves the "commit action lives at the trailing edge" convention from §3/§8 across all three tiers, and it's a direct reuse of existing code (no new save-row variant to design or maintain).

Vertical spacing between the three rows: `Spacing.medium` (16) — reuses the exact token already governing `twoRow`'s single vertical gap (§6), so the fallback ladder keeps one consistent vertical rhythm rather than inventing a new value for the deeper tier.

**Guaranteed to fit at the 880pt window minimum.** Each row now carries exactly ONE label + ONE control (never two controls sharing a row), so the widest row's ideal width is roughly: label (~70–90pt at `Font.caption` for "Interpolation," the longer of the two) + `Spacer(minLength: Spacing.small)` (8) + the wider of the segmented control or the Preset menu (segmented ≈ 180–220pt typical for two segments; Preset menu ≥ 140pt per its `minWidth`). That tops out well under 320pt, against a content width of ≈ 848pt at the 880pt window-min — better than 2.5x headroom. Critically, this tier doesn't depend on getting a combined-width estimate right (the failure mode behind the bug): it's correct by construction, because splitting the two controls onto separate rows means no row ever needs to fit two controls' worth of width at once. That makes `threeRow` a true backstop — the ladder now has a level that cannot break, regardless of window width, Dynamic Type scale, or any future control added to the leading cluster.

*Accessibility carry-over:* the label-associates-with-control contract from §9 (VoiceOver reads "Interpolation, Smooth Curve" not "Smooth Curve" alone) must hold in `threeRow` too — whether swiftui-pro implements each row via the existing `LabeledContent` pairing (restyled so its label/content spread to the row's leading/trailing edges) or a plain `HStack` with an explicit `.accessibilityLabel`/`.accessibilityElement(children: .combine)` is an implementation choice, not a design decision, and is left to swiftui-pro.

### 11.3 Why the original width math (§7) wasn't sufficient

§7's arithmetic sized the *common case* correctly — at 880pt, `singleRow`'s ideal width (≈620pt) comfortably fits inside the ≈848pt content region, leaving `ViewThatFits` free to pick it. The gap is at the *edge* of the ladder, not in that estimate: `ViewThatFits` tests each candidate's *ideal* size against the *real* available width, in order, and renders the FIRST one that fits — but if NONE of the candidates fit, it does not "give up" gracefully; it renders its LAST candidate anyway, using whatever real (possibly smaller-than-ideal) width it's actually given. With only two candidates, `twoRow` was that last-resort candidate — and `twoRow` still shares `leadingCluster`'s full two-control width requirement. Any real width narrower than `twoRow`'s own ideal width (extreme Dynamic Type, an unexpectedly narrow content region from a future layout change, etc.) forces `leadingCluster` to compress below what it needs — and because the label had no wrap protection (§11.1), that compression cascaded into the reported bug.

Adding `threeRow` as a genuine third candidate doesn't just add a bigger safety margin — it changes the failure mode at the bottom of the ladder from "requires correct width arithmetic to avoid breaking" to "structurally cannot need more than one control's width at a time." Combined with the non-wrap rule (§11.1) protecting every label at every tier, the ladder now degrades increasingly compact but never incorrectly, at any width ≥ the app's enforced 880pt minimum.

*For implementation: `EQControlsSection.body`'s `ViewThatFits` gains the third candidate (§11.2); `controlLabel(_:)` gains the two wrap-protection modifiers (§11.1). No other child view, state, or model changes. Founder `make run` re-verifies at window-min and at large Dynamic Type, specifically checking that the label never goes multi-line at any width down to 880pt.*

---

*Next: swiftui-pro implements the container reshuffle in `EQControlsSection.swift` (child views + `showSaveSheet` gating unchanged), behind build/lint/test/periphery; founder `make run` verifies the single-row look + the two-row reflow at window-min / large Dynamic Type.*
