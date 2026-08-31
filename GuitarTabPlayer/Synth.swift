import Foundation

/// The chord qualities the transposition engine must preserve (spec §24).
enum ChordQuality: String, Codable, CaseIterable, Sendable {
    case major, minor, diminished, augmented
    case dominant7, major7, minor7, minorMajor7, halfDiminished7, diminished7
    case sus2, sus4, add9, six, minor6, major9, minor9, dominant9, dominant11, dominant13
    case power

    /// Suffix appended to the root name to build the chord symbol.
    var symbolSuffix: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .diminished: return "dim"
        case .augmented: return "aug"
        case .dominant7: return "7"
        case .major7: return "maj7"
        case .minor7: return "m7"
        case .minorMajor7: return "mMaj7"
        case .halfDiminished7: return "m7b5"
        case .diminished7: return "dim7"
        case .sus2: return "sus2"
        case .sus4: return "sus4"
        case .add9: return "add9"
        case .six: return "6"
        case .minor6: return "m6"
        case .major9: return "maj9"
        case .minor9: return "m9"
        case .dominant9: return "9"
        case .dominant11: return "11"
        case .dominant13: return "13"
        case .power: return "5"
        }
    }

    /// Semitone offsets from the root, used by the synthesized backtrack.
    var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .diminished: return [0, 3, 6]
        case .augmented: return [0, 4, 8]
        case .dominant7: return [0, 4, 7, 10]
        case .major7: return [0, 4, 7, 11]
        case .minor7: return [0, 3, 7, 10]
        case .minorMajor7: return [0, 3, 7, 11]
        case .halfDiminished7: return [0, 3, 6, 10]
        case .diminished7: return [0, 3, 6, 9]
        case .sus2: return [0, 2, 7]
        case .sus4: return [0, 5, 7]
        case .add9: return [0, 4, 7, 14]
        case .six: return [0, 4, 7, 9]
        case .minor6: return [0, 3, 7, 9]
        case .major9: return [0, 4, 7, 11, 14]
        case .minor9: return [0, 3, 7, 10, 14]
        case .dominant9: return [0, 4, 7, 10, 14]
        case .dominant11: return [0, 4, 7, 10, 14, 17]
        case .dominant13: return [0, 4, 7, 10, 14, 21]
        case .power: return [0, 7]
        }
    }
}

/// A chord symbol anchored to a position on the musical timeline.
struct Chord: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var startBeat: Double
    var durationBeats: Double
    var root: Int              // pitch class 0...11
    var quality: ChordQuality
    var bass: Int?             // pitch class of a slash-chord bass note

    var endBeat: Double { startBeat + durationBeats }

    init(id: String = UUID().uuidString,
         startBeat: Double,
         durationBeats: Double,
         root: Int,
         quality: ChordQuality,
         bass: Int? = nil) {
        self.id = id
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.root = ((root % 12) + 12) % 12
        self.quality = quality
        self.bass = bass
    }

    func symbol(preferFlats: Bool = false) -> String {
        var text = NoteName.name(for: root, preferFlats: preferFlats) + quality.symbolSuffix
        if let bass, bass != root {
            text += "/" + NoteName.name(for: bass, preferFlats: preferFlats)
        }
        return text
    }

    /// Pitch classes that make up the chord, for synthesis and for chord diagrams.
    var pitchClasses: [Int] {
        quality.intervals.map { (((root + $0) % 12) + 12) % 12 }
    }
}
