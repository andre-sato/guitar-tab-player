import SwiftUI

/// Transport, scrubber, speed and key (spec §28 "Playback" area).
struct PlaybackControlsView: View {
    @Environment(PlaybackEngine.self) private var playback

    private var state: PlaybackState { playback.state }

    static let speedPresets: [Double] = [0.5, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5]

    var body: some View {
        VStack(spacing: 12) {
            scrubber
            transport
            HStack(spacing: 12) {
                speedControl
                Divider().frame(height: 34)
                keyControl
            }
            quickToggles
        }
    }

    // MARK: - Scrubber

    /// Kept out of the string interpolation below: nesting a ternary, a generic `max` and an
    /// `Int(_:)` conversion inside one interpolated expression is a classic type-checker stall.
    private var measureNumber: Int {
        guard state.totalBeats > 0 else { return 1 }
        let bar = max(1.0, playback.layout.timeSignature.barLengthInBeats)
        return Int(state.currentBeat / bar) + 1
    }

    private var scrubber: some View {
        VStack(spacing: 2) {
            Slider(value: Binding(
                get: { state.currentBeat },
                set: { playback.seek(toBeat: $0) }
            ), in: 0...max(1, state.totalBeats))
            .accessibilityLabel("Position")
            .accessibilityValue(state.currentTime.clockString)

            HStack {
                Text(state.currentTime.clockString)
                Spacer()
                Text("Measure \(measureNumber)")
                Spacer()
                Text(state.totalTime.clockString)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 26) {
            Button { playback.skip(measures: -1) } label: {
                Image(systemName: "backward.fill").font(.title2)
            }
            .accessibilityLabel("Previous measure")

            Button { playback.stop() } label: {
                Image(systemName: "stop.fill").font(.title3)
            }
            .accessibilityLabel("Stop")

            ZStack {
                Button { playback.togglePlayPause() } label: {
                    Image(systemName: state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 54))
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel(state.isPlaying ? "Pause" : "Play")

                if state.isCountingIn {
                    Text(MetronomeEngine.countInDisplayNumber(beatsRemaining: state.countInBeatsRemaining))
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(14)
                        .background(Circle().fill(Color.accentColor))
                        .transition(.scale.combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(.easeOut(duration: 0.12), value: state.countInBeatsRemaining)

            Button { playback.setLoopEnabled(!state.loopEnabled) } label: {
                Image(systemName: state.loopEnabled ? "repeat.circle.fill" : "repeat")
                    .font(.title3)
                    .foregroundStyle(state.loopEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .accessibilityLabel("Loop")
            .accessibilityValue(state.loopEnabled ? "on" : "off")

            Button { playback.skip(measures: 1) } label: {
                Image(systemName: "forward.fill").font(.title2)
            }
            .accessibilityLabel("Next measure")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    // MARK: - Speed

    private var speedControl: some View {
        VStack(spacing: 2) {
            Text("Speed").font(.caption2).foregroundStyle(.secondary)
            Menu {
                ForEach(Self.speedPresets, id: \.self) { value in
                    Button {
                        playback.setSpeed(value)
                    } label: {
                        if abs(value - state.speed) < 0.001 {
                            Label("\(Int(value * 100))%", systemImage: "checkmark")
                        } else {
                            Text("\(Int(value * 100))%")
                        }
                    }
                }
            } label: {
                Text("\(Int(state.speed * 100))%")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 62)
                    .padding(.vertical, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .accessibilityLabel("Playback speed")
            .accessibilityValue("\(Int(state.speed * 100)) percent")
        }
    }

    // MARK: - Key

    private var keyControl: some View {
        VStack(spacing: 2) {
            Text("Key").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Button { playback.setTranspose(state.transpose - 1) } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .accessibilityLabel("Transpose down")

                VStack(spacing: 0) {
                    Text(playback.document?.key.displayName ?? "—")
                        .font(.headline)
                    if state.transpose != 0 {
                        Text(state.transpose > 0 ? "+\(state.transpose)" : "\(state.transpose)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 44)

                Button { playback.setTranspose(state.transpose + 1) } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Transpose up")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .font(.title3)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Quick toggles

    private var quickToggles: some View {
        HStack(spacing: 8) {
            ToggleChip(title: "Metronome", systemImage: "metronome", isOn: state.metronomeEnabled) {
                playback.setMetronome(enabled: !state.metronomeEnabled)
            }
            ToggleChip(title: "Count-in", systemImage: "3.circle", isOn: state.countInEnabled) {
                playback.setCountIn(enabled: !state.countInEnabled)
            }
            ToggleChip(title: "Backtrack", systemImage: "waveform", isOn: state.backtrackEnabled) {
                playback.setBacktrack(enabled: !state.backtrackEnabled)
            }
        }
    }
}

struct ToggleChip: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).imageScale(.small)
                Text(title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                        in: Capsule())
            .foregroundStyle(isOn ? Color.white : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "on" : "off")
        .accessibilityAddTraits(.isButton)
    }
}
