import Foundation
import Observation

@Observable
@MainActor
final class SearchViewModel {

    var query: String = ""
    var filters = SearchFilters()
    private(set) var results: [TabSearchResult] = []
    private(set) var failures: [SearchService.ProviderFailure] = []
    private(set) var isSearching = false
    private(set) var hasSearched = false

    private let service: SearchService
    private var searchTask: Task<Void, Never>?

    init(service: SearchService) {
        self.service = service
    }

    var availableProviders: [(id: String, name: String)] { service.providers }

    var availableTunings: [String] { Tuning.allPresets.map(\.name) }

    func onAppear() async {
        guard !hasSearched else { return }
        await runSearch()
    }

    /// Debounced so typing does not fan out a request per keystroke.
    func queryChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.runSearch()
        }
    }

    func filtersChanged() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in await self?.runSearch() }
    }

    func clearFilters() {
        filters = SearchFilters()
        filtersChanged()
    }

    func runSearch() async {
        isSearching = true
        let outcome = await service.search(query: query, filters: filters)
        guard !Task.isCancelled else { isSearching = false; return }
        results = outcome.results
        failures = outcome.failures
        isSearching = false
        hasSearched = true
    }
}
