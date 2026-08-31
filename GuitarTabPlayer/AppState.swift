import Foundation
import Observation
import SwiftData

/// Composition root: builds the provider registry, the services and the playback engine,
/// and holds whatever navigation state the whole app shares.
@Observable
@MainActor
final class AppState {

    enum Tab: String, CaseIterable, Identifiable {
        case search, library, player, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .search: return "Search"
            case .library: return "Library"
            case .player: return "Player"
            case .settings: return "Settings"
            }
        }
        var symbolName: String {
            switch self {
            case .search: return "magnifyingglass"
            case .library: return "books.vertical"
            case .player: return "music.note.list"
            case .settings: return "gearshape"
            }
        }
    }

    let registry: ProviderRegistry
    let searchService: SearchService
    let tabService: TabService
    let libraryService: LibraryService
    let downloadService: DownloadService
    let playback: PlaybackEngine

    var selectedTab: Tab = .search
    var preferences: UserPreferences {
        didSet { libraryService.update(preferences: preferences) }
    }

    private(set) var openEntry: LibraryEntry?
    private(set) var isLoadingTab = false
    var loadError: String?
    var resumePrompt: ResumePrompt?

    struct ResumePrompt: Identifiable {
        var id: String { entryId }
        var entryId: String
        var title: String
        var snapshot: PracticeSnapshot
        var timeLabel: String
    }

    init(context: ModelContext) {
        let registry = ProviderRegistry.makeDefault()
        self.registry = registry
        self.searchService = SearchService(registry: registry)
        let tabService = TabService(registry: registry)
        self.tabService = tabService
        let library = LibraryService(context: context)
        self.libraryService = library
        self.downloadService = DownloadService(tabService: tabService, library: library)
        self.playback = PlaybackEngine()
        self.preferences = library.preferences()

        playback.onPlaybackFinished = { [weak self] in
            self?.persistPracticeState()
        }
    }

    // MARK: - Opening a tab

    func open(result: TabSearchResult, autoplay: Bool = false) async {
        isLoadingTab = true
        loadError = nil

        let entry = libraryService.addIfNeeded(result)
        openEntry = entry

        do {
            let document = try await tabService.document(
                for: result, offlineData: downloadService.offlineData(for: entry))
            await playback.load(document: document, preferences: preferences)
            libraryService.markPlayed(entry)
            selectedTab = .player

            if preferences.resumeFromLastPosition, entry.hasResumePoint {
                let snapshot = entry.practiceSnapshot
                // Same conversion the transport read-out uses, so the two agree at any speed.
                var probe = PlaybackState()
                probe.tempo = document.tempo
                probe.speed = snapshot.speed
                let seconds = probe.beatsToSeconds(snapshot.beat)
                resumePrompt = ResumePrompt(entryId: entry.id,
                                            title: document.title,
                                            snapshot: snapshot,
                                            timeLabel: seconds.clockString)
            } else if autoplay {
                playback.play()
            }
        } catch {
            loadError = error.localizedDescription
        }
        isLoadingTab = false
    }

    func open(entry: LibraryEntry, autoplay: Bool = false) async {
        await open(result: entry.searchResult, autoplay: autoplay)
    }

    func acceptResume() {
        guard let prompt = resumePrompt else { return }
        playback.restore(practice: prompt.snapshot)
        resumePrompt = nil
    }

    func declineResume() {
        resumePrompt = nil
        playback.seek(toBeat: 0)
    }

    // MARK: - Practice state

    func persistPracticeState() {
        guard let entry = openEntry else { return }
        libraryService.store(practice: playback.practiceSnapshot, for: entry)
    }

    /// Mirrors the player's current toggles back into the user's defaults.
    func capturePlaybackDefaults() {
        var updated = preferences
        updated.metronomeEnabled = playback.state.metronomeEnabled
        updated.metronomeVolume = playback.state.metronomeVolume
        updated.metronomeSubdivision = playback.state.metronomeSubdivision
        updated.countInEnabled = playback.state.countInEnabled
        updated.backtrackEnabled = playback.state.backtrackEnabled
        updated.autoScrollEnabled = playback.state.autoScrollEnabled
        updated.chordDisplayEnabled = playback.state.chordDisplayEnabled
        preferences = updated
    }
}
