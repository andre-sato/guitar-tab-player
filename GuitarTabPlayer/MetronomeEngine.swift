import Foundation

/// Builds the click plan for the metronome and the count-in.
///
/// The engine only produces *positions*; rendering them to audio is the audio layer's job.
/// That keeps the click perfectly aligned with the same beat grid the tab sheet uses (spec §38).
struct MetronomeEngine: Sendable {

    struct Click: Hashable, Sendable {
        /// Position on the song timeline. Negative values belong to the count-in.
        var beat: Double
        var accent: Bool
        var isCountIn: Bool
    }

    var tempo: TempoEngine
    var subdivision: MetronomeSubdivision

    init(tempo: TempoEngine, subdivision: MetronomeSubdivision = .quarter) {
        self.tempo = tempo
        self.subdivision = subdivision
    }

    /// Clicks for the body of the song, starting at `startBeat`.
    func clicks(from startBeat: Double, to endBeat: Double) -> [Click] {
        let step = 1.0 / Double(subdivision.clicksPerBeat)
        guard step > 0, endBeat > startBeat else { return [] }

        // Align to the subdivision grid so a mid-song seek still lands on the grid.
        var beat = (startBeat / step).rounded(.up) * step
        var result: [Click] = []
        while beat < endBeat - 1e-9 {
            result.append(Click(beat: beat, accent: tempo.isDownbeat(beat), isCountIn: false))
            beat += step
        }
        return result
    }

    /// The three-beat count-in (spec §21). Beats are negative: -3, -2, -1.
    func countInClicks(beats: Int = TempoEngine.countInBeats, startBeat: Double = 0) -> [Click] {
        guard beats > 0 else { return [] }
        return (0..<beats).map { index in
            Click(beat: startBeat - Double(beats - index), accent: index == 0, isCountIn: true)
        }
    }

    /// Number the user sees during the count-in: 3, 2, 1.
    static func countInDisplayNumber(beatsRemaining: Int) -> String {
        beatsRemaining > 0 ? "\(beatsRemaining)" : "GO"
    }
}
