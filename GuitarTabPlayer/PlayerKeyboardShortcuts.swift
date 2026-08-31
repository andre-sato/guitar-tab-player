import SwiftUI

/// Hardware-keyboard shortcuts for iPad (spec §UX, §41).
///
/// The buttons are invisible but not zero-sized: a fully collapsed button is unreliable as a
/// shortcut host. They are split into two `Group`s so the view builder never sees more than
/// ten children in one block.
struct PlayerKeyboardShortcuts: ViewModifier {
    @Environment(PlaybackEngine.self) private var playback

    func body(content: Content) -> some View {
        content.background {
            VStack(spacing: 0) {
                Group {
                    Button("Play or pause") { playback.togglePlayPause() }
                        .keyboardShortcut(.space, modifiers: [])
                    Button("Previous measure") { playback.skip(measures: -1) }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button("Next measure") { playback.skip(measures: 1) }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Back to start") { playback.seek(toBeat: 0) }
                        .keyboardShortcut(.home, modifiers: [])
                    Button("Toggle metronome") { playback.setMetronome(enabled: !playback.state.metronomeEnabled) }
                        .keyboardShortcut("m", modifiers: [])
                    Button("Toggle count-in") { playback.setCountIn(enabled: !playback.state.countInEnabled) }
                        .keyboardShortcut("c", modifiers: [])
                }
                Group {
                    Button("Toggle backtrack") { playback.setBacktrack(enabled: !playback.state.backtrackEnabled) }
                        .keyboardShortcut("b", modifiers: [])
                    Button("Toggle loop") { playback.setLoopEnabled(!playback.state.loopEnabled) }
                        .keyboardShortcut("l", modifiers: [])
                    Button("Toggle auto-scroll") { playback.setAutoScroll(enabled: !playback.state.autoScrollEnabled) }
                        .keyboardShortcut("a", modifiers: [])
                    Button("Slower") { playback.setSpeed(playback.state.speed - 0.05) }
                        .keyboardShortcut("[", modifiers: [])
                    Button("Faster") { playback.setSpeed(playback.state.speed + 0.05) }
                        .keyboardShortcut("]", modifiers: [])
                    Button("Transpose down") { playback.setTranspose(playback.state.transpose - 1) }
                        .keyboardShortcut(.downArrow, modifiers: [])
                    Button("Transpose up") { playback.setTranspose(playback.state.transpose + 1) }
                        .keyboardShortcut(.upArrow, modifiers: [])
                }
            }
            .frame(width: 1, height: 1)
            .opacity(0.001)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    func playerKeyboardShortcuts() -> some View { modifier(PlayerKeyboardShortcuts()) }
}
