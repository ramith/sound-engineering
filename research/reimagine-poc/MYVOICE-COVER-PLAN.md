# My-Voice AI Cover — Technical Execution Plan

**Goal:** Produce recognizable **covers of old Sinhala songs** — keep the original **melody, tempo, and composition**, deliver them in **the founder's own voice** (a non-singer), with a **modern backing**. Legally clean (your own voice + a cover of much-covered old songs). Runs self-hosted / on rented cloud GPU.

**Core idea:** You never sing the song. We train a voice model on *your* voice, then **convert the original singer's performance into your timbre** (it carries the melody/timing/phrasing), and put a **modern backing** under it.

---

## Architecture

**One-time — build your voice model:**
```
your audio (~20 min speech + a few sung/hummed clips)
  → clean + slice → train RVC v2 voice model  →  ramith_voice.pth (+ index)
```

**Per song — produce a cover:**
```
original recording
 ├─ isolate vocal (Mel-Band RoFormer)  → restore (Smule)  → [transpose to your range]
 │      → SVC convert → YOUR voice (ramith_voice RVC)   ──┐
 └─ analyze: tempo + key + chords + structure             │
        → modern backing built on those chords @ tempo  ──┤
                                                          ▼
                                          align on shared grid → mix → master → COVER
```
Everything rides one tempo grid (the original's), so the backing fits by construction — no alignment guesswork.

---

## Tooling (concrete)

| Stage | Tool | Where | Status |
|---|---|---|---|
| Vocal isolation | Mel-Band RoFormer (`audio-separator`) | Mac | ✅ working |
| Vocal restore | Smule Renaissance | Mac | ✅ working |
| **Voice model train** | **RVC v2** (Retrieval-based-Voice-Conversion-WebUI) | Cloud CUDA | to set up |
| **Voice conversion** | RVC (primary); **R2-SVC** fallback for noisy/old input | Cloud CUDA | to set up |
| Song analysis | `librosa` (tempo/key) + chord recognition (Chordino/`autochord`/madmom) | Mac | partial |
| Modern backing | (a) DSP-modernize original · (b) ACE-Step LoKr fine-tune on 500 songs · (c) arranged samples | Mac / Cloud | optional |
| Mix / master | ffmpeg + our scripts (or Reaper for hand-polish) | Mac | ✅ scripts exist |

Compute: voice work + SVC need **CUDA** (rent a 24 GB box — 3090/4090/A100). The Mac handles isolation, restoration, analysis, and mixing.

---

## Phases

### Phase 0 — Setup (½ day)
- Stand up a rented **24 GB CUDA** box (RunPod/Vast/Lambda); persistent volume for voice data + checkpoints.
- Install **RVC v2** on the box; confirm GPU + training launches.
- Mac side already has separation/restore/mix.

### Phase 1 — Voice data collection *(your task — the gating input)*
- **~20+ min clean speech** (read varied text, natural & expressive).
- **2–3 sung/hummed clips** in *your* comfortable range (rough is fine — gives the model pitch/sustain examples; this is what makes a non-singer's model sing well).
- See the **Recording Guide** below for format + quality rules.
- Deliverable: `voice_data/speech/*.wav` + `voice_data/singing/*.wav`.

### Phase 2 — Train your voice model (~1–2 hrs, ~$2–5)
- Preprocess: slice to ~3–10 s segments, de-noise, extract F0/features.
- Train **RVC v2** on speech + singing combined.
- Output: `ramith_voice.pth` + feature index.
- Self-check: convert a held-out clip → sounds like you + natural?

### Phase 3 — 🎯 Voice make-or-break (the cheap proof, ~$5)
- Take **one** of your chosen songs → isolate → restore → (transpose to your range) → **SVC → your voice**.
- **You listen:** does *your voice* singing it sound natural and good?
- **GATE:** ✅ proceed · ⚠️ tune (more singing data, pitch/transpose, try R2-SVC) · ❌ rethink.
- *Nothing else gets built until this passes.*

### Phase 4 — Song analysis (per song, fast)
- Detect tempo, key, chord progression, structure; pick transposition to fit your range.
- Review chords by hand (auto-detection makes mistakes).

### Phase 5 — Modern backing (choose per song)
- **(a) Modernize the original band** — keep its exact chords/timing, clean it, add deep low-end + air + width + **modern drums** on its beat. *Reliable, no generation risk.*
- **(b) AI-generate** — fine-tune **ACE-Step (LoKr) on your 500 Sinhala songs**, generate backing conditioned on the chord chart + tempo (on CUDA + 4B planner — the config that was impossible on the Mac). *Where the 500 songs pay off.*
- **(c) Arrange** — chords → modern virtual instruments/samples in a DAW.
- Start with (a); bake off (b) once the voice path is proven.

### Phase 6 — Assemble (per song)
- Align your converted vocal + backing on the shared tempo grid (tweak global offset if needed).
- Mix: vocal forward, backing as bed, EBU-R128 loudness, gentle master. **Keep vocal processing minimal** (your stated preference).
- Output the cover.

### Phase 7 — Scale
- Do your chosen couple of songs; wrap the per-song flow into a repeatable script.

---

## Recording Guide (Phase 1 — do this first)

**Speech (~20 min):** read books/news/articles at a natural, *expressive* pace (not monotone — we want your pitch range). 
**Singing (2–3 clips):** sing or hum melodies you like, in a comfortable range. Quality of *singing* doesn't matter — pitch coverage does.

**Format & quality (important — garbage in, garbage out):**
- WAV or FLAC (avoid mp3), **mono**, 44.1 or 48 kHz.
- **Quiet room**, soft furnishings to kill echo (a closet/wardrobe works great). No TV/fan/AC.
- **Consistent mic distance**; a cheap USB mic > a phone, but a phone in a quiet room is a fine start.
- **No clipping** — keep peaks below ~−6 dB.
- **Dry** — no reverb/effects.
- Name files clearly; one take per file is fine.

---

## Costs (cloud rental — all well within $200–1000)
| Item | Est. |
|---|---|
| Voice model training (RVC) | ~$2–5 |
| Voice conversion runs | pennies each |
| ACE-Step LoKr backing fine-tune (optional) | ~$10–50 |
| Iteration / inference | low |
| **Whole project** | **comfortably < $100** |

---

## Risks & mitigations
| Risk | Mitigation |
|---|---|
| Speech-only model sounds stiff on high/long notes | You're also recording singing/humming → covers pitch range |
| Original singer's range far from yours | **Transpose** the song to your key (normal for covers; tempo/composition unchanged) |
| SVC artifacts on old/noisy vocal | Restore first (Smule); use robust **R2-SVC** if RVC struggles |
| Backing incoherence (our old nemesis) | **(a) modernize-original is the reliable fallback**; AI-generate is upside, on CUDA this time |
| Sinhala lyrics/phonemes | **Not a problem** — SVC is language-agnostic (converts timbre, not words) |
| Chord-detection errors | Manual review pass |

---

## Success milestones
1. **Voice model trained**, converts a test clip to your voice naturally. *(Phase 2)*
2. **🎯 One song, your voice, no backing — sounds good.** *(Phase 3 gate)*
3. One song, your voice + modern backing, mixed — *a finished cover you like.* *(Phase 6)*
4. Repeatable pipeline for your shortlist. *(Phase 7)*

## Your immediate next actions
1. **Record your voice** per the guide (~20 min speech + a few sung clips).
2. **Pick your 2–3 candidate songs** (criteria: you can get the original recording, it has a clear lead vocal for clean separation, and it's in/transposable to your range).
3. Hand me both → I stand up the cloud box, train your voice model, and run the Phase-3 proof.
</content>
