# User Journeys — Adaptive Sound

**Document ID:** JOURNEYS-ASE-001  
**Version:** 1.0 — extracted from requirements.md v0.6  
**Date:** 2026-06-13  
**Extracted by:** Business Analyst (refactoring for clarity)  
**Status:** Authoritative; cross-referenced from requirements.md

---

## Overview

This document defines the core user journeys (workflows) for Adaptive Sound. Each journey describes a specific actor, goal, and step-by-step interaction flow. Success conditions are measurable.

**Journeys are organized by persona and phase:**
- **Journeys 2.1–2.5:** Phase 0 & Phase 1 (own-player focus)
- **Journey 2.6:** Phase 2 (system-wide, two implementation paths)
- **Journey 2.7:** Natural-language steering (Conversational Tuning, applies across phases)

> **Implementation status (current build).** These journeys are product *specifications*, not descriptions of shipped behavior. Verified against `Sources/` on `main`, the current app is a Phase-0 own-player: it launches straight into a four-tab window (Now Playing · EQ · Monitoring · Settings) with local-file playback, a 31-band EQ, LUFS loudness normalization + a true-peak limiter, opt-in crossfeed, a Reimagine "Intensity" (wet/dry) knob, a bit-perfect Pure Mode, gapless + multichannel playback, and automatic output-device switching. Each journey below carries a **Status** line marking how much is built. Onboarding, hearing calibration, the automatic adaptivity engine, environment/mic sensing, natural-language tuning, and Phase-2 system-wide capture are **not yet built** — they remain valid *planned* journeys, not current behavior.

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
**Status:** NOT YET BUILT (planned). The app launches directly into the four-tab player; there is no welcome screen, hearing-profile prompt, mic-permission step, or first-run tooltip.

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

Step 3 — Hearing Profile Prompt
  App asks: "Would you like a quick hearing check to personalise your experience?"
  Options: [Start Hearing Check] [Skip for Now]
  If skipped → uses a neutral default profile; reminder surfaced in Settings after 3 listening sessions.

Step 4 — Microphone Permission (Environment Sensing)
  System dialog requests microphone access.
  App explains in plain language: "Used only to sense room noise — never recorded or transmitted."
  If denied → environment sensing disabled; adaptive ambient-noise feature inactive; user notified with non-blocking banner.

Step 5 — Profile Load and Playback Ready
  App loads default DSP profile for detected device.
  Opens media browser / file importer.
  User selects a track and presses Play.
  Adaptivity engine begins processing; visual VU/analysis meter shows activity.

Step 6 — First Listening Moment
  After 10 seconds of playback, a subtle non-blocking tooltip appears:
  "Sound is adapting to your headphones and room — no action needed."
```

**Success Condition:** User is listening to music with the adaptivity engine active within 3 minutes of first launch, with no technical errors.

---

## Journey 2.2 — Hearing Profile Calibration

**Actor:** User who chose to run or re-run the hearing check.  
**Goal:** Generate a personal hearing profile that the DSP engine uses for equalisation compensation.  
**Phase:** Phase 0 onwards (optional, skippable).  
**Status:** NOT YET BUILT (planned). No hearing test, tone sequence, audiogram, or stored hearing profile exists; the only "hearing"-adjacent code is the unrelated EQ cumulative-gain safety clamp.

**Steps:**

```
Step 1 — Pre-Check Instructions
  App displays: headphone requirement notice, estimated time (~5 minutes), quiet environment recommendation.
  Volume is automatically set to a safe calibration level (~65 dBSPL target, not app-adjustable during test).

Step 2 — Tone Playback Sequence
  App plays pure tones at discrete frequencies across both ears (500 Hz, 1 kHz, 2 kHz, 3 kHz, 4 kHz, 6 kHz, 8 kHz — minimum; extended range optional).
  User presses and holds "I can hear this" button for each tone; minimum presentation threshold derived.
  Audiogram-style result graph displayed.

Step 3 — Profile Saved
  Hearing profile stored locally (encrypted, not synced by default).
  Profile applied immediately to DSP engine.
  User can label the profile (e.g., "My AirPods", "Office Headphones") and link it to a specific output device.

Step 4 — Ongoing Prompt
  App offers to re-run calibration if output device changes to a new device category not yet profiled.
```

**Success Condition:** A stored hearing profile exists, is linked to the active output device, and measurably alters EQ curves in the DSP chain.

---

## Journey 2.3 — Normal Listening Session (Phase 1 — Own Player)

**Actor:** Returning user with a configured profile.  
**Goal:** Listen to a music playlist with seamless adaptive enhancement.  
**Phase:** Phase 1 (mix-level adaptation).  
**Status:** PARTIALLY BUILT. Playback, manual 31-band EQ (+ per-device preset recall), LUFS loudness normalization + true-peak limiter, crossfeed, and the Reimagine "Intensity" wet/dry knob are live. The **automatic adaptivity** in Steps 3–5 is NOT built: there is no content/genre classifier and no Fletcher-Munson volume compensation (only a manual EQ + program-loudness normalization; no per-track curve cross-fades).

**Steps:**

```
Step 1 — App Launch / Resume
  App opens to last state (queue, volume, playback position if paused).
  Detects currently active output device; loads matching profile automatically.

Step 2 — Track Playback
  User presses Play.
  Audio routed through DSP chain: EQ → spatialization → dynamics → output.
  Adaptivity engine begins analysis; adapts over first 2–5 seconds per track.

Step 3 — Genre / Spectral Analysis
  Content analyser runs on audio buffer (on a non-real-time thread).
  Derived spectral profile / genre classification communicated to DSP via lock-free parameter update.
  DSP gradually cross-fades to genre-appropriate tonal curve (no abrupt change).

Step 4 — Volume Adjustment
  User changes volume (system slider or in-app).
  Adaptivity engine applies Fletcher-Munson equal-loudness compensation:
    — Low volume → boosts bass and treble to preserve perceived balance.
    — High volume → reduces over-compensation to avoid over-emphasis.

Step 5 — Track Skip / Change
  New track begins; content analyser re-evaluates within 2–5 seconds.
  DSP parameters smoothed across track boundary; no audible click or abrupt shift.

Step 6 — Session End
  User pauses/closes app.
  Session state (queue, position, active profile) persisted.
```

**Success Condition:** User experiences no audible glitches across a 1-hour session; adaptive parameters visibly change between tracks of different genres in the analysis display.

---

## Journey 2.4 — Switching Output Device Mid-Session

**Actor:** User listening on AirPods who unplugs or switches to laptop speakers.  
**Goal:** Sound continues without interruption; DSP profile switches automatically.  
**Phase:** Phase 1 onwards.  
**Status:** PARTIALLY BUILT. Automatic output-device detection/switch and the follow-vs-pin preference work (`AudioEngineBridge+Devices` / `+ConfigChange`), and crossfeed auto-disables on non-headphone devices. Step 5's **spatialization-mode change** (HRTF binaural vs. speaker widening) is NOT built — the spatial render stage is an identity/stub, so the only headphone spatial effect is the opt-in crossfeed. Per-*device* EQ preset recall exists, but there is no full "DSP profile" concept.

**Steps:**

```
Step 1 — Device Change Detected
  App registers an AudioObjectAddPropertyListenerBlock callback on
  kAudioHardwarePropertyDefaultOutputDevice.
  Callback fires on device change (runs on non-real-time thread).

Step 2 — Profile Resolution
  App looks up the profile associated with the new device.
  If a profile exists → loads it.
  If no profile exists → loads generic profile for the device category (headphones vs. speakers).

Step 3 — DSP Reconfiguration
  DSP parameters pushed to audio thread via lock-free atomic/ring-buffer mechanism.
  Old DSP state fades out, new state fades in over a configurable crossfade window (default: 200 ms).
  No audio dropout; ring buffer absorbs the gap.

Step 4 — User Notification
  Non-blocking banner: "Switched to Built-in Speakers — Speaker profile loaded."
  Banner includes shortcut: [Edit Profile].

Step 5 — Spatialization Mode Change
  AirPods → binaural HRTF / head-tracked mode active.
  Built-in speakers → crossfeed / stereo widening mode; HRTF disabled (already physical stereo).
```

**Success Condition:** Device switch results in no audio dropout longer than 50 ms and the correct profile is applied within 500 ms of the detected change.

---

## Journey 2.5 — Environment Change (Room Gets Noisy)

**Actor:** User listening in a room that has become noisier (e.g., construction starts outside).  
**Goal:** User triggers a one-shot environment sample; app adapts DSP to compensate, then releases the mic.  
**Phase:** Phase 1 onwards (requires microphone permission, LD-6 on-demand sampling only).  
**Status:** NOT YET BUILT (planned). There is no microphone access, ambient-SPL sampling, or noise-based adaptation anywhere in the code.

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
**Status:** NOT YET BUILT (planned — Phase 2). Neither path exists in the code: there is no Core Audio process tap (`CATapDescription` / `AudioHardwareCreateProcessTap`) and no AudioServerPlugIn driver. The current app processes only its own player output; the sole system-level output path is the bit-perfect Pure Mode HAL render, not a capture-all-apps tap.

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

## Journey 2.7 — Giving Natural-Language Feedback Mid-Listen (Conversational Tuning)

**Actor:** Returning user actively listening to music.  
**Goal:** Adjust the sound by typing what they hear in plain language, without touching EQ controls.  
**Phase:** Phase 1 onwards (NL tuning, mechanism deferred per OQ-11).  
**Status:** NOT YET BUILT (planned; mechanism deferred, OQ-11). There is no text-input control, intent-derivation subsystem, confirmation card, or transparency log in the code — no natural-language path of any kind exists yet.

**Steps:**

```
Step 1 — Opening the Conversational Tuning Input
  User notices the sound feels off (e.g., bass is too weak).
  User clicks the "Tell us what you hear" button in the Now Playing view
  (or activates via keyboard shortcut).
  A compact text field slides in below the Now Playing view.
  Placeholder text reads: "e.g. 'bass is too low' or 'voices are hard to hear'"

Step 2 — Entering Feedback
  User types: "bass is too low"
  No submit button required; user presses Return or clicks "Apply".
  The app accepts the raw text and passes it to the Conversational Tuning
  subsystem for intent derivation.
  A subtle processing indicator appears (spinner or pulsing waveform icon)
  while intent is being derived — target: < 1 500 ms.

Step 3 — Intent Derived, Change Applied
  The subsystem determines intent: raise low-frequency gain (60–250 Hz), moderate
  magnitude, positive direction.
  Change is communicated to the DSP thread via the existing lock-free parameter
  path (FR-ADAPT-02 / FR-ADAPT-03); gain ramps smoothly (≥ 50 ms, per FR-ADAPT-03).
  The text field clears; a confirmation card appears:
    "Boosted bass (60–250 Hz) +3 dB  — does that feel better?
     [Yes, keep it]  [Undo]  [Adjust more]"
```

**Success Condition:** User receives an audible change within 500 ms of typing, with a confidence-driven confirmation card reflecting the system's interpretation of the user's intent.

---

## Cross-References

- **Requirements.md:** Journey descriptions in §2 link back to this document. (`docs/product/requirements.md` — exists.)
- **UX-guidelines.md:** §2.2 (Core Journeys) references each journey's UX principles. *(Planned — this document does not yet exist in the repo.)*
- **Test-and-qa-strategy.md:** §3.1 (Integration Test Journeys) uses these journeys as the basis for end-to-end testing. *(Planned — this document does not yet exist in the repo.)*

---

## Open Questions

- **OQ-01:** First-run onboarding — auto-switch virtual device vs. manual?
- **OQ-03:** Environment sampling window length and SPL smoothing (Journey 2.5).
- **OQ-07:** Hearing profile — ISO 8253-1 conformance (Journey 2.2)?
- **OQ-11:** Conversational Tuning architecture (Journey 2.7 mechanism — deferred).

See `docs/product/requirements.md` §7 for full open-questions list with impact & priority.
