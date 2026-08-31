import Foundation
import SwiftData

/// Value type used across the app; the SwiftData record below is only its storage.
struct UserPreferences: Codable, Hashable, Sendable {
    var metronomeEnabled: Bool = false
    var metronomeVolume: Float = 0.7
    var metronomeSubdivision: MetronomeSubdivision = .quarter
    var countInEnabled: Bool = true
    var backtrackEnabled: Bool = true
    var autoScrollEnabled: Bool = true
    var chordDisplayEnabled: Bool = true
    var defaultSpeed: Double = 1.0
    var resumeFromLastPosition: Bool = true
    var tabZoom: Double = 1.0

    static let `default` = UserPreferences()
}

@Model
final class UserPreferencesRecord {
    @Attribute(.unique) var key: String
    var metronomeEnabled: Bool
    var metronomeVolume: Double
    var metronomeSubdivisionRaw: String
    var countInEnabled: Bool
    var backtrackEnabled: Bool
    var autoScrollEnabled: Bool
    var chordDisplayEnabled: Bool
    var defaultSpeed: Double
    var resumeFromLastPosition: Bool
    var tabZoom: Double

    init(key: String = "default", preferences: UserPreferences = .default) {
        self.key = key
        self.metronomeEnabled = preferences.metronomeEnabled
        self.metronomeVolume = Double(preferences.metronomeVolume)
        self.metronomeSubdivisionRaw = preferences.metronomeSubdivision.rawValue
        self.countInEnabled = preferences.countInEnabled
        self.backtrackEnabled = preferences.backtrackEnabled
        self.autoScrollEnabled = preferences.autoScrollEnabled
        self.chordDisplayEnabled = preferences.chordDisplayEnabled
        self.defaultSpeed = preferences.defaultSpeed
        self.resumeFromLastPosition = preferences.resumeFromLastPosition
        self.tabZoom = preferences.tabZoom
    }

    var value: UserPreferences {
        get {
            UserPreferences(
                metronomeEnabled: metronomeEnabled,
                metronomeVolume: Float(metronomeVolume),
                metronomeSubdivision: MetronomeSubdivision(rawValue: metronomeSubdivisionRaw) ?? .quarter,
                countInEnabled: countInEnabled,
                backtrackEnabled: backtrackEnabled,
                autoScrollEnabled: autoScrollEnabled,
                chordDisplayEnabled: chordDisplayEnabled,
                defaultSpeed: defaultSpeed,
                resumeFromLastPosition: resumeFromLastPosition,
                tabZoom: tabZoom)
        }
        set {
            metronomeEnabled = newValue.metronomeEnabled
            metronomeVolume = Double(newValue.metronomeVolume)
            metronomeSubdivisionRaw = newValue.metronomeSubdivision.rawValue
            countInEnabled = newValue.countInEnabled
            backtrackEnabled = newValue.backtrackEnabled
            autoScrollEnabled = newValue.autoScrollEnabled
            chordDisplayEnabled = newValue.chordDisplayEnabled
            defaultSpeed = newValue.defaultSpeed
            resumeFromLastPosition = newValue.resumeFromLastPosition
            tabZoom = newValue.tabZoom
        }
    }
}
