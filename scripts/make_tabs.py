import Foundation
import SwiftData

enum SwiftDataContainer {

    static let schema = Schema([LibraryEntry.self, UserPreferencesRecord.self])

    /// On-disk store used by the app.
    static func makeShared() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            NSLog("GuitarTabPlayer: falling back to an in-memory store - \(error.localizedDescription)")
            return makeInMemory()
        }
    }

    /// Used by previews and unit tests.
    static func makeInMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // A container for an in-memory store cannot realistically fail; a crash here is a programmer error.
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
