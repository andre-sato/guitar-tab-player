import Foundation

struct TimeSignature: Codable, Hashable, Sendable {
    var beatsPerBar: Int
    var beatUnit: Int

    static let fourFour = TimeSignature(beatsPerBar: 4, beatUnit: 4)
    static let threeFour = TimeSignature(beatsPerBar: 3, beatUnit: 4)
    static let sixEight = TimeSignature(beatsPerBar: 6, beatUnit: 8)

    var displayName: String { "\(beatsPerBar)/\(beatUnit)" }

    /// Length of one bar expressed in quarter-note beats (the unit used throughout the app).
    var barLengthInBeats: Double { Double(beatsPerBar) * (4.0 / Double(beatUnit)) }

    func measureIndex(forBeat beat: Double) -> Int {
        guard barLengthInBeats > 0 else { return 0 }
        return Int(floor(beat / barLengthInBeats))
    }

    func beatWithinMeasure(forBeat beat: Double) -> Double {
        guard barLengthInBeats > 0 else { return beat }
        return beat.truncatingRemainder(dividingBy: barLengthInBeats)
    }

    func startBeat(ofMeasure index: Int) -> Double { Double(index) * barLengthInBeats }
}

struct SongSection: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var startBeat: Double
    var lengthBeats: Double

    var endBeat: Double { startBeat + lengthBeats }
}
