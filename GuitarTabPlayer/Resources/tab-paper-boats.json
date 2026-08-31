import Foundation

/// Offline renderer that turns score events into mono PCM.
///
/// Rendering happens once per track, on a background queue, at 100% speed and concert pitch.
/// Practice speed and transposition are applied in real time by the audio graph, so the user can
/// move both without waiting for a re-render (spec §22, §23).
struct TrackRenderer: Sendable {

    struct Tone {
        var brightness: Double
        /// Seconds for the note to fall to 1/1000 of its initial amplitude. Expressed as a
        /// time rather than a per-sample coefficient so a low bass note does not ring
        /// dozens of times longer than a high lead note.
        var t60: Double
        var gain: Float
        var sustainBeats: Double     // how much the note rings past its written length
    }

    static func tone(for instrument: InstrumentType) -> Tone {
        switch instrument {
        case .leadGuitar:      return Tone(brightness: 0.78, t60: 2.6, gain: 0.55, sustainBeats: 0.6)
        case .rhythmGuitar:    return Tone(brightness: 0.58, t60: 1.4, gain: 0.42, sustainBeats: 0.25)
        case .acousticGuitar:  return Tone(brightness: 0.70, t60: 2.2, gain: 0.48, sustainBeats: 0.4)
        case .bass:            return Tone(brightness: 0.26, t60: 1.8, gain: 0.70, sustainBeats: 0.2)
        case .piano:           return Tone(brightness: 0.62, t60: 3.0, gain: 0.50, sustainBeats: 0.5)
        case .vocals:          return Tone(brightness: 0.45, t60: 1.0, gain: 0.45, sustainBeats: 0.3)
        case .drums, .other:   return Tone(brightness: 0.60, t60: 1.2, gain: 0.50, sustainBeats: 0.3)
        }
    }

    var sampleRate: Double
    var tempo: TempoEngine

    init(sampleRate: Double, tempo: TempoEngine) {
        self.sampleRate = sampleRate
        self.tempo = tempo
    }

    private var secondsPerBeat: Double { tempo.secondsPerBeat }

    func frameCount(forBeats beats: Double, tailSeconds: Double = 2.0) -> Int {
        max(1, Int((beats * secondsPerBeat + tailSeconds) * sampleRate))
    }

    private func frame(forBeat beat: Double) -> Int {
        Int(beat * secondsPerBeat * sampleRate)
    }

    // MARK: - Track

    func render(track: TabTrack, totalBeats: Double) -> [Float] {
        var buffer = [Float](repeating: 0, count: frameCount(forBeats: totalBeats))
        if track.instrument == .drums {
            renderDrums(track: track, into: &buffer)
        } else {
            renderPitched(track: track, into: &buffer)
        }
        Synth.softLimit(&buffer, ceiling: 0.85)
        return buffer
    }

    private func renderPitched(track: TabTrack, into buffer: inout [Float]) {
        let tone = Self.tone(for: track.instrument)

        for event in track.events {
            switch event {
            case .rest, .drum:
                continue

            case .bend(let bend):
                let base = bend.note
                guard let pitch = track.pitch(for: base) else { continue }
                let total = base.durationBeats
                let riseBeats = max(0.05, total * bend.riseFraction)
                pluck(&buffer, note: base, frequency: pitch.frequency,
                      durationBeats: riseBeats, tone: tone, gainScale: 1.0)
                let targetFrequency = pitch.frequency * pow(2.0, bend.semitones / 12.0)
                pluck(&buffer, note: base, frequency: targetFrequency,
                      durationBeats: max(0.05, total - riseBeats),
                      tone: tone, gainScale: 0.85, beatOffset: riseBeats)

            case .slide(let slide):
                let base = slide.note
                guard let from = track.pitch(for: base),
                      let to = track.tuning.pitch(string: base.string, fret: slide.targetFret + track.capo)
                else { continue }
                let half = base.durationBeats * 0.5
                pluck(&buffer, note: base, frequency: from.frequency,
                      durationBeats: half, tone: tone, gainScale: 1.0)
                pluck(&buffer, note: base, frequency: to.frequency,
                      durationBeats: base.durationBeats - half,
                      tone: tone, gainScale: 0.8, beatOffset: half)

            case .chord(let chordEvent):
                let ordered = chordEvent.notes.sorted { $0.string < $1.string }
                for (index, note) in ordered.enumerated() {
                    guard let pitch = track.pitch(for: note) else { continue }
                    let offset = Double(index) * chordEvent.strumSpreadBeats
                    // The chord's own velocity wins over the individual notes', so a soft
                    // strum stays soft across the whole shape.
                    let scale = chordEvent.velocity / max(note.velocity, 0.001) * 0.9
                    pluck(&buffer, note: note, frequency: pitch.frequency,
                          durationBeats: max(note.durationBeats, chordEvent.durationBeats),
                          tone: tone, gainScale: scale, beatOffset: offset)
                }

            default:
                for note in event.frettedNotes {
                    guard let pitch = track.pitch(for: note) else { continue }
                    // Hammer-ons and pull-offs are quieter than a picked note.
                    let attenuation: Float = (note.technique == .hammerOn || note.technique == .pullOff) ? 0.7 : 1.0
                    pluck(&buffer, note: note, frequency: pitch.frequency,
                          durationBeats: note.durationBeats, tone: tone, gainScale: attenuation)
                }
            }
        }
    }

    private func pluck(_ buffer: inout [Float],
                       note: NoteEvent,
                       frequency: Double,
                       durationBeats: Double,
                       tone: Tone,
                       gainScale: Float,
                       beatOffset: Double = 0) {
        let start = frame(forBeat: note.startBeat + beatOffset)
        guard start < buffer.count else { return }
        let ringBeats = note.technique == .palmMute ? min(durationBeats, 0.3) : durationBeats + tone.sustainBeats
        let amplitude = note.velocity * tone.gain * gainScale * (note.technique == .ghost ? 0.35 : 1.0)
        Synth.pluck(into: &buffer,
                    startFrame: start,
                    frequency: frequency,
                    durationSeconds: max(0.05, ringBeats * secondsPerBeat),
                    amplitude: amplitude,
                    sampleRate: sampleRate,
                    brightness: note.technique == .harmonic ? 0.95 : tone.brightness,
                    t60: tone.t60,
                    muted: note.technique == .palmMute)
    }

    private func renderDrums(track: TabTrack, into buffer: inout [Float]) {
        for event in track.events {
            guard let hit = event.drumEvent else { continue }
            let start = frame(forBeat: hit.startBeat)
            guard start < buffer.count else { continue }
            let amplitude = hit.velocity
            switch hit.piece {
            case .kick:        Synth.kick(into: &buffer, startFrame: start, amplitude: amplitude * 0.95, sampleRate: sampleRate)
            case .snare:       Synth.snare(into: &buffer, startFrame: start, amplitude: amplitude * 0.62, sampleRate: sampleRate)
            case .hiHatClosed: Synth.hiHat(into: &buffer, startFrame: start, amplitude: amplitude * 0.30, sampleRate: sampleRate, open: false)
            case .hiHatOpen:   Synth.hiHat(into: &buffer, startFrame: start, amplitude: amplitude * 0.28, sampleRate: sampleRate, open: true)
            case .crash:       Synth.cymbal(into: &buffer, startFrame: start, amplitude: amplitude * 0.42, sampleRate: sampleRate)
            case .ride:        Synth.hiHat(into: &buffer, startFrame: start, amplitude: amplitude * 0.26, sampleRate: sampleRate, open: true)
            case .tomHigh:     Synth.tom(into: &buffer, startFrame: start, amplitude: amplitude * 0.55, sampleRate: sampleRate, frequency: 220)
            case .tomMid:      Synth.tom(into: &buffer, startFrame: start, amplitude: amplitude * 0.55, sampleRate: sampleRate, frequency: 165)
            case .tomLow:      Synth.tom(into: &buffer, startFrame: start, amplitude: amplitude * 0.58, sampleRate: sampleRate, frequency: 110)
            }
        }
    }

    // MARK: - Metronome

    /// Click track covering the whole song, frame 0 == beat 0.
    func renderClickTrack(clicks: [MetronomeEngine.Click], totalBeats: Double) -> [Float] {
        var buffer = [Float](repeating: 0, count: frameCount(forBeats: totalBeats, tailSeconds: 0.5))
        for click in clicks where click.beat >= 0 {
            let start = frame(forBeat: click.beat)
            guard start < buffer.count else { continue }
            Synth.click(into: &buffer, startFrame: start,
                        amplitude: click.accent ? 0.85 : 0.55,
                        sampleRate: sampleRate, accent: click.accent)
        }
        return buffer
    }

    /// Count-in clicks rendered as their own buffer, scheduled before the song starts.
    func renderCountIn(beats: Int) -> [Float] {
        let frames = max(1, Int(Double(beats) * secondsPerBeat * sampleRate))
        var buffer = [Float](repeating: 0, count: frames)
        for index in 0..<beats {
            let start = Int(Double(index) * secondsPerBeat * sampleRate)
            Synth.click(into: &buffer, startFrame: start,
                        amplitude: index == 0 ? 0.9 : 0.7,
                        sampleRate: sampleRate, accent: index == 0)
        }
        return buffer
    }
}
