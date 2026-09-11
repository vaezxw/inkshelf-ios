import SwiftUI
import SwiftData

@main
struct InkShelfApp: App {
    var sharedModelContainer: ModelContainer = {
        Self.makeModelContainer()
    }()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(ReaderPrefs.shared)
                .environmentObject(SyncService.shared)
                .tint(InkShelfColors.lamp)
                .preferredColorScheme(.light)
        }
        .modelContainer(sharedModelContainer)
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema([
            BookEntity.self,
            ChapterEntity.self,
            BookmarkEntity.self,
            BookSourceEntity.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Schema changed (e.g. cloud sync fields). Reset store once so launch
            // does not fatalError; Documents TXT files remain intact.
            Self.deletePersistentStore(at: config.url)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("SwiftData container failed after reset: \(error)")
            }
        }
    }

    private static func deletePersistentStore(at url: URL) {
        let fm = FileManager.default
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            try? fm.removeItem(atPath: path)
        }
    }
}
