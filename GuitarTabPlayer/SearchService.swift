import Foundation

/// Fans a query out to every registered provider and merges the results (spec §6.1).
@MainActor
final class SearchService {

    struct ProviderFailure: Identifiable, Hashable {
        var id: String { providerId }
        var providerId: String
        var providerName: String
        var message: String
    }

    struct Outcome {
        var results: [TabSearchResult]
        var failures: [ProviderFailure]
    }

    private let registry: ProviderRegistry

    init(registry: ProviderRegistry) {
        self.registry = registry
    }

    var providers: [(id: String, name: String)] {
        registry.providers.map { ($0.id, $0.name) }
    }

    func search(query: String, filters: SearchFilters = .none) async -> Outcome {
        let selected = registry.providers.filter {
            filters.providerIds.isEmpty || filters.providerIds.contains($0.id)
        }

        var results: [TabSearchResult] = []
        var failures: [ProviderFailure] = []

        await withTaskGroup(of: (String, String, Result<[TabSearchResult], Error>).self) { group in
            for provider in selected {
                group.addTask {
                    do {
                        let found = try await provider.search(query: query, filters: filters)
                        return (provider.id, provider.name, .success(found))
                    } catch {
                        return (provider.id, provider.name, .failure(error))
                    }
                }
            }
            for await (providerId, providerName, outcome) in group {
                switch outcome {
                case .success(let found):
                    results.append(contentsOf: found)
                case .failure(let error):
                    failures.append(ProviderFailure(providerId: providerId,
                                                    providerName: providerName,
                                                    message: error.localizedDescription))
                }
            }
        }

        results.sort { lhs, rhs in
            if lhs.rating != rhs.rating { return lhs.rating > rhs.rating }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
        return Outcome(results: results, failures: failures)
    }

    /// Everything the catalogue can offer, used to fill the browse screen.
    func browseAll() async -> [TabSearchResult] {
        await search(query: "").results
    }
}
