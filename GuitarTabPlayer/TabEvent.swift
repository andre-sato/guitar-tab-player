import Foundation

/// Playing technique attached to a fretted note.
enum Technique: String, Codable, CaseIterable, Sendable {
    case none
    case hammerOn
    case pullOff
    case bend
    case slide
    case vibrato
    case palmMute
    case ghost
    case harmonic
    case tap

    /// Marker drawn next to the fret number in the tab sheet.
    var tabMarker: String? {
        switch self {
        case .none: return nil
        case .hammerOn: return "h"
        case .pullOff: return "p"
        case .bend: return "b"
        case .slide: return "/"
        case .vibrato: return "~"
        case .palmMute: return "PM"
        case .ghost: return "x"
        case .harmonic: return "◇"
        case .tap: return "t"
        }
    }
}

/// A single fretted note on one string.
struct NoteEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var startBeat: Double
    var durationBeats: Double
    var string: Int
    var fret: Int
    var technique: Technique
    var velocity: Float

    init(id: String = UUID().uuidString,
         startBeat: Double,
         durationBeats: Double,
         string: Int,
         fret: Int,
         technique: Technique = .none,
         velocity: Float = 0.8) {
        self.id = id
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.string = string
        self.fret = fret
        self.technique = technique
        self.velocity = velocity
    }
}

/// Several notes struck together (a strummed shape).
struct ChordEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var startBeat: Double
    var durationBeats: Double
    var notes: [NoteEvent]
    var strumSpreadBeats: Double
    var velocity: Float

    init(id: String = UUID().uuidString,
         startBeat: Double,
         durationBeats: Double,
         notes: [NoteEvent],
         strumSpreadBeats: Double = 0.03,
         velocity: Float = 0.85) {
        self.id = id
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.notes = notes
        self.strumSpreadBeats = strumSpreadBeats
        self.velocity = velocity
    }
}

struct RestEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var startBeat: Double
    var durationBeats: Double

    init(id: String = UUID().uuidString, startBeat: Double, durationBeats: Double) {
        self.id = id
        self.startBeat = startBeat
        self.durationBeats = durationBeats
    }
}

struct BendEvent: Codable, Hashable, Sendable, Identifiable {
    var note: NoteEvent
    /// How far the string is pushed, in semitones (1.0 = full tone bend).
    var semitones: Double
    /// Fraction of the note duration spent reaching the target pitch.
    var riseFraction: Double

    var id: String { note.id }

    init(note: NoteEvent, semitones: Double = 2.0, riseFraction: Double = 0.35) {
        self.note = note
        self.semitones = semitones
        self.riseFraction = riseFraction
    }
}

struct SlideEvent: Codable, Hashable, Sendable, Identifiable {
    var note: NoteEvent
    var targetFret: Int

    var id: String { note.id }

    init(note: NoteEvent, targetFret: Int) {
        self.note = note
        self.targetFret = targetFret
    }
}

enum DrumPiece: String, Codable, CaseIterable, Sendable {
    case kick, snare, hiHatClosed, hiHatOpen, crash, ride, tomLow, tomMid, tomHigh

    /// Lane index used by the drum tab view (0 = top lane).
    var lane: Int {
        switch self {
        case .crash: return 0
        case .hiHatOpen, .hiHatClosed, .ride: return 1
        case .tomHigh: return 2
        case .snare: return 3
        case .tomMid: return 4
        case .tomLow: return 5
        case .kick: return 6
        }
    }

    var tabSymbol: String {
        switch self {
        case .kick: return "O"
        case .snare: return "o"
        case .hiHatClosed: return "x"
        case .hiHatOpen: return "X"
        case .crash: return "C"
        case .ride: return "r"
        case .tomLow, .tomMid, .tomHigh: return "o"
        }
    }

    var laneLabel: String {
        switch self {
        case .crash: return "CC"
        case .hiHatClosed, .hiHatOpen, .ride: return "HH"
        case .tomHigh: return "T1"
        case .snare: return "SD"
        case .tomMid: return "T2"
        case .tomLow: return "FT"
        case .kick: return "BD"
        }
    }

    static let laneLabels = ["CC", "HH", "T1", "SD", "T2", "FT", "BD"]
    static let laneCount = 7
}

struct DrumEvent: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var startBeat: Double
    var durationBeats: Double
    var piece: DrumPiece
    var velocity: Float

    init(id: String = UUID().uuidString,
         startBeat: Double,
         durationBeats: Double,
         piece: DrumPiece,
         velocity: Float = 0.9) {
        self.id = id
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.piece = piece
        self.velocity = velocity
    }
}

// MARK: - Event

enum TabEvent: Hashable, Sendable, Identifiable {
    case note(NoteEvent)
    case chord(ChordEvent)
    case rest(RestEvent)
    case bend(BendEvent)
    case slide(SlideEvent)
    case hammerOn(NoteEvent)
    case pullOff(NoteEvent)
    case drum(DrumEvent)

    var id: String {
        switch self {
        case .note(let e), .hammerOn(let e), .pullOff(let e): return e.id
        case .chord(let e): return e.id
        case .rest(let e): return e.id
        case .bend(let e): return e.id
        case .slide(let e): return e.id
        case .drum(let e): return e.id
        }
    }

    var startBeat: Double {
        switch self {
        case .note(let e), .hammerOn(let e), .pullOff(let e): return e.startBeat
        case .chord(let e): return e.startBeat
        case .rest(let e): return e.startBeat
        case .bend(let e): return e.note.startBeat
        case .slide(let e): return e.note.startBeat
        case .drum(let e): return e.startBeat
        }
    }

    var durationBeats: Double {
        switch self {
        case .note(let e), .hammerOn(let e), .pullOff(let e): return e.durationBeats
        case .chord(let e): return e.durationBeats
        case .rest(let e): return e.durationBeats
        case .bend(let e): return e.note.durationBeats
        case .slide(let e): return e.note.durationBeats
        case .drum(let e): return e.durationBeats
        }
    }

    var endBeat: Double { startBeat + durationBeats }

    /// Every fretted note carried by this event, flattened for rendering and synthesis.
    var frettedNotes: [NoteEvent] {
        switch self {
        case .note(let e): return [e]
        case .hammerOn(let e): return [NoteEvent(id: e.id, startBeat: e.startBeat, durationBeats: e.durationBeats, string: e.string, fret: e.fret, technique: .hammerOn, velocity: e.velocity)]
        case .pullOff(let e): return [NoteEvent(id: e.id, startBeat: e.startBeat, durationBeats: e.durationBeats, string: e.string, fret: e.fret, technique: .pullOff, velocity: e.velocity)]
        case .chord(let e): return e.notes
        case .bend(let e): return [e.note]
        case .slide(let e): return [e.note]
        case .rest, .drum: return []
        }
    }

    var drumEvent: DrumEvent? {
        if case .drum(let e) = self { return e }
        return nil
    }

    var isRest: Bool {
        if case .rest = self { return true }
        return false
    }

    func measure(in timeSignature: TimeSignature) -> Int {
        timeSignature.measureIndex(forBeat: startBeat)
    }

    /// Returns the same event with every fretted note remapped by `transform`.
    func mappingNotes(_ transform: (NoteEvent) -> NoteEvent) -> TabEvent {
        switch self {
        case .note(let e): return .note(transform(e))
        case .hammerOn(let e): return .hammerOn(transform(e))
        case .pullOff(let e): return .pullOff(transform(e))
        case .chord(let e):
            var copy = e
            copy.notes = e.notes.map(transform)
            return .chord(copy)
        case .bend(let e):
            var copy = e
            copy.note = transform(e.note)
            return .bend(copy)
        case .slide(let e):
            var copy = e
            copy.note = transform(e.note)
            return .slide(copy)
        case .rest, .drum:
            return self
        }
    }
}

// MARK: - Codable

extension TabEvent: Codable {
    private enum Kind: String, Codable {
        case note, chord, rest, bend, slide, hammerOn, pullOff, drum
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id, startBeat, durationBeats, string, fret, technique, velocity
        case notes, strumSpreadBeats
        case semitones, riseFraction, targetFret
        case piece
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)

        func decodeNote() throws -> NoteEvent {
            NoteEvent(
                id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
                startBeat: try container.decode(Double.self, forKey: .startBeat),
                durationBeats: try container.decode(Double.self, forKey: .durationBeats),
                string: try container.decode(Int.self, forKey: .string),
                fret: try container.decode(Int.self, forKey: .fret),
                technique: try container.decodeIfPresent(Technique.self, forKey: .technique) ?? .none,
                velocity: try container.decodeIfPresent(Float.self, forKey: .velocity) ?? 0.8
            )
        }

        switch kind {
        case .note: self = .note(try decodeNote())
        case .hammerOn: self = .hammerOn(try decodeNote())
        case .pullOff: self = .pullOff(try decodeNote())
        case .rest:
            self = .rest(RestEvent(
                id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
                startBeat: try container.decode(Double.self, forKey: .startBeat),
                durationBeats: try container.decode(Double.self, forKey: .durationBeats)))
        case .chord:
            self = .chord(ChordEvent(
                id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
                startBeat: try container.decode(Double.self, forKey: .startBeat),
                durationBeats: try container.decode(Double.self, forKey: .durationBeats),
                notes: try container.decode([NoteEvent].self, forKey: .notes),
                strumSpreadBeats: try container.decodeIfPresent(Double.self, forKey: .strumSpreadBeats) ?? 0.03,
                velocity: try container.decodeIfPresent(Float.self, forKey: .velocity) ?? 0.85))
        case .bend:
            self = .bend(BendEvent(
                note: try decodeNote(),
                semitones: try container.decodeIfPresent(Double.self, forKey: .semitones) ?? 2.0,
                riseFraction: try container.decodeIfPresent(Double.self, forKey: .riseFraction) ?? 0.35))
        case .slide:
            self = .slide(SlideEvent(
                note: try decodeNote(),
                targetFret: try container.decode(Int.self, forKey: .targetFret)))
        case .drum:
            self = .drum(DrumEvent(
                id: try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString,
                startBeat: try container.decode(Double.self, forKey: .startBeat),
                durationBeats: try container.decode(Double.self, forKey: .durationBeats),
                piece: try container.decode(DrumPiece.self, forKey: .piece),
                velocity: try container.decodeIfPresent(Float.self, forKey: .velocity) ?? 0.9))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        func encodeNote(_ note: NoteEvent) throws {
            try container.encode(note.id, forKey: .id)
            try container.encode(note.startBeat, forKey: .startBeat)
            try container.encode(note.durationBeats, forKey: .durationBeats)
            try container.encode(note.string, forKey: .string)
            try container.encode(note.fret, forKey: .fret)
            try container.encode(note.technique, forKey: .technique)
            try container.encode(note.velocity, forKey: .velocity)
        }

        switch self {
        case .note(let e):
            try container.encode(Kind.note, forKey: .type); try encodeNote(e)
        case .hammerOn(let e):
            try container.encode(Kind.hammerOn, forKey: .type); try encodeNote(e)
        case .pullOff(let e):
            try container.encode(Kind.pullOff, forKey: .type); try encodeNote(e)
        case .rest(let e):
            try container.encode(Kind.rest, forKey: .type)
            try container.encode(e.id, forKey: .id)
            try container.encode(e.startBeat, forKey: .startBeat)
            try container.encode(e.durationBeats, forKey: .durationBeats)
        case .chord(let e):
            try container.encode(Kind.chord, forKey: .type)
            try container.encode(e.id, forKey: .id)
            try container.encode(e.startBeat, forKey: .startBeat)
            try container.encode(e.durationBeats, forKey: .durationBeats)
            try container.encode(e.notes, forKey: .notes)
            try container.encode(e.strumSpreadBeats, forKey: .strumSpreadBeats)
            try container.encode(e.velocity, forKey: .velocity)
        case .bend(let e):
            try container.encode(Kind.bend, forKey: .type)
            try encodeNote(e.note)
            try container.encode(e.semitones, forKey: .semitones)
            try container.encode(e.riseFraction, forKey: .riseFraction)
        case .slide(let e):
            try container.encode(Kind.slide, forKey: .type)
            try encodeNote(e.note)
            try container.encode(e.targetFret, forKey: .targetFret)
        case .drum(let e):
            try container.encode(Kind.drum, forKey: .type)
            try container.encode(e.id, forKey: .id)
            try container.encode(e.startBeat, forKey: .startBeat)
            try container.encode(e.durationBeats, forKey: .durationBeats)
            try container.encode(e.piece, forKey: .piece)
            try container.encode(e.velocity, forKey: .velocity)
        }
    }
}
