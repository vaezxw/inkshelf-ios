import SwiftUI
import SwiftData

@main
struct InkShelfApp: App {
    var sharedModelContainer: ModelContainer = {
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
            fatalError("SwiftData container failed: \(error)")
        }
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
}
