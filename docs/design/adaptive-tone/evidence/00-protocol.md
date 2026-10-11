# Research protocol: an AI that reads ahead, suggests EQ and tone, and learns from "sounds better / not"

*2026-10-10. This is the protocol every research track follows. Briefs that don't follow it get sent back.*

## 1. The problem statement, restated

> The founder's words: "plug in a neural network to dynamically read ahead the song we are playing, then suggest the best EQ levels (+ tone) during mid-song play, and that controls the entire playback; we can instruct the network to stick to a particular theme, and give the user a simple control to steer it: 'it sounds better, or not'."

**Restated as an engineering problem.** For a track that AdaptiveSound decodes locally (so the whole file is available before and during playback), automatically choose and apply an EQ/tone setting the listener prefers. The setting may vary within the song. It must stay inside a theme the listener picks, and it is refined over time by one-bit "better / not" feedback. It must not cost faithfulness, hearing safety, the real-time guarantees, or the bit-perfect Pure Mode path.

**What we already have** (not research objectives, these are constraints):
- an honest 31-band cascade graphic EQ;
- loudness-neutral output gain (decision 26);
- presets as 5-D Tone vectors [Bass, Body, Mids, Presence, Air];
- per-output memory;
- a BS.1770 normaliser and a −1 dBTP limiter;
- the designed-but-unbuilt typed-contributor Arbiter, with its hearing-safety clamps and the KPI "adaptation is never perceived as the EQ moving".

**Out of scope** (related work only):
- natural-language tuning;
- hearing-test or audiogram personalisation (cut 2026-07-12).

## 2. The sub-problems, as research objectives

| ID | Sub-problem | Research question(s) | Track |
|---|---|---|---|
| **RO1** | **Sensing (read-ahead)** | Which properties of a track can be extracted reliably ahead of playback, and which of them predict a preferred tonal correction? Covers spectral balance vs references, structure/sections, genre/mood/era, production quality. | A (+D for tools) |
| **RO2** | **The objective: what "best" means** | How can "better" be defined and measured? Candidates: deviation from a target curve, a learned aesthetics/quality predictor (e.g. Audiobox Aesthetics), a listener-preference model. Does any automatic predictor track listener preference for EQ changes **on the same track**? | A (+B, +D probe) |
| **RO3** | **The policy: content → EQ/tone** | Which methods map content to EQ/tone parameters, what do they output, and what listening-test evidence shows them beating the original or a static preset? | A |
| **RO4** | **Changing EQ within a song** | Should the EQ change within a song? If so, when (section boundaries?), how fast, and how much, before it is perceived as "the EQ moving" or overrides the artist's intent? | B |
| **RO5** | **Theme steering** | How is a theme represented and enforced (target curves, listener preference classes, reference tracks, embeddings)? How many themes cover most listeners? | A + B |
| **RO6** | **Learning from feedback** | Which learning method turns sparse "better / not" feedback into a reliable personal model (dimensionality, trials to convergence, active query selection)? Which biases must the A/B control (loudness, order, adaptation)? | B |
| **RO7** | **Authority and safety** | What should the model be allowed to control ("the entire playback": EQ, loudness, dynamics, width/crossfeed, Reimagine intensity), within which bounds? How does it compose with the existing contributors and clamps? What do shipped products let their "AI" control? | C + D + synthesis |
| **RO8** | **On-device feasibility** | Can it run on M1–M5 within budget? Which models and tools, under which licences (code AND weights)? What hooks exist in this repo? Can the existing Compare / level-match machinery support a fair A/B? | D |
| **RO9** | **Training data and the learning signal** | What data exists or can be generated to train and validate: preference datasets, unmastered/mastered pairs, self-supervised "undo a random EQ" schemes? Under which licences? Can a useful model be built without large labelled data? | **E (new)** |
| **RO10** | **Market and positioning** | Who does content-adaptive, preference-learned or theme-steered EQ, how do they do it, what do users reject, and where is the gap for a music player? | C |
| **RO11** | **IP / freedom to operate** | Which patents cover content-adaptive EQ, preference-learning EQ / A/B personalisation, target or theme EQ, and section-aware processing? Which designs avoid them? | **F (new)** |
| **RO12** | **Evaluation** | How do we prove it's better? Listening-test designs for one listener (the founder) and for small panels; in-product metrics (keep/revert/override rate, feedback rate); offline regression gates that fit the repo's existing null-test/gate culture. | **G (new)** |

## 3. Search method (every track)

1. **Seed queries.** Write 5–10 queries per RO you own, mixing terms and synonyms. Log each one: query, source, date, number of hits screened, number included.
2. **Sources, primary first.**
   - Papers: arXiv (eess.AS, cs.SD), Google Scholar, AES E-Library, DAFx, ISMIR, ICASSP/WASPAA, JASA/JAES, IEEE/ACM TASLP.
   - Patents: Google Patents / Espacenet.
   - Code and models: GitHub, Hugging Face model cards.
   - Products: vendor manuals and white papers; reputable reviews (Sound On Sound, RTINGS and similar).
3. **Screen.** Screen titles and abstracts first, then OPEN the full text of everything included.
4. **Snowball.** Pick the 3 key sources per RO. Follow their references backward and their citations forward ("cited by"), one hop.
5. **Stop at saturation.** Stop an RO when two consecutive query rounds add no new included source, or at a sensible cap. Say which happened.
6. **Inclusion and exclusion.**
   - Include primary sources that address the RO directly, from 2005–2026 (older seminal work is allowed).
   - For efficacy claims, prefer evidence from listening tests or measurements.
   - Exclude secondary blogs when a primary source exists, and marketing with no mechanism. The market track (RO10) may list marketing, graded D.

## 4. Evidence grades

- **A:** peer-reviewed, with listener-test or measurement evidence.
- **B:** peer-reviewed or preprint without listener evidence, or an official technical document or patent.
- **C:** a vendor manual or documentation.
- **D:** marketing, reviews or forums.
- **U:** unverified (not opened this session). Never state a U claim as fact.

## 5. Extraction template (one row per source)

`ID | RO(s) | type | claim | numbers (n, effect size, test type) | method / output | code + weights licence | limitation | grade | URL`

## 6. Every brief must contain

1. a TL;DR;
2. findings **grouped by RO ID**;
3. an **evidence table** in the template above;
4. a **search log** (query | source | hits screened | included) and the saturation note;
5. **answers per RO**: answer, confidence (high/med/low), key source IDs;
6. **gaps**: what the evidence does not answer.

## 7. Synthesis (main thread, after all tracks)

1. Build an evidence matrix: RO × (answer, confidence, sources, gaps).
2. Write the proposal from the matrix. Every recommendation cites RO and source IDs.
3. One independent adversarial review (the-fool / architect lens). Then one revision, then the founder's decisions (no endless loop).
