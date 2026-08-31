import Foundation

/// Anything that can supply tabs. Adapters translate their own format into `TabDocument`
/// so the player never learns about a provider's wire format (ADR-003, ADR-004).
protocol TabProvider: Sendable {
    var id: String { get }
    var name: String { get }
    /// False when the provider needs the network, so the library can hide it offline.
    var isAvailableOffline: Bool { get }

    func search(query: String, filters: SearchFilters) async throws -> [TabSearchResult]
    func fetchTab(id: String) async throws -> TabDocument
    func fetchAudio(id: String) async throws -> AudioPackage?
    /// What the licence allows for this item (spec §44).
    func capabilities(for id: String) async throws -> ContentCapabilities
}

extension TabProvider {
    var isAvailableOffline: Bool { false }
    func fetchAudio(id: String) async throws -> AudioPackage? { nil }
    func capabilities(for id: String) async throws -> ContentCapabilities { .tabOnly }
}

enum ProviderError: LocalizedError {
    case unavailable(providerName: String)
    case notFound(id: String)
    case unsupportedFormat(String)
    case notLicensedForOffline

    var errorDescription: String? {
        switch self {
        case .unavailable(let name):
            return "Unable to connect to \(name). Try again."
        case .notFound(let id):
            return "Tab \(id) is no longer available from this catalog."
        case .unsupportedFormat(let detail):
            return "This tab format could not be read (\(detail))."
        case .notLicensedForOffline:
            return "This content needs an internet connection to be validated."
        }
    }
}

/// Registry of every adapter the app knows about. Adding a catalogue means adding it here —
/// nothing in the player changes.
@MainActor
final class ProviderRegistry {
    private(set) var providers: [any TabProvider]

    init(providers: [any TabProvider]) {
        self.providers = providers
    }

    static func makeDefault() -> ProviderRegistry {
        ProviderRegistry(providers: [LocalFileProvider()])
    }

    func provider(withId id: String) -> (any TabProvider)? {
        providers.first { $0.id == id }
    }

    func register(_ provider: any TabProvider) {
        guard !providers.contains(where: { $0.id == provider.id }) else { return }
        providers.append(provider)
    }
}
