import Foundation

/// Converts between the musical timeline (beats/measures) and wall-clock seconds.
///
/// The engine always works in *score time*: seconds at 100% speed. Practice speed is applied
/// by the audio graph's time-stretch unit, so the beat grid never has to be rebuilt.
struct TempoEngine: Sendable {
    var tempo: Double                 // quarter notes per minute
    var timeSignature: TimeSignature

    init(tempo: Double, timeSignature: TimeSignature = .fourFour) {
        self.tempo = max(1, tempo)
        self.timeSignature = timeSignature
    }

    var secondsPerBeat: Double { 60.0 / tempo }
    var beatsPerSecond: Double { tempo / 60.0 }
    var secondsPerMeasure: Double { timeSignature.barLengthInBeats * secondsPerBeat }

    func seconds(forBeat beat: Double) -> Double { beat * secondsPerBeat }
    func beat(forSeconds seconds: Double) -> Double { seconds * beatsPerSecond }

    func measureIndex(forBeat beat: Double) -> Int { timeSignature.measureIndex(forBeat: beat) }
    func beatWithinMeasure(_ beat: Double) -> Double { timeSignature.beatWithinMeasure(forBeat: beat) }
    func startBeat(ofMeasure index: Int) -> Double { timeSignature.startBeat(ofMeasure: index) }

    /// Snaps a beat to the nearest subdivision of a quarter note.
    func quantize(_ beat: Double, subdivisionsPerBeat: Int) -> Double {
        guard subdivisionsPerBeat > 0 else { return beat }
        let step = 1.0 / Double(subdivisionsPerBeat)
        return (beat / step).rounded() * step
    }

    /// Beat positions where the metronome should click across `totalBeats`.
    func clickBeats(totalBeats: Double, subdivision: MetronomeSubdivision) -> [Double] {
        let step = 1.0 / Double(subdivision.clicksPerBeat)
        guard step > 0, totalBeats > 0 else { return [] }
        var beats: [Double] = []
        var beat = 0.0
        while beat < totalBeats - 1e-9 {
            beats.append(beat)
            beat += step
        }
        return beats
    }

    /// True when the click at `beat` falls on the downbeat of a measure.
    func isDownbeat(_ beat: Double) -> Bool {
        abs(beatWithinMeasure(beat)) < 1e-6
    }

    /// Length of the count-in in beats (spec §21: three beats before the song).
    static let countInBeats: Int = 3

    func countInDuration(beats: Int = TempoEngine.countInBeats) -> Double {
        Double(beats) * secondsPerBeat
    }
}
