import SwiftUI

struct TabPlayerView: View {
    @Environment(AppState.self) private var appState
    @Environment(PlaybackEngine.self) private var playback
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var showFeatureCenter = false
    @State private var zoom: Double = 1.0
    /// Zoom committed at the end of the last pinch. `MagnifyGesture.magnification` restarts at
    /// 1.0 on every gesture, so without this each new pinch would snap back to 100%.
    @State private var zoomBase: Double = 1.0

    private var state: PlaybackState { playback.state }
    private var isWide: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            Group {
                if playback.document == nil {
                    ContentUnavailableView(
                        "No tab open",
                        systemImage: "music.note.list",
                        description: Text("Pick a song from Search or your Library to start practising."))
                } else if isWide {
                    wideLayout
                } else {
                    compactLayout
                }
            }
            .navigationTitle(playback.document?.title ?? "Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showFeatureCenter) { FeatureControlCenter() }
            .playerKeyboardShortcuts()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                playback.pause()
                appState.persistPracticeState()
            }
        }
        .onDisappear { appState.persistPracticeState() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(playback.document?.title ?? "").font(.headline).lineLimit(1)
                Text(playback.document?.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showFeatureCenter = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Feature control center")
        }
    }

    // MARK: - Layouts

    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 14) {
                statusStrip
                tabSheet
                TrackMixerView(showsVolumeSliders: true)
                    .padding(.horizontal)
                Divider()
                PlaybackControlsView()
                    .padding(.horizontal)
                    .padding(.bottom, 12)
            }
        }
    }

    private var wideLayout: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 10) {
                    statusStrip
                    tabSheet
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                Divider()

                ScrollView {
                    TrackMixerView(showsVolumeSliders: true)
                        .padding()
                }
                .frame(width: 320)
            }
            Divider()
            PlaybackControlsView()
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: 760)
        }
    }

    // MARK: - Pieces

    private var tabSheet: some View {
        TabSheetView(layout: playback.layout,
                     currentBeat: state.currentBeat,
                     isPlaying: state.isPlaying,
                     autoScroll: state.autoScrollEnabled,
                     showChords: state.chordDisplayEnabled,
                     loop: state.loop,
                     loopEnabled: state.loopEnabled,
                     metrics: TabMetrics.default.scaled(by: zoom),
                     seekGeneration: playback.seekGeneration,
                     onSeek: { playback.seek(toBeat: $0) },
                     onUserScrolled: { playback.setAutoScroll(enabled: false) })
        .background(TabPalette(colorScheme: colorScheme).background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.quaternary))
        .padding(.horizontal, 12)
        .gesture(MagnifyGesture()
            .onChanged { value in zoom = min(2.0, max(0.6, zoomBase * value.magnification)) }
            .onEnded { _ in zoomBase = zoom })
    }

    private var statusStrip: some View {
        VStack(spacing: 6) {
            if let message = playback.lastError {
                Label(message, systemImage: "speaker.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }
            if playback.transpositionIsApproximate {
                Label("Some notes were moved to another string to stay playable.",
                      systemImage: "arrow.triangle.branch")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
            }

            HStack(spacing: 10) {
                if let section = playback.activeSection {
                    Text(section.name.uppercased())
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
                if !state.autoScrollEnabled {
                    Button {
                        playback.setAutoScroll(enabled: true)
                        playback.seek(toBeat: state.currentBeat)
                    } label: {
                        Label("Follow", systemImage: "scope")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Re-centres the tablature on the playhead and resumes auto-scroll.")
                }
                if state.chordDisplayEnabled, let chord = playback.activeChord {
                    Text(chord.symbol(preferFlats: playback.layout.prefersFlats))
                        .font(.title3.weight(.bold))
                        .contentTransition(.numericText())
                }
                Spacer()
                Text("\(Int(state.effectiveTempo)) BPM · \(playback.layout.timeSignature.displayName)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .animation(.easeOut(duration: 0.15), value: playback.activeChord)
        }
    }
}

#Preview {
    PreviewFactory.wrap { TabPlayerView() }
}
