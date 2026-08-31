import Foundation

/// Fetches normalised tabs, preferring an offline copy when one is allowed to exist (spec §33).
@MainActor
final class TabService {

    private let registry: ProviderRegistry
    private var memoryCache: [String: TabDocument] = [:]

    init(registry: ProviderRegistry) {
        self.registry = registry
    }

    private func cacheKey(providerId: String, tabId: String) -> String { "\(providerId):\(tabId)" }

    func document(providerId: String, tabId: String, offlineData: Data? = nil) async throws -> TabDocument {
        let key = cacheKey(providerId: providerId, tabId: tabId)
        if let cached = memoryCache[key] { return cached }

        if let offlineData, let document = try? JSONDecoder().decode(TabDocument.self, from: offlineData) {
            memoryCache[key] = document
            return document
        }

        guard let provider = registry.provider(withId: providerId) else {
            throw ProviderError.unavailable(providerName: providerId)
        }

        var document = try await provider.fetchTab(id: tabId)
        document.capabilities = (try? await provider.capabilities(for: tabId)) ?? document.capabilities
        if document.capabilities.canStreamAudio {
            document.audioPackage = try? await provider.fetchAudio(id: tabId)
        }
        memoryCache[key] = document
        return document
    }

    func document(for result: TabSearchResult, offlineData: Data? = nil) async throws -> TabDocument {
        try await document(providerId: result.providerId, tabId: result.id, offlineData: offlineData)
    }

    func evict(providerId: String, tabId: String) {
        memoryCache.removeValue(forKey: cacheKey(providerId: providerId, tabId: tabId))
    }

    func clearCache() { memoryCache.removeAll() }
}
