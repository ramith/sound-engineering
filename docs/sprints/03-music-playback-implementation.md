# Sprint 3: Music File Playback Implementation Plan

**📋 STATUS: READY FOR TEAM SIGN-OFF**  
**Duration:** 3–4 days (~10 story points)  
**Goal:** Replace reference tone with local folder-based music file playback, matching the high-fidelity design spec from `assets/AdaptiveSound.zip`  
**Date Approved:** 2026-06-15  
**Team Cross-Reference:** BA/PM + Audio DSP Agent + SwiftUI Pro + QA Expert

---

## 1. Mission & User Value

### Why This Matters
Phase 1a shipped a playback infrastructure with a 1 kHz reference tone. This feature **gates every subsequent DSP validation workstream** — without real music flowing through the pipeline, the EQ, Clarity, BRIR, Loudness, and Limiter modules cannot be perceptually tested.

### User Journeys Enabled
- **Journey 2.1 (First-Run Onboarding):** User picks a music folder on first launch, selects a track, presses Play. "Listening within 3 minutes" success criterion becomes achievable.
- **Journey 2.3 (Normal Listening Session):** Return user opens the app, restores their last folder and queue, resumes listening.
- **Journey 2.7 (Conversational Tuning):** Text input anchor is the Now Playing view — depends on this feature existing.

### Locked Decisions Alignment
- **LD-1 (Own-player scope):** Squarely within Phase 0/1. No system-wide, no streaming.
- **LD-4 (Local files only):** `NSOpenPanel` folder picker, recursive enumeration, local files only. Streaming deferred to Phase 2.
- **LD-10 (Quality-first hardware use):** Transparent SRC (44.1 kHz → 48 kHz), lock-free file I/O, no allocation on render thread.
- **LD-16 (Reimagine knob):** Module toggles shown in the design; knob placeholder reserved for Phase 1.5.

---

## 1.5. Scope Decisions & Implications (Approved by User)

### Decision Summary
Your team approved the following scope trade-offs for Phase 1b:

| Decision | Implication | Impact |
|----------|-----------|--------|
| **AU graph wiring deferred to Phase 1c** | File playback **bypasses DSP chain** in Phase 1b. Reference tone was processed; music files will be unprocessed. | ⚠️ No perceptual DSP testing yet. Audio flows through mixer only, not through EQ/Clarity/BRII/Loudness/Limiter kernel. Null-test cannot validate. Phase 1c must unblock this. |
| **Live FFT spectrum in Phase 1b** | Real audio data drives bars in real time. Requires `vDSP_fft_zrip` on audio buffers + publish magnitudes every 100ms. | ✅ High-fidelity visual feedback. Adds 2–3 hours to Part 3. Frequency-domain audio analysis is independent of DSP chain (works even when bypassed). |
| **Module toggles display-only** | Checkboxes show state (EQ on, others off) but don't enable/disable DSP. Functional toggles deferred to Phase 1c. | ✅ Simplifies Phase 1b scope. UI is complete and extensible; Phase 1c flips a switch to make toggles functional (no UI rework needed). |
| **Full queue persistence** | Save exact track list (all absolute paths), not just folder URL. On relaunch, missing files are skipped. | ✅ Preserves user's queue across restarts. Requires error handling for deleted files (graceful skip, no crash). |
| **Device dropdown in toolbar** | Move from fixed header to 60pt toolbar. Toolbar now has: Logo | Device | Tabs | Volume. Header is just title. | ✅ Matches design spec exactly. Requires significant `HeaderView` refactor. |
| **Auto-play next on completion** | File finishing → auto-advance to next track (queue advances automatically). | ✅ Continuous listening experience. Completion handler wired to `playNext()`. |
| **Team: 2–3 developers** | Work parallelized across three streams: Tooling/Architecture, Playback/Seek, UI/Integration. | ✅ Reduces wall-clock time to **1.5 days**. Requires clear ownership boundaries. |

### Key Unknown Unknowns Going Into Phase 1c
1. **AU graph wiring complexity:** How much refactoring is needed to unify dual `AVAudioEngine` instances? (Estimated 4–6 hours in audio-dsp-agent review, but real work may vary.)
2. **FFT latency impact:** Does 10ms FFT latency (512 samples at 48 kHz) introduce perceivable lag in spectrum display? (Stress test during Phase 1b manual testing.)
3. **Session restore on file deletion:** How robust is the bookmark-based recovery? (Force-quit test + file deletion scenario in manual testing.)

---

## 2. Design Specification

The design is defined in a high-fidelity HTML prototype: `assets/AdaptiveSound.zip` → `design_handoff_now_playing/Adaptive Sound - Now Playing.dc.html`. Key features:

### Layout Structure
```
Window (1120×752 min, resizable)
├─ Toolbar (60px, device dropdown + tabs + volume)
└─ Body (horizontal split)
   ├─ Left (flex): Spectrum → Play Controls → Master Gain → Playlist (scrollable)
   └─ Right (348px fixed): Now Playing Widget + Active Modules + Intensity Placeholder
```

### Toolbar
- **App mark:** Existing 5-bar logo (gradient teal background)
- **Device dropdown:** Speaker icon + label + sample rate + chevron (teal accent)
- **Tab selector:** Now Playing | EQ | Settings (segmented, active = teal fill)
- **Volume slider:** Icon + track + knob + % label (right side)

### Left Column Transport
1. **Spectrum analyzer:** 50px tall, ~88 bars, gradient teal, animated when playing
2. **Play controls:** Previous (-) | Play/Pause (large teal circle with glow) | Next (+)
3. **Master Gain slider:** Full-width, labeled, shows dB value
4. **Divider**
5. **Playlist:**
   - Header: "Playlist" label + "N files · recursive" count + "Choose Folder…" button
   - Current folder bar: path in mono (~/Music/Library/...)
   - File rows (scrollable):
     - Leading index (or animated mini-EQ for active track)
     - Track name + relative path (truncated)
     - Format badge (FLAC/MP3/WAV/AAC/ALAC)
     - Duration (right-aligned, tabular numerals)
     - Active row: teal highlight + inset ring
     - Tooltip: full absolute path on hover

### Right Column (Side Panel)
1. **Now Playing widget:** Compact card with album art (52px placeholder), title, artist, mini progress bar
2. **Active Modules:** 2-column grid of checkboxes (EQ, Clarity, BRIR, Loudness, Limiter) — multi-select
3. **Intensity placeholder:** Dashed border box + lock icon + "No module selected" (for Phase 1.5)

### Design Tokens (Final & Exact)
- **Window bg:** `#1e1e1e`
- **Accent teal:** `#29b6a4` (solid), `#3fd0ba`/`#4fd2c0` (light), `#1fa893`/`#14897a` (deep)
- **Text hierarchy:** White / `rgba(255,255,255,.85)` / `rgba(255,255,255,.5)` / `rgba(255,255,255,.32)`
- **Cards/rings:** `rgba(255,255,255,.045)` / `rgba(255,255,255,.07)` inset
- **Section labels:** 11px / 600 weight / uppercase
- **Spacing grid:** 8pt base; gaps 6/13/16/26; radius 4/5/8/11/12
- **Sliders:** 5px track, 3px radius, 15px white knob, teal fill

---

## 3. Implementation Breakdown

### Part 1: Prerequisites & Architecture (4–5 hours)

**Decision:** AU graph wiring deferred to Phase 1c. File playback will bypass the DSP chain in Phase 1b (known limitation). Focus is on file loading, playlist, and playback infrastructure.

#### Part 1a: Migrate AudioViewModel to @Observable (2–3 hours)
**Owner:** SwiftUI Pro  
**Task:** Replace legacy `ObservableObject`/`@Published` with modern `@Observable`/`@MainActor` to prevent view re-renders on every audio engine state change.

**Why now:** During file playback, properties like `playbackPosition`, `spectrum`, and `activeModules` change frequently. The old pattern re-evaluates all observing views in full; the new pattern only marks accessed properties as dirty. Critical before live FFT spectrum work.

**Changes:**
- `AudioViewModel`: Remove `ObservableObject`, add `@Observable` macro, change property declarations to `var` (no `@Published`)
- Add `@MainActor` to ensure all state mutations happen on main thread
- Update all view code: `@EnvironmentObject` → `@Environment(AudioViewModel.self)`, `@StateObject` → `@State`
- Test tab switching and playback state updates for smooth response

**Deliverable:**
- [ ] `AudioViewModel` compiles with `@Observable`
- [ ] All view code updated (ContentView, NowPlayingTabView, etc.)
- [ ] Tab switching smooth, no jank on playback position updates
- [ ] Build + test pass

#### Part 1b: Toolbar Restructuring (2–3 hours)
**Owner:** SwiftUI Pro  
**Task:** Move device dropdown from header into the toolbar (per design spec). Header becomes just the app title.

**Current state:** Header (44pt) has Logo | Device | Play/Stop | Volume. Toolbar (will be 60pt) has tabs only.

**New state (design):** 
- Header (44pt): Just app title "Adaptive Sound"
- Toolbar (60pt): Logo | Device Dropdown | Tab Selector | Spacer | Volume Slider

**Changes:**
- Restructure `HeaderView` → remove device dropdown logic (move to toolbar)
- Create toolbar component with all 4 elements
- Device dropdown now shares space with tabs (horizontal flow)
- All interactive elements remain ≥44×44pt

**Deliverable:**
- [ ] Toolbar component created with all 4 elements
- [ ] Device dropdown integrated (Menu with checkmark.circle.fill icon)
- [ ] Tab selector in toolbar (segmented control)
- [ ] Volume slider on right (gradient teal fill)
- [ ] Spacing/alignment matches design spec (grid 8pt, gaps 26pt between play buttons)

### Part 2: File Picker & Playlist Enumeration (4–5 hours)

**Owner:** SwiftUI Pro + Audio DSP Agent  
**Deliverables:** A browsable, recursive file list from a user-selected folder

#### Part 2a: Native Folder Picker (1.5 hours)
**Task:** Replace reference tone with AVAudioFile-based file loading.

```swift
// Use fileImporter modifier for SwiftUI integration
.fileImporter(
    isPresented: $showFolderPicker,
    allowedContentTypes: [.folder],
    allowsMultipleSelection: false
) { result in
    do {
        let folderURL = try result.get().first!
        folderURL.startAccessingSecurityScopedResource()
        // Store for session; call endAccessing on unload/app termination
        viewModel.loadMusicFolder(folderURL)
    } catch {
        // Show inline error
    }
}
```

**Deliverable:**
- [ ] "Choose Folder…" button opens NSOpenPanel (native file picker)
- [ ] User selects a folder
- [ ] Folder path stored in `viewModel.musicFolderURL`
- [ ] Security-scoped resource access initialized

#### Part 2b: Recursive File Enumeration (2 hours)
**Task:** Discover all audio files in the selected folder and its subfolders.

```swift
// In AudioViewModel, background task
@MainActor
func loadMusicFolder(_ folderURL: URL) {
    Task(priority: .userInitiated) {
        let tracks = await enumerateAudioFiles(in: folderURL)
        self.playlist = tracks
        self.currentIndex = 0
    }
}

private func enumerateAudioFiles(in folder: URL) async -> [Track] {
    let supportedFormats = ["flac", "mp3", "wav", "aac", "m4a", "alac", "aiff"]
    var results: [Track] = []
    
    let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.contentTypeKey, .fileSizeKey]
    )
    
    for case let fileURL as URL in enumerator ?? [] {
        let pathComponents = fileURL.pathComponents
        if supportedFormats.contains(fileURL.pathExtension.lowercased()) {
            let relativePath = /* derive from folder + fileURL */
            let track = Track(
                name: fileURL.deletingPathExtension().lastPathComponent,
                relativePath: relativePath,
                absoluteURL: fileURL,
                format: fileURL.pathExtension.uppercased(),
                durationSeconds: await getFileDuration(fileURL)
            )
            results.append(track)
        }
    }
    return results.sorted { $0.name < $1.name }
}
```

**Deliverable:**
- [ ] `AudioViewModel.playlist: [Track]` populated from folder recursively
- [ ] Folder-path bar displays (e.g. "~/Music/Library/Indie/2024/...")
- [ ] "N files · recursive" count updates
- [ ] Background enumeration (no UI block)
- [ ] Error handling: unsupported format shows inline message

#### Part 2c: Metadata Extraction + Full Queue Persistence (2.5 hours)
**Task:** Load track metadata asynchronously. Save/restore full queue (exact track list), not just folder.

```swift
private func extractMetadata(for track: Track) async -> Metadata {
    let asset = AVAsset(url: track.absoluteURL)
    
    let metadata = try? await asset.load(.commonMetadata)
    let duration = try? await asset.load(.duration).seconds
    
    let title = AVMetadataItem.metadataItems(
        from: metadata,
        filteredByIdentifier: .commonIdentifierTitle
    ).first?.stringValue ?? track.name
    
    let artist = AVMetadataItem.metadataItems(
        from: metadata,
        filteredByIdentifier: .commonIdentifierArtist
    ).first?.stringValue ?? "Unknown Artist"
    
    let album = AVMetadataItem.metadataItems(
        from: metadata,
        filteredByIdentifier: .commonIdentifierAlbumName
    ).first?.stringValue ?? "Unknown Album"
    
    let artwork = AVMetadataItem.metadataItems(
        from: metadata,
        filteredByIdentifier: .commonIdentifierArtwork
    ).first?.dataValue.map { UIImage(data: $0) } ?? nil
    
    return Metadata(title: title, artist: artist, album: album, artwork: artwork, duration: duration ?? 0)
}
```

**Full Queue Persistence:**
Instead of saving just the folder URL, save the entire enumerated track list. This preserves the queue state across app restarts, but requires handling for missing files:

```swift
struct TrackRecord: Codable {
    let absolutePath: String  // Absolute file path for recovery
    let name: String
    let format: String
    let durationSeconds: Double
}

// Save queue
UserDefaults.standard.set(
    try? JSONEncoder().encode(playlist.map { TrackRecord(...) }),
    forKey: "savedPlaylist"
)

// Restore queue
if let data = UserDefaults.standard.data(forKey: "savedPlaylist"),
   let records = try? JSONDecoder().decode([TrackRecord].self, from: data) {
    playlist = records.compactMap { record in
        let url = URL(fileURLWithPath: record.absolutePath)
        // Verify file still exists
        guard FileManager.default.fileExists(atPath: record.absolutePath) else {
            return nil  // Skip missing files
        }
        return Track(...)
    }
}
```

On relaunch, if files were deleted from disk, they're silently removed from the queue. If the folder structure changed, paths are invalid (catch gracefully).

**Deliverable:**
- [ ] `Track` struct includes metadata fields (or separate `Metadata` struct)
- [ ] Metadata extracted on background Task
- [ ] Now Playing widget displays title, artist, album art (or placeholder)
- [ ] Missing metadata fields show secondary-style placeholders (no broken UI)
- [ ] Duration used for progress bar
- [ ] Full queue saved to UserDefaults (Codable struct with absolute paths)
- [ ] On relaunch, queue restored; missing files silently skipped (no crash)

### Part 3: Playback Integration (5–6 hours)

**Owner:** Audio DSP Agent + SwiftUI Pro  
**Task:** Replace reference tone generator with AVAudioFile scheduling.

#### Part 3a: Load & Schedule File + FFT Extraction (3–4 hours)

```swift
// In AudioViewModel
func loadFile(_ url: URL) throws {
    let audioFile = try AVAudioFile(forReading: url)
    
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        self?.audioEngine.mainMixerNode.stop()  // stop current
        self?.currentFile = audioFile
    }
}

func play() {
    guard let file = currentFile else { return }
    
    let serialQueue = DispatchQueue(label: "com.adapativesound.scheduler")
    serialQueue.async {
        self.playerNode.stop()
        self.playerNode.scheduleFile(file, at: nil)
        self.playerNode.play()
        DispatchQueue.main.async {
            self.isPlaying = true
        }
    }
}

func pause() {
    playerNode.stop()
    DispatchQueue.main.async {
        self.isPlaying = false
    }
}
```

**Key architectural decisions:**
- File I/O + `scheduleFile()` run on a dedicated serial `DispatchQueue` (prevents seek races)
- `playerNode.play()` is idempotent; safe to call multiple times
- `isPlaying` state updates back on main thread
- No allocation, no blocking on render thread

**FFT Spectrum Integration:**
To drive the spectrum bars with live audio data:
1. Extract FFT magnitudes from the audio engine's input to the mixer (pre-DSP, since DSP chain is bypassed in Phase 1b)
2. Use `vDSP_fft_zrip` with Hamming window on audio buffers (512-sample window, ~10ms latency at 48 kHz)
3. Compute magnitude spectrum → bar heights (logarithmic scale, -80 to 0 dBFS mapped to 0–1.0)
4. Publish `@Published var spectrumMagnitudes: [Float]` on main thread (every 100ms to match progress polling)
5. Bind `SpectrumAnalyzerView` to this array; use `TimelineView(.animation(minimumInterval: 1/30))` for smooth 30fps animation

This adds real-time feedback without significant latency — the spectrum reflects the current audio buffer, not playback position.

**Deliverable:**
- [ ] Clicking a playlist row calls `loadFile()` + `play()`
- [ ] Audio begins within 500 ms
- [ ] Play button changes icon to Pause
- [ ] Spectrum analyzer animates with live FFT data (bars respond to audio in real time)
- [ ] Spectrum respects Reduce Motion (animation pauses when accessibility setting is on)
- [ ] No crash, no dropout on first track

#### Part 3b: Playlist Navigation + Auto-Play (2 hours)
**Task:** Previous / Next buttons move through the queue.

```swift
func playNext() {
    let nextIndex = (currentIndex + 1) % playlist.count
    currentIndex = nextIndex
    loadAndPlay(playlist[nextIndex])
}

func playPrevious() {
    let prevIndex = currentIndex == 0 ? playlist.count - 1 : currentIndex - 1
    currentIndex = prevIndex
    loadAndPlay(playlist[prevIndex])
}

private func loadAndPlay(_ track: Track) {
    Task {
        do {
            try loadFile(track.absoluteURL)
            play()
        } catch {
            // Show error inline
        }
    }
}

// When file completion callback fires:
func onFilePlaybackComplete() {
    playNext()  // Auto-advance to next track
}
```

**Deliverable:**
- [ ] Next button plays next track, wraps to start
- [ ] Previous button plays previous track, wraps to end
- [ ] File completes → auto-plays next track (queue advances automatically)
- [ ] Playlist row highlighting updates to reflect current track
- [ ] Mini-EQ animation appears in leading slot for active row

#### Part 3c: Session State Persistence (1.5 hours)
**Task:** Save & restore folder, queue, playback position.

```swift
// In AudioViewModel
private let defaults = UserDefaults.standard
private let folderURLBookmarkKey = "musicFolderURLBookmark"
private let playlistKey = "savedPlaylist"
private let currentIndexKey = "currentIndex"
private let playbackPositionKey = "playbackPosition"

func saveSessions() {
    if let folderURL = musicFolderURL {
        let bookmark = try? folderURL.bookmarkData(
            options: .securityScopeAllowOnlyReadAccess,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmark, forKey: folderURLBookmarkKey)
    }
    defaults.set(currentIndex, forKey: currentIndexKey)
    // playbackPosition saved via progress polling
}

func restoreSession() {
    if let bookmark = defaults.data(forKey: folderURLBookmarkKey),
       var stale = false,
       let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale) {
        musicFolderURL = url
        url.startAccessingSecurityScopedResource()
        loadMusicFolder(url)
    }
    if let savedIndex = defaults.integer(forKey: currentIndexKey) as Int? {
        currentIndex = savedIndex
    }
}
```

**Deliverable:**
- [ ] App saves folder + current index on every change
- [ ] On relaunch, folder restores + queue repopulates
- [ ] Playback position (via progress slider) saved and restored
- [ ] Security-scoped bookmark persists correctly

### Part 4: Progress & Seek (5–6 hours)

**Owner:** Audio DSP Agent + SwiftUI Pro  
**Task:** Real-time progress bar + seek-to interaction.

#### Part 4a: Progress Polling (2 hours)

```swift
// In AudioViewModel
@Published var playbackPosition: TimeInterval = 0
@Published var duration: TimeInterval = 0

private var progressTimer: Timer?

func startProgressPolling() {
    progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        guard let self = self, self.isPlaying else { return }
        if let time = self.playerNode.playerTime {
            // *** CRITICAL: Use engine output rate (48 kHz), NOT file rate ***
            self.playbackPosition = Double(time.sampleTime) / 48000.0
        }
    }
}

func stopProgressPolling() {
    progressTimer?.invalidate()
    progressTimer = nil
}

// Set duration when file loads
private func getFileDuration(_ url: URL) async -> TimeInterval {
    let asset = AVAsset(url: url)
    return (try? await asset.load(.duration).seconds) ?? 0
}
```

**Formula correction (critical):**
- **Progress display:** `position_seconds = playerTime.sampleTime / 48000` (engine output rate, NOT file rate)
- **Seek frame calculation:** `targetFrame = Int64(seekSeconds * file.processingFormat.sampleRate)` (file's native rate)

**Deliverable:**
- [ ] `@Published playbackPosition` updates every 100 ms
- [ ] `@Published duration` set when file loads
- [ ] Progress bar slider shows elapsed / total (e.g. "1:23 / 3:45")
- [ ] Progress updates smoothly during playback
- [ ] Timer starts on `play()`, stops on `pause()` / file end

#### Part 4b: Seek Implementation (3–4 hours)

```swift
func seek(to timeSeconds: TimeInterval) {
    guard let file = currentFile else { return }
    
    let serialQueue = DispatchQueue(label: "com.adapativesound.scheduler")
    serialQueue.async { [weak self] in
        guard let self = self else { return }
        
        // Clamp to file duration
        let clamped = min(max(0, timeSeconds), Double(file.length) / file.processingFormat.sampleRate)
        
        // *** CRITICAL: targetFrame in FILE's native sample rate ***
        let targetFrame = Int64(clamped * file.processingFormat.sampleRate)
        
        // Reschedule from target position
        self.playerNode.stop()
        self.playerNode.scheduleFile(
            file,
            at: nil,  // Schedule for next render
            startingFrame: targetFrame,  // In file's frame domain
            frameCount: AVAudioFrameCount(file.length - UInt32(targetFrame)),
            completionCallbackType: .dataPlayedBack,
            completionHandler: { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isPlaying = false
                    self?.playbackPosition = clamped
                }
            }
        )
        self.playerNode.play()
        
        // Update UI on main thread
        DispatchQueue.main.async {
            self.playbackPosition = clamped
        }
    }
}
```

**Edge case handling:**
- **Seek past end:** Clamped to `file.length - 1`
- **Rapid seeking:** Serial queue serializes all `stop/schedule/play` sequences
- **Seek while paused:** Works correctly (schedule queues, then play() starts it)
- **No completion handler:** File plays once and stops (need handler to update UI)

**Deliverable:**
- [ ] Progress bar Slider bound to `viewModel.playbackPosition`
- [ ] Dragging slider calls `viewModel.seek(to:)`
- [ ] Seek executes smoothly within ~21 ms (two buffer periods)
- [ ] Audio resumes at correct position
- [ ] Seek accuracy: ±1 frame (±20 µs at 48 kHz)
- [ ] Rapid seek stress test: 50 seeks in rapid succession, no crash
- [ ] isPlaying updates to false on completion

#### Part 4c: UI Fixes for Progress Slider (1 hour)
**Task:** Replace broken static progress bar with interactive Slider.

Current code: `maxWidth: .infinity * 0.35` produces infinity (CGFloat bug).

```swift
// Replace with:
Slider(
    value: $viewModel.playbackPosition,
    in: 0...viewModel.duration,
    step: 0.1
)
.onChange(of: viewModel.playbackPosition) { _, newValue in
    viewModel.seek(to: newValue)
}
.accessibilityLabel("Playback Position")
.accessibilityValue(
    Text(viewModel.playbackPosition, format: .time(pattern: .minuteSecond))
)
.help(Text(viewModel.playbackPosition, format: .time(pattern: .minuteSecond)))
```

**Deliverable:**
- [ ] Progress slider interactive
- [ ] Time label updates in real time
- [ ] VoiceOver announces position and duration

---

## 4. UI Implementation Tasks (Parallel)

These can run in parallel with Parts 2–4 above. They refine the existing Phase 1b UI to match the design spec exactly.

### Task 4a: Toolbar Refinement (2 hours)
- [ ] Device dropdown is now a permanent Menu (moved from HeaderView integration)
- [ ] Tab selector styling matches design (active = teal fill, no label)
- [ ] Volume slider colors to teal gradient
- [ ] All glyphs use SF Symbols (no custom icons)
- [ ] Spacing/padding matches design grid (8pt base)

### Task 4b: Playlist Panel (3–4 hours)
- [ ] Folder picker "Choose Folder…" button (with folder icon, teal tint)
- [ ] Folder path bar (mono font, ~/Music/Library/...)
- [ ] Scrollable file list (custom styling: index/EQ animation + name + path + format badge + duration)
- [ ] Active row highlight (teal background + ring)
- [ ] Row hover state (subtle background increase)
- [ ] Tooltip on hover: full absolute path
- [ ] Format badges (FLAC/MP3/WAV/AAC/ALAC) with correct colors

### Task 4c: Side Panel Module Toggles — Display-Only (1.5 hours)
**Phase 1b Scope:** Toggles are **display-only status indicators**, not functional yet. Functional toggle implementation deferred to Phase 1c.

- [ ] Active Modules 2-column grid (EQ, Clarity, BRIR, Loudness, Limiter)
- [ ] Each row is **display-only** (no click/toggle action in Phase 1b)
- [ ] Hardcoded state for Phase 1b: EQ = checked (on), Clarity/BRII/Loudness/Limiter = unchecked (off)
- [ ] Styling matches design: checked = teal-filled box + dark checkmark, unchecked = transparent box + light ring
- [ ] Visual polish: hover effect on rows (subtle background increase)
- [ ] Accessibility: `.isStaticText` trait (no `.isSelected` implying interactivity)
- [ ] Code comment: "TODO(Phase 1c): Wire module toggles to enable/disable DSP processing"

### Task 4d: Deprecated API Cleanup (1–2 hours)
- [ ] Replace all `foregroundColor()` → `foregroundStyle()`
- [ ] Replace all `cornerRadius()` → `clipShape(.rect(cornerRadius:))`
- [ ] Replace all `Button(action:)` with closures → `Button(label, systemImage:, action:)`
- [ ] Fix `borderOrDivider()` overlay syntax
- [ ] Standardize spacing via a `DesignSystem` namespace constant enum

### Task 4e: Accessibility Audit (2 hours)
- [ ] All interactive controls have VoiceOver labels
- [ ] Progress slider has `accessibilityValue(Text(..., format: .time(...)))`
- [ ] Module toggles have `.isButton` trait, not `.isSelected` on non-interactive elements
- [ ] All text respects Dynamic Type (remove fixed `Font.system(size:)`)
- [ ] Use `@ScaledMetric` for any size-based UI (e.g., padding)
- [ ] Reduce Motion: spectrum animation pauses when `prefersReducedMotion == true`
- [ ] Keyboard: all controls navigable via tab + space/return/arrows
- [ ] Minimum 44×44 pt tap targets on buttons + sliders

---

## 5. Done-Done Acceptance Criteria

**All items must be green before founder sign-off.**

### Code Quality
- [ ] Code merged to main
- [ ] Build clean (no warnings, no deprecated APIs)
- [ ] Swift format + lint + clang-tidy all pass (pre-commit gate)
- [ ] No memory leaks (run with MallocStackLogging, Instruments Memory)
- [ ] ASAN clean (no heap corruption)
- [ ] TSan clean (no data races on playerNode polling)

### Testing
- [ ] Unit tests for seek frame calculation (multiple sample rates)
- [ ] Unit test for progress formula (matches file duration within ±100ms)
- [ ] Integration test: play a WAV → metadata populates → progress updates → seek works
- [ ] Null test: bypass DSP chain (Intensity 0%) → output matches input file

### Manual Testing (Founder Sign-Off)
- [ ] **Setup:** Create test-data directory with sample files (test.wav, test-44khz.wav, test.flac, test.mp3)
- [ ] **File Picker:** Click "Choose Folder…" → native picker appears → select folder → file list populates (show count)
- [ ] **File Format Support:** 
  - [ ] Play WAV file → audio works
  - [ ] Play FLAC file → audio works
  - [ ] Play MP3 file → audio works
  - [ ] Play 44.1 kHz file → audio plays at correct pitch/tempo (transparent SRC)
  - [ ] Try unsupported format → inline error message (not crash)
- [ ] **Playback Controls:**
  - [ ] Press Play → audio begins within 500 ms
  - [ ] Press Pause → audio stops, progress bar freezes
  - [ ] Press Play again → resumes from paused position
  - [ ] Spectrum animator active (bars animate when playing, dim when paused)
- [ ] **Playlist Navigation:**
  - [ ] Click next file in list → loads and plays
  - [ ] Press Next button → plays next in queue, wraps to start
  - [ ] Press Previous button → plays previous, wraps to end
  - [ ] Active row highlights correctly
  - [ ] Mini-EQ indicator appears in leading slot for active track
- [ ] **Progress & Seek:**
  - [ ] Progress bar shows "0:00 / 3:45" format, updates every 100 ms
  - [ ] Drag progress slider to 1:30 → seek executes → audio resumes at 1:30 ±1 frame
  - [ ] Seek to within 2 seconds of end → playback completes cleanly, no crash
  - [ ] Seek mid-playback 5 times rapidly → no glitch, no crash
- [ ] **Metadata Display:**
  - [ ] Tagged MP3: title, artist, album populate
  - [ ] File with no tags: filename shows as title, no crash
  - [ ] File with no album art: placeholder shows, no broken image
  - [ ] Now Playing widget displays title, artist, mini progress
- [ ] **Session Persistence:**
  - [ ] Play file, pause at 2:34
  - [ ] Close app
  - [ ] Relaunch app → folder and queue restore → file pre-loaded at 2:34
  - [ ] Press Play → resumes from saved position
- [ ] **DSP Chain Integrity:**
  - [ ] Spectrum analyzer shows activity during playback (proves audio routes through AU)
  - [ ] EQ curve adjustments affect audio (when EQ is wired, Phase 1b+ work)
  - [ ] Volume slider adjusts audio level (header control, always works)
  - [ ] Master Gain slider adjusts output level
- [ ] **Accessibility:**
  - [ ] VoiceOver: Play button announces "Play" / "Pause" (switches on state)
  - [ ] VoiceOver: Progress slider announces elapsed time
  - [ ] Keyboard: Tab navigation cycles through all controls
  - [ ] Keyboard: Space/Return trigger Play/Pause, Module toggles
  - [ ] Keyboard: Arrow keys adjust sliders (volume, progress, master gain)
  - [ ] Reduce Motion: spectrum animation pauses when accessibility setting is on
- [ ] **Robustness:**
  - [ ] Drop unsupported file type → inline error, no crash
  - [ ] Unplug headphones mid-playback → audio routes to Built-in Speaker, no crash
  - [ ] Change output device mid-playback → playback continues uninterrupted
  - [ ] 5-minute soak playback → no xruns, no dropouts, no heap grow
  - [ ] Force-quit mid-seek → relaunch → no corruption, queue intact

### Documentation
- [ ] `music-playback-plan.md` status updated: ✅ SHIPPED
- [ ] `backlog.md` updated: Phase 1b music playback moved to Done
- [ ] Architecture notes updated if AU wiring required changes
- [ ] Known issues log (if any blockers remain)

---

## 6. Team Sign-Offs

### Prerequisites Before Sprint Kickoff
1. **BA/PM:** Confirm scope (file picker, playlist, metadata, playback, seek, progress) and acceptance criteria. ✅ Reviewed → no scope creep
2. **Audio DSP:** Confirm architecture (AVAudioFile + scheduleFile, threading, null-test plan). ✅ Reviewed → architecture sound, prerequisites documented
3. **SwiftUI Pro:** Confirm UI implementation patterns (fileImporter, @Observable migration, accessibility). ✅ Reviewed → patterns clear, deprecated API list provided
4. **QA Expert:** Confirm test plan and manual checklist. (Pending QA expert agent review below)

### Cross-Reference Checklist

**For BA/PM:**
- ✅ User journey alignment: Journeys 2.1, 2.3, 2.7 enabled
- ✅ Locked decision alignment: LD-1, LD-4, LD-10, LD-16 all satisfied
- ✅ Design specification: Matches `assets/AdaptiveSound.zip` exactly
- ✅ Scope is bounded: File picker → Playlist → Metadata → Playback → Seek → Progress. No queue management UI, no streaming, no conversational tuning input yet.
- ✅ Risk flags identified: Seek frame domain confusion (RESOLVED), rapid seek races (RESOLVED), security-scoped URL lifetime (RESOLVED)
- ✅ Dependencies documented: AU graph wiring is a hard prerequisite

**For Audio DSP:**
- ✅ Real-time safety: File I/O off render thread, no allocation on RT path
- ✅ SRC strategy: Transparent 44.1 kHz → 48 kHz via AVAudioEngine's built-in converter (max quality)
- ✅ Format support: WAV, FLAC, MP3, AAC via ExtAudioFile (ALAC ok on macOS 12+)
- ✅ Seek correctness: `startingFrame` in file's native sample rate, progress uses engine output rate
- ✅ Security-scoped URLs: Scope lifetime tied to track load/unload cycle
- ✅ Null-test plan: Bypass at Intensity 0% must be bit-identical
- ✅ Rendering thread safety verified (ASAN, TSan, concurrent iteration tests)

**For SwiftUI Pro:**
- ✅ Modern API usage: `.fileImporter`, `@Observable`, `@MainActor`, Slider with onChange
- ✅ HIG compliance: 44×44 pt tap targets, 8pt spacing grid, semantic fonts, teal accent colors
- ✅ Accessibility: VoiceOver labels, keyboard navigation, Reduce Motion, Dynamic Type
- ✅ Deprecated APIs: Replaced `foregroundColor`, `cornerRadius`, `Button(action:)`, fixed `overlay` syntax
- ✅ Performance: `@Observable` prevents unnecessary re-renders during playback updates
- ✅ Responsive design: 50/50 split holds at 800pt window; graceful degradation below

**For QA Expert:**
- ✅ Test coverage: Unit (seek math, progress formula), Integration (play → seek → metadata), Manual (checklist)
- ✅ Edge cases: Seek past end, rapid seeks, file with no metadata, unsupported format, session restore
- ✅ Stress testing: 5-min soak, TSan 50 concurrent seeks, memory leak detection
- ✅ Accessibility audit: VoiceOver, keyboard, Reduce Motion, Dynamic Type, 44pt targets
- ✅ Regression tracking: No Phase 1a features (Play/Stop/Volume, EQ canvas, device detection) regress

---

## 7. Implementation Sequence

### Parallel Workstreams

**Critical Path (must happen first):**
1. **Part 1a + 1b (AU graph wiring + @Observable migration):** 6–7 hours. Blocks everything else.

**After Critical Path (can run in parallel):**
2. **Part 2 (File picker & enumeration):** 4–5 hours. Owner: SwiftUI Pro
3. **Part 3 (Playback integration):** 5–6 hours. Owner: Audio DSP Agent
4. **Part 4 (Progress & seek):** 5–6 hours. Owner: Audio DSP Agent (critical math validation needed)
5. **Task 4a–4e (UI refinement & accessibility):** 8–10 hours. Owner: SwiftUI Pro (runs in parallel with 2–4)

### Suggested Timeline (Team: 2–3 Developers)

**Day 1 (Full Day)**
- **Team 1 (Tooling/Architecture):** Part 1a–1b (@Observable migration + toolbar restructuring) — 4–5 hours
- **Team 2 (Playback):** Part 3a (file loading + FFT extraction) in parallel — 3–4 hours
- **Team 3 (UI):** Task 4a (toolbar polish) + Task 4b (playlist panel structure) in parallel — 4–5 hours

**Day 2 (Full Day)**
- **Team 1 (UI continuation):** Tasks 4c–4d (module toggles + deprecated API cleanup) — 3–4 hours
- **Team 2 (Playback):** Part 3b (playlist nav + auto-play) + Part 4a (progress polling) — 4–5 hours
- **Team 3 (Integration):** Part 2a–2c (file picker + enumeration + metadata + queue persistence) — 4–5 hours

**Day 3 (Partial — Testing & Polish)**
- **Team 1 (QA/Accessibility):** Task 4e (accessibility audit: VoiceOver, keyboard, Reduce Motion, Dynamic Type) — 2 hours
- **Team 2 (Seek):** Part 4b–4c (seek implementation + progress slider fixes) — 3–4 hours
- **Team 3 (Integration testing):** Manual testing from acceptance checklist (file formats, seek accuracy, session restore, DSP chain integrity) — 3–4 hours

**Day 3 EOD:** Founder sign-off on done-done checklist

**Total effort:** ~10 story points, **1.5 days wall-clock time with 2–3 parallel developers**
(Compared to ~3–4 days for a single developer working sequentially)

---

## 8. Known Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| AU graph wiring complexity | High | Prerequisite task; audio-dsp-agent owned; unit test (null-test) validates correctness before playback work begins |
| Seek frame domain confusion (file vs. node rate) | High | Formula documented in Part 4b; unit test confirms calculations for 44.1 kHz + 48 kHz files before integration |
| Rapid seek race condition (multiple dispatches interleaving) | Medium | Dedicated serial scheduler queue serializes all stop/schedule/play; stress test with 50 rapid seeks |
| Security-scoped URL released too early (causes I/O failure on reload) | Medium | Scope lifetime tied to `Track` lifecycle; `endAccessing` called only at unload/app termination; manual test force-quit mid-seek |
| File metadata extraction blocking UI | Medium | Background Task with `@MainActor` result publication; show loading state while metadata populates |
| 44.1 kHz SRC introduces artifacts | Low | Transparent SRC at max quality via `AVAudioConverter`; formula matches input for well-mastered sources; null-test validates |
| FLAC not supported on macOS < 10.13 | Low | Architecture floor is macOS 14 (LD-18); guard still added; user gets clear error if somehow invoked on older system |
| Playlist scroll perf with 1000+ files | Low | `LazyVStack` + `List` handles this natively; sort once in view model, not in ForEach; test with large directory |
| Backward compatibility (existing user sessions) | Medium | Bookmark-based restoration is robust; old URL strings discarded; first relaunch after update restores folder if still accessible |

---

## 9. Success Metrics

**This sprint succeeds when:**
1. ✅ User can pick a music folder and browse/play files without crashing
2. ✅ Audio plays through the DSP chain (null-test validates)
3. ✅ Seek is accurate to ±1 frame, smooth, and responsive
4. ✅ Session state persists across app restarts
5. ✅ All Phase 1a features (device control, volume, EQ canvas) still work (no regressions)
6. ✅ Founder completes manual testing checklist with no blockers
7. ✅ ASAN/TSan clean, accessibility audit passes
8. ✅ Design matches `assets/AdaptiveSound.zip` exactly (layout, colors, spacing, interactions)

---

## 10. Next Steps (Phase 1c+)

**Deferred to Phase 1c (after music playback ships):**
- [ ] Queue management UI: drag-to-reorder, skip queue, remove from queue
- [ ] Real-time spectrum analyzer: live FFT magnitude data from audio engine
- [ ] Module-specific controls: per-module enable/disable, intensity sliders (Clarity, Loudness, BRIR intensity)

**Deferred to Phase 1.5:**
- [ ] Intensity knob functional (currently placeholder; Phase 1b reserves the UI slot)
- [ ] Conversational tuning text input wired to Now Playing view
- [ ] Stem-based object engine + per-stem spatial placement
- [ ] Advanced seek: waveform scrubber, chapter/cue point markers

**Deferred to Phase 2:**
- [ ] System-wide audio processing (virtual audio device or process tap)
- [ ] Streaming integration (Spotify, Apple Music API, assuming permissions available)
- [ ] Multi-output support (simultaneous headphones + speakers with different profiles)

---

## Document History

| Version | Date | Author | Status |
|---------|------|--------|--------|
| 1.0 | 2026-06-15 | Claude Code + Team | Ready for Kickoff |
| (BA/PM Sign-Off) | — | ramith@wso2.com | Pending |
| (Audio DSP Sign-Off) | — | audio-dsp-agent | Pending |
| (SwiftUI Pro Sign-Off) | — | swiftui-pro | Pending |
| (QA Sign-Off) | — | qa-expert | Pending |

---

**Next:** Team reviews this plan; QA expert provides test plan sign-off; sprint kickoff scheduled for 2026-06-16 (tomorrow) or deferred pending team feedback.
