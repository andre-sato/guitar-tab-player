import Foundation
import Observation

/// The musical timeline's owner (ADR-005).
///
/// Views never derive position from their own animation clock: they read `state.currentBeat`,
/// which is computed from the audio graph's sample clock. Tab, chords, cursor and metronome are
/// therefore always describing the same instant.
@Observable
@MainActor
final class PlaybackEngine {

    // MARK: - Published state

    private(set) var state = PlaybackState()
    private(set) var document: TabDocument?          // transposed view used by the UI
    private(set) var layout: TabLayout = .empty
    private(set) var selectedTrackId: String?
    private(set) var activeChord: Chord?
    private(set) var activeSection: SongSection?
    private(set) var transpositionIsApproximate = false
    private(set) var lastError: String?

    /// Emitted whenever the user or the engine jumps the playhead, so the sheet can re-centre.
    private(set) var seekGeneration: Int = 0

    // MARK: - Dependencies

    private let audio: AudioService
    private var baseDocument: TabDocument?
    private var tempoEngine = TempoEngine(tempo: 120)
    private var ticker: Task<Void, Never>?
    private var isPreparing = false

    var onPlaybackFinished: (() -> Void)?

    init(audio: AudioService = AudioService()) {
        self.audio = audio
    }

    // MARK: - Loading

    func load(document newDocument: TabDocument, preferences: UserPreferences = .default) async {
        stopTicker()
        audio.stop()

        baseDocument = newDocument
        tempoEngine = TempoEngine(tempo: newDocument.tempo, timeSignature: newDocument.timeSignature)

        var newState = PlaybackState()
        newState.tempo = newDocument.tempo
        newState.totalBeats = newDocument.totalBeats
        newState.speed = preferences.defaultSpeed
        newState.metronomeEnabled = preferences.metronomeEnabled
        newState.metronomeVolume = preferences.metronomeVolume
        newState.metronomeSubdivision = preferences.metronomeSubdivision
        newState.countInEnabled = preferences.countInEnabled
        newState.backtrackEnabled = preferences.backtrackEnabled
        newState.autoScrollEnabled = preferences.autoScrollEnabled
        newState.chordDisplayEnabled = preferences.chordDisplayEnabled
        newState.backtrackSource = newDocument.hasOriginalAudio ? .original : .synthesized
        newState.transpose = 0
        newState.tracks = newDocument.tracks.map(TrackPlaybackState.init(track:))
        state = newState

        selectedTrackId = newDocument.tracks.first(where: { $0.instrument.isFretted })?.id
            ?? newDocument.tracks.first?.id

        rebuildDerivedState()

        isPreparing = true
        do {
            try await audio.prepare(document: newDocument, subdivision: state.metronomeSubdivision)
            audio.setSpeed(state.speed)
            audio.setTranspose(state.transpose)
            audio.backtrackEnabled = state.backtrackEnabled
            audio.metronomeEnabled = state.metronomeEnabled
            audio.metronomeVolume = state.metronomeVolume
            audio.masterVolume = state.masterVolume
            audio.updateTracks(state.tracks)
            lastError = nil
        } catch {
            // A tab without audio must remain fully usable (spec §42).
            lastError = error.localizedDescription
        }
        isPreparing = false
    }

    func unload() {
        stopTicker()
        audio.stop()
        baseDocument = nil
        document = nil
        layout = .empty
        state = PlaybackState()
    }

    // MARK: - Derived state

    private func rebuildDerivedState() {
        guard let base = baseDocument else { document = nil; layout = .empty; return }
        let transposed = TranspositionEngine.transpose(base, by: state.transpose)
        document = transposed
        transpositionIsApproximate = state.transpose != 0
            && !TranspositionEngine.isFullyRepresentable(base, by: state.transpose)
        layout = TabEngine.buildLayout(document: transposed, trackId: selectedTrackId)
        updateActiveMarkers()
    }

    private func updateActiveMarkers() {
        guard let document else { activeChord = nil; activeSection = nil; return }
        activeChord = TabEngine.chord(in: document.chords, at: state.currentBeat)
        activeSection = TabEngine.section(in: document.sections, at: state.currentBeat)
    }

    // MARK: - Transport

    func togglePlayPause() {
        state.isPlaying ? pause() : play()
    }

    func play() {
        guard baseDocument != nil, !state.isPlaying else { return }

        // Un-pausing picks the transport back up where it stopped: no re-slicing of the
        // buffers, and no second count-in.
        if audio.isPaused, state.currentBeat < state.totalBeats - 0.01 {
            audio.resume()
            state.isPlaying = true
            startTicker()
            return
        }

        let from = state.currentBeat >= state.totalBeats - 0.01 ? 0 : state.currentBeat
        do {
            try audio.play(fromBeat: from, countIn: state.countInEnabled, tempo: state.tempo)
            state.isPlaying = true
            state.isCountingIn = state.countInEnabled
            state.countInBeatsRemaining = state.countInEnabled ? TempoEngine.countInBeats : 0
            startTicker()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func pause() {
        guard state.isPlaying else { return }
        audio.pause()
        state.isPlaying = false
        state.isCountingIn = false
        stopTicker()
    }

    func stop() {
        audio.stop()
        state.isPlaying = false
        state.isCountingIn = false
        state.countInBeatsRemaining = 0
        stopTicker()
        seek(toBeat: 0)
    }

    func seek(toBeat beat: Double) {
        let clamped = min(max(0, beat), state.totalBeats)
        state.currentBeat = clamped
        seekGeneration &+= 1
        updateActiveMarkers()

        if state.isPlaying {
            do {
                // A seek during playback never re-arms the count-in.
                try audio.play(fromBeat: clamped, countIn: false, tempo: state.tempo)
                state.isCountingIn = false
                state.countInBeatsRemaining = 0
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func seek(toTime seconds: TimeInterval) {
        seek(toBeat: state.secondsToBeats(seconds))
    }

    func skip(measures: Int) {
        let bar = tempoEngine.timeSignature.barLengthInBeats
        let current = tempoEngine.measureIndex(forBeat: state.currentBeat)
        let target = max(0, current + measures)
        seek(toBeat: Double(target) * bar)
    }

    // MARK: - Parameters

    func setSpeed(_ speed: Double) {
        state.speed = max(0.25, min(2.0, speed))
        audio.setSpeed(state.speed)
    }

    func setTranspose(_ semitones: Int) {
        let clamped = max(TranspositionEngine.range.lowerBound, min(TranspositionEngine.range.upperBound, semitones))
        guard clamped != state.transpose else { return }
        state.transpose = clamped
        audio.setTranspose(clamped)
        rebuildDerivedState()
    }

    func setMetronome(enabled: Bool) {
        state.metronomeEnabled = enabled
        audio.metronomeEnabled = enabled
    }

    func setMetronomeVolume(_ volume: Float) {
        state.metronomeVolume = volume
        audio.metronomeVolume = volume
    }

    func setMetronomeSubdivision(_ subdivision: MetronomeSubdivision) {
        state.metronomeSubdivision = subdivision
        guard let base = baseDocument else { return }
        Task { await audio.updateMetronome(subdivision: subdivision, document: base) }
    }

    func setCountIn(enabled: Bool) { state.countInEnabled = enabled }

    func setBacktrack(enabled: Bool) {
        state.backtrackEnabled = enabled
        audio.backtrackEnabled = enabled
    }

    func setBacktrackSource(_ source: BacktrackSource) {
        state.backtrackSource = source
    }

    func setAutoScroll(enabled: Bool) { state.autoScrollEnabled = enabled }
    func setChordDisplay(enabled: Bool) { state.chordDisplayEnabled = enabled }

    func setMasterVolume(_ volume: Float) {
        state.masterVolume = volume
        audio.masterVolume = volume
    }

    // MARK: - Tracks

    func selectTrack(_ trackId: String) {
        selectedTrackId = trackId
        rebuildDerivedState()
    }

    func toggleMute(trackId: String) {
        guard let index = state.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        state.tracks[index].isMuted.toggle()
        audio.updateTracks(state.tracks)
    }

    func toggleSolo(trackId: String) {
        guard let index = state.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        state.tracks[index].isSolo.toggle()
        audio.updateTracks(state.tracks)
    }

    func clearSolos() {
        for index in state.tracks.indices { state.tracks[index].isSolo = false }
        audio.updateTracks(state.tracks)
    }

    func setVolume(_ volume: Float, trackId: String) {
        guard let index = state.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        state.tracks[index].volume = max(0, min(1, volume))
        audio.updateTracks(state.tracks)
    }

    func setPan(_ pan: Float, trackId: String) {
        guard let index = state.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        state.tracks[index].pan = max(-1, min(1, pan))
        audio.updateTracks(state.tracks)
    }

    // MARK: - Loop

    func setLoopEnabled(_ enabled: Bool) {
        state.loopEnabled = enabled
        if enabled, state.loop == nil {
            let bar = tempoEngine.timeSignature.barLengthInBeats
            let start = Double(tempoEngine.measureIndex(forBeat: state.currentBeat)) * bar
            state.loop = LoopRegion(startBeat: start, endBeat: min(state.totalBeats, start + bar * 2))
        }
    }

    func setLoopStart(_ beat: Double? = nil) {
        let value = beat ?? state.currentBeat
        var region = state.loop ?? LoopRegion(startBeat: value, endBeat: min(state.totalBeats, value + tempoEngine.timeSignature.barLengthInBeats))
        region.startBeat = value
        if region.endBeat <= region.startBeat { region.endBeat = min(state.totalBeats, value + tempoEngine.timeSignature.barLengthInBeats) }
        state.loop = region
    }

    func setLoopEnd(_ beat: Double? = nil) {
        let value = beat ?? state.currentBeat
        var region = state.loop ?? LoopRegion(startBeat: max(0, value - tempoEngine.timeSignature.barLengthInBeats), endBeat: value)
        region.endBeat = value
        if region.endBeat <= region.startBeat { region.startBeat = max(0, value - tempoEngine.timeSignature.barLengthInBeats) }
        state.loop = region
    }

    func clearLoop() {
        state.loop = nil
        state.loopEnabled = false
    }

    // MARK: - Practice state

    func restore(practice: PracticeSnapshot) {
        setSpeed(practice.speed)
        setTranspose(practice.transpose)
        for mutedId in practice.mutedTrackIds {
            if let index = state.tracks.firstIndex(where: { $0.id == mutedId }) {
                state.tracks[index].isMuted = true
            }
        }
        audio.updateTracks(state.tracks)
        seek(toBeat: practice.beat)
    }

    var practiceSnapshot: PracticeSnapshot {
        PracticeSnapshot(beat: state.currentBeat,
                         speed: state.speed,
                         transpose: state.transpose,
                         mutedTrackIds: state.tracks.filter(\.isMuted).map(\.id))
    }

    // MARK: - Ticker

    /// A main-actor task rather than a `Timer`: it needs no `assumeIsolated`, it is cancelled
    /// deterministically, and it cannot outlive the engine the way a run-loop timer can.
    private func startTicker() {
        stopTicker()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 16_000_000)   // ~60 Hz
                guard !Task.isCancelled, let self else { return }
                self.tick()
            }
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    private func tick() {
        guard state.isPlaying else { return }

        if state.isCountingIn {
            let remaining = audio.countInRemaining(tempo: state.tempo)
            if remaining <= 0 {
                state.isCountingIn = false
                state.countInBeatsRemaining = 0
            } else {
                let beats = Int(ceil(remaining / tempoEngine.secondsPerBeat))
                state.countInBeatsRemaining = min(TempoEngine.countInBeats, max(1, beats))
                return
            }
        }

        guard let beat = audio.currentBeat(tempo: state.tempo) else { return }
        state.currentBeat = min(max(0, beat), state.totalBeats)
        updateActiveMarkers()

        if state.loopEnabled, let loop = state.loop, loop.isValid, state.currentBeat >= loop.endBeat - 0.01 {
            seek(toBeat: loop.startBeat)
            return
        }

        if beat >= state.totalBeats - 0.01 {
            pause()
            state.currentBeat = state.totalBeats
            onPlaybackFinished?()
        }
    }
}

/// Where the user left off (spec §36).
struct PracticeSnapshot: Codable, Hashable, Sendable {
    var beat: Double
    var speed: Double
    var transpose: Int
    var mutedTrackIds: [String]
}
