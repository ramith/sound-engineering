import DesignTokenKit
import SwiftUI

// MARK: - Now Playing Tab View (S10.7 PR 5 — the 8a restructure)

/// The 8a layout (design §5): a hero row (title/artist/badges left, the analyzer LENS right,
/// vertically centered against each other) over a queue-flex + fixed-260 inspector split.
/// The ambient glow field paints behind everything.
///
/// SCROLLING ARCHITECTURE (§5, mandated): NO outer ScrollView — an unbounded height proposal
/// would materialize every queue row (virtualization dead) and break jump-to-now-playing.
/// The hero hugs its intrinsic height; the queue scrolls internally; the inspector scrolls
/// its content inside its panel chrome. Near the 880×640 minimum the inspector is EXPECTED
/// to scroll — that's the design, not a defect.
struct NowPlayingTabView: View {
    @Environment(AudioViewModel.self) private var viewModel
    @Environment(NowPlayingController.self) private var nowPlaying
    /// D8 (PR 7): the sampler owns the per-track clamped palette the field renders.
    @State private var glowSampler = ArtworkGlowSampler()

    var body: some View {
        VStack(spacing: 0) {
            HeroRow()
                .padding(.horizontal, CGFloat(NowPlayingLayout.contentInset))
                .padding(.top, CGFloat(NowPlayingLayout.contentInset))
                .padding(.bottom, 12)

            HStack(alignment: .top, spacing: CGFloat(NowPlayingLayout.regionGap)) {
                PlaylistView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                InspectorColumn()
            }
            .padding(.horizontal, CGFloat(NowPlayingLayout.contentInset))
            .padding(.bottom, CGFloat(NowPlayingLayout.contentInset))
        }
        // The ambient glow field (PR 2): window base + the three 8a glows behind the whole
        // tab — art-tinted per D8 (PR 7). Other tabs keep the plain base until S10.8 (D1).
        .background { GlowField(sampledPalette: glowSampler.palette) }
        // D8: re-sample when the artwork resolves. `currentArtwork` is token-guarded — it
        // reads nil during the resolve gap right after a track change, which resets the
        // field to brand until the new art lands (the designed fallback, §3.3). `initial:
        // true` covers mounting the tab with a track already playing (cache makes it cheap).
        .onChange(of: nowPlaying.currentArtwork, initial: true) { _, artwork in
            glowSampler.update(artwork: artwork, trackKey: currentTrackKey)
        }
    }

    /// Cache identity for the current track (same file ⇒ same art ⇒ same palette). Keyed by
    /// the file's absolute URL (`AudioFile.id`) — NEVER `relativePath`, which the queue
    /// adapter leaves empty for every track (review BLOCKER: one shared "" key served the
    /// first album's palette to the whole session).
    private var currentTrackKey: String? {
        guard let index = viewModel.selectedTrackIndex,
              index < viewModel.playlist.count else { return nil }
        return viewModel.playlist[index].id.absoluteString
    }
}

// MARK: - Hero Row

/// Hero-left (title/artist/badges) + the lens (D6: flexing 400→560 × 122), CENTERED against
/// each other (§5: no lower-left void — the transport-less hero's composition). Beyond the
/// lens's max width, whitespace between the two is legitimate hero negative space.
private struct HeroRow: View {
    @Environment(AudioViewModel.self) private var viewModel
    @FocusState private var lensFocused: Bool
    @State private var lensHovered = false

    var body: some View {
        HStack(alignment: .center, spacing: CGFloat(NowPlayingLayout.regionGap)) {
            HeroBand()
                .frame(maxWidth: .infinity, alignment: .leading)

            lens
        }
    }

    /// The analyzer lens carries the double-click→Monitoring affordance (§3.4): hover rim
    /// brighten + pointer, keyboard focus + Return, and an exposed accessibility element
    /// with a named action — the affordance reaches everyone, not just sighted pointer
    /// users (the fool's replacement of the old "tab picker exists" position).
    private var lens: some View {
        SpectrumAnalyzerView()
            .frame(minWidth: CGFloat(NowPlayingLayout.lensMinWidth),
                   maxWidth: CGFloat(NowPlayingLayout.lensMaxWidth),
                   minHeight: CGFloat(NowPlayingLayout.lensHeight),
                   maxHeight: CGFloat(NowPlayingLayout.lensHeight))
            .overlay {
                if lensHovered || lensFocused {
                    RoundedRectangle(cornerRadius: CGFloat(GlassDecor.lensRadius), style: .continuous)
                        .strokeBorder(DesignSystem.Color.accent.opacity(0.35), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: CGFloat(GlassDecor.lensRadius),
                                           style: .continuous))
            .onTapGesture(count: 2) { viewModel.selectedTab = .monitoring }
            .onHover { lensHovered = $0 }
            .focusable()
            .focused($lensFocused)
            // Return only — NOT Space: the transport's Space key-equivalent (Controls menu)
            // is matched before any focused view's `onKeyPress`, so a Space handler here
            // would be dead code (the same audit that removed the queue list's).
            .onKeyPress(.return) {
                viewModel.selectedTab = .monitoring
                return .handled
            }
            .help("Double-click to open Monitoring")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Spectrum analyzer")
            // Default action (VO-press works directly) + the named action in the rotor.
            .accessibilityAction { viewModel.selectedTab = .monitoring }
            .accessibilityAction(named: "Open Monitoring") { viewModel.selectedTab = .monitoring }
    }
}
