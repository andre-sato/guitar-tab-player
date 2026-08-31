import Foundation

/// Catalogue-level metadata, kept separate from tab content so licensing can differ (spec §44).
struct Song: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var artist: String
    var album: String?
    var duration: TimeInterval
    var tempo: Double
    var key: MusicalKey
    var providerId: String

    init(id: String,
         title: String,
         artist: String,
         album: String? = nil,
         duration: TimeInterval,
         tempo: Double,
         key: MusicalKey,
         providerId: String) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.tempo = tempo
        self.key = key
        self.providerId = providerId
    }

    init(document: TabDocument) {
        self.init(id: document.id,
                  title: document.title,
                  artist: document.artist,
                  album: document.album,
                  duration: document.duration,
                  tempo: document.tempo,
                  key: document.key,
                  providerId: document.providerId)
    }
}

/// One row in a search result list. Deliberately light: no events, no audio.
struct TabSearchResult: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var providerId: String
    var providerName: String
    var title: String
    var artist: String
    var album: String?
    var difficulty: Difficulty
    var tuning: String
    var instruments: [InstrumentType]
    var tempo: Double
    var rating: Double
    var capabilities: ContentCapabilities

    var subtitle: String {
        [artist, album].compactMap { $0 }.joined(separator: " · ")
    }
}

struct SearchFilters: Hashable, Sendable {
    var instrument: InstrumentType?
    var difficulty: Difficulty?
    var tuning: String?
    var providerIds: Set<String>
    var artist: String?
    var album: String?

    init(instrument: InstrumentType? = nil,
         difficulty: Difficulty? = nil,
         tuning: String? = nil,
         providerIds: Set<String> = [],
         artist: String? = nil,
         album: String? = nil) {
        self.instrument = instrument
        self.difficulty = difficulty
        self.tuning = tuning
        self.providerIds = providerIds
        self.artist = artist
        self.album = album
    }

    static let none = SearchFilters()

    var isEmpty: Bool {
        instrument == nil && difficulty == nil && tuning == nil
            && providerIds.isEmpty && artist == nil && album == nil
    }

    var activeCount: Int {
        var count = 0
        if instrument != nil { count += 1 }
        if difficulty != nil { count += 1 }
        if tuning != nil { count += 1 }
        if !providerIds.isEmpty { count += 1 }
        if artist != nil { count += 1 }
        if album != nil { count += 1 }
        return count
    }
}
