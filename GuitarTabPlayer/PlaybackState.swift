import Foundation

enum BacktrackSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case original
    case synthesized

    var id: String { rawValue }
    var displayName: String { self == .original ? "Original" : "Synthesized" }
}

enum MetronomeSubdivision: String, Codable, CaseIterable, Sendable, Identifiable {
    case quarter, eighth, sixteenth

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .sixteenth: return "Sixteenth"
        }
    }
    /// Clicks per quarter-note beat.
    var clicksPerBeat: Int {
        switch self {
        case .quarter: return 1
        case .eighth: return 2
        case .sixteenth: return 4
        }
    }
}

struct TrackPlaybackState: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var instrument: InstrumentType
    var isMuted: Bool
    var isSolo: Bool
    var volume: Float
    var pan: Float

    init(track: TabTrack) {
        self.id = track.id
        self.name = track.name
        self.instrument = track.instrument
        self.isMuted = track.isMuted
        self.isSolo = track.isSolo
        self.volume = track.volume
        self.pan = track.pan
    }
}

struct LoopRegion: Codable, Hashable, Sendable {
    var startBeat: Double
    var endBeat: Double

    var lengthBeats: Double { max(0, endBeat - startBeat) }
    var isValid: Bool { endBeat > startBeat + 0.001 }
}

/// The single source of truth every view binds to (spec §30).
struct PlaybackState: Codable, Hashable, Sendable {
    var isPlaying: Bool = false
    var isCountingIn: Bool = false
    var countInBeatsRemaining: Int = 0
    var currentBeat: Double = 0
    var totalBeats: Double = 0
    var tempo: Double = 120
    var speed: Double = 1.0
    var transpose: Int = 0
    var metronomeEnabled: Bool = false
    var metronomeVolume: Float = 0.7
    var metronomeSubdivision: MetronomeSubdivision = .quarter
    var countInEnabled: Bool = true
    var backtrackEnabled: Bool = true
    var backtrackSource: BacktrackSource = .synthesized
    var autoScrollEnabled: Bool = true
    var loopEnabled: Bool = false
    var loop: LoopRegion?
    var chordDisplayEnabled: Bool = true
    var masterVolume: Float = 0.9
    var tracks: [TrackPlaybackState] = []

    /// Seconds elapsed at the current practice speed.
    var currentTime: TimeInterval { beatsToSeconds(currentBeat) }
    var totalTime: TimeInterval { beatsToSeconds(totalBeats) }

    func beatsToSeconds(_ beats: Double) -> TimeInterval {
        guard tempo > 0, speed > 0 else { return 0 }
        return beats * 60.0 / (tempo * speed)
    }

    func secondsToBeats(_ seconds: TimeInterval) -> Double {
        seconds * (tempo * speed) / 60.0
    }

    var effectiveTempo: Double { tempo * speed }

    var hasSoloedTrack: Bool { tracks.contains { $0.isSolo } }

    func isAudible(_ track: TrackPlaybackState) -> Bool {
        if hasSoloedTrack { return track.isSolo && !track.isMuted }
        return !track.isMuted
    }

    var progress: Double {
        guard totalBeats > 0 else { return 0 }
        return min(1, max(0, currentBeat / totalBeats))
    }
}

extension TimeInterval {
    var clockString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
