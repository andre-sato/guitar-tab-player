import Foundation

enum Difficulty: String, Codable, CaseIterable, Sendable, Identifiable {
    case beginner, intermediate, advanced, expert

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
    var stars: Int {
        switch self {
        case .beginner: return 2
        case .intermediate: return 3
        case .advanced: return 4
        case .expert: return 5
        }
    }
}

/// What the licence attached to a piece of content allows (spec §44).
struct ContentCapabilities: Codable, Hashable, Sendable {
    var canViewTab: Bool
    var canStreamAudio: Bool
    var canDownload: Bool
    var canTranspose: Bool

    static let full = ContentCapabilities(canViewTab: true, canStreamAudio: true, canDownload: true, canTranspose: true)
    static let tabOnly = ContentCapabilities(canViewTab: true, canStreamAudio: false, canDownload: false, canTranspose: true)
}

/// The normalised, provider-independent representation every adapter must produce.
struct TabDocument: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var providerId: String
    var title: String
    var artist: String
    var album: String?
    var version: Int
    var tempo: Double
    var timeSignature: TimeSignature
    var key: MusicalKey
    var difficulty: Difficulty
    var tracks: [TabTrack]
    var sections: [SongSection]
    var chords: [Chord]
    var capabilities: ContentCapabilities
    /// Set when the provider ships mixed or per-stem audio for this tab.
    var audioPackage: AudioPackage?

    init(id: String,
         providerId: String,
         title: String,
         artist: String,
         album: String? = nil,
         version: Int = 1,
         tempo: Double,
         timeSignature: TimeSignature = .fourFour,
         key: MusicalKey = .cMajor,
         difficulty: Difficulty = .intermediate,
         tracks: [TabTrack] = [],
         sections: [SongSection] = [],
         chords: [Chord] = [],
         capabilities: ContentCapabilities = .tabOnly,
         audioPackage: AudioPackage? = nil) {
        self.id = id
        self.providerId = providerId
        self.title = title
        self.artist = artist
        self.album = album
        self.version = version
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.key = key
        self.difficulty = difficulty
        self.tracks = tracks
        self.sections = sections
        self.chords = chords
        self.capabilities = capabilities
        self.audioPackage = audioPackage
    }

    var totalBeats: Double {
        let fromTracks = tracks.map(\.lastBeat).max() ?? 0
        let fromSections = sections.map(\.endBeat).max() ?? 0
        let fromChords = chords.map(\.endBeat).max() ?? 0
        let raw = max(fromTracks, max(fromSections, fromChords))
        // Round up to a whole bar so the sheet always ends on a barline.
        let bar = timeSignature.barLengthInBeats
        guard bar > 0 else { return raw }
        return (raw / bar).rounded(.up) * bar
    }

    var measureCount: Int {
        let bar = timeSignature.barLengthInBeats
        guard bar > 0 else { return 0 }
        return max(1, Int((totalBeats / bar).rounded(.up)))
    }

    /// Duration at 100% speed.
    var duration: TimeInterval { totalBeats * 60.0 / tempo }

    var hasOriginalAudio: Bool { audioPackage != nil && capabilities.canStreamAudio }

    func track(withId id: String) -> TabTrack? { tracks.first { $0.id == id } }
}

/// Audio delivered by a provider alongside a tab.
struct AudioPackage: Codable, Hashable, Sendable {
    struct Stem: Codable, Hashable, Sendable, Identifiable {
        var id: String
        var trackId: String?
        var instrument: InstrumentType
        var url: URL
    }

    var mixURL: URL?
    var stems: [Stem]
    /// Where the audio's beat 0 sits inside the file.
    var offsetSeconds: Double

    init(mixURL: URL? = nil, stems: [Stem] = [], offsetSeconds: Double = 0) {
        self.mixURL = mixURL
        self.stems = stems
        self.offsetSeconds = offsetSeconds
    }
}
