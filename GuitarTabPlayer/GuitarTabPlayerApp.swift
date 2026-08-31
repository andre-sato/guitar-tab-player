import SwiftUI
import SwiftData

@main
struct GuitarTabPlayerApp: App {

    private let container: ModelContainer
    @State private var appState: AppState

    init() {
        let container = SwiftDataContainer.makeShared()
        self.container = container
        _appState = State(initialValue: AppState(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(appState.playback)
        }
        .modelContainer(container)
    }
}
