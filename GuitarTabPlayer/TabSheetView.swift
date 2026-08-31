import SwiftUI

/// The tablature sheet: chords sit on the same lane as the tab they belong to, the cursor is
/// driven by the audio clock, and tapping anywhere seeks (spec §11, §12, §13).
///
/// Everything is drawn in a single `Canvas`, and only the measures inside the viewport are
/// rendered, so scrolling stays smooth on long songs (spec §39).
struct TabSheetView: View {

    let layout: TabLayout
    let currentBeat: Double
    let isPlaying: Bool
    let autoScroll: Bool
    let showChords: Bool
    let loop: LoopRegion?
    let loopEnabled: Bool
    let metrics: TabMetrics
    let seekGeneration: Int
    let onSeek: (Double) -> Void
    let onUserScrolled: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewportBeat: Double = 0
    @State private var dragAnchorBeat: Double?

    private var palette: TabPalette { TabPalette(colorScheme: colorScheme) }

    private var lineCount: Int { max(1, layout.lineCount) }

    private var staffTop: Double {
        metrics.sectionLaneHeight + (showChords ? metrics.chordLaneHeight : 6) + 6
    }

    private var staffHeight: Double { Double(lineCount - 1) * metrics.stringSpacing }

    private var preferredHeight: Double {
        staffTop + staffHeight + metrics.beatRulerHeight + 26
    }

    var body: some View {
        GeometryReader { proxy in
            let cursorX = proxy.size.width * 0.32
            let offsetX = cursorX - metrics.x(forBeat: viewportBeat)

            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                draw(context: context, size: size, offsetX: offsetX)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if dragAnchorBeat == nil {
                            dragAnchorBeat = viewportBeat
                            onUserScrolled()
                        }
                        let anchor = dragAnchorBeat ?? viewportBeat
                        viewportBeat = clampBeat(anchor - value.translation.width / metrics.pointsPerBeat)
                    }
                    .onEnded { _ in dragAnchorBeat = nil }
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        let beat = metrics.beat(forX: value.location.x - offsetX)
                        onSeek(TabEngine.snapBeat(clampBeat(beat), layout: layout))
                    }
            )
        }
        .frame(height: preferredHeight)
        .onAppear { viewportBeat = currentBeat }
        .onChange(of: currentBeat) { _, newValue in
            guard autoScroll, dragAnchorBeat == nil else { return }
            viewportBeat = newValue
        }
        .onChange(of: seekGeneration) { _, _ in
            viewportBeat = currentBeat
        }
        .accessibilityElement()
        .accessibilityLabel("Tablature")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Swipe horizontally to browse, double tap to play from here.")
    }

    private func clampBeat(_ beat: Double) -> Double {
        min(max(0, beat), max(0, layout.totalBeats))
    }

    private var accessibilitySummary: String {
        let measure = layout.timeSignature.measureIndex(forBeat: currentBeat) + 1
        let chord = TabEngine.chord(in: layout.chords, at: currentBeat)?.symbol(preferFlats: layout.prefersFlats) ?? "no chord"
        return "Measure \(measure), chord \(chord)"
    }

    // MARK: - Drawing

    private func draw(context: GraphicsContext, size: CGSize, offsetX: Double) {
        let visibleStartBeat = max(0, metrics.beat(forX: -offsetX) - 2)
        let visibleEndBeat = metrics.beat(forX: size.width - offsetX) + 2
        let range = visibleStartBeat...max(visibleStartBeat + 0.001, visibleEndBeat)

        context.drawLayer { layer in
            layer.translateBy(x: offsetX, y: 0)
            drawLoopRegion(layer, size: size)
            drawSections(layer, range: range)
            drawMeasures(layer, range: range, size: size)
            drawStaffLines(layer, range: range)
            if showChords { drawChords(layer, range: range) }
            if layout.isDrumLane {
                drawDrumHits(layer, range: range)
            } else {
                drawNotes(layer, range: range)
            }
            drawBeatRuler(layer, range: range)
            drawCursor(layer)
        }

        drawGutter(context, size: size)
    }

    private func y(forLine index: Int) -> Double {
        staffTop + Double(index) * metrics.stringSpacing
    }

    /// Tab draws the highest string on the top line, so the display index is mirrored.
    private func displayLine(forString stringIndex: Int) -> Int {
        max(0, lineCount - 1 - stringIndex)
    }

    private func drawStaffLines(_ context: GraphicsContext, range: ClosedRange<Double>) {
        let startX = metrics.x(forBeat: range.lowerBound)
        let endX = metrics.x(forBeat: range.upperBound)
        for index in 0..<lineCount {
            var path = Path()
            let lineY = y(forLine: index)
            path.move(to: CGPoint(x: startX, y: lineY))
            path.addLine(to: CGPoint(x: endX, y: lineY))
            context.stroke(path, with: .color(palette.staffLine), lineWidth: 1)
        }
    }

    private func drawMeasures(_ context: GraphicsContext, range: ClosedRange<Double>, size: CGSize) {
        let top = y(forLine: 0)
        let bottom = y(forLine: lineCount - 1)
        for measure in layout.measures where measure.endBeat >= range.lowerBound && measure.startBeat <= range.upperBound {
            let x = metrics.x(forBeat: measure.startBeat)
            var path = Path()
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottom))
            context.stroke(path, with: .color(palette.barLine), lineWidth: measure.index % 4 == 0 ? 1.8 : 1)

            var number = context.resolve(Text("\(measure.index + 1)").font(.system(size: 9, design: .rounded)))
            number.shading = .color(palette.secondaryText)
            context.draw(number, at: CGPoint(x: x + 4, y: top - 8), anchor: .leading)
        }

        // Final barline
        if let last = layout.measures.last, last.endBeat <= range.upperBound {
            let x = metrics.x(forBeat: last.endBeat)
            var path = Path()
            path.move(to: CGPoint(x: x, y: top))
            path.addLine(to: CGPoint(x: x, y: bottom))
            context.stroke(path, with: .color(palette.barLine), lineWidth: 2.5)
        }
    }

    private func drawSections(_ context: GraphicsContext, range: ClosedRange<Double>) {
        for section in layout.sections where section.endBeat >= range.lowerBound && section.startBeat <= range.upperBound {
            let x = metrics.x(forBeat: section.startBeat)
            var label = context.resolve(Text(section.name.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded)))
            label.shading = .color(palette.sectionText)
            context.draw(label, at: CGPoint(x: x + 4, y: 8), anchor: .leading)
        }
    }

    private func drawChords(_ context: GraphicsContext, range: ClosedRange<Double>) {
        let preferFlats = layout.prefersFlats
        let chordY = metrics.sectionLaneHeight + metrics.chordLaneHeight * 0.45
        for chord in layout.chords where chord.endBeat >= range.lowerBound && chord.startBeat <= range.upperBound {
            let x = metrics.x(forBeat: chord.startBeat)
            let isActive = chord.startBeat <= currentBeat && currentBeat < chord.endBeat

            var label = context.resolve(Text(chord.symbol(preferFlats: preferFlats))
                .font(.system(size: 15, weight: .bold, design: .rounded)))
            label.shading = .color(isActive ? palette.activeChord : palette.chordText)

            if isActive {
                let labelWidth = Double(label.measure(in: CGSize(width: 200, height: 40)).width)
                let box = CGRect(x: x - 5, y: chordY - 12, width: labelWidth + 10, height: 24)
                context.fill(Path(roundedRect: box, cornerRadius: 6), with: .color(palette.activeChordBackground))
            }
            context.draw(label, at: CGPoint(x: x, y: chordY), anchor: .leading)

            // Tie the chord to the tab lane it belongs to.
            var connector = Path()
            connector.move(to: CGPoint(x: x, y: chordY + 12))
            connector.addLine(to: CGPoint(x: x, y: y(forLine: 0) - 2))
            context.stroke(connector, with: .color(palette.chordConnector), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
        }
    }

    private func drawNotes(_ context: GraphicsContext, range: ClosedRange<Double>) {
        for note in layout.notes where note.beat + note.durationBeats >= range.lowerBound && note.beat <= range.upperBound {
            let x = metrics.x(forBeat: note.beat)
            let lineY = y(forLine: displayLine(forString: note.stringIndex))
            let isActive = note.beat <= currentBeat && currentBeat < note.beat + note.durationBeats

            var text = "\(note.fret)"
            if let marker = note.technique.tabMarker, note.technique != .none, note.technique != .slide, note.technique != .bend {
                text += marker
            }
            if let annotation = note.annotation { text += annotation }

            var resolved = context.resolve(Text(text)
                .font(.system(size: 13, weight: isActive ? .bold : .medium, design: .monospaced)))
            resolved.shading = .color(isActive ? palette.activeNote : palette.noteText)
            let width = Double(resolved.measure(in: CGSize(width: 120, height: 30)).width)

            // Knock out the staff line behind the digits so they stay legible.
            let plate = CGRect(x: x - 2, y: lineY - 8, width: width + 4, height: 16)
            context.fill(Path(plate), with: .color(palette.background))

            if isActive {
                context.fill(Path(roundedRect: plate.insetBy(dx: -2, dy: -1), cornerRadius: 4),
                             with: .color(palette.activeNoteBackground))
            }
            context.draw(resolved, at: CGPoint(x: x, y: lineY), anchor: .leading)
        }
    }

    private func drawDrumHits(_ context: GraphicsContext, range: ClosedRange<Double>) {
        for hit in layout.drumHits where range.contains(hit.beat) {
            let x = metrics.x(forBeat: hit.beat)
            let lineY = y(forLine: min(hit.lane, lineCount - 1))
            let isActive = abs(hit.beat - currentBeat) < 0.12

            var resolved = context.resolve(Text(hit.symbol)
                .font(.system(size: 13, weight: hit.accent ? .bold : .regular, design: .monospaced)))
            resolved.shading = .color(isActive ? palette.activeNote : palette.noteText)
            let width = Double(resolved.measure(in: CGSize(width: 60, height: 30)).width)
            context.fill(Path(CGRect(x: x - 2, y: lineY - 8, width: width + 4, height: 16)), with: .color(palette.background))
            context.draw(resolved, at: CGPoint(x: x, y: lineY), anchor: .leading)
        }
    }

    private func drawBeatRuler(_ context: GraphicsContext, range: ClosedRange<Double>) {
        let rulerY = y(forLine: lineCount - 1) + metrics.beatRulerHeight
        let start = floor(range.lowerBound * 2) / 2
        var beat = max(0, start)
        while beat <= min(range.upperBound, layout.totalBeats) {
            let x = metrics.x(forBeat: beat)
            let isWholeBeat = abs(beat.rounded() - beat) < 1e-6
            let beatInBar = layout.timeSignature.beatWithinMeasure(forBeat: beat)
            let text = isWholeBeat ? "\(Int(beatInBar) + 1)" : "&"
            var resolved = context.resolve(Text(text).font(.system(size: 9, design: .rounded)))
            resolved.shading = .color(isWholeBeat ? palette.secondaryText : palette.tertiaryText)
            context.draw(resolved, at: CGPoint(x: x, y: rulerY), anchor: .center)
            beat += 0.5
        }
    }

    private func drawLoopRegion(_ context: GraphicsContext, size: CGSize) {
        guard loopEnabled, let loop, loop.isValid else { return }
        let rect = CGRect(x: metrics.x(forBeat: loop.startBeat),
                          y: 0,
                          width: (loop.endBeat - loop.startBeat) * metrics.pointsPerBeat,
                          height: size.height)
        context.fill(Path(rect), with: .color(palette.loopFill))
    }

    private func drawCursor(_ context: GraphicsContext) {
        let x = metrics.x(forBeat: currentBeat)
        var path = Path()
        path.move(to: CGPoint(x: x, y: staffTop - (showChords ? metrics.chordLaneHeight : 4)))
        path.addLine(to: CGPoint(x: x, y: y(forLine: lineCount - 1) + 8))
        context.stroke(path, with: .color(palette.cursor), lineWidth: 2)

        let head = Path(ellipseIn: CGRect(x: x - 4, y: staffTop - (showChords ? metrics.chordLaneHeight : 4) - 4, width: 8, height: 8))
        context.fill(head, with: .color(palette.cursor))
    }

    /// String labels pinned to the left edge, outside the scrolling content.
    private func drawGutter(_ context: GraphicsContext, size: CGSize) {
        let gutterRect = CGRect(x: 0, y: staffTop - 12, width: metrics.leadingGutter - 8, height: staffHeight + 24)
        context.fill(Path(gutterRect), with: .color(palette.background))

        let labels: [String] = layout.isDrumLane ? DrumPiece.laneLabels : layout.tuning.lineLabels
        for (index, label) in labels.prefix(lineCount).enumerated() {
            var resolved = context.resolve(Text(label).font(.system(size: 11, weight: .semibold, design: .monospaced)))
            resolved.shading = .color(palette.secondaryText)
            context.draw(resolved, at: CGPoint(x: 6, y: y(forLine: index)), anchor: .leading)
        }
    }
}

/// Colours for the sheet, tuned for both appearances (spec §40 high contrast).
struct TabPalette {
    let colorScheme: ColorScheme

    var isDark: Bool { colorScheme == .dark }

    var background: Color { isDark ? Color(white: 0.09) : Color(white: 0.99) }
    var staffLine: Color { isDark ? Color(white: 0.32) : Color(white: 0.78) }
    var barLine: Color { isDark ? Color(white: 0.45) : Color(white: 0.62) }
    var noteText: Color { isDark ? Color(white: 0.92) : Color(white: 0.12) }
    var activeNote: Color { .white }
    var activeNoteBackground: Color { .accentColor }
    var chordText: Color { isDark ? Color(white: 0.75) : Color(white: 0.28) }
    var activeChord: Color { .accentColor }
    var activeChordBackground: Color { Color.accentColor.opacity(0.14) }
    var chordConnector: Color { isDark ? Color(white: 0.4) : Color(white: 0.72) }
    var sectionText: Color { .secondary }
    var secondaryText: Color { .secondary }
    var tertiaryText: Color { isDark ? Color(white: 0.45) : Color(white: 0.65) }
    var cursor: Color { .accentColor }
    var loopFill: Color { Color.accentColor.opacity(0.10) }
}
