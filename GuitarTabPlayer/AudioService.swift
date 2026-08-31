import Foundation

/// An instrument tuning. `strings` is ordered from the lowest sounding string upwards,
/// i.e. index 0 is the 6th string (low E) on a standard guitar.
struct Tuning: Codable, Hashable, Sendable, Identifiable {
    var name: String
    var strings: [Pitch]

    var id: String { name }
    var stringCount: Int { strings.count }

    /// Tab notation draws the highest string on the top line.
    var displayOrder: [Int] { Array((0..<strings.count).reversed()) }

    /// Single letter labels drawn at the left of each tab line, top to bottom.
    var lineLabels: [String] {
        displayOrder.map { index in
            let raw = strings[index].name
            // Tab convention writes only the highest string in lower case, so that a
            // standard-tuned guitar reads e B G D A E and the two Es stay distinguishable.
            return index == strings.count - 1 ? raw.lowercased() : raw
        }
    }

    func fret(for pitch: Pitch, string index: Int) -> Int? {
        guard strings.indices.contains(index) else { return nil }
        let fret = pitch.midi - strings[index].midi
        return fret >= 0 ? fret : nil
    }

    func pitch(string index: Int, fret: Int) -> Pitch? {
        guard strings.indices.contains(index) else { return nil }
        return Pitch(midi: strings[index].midi + fret)
    }

    func transposed(by semitones: Int) -> Tuning {
        Tuning(name: name, strings: strings.map { $0.transposed(by: semitones) })
    }

    // MARK: - Presets

    static let standard      = Tuning(name: "Standard",     strings: [40, 45, 50, 55, 59, 64].map(Pitch.init(midi:)))
    static let dropD         = Tuning(name: "Drop D",       strings: [38, 45, 50, 55, 59, 64].map(Pitch.init(midi:)))
    static let ebStandard    = Tuning(name: "Eb Standard",  strings: [39, 44, 49, 54, 58, 63].map(Pitch.init(midi:)))
    static let dStandard     = Tuning(name: "D Standard",   strings: [38, 43, 48, 53, 57, 62].map(Pitch.init(midi:)))
    static let dropC         = Tuning(name: "Drop C",       strings: [36, 43, 48, 53, 57, 62].map(Pitch.init(midi:)))
    static let openG         = Tuning(name: "Open G",       strings: [38, 43, 50, 55, 59, 62].map(Pitch.init(midi:)))
    static let openD         = Tuning(name: "Open D",       strings: [38, 45, 50, 54, 57, 62].map(Pitch.init(midi:)))
    static let bassStandard  = Tuning(name: "Bass Standard", strings: [28, 33, 38, 43].map(Pitch.init(midi:)))
    static let bassDropD     = Tuning(name: "Bass Drop D",  strings: [26, 33, 38, 43].map(Pitch.init(midi:)))

    static let allPresets: [Tuning] = [
        .standard, .dropD, .ebStandard, .dStandard, .dropC, .openG, .openD, .bassStandard, .bassDropD
    ]

    static func preset(named name: String) -> Tuning? {
        allPresets.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
