import Foundation
import AVFoundation

/// Owns the AVAudioEngine graph (spec §14, §37).
///
///     pitched trackPlayers ─┐
///     clockPlayer (silent) ─┼─▶ pitchedMixer ─▶ timePitchMusic (rate + pitch) ─┐
///                                                                              ├─▶ main ─▶ out
///     drum trackPlayers ────┐                                                  │
///     clickPlayer ──────────┼─▶ flatMixer ────▶ timePitchFlat (rate only) ─────┘
///     countInPlayer ────────┘
///
/// `timePitchMusic` applies practice speed (rate) and transposition (pitch) in real time, which
/// is why changing either never forces a re-render. Drums, the metronome and the count-in run
/// through `timePitchFlat`, which gets the same rate but no pitch shift: transposing a song must
/// not detune the kick drum or the click.
///
/// The silent `clockPlayer` rides the *music* chain so its sample clock has exactly the same
/// latency as the pitched instruments. It is the musical timeline, and it keeps ticking even
/// when every track is muted or the backtrack is switched off entirely (spec §19).
@MainActor
final class AudioService {

    // MARK: - Types

    enum AudioError: LocalizedError {
        case engineFailed(String)
        case notPrepared
        case nothingToPlay

        var errorDescription: String? {
            switch self {
            case .engineFailed(let message): return "Audio engine could not start: \(message)"
            case .notPrepared: return "No song is loaded."
            case .nothingToPlay: return "There is nothing left to play from here."
            }
        }
    }

    struct PreparedSong {
        var documentId: String
        var tempo: Double
        var totalBeats: Double
        var trackBuffers: [String: AVAudioPCMBuffer]
        var clickBuffer: AVAudioPCMBuffer
        var countInBuffer: AVAudioPCMBuffer
        var clockBuffer: AVAudioPCMBuffer
    }

    // MARK: - Graph

    private let engine = AVAudioEngine()
    private let pitchedMixer = AVAudioMixerNode()
    private let flatMixer = AVAudioMixerNode()
    private let timePitchMusic = AVAudioUnitTimePitch()
    private let timePitchFlat = AVAudioUnitTimePitch()
    private let clickPlayer = AVAudioPlayerNode()
    private let countInPlayer = AVAudioPlayerNode()
    private let clockPlayer = AVAudioPlayerNode()
    private var trackPlayers: [String: AVAudioPlayerNode] = [:]

    /// Matches the hardware session so the graph never resamples. Frozen once the graph is built.
    private(set) var sampleRate: Double = 44_100

    private var monoFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }
    private var stereoFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    }

    private var prepared: PreparedSong?
    private var isGraphBuilt = false

    // MARK: - Transport bookkeeping

    private var startBeat: Double = 0
    private var countInSeconds: Double = 0
    private(set) var isRunning = false
    private(set) var isPaused = false

    var backtrackEnabled = true { didSet { applyTrackGains() } }
    var metronomeEnabled = false { didSet { applyMetronomeGain() } }
    var metronomeVolume: Float = 0.7 { didSet { applyMetronomeGain() } }
    var masterVolume: Float = 0.9 { didSet { engine.mainMixerNode.outputVolume = masterVolume } }

    private var trackStates: [String: TrackPlaybackState] = [:]
    private var trackInstruments: [String: InstrumentType] = [:]

    // MARK: - Session

    func configureSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredIOBufferDuration(0.005)   // low latency (spec §39)
            try session.setActive(true)
            // Match the hardware rate, but only while the graph can still be built around it.
            if !isGraphBuilt, session.sampleRate > 0 { sampleRate = session.sampleRate }
        } catch {
            NSLog("GuitarTabPlayer: audio session setup failed - \(error.localizedDescription)")
        }
        #endif
    }

    /// Wall-clock delay between a rendered sample and the listener hearing it.
    private var outputLatency: Double {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        return session.outputLatency + session.ioBufferDuration
        #else
        return 0
        #endif
    }

    // MARK: - Graph construction

    private func buildGraphIfNeeded() {
        guard !isGraphBuilt else { return }
        let mono = monoFormat
        let stereo = stereoFormat

        engine.attach(pitchedMixer)
        engine.attach(flatMixer)
        engine.attach(timePitchMusic)
        engine.attach(timePitchFlat)
        engine.attach(clickPlayer)
        engine.attach(countInPlayer)
        engine.attach(clockPlayer)

        engine.connect(pitchedMixer, to: timePitchMusic, format: stereo)
        engine.connect(timePitchMusic, to: engine.mainMixerNode, format: stereo)

        engine.connect(flatMixer, to: timePitchFlat, format: stereo)
        engine.connect(timePitchFlat, to: engine.mainMixerNode, format: stereo)

        engine.connect(clickPlayer, to: flatMixer, format: mono)
        engine.connect(countInPlayer, to: flatMixer, format: mono)
        engine.connect(clockPlayer, to: pitchedMixer, format: mono)

        clockPlayer.volume = 0
        countInPlayer.volume = 1
        applyMetronomeGain()
        engine.mainMixerNode.outputVolume = masterVolume

        isGraphBuilt = true
    }

    private func ensurePlayer(for trackId: String, instrument: InstrumentType) -> AVAudioPlayerNode {
        if let existing = trackPlayers[trackId] { return existing }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        // Unpitched instruments bypass the pitch shifter so transposing never detunes them.
        engine.connect(player, to: instrument == .drums ? flatMixer : pitchedMixer, format: monoFormat)
        trackPlayers[trackId] = player
        return player
    }

    private func applyMetronomeGain() {
        // The gate lives on the click player, not on the mixer, so the count-in stays audible
        // with the metronome switched off (spec §29: the two toggles are independent).
        clickPlayer.volume = metronomeEnabled ? metronomeVolume : 0
    }

    private func startEngineIfNeeded() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        do { try engine.start() }
        catch { throw AudioError.engineFailed(error.localizedDescription) }
    }

    // MARK: - Preparation

    /// Renders the synthesized backtrack and the click track for `document`.
    /// The heavy DSP runs off the main thread; only buffer creation happens here (spec §39).
    func prepare(document: TabDocument, subdivision: MetronomeSubdivision) async throws {
        configureSession()
        buildGraphIfNeeded()

        let rate = sampleRate
        let tempo = document.tempo
        let timeSignature = document.timeSignature
        let totalBeats = document.totalBeats
        let tracks = document.tracks

        var rendered: (tracks: [String: [Float]], click: [Float], countIn: [Float], clockFrames: Int) =
        await Task.detached(priority: .userInitiated) {
            let tempoEngine = TempoEngine(tempo: tempo, timeSignature: timeSignature)
            let renderer = TrackRenderer(sampleRate: rate, tempo: tempoEngine)
            var trackSamples: [String: [Float]] = [:]
            for track in tracks {
                trackSamples[track.id] = renderer.render(track: track, totalBeats: totalBeats)
            }
            let metronome = MetronomeEngine(tempo: tempoEngine, subdivision: subdivision)
            let click = renderer.renderClickTrack(
                clicks: metronome.clicks(from: 0, to: totalBeats), totalBeats: totalBeats)
            let countIn = renderer.renderCountIn(beats: TempoEngine.countInBeats)
            let clockFrames = renderer.frameCount(forBeats: totalBeats, tailSeconds: 2.0)
            return (trackSamples, click, countIn, clockFrames)
        }.value

        trackInstruments = Dictionary(tracks.map { ($0.id, $0.instrument) },
                                      uniquingKeysWith: { _, latest in latest })

        var buffers: [String: AVAudioPCMBuffer] = [:]
        for trackId in Array(rendered.tracks.keys) {
            guard let samples = rendered.tracks[trackId] else { continue }
            let buffer = makeBuffer(from: samples)
            // Drop the Swift array as soon as its PCM copy exists: a five-track song otherwise
            // holds two full-length float buffers per track at once.
            rendered.tracks[trackId] = nil
            guard let buffer else { continue }
            buffers[trackId] = buffer
            _ = ensurePlayer(for: trackId, instrument: trackInstruments[trackId] ?? .other)
        }

        guard let click = makeBuffer(from: rendered.click),
              let countIn = makeBuffer(from: rendered.countIn),
              let clock = makeBuffer(from: [Float](repeating: 0, count: rendered.clockFrames))
        else { throw AudioError.notPrepared }

        // Drop players belonging to a previous song.
        for (trackId, player) in trackPlayers where buffers[trackId] == nil {
            player.stop()
            engine.detach(player)
            trackPlayers.removeValue(forKey: trackId)
        }

        prepared = PreparedSong(documentId: document.id,
                                tempo: document.tempo,
                                totalBeats: totalBeats,
                                trackBuffers: buffers,
                                clickBuffer: click,
                                countInBuffer: countIn,
                                clockBuffer: clock)

        trackStates = Dictionary(document.tracks.map { ($0.id, TrackPlaybackState(track: $0)) },
                                 uniquingKeysWith: { _, latest in latest })
        applyTrackGains()
        try startEngineIfNeeded()
    }

    /// Re-renders the click track when the subdivision changes, and reschedules it so the change
    /// is audible immediately rather than at the next seek (spec §20).
    func updateMetronome(subdivision: MetronomeSubdivision, document: TabDocument) async {
        guard prepared != nil else { return }
        let rate = sampleRate
        let tempo = document.tempo
        let timeSignature = document.timeSignature
        let totalBeats = document.totalBeats

        let samples: [Float] = await Task.detached(priority: .userInitiated) {
            let tempoEngine = TempoEngine(tempo: tempo, timeSignature: timeSignature)
            let renderer = TrackRenderer(sampleRate: rate, tempo: tempoEngine)
            let metronome = MetronomeEngine(tempo: tempoEngine, subdivision: subdivision)
            return renderer.renderClickTrack(clicks: metronome.clicks(from: 0, to: totalBeats), totalBeats: totalBeats)
        }.value

        guard let buffer = makeBuffer(from: samples) else { return }
        prepared?.clickBuffer = buffer

        guard isRunning, !isPaused else { return }
        let beat = max(0, currentBeat(tempo: tempo) ?? 0)
        let offset = AVAudioFramePosition(beat * (60.0 / max(1, tempo)) * sampleRate)
        clickPlayer.stop()
        if let segment = slice(buffer, fromFrame: offset) {
            clickPlayer.scheduleBuffer(segment, at: nil, options: [])
            clickPlayer.play()
        }
    }

    private func makeBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            channel.update(from: base, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    /// Copies the tail of `buffer` from `offset`.
    ///
    /// A copy, not a view: `AVAudioPCMBuffer` has no sub-range scheduling for buffers, and a
    /// no-copy buffer list would have to outlive the schedule. Starting at frame 0 — the common
    /// case for play and for a loop that begins at the top — returns the original with no work.
    private func slice(_ buffer: AVAudioPCMBuffer, fromFrame offset: AVAudioFramePosition) -> AVAudioPCMBuffer? {
        let start = max(0, min(Int(offset), Int(buffer.frameLength)))
        let length = Int(buffer.frameLength) - start
        guard length > 0 else { return nil }
        if start == 0 { return buffer }
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: AVAudioFrameCount(length)),
              let source = buffer.floatChannelData?[0], let destination = copy.floatChannelData?[0]
        else { return nil }
        destination.update(from: source.advanced(by: start), count: length)
        copy.frameLength = AVAudioFrameCount(length)
        return copy
    }

    private func silenceBuffer(seconds: Double) -> AVAudioPCMBuffer? {
        let frames = Int(seconds * sampleRate)
        guard frames > 0 else { return nil }
        return makeBuffer(from: [Float](repeating: 0, count: frames))
    }

    // MARK: - Transport

    /// Starts playback at `beat`. Every node is scheduled against one shared start time so the
    /// backtrack, the click, the count-in and the clock stay sample-aligned.
    func play(fromBeat beat: Double, countIn: Bool, tempo: Double) throws {
        guard let song = prepared else { throw AudioError.notPrepared }
        try startEngineIfNeeded()

        stopNodes()

        let secondsPerBeat = 60.0 / max(1, tempo)
        let offsetFrames = AVAudioFramePosition(max(0, beat) * secondsPerBeat * sampleRate)
        startBeat = max(0, beat)
        countInSeconds = countIn ? Double(TempoEngine.countInBeats) * secondsPerBeat : 0

        // The clock decides whether there is anything left to play at all.
        guard let clockSegment = slice(song.clockBuffer, fromFrame: offsetFrames) else {
            throw AudioError.nothingToPlay
        }

        // The silence prefix has to reach every node or none of them, otherwise the tracks would
        // start three beats before the click.
        let leadIn: AVAudioPCMBuffer? = countIn ? silenceBuffer(seconds: countInSeconds) : nil
        let hasCountIn = countIn && leadIn != nil
        if countIn && leadIn == nil {
            NSLog("GuitarTabPlayer: count-in skipped, zero-length at \(tempo) BPM")
            countInSeconds = 0
        }

        for (trackId, player) in trackPlayers {
            guard let buffer = song.trackBuffers[trackId],
                  let segment = slice(buffer, fromFrame: offsetFrames) else { continue }
            if let leadIn { player.scheduleBuffer(leadIn, at: nil, options: []) }
            player.scheduleBuffer(segment, at: nil, options: [])
        }

        if hasCountIn { countInPlayer.scheduleBuffer(song.countInBuffer, at: nil, options: []) }
        if let leadIn { clickPlayer.scheduleBuffer(leadIn, at: nil, options: []) }
        if let clickSegment = slice(song.clickBuffer, fromFrame: offsetFrames) {
            clickPlayer.scheduleBuffer(clickSegment, at: nil, options: [])
        }

        if let leadIn { clockPlayer.scheduleBuffer(leadIn, at: nil, options: []) }
        clockPlayer.scheduleBuffer(clockSegment, at: nil, options: [])

        startAllPlayers()
        isRunning = true
        isPaused = false
    }

    /// One shared host time keeps every node phase-locked.
    private func startAllPlayers() {
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.08))
        for player in trackPlayers.values { player.play(at: startTime) }
        clickPlayer.play(at: startTime)
        countInPlayer.play(at: startTime)
        clockPlayer.play(at: startTime)
    }

    func pause() {
        for player in trackPlayers.values { player.pause() }
        clickPlayer.pause()
        countInPlayer.pause()
        clockPlayer.pause()
        isRunning = false
        isPaused = true
    }

    /// Picks up exactly where `pause()` left off — no re-slicing and no second count-in.
    func resume() {
        guard prepared != nil, isPaused else { return }
        try? startEngineIfNeeded()
        startAllPlayers()
        isRunning = true
        isPaused = false
    }

    func stop() {
        stopNodes()
        isRunning = false
        isPaused = false
    }

    private func stopNodes() {
        for player in trackPlayers.values { player.stop() }
        clickPlayer.stop()
        countInPlayer.stop()
        clockPlayer.stop()
    }

    /// Musical position, derived from the silent clock node.
    ///
    /// `playerTime` counts frames the *player* produced. A downstream time-pitch unit running at
    /// `rate` consumes `rate` input frames per output frame, so this is score time regardless of
    /// the practice speed. The output latency is subtracted so the cursor matches what is being
    /// heard rather than what has just been rendered.
    func currentBeat(tempo: Double) -> Double? {
        guard let nodeTime = clockPlayer.lastRenderTime,
              let playerTime = clockPlayer.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else { return nil }
        let latencyInScoreTime = outputLatency * Double(timePitchMusic.rate)
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate - countInSeconds - latencyInScoreTime
        return startBeat + elapsed / (60.0 / max(1, tempo))
    }

    /// Seconds still to run in the count-in, or 0 when the song proper has started.
    func countInRemaining(tempo: Double) -> Double {
        guard countInSeconds > 0 else { return 0 }
        guard let nodeTime = clockPlayer.lastRenderTime,
              let playerTime = clockPlayer.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0
        else {
            // The clock has not rendered yet, so the count-in has not started — not finished.
            return countInSeconds
        }
        let elapsed = Double(playerTime.sampleTime) / playerTime.sampleRate
        return max(0, countInSeconds - elapsed)
    }

    // MARK: - Parameters

    /// Practice speed. Applied as a real-time time-stretch, so pitch is unaffected (spec §22).
    func setSpeed(_ speed: Double) {
        let clamped = Float(max(0.25, min(2.0, speed)))
        timePitchMusic.rate = clamped
        timePitchFlat.rate = clamped
    }

    /// Transposition in semitones, applied as a real-time pitch shift on the pitched bus only
    /// (spec §23). Drums and the click are on the flat bus and stay put.
    func setTranspose(_ semitones: Int) {
        let clamped = max(-12, min(12, semitones))
        timePitchMusic.pitch = Float(clamped) * 100.0    // cents
    }

    func updateTracks(_ states: [TrackPlaybackState]) {
        trackStates = Dictionary(states.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        applyTrackGains()
    }

    private func applyTrackGains() {
        let hasSolo = trackStates.values.contains { $0.isSolo }
        for (trackId, player) in trackPlayers {
            guard let state = trackStates[trackId] else { player.volume = 0; continue }
            let audible = hasSolo ? (state.isSolo && !state.isMuted) : !state.isMuted
            player.volume = (backtrackEnabled && audible) ? state.volume : 0
            player.pan = state.pan
        }
    }

    // MARK: - Teardown

    func shutdown() {
        stopNodes()
        if engine.isRunning { engine.stop() }
        isRunning = false
        isPaused = false
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
