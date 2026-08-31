import Foundation

/// Reads tabs the app is allowed to ship or that the user imported themselves (spec §2.5).
///
/// Two sources are merged:
///  * `tab-*.json` bundled with the app — original demo material written for this project;
///  * `Documents/ImportedTabs/*.json` — files the user imported from their own device.
actor LocalFileProvider: TabProvider {

    nonisolated let id = "local"
    nonisolated let name = "Local Library"
    nonisolated var isAvailableOffline: Bool { true }

    private var cache: [String: TabDocument] = [:]
    private var didLoad = false

    static var importedTabsDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ImportedTabs", isDirectory: true)
    }

    // MARK: - Loading

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        let decoder = JSONDecoder()
        var urls: [URL] = []

        if let bundled = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            urls += bundled.filter { $0.lastPathComponent.hasPrefix("tab-") }
        }
        if let bundledInFolder = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Tabs") {
            urls += bundledInFolder
        }
        if let imported = try? FileManager.default.contentsOfDirectory(
            at: Self.importedTabsDirectory, includingPropertiesForKeys: nil) {
            urls += imported.filter { $0.pathExtension.lowercased() == "json" }
        }

        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard var document = try? decoder.decode(TabDocument.self, from: data) else {
                NSLog("GuitarTabPlayer: could not decode tab at \(url.lastPathComponent)")
                continue
            }
            document.providerId = id
            cache[document.id] = document
        }
    }

    private var documents: [TabDocument] {
        loadIfNeeded()
        return cache.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - TabProvider

    func search(query: String, filters: SearchFilters) async throws -> [TabSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return documents
            .filter { document in
                guard trimmed.isEmpty || Self.matches(document, query: trimmed) else { return false }
                if let instrument = filters.instrument,
                   !document.tracks.contains(where: { $0.instrument == instrument }) { return false }
                if let difficulty = filters.difficulty, document.difficulty != difficulty { return false }
                if let tuning = filters.tuning,
                   !document.tracks.contains(where: { $0.tuning.name.caseInsensitiveCompare(tuning) == .orderedSame }) { return false }
                if let artist = filters.artist,
                   document.artist.localizedCaseInsensitiveContains(artist) == false { return false }
                if let album = filters.album,
                   (document.album ?? "").localizedCaseInsensitiveContains(album) == false { return false }
                return true
            }
            .map(makeResult(from:))
    }

    func fetchTab(id documentId: String) async throws -> TabDocument {
        loadIfNeeded()
        guard let document = cache[documentId] else { throw ProviderError.notFound(id: documentId) }
        return document
    }

    func fetchAudio(id documentId: String) async throws -> AudioPackage? {
        loadIfNeeded()
        return cache[documentId]?.audioPackage
    }

    func capabilities(for documentId: String) async throws -> ContentCapabilities {
        loadIfNeeded()
        return cache[documentId]?.capabilities ?? .tabOnly
    }

    // MARK: - Import

    /// Copies a user-supplied tab file into the app's library.
    func importTab(from url: URL) throws -> TabDocument {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        var document = try JSONDecoder().decode(TabDocument.self, from: data)
        document.providerId = id

        try FileManager.default.createDirectory(at: Self.importedTabsDirectory, withIntermediateDirectories: true)
        let destination = Self.importedTabsDirectory.appendingPathComponent("\(document.id).json")
        try JSONEncoder().encode(document).write(to: destination, options: .atomic)

        loadIfNeeded()
        cache[document.id] = document
        return document
    }

    // MARK: - Helpers

    private static func matches(_ document: TabDocument, query: String) -> Bool {
        document.title.localizedCaseInsensitiveContains(query)
            || document.artist.localizedCaseInsensitiveContains(query)
            || (document.album ?? "").localizedCaseInsensitiveContains(query)
    }

    private func makeResult(from document: TabDocument) -> TabSearchResult {
        TabSearchResult(id: document.id,
                        providerId: id,
                        providerName: name,
                        title: document.title,
                        artist: document.artist,
                        album: document.album,
                        difficulty: document.difficulty,
                        tuning: document.tracks.first(where: { $0.instrument.isFretted })?.tuning.name ?? "Standard",
                        instruments: document.tracks.map(\.instrument),
                        tempo: document.tempo,
                        rating: 4.5,
                        capabilities: document.capabilities)
    }
}
