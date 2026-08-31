import Foundation

enum InstrumentType: String, Codable, CaseIterable, Sendable, Identifiable {
    case leadGuitar
    case rhythmGuitar
    case acousticGuitar
    case bass
    case drums
    case piano
    case vocals
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .leadGuitar: return "Lead Guitar"
        case .rhythmGuitar: return "Rhythm Guitar"
        case .acousticGuitar: return "Acoustic Guitar"
        case .bass: return "Bass"
        case .drums: return "Drums"
        case .piano: return "Piano"
        case .vocals: return "Vocals"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .leadGuitar, .rhythmGuitar, .acousticGuitar: return "guitars"
        case .bass: return "guitars.fill"
        case .drums: return "circle.grid.cross"
        case .piano: return "pianokeys"
        case .vocals: return "music.mic"
        case .other: return "waveform"
        }
    }

    var isFretted: Bool {
        switch self {
        case .leadGuitar, .rhythmGuitar, .acousticGuitar, .bass: return true
        default: return false
        }
    }

    var defaultTuning: Tuning {
        switch self {
        case .bass: return .bassStandard
        default: return .standard
        }
    }

    /// Default stereo placement so the mix is not a mono blob.
    var defaultPan: Float {
        switch self {
        case .leadGuitar: return 0.25
        case .rhythmGuitar: return -0.3
        case .acousticGuitar: return -0.15
        default: return 0
        }
    }
}

struct TabTrack: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var instrument: InstrumentType
    var tuning: Tuning
    var events: [TabEvent]
    var isMuted: Bool
    var isSolo: Bool
    var volume: Float
    var pan: Float
    /// Capo position; fret numbers in the tab are relative to it.
    var capo: Int

    init(id: String = UUID().uuidString,
         name: String,
         instrument: InstrumentType,
         tuning: Tuning? = nil,
         events: [TabEvent] = [],
         isMuted: Bool = false,
         isSolo: Bool = false,
         volume: Float = 0.8,
         pan: Float? = nil,
         capo: Int = 0) {
        self.id = id
        self.name = name
        self.instrument = instrument
        self.tuning = tuning ?? instrument.defaultTuning
        self.events = events
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.volume = volume
        self.pan = pan ?? instrument.defaultPan
        self.capo = capo
    }

    var lastBeat: Double { events.map(\.endBeat).max() ?? 0 }

    /// Sounding pitch of a fretted note on this track, taking capo into account.
    func pitch(for note: NoteEvent) -> Pitch? {
        tuning.pitch(string: note.string, fret: note.fret + capo)
    }
}
