import Foundation

/// A concrete musical pitch, expressed as a MIDI note number (C-1 = 0, A4 = 69).
struct Pitch: Codable, Hashable, Sendable, Comparable {
    var midi: Int

    init(midi: Int) { self.midi = midi }

    init(pitchClass: Int, octave: Int) {
        self.midi = (octave + 1) * 12 + ((pitchClass % 12) + 12) % 12
    }

    /// 0 = C, 1 = C#, ... 11 = B
    var pitchClass: Int { ((midi % 12) + 12) % 12 }
    var octave: Int { midi / 12 - 1 }
    var frequency: Double { 440.0 * pow(2.0, Double(midi - 69) / 12.0) }

    var name: String { NoteName.sharpNames[pitchClass] }
    var displayName: String { "\(name)\(octave)" }

    func transposed(by semitones: Int) -> Pitch { Pitch(midi: midi + semitones) }

    static func < (lhs: Pitch, rhs: Pitch) -> Bool { lhs.midi < rhs.midi }

    // Codable as a bare integer so tab JSON stays compact.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.midi = try container.decode(Int.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(midi)
    }
}

enum NoteName {
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    static let flatNames  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// Chooses a spelling for a pitch class. Flat keys prefer flat spellings.
    static func name(for pitchClass: Int, preferFlats: Bool) -> String {
        let index = ((pitchClass % 12) + 12) % 12
        return preferFlats ? flatNames[index] : sharpNames[index]
    }

    static func pitchClass(for name: String) -> Int? {
        let normalized = name.trimmingCharacters(in: .whitespaces)
        if let index = sharpNames.firstIndex(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame } ) { return index }
        if let index = flatNames.firstIndex(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame } ) { return index }
        return nil
    }
}

/// Musical key of a piece, used for display and for chord spelling.
struct MusicalKey: Codable, Hashable, Sendable {
    enum Mode: String, Codable, Sendable { case major, minor }

    var root: Int          // pitch class 0...11
    var mode: Mode

    static let cMajor = MusicalKey(root: 0, mode: .major)

    /// Keys on the flat side of the circle of fifths read better with flat spellings.
    var prefersFlats: Bool {
        let flatMajorRoots: Set<Int> = [5, 10, 3, 8, 1]        // F, Bb, Eb, Ab, Db
        let flatMinorRoots: Set<Int> = [2, 7, 0, 5, 10]        // Dm, Gm, Cm, Fm, Bbm
        return mode == .major ? flatMajorRoots.contains(root) : flatMinorRoots.contains(root)
    }

    var displayName: String {
        let rootName = NoteName.name(for: root, preferFlats: prefersFlats)
        return mode == .major ? rootName : "\(rootName)m"
    }

    func transposed(by semitones: Int) -> MusicalKey {
        MusicalKey(root: (((root + semitones) % 12) + 12) % 12, mode: mode)
    }
}
