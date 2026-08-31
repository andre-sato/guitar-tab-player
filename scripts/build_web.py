import Foundation
import SwiftData

/// One saved tab, plus the practice state attached to it (spec §32, §35, §36).
@Model
final class LibraryEntry {
    @Attribute(.unique) var id: String        // "<providerId>:<tabId>"
    var tabId: String
    var providerId: String
    var providerName: String
    var title: String
    var artist: String
    var album: String?
    var tempo: Double
    var difficultyRaw: String
    var tuningName: String
    var instrumentsRaw: [String]

    var isFavorite: Bool
    var isDownloaded: Bool
    var addedAt: Date
    var lastPlayedAt: Date?
    var playCount: Int

    // Practice state
    var lastBeat: Double
    var lastSpeed: Double
    var lastTranspose: Int
    var mutedTrackIds: [String]

    /// Normalised document cached for offline use, only when the licence permits it (spec §33).
    @Attribute(.externalStorage) var cachedDocument: Data?

    init(result: TabSearchResult) {
        self.id = "\(result.providerId):\(result.id)"
        self.tabId = result.id
        self.providerId = result.providerId
        self.providerName = result.providerName
        self.title = result.title
        self.artist = result.artist
        self.album = result.album
        self.tempo = result.tempo
        self.difficultyRaw = result.difficulty.rawValue
        self.tuningName = result.tuning
        self.instrumentsRaw = result.instruments.map(\.rawValue)
        self.isFavorite = false
        self.isDownloaded = false
        self.addedAt = .now
        self.lastPlayedAt = nil
        self.playCount = 0
        self.lastBeat = 0
        self.lastSpeed = 1.0
        self.lastTranspose = 0
        self.mutedTrackIds = []
        self.cachedDocument = nil
    }

    var difficulty: Difficulty { Difficulty(rawValue: difficultyRaw) ?? .intermediate }
    var instruments: [InstrumentType] { instrumentsRaw.compactMap(InstrumentType.init(rawValue:)) }

    var practiceSnapshot: PracticeSnapshot {
        PracticeSnapshot(beat: lastBeat, speed: lastSpeed, transpose: lastTranspose, mutedTrackIds: mutedTrackIds)
    }

    func apply(_ snapshot: PracticeSnapshot) {
        lastBeat = snapshot.beat
        lastSpeed = snapshot.speed
        lastTranspose = snapshot.transpose
        mutedTrackIds = snapshot.mutedTrackIds
    }

    var hasResumePoint: Bool { lastBeat > 1 }

    var searchResult: TabSearchResult {
        TabSearchResult(id: tabId,
                        providerId: providerId,
                        providerName: providerName,
                        title: title,
                        artist: artist,
                        album: album,
                        difficulty: difficulty,
                        tuning: tuningName,
                        instruments: instruments,
                        tempo: tempo,
                        rating: 0,
                        capabilities: isDownloaded ? .full : .tabOnly)
    }
}
