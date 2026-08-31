import Foundation
import SwiftData

/// Everything that touches the SwiftData store: library, favourites, history, preferences,
/// and the per-song practice state (spec §32, §35, §36).
@MainActor
final class LibraryService {

    enum Filter: String, CaseIterable, Identifiable {
        case all, recentlyPlayed, favorites, downloaded, practice

        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .all: return "My Library"
            case .recentlyPlayed: return "Recently Played"
            case .favorites: return "Favorites"
            case .downloaded: return "Downloaded"
            case .practice: return "Practice"
            }
        }
        var symbolName: String {
            switch self {
            case .all: return "music.note.list"
            case .recentlyPlayed: return "clock"
            case .favorites: return "heart"
            case .downloaded: return "arrow.down.circle"
            case .practice: return "metronome"
            }
        }
    }

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Entries

    func entry(providerId: String, tabId: String) -> LibraryEntry? {
        let key = "\(providerId):\(tabId)"
        var descriptor = FetchDescriptor<LibraryEntry>(predicate: #Predicate { $0.id == key })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    @discardableResult
    func addIfNeeded(_ result: TabSearchResult) -> LibraryEntry {
        if let existing = entry(providerId: result.providerId, tabId: result.id) { return existing }
        let entry = LibraryEntry(result: result)
        context.insert(entry)
        save()
        return entry
    }

    func entries(filter: Filter) -> [LibraryEntry] {
        let descriptor: FetchDescriptor<LibraryEntry>
        switch filter {
        case .all:
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.addedAt, order: .reverse)])
        case .recentlyPlayed:
            descriptor = FetchDescriptor(predicate: #Predicate { $0.lastPlayedAt != nil },
                                         sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        case .favorites:
            descriptor = FetchDescriptor(predicate: #Predicate { $0.isFavorite },
                                         sortBy: [SortDescriptor(\.title)])
        case .downloaded:
            descriptor = FetchDescriptor(predicate: #Predicate { $0.isDownloaded },
                                         sortBy: [SortDescriptor(\.title)])
        case .practice:
            descriptor = FetchDescriptor(predicate: #Predicate { $0.lastBeat > 1 },
                                         sortBy: [SortDescriptor(\.lastPlayedAt, order: .reverse)])
        }
        return (try? context.fetch(descriptor)) ?? []
    }

    func toggleFavorite(_ entry: LibraryEntry) {
        entry.isFavorite.toggle()
        save()
    }

    func remove(_ entry: LibraryEntry) {
        context.delete(entry)
        save()
    }

    func markPlayed(_ entry: LibraryEntry) {
        entry.lastPlayedAt = .now
        entry.playCount += 1
        save()
    }

    func store(practice: PracticeSnapshot, for entry: LibraryEntry) {
        entry.apply(practice)
        save()
    }

    // MARK: - Preferences

    func preferences() -> UserPreferences {
        record().value
    }

    func update(preferences: UserPreferences) {
        let record = record()
        record.value = preferences
        save()
    }

    private func record() -> UserPreferencesRecord {
        var descriptor = FetchDescriptor<UserPreferencesRecord>(predicate: #Predicate { $0.key == "default" })
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first { return existing }
        let created = UserPreferencesRecord()
        context.insert(created)
        save()
        return created
    }

    // MARK: - Saving

    func save() {
        guard context.hasChanges else { return }
        do { try context.save() }
        catch { NSLog("GuitarTabPlayer: could not save library - \(error.localizedDescription)") }
    }
}
