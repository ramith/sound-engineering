# User Journeys — Adaptive Sound

**Document ID:** JOURNEYS-ASE-001  
**Version:** 1.2 — 2026-10-23 reconciliation (journeys 2.3 and 2.4 rewritten; 2.11–2.13 added); 1.1.1 — reconciled to the code (2026-10-13), re-checked after R1's blocker fixes (PR #88, 2026-10-14; R1 = v1.0.0-alpha); v1.0 extracted from requirements.md v0.6  
**Date:** 2026-06-13 (statuses re-verified 2026-10-13; journeys 2.4 and 2.10 re-checked 2026-10-14)  
**Extracted by:** Business Analyst (refactoring for clarity)  
**Status:** Authoritative; cross-referenced from requirements.md

---

## Overview

This document defines the core user journeys (workflows) for Adaptive Sound. Each journey describes a specific actor, goal, and step-by-step interaction flow. Success conditions are measurable.

**Journeys are organized by persona and phase:**
- **Journeys 2.1–2.5:** Phase 0 & Phase 1 (own-player focus)
- **Journey 2.6:** Phase 2 (system-wide, two implementation paths)
- **Journeys 2.8–2.10** *(added 2026-10-13)*: the journeys R1 is actually built around — the library, playlists and bit-perfect Pure Mode — written down so they trace to the code like the rest.
- **Journeys 2.11–2.13** *(added 2026-10-23, the sound-roadmap reconciliation)*: pressing Enhance, a surround album on stereo headphones, and leveling in both modes. All planned, none built. *(2.13 amended 2026-10-25: leveling in Enhanced in R1.1-B; in Pure deferred until the USB DAC.)*

> **Implementation status (current build).** These journeys are product *specifications*, not descriptions of shipped behavior. ~~Verified against `Sources/` on `main`, the current app is a Phase-0 own-player: it launches straight into a four-tab window (Now Playing · EQ · Monitoring · Settings) with local-file playback, a 31-band EQ, LUFS loudness normalization + a true-peak limiter, opt-in crossfeed, a Reimagine "Intensity" (wet/dry) knob, a bit-perfect Pure Mode, gapless + multichannel playback, and automatic output-device switching.~~ **Re-verified 2026-10-13 (R1 / v1.0.0-alpha; re-checked after R1's blocker fixes, 2026-10-14):** the app launches straight into a **five-tab** Liquid Glass window (Now Playing · Library · EQ · Monitoring · Settings), dark and light, plus a menu-bar extra. It has a persistent library (music folders, live updates, Songs / Albums / Artists / Genres with filter and sort), playlists, a persistent queue with shuffle / repeat and Recently Played, media keys and Control Center, a 31-band graphic EQ with Tone controls, presets and per-output memory, LUFS loudness normalization + a true-peak limiter, opt-in crossfeed, a Reimagine "Intensity" knob (which no longer touches the EQ), a bit-perfect Pure Mode, gapless + multichannel (≤ 7.1) playback, and an output-device rule (pick or follow; pause on loss; return to the picked device when it reconnects). Each journey below carries a **Status** line marking how much is built. Onboarding, the automatic adaptivity engine, environment/mic sensing, and Phase-2 system-wide capture are **not yet built** — they remain valid *planned* journeys, not current behavior. Open defects are in [known-issues.md](known-issues.md).

---

## Journey format (template)

Every journey below follows one template — reuse it for new use-cases:

- **Actor:** who is acting.
- **Goal:** the measurable outcome they want.
- **Phase:** the PRD product-capability phase (0 / 1 / 1.5 / 2 — *not* the execution roadmap; see the Phase Rosetta in [PRD.md](PRD.md)).
- **Status:** `BUILT` | `PARTIALLY BUILT` | `NOT YET BUILT (planned)`, plus one clause on what is / isn't realized. Keep it **coarse — do not cite specific source files** (they drift; the code is the source of truth for build state).
- **Steps:** a fenced `Step 1…N` interaction flow.
- **Success Condition:** the measurable pass criterion.

> These journeys are *specifications*, not claims of shipped behavior. For what is actually built vs. planned, see [../sprints/sprint-plan.md](../sprints/sprint-plan.md) §Status + the source.

---

## Journey 2.1 — First-Run Onboarding

**Actor:** New user, app just launched for the first time.  
**Goal:** Reach a working listening state with a meaningful default sound profile in under 3 minutes.  
**Phase:** Phase 0 (Player MVP).  
**Status:** NOT YET BUILT (planned; unscheduled — backlog US-UI-03). The app launches directly into the five-tab player; there is no welcome screen, mic-permission step, or first-run tooltip. The nearest thing is the empty Library, which asks the user to add a music folder (Journey 2.8, Step 1).

**Steps:**

```
Step 1 — Welcome Screen
  App launches → shows welcome screen with a single CTA: "Get Started"
  No login, no account wall.

Step 2 — Output Device Detection
  App enumerates available output devices via Core Audio property API.
  Auto-selects the active default output device (headphones if connected, otherwise built-in speakers).
  Displays detected device name and type (e.g., "AirPods Pro detected — Headphone mode active").
  [If no device detected → show inline error with troubleshooting link]

Step 3 — Microphone Permission (Environment Sensing)
  System dialog requests microphone access.
  App explains in plain language: "Used only to sense room noise — never recorded or transmitted."
  If denied → environment sensing disabled; adaptive ambient-noise feature inactive; user notified with non-blocking banner.

Step 4 — Profile Load and Playback Ready
  App loads default DSP profile for detected device.
  Opens media browser / file importer.
  User selects a track and presses Play.
  Adaptivity engine begins processing; visual VU/analysis meter shows activity.

Step 5 — First Listening Moment
  After 10 seconds of playback, a subtle non-blocking tooltip appears:
  "Sound is adapting to your headphones and room — no action needed."
```

**Success Condition:** User is listening to music with the adaptivity engine active within 3 minutes of first launch, with no technical errors.

---

## Journey 2.2 — Hearing Profile Calibration — *withdrawn 2026-07-12*
> Hearing personalization removed from scope (founder decision); prior journey in git, may be re-added.

---

## Journey 2.3 — Normal Listening Session (Phase 1 — Own Player)

**Actor:** Returning user with a configured profile.  
**Goal:** Listen to a music playlist with seamless adaptive enhancement.  
**Phase:** Phase 1 (mix-level adaptation).  
**Status (2026-10-23):** PARTIALLY BUILT. *Reconciled 2026-10-23 (the sound-roadmap decisions): Step 4 is rewritten — the loudness button is **not built** (S14-lite) and is a bass-only, ease-the-mids curve that follows the volume where the Mac can read it; the old "boosts bass and treble" wording is withdrawn. Leveling (the `Even out track levels` row) is R1.1-B — see Journey 2.13.* Playback, manual 31-band EQ (+ per-device preset recall), LUFS loudness normalization + true-peak limiter, crossfeed, and the Reimagine "Intensity" wet/dry knob are live *(Intensity is hidden at 0 since R1.1-A; the normaliser behind it is removed in R1.1-B)*. The **automatic adaptivity** in Steps 3 and 5 is NOT built: there is no content/genre classifier and no volume compensation (only a manual EQ + program-loudness normalization; no per-track curve cross-fades). *(Re-verified 2026-10-13: Step 1 restores the queue, track, position, shuffle and repeat **paused** and the EQ for the current output, but not Master Gain, Pure Mode, Intensity or crossfeed — known issue KI-SET-01; Step 2's chain is EQ → crossfeed → loudness → limiter, with no spatialization stage yet; Step 6 persists the queue continuously. Steps 3–4 → S14–S16; the track-boundary smoothing of Step 5 holds for the loudness gain, which follows each track's own analysis.)*

**Steps:**

```
Step 1 — App Launch / Resume
  App opens to last state (queue, volume, playback position if paused).
  Detects the active output device and recalls what the listener last chose for that output
  (EQ, correction choice, loudness reference, Headphones position). It applies nothing it has
  not been told to remember: a never-seen output plays the file as recorded.

Step 2 — Track Playback
  User presses Play.
  Enhanced: audio runs the chain, in order — per-track gain (leveling, peak-safe turn-down)
  → EQ program (correction | taste | compensation) → the fold (surround only) → the headphones
  stage (crossfeed today; the Spatial render, S18) → the one safety net, last → volume.
  Pure: the file goes straight to the device, untouched.
  Adaptivity (Clarity, S16) analyses ahead and adapts over the first 2–5 seconds per track.

Step 3 — Genre / Spectral Analysis
  Content analyser runs on audio buffer (on a non-real-time thread).
  Derived spectral profile / genre classification communicated to DSP via lock-free parameter update.
  DSP gradually cross-fades to genre-appropriate tonal curve (no abrupt change).

Step 4 — Volume Adjustment and the loudness button ("Keep bass at low volume", S14-lite)
  4a. One-time setup, per output: at the volume the listener normally listens at, they press
      "This is my normal loud setting". Until then the button does nothing on that output
      (the row says "Set your normal volume to start").
  4b. Which volume counts depends on the output:
      — An output whose volume reads (decided at run time, never by the kind of device: your XM4
        today; the soundbar does not): the level is Master Gain + the device's own volume
        + the track's leveling gain + the peak-safe turn-down + the button's own cut — read as
        "volume minus its own cut", solved off the audio thread, so there is no loop. Turning the
        headphones or the Mac's volume down, by either, is noticed within 100 ms.
        (Owed: whether the XM4's own buttons move the Mac's slider. If not, the caption says
        "use the Mac's volume keys".)
      — An output whose volume does not read ("Set on device", the HDMI soundbar): a manual
        slider labelled "Loudness amount", in dB of assumed turn-down (0–20 dB). It does not
        follow any volume, and says so.
  4c. Turning the volume down below the reference adds the ISO 226 difference curve, bass only:
      at a 20 dB turn-down and 50 % depth, +5.25 dB at 20 Hz, +4.1 at 50 Hz, +3.1 at 100 Hz,
      +1.95 at 200 Hz, +0.6 at 500 Hz, nothing above 1 kHz (no treble lift). It is applied by
      easing the mids, never by boosting — so the music is a little quieter, the safety net
      never works, and the caption says "nudge the volume up a notch". Turning the volume up
      to or past the reference adds nothing. The filters glide; there is no click.
  4d. In Pure the button shows "Not in bit-perfect mode" and does nothing.

Step 5 — Track Skip / Change
  New track begins; content analyser re-evaluates within 2–5 seconds.
  DSP parameters smoothed across track boundary; no audible click or abrupt shift.

Step 6 — Session End
  User pauses/closes app.
  Session state (queue, position, active profile) persisted.
```

**Success Condition:** User experiences no audible glitches across a 1-hour session; adaptive parameters visibly change between tracks of different genres in the analysis display. For Step 4: on the XM4 at a 20 dB turn-down, in the founder's blind, level-matched A/B (about 23 trials, capped at 60; "with" against "without, nudged to equal loudness"), the loudness button is preferred — otherwise it ships off and hidden.

---

## Journey 2.4 — Switching Output Device Mid-Session

**Actor:** User listening on AirPods who unplugs or switches to laptop speakers.  
**Goal:** Sound continues without interruption; DSP profile switches automatically.  
**Phase:** Phase 1 onwards.  
**Status (2026-10-23):** PARTIALLY BUILT. *Reconciled 2026-10-23: Steps 2, 3, 5 and 6 are rewritten — recognised headphones are **offered** a correction with a hold-to-hear preview (S13), never auto-applied; the "generic profile for the device category" is withdrawn; the profile model is "correction + taste"; Spatial is opt-in (S18). The per-output recall of Step 2 (taste only) and Step 4's toast are built; identification, the offer and Steps 5–6 are not.* Automatic output-device detection/switch and the follow-vs-pin preference work ~~(`AudioEngineBridge+Devices` / `+ConfigChange`)~~, and crossfeed auto-disables on non-headphone devices. Step 5's **spatialization-mode change** (HRTF binaural vs. speaker widening) is NOT built — the spatial render stage is an identity/stub, so the only headphone spatial effect is the opt-in crossfeed. Per-*device* EQ preset recall exists, but there is no full "DSP profile" concept. *(Re-verified 2026-10-13, after Sprint G (PR #85) and the freeze fix (PR #86): every output event goes through one device rule. Step 2 = the output's pinned EQ, else the shared EQ; Step 4 is **built** as a toast naming the output and its EQ ("AirPods Pro · Late Night"), which opens the EQ tab when tapped; the limiter ceiling and rate readout follow the output. A device **lost** while playing now pauses (both paths), keeps the place and says so — it does not continue on the speakers. Not built: Step 3's dedicated 200 ms profile crossfade (EQ changes glide through the engine's own smoothing), Step 5 (→ S18), whole profiles (→ S13). Wired headphones in the Mac's own jack are treated as speakers for crossfeed — KI-DEV-01.)* *(Since R1, PR #88 — council N92: the device the user picked is kept apart from the device the app falls back to, so when the picked device (say, Bluetooth headphones) reconnects, the next Play plays on it, not on the speakers it fell back to; until the user picks a device, the app follows the Mac's sound output. Within a session only: DEV-1.)*

**Steps:**

```
Step 1 — Device Change Detected
  App registers an AudioObjectAddPropertyListenerBlock callback on
  kAudioHardwarePropertyDefaultOutputDevice.
  Callback fires on device change (runs on non-real-time thread).

Step 2 — Recall, recognise, offer (S13; never apply)
  App looks up what THIS output remembers (its per-output memory: taste EQ, correction choice,
  loudness reference, Headphones position, Enhance).
  — Remembered → it comes back within 500 ms, no dropout longer than 50 ms.
  — Never seen → NOTHING is applied; the file plays as recorded. The device class only picks the
    default suggestion. If the output's class is uncertain (a USB DAC) the app asks once,
    "What's plugged into this output?" (Headphones / Speakers / Something else), and remembers it.
  — If the app recognises the headphone model (Sony WH-1000XM4, ANC variant shown), it OFFERS
    the correction: "Sony WH-1000XM4 recognised — hold to hear it corrected". Holding plays it
    at the same loudness (within 0.2 dB); releasing returns; one tap keeps it for these
    headphones; "Not now" is remembered and not asked again on every connect.

Step 3 — DSP Reconfiguration
  DSP parameters pushed to the audio thread via the lock-free bus; the filters move by the
  engine's own per-band glide (no dedicated profile crossfade). No audio dropout longer than 50 ms.

Step 4 — User Notification
  Non-blocking toast naming the output and what was recalled ("AirPods Pro · Late Night"; with a
  correction on, "· corrected"). Tapping opens the EQ tab.

Step 5 — A second pair of the same model
  A second pair of XM4s is a NEW output: it is offered the correction afresh, with the same preview.
  It never inherits a second copy — the correction (one library entry, −4.2 dB at 105 Hz) plays
  once, never twice (−8.4 dB would be unmistakably wrong).

Step 6 — Headphones control (S18)
  Per output, "Headphones: Off / Crossfeed / Spatial" is remembered. Spatial is offered with a
  hold-to-hear preview against a timbre-matched dry reference; it is never switched on by device
  class. Built-in speakers: no headphone control is offered.
```

**Success Condition:** Device switch results in no audio dropout longer than 50 ms and the output's remembered settings are back within 500 ms of the detected change. A fresh install with the XM4 connected plays a stream bit-identical to the file until the listener accepts the offer; the accepted correction is level-matched to the uncorrected sound within 0.2 dB.

---

## Journey 2.5 — Environment Change (Room Gets Noisy)

**Actor:** User listening in a room that has become noisier (e.g., construction starts outside).  
**Goal:** User triggers a one-shot environment sample; app adapts DSP to compensate, then releases the mic.  
**Phase:** Phase 1 onwards (requires microphone permission, LD-6 on-demand sampling only).  
**Status:** NOT YET BUILT (planned; unscheduled — backlog US-AMB-01). There is no microphone access, ambient-SPL sampling, or noise-based adaptation anywhere in the code (re-verified 2026-10-13).

**Steps:**

```
Step 1 — User Triggers Environment Sample
  The room gets noisy; the user taps "Adapt to my environment" (control strip / menu).
  App opens the mic for a short window (~3 s), computes an A-weighted SPL estimate, then releases the mic.
  No continuous monitoring; the mic is not held open between samples.

Step 2 — Noise Level Classification
  Classifies ambient level into bands: Quiet (<40 dBA), Moderate (40–65 dBA), Loud (>65 dBA).
  Hysteresis applied: must remain in new band for >3 seconds before triggering adaptation
  (avoids hunting on transient noise spikes).

Step 3 — DSP Adaptation
  Noise level change communicated to DSP thread via atomic parameter update.
  Adaptivity engine adjusts:
    — Dynamic range (reduces compression ratio in louder environments to improve clarity).
    — Low-frequency gain (slight boost to maintain bass perception over masking noise).
    — Optional: activates or deepens noise-aware loudness compensation.
  Changes applied gradually over ~1 second to avoid jarring shifts.

Step 4 — Visual Feedback
  Ambient noise indicator in status bar / control strip updates (e.g., icon changes from green to amber).
  Tooltip on hover: "Loud environment detected — audio adapted."

Step 5 — Noise Decreases
  Same hysteresis logic applies to returning to quieter state.
  DSP parameters return to prior state gradually.

Step 6 — Mic Permission Denied Fallback
  If mic access unavailable, ambient noise adaptation is skipped entirely.
  All other adaptation paths (volume, device, content) remain active.
```

**Success Condition:** In a controlled test, raising ambient noise by 25 dBA causes measurable DSP parameter change (verifiable in engineering debug view) within 5 seconds, with no audio artifacts during the transition.

---

## Journey 2.6 — Phase 2: Enabling System-Wide Enhancement

**Actor:** User who wants to enable the Phase 2 system-wide enhancement.  
**Goal:** All system audio (Spotify, Apple Music, YouTube, etc.) routed through the DSP engine.  
**Phase:** Phase 2 (system-wide, two implementation paths).  
**Status:** NOT YET BUILT (planned — Phase 2; **"Won't, this horizon"** on the roadmap). Neither path exists in the code: there is no Core Audio process tap (`CATapDescription` / `AudioHardwareCreateProcessTap`) and no AudioServerPlugIn driver. The current app processes only its own player output; the sole system-level output path is the bit-perfect Pure Mode HAL render, not a capture-all-apps tap.

**Architecture Note:**  
See `docs/architecture/architecture.md` §13 and `docs/session-notes/prior-art.md` (ADR-002) for the technical foundation. The primary mechanism for macOS 14.2/14.4+ is a **Core Audio process tap** (no driver, no admin password, no coreaudiod restart). The **AudioServerPlugIn virtual device** (FALLBACK PATH) is used when the tap path is unavailable (macOS < 14.2) or when the user specifically wants a persistent, selectable output device.

### PRIMARY PATH: Core Audio Process Tap (macOS 14.2+)

```
Step 1 — Permission Request (TCC consent only)
  App detects macOS 14.2+ (or 14.4+ — verify minimum in AudioHardwareTapping.h headers).
  App presents a plain-language explanation:
    "To enhance all apps, Adaptive Sound needs permission to capture audio output.
     You'll see a one-time macOS permission dialog. No admin password needed."
  User acknowledges with [Enable System Enhancement] or [Not Now].
  macOS presents the standard audio-capture TCC consent dialog
  (NSAudioCaptureUsageDescription; purple mic-like indicator while tap is active).

Step 2 — Tap Activation (no install, no restart)
  App creates a CATapDescription for global output, creates an AudioHardwareTap,
  and constructs a private aggregate device that reads the tap and mutes the original
  output device. All audio now flows: [any app] → tap capture → DSP engine → physical
  output device.
  No HAL plug-in installed. No coreaudiod restart. No audio interruption.

Step 3 — Physical Output Selection
  App confirms or lets the user select the physical output device for processed audio
  (defaults to the current system default output).

Step 4 — Verification
  App plays a brief internal test tone through the chain.
  User confirms they can hear it; setup wizard closes.
  App enters menu-bar mode (always-on background processing).
  Purple audio-capture indicator visible in menu bar while tap is active.

Step 5 — Disable / Revoke
  User navigates to Settings → System Enhancement → Disable, or revokes audio-capture
  permission in System Settings → Privacy & Security → Microphone (or equivalent).
  App stops the tap; original output device is unmuted automatically.
  No residual audio routing or installed files left behind.
```

### FALLBACK PATH: AudioServerPlugIn Virtual Device (macOS < 14.2 or user preference)

```
Step 1 — Pre-Install Notice (driver path)
  App presents a plain-language explanation:
    "To enhance all apps on this macOS version, we install a virtual audio device.
     This requires your administrator password and briefly interrupts system audio (~2 s)."
  User acknowledges with [Install System Enhancer] or [Not Now].

Step 2 — Privileged Installer
  A signed, notarised privileged helper (SMAppService / ServiceManagement framework)
  is invoked.
  Helper copies the AudioServerPlugIn bundle to /Library/Audio/Plug-Ins/HAL/.
  Helper restarts coreaudiod.
  Audio interruption is expected; app shows a "Restarting audio system…" overlay.

Step 3 — Virtual Device Activation
  coreaudiod loads the new plug-in.
  App detects the virtual device appears in the device list.
  App instructs the user (or does so automatically with permission) to set the virtual
  device as the macOS System Output in System Settings → Sound.

Step 4 — Physical Output Selection
  Within the app, user selects the real physical output device.
  App configures the DSP engine to read from the virtual device and write to the
  selected physical device.

Step 5 — Verification (same as tap path Step 4 above)

Step 6 — Uninstall Path
  User navigates to Settings → System Enhancer → Remove.
  Privileged helper removes the plug-in bundle, restarts coreaudiod.
  System Output automatically reverts to built-in speakers (or previous device).
  No residual audio routing left behind.
```

**Success Condition:** After Phase 2 setup (either path), music from Spotify sounds measurably different (enhancement active vs. disabled) with no additional audio latency perceptible to the user (< 10 ms round-trip added, per NFR-PERF-05). On the tap path, no admin password was required and no files were installed.

---

## Journey 2.7 — Giving Natural-Language Feedback Mid-Listen (Conversational Tuning) — *withdrawn 2026-07-12*
> Natural-language feedback removed from scope (founder decision); prior journey in git, may be re-added.

---

## Journey 2.8 — Add Music and Play from the Library *(added 2026-10-13)*

**Actor:** A listener with music in one or more folders on their Mac or an external drive.  
**Goal:** Point the app at their folders once, then find and play anything in a few clicks — and come back to it after a relaunch.  
**Phase:** Phase 0 (the player — roadmap S8–S10, R1).  
**Status:** BUILT (R1). Not built: playing a single file from outside the music folders (no Finder drop or Open…, backlog US-LIB-02); a visible state for an unplugged folder (KI-LIB-02).

**Steps:**

```
Step 1 — Add a music folder
  The empty Library offers "add a music folder"; the Library rail's Music Folders section adds more,
  and removes one (songs a user playlist names stay as loose songs).
  The scan walks each folder once at a time, reads tags and artwork in the background, and shows progress.

Step 2 — Browse and find
  Songs (sortable, customizable columns, keyboard selection), Albums, Artists and Genres
  (tile grids, arrow keys), each with a detail page and a Filter field.

Step 3 — Play
  Double-click a song, or Play / Shuffle a page: the queue is replaced ("Restore previous queue"
  undoes it for a few seconds). Play Next / Add to Queue insert without replacing.

Step 4 — Live with it
  Files added, moved or deleted in Finder show up live (FSEvents); a moved file keeps its identity,
  play count and playlist places. Changes made while the app was closed are caught up at launch.

Step 5 — Come back
  Quit and relaunch: the queue, the track, its position, shuffle and repeat come back paused.
```

**Success Condition:** A 10,000-song library is browsable and playable with no beach ball, and survives a relaunch and a Finder move with every playlist entry intact.

---

## Journey 2.9 — Curate a Playlist *(added 2026-10-13)*

**Actor:** A listener who wants a lasting selection of songs, separate from the play queue.  
**Goal:** Create a playlist, fill it from anywhere in the library, order it, and play it — without ever moving a file.  
**Phase:** Phase 0 (roadmap S10.1–S10.3, R1).  
**Status:** BUILT (R1). Not built: adding a file from outside the library (US-PLIST-02); dragging from one playlist into another; "save queue as playlist". Dragging a multi-selection adds only one song (KI-LIB-04).

**Steps:**

```
Step 1 — Create
  The + on the Library rail's Playlists header ("New Playlist", then "New Playlist 2", …);
  rename or delete it later.

Step 2 — Fill
  Drag a song onto the playlist in the rail, or use Add to Playlist on a song, a selection,
  a detail page or a tile. Adding is always a reference: the file never moves.

Step 3 — Order
  Drag rows by their grip, or Move Up / Move Down; remove rows.

Step 4 — Play
  Play or Shuffle the playlist: it becomes the queue. A song whose file is missing is skipped,
  badged, and can be re-pointed (Locate…) or removed ("Remove Missing…").
```

**Success Condition:** A playlist keeps its songs and order across relaunches, schema upgrades and Finder moves; no playlist action changes a file on disk.

---

## Journey 2.10 — Bit-Perfect Listening with Pure Mode *(added 2026-10-13)*

**Actor:** An audiophile with a USB DAC who wants the file's bits to reach the DAC unaltered.  
**Goal:** Play the library bit-perfect, at each track's own sample rate, and know at a glance that it is.  
**Phase:** Phase 0 (the anchor story — "this Mac → this DAC, bit-perfect").  
**Status:** BUILT (R1). Pure falls back to Enhanced on Bluetooth / AirPlay by design (the link re-encodes), and — since PR #88 — for a track whose channel count is not the device's (a mono file on stereo speakers) or a device format it cannot write exactly, saying so in Settings. ~~Open: a mid-song Repeat / Shuffle change or queue edit may not reach Pure's next track (KI-PB-01, needs a live check);~~ *(fixed by PR #88, council D41: a changed next song reaches Pure; residual KI-PB-16)* Open: switching Pure on or off waits for a manual start (KI-PB-05). The founder's by-ear check on a USB DAC is still owed.

**Steps:**

```
Step 1 — Turn it on
  Settings › Pure Mode (Bit-Perfect) › "Play bit-perfect". It applies at the next track start.

Step 2 — Play
  The app takes the device directly (HAL, hog mode), switches it to each track's sample rate,
  and bypasses every DSP stage, EQ included. Same-rate tracks join gaplessly. A track Pure can't
  play exactly (another channel count, a device format it can't write bit for bit) plays in
  Enhanced, and Settings says so.

Step 3 — Check
  Settings shows what is playing through ("Playing through: Pure") and the rate; Master Gain
  becomes the device's own volume.

Step 4 — Change device or lose it
  Choosing another output restarts at the playhead on it (or falls back to Enhanced there);
  unplugging the DAC pauses and keeps the place; when a DAC the user picked comes back, Play plays on it.
```

**Success Condition:** A loopback capture of a 24-bit FLAC at the device's rate is bit-identical to the file (NFR-QUAL-03).

---

## Journey 2.11 — Pressing Enhance *(added 2026-10-23, reconciliation card 11)*

**Actor:** A listener who does not know what "crossfeed" or "loudness compensation" mean.  
**Goal:** Get the better sound on the output in use with one tap, know in plain words what changed, and check it in a second.  
**Phase:** Phase 1 (the first sprint with a winning stage — S14-lite).  
**Status:** NOT YET BUILT (planned — backlog US-UI-08).

**Steps:**

```
Step 1 — The switch exists only where something won
  Enhance appears for an output only if some stage won the founder's blind A/B there (the XM4,
  the soundbar). It is off on a fresh install. A launch plays the file as recorded.

Step 2 — Press it
  One thing gets better now, at the same loudness: no fade-in over seconds, no level jump,
  nothing the listener set by hand is touched (Enhance only turns stages ON). Only stages that
  won on THIS output turn on; a stage that lost never does. Loudness is skipped if this output's
  "normal loud setting" is not set yet (the row says so).

Step 3 — Read the chip (Now Playing, beside the status badge)
  "Enhance: even levels · full at low volume · headphones in a room" — only the stages really
  playing, in the listener's words. When the level changes by design it says so:
  "−6 dB to match your other albums" (shown at 1 dB or more). The badge never reads "ENHANCED"
  alone: it names what is on, or says nothing is ("Untouched").

Step 4 — Check it
  Hold the chip: the song plays without the stages Enhance turned on, at the same loudness
  (within 0.2 dB). Release: back. Claim checked in a second.

Step 5 — Turn it off
  Exactly the stages Enhance turned on go off (anything the listener had on stays); the chip goes;
  with nothing else on, the file is as recorded.

Step 6 — In Pure
  The row reads "Not in bit-perfect mode — leave Pure?" with one tap to leave Pure. The Pure card
  answers, in one sentence, why there are two untouched states (Pure; Enhanced with nothing on).
```

**Success Condition:** On each output, the founder's blind, level-matched A/B of Enhance on against off (about 23 trials, capped at 60) is "prefer"; Enhance never turns on a stage that lost.

---

## Journey 2.12 — Playing a Surround Album on Stereo Headphones *(added 2026-10-23, reconciliation card 5)*

**Actor:** A listener with a 5.1 music album and stereo headphones or a soundbar.  
**Goal:** Hear every channel, at a sensible level, with the bass intact, and know what the app did.  
**Phase:** Phase 0 (interim fold — R1.1-B; the final arrangement is the Engine sprint's).  
**Status:** NOT YET BUILT (planned — backlog US-R1F-08). Today four of six channels are dropped.

**Steps:**

```
Step 1 — Play it
  Pure declines the file (6 channels, 2-channel output): "This track has 6 channels and your output
  has 2, so Enhanced plays it, folded to stereo." Enhanced folds it with the standard BS.775
  matrix (centre and surrounds into each side at −3 dB). The badge reads "5.1 → stereo".

Step 2 — The level
  Folding can add up to +7.66 dB on a dense mix. A per-track trim from the folded true peak
  (−7.7 dB until the track is analysed) keeps the safety net asleep, so a dense album is not
  squashed and a quiet one is barely touched. With Leveling on, the folded loudness (1–2 LU under
  the six-channel figure) is what levels it.

Step 3 — Crossfeed does nothing here
  With crossfeed switched on, the folded file plays without it (crossfeed is stereo-only until the
  fold moves into the engine). The switch reads "not active on surround albums" and the badge shows
  no "XF". A stereo album shows "XF".

Step 4 — The LFE (the subwoofer channel), decided per track
  If it is a copy of the bass already in the main channels, it is left out (adding it would double
  the bass, +6 dB, boomy). If it carries bass the mains do not, it is added at full level to each
  side, and the trim is computed with it. When unknown: left out.
  Before this ships, the founder listens on the XM4 to one album of each kind, a bass-heavy passage
  three ways (omit / −6 dB / full): pass = no "where did the bass go", no boominess.
```

**Success Condition:** A centre-only tone comes out −3.0 dB per side; a stereo file inside a 5.1 container folds to exactly the stereo input; the limiter's gain reduction on the founder's surround albums is 0.0 dB; the two LFE albums pass the founder's listen.

---

## Journey 2.13 — Leveling in Both Modes *(added 2026-10-23, reconciliation card 1)*

**Actor:** A listener who shuffles a 1980s master and a modern loud one.  
**Goal:** Everything at one level, whichever mode, and nothing ever moving inside a song.  
**Phase:** Phase 0 (R1.1-B).  
**Status:** NOT YET BUILT (planned — backlog US-R1F-10). Today the only leveller is the old auto-leveller, held silent only because Intensity is hidden.  
**Amended 2026-10-25 (founder, R1.1-B's plan check):** Pure declines Bluetooth, so the XM4 always plays Enhanced — the premise that Pure is the founder's daily mode was wrong; leveling in Pure is deferred until the USB DAC arrives, verified there. R1.1-B builds Steps 1, 2 and 5; Steps 3 and 4 land with the USB DAC. The Leveling row lives in Settings (founder, 2026-10-25).

**Steps:**

```
Step 1 — Choose
  Settings › "Even out track levels": Off / Auto / Album / Track. Off by default. The row shows the target,
  "Target −18 LUFS", and the playing track's gain and where it came from ("from analysis",
  "from file tags", "unknown: −5 dB"). Auto = the album gain when the neighbouring track — the one
  just played or the next — is from the same album, else the track gain; a gapless album takes
  the album gain.

Step 2 — Enhanced
  One constant gain, fixed when the track starts, through the per-track gain: a quiet intro and a
  loud chorus play as mastered; only the whole track sits at −18. A louder-than-target master is
  turned down; a quiet one is raised only as far as its true peak allows, so the safety net never
  works. A track with no analysis and no tag gets a fixed −5 dB for its whole length — never a
  live guess. Change the mode mid-song and it applies at once with a short glide — your own act;
  nothing automatic moves the level inside a song. In Album mode, before the album is fully
  analysed: its tags if every track has them, else the track's own gain until the next seam
  across silence (decided 2026-10-25).

Step 3 — Pure (deferred until the USB DAC arrives — amended 2026-10-25)
  In R1.1-B the row reads "Leveling off (bit-perfect)" and Pure plays the file untouched. Once
  the DAC is here and its check passes: same choice, same result, on the device's own volume: loud tracks are turned down in the
  device's volume steps (never raised). The cut is set between tracks, never inside one. The Mac's
  volume indicator moves by itself at track changes, and the readout says why: "Leveled −4.2 dB on
  the device volume". The app's own moves are not mistaken for the listener's: ten track changes
  in a row never walk the level down. If the listener presses a volume key, that is theirs.

Step 4 — Where it cannot (with Step 3, deferred)
  On the soundbar ("Set on device") the Mac cannot set the volume: no leveling in Pure, and the row
  says so. 

Step 5 — Give-back (R1.1-B — Master Gain's loan, not leveling)
  When Pure ends (Stop, end of the queue, Enhanced starting, another output), the device volume
  Master Gain lowered is put back and a toast says "Volume restored".
```

**Success Condition:** Over the founder's loudest albums the limiter's gain reduction is 0.0 dB; ~~ten track changes in Pure never re-anchor the listener's volume~~ (moved with Step 3 to the DAC, 2026-10-25); by ear on the XM4, in Enhanced, a mixed-era shuffle on Auto keeps albums even with nothing moving inside a song; in Pure on the Mac's built-in output the row reads "Leveling off (bit-perfect)" and, after a Master Gain cut, "Volume restored" shows once at the end of the queue; with Leveling Off, an Intensity sweep leaves integrated loudness unchanged within 0.1 dB.

---

## Cross-References

- **Requirements.md:** Journey descriptions in §2 link back to this document. (`docs/product/requirements.md` — exists.)
- **UX-guidelines.md:** §2.2 (Core Journeys) references each journey's UX principles. *(Planned — this document does not yet exist in the repo. The closest live references are the design packages under `docs/design/` and [s10-7-liquid-glass-design.md](../sprints/s10-7-liquid-glass-design.md).)*
- **Test-and-qa-strategy.md:** §3.1 (Integration Test Journeys) uses these journeys as the basis for end-to-end testing. *(Planned — this document does not yet exist in the repo. The QA strategy that exists is [validation-strategy.md](../architecture/validation-strategy.md), which does not use the journeys; the Sprint G break-it reports exercised Journeys 2.3, 2.4 and 2.8–2.10 by hand.)*
- **Open defects:** [known-issues.md](known-issues.md). **Stories:** [backlog.md](backlog.md) (EP-LIBRARY / EP-PLAYLIST for 2.8–2.9; US-ENG-07 for 2.10).

---

## Open Questions

- **OQ-01:** First-run onboarding — auto-switch virtual device vs. manual?
- **OQ-03:** Environment sampling window length and SPL smoothing (Journey 2.5).

See `docs/product/requirements.md` §7 for full open-questions list with impact & priority.
