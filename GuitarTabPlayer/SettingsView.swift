import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        NavigationStack {
            Form {
                Section("Defaults for new songs") {
                    Toggle("Metronome", isOn: $state.preferences.metronomeEnabled)
                    Toggle("Count-in", isOn: $state.preferences.countInEnabled)
                    Toggle("Backtrack", isOn: $state.preferences.backtrackEnabled)
                    Toggle("Auto-scroll", isOn: $state.preferences.autoScrollEnabled)
                    Toggle("Chord display", isOn: $state.preferences.chordDisplayEnabled)
                    Toggle("Resume where I stopped", isOn: $state.preferences.resumeFromLastPosition)
                }

                Section("Default speed") {
                    Picker("Speed", selection: $state.preferences.defaultSpeed) {
                        ForEach(PlaybackControlsView.speedPresets, id: \.self) { value in
                            Text("\(Int(value * 100))%").tag(value)
                        }
                    }
                }

                Section("Metronome") {
                    Picker("Subdivision", selection: $state.preferences.metronomeSubdivision) {
                        ForEach(MetronomeSubdivision.allCases) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                    HStack {
                        Text("Volume")
                        Slider(value: Binding(
                            get: { Double(state.preferences.metronomeVolume) },
                            set: { state.preferences.metronomeVolume = Float($0) }), in: 0...1)
                    }
                }

                Section("Catalogs") {
                    ForEach(appState.searchService.providers, id: \.id) { provider in
                        HStack {
                            Label(provider.name, systemImage: "square.stack.3d.up")
                            Spacer()
                            Text(provider.id).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("The app only reads catalogs it is licensed to use, plus tabs you import yourself.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.shortVersionString)
                    LabeledContent("Build", value: Bundle.main.buildString)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

extension Bundle {
    var shortVersionString: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    var buildString: String {
        (infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }
}

#Preview {
    PreviewFactory.wrap { SettingsView() }
}
