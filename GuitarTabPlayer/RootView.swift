import Foundation

/// Transposes chords and fretted notes, honouring the instrument's tuning (spec §23–§25).
enum TranspositionEngine {

    static let range: ClosedRange<Int> = -12...12

    // MARK: - Chords

    static func transpose(_ chord: Chord, by semitones: Int) -> Chord {
        var copy = chord
        copy.root = normalize(chord.root + semitones)
        if let bass = chord.bass { copy.bass = normalize(bass + semitones) }
        return copy
    }

    static func transpose(_ chords: [Chord], by semitones: Int) -> [Chord] {
        semitones == 0 ? chords : chords.map { transpose($0, by: semitones) }
    }

    static func transpose(_ key: MusicalKey, by semitones: Int) -> MusicalKey {
        key.transposed(by: semitones)
    }

    private static func normalize(_ pitchClass: Int) -> Int {
        ((pitchClass % 12) + 12) % 12
    }

    // MARK: - Tab

    /// The number of frets the app is willing to use before looking for another string.
    static let maxUsableFret = 22

    /// Result of relocating one note after a transposition.
    struct RelocatedNote {
        var string: Int
        var fret: Int
        /// True when the note had to move to a different string to stay playable.
        var movedString: Bool
        /// True when no playable position existed and the note was clamped.
        var isApproximate: Bool
    }

    /// Finds a playable position for `pitch` on `tuning`, preferring the original string and
    /// then the position closest to the original fret (spec §25).
    ///
    /// Frets are absolute (measured from the nut). `minFret` is where the capo sits — anything
    /// below it cannot be fretted at all, and clamping into that region would silently sound
    /// the wrong pitch.
    /// `excludedStrings` lets a caller relocate the notes of one chord without stacking two of
    /// them on the same string.
    static func relocate(pitch: Pitch,
                         tuning: Tuning,
                         preferredString: Int,
                         preferredFret: Int,
                         minFret: Int = 0,
                         excludedStrings: Set<Int> = []) -> RelocatedNote {
        if !excludedStrings.contains(preferredString),
           let fret = tuning.fret(for: pitch, string: preferredString),
           fret >= minFret, fret <= maxUsableFret {
            return RelocatedNote(string: preferredString, fret: fret, movedString: false, isApproximate: false)
        }

        var best: RelocatedNote?
        var bestCost = Double.greatestFiniteMagnitude

        for stringIndex in tuning.strings.indices where !excludedStrings.contains(stringIndex) {
            guard let fret = tuning.fret(for: pitch, string: stringIndex),
                  fret >= minFret, fret <= maxUsableFret else { continue }
            // Prefer staying near the original hand position and near the original string.
            let cost = Double(abs(fret - preferredFret)) + Double(abs(stringIndex - preferredString)) * 1.5
            if cost < bestCost {
                bestCost = cost
                best = RelocatedNote(string: stringIndex, fret: fret,
                                     movedString: stringIndex != preferredString, isApproximate: false)
            }
        }

        if let best { return best }

        // Out of range on every string: keep the shape, mark it as approximate.
        let clampedFret = max(minFret, min(maxUsableFret, preferredFret))
        return RelocatedNote(string: preferredString, fret: clampedFret, movedString: false, isApproximate: true)
    }

    static func transpose(_ note: NoteEvent,
                          by semitones: Int,
                          tuning: Tuning,
                          capo: Int = 0,
                          excludedStrings: Set<Int> = []) -> NoteEvent {
        guard semitones != 0 else { return note }
        guard let original = tuning.pitch(string: note.string, fret: note.fret + capo) else { return note }
        let placed = relocate(pitch: original.transposed(by: semitones),
                              tuning: tuning,
                              preferredString: note.string,
                              preferredFret: note.fret + capo,
                              minFret: capo,
                              excludedStrings: excludedStrings)
        var copy = note
        copy.string = placed.string
        copy.fret = max(0, placed.fret - capo)
        return copy
    }

    static func transpose(_ track: TabTrack, by semitones: Int) -> TabTrack {
        guard semitones != 0, track.instrument.isFretted else { return track }
        var copy = track
        copy.events = track.events.map { transpose($0, by: semitones, on: track) }
        return copy
    }

    /// Chords and slides carry state that a plain per-note remap would lose: a chord must not
    /// end up with two notes on one string, and a slide's destination fret has to travel with
    /// its starting note.
    static func transpose(_ event: TabEvent, by semitones: Int, on track: TabTrack) -> TabEvent {
        let tuning = track.tuning
        let capo = track.capo

        switch event {
        case .chord(let chordEvent):
            var claimed = Set<Int>()
            var copy = chordEvent
            copy.notes = chordEvent.notes
                .sorted { $0.string < $1.string }
                .map { note in
                    let moved = transpose(note, by: semitones, tuning: tuning,
                                          capo: capo, excludedStrings: claimed)
                    claimed.insert(moved.string)
                    return moved
                }
            return .chord(copy)

        case .slide(let slideEvent):
            var copy = slideEvent
            copy.note = transpose(slideEvent.note, by: semitones, tuning: tuning, capo: capo)
            if let targetPitch = tuning.pitch(string: slideEvent.note.string,
                                              fret: slideEvent.targetFret + capo)?
                                        .transposed(by: semitones),
               let fret = tuning.fret(for: targetPitch, string: copy.note.string),
               fret >= capo, fret <= maxUsableFret {
                copy.targetFret = fret - capo
            }
            return .slide(copy)

        default:
            return event.mappingNotes { transpose($0, by: semitones, tuning: tuning, capo: capo) }
        }
    }

    /// Applies a transposition to a whole document: key, chords and every fretted track.
    static func transpose(_ document: TabDocument, by semitones: Int) -> TabDocument {
        guard semitones != 0 else { return document }
        var copy = document
        copy.key = document.key.transposed(by: semitones)
        copy.chords = transpose(document.chords, by: semitones)
        copy.tracks = document.tracks.map { transpose($0, by: semitones) }
        return copy
    }

    /// Whether a transposition can be represented on the fretboard without approximation.
    static func isFullyRepresentable(_ document: TabDocument, by semitones: Int) -> Bool {
        for track in document.tracks where track.instrument.isFretted {
            for event in track.events {
                for note in event.frettedNotes {
                    guard let original = track.tuning.pitch(string: note.string, fret: note.fret + track.capo) else { continue }
                    let placed = relocate(pitch: original.transposed(by: semitones),
                                          tuning: track.tuning,
                                          preferredString: note.string,
                                          preferredFret: note.fret + track.capo,
                                          minFret: track.capo)
                    if placed.isApproximate { return false }
                }
            }
        }
        return true
    }
}
