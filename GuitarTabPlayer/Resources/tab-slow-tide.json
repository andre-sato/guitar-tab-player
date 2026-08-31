import Foundation

/// Geometry constants shared by the tab sheet view and its hit-testing.
struct TabMetrics: Hashable, Sendable {
    var pointsPerBeat: Double = 62
    var stringSpacing: Double = 19
    var chordLaneHeight: Double = 30
    var sectionLaneHeight: Double = 18
    var beatRulerHeight: Double = 20
    var leadingGutter: Double = 34

    static let `default` = TabMetrics()

    func staffHeight(stringCount: Int) -> Double {
        Double(max(1, stringCount - 1)) * stringSpacing
    }

    func x(forBeat beat: Double) -> Double { leadingGutter + beat * pointsPerBeat }
    func beat(forX x: Double) -> Double { max(0, (x - leadingGutter) / pointsPerBeat) }

    func scaled(by factor: Double) -> TabMetrics {
        var copy = self
        copy.pointsPerBeat = pointsPerBeat * factor
        copy.stringSpacing = stringSpacing * factor
        return copy
    }
}

/// One measure of the sheet, precomputed so the view never does layout maths per frame.
struct MeasureLayout: Identifiable, Hashable, Sendable {
    var index: Int
    var startBeat: Double
    var lengthBeats: Double
    var id: Int { index }
    var endBeat: Double { startBeat + lengthBeats }
}

/// A fretted note already placed on the sheet.
struct PlacedNote: Identifiable, Hashable, Sendable {
    var id: String
    var beat: Double
    var durationBeats: Double
    var stringIndex: Int      // 0 = lowest string
    var fret: Int
    var technique: Technique
    /// Extra text drawn after the fret number (bend target, slide destination…).
    var annotation: String?
}

struct PlacedDrumHit: Identifiable, Hashable, Sendable {
    var id: String
    var beat: Double
    var lane: Int
    var symbol: String
    var accent: Bool
}

/// Read model consumed by the tab sheet. Rebuilt only when the document, track or transpose change.
struct TabLayout: Sendable {
    var trackId: String
    var instrument: InstrumentType
    var tuning: Tuning
    var timeSignature: TimeSignature
    var totalBeats: Double
    var measures: [MeasureLayout]
    var notes: [PlacedNote]
    var drumHits: [PlacedDrumHit]
    var chords: [Chord]
    var sections: [SongSection]
    var isDrumLane: Bool
    /// Flat keys read better spelled with flats: Bb, not A#.
    var prefersFlats: Bool

    var lineCount: Int { isDrumLane ? DrumPiece.laneCount : tuning.stringCount }

    static let empty = TabLayout(trackId: "", instrument: .other, tuning: .standard,
                                 timeSignature: .fourFour, totalBeats: 0, measures: [],
                                 notes: [], drumHits: [], chords: [], sections: [], isDrumLane: false,
                                 prefersFlats: false)
}

/// Turns a `TabDocument` into everything the tab sheet needs, and answers timeline queries.
enum TabEngine {

    // MARK: - Layout

    static func buildLayout(document: TabDocument, trackId: String?) -> TabLayout {
        guard let track = trackId.flatMap({ document.track(withId: $0) }) ?? document.tracks.first else {
            return .empty
        }

        let timeSignature = document.timeSignature
        let totalBeats = document.totalBeats
        let bar = timeSignature.barLengthInBeats
        let measureCount = document.measureCount

        let measures = (0..<measureCount).map {
            MeasureLayout(index: $0, startBeat: Double($0) * bar, lengthBeats: bar)
        }

        var notes: [PlacedNote] = []
        var hits: [PlacedDrumHit] = []

        for event in track.events {
            switch event {
            case .rest:
                continue
            case .drum(let drum):
                hits.append(PlacedDrumHit(id: drum.id,
                                          beat: drum.startBeat,
                                          lane: drum.piece.lane,
                                          symbol: drum.piece.tabSymbol,
                                          accent: drum.velocity >= 0.9))
            case .bend(let bend):
                notes.append(PlacedNote(id: bend.note.id,
                                        beat: bend.note.startBeat,
                                        durationBeats: bend.note.durationBeats,
                                        stringIndex: bend.note.string,
                                        fret: bend.note.fret,
                                        technique: .bend,
                                        annotation: bend.semitones >= 2 ? "b" : "b½"))
            case .slide(let slide):
                notes.append(PlacedNote(id: slide.note.id,
                                        beat: slide.note.startBeat,
                                        durationBeats: slide.note.durationBeats,
                                        stringIndex: slide.note.string,
                                        fret: slide.note.fret,
                                        technique: .slide,
                                        annotation: "/\(slide.targetFret)"))
            default:
                for note in event.frettedNotes {
                    notes.append(PlacedNote(id: note.id,
                                            beat: note.startBeat,
                                            durationBeats: note.durationBeats,
                                            stringIndex: note.string,
                                            fret: note.fret,
                                            technique: note.technique,
                                            annotation: nil))
                }
            }
        }

        notes.sort { $0.beat < $1.beat }
        hits.sort { $0.beat < $1.beat }

        return TabLayout(trackId: track.id,
                         instrument: track.instrument,
                         tuning: track.tuning,
                         timeSignature: timeSignature,
                         totalBeats: totalBeats,
                         measures: measures,
                         notes: notes,
                         drumHits: hits,
                         chords: document.chords,
                         sections: document.sections,
                         isDrumLane: track.instrument == .drums,
                         prefersFlats: document.key.prefersFlats)
    }

    // MARK: - Timeline queries

    static func chord(in chords: [Chord], at beat: Double) -> Chord? {
        chords.last { $0.startBeat <= beat + 1e-6 && beat < $0.endBeat - 1e-6 }
            ?? chords.last { $0.startBeat <= beat + 1e-6 }
    }

    static func section(in sections: [SongSection], at beat: Double) -> SongSection? {
        sections.last { $0.startBeat <= beat + 1e-6 && beat < $0.endBeat - 1e-6 }
    }

    /// Beats of all events in a window — used to pre-cache what is about to be drawn (spec §39).
    static func notes(_ notes: [PlacedNote], in range: ClosedRange<Double>) -> [PlacedNote] {
        notes.filter { $0.beat + $0.durationBeats >= range.lowerBound && $0.beat <= range.upperBound }
    }

    static func drumHits(_ hits: [PlacedDrumHit], in range: ClosedRange<Double>) -> [PlacedDrumHit] {
        hits.filter { range.contains($0.beat) }
    }

    /// Snaps a seek target to the nearest event so tapping the sheet lands musically (spec §13).
    static func snapBeat(_ beat: Double, layout: TabLayout, tolerance: Double = 0.25) -> Double {
        let candidates: [Double] = layout.isDrumLane
            ? layout.drumHits.map(\.beat)
            : layout.notes.map(\.beat)
        guard let nearest = candidates.min(by: { abs($0 - beat) < abs($1 - beat) }) else { return beat }
        return abs(nearest - beat) <= tolerance ? nearest : beat
    }
}
