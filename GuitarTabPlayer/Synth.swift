import Foundation

/// Small offline synthesis kit used to build the synthesized backtrack (spec §18.2).
///
/// Everything here writes into a caller-owned `[Float]` buffer, so a whole track can be
/// rendered on a background queue and handed to AVAudioEngine as a single PCM buffer.
enum Synth {

    /// Deterministic bipolar white noise. A per-voice seed keeps renders reproducible.
    struct Noise {
        private var state: UInt64

        init(seed: UInt64) {
            // Any non-zero state works; mixing avoids a weak first sample.
            self.state = seed &* 6364136223846793005 &+ 1442695040888963407
        }

        /// Uniform in roughly -1...1.
        mutating func next() -> Float {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            // Take the top 32 bits and reinterpret them as signed, so the noise is
            // symmetric around zero. Taking 31 bits would give a +0.5 DC offset, which
            // a Karplus-Strong loop then circulates for the whole life of the note.
            let bits = UInt32(truncatingIfNeeded: state >> 32)
            return Float(Int32(bitPattern: bits)) / Float(Int32.max)
        }
    }

    // MARK: - Plucked string (Karplus-Strong)

    /// Renders a plucked string into `buffer` starting at `startFrame`.
    ///
    /// The loop delay is `N + frac + 0.5` samples: `N` slots, a fractional tap, and the half
    /// sample contributed by the averaging filter. Solving that for the requested period is
    /// what keeps the upper register in tune — an integer-only delay line is up to half a
    /// sample short, which at the 12th fret is tens of cents flat.
    static func pluck(into buffer: inout [Float],
                      startFrame: Int,
                      frequency: Double,
                      durationSeconds: Double,
                      amplitude: Float,
                      sampleRate: Double,
                      brightness: Double = 0.5,
                      t60: Double = 2.0,
                      muted: Bool = false) {
        guard frequency > 20, durationSeconds > 0, startFrame >= 0, startFrame < buffer.count else { return }

        let period = max(2.5, sampleRate / frequency)
        let ideal = period - 0.5                       // the loop filter adds half a sample
        let delayLength = max(2, Int(ideal))
        let frac = Float(ideal - Double(delayLength))

        // Amplitude falls to 1/1000 after t60 seconds. The gain is applied once per traversal
        // of the delay line, so it has to be derived from the period — otherwise a low bass
        // note (long delay line) rings an order of magnitude longer than a high one.
        let ringSeconds = max(0.05, muted ? t60 * 0.22 : t60)
        let decay = Float(pow(0.001, Double(delayLength) / (ringSeconds * sampleRate)))

        // Excitation: noise shaped by `brightness` (darker = more low-passed noise).
        var noise = Noise(seed: UInt64(delayLength) &* 0x9E3779B97F4A7C15 &+ UInt64(startFrame))
        var delayLine = [Float](repeating: 0, count: delayLength)
        var lowpassed: Float = 0
        let mix = Float(max(0.05, min(1.0, brightness)))
        for index in 0..<delayLength {
            lowpassed = lowpassed * (1 - mix) + noise.next() * mix
            delayLine[index] = lowpassed
        }

        let totalFrames = min(Int(durationSeconds * sampleRate), buffer.count - startFrame)
        guard totalFrames > 0 else { return }

        // Short fades so a note that is cut off does not click.
        let releaseFrames = min(totalFrames, Int(0.02 * sampleRate))
        let attackFrames = min(totalFrames, 32)

        var pointer = 0
        var previous: Float = delayLine[delayLength - 1]

        for index in 0..<totalFrames {
            let current = delayLine[pointer]
            let tap = current * (1 - frac) + previous * frac        // fractional delay
            let filtered = (tap + previous) * 0.5 * decay           // one-pole loop filter
            delayLine[pointer] = filtered
            previous = tap
            pointer += 1
            if pointer == delayLength { pointer = 0 }

            var envelope: Float = 1
            let remaining = totalFrames - index
            if remaining < releaseFrames { envelope = Float(remaining) / Float(max(1, releaseFrames)) }
            if index < attackFrames { envelope *= Float(index) / Float(max(1, attackFrames)) }

            buffer[startFrame + index] += tap * amplitude * envelope
        }
    }

    // MARK: - Drums

    static func kick(into buffer: inout [Float], startFrame: Int, amplitude: Float, sampleRate: Double) {
        guard startFrame >= 0, startFrame < buffer.count else { return }
        let frames = min(Int(0.35 * sampleRate), buffer.count - startFrame)
        guard frames > 0 else { return }
        var phase = 0.0
        for index in 0..<frames {
            let t = Double(index) / sampleRate
            let frequency = 52.0 + 95.0 * exp(-t * 34.0)
            phase += 2 * .pi * frequency / sampleRate
            let envelope = exp(-t * 9.0)
            let click = index < 60 ? 0.35 * exp(-Double(index) / 18.0) : 0
            buffer[startFrame + index] += Float(sin(phase) * envelope + click) * amplitude
        }
    }

    static func snare(into buffer: inout [Float], startFrame: Int, amplitude: Float, sampleRate: Double) {
        guard startFrame >= 0, startFrame < buffer.count else { return }
        let frames = min(Int(0.22 * sampleRate), buffer.count - startFrame)
        guard frames > 0 else { return }
        var noise = Noise(seed: 0x9E3779B97F4A7C15 &+ UInt64(startFrame))
        var phase = 0.0
        var lowState: Float = 0
        for index in 0..<frames {
            let t = Double(index) / sampleRate
            let white = noise.next()
            lowState = lowState * 0.55 + white * 0.45
            let bright = white - lowState          // crude high-pass
            phase += 2 * .pi * 185.0 / sampleRate
            let body = Float(sin(phase)) * 0.4
            let envelope = Float(exp(-t * 26.0))
            buffer[startFrame + index] += (bright * 0.9 + body) * envelope * amplitude
        }
    }

    static func hiHat(into buffer: inout [Float], startFrame: Int, amplitude: Float, sampleRate: Double, open: Bool) {
        guard startFrame >= 0, startFrame < buffer.count else { return }
        let decay = open ? 8.0 : 42.0
        let frames = min(Int((open ? 0.45 : 0.09) * sampleRate), buffer.count - startFrame)
        guard frames > 0 else { return }
        var noise = Noise(seed: 0xD1B54A32D192ED03 &+ UInt64(startFrame))
        var lowState: Float = 0
        for index in 0..<frames {
            let t = Double(index) / sampleRate
            let white = noise.next()
            lowState = lowState * 0.72 + white * 0.28
            let bright = white - lowState
            buffer[startFrame + index] += bright * Float(exp(-t * decay)) * amplitude * 0.7
        }
    }

    static func cymbal(into buffer: inout [Float], startFrame: Int, amplitude: Float, sampleRate: Double) {
        guard startFrame >= 0, startFrame < buffer.count else { return }
        let frames = min(Int(1.2 * sampleRate), buffer.count - startFrame)
        guard frames > 0 else { return }
        var noise = Noise(seed: 0xA24BAED4963EE407 &+ UInt64(startFrame))
        var lowState: Float = 0
        for index in 0..<frames {
            let t = Double(index) / sampleRate
            let white = noise.next()
            lowState = lowState * 0.85 + white * 0.15
            let bright = white - lowState
            buffer[startFrame + index] += bright * Float(exp(-t * 3.2)) * amplitude * 0.55
        }
    }

    static func tom(into buffer: inout [Float], startFrame: Int, amplitude: Float, sampleRate: Double, frequency: Double) {
        guard startFrame >= 0, startFrame < buffer.count else { return }
        let frames = min(Int(0.4 * sampleRate), buffer.count - startFrame)
        guard frames > 0 else { return }
        var phase = 0.0
        for index in 0..<frames {
            let t = Double(index) / sampleRate
            let f = frequency * (1.0 + 0.35 * exp(-t * 18.0))
            phase += 2 * .pi * f / sampleRate
            buffer[startFrame + index] += Float(sin(phase) * exp(-t * 11.0)) * amplitude
        }
    }

    // MARK: - Metronome click

    static func click(into buffer: inout [Float], startFrame: Int, amplitude: Float, sampleRate: Double, accent: Bool) {
        guard startFrame >= 0, startFrame < buffer.count else { return }
        let frames = min(Int(0.045 * sampleRate), buffer.count - startFrame)
        guard frames > 0 else { return }
        let frequency = accent ? 1760.0 : 1174.0
        var phase = 0.0
        for index in 0..<frames {
            let t = Double(index) / sampleRate
            phase += 2 * .pi * frequency / sampleRate
            buffer[startFrame + index] += Float(sin(phase) * exp(-t * 110.0)) * amplitude
        }
    }

    // MARK: - Utilities

    /// Removes any residual DC, then peak-normalises and applies a gentle soft clip so a dense
    /// mix never wraps around.
    static func softLimit(_ buffer: inout [Float], ceiling: Float = 0.92) {
        guard !buffer.isEmpty else { return }

        var sum: Float = 0
        for sample in buffer { sum += sample }
        let mean = sum / Float(buffer.count)
        if abs(mean) > 1e-5 {
            for index in buffer.indices { buffer[index] -= mean }
        }

        var peak: Float = 0
        for sample in buffer { peak = max(peak, abs(sample)) }
        guard peak > 0 else { return }
        let gain = peak > ceiling ? ceiling / peak : 1
        for index in buffer.indices {
            buffer[index] = tanh(buffer[index] * gain * 1.08) * 0.94
        }
    }
}
