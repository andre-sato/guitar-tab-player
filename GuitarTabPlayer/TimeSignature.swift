import Foundation

/// Stores a normalised tab for offline use, but only when the licence allows it (spec §33, §44).
@MainActor
final class DownloadService {

    enum DownloadState: Equatable {
        case notDownloaded
        case downloading
        case downloaded
        case notPermitted
        case failed(String)
    }

    private let tabService: TabService
    private let library: LibraryService
    private(set) var states: [String: DownloadState] = [:]

    init(tabService: TabService, library: LibraryService) {
        self.tabService = tabService
        self.library = library
    }

    func state(for entry: LibraryEntry) -> DownloadState {
        states[entry.id] ?? (entry.isDownloaded ? .downloaded : .notDownloaded)
    }

    @discardableResult
    func download(entry: LibraryEntry) async -> DownloadState {
        states[entry.id] = .downloading
        do {
            let document = try await tabService.document(providerId: entry.providerId, tabId: entry.tabId)
            guard document.capabilities.canDownload else {
                states[entry.id] = .notPermitted
                return .notPermitted
            }
            entry.cachedDocument = try JSONEncoder().encode(document)
            entry.isDownloaded = true
            library.save()
            states[entry.id] = .downloaded
            return .downloaded
        } catch {
            let state = DownloadState.failed(error.localizedDescription)
            states[entry.id] = state
            return state
        }
    }

    func removeDownload(entry: LibraryEntry) {
        entry.cachedDocument = nil
        entry.isDownloaded = false
        library.save()
        states[entry.id] = .notDownloaded
        tabService.evict(providerId: entry.providerId, tabId: entry.tabId)
    }

    /// Offline payload for an entry, if one was stored.
    func offlineData(for entry: LibraryEntry?) -> Data? {
        guard let entry, entry.isDownloaded else { return nil }
        return entry.cachedDocument
    }
}
