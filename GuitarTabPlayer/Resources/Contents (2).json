import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            SearchView()
                .tabItem { Label(AppState.Tab.search.title, systemImage: AppState.Tab.search.symbolName) }
                .tag(AppState.Tab.search)

            LibraryView()
                .tabItem { Label(AppState.Tab.library.title, systemImage: AppState.Tab.library.symbolName) }
                .tag(AppState.Tab.library)

            TabPlayerView()
                .tabItem { Label(AppState.Tab.player.title, systemImage: AppState.Tab.player.symbolName) }
                .tag(AppState.Tab.player)

            SettingsView()
                .tabItem { Label(AppState.Tab.settings.title, systemImage: AppState.Tab.settings.symbolName) }
                .tag(AppState.Tab.settings)
        }
        .overlay(alignment: .top) {
            if appState.isLoadingTab {
                LoadingBanner(text: "Loading tab…")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isLoadingTab)
        .alert("Resume?", isPresented: Binding(
            get: { appState.resumePrompt != nil },
            set: { if !$0 { appState.declineResume() } }
        ), presenting: appState.resumePrompt) { prompt in
            Button("Resume from \(prompt.timeLabel)") { appState.acceptResume() }
            Button("Start over", role: .cancel) { appState.declineResume() }
        } message: { prompt in
            Text("\(prompt.title) — you stopped at \(prompt.timeLabel).")
        }
    }
}

struct LoadingBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text).font(.subheadline)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    PreviewFactory.root()
}
