import SwiftUI

/// Every optional feature has its own switch, and none of them is required for basic
/// playback (spec §29).
struct FeatureControlCenter: View {
    @Environment(PlaybackEngine.self) private var playback
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    private var state: PlaybackState { playback.state }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playback settings") {
                    Toggle("Metronome", isOn: binding(state.metronomeEnabled) { playback.setMetronome(enabled: $0) })
                    Toggle("Count-in", isOn: binding(state.countInEnabled) { playback.setCountIn(enabled: $0) })
                    Toggle("Backtrack", isOn: binding(state.backtrackEnabled) { playback.setBacktrack(enabled: $0) })
                    Toggle("Auto-scroll", isOn: binding(state.autoScrollEnabled) { playback.setAutoScroll(enabled: $0) })
                    Toggle("Loop", isOn: binding(state.loopEnabled) { playback.setLoopEnabled($0) })
                    Toggle("Chord display", isOn: binding(state.chordDisplayEnabled) { playback.setChordDisplay(enabled: $0) })
                }

                Section("Metronome") {
                    HStack {
                        Text("BPM")
                        Spacer()
                        Text("\(Int(state.effectiveTempo))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Volume")
                        Slider(value: binding(Double(state.metronomeVolume)) { playback.setMetronomeVolume(Float($0)) }, in: 0...1)
                        Text("\(Int(state.metronomeVolume * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                    Picker("Subdivision", selection: binding(state.metronomeSubdivision) { playback.setMetronomeSubdivision($0) }) {
                        ForEach(MetronomeSubdivision.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Backtrack") {
                    Picker("Source", selection: binding(state.backtrackSource) { playback.setBacktrackSource($0) }) {
                        ForEach(BacktrackSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(playback.document?.hasOriginalAudio != true)

                    if playback.document?.hasOriginalAudio != true {
                        Label("No original audio is licensed for this tab — the synthesized backtrack is used.",
                              systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Master volume")
                        Slider(value: binding(Double(state.masterVolume)) { playback.setMasterVolume(Float($0)) }, in: 0...1)
                    }
                }

                Section("Loop") {
                    if let loop = state.loop, loop.isValid {
                        HStack {
                            Text("Region")
                            Spacer()
                            Text("bar \(barNumber(loop.startBeat)) – \(barNumber(loop.endBeat))")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Button("Set loop start here") { playback.setLoopStart() }
                    Button("Set loop end here") { playback.setLoopEnd() }
                    Button("Clear loop", role: .destructive) { playback.clearLoop() }
                }

                Section {
                    Button("Save these as my defaults") { appState.capturePlaybackDefaults() }
                } footer: {
                    Text("New songs will open with the toggles you have set here.")
                }
            }
            .navigationTitle("Feature Control")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func barNumber(_ beat: Double) -> Int {
        Int(beat / max(1, playback.layout.timeSignature.barLengthInBeats)) + 1
    }

    private func binding<Value>(_ value: Value, set: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(get: { value }, set: set)
    }
}
