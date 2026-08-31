import SwiftUI

/// Per-track mute, solo, volume and pan (spec §15–§17).
struct TrackMixerView: View {
    @Environment(PlaybackEngine.self) private var playback

    var showsVolumeSliders: Bool = true

    private var state: PlaybackState { playback.state }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Tracks")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.hasSoloedTrack {
                    Button("Clear solo") { playback.clearSolos() }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }

            ForEach(state.tracks) { track in
                TrackRow(track: track,
                         isSelected: playback.selectedTrackId == track.id,
                         isAudible: state.isAudible(track),
                         showsVolume: showsVolumeSliders)
            }
        }
    }
}

private struct TrackRow: View {
    @Environment(PlaybackEngine.self) private var playback

    let track: TrackPlaybackState
    let isSelected: Bool
    let isAudible: Bool
    let showsVolume: Bool

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                Button {
                    playback.selectTrack(track.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: track.instrument.symbolName)
                            .frame(width: 22)
                            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(track.name)
                            .font(.subheadline)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundStyle(isAudible ? .primary : .secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows this track's tablature")

                Button {
                    playback.toggleSolo(trackId: track.id)
                } label: {
                    Text("S")
                        .font(.caption.weight(.bold))
                        .frame(width: 26, height: 26)
                        .background(track.isSolo ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .foregroundStyle(track.isSolo ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(track.name) solo")
                .accessibilityValue(track.isSolo ? "on" : "off")

                Button {
                    playback.toggleMute(trackId: track.id)
                } label: {
                    Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.caption)
                        .frame(width: 26, height: 26)
                        .background(track.isMuted ? AnyShapeStyle(Color.red.opacity(0.85)) : AnyShapeStyle(.quaternary),
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .foregroundStyle(track.isMuted ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(track.name) mute")
                .accessibilityValue(track.isMuted ? "muted" : "audible")
            }

            if showsVolume {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.tertiary)
                    Slider(value: Binding(
                        get: { Double(track.volume) },
                        set: { playback.setVolume(Float($0), trackId: track.id) }
                    ), in: 0...1)
                    .disabled(track.isMuted)
                    Text("\(Int(track.volume * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(track.name) volume")
            }
        }
        .padding(.vertical, 2)
        .opacity(isAudible ? 1 : 0.55)
    }
}
